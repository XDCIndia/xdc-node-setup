#!/usr/bin/env bash

# Source utility functions
source "$(dirname "$0")/lib/utils.sh" || { echo "Failed to load utils"; exit 1; }
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }

#==============================================================================
# XDC Node Version Check and Auto-Update Script
# Implements Section 5 of XDC-NODE-STANDARDS.md
# Features: ETag caching, multi-repo support, rolling restart
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Source libraries
# shellcheck source=/dev/null
source "${LIB_DIR}/error-handler.sh" 2>/dev/null || {
    echo "Error: error-handler.sh library not found at ${LIB_DIR}/error-handler.sh"
    exit 1
}
# shellcheck source=/dev/null
source "${LIB_DIR}/notify.sh" 2>/dev/null || {
    echo "Warning: Notification library not found at ${LIB_DIR}/notify.sh"
}

VERSIONS_FILE="/opt/xdc-node/configs/versions.json"
REPORT_DIR="/opt/xdc-node/reports"
LOG_FILE="/var/log/xdc-version-check.log"
LOCK_FILE="/var/run/xdc-version-check.lock"
ETAG_CACHE_DIR="/tmp/xdc-version-cache"

# Ensure directories exist
mkdir -p "$REPORT_DIR" "$ETAG_CACHE_DIR"

# Telegram settings (from env or versions.json - legacy fallback)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Stats
UPDATES_AVAILABLE=0
UPDATES_APPLIED=0
CHECKS_PERFORMED=0

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


info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >> "$LOG_FILE" 2>/dev/null || true
}

#==============================================================================
# Lock Management (using lib/error-handler.sh functions)
#==============================================================================
# acquire_lock() and release_lock() are now sourced from lib/error-handler.sh

#==============================================================================
# GitHub API with ETag Caching (for rate limit avoidance)
#==============================================================================
get_latest_release() {
    local repo=$1
    local api_url="https://api.github.com/repos/$repo/releases/latest"
    local etag_file="$ETAG_CACHE_DIR/$(echo "$repo" | tr '/' '_').etag"
    local cache_file="$ETAG_CACHE_DIR/$(echo "$repo" | tr '/' '_').json"
    
    local curl_opts=(-sL -H "Accept: application/vnd.github.v3+json")
    
    # Use ETag if available for caching
    if [[ -f "$etag_file" ]]; then
        local etag
        etag=$(cat "$etag_file")
        curl_opts+=(-H "If-None-Match: $etag")
        info "Using ETag cache for $repo"
    fi
    
    local response
    local http_code
    response=$(curl "${curl_opts[@]}" -w "\n%{http_code}" "$api_url" 2>/dev/null || echo '{}\n000')
    http_code=$(echo "$response" | tail -1)
    response=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" == "304" && -f "$cache_file" ]]; then
        # Not modified - use cached response
        info "GitHub returned 304 Not Modified - using cache"
        response=$(cat "$cache_file")
    elif [[ "$http_code" == "200" ]]; then
        # New response - cache it
        echo "$response" > "$cache_file"
        # Save ETag
        echo "$response" | grep -i "^etag:" | head -1 | sed 's/etag: //i' > "$etag_file" || \
            echo "W/\\\"$(date +%s)\\\"" > "$etag_file"
        info "Cached new response for $repo (HTTP 200)"
    elif [[ "$http_code" == "403" ]]; then
        # Rate limited
        warn "GitHub API rate limit hit (403) - using cache if available"
        if [[ -f "$cache_file" ]]; then
            response=$(cat "$cache_file")
        else
            echo '{}'
            return
        fi
    else
        info "HTTP $http_code from GitHub API"
    fi
    
    echo "$response"
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
    # Compare semantic versions
    local v1=$1
    local v2=$2
    v1=$(echo "$v1" | sed 's/^[vV]//')
    v2=$(echo "$v2" | sed 's/^[vV]//')
    
    # Use sort -V for version comparison
    local higher
    higher=$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | tail -n 1)
    
    [[ "$higher" == "$v1" && "$v1" != "$v2" ]]
}

normalize_version() {
    echo "$1" | sed 's/^[vV]//'
}

#==============================================================================
# Rolling Restart Functions
#==============================================================================
test_node_health() {
    local rpc_url=$1
    local max_attempts=${2:-30}
    local attempt=0
    
    log "Testing node health at $rpc_url..."
    
    while [[ $attempt -lt $max_attempts ]]; do
        local response
        response=$(curl -s -m 5 -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            "$rpc_url" 2>/dev/null || echo '{}')
        
        local result
        result=$(echo "$response" | jq -r '.result // empty')
        
        if [[ -n "$result" && "$result" != "null" ]]; then
            log "✓ Node is healthy (blockNumber: $result)"
            return 0
        fi
        
        attempt=$((attempt + 1))
        sleep 2
    done
    
    error "✗ Node health check failed after $max_attempts attempts"
    return 1
}

rolling_restart_test_first() {
    local client_name=$1
    local nodes=$2
    local update_cmd=$3
    
    log "Performing rolling restart with test-first strategy..."
    
    # Find test node
    local test_node=""
    local prod_nodes=()
    
    while IFS= read -r node; do
        [[ -z "$node" ]] && continue
        local role
        role=$(echo "$node" | jq -r '.role // "production"')
        local host
        host=$(echo "$node" | jq -r '.host // empty')
        
        if [[ "$role" == "test" && -z "$test_node" ]]; then
            test_node="$host"
        else
            prod_nodes+=("$host")
        fi
    done < <(echo "$nodes" | jq -c '.[]' 2>/dev/null || echo "[]")
    
    if [[ -z "$test_node" && ${#prod_nodes[@]} -gt 0 ]]; then
        # No test node, use first prod node as test
        test_node="${prod_nodes[0]}"
        prod_nodes=("${prod_nodes[@]:1}")
        warn "No test node found, using $test_node for initial test"
    fi
    
    # Deploy to test node first
    if [[ -n "$test_node" ]]; then
        log "Step 1: Deploying to test node $test_node..."
        if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$test_node" "$update_cmd" 2>> "$LOG_FILE"; then
            log "✓ Test node updated successfully"
            
            # Wait and verify
            sleep 10
            if test_node_health "http://$test_node:8545"; then
                log "✓ Test node health verified"
            else
                error "✗ Test node failed health check - aborting production rollout"
                return 1
            fi
        else
            error "✗ Test node update failed - aborting production rollout"
            return 1
        fi
    fi
    
    # Deploy to production nodes (with delay between each)
    for node in "${prod_nodes[@]}"; do
        log "Step 2: Deploying to production node $node..."
        if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$node" "$update_cmd" 2>> "$LOG_FILE"; then
            log "✓ Production node $node updated"
            # Delay between nodes
            sleep 30
        else
            warn "⚠ Production node $node update failed"
        fi
    done
    
    log "✓ Rolling restart complete"
    return 0
}

#==============================================================================
# Update Functions
#==============================================================================
update_docker_image() {
    local image=$1
    local version=$2
    local container_name=${3:-xdc-node}
    
    log "Pulling Docker image: $image:$version"
    
    cd /opt/xdc-node/docker || exit 1
    
    # Backup current compose file
    cp docker-compose.yml "docker-compose.yml.backup.$(date +%Y%m%d)"
    
    # Pull new image
    if docker pull "$image:$version" 2>> "$LOG_FILE"; then
        log "✓ Docker image pulled successfully"
        
        # Update docker-compose.yml
        sed -i "s|image: $image:.*|image: $image:$version|" docker-compose.yml
        
        # Rolling restart
        log "Performing rolling restart..."
        docker compose up -d --no-deps "$container_name" 2>> "$LOG_FILE"
        
        # Wait for health check
        sleep 30
        
        # Verify node is running
        if docker ps | grep -q "$container_name"; then
            log "✓ Container restarted successfully"
            
            # Test RPC
            for i in {1..10}; do
                if curl -s -m 5 http://localhost:8545 -X POST \
                    -H "Content-Type: application/json" \
                    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | grep -q "result"; then
                    log "✓ RPC responding after restart"
                    return 0
                fi
                sleep 3
            done
            
            warn "RPC not responding after restart"
            return 1
        else
            error "✗ Container failed to start after update"
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
    local build_type=${4:-local}  # local or remote
    
    log "Building $binary $version from source..."
    
    if [[ "$build_type" == "local" ]]; then
        local build_dir="/opt/xdc-node/builds/$binary-$version"
        mkdir -p "$build_dir"
        
        # Clone or update repository
        if [[ -d "$build_dir/.git" ]]; then
            cd "$build_dir"
            git fetch origin 2>> "$LOG_FILE"
            git checkout "$version" 2>> "$LOG_FILE"
        else
            rm -rf "$build_dir"
            git clone --branch "$version" --depth 1 "https://github.com/$repo.git" "$build_dir" 2>> "$LOG_FILE"
            cd "$build_dir"
        fi
        
        # Build
        log "Running make..."
        if make 2>> "$LOG_FILE"; then
            log "✓ Build successful"
            
            # Stop current node
            systemctl stop xdc-node 2>/dev/null || \
                docker compose -f /opt/xdc-node/docker/docker-compose.yml stop xdc-node 2>/dev/null || true
            
            # Backup current binary
            if [[ -f "/usr/local/bin/$binary" ]]; then
                cp "/usr/local/bin/$binary" "/usr/local/bin/$binary.backup.$(date +%Y%m%d)"
                log "Backed up current binary"
            fi
            
            # Install new binary
            cp "./build/bin/$binary" "/usr/local/bin/$binary"
            chmod +x "/usr/local/bin/$binary"
            log "Installed new binary to /usr/local/bin/$binary"
            
            # Start node
            systemctl start xdc-node 2>/dev/null || \
                docker compose -f /opt/xdc-node/docker/docker-compose.yml start xdc-node 2>/dev/null || true
            
            log "✓ Update complete"
            return 0
        else
            error "✗ Build failed - check $LOG_FILE for details"
            return 1
        fi
    fi
}

#==============================================================================
# Notification Functions
#==============================================================================
send_notification() {
    local level="$1"
    local title="$2"
    local message="$3"
    
    # Use new notification system if available
    if [[ "$(type -t notify)" == "function" ]]; then
        notify "$level" "$title" "$message" "version_check"
    else
        # Fallback to legacy Telegram
        send_telegram "$message"
    fi
}

send_alert() {
    local title="$1"
    local message="$2"
    
    # Use new notification system if available
    if [[ "$(type -t notify_alert)" == "function" ]]; then
        notify_alert "critical" "$title" "$message" "version_update_failed"
    else
        # Fallback to legacy Telegram
        send_telegram "$message"
    fi
}

# Legacy Telegram notification (fallback)
send_telegram() {
    local message=$1
    
    # Load from versions.json if not set
    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        if [[ -f "$VERSIONS_FILE" ]]; then
            TELEGRAM_BOT_TOKEN=$(jq -r '.notifications.telegram.botToken // empty' "$VERSIONS_FILE")
            TELEGRAM_CHAT_ID=$(jq -r '.notifications.telegram.chatId // empty' "$VERSIONS_FILE")
        fi
    fi
    
    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        info "Telegram not configured, skipping notification"
        return 0
    fi
    
    local api_url="https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"
    
    # Escape special characters for JSON
    message=$(echo "$message" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\":\"$TELEGRAM_CHAT_ID\",\"text\":\"$message\",\"parse_mode\":\"Markdown\",\"disable_web_page_preview\":true}" \
        "$api_url" > /dev/null 2>&1 || warn "Failed to send Telegram notification"
}

#==============================================================================
# Update versions.json
#==============================================================================
update_versions_json() {
    local client_name=$1
    local latest_version=$2
    local timestamp
    timestamp=$(date -Iseconds)
    
    # Update current and latest versions, plus lastChecked
    jq --arg client "$client_name" \
       --arg latest "$latest_version" \
       --arg time "$timestamp" \
       '.clients[$client].current = $latest | .clients[$client].latest = $latest | .lastChecked = $time' \
       "$VERSIONS_FILE" > "${VERSIONS_FILE}.tmp" && mv "${VERSIONS_FILE}.tmp" "$VERSIONS_FILE"
    
    log "✓ Updated versions.json: $client_name -> $latest_version"
}

#==============================================================================
# Version Check for Single Client
#==============================================================================
check_client() {
    local client_name=$1
    local client_config=$2
    
    ((CHECKS_PERFORMED++)) || true
    
    local repo
    local current
    local auto_update
    local binary
    local image
    local nodes
    
    repo=$(echo "$client_config" | jq -r '.repo // empty')
    current=$(echo "$client_config" | jq -r '.current // empty')
    auto_update=$(echo "$client_config" | jq -r '.autoUpdate // false')
    binary=$(echo "$client_config" | jq -r '.binary // empty')
    image=$(echo "$client_config" | jq -r '.image // empty')
    nodes=$(echo "$client_config" | jq -r '.nodes // empty')
    
    if [[ -z "$repo" || -z "$current" ]]; then
        warn "Incomplete configuration for $client_name (repo: $repo, current: $current)"
        return 1
    fi
    
    log "========================================"
    log "Checking $client_name"
    log "  Repository: $repo"
    log "  Current: $current"
    log "  Auto-update: $auto_update"
    log "========================================"
    
    # Get latest release from GitHub (with ETag caching)
    local latest_response
    latest_response=$(get_latest_release "$repo")
    
    local latest
    latest=$(echo "$latest_response" | jq -r '.tag_name // empty')
    local html_url
    html_url=$(echo "$latest_response" | jq -r '.html_url // empty')
    
    if [[ -z "$latest" || "$latest" == "null" ]]; then
        warn "Could not fetch latest version for $client_name"
        return 1
    fi
    
    # Update latest in versions.json (always do this)
    jq --arg client "$client_name" --arg latest "$latest" \
       '.clients[$client].latest = $latest' \
       "$VERSIONS_FILE" > "${VERSIONS_FILE}.tmp" && mv "${VERSIONS_FILE}.tmp" "$VERSIONS_FILE"
    
    log "Latest version: $latest"
    
    # Normalize versions for comparison
    local current_norm
    local latest_norm
    current_norm=$(normalize_version "$current")
    latest_norm=$(normalize_version "$latest")
    
    # Check if update is needed
    if version_gt "$latest_norm" "$current_norm"; then
        ((UPDATES_AVAILABLE++)) || true
        log "📦 Update available: $current → $latest"
        
        local release_notes
        release_notes=$(echo "$latest_response" | jq -r '.body // "No release notes available"' | head -c 2000)
        
        if [[ "$auto_update" == "true" ]]; then
            log "🔄 Auto-update enabled, proceeding with update..."
            
            local update_success=false
            
            # Determine update method
            if [[ -n "$binary" && -z "$image" ]]; then
                # Build from source
                if [[ -n "$nodes" && $(echo "$nodes" | jq 'length') -gt 0 ]]; then
                    # Rolling restart across nodes
                    local update_cmd="cd /opt/xdc-node && git pull && make && systemctl restart xdc-node"
                    if rolling_restart_test_first "$client_name" "$nodes" "$update_cmd"; then
                        update_success=true
                    fi
                else
                    # Single node build
                    if build_from_source "$repo" "$latest" "$binary" "local"; then
                        update_success=true
                    fi
                fi
            elif [[ -n "$image" ]]; then
                # Docker-based update
                if [[ -n "$nodes" && $(echo "$nodes" | jq 'length') -gt 0 ]]; then
                    # Rolling restart across nodes
                    local update_cmd="cd /opt/xdc-node/docker && docker pull $image:$latest && sed -i 's|image: $image:.*|image: $image:$latest|' docker-compose.yml && docker compose up -d"
                    if rolling_restart_test_first "$client_name" "$nodes" "$update_cmd"; then
                        update_success=true
                    fi
                else
                    # Single node Docker update
                    if update_docker_image "$image" "$latest"; then
                        update_success=true
                    fi
                fi
            else
                warn "No update method configured (binary or image required)"
            fi
            
            if [[ "$update_success" == true ]]; then
                ((UPDATES_APPLIED++)) || true
                update_versions_json "$client_name" "$latest"
                
                # Send success notification
                send_notification "info" "✅ $client_name Auto-Updated" \
                    "Version: \`$current\` → \`$latest\`\nServer: \`$(hostname)\`\nTime: $(date '+%Y-%m-%d %H:%M:%S')\n\nAuto-update completed successfully."
                
                return 0
            else
                # Send failure notification
                send_alert "❌ $client_name Update Failed" \
                    "Version: \`$current\` → \`$latest\`\nServer: \`$(hostname)\`\nTime: $(date '+%Y-%m-%d %H:%M:%S')\n\nUpdate failed. Check logs: $LOG_FILE"
                return 1
            fi
        else
            log "📧 Auto-update disabled, sending notification..."
            
            # Send notification about available update
            send_notification "info" "📦 $client_name Update Available" \
                "Version: \`$current\` → \`$latest\`\nServer: \`$(hostname)\`\nTime: $(date '+%Y-%m-%d %H:%M:%S')\n\nAuto-update is disabled. Manual update required.\n\n[View Release]($html_url)"
        fi
    else
        log "✓ $client_name is up to date ($current)"
    fi
    
    return 0
}

#==============================================================================
# Generate Report
#==============================================================================
generate_report() {
    local report_file="$REPORT_DIR/version-check-$(date +%Y%m%d-%H%M%S).json"
    local timestamp
    timestamp=$(date -Iseconds)
    
    jq --arg time "$timestamp" \
       --argjson available "$UPDATES_AVAILABLE" \
       --argjson applied "$UPDATES_APPLIED" \
       --argjson checks "$CHECKS_PERFORMED" \
       '. | {
           timestamp: $time,
           summary: {
               checksPerformed: $checks,
               updatesAvailable: $available,
               updatesApplied: $applied
           },
           clients: .clients
       }' \
       "$VERSIONS_FILE" > "$report_file"
    
    log "Report saved to: $report_file"
}

#==============================================================================
# Main
#==============================================================================
main() {
    log "========================================"
    log "XDC Node Version Check Starting"
    log "========================================"
    log "Versions file: $VERSIONS_FILE"
    log "ETag cache: $ETAG_CACHE_DIR"
    log "Log file: $LOG_FILE"
    
    acquire_lock "$LOCK_FILE"
    trap release_lock EXIT
    
    # Check if versions.json exists
    if [[ ! -f "$VERSIONS_FILE" ]]; then
        error "Versions file not found: $VERSIONS_FILE"
        exit 1
    fi
    
    # Update lastChecked timestamp
    local timestamp
    timestamp=$(date -Iseconds)
    jq --arg time "$timestamp" '.lastChecked = $time' "$VERSIONS_FILE" > "${VERSIONS_FILE}.tmp" && mv "${VERSIONS_FILE}.tmp" "$VERSIONS_FILE"
    
    # Get list of clients to check
    local clients
    clients=$(jq -r '.clients | keys[]' "$VERSIONS_FILE")
    
    if [[ -z "$clients" ]]; then
        warn "No clients configured in versions.json"
        exit 0
    fi
    
    log "Found clients: $(echo "$clients" | tr '\n' ' ')"
    
    # Process each client
    for client in $clients; do
        local config
        config=$(jq -r ".clients[\"$client\"]" "$VERSIONS_FILE")
        check_client "$client" "$config"
    done
    
    # Generate report
    generate_report
    
    log ""
    log "========================================"
    log "Version Check Complete"
    log "========================================"
    log "Checks performed: $CHECKS_PERFORMED"
    log "Updates available: $UPDATES_AVAILABLE"
    log "Updates applied: $UPDATES_APPLIED"
    
    release_lock
    
    # Exit with appropriate code
    if [[ $UPDATES_AVAILABLE -gt 0 && $UPDATES_APPLIED -eq 0 ]]; then
        # Updates available but not applied (waiting for manual action)
        exit 10
    elif [[ $UPDATES_APPLIED -gt 0 ]]; then
        # Updates were applied
        exit 0
    else
        # All up to date
        exit 0
    fi
}

main "$@"
