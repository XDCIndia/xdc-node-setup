#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDC Node Version Check and Auto-Update Script
#==============================================================================

VERSIONS_FILE="/opt/xdc-node/configs/versions.json"
REPORT_DIR="/opt/xdc-node/reports"
LOG_FILE="/var/log/xdc-version-check.log"
LOCK_FILE="/var/run/xdc-version-check.lock"

# Telegram settings (from env)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

#==============================================================================
# Logging
#==============================================================================
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE" 2>/dev/null || true
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE" 2>/dev/null || true
}

#==============================================================================
# Lock Management
#==============================================================================
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if kill -0 "$pid" 2>/dev/null; then
            warn "Another version check is running (PID: $pid)"
            exit 0
        fi
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE"
}

#==============================================================================
# GitHub API
#==============================================================================
get_latest_release() {
    local repo=$1
    local api_url="https://api.github.com/repos/$repo/releases/latest"
    
    curl -sL -H "Accept: application/vnd.github.v3+json" \
         "${api_url}" 2>/dev/null || echo '{}'
}

get_release_notes() {
    local repo=$1
    local version=$2
    local api_url="https://api.github.com/repos/$repo/releases/tags/$version"
    
    curl -sL -H "Accept: application/vnd.github.v3+json" \
         "${api_url}" 2>/dev/null | jq -r '.body // "No release notes available"' || echo "No release notes available"
}

#==============================================================================
# Version Comparison
#==============================================================================
version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

normalize_version() {
    echo "$1" | sed 's/^[vV]//'
}

#==============================================================================
# Update Functions
#==============================================================================
update_docker_image() {
    local image=$1
    local version=$2
    
    log "Pulling Docker image: $image:$version"
    
    cd /opt/xdc-node/docker || exit 1
    
    # Pull new image
    if docker pull "$image:$version"; then
        log "✓ Docker image pulled successfully"
        
        # Update docker-compose.yml
        sed -i "s|image: $image:.*|image: $image:$version|" docker-compose.yml
        
        # Rolling restart
        log "Performing rolling restart..."
        docker compose up -d --no-deps xdc-node
        
        # Wait for health check
        sleep 30
        
        # Verify node is running
        if docker ps | grep -q "xdc-node"; then
            log "✓ Node restarted successfully"
            return 0
        else
            error "✗ Node failed to start after update"
            return 1
        fi
    else
        error "✗ Failed to pull Docker image"
        return 1
    fi
}

build_from_source() {
    local repo=$1
    local version=$2
    local binary=$3
    
    log "Building $binary $version from source..."
    
    local build_dir="/opt/xdc-node/builds/$binary-$version"
    mkdir -p "$build_dir"
    
    # Clone repository
    if [[ -d "$build_dir/.git" ]]; then
        cd "$build_dir"
        git fetch origin
        git checkout "$version"
    else
        git clone --branch "$version" --depth 1 "https://github.com/$repo.git" "$build_dir"
        cd "$build_dir"
    fi
    
    # Build
    if make; then
        log "✓ Build successful"
        
        # Stop current node
        systemctl stop xdc-node || docker compose -f /opt/xdc-node/docker/docker-compose.yml stop xdc-node
        
        # Backup current binary
        if [[ -f "/usr/local/bin/$binary" ]]; then
            cp "/usr/local/bin/$binary" "/usr/local/bin/$binary.backup.$(date +%Y%m%d)"
        fi
        
        # Install new binary
        cp "./build/bin/$binary" "/usr/local/bin/$binary"
        chmod +x "/usr/local/bin/$binary"
        
        # Start node
        systemctl start xdc-node || docker compose -f /opt/xdc-node/docker/docker-compose.yml start xdc-node
        
        log "✓ Update complete"
        return 0
    else
        error "✗ Build failed"
        return 1
    fi
}

#==============================================================================
# Notification
#==============================================================================
send_telegram() {
    local message=$1
    
    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        return 0
    fi
    
    local api_url="https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\":\"$TELEGRAM_CHAT_ID\",\"text\":\"$message\",\"parse_mode\":\"Markdown\",\"disable_web_page_preview\":true}" \
        "$api_url" > /dev/null 2>& || warn "Failed to send Telegram notification"
}

#==============================================================================
# Version Check for Single Client
#==============================================================================
check_client() {
    local client_name=$1
    local client_config=$2
    
    local repo
    local current
    local auto_update
    local binary
    
    repo=$(echo "$client_config" | jq -r '.repo')
    current=$(echo "$client_config" | jq -r '.current')
    auto_update=$(echo "$client_config" | jq -r '.autoUpdate')
    binary=$(echo "$client_config" | jq -r '.binary // empty')
    
    log "Checking $client_name (current: $current)..."
    
    # Get latest release from GitHub
    local latest_response
    latest_response=$(get_latest_release "$repo")
    local latest
    latest=$(echo "$latest_response" | jq -r '.tag_name // empty')
    
    if [[ -z "$latest" || "$latest" == "null" ]]; then
        warn "Could not fetch latest version for $client_name"
        return 1
    fi
    
    log "Latest version: $latest"
    
    # Normalize versions for comparison
    local current_norm
    local latest_norm
    current_norm=$(normalize_version "$current")
    latest_norm=$(normalize_version "$latest")
    
    # Check if update is needed
    if version_gt "$latest_norm" "$current_norm"; then
        log "Update available: $current → $latest"
        
        local release_notes
        release_notes=$(get_release_notes "$repo" "$latest")
        
        if [[ "$auto_update" == "true" ]]; then
            log "Auto-update enabled, proceeding with update..."
            
            # Determine update method
            if [[ -n "$binary" ]]; then
                # Build from source
                if build_from_source "$repo" "$latest" "$binary"; then
                    # Update versions.json
                    jq --arg client "$client_name" --arg latest "$latest" \
                       '.clients[$client].current = $latest | .clients[$client].latest = $latest' \
                       "$VERSIONS_FILE" > "${VERSIONS_FILE}.tmp" && mv "${VERSIONS_FILE}.tmp" "$VERSIONS_FILE"
                    
                    # Send success notification
                    send_telegram "✅ *$client_name Updated*\n\nVersion: \`$current\` → \`$latest\`\nServer: \`$(hostname)\`\n\nAuto-update completed successfully."
                    
                    return 0
                else
                    # Send failure notification
                    send_telegram "❌ *$client_name Update Failed*\n\nVersion: \`$current\` → \`$latest\`\nServer: \`$(hostname)\`\n\nBuild failed. Manual intervention required."
                    return 1
                fi
            else
                # Docker-based update
                local image
                image=$(echo "$client_config" | jq -r '.image // "xinfinorg/xdposchain"')
                
                if update_docker_image "$image" "$latest"; then
                    # Update versions.json
                    jq --arg client "$client_name" --arg latest "$latest" \
                       '.clients[$client].current = $latest | .clients[$client].latest = $latest' \
                       "$VERSIONS_FILE" > "${VERSIONS_FILE}.tmp" && mv "${VERSIONS_FILE}.tmp" "$VERSIONS_FILE"
                    
                    # Send success notification
                    send_telegram "✅ *$client_name Updated*\n\nVersion: \`$current\` → \`$latest\`\nServer: \`$(hostname)\`\n\nAuto-update completed successfully."
                    
                    return 0
                else
                    # Send failure notification
                    send_telegram "❌ *$client_name Update Failed*\n\nVersion: \`$current\` → \`$latest\`\nServer: \`$(hostname)\`\n\nDocker update failed. Manual intervention required."
                    return 1
                fi
            fi
        else
            log "Auto-update disabled, sending notification..."
            
            # Send notification about available update
            local notes_truncated
            notes_truncated=$(echo "$release_notes" | head -c 1000)
            
            send_telegram "📦 *$client_name Update Available*\n\nVersion: \`$current\` → \`$latest\`\nServer: \`$(hostname)\`\n\n*Release Notes:*\n\`\`\`\n$notes_truncated\n\`\`\`\n\n[View Release](https://github.com/$repo/releases/tag/$latest)"
        fi
    else
        log "✓ $client_name is up to date ($current)"
    fi
    
    return 0
}

#==============================================================================
# Main
#==============================================================================
main() {
    log "Starting version check..."
    
    acquire_lock
    trap release_lock EXIT
    
    # Check if versions.json exists
    if [[ ! -f "$VERSIONS_FILE" ]]; then
        error "Versions file not found: $VERSIONS_FILE"
        exit 1
    fi
    
    # Update lastChecked timestamp
    jq --arg time "$(date -Iseconds)" '.lastChecked = $time' "$VERSIONS_FILE" > "${VERSIONS_FILE}.tmp" && mv "${VERSIONS_FILE}.tmp" "$VERSIONS_FILE"
    
    # Get list of clients to check
    local clients
    clients=$(jq -r '.clients | keys[]' "$VERSIONS_FILE")
    
    local updates_available=0
    local updates_applied=0
    
    for client in $clients; do
        local config
        config=$(jq -r ".clients[\"$client\"]" "$VERSIONS_FILE")
        
        if check_client "$client" "$config"; then
            local current
            local latest
            current=$(echo "$config" | jq -r '.current')
            latest=$(jq -r ".clients[\"$client\"].latest" "$VERSIONS_FILE")
            
            if [[ "$latest" != "null" && "$latest" != "$current" ]]; then
                ((updates_applied++)) || true
            fi
        fi
    done
    
    # Generate report
    mkdir -p "$REPORT_DIR"
    local report_file="$REPORT_DIR/version-check-$(date +%Y%m%d-%H%M%S).json"
    
    jq --arg time "$(date -Iseconds)" \
       --argjson applied "$updates_applied" \
       '. | {timestamp: $time, updatesApplied: $applied, clients: .clients}' \
       "$VERSIONS_FILE" > "$report_file"
    
    log ""
    log "=================================="
    log "Version Check Complete"
    log "=================================="
    log "Updates applied: $updates_applied"
    log "Report saved to: $report_file"
    
    release_lock
}

main "$@"
