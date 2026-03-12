#!/usr/bin/env bash
#==============================================================================
# XDC Node Auto-Update System
# Automated updates with rollback capability
#==============================================================================

set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }
source "${SCRIPT_DIR}/lib/logging.sh" 2>/dev/null || { echo "ERROR: Cannot source logging.sh"; exit 1; }

# Set logging component
export LOG_COMPONENT="auto-update"

# Configuration
readonly XDC_NODE_HOME="${XDC_NODE_HOME:-/opt/xdc-node}"
readonly UPDATE_LOG="${UPDATE_LOG:-/var/log/xdc-node-updates.log}"
readonly BACKUP_DIR="${XDC_NODE_HOME}/backups"
readonly HEALTH_CHECK_RETRIES=6
readonly HEALTH_CHECK_INTERVAL=30
readonly GITHUB_RELEASES_URL="https://api.github.com/repos/XinFinOrg/XDPoSChain/releases"

# State
CURRENT_VERSION=""
LATEST_VERSION=""
BACKUP_TAG=""

#==============================================================================
# Logging Setup
#==============================================================================
init_logging() {
    local log_dir
    log_dir=$(dirname "$UPDATE_LOG")
    mkdir -p "$log_dir" 2>/dev/null || true
    touch "$UPDATE_LOG" 2>/dev/null || true
    chmod 644 "$UPDATE_LOG" 2>/dev/null || true
    export LOG_FILE="$UPDATE_LOG"
}

# Wrapper functions for backward compatibility

#==============================================================================
# Usage
#==============================================================================
print_usage() {
    cat << EOF
XDC Node Auto-Update System v${SCRIPT_VERSION}

Usage: $(basename "$0") [COMMAND] [OPTIONS]

Commands:
  check           Check for available updates
  update          Update to latest version
  rollback        Rollback to previous version
  status          Show current version and update status
  schedule        Setup automatic update schedule
  history         Show update history

Options:
  --force         Force update even if on latest version
  --no-backup     Skip backup before update
  --no-health     Skip health check after update
  --version VER   Update to specific version (e.g., v2.6.8)
  --dry-run       Show what would be done without executing
  --help, -h      Show this help message

Examples:
  $(basename "$0") check
  $(basename "$0") update
  $(basename "$0") update --version v2.6.8
  $(basename "$0") rollback
  $(basename "$0") schedule --cron "0 4 * * 0"  # Weekly at 4 AM Sunday

EOF
}

#==============================================================================
# Version Functions
#==============================================================================

get_current_version() {
    # Try to get version from running container
    local version
    version=$(docker exec xdc-node /work/xdc version 2>/dev/null | grep -oP 'Version: \K[^\s]+' || echo "")
    
    if [[ -z "$version" ]]; then
        # Fallback: get from image tag
        version=$(docker inspect xdc-node 2>/dev/null | jq -r '.[0].Config.Image' | cut -d: -f2 || echo "unknown")
    fi
    
    echo "$version"
}

get_latest_version() {
    local releases
    releases=$(curl -fsSL "$GITHUB_RELEASES_URL" 2>/dev/null || echo "[]")
    
    # Get latest non-prerelease version
    local latest
    latest=$(echo "$releases" | jq -r '[.[] | select(.prerelease == false) | .tag_name][0] // empty')
    
    if [[ -z "$latest" ]]; then
        log ERROR "Failed to fetch latest version from GitHub"
        return 1
    fi
    
    echo "$latest"
}

compare_versions() {
    local current="$1"
    local latest="$2"
    
    # Strip 'v' prefix
    current="${current#v}"
    latest="${latest#v}"
    
    if [[ "$current" == "$latest" ]]; then
        return 0  # Equal
    fi
    
    # Compare versions
    local IFS='.'
    read -ra curr_parts <<< "$current"
    read -ra latest_parts <<< "$latest"
    
    for ((i=0; i<3; i++)); do
        local c="${curr_parts[i]:-0}"
        local l="${latest_parts[i]:-0}"
        
        if [[ "$l" -gt "$c" ]]; then
            return 1  # Update available
        elif [[ "$l" -lt "$c" ]]; then
            return 2  # Current is newer
        fi
    done
    
    return 0  # Equal
}

#==============================================================================
# Backup Functions
#==============================================================================

create_backup() {
    log INFO "Creating backup before update..."
    
    mkdir -p "$BACKUP_DIR"
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    BACKUP_TAG="${CURRENT_VERSION}_${timestamp}"
    local backup_path="${BACKUP_DIR}/${BACKUP_TAG}"
    
    mkdir -p "$backup_path"
    
    # Backup configuration
    cp -r "${XDC_NODE_HOME}/.env" "$backup_path/" 2>/dev/null || true
    cp -r "${XDC_NODE_HOME}/docker-compose.yml" "$backup_path/" 2>/dev/null || true
    
    # Save current image info
    echo "$CURRENT_VERSION" > "$backup_path/version"
    docker images xinfinorg/xdposchain --format "{{.Tag}}" > "$backup_path/images.txt"
    
    # Commit current container state (optional, for quick rollback)
    docker commit xdc-node "xdc-node-backup:$BACKUP_TAG" 2>/dev/null || true
    
    log SUCCESS "Backup created: $backup_path"
    echo "$BACKUP_TAG" > "${BACKUP_DIR}/latest"
    
    return 0
}

list_backups() {
    log INFO "Available backups:"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo "  No backups found"
        return 0
    fi
    
    ls -1d "${BACKUP_DIR}"/*/ 2>/dev/null | while read -r dir; do
        local name
        name=$(basename "$dir")
        local version
        version=$(cat "$dir/version" 2>/dev/null || echo "unknown")
        echo "  • $name (version: $version)"
    done
}

cleanup_old_backups() {
    local keep_count="${1:-5}"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        return 0
    fi
    
    local backup_count
    backup_count=$(ls -1d "${BACKUP_DIR}"/*/ 2>/dev/null | wc -l || echo 0)
    
    if [[ "$backup_count" -gt "$keep_count" ]]; then
        log INFO "Cleaning up old backups (keeping $keep_count)..."
        
        ls -1dt "${BACKUP_DIR}"/*/ 2>/dev/null | tail -n +$((keep_count + 1)) | while read -r dir; do
            local name
            name=$(basename "$dir")
            rm -rf "$dir"
            docker rmi "xdc-node-backup:$name" 2>/dev/null || true
            log INFO "Removed old backup: $name"
        done
    fi
}

#==============================================================================
# Update Functions
#==============================================================================

stop_node() {
    log INFO "Stopping XDC node..."
    
    cd "$XDC_NODE_HOME"
    
    if command -v docker-compose &> /dev/null; then
        docker-compose stop xdc-node
    else
        docker compose stop xdc-node
    fi
    
    sleep 5
    log SUCCESS "Node stopped"
}

start_node() {
    log INFO "Starting XDC node..."
    
    cd "$XDC_NODE_HOME"
    
    if command -v docker-compose &> /dev/null; then
        docker-compose up -d xdc-node
    else
        docker compose up -d xdc-node
    fi
    
    sleep 10
    log SUCCESS "Node started"
}

pull_new_version() {
    local version="$1"
    
    log INFO "Pulling XDC image version: $version..."
    
    docker pull "xinfinorg/xdposchain:$version"
    
    # Update docker-compose.yml
    local compose_file="${XDC_NODE_HOME}/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
        sed -i "s|xinfinorg/xdposchain:[^[:space:]]*|xinfinorg/xdposchain:$version|g" "$compose_file"
    fi
    
    log SUCCESS "Pulled version $version"
}

perform_update() {
    local target_version="$1"
    local skip_backup="${2:-false}"
    local skip_health="${3:-false}"
    
    log INFO "Starting update to version $target_version"
    log INFO "Current version: $CURRENT_VERSION"
    
    # Create backup
    if [[ "$skip_backup" != "true" ]]; then
        create_backup || {
            log ERROR "Backup failed, aborting update"
            return 1
        }
    fi
    
    # Stop node
    stop_node
    
    # Pull new version
    pull_new_version "$target_version" || {
        log ERROR "Failed to pull new version"
        start_node  # Restart with old version
        return 1
    }
    
    # Start node with new version
    start_node
    
    # Health check
    if [[ "$skip_health" != "true" ]]; then
        if ! run_health_check; then
            log ERROR "Health check failed after update"
            log WARNING "Initiating automatic rollback..."
            
            perform_rollback
            return 1
        fi
    fi
    
    # Cleanup old backups
    cleanup_old_backups 5
    
    log SUCCESS "Update completed successfully!"
    log SUCCESS "New version: $target_version"
    
    return 0
}

#==============================================================================
# Rollback Functions
#==============================================================================

perform_rollback() {
    local backup_tag="${1:-}"
    
    # Get latest backup if not specified
    if [[ -z "$backup_tag" ]]; then
        if [[ -f "${BACKUP_DIR}/latest" ]]; then
            backup_tag=$(cat "${BACKUP_DIR}/latest")
        else
            log ERROR "No backup available for rollback"
            return 1
        fi
    fi
    
    local backup_path="${BACKUP_DIR}/${backup_tag}"
    
    if [[ ! -d "$backup_path" ]]; then
        log ERROR "Backup not found: $backup_tag"
        return 1
    fi
    
    local old_version
    old_version=$(cat "$backup_path/version" 2>/dev/null || echo "unknown")
    
    log INFO "Rolling back to version: $old_version (backup: $backup_tag)"
    
    # Stop current node
    stop_node
    
    # Restore configuration
    cp -f "$backup_path/.env" "${XDC_NODE_HOME}/" 2>/dev/null || true
    cp -f "$backup_path/docker-compose.yml" "${XDC_NODE_HOME}/" 2>/dev/null || true
    
    # Pull the old version if not available
    if ! docker images | grep -q "xinfinorg/xdposchain.*$old_version"; then
        docker pull "xinfinorg/xdposchain:$old_version"
    fi
    
    # Update docker-compose with old version
    sed -i "s|xinfinorg/xdposchain:[^[:space:]]*|xinfinorg/xdposchain:$old_version|g" "${XDC_NODE_HOME}/docker-compose.yml"
    
    # Start node
    start_node
    
    # Verify rollback
    sleep 10
    local new_current
    new_current=$(get_current_version)
    
    if [[ "$new_current" == "$old_version" ]] || [[ "$new_current" == "${old_version#v}" ]]; then
        log SUCCESS "Rollback successful! Running version: $new_current"
        return 0
    else
        log ERROR "Rollback verification failed. Current: $new_current, Expected: $old_version"
        return 1
    fi
}

#==============================================================================
# Health Check Functions
#==============================================================================

run_health_check() {
    log INFO "Running health checks..."
    
    local retries=0
    
    while [[ $retries -lt $HEALTH_CHECK_RETRIES ]]; do
        sleep "$HEALTH_CHECK_INTERVAL"
        
        # Check if container is running
        if ! docker ps | grep -q "xdc-node"; then
            log WARNING "Container not running (attempt $((retries + 1))/$HEALTH_CHECK_RETRIES)"
            ((retries++))
            continue
        fi
        
        # Check RPC responsiveness
        local rpc_response
        rpc_response=$(curl -s -m 10 http://localhost:8545 \
            -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' 2>/dev/null || echo "")
        
        if echo "$rpc_response" | grep -q "result"; then
            log SUCCESS "RPC endpoint responding"
            
            # Check peer count
            local peer_response
            peer_response=$(curl -s -m 10 http://localhost:8545 \
                -X POST \
                -H "Content-Type: application/json" \
                -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null || echo "")
            
            local peer_count
            peer_count=$(echo "$peer_response" | jq -r '.result // "0x0"' | xargs printf "%d" 2>/dev/null || echo "0")
            
            if [[ "$peer_count" -gt 0 ]]; then
                log SUCCESS "Node has $peer_count peers"
                return 0
            else
                log WARNING "No peers connected yet (attempt $((retries + 1))/$HEALTH_CHECK_RETRIES)"
            fi
        else
            log WARNING "RPC not responding (attempt $((retries + 1))/$HEALTH_CHECK_RETRIES)"
        fi
        
        ((retries++))
    done
    
    log ERROR "Health check failed after $HEALTH_CHECK_RETRIES attempts"
    return 1
}

#==============================================================================
# Schedule Functions
#==============================================================================

setup_schedule() {
    local cron_schedule="${1:-0 4 * * 0}"  # Default: Sunday 4 AM
    
    log INFO "Setting up automatic update schedule: $cron_schedule"
    
    # Create wrapper script
    local update_script="/usr/local/bin/xdc-auto-update"
    cat > "$update_script" << 'EOF'
#!/bin/bash
exec >> /var/log/xdc-node-updates.log 2>&1
echo "=== Auto-update started at $(date) ==="
/opt/xdc-node/scripts/auto-update.sh update --no-backup-on-fail
echo "=== Auto-update finished at $(date) ==="
EOF
    chmod +x "$update_script"
    
    # Add cron job
    local cron_line="$cron_schedule $update_script"
    
    # Remove existing entry
    crontab -l 2>/dev/null | grep -v "xdc-auto-update" | crontab - 2>/dev/null || true
    
    # Add new entry
    (crontab -l 2>/dev/null; echo "$cron_line") | crontab -
    
    log SUCCESS "Auto-update scheduled: $cron_schedule"
    log INFO "View schedule: crontab -l"
    
    return 0
}

remove_schedule() {
    log INFO "Removing auto-update schedule..."
    
    crontab -l 2>/dev/null | grep -v "xdc-auto-update" | crontab - 2>/dev/null || true
    
    log SUCCESS "Auto-update schedule removed"
}

#==============================================================================
# Status Functions
#==============================================================================

show_status() {
    CURRENT_VERSION=$(get_current_version)
    LATEST_VERSION=$(get_latest_version) || LATEST_VERSION="unknown"
    
    echo ""
    echo -e "${BOLD}XDC Node Update Status${NC}"
    echo "================================"
    echo ""
    echo -e "Current version:  ${CYAN}$CURRENT_VERSION${NC}"
    echo -e "Latest version:   ${CYAN}$LATEST_VERSION${NC}"
    
    if [[ "$LATEST_VERSION" != "unknown" ]]; then
        if compare_versions "$CURRENT_VERSION" "$LATEST_VERSION"; then
            echo -e "Status:           ${GREEN}Up to date${NC}"
        else
            echo -e "Status:           ${YELLOW}Update available${NC}"
        fi
    fi
    
    echo ""
    echo "Update Log: $UPDATE_LOG"
    echo ""
    
    # Check for scheduled updates
    if crontab -l 2>/dev/null | grep -q "xdc-auto-update"; then
        local schedule
        schedule=$(crontab -l | grep "xdc-auto-update" | awk '{print $1,$2,$3,$4,$5}')
        echo -e "Auto-update:      ${GREEN}Enabled${NC} ($schedule)"
    else
        echo -e "Auto-update:      ${YELLOW}Disabled${NC}"
    fi
    
    echo ""
    
    # Show recent updates
    if [[ -f "$UPDATE_LOG" ]]; then
        echo "Recent Updates:"
        tail -5 "$UPDATE_LOG" | while read -r line; do
            echo "  $line"
        done
    fi
    
    echo ""
}

show_history() {
    echo ""
    echo -e "${BOLD}XDC Node Update History${NC}"
    echo "================================"
    echo ""
    
    if [[ ! -f "$UPDATE_LOG" ]]; then
        echo "No update history available."
        return 0
    fi
    
    grep -E "Update completed|Rollback|Starting update" "$UPDATE_LOG" | tail -20 | while read -r line; do
        echo "  $line"
    done
    
    echo ""
    list_backups
    echo ""
}

#==============================================================================
# Main
#==============================================================================

main() {
    init_logging
    
    local command="${1:-}"
    shift || true
    
    # Parse global options
    local force=false
    local skip_backup=false
    local skip_health=false
    local target_version=""
    local dry_run=false
    local cron_schedule=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force=true
                shift
                ;;
            --no-backup)
                skip_backup=true
                shift
                ;;
            --no-health)
                skip_health=true
                shift
                ;;
            --version)
                target_version="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --cron)
                cron_schedule="$2"
                shift 2
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Get current version
    CURRENT_VERSION=$(get_current_version)
    
    case "$command" in
        check)
            LATEST_VERSION=$(get_latest_version) || exit 1
            
            echo "Current version: $CURRENT_VERSION"
            echo "Latest version:  $LATEST_VERSION"
            
            if compare_versions "$CURRENT_VERSION" "$LATEST_VERSION"; then
                echo -e "${GREEN}You are running the latest version.${NC}"
                exit 0
            else
                echo -e "${YELLOW}Update available!${NC}"
                echo "Run: $0 update"
                exit 0
            fi
            ;;
            
        update)
            # Determine target version
            if [[ -n "$target_version" ]]; then
                LATEST_VERSION="$target_version"
            else
                LATEST_VERSION=$(get_latest_version) || exit 1
            fi
            
            # Check if update needed
            if [[ "$force" != "true" ]] && compare_versions "$CURRENT_VERSION" "$LATEST_VERSION"; then
                log INFO "Already running latest version: $CURRENT_VERSION"
                exit 0
            fi
            
            if [[ "$dry_run" == "true" ]]; then
                log INFO "DRY RUN: Would update from $CURRENT_VERSION to $LATEST_VERSION"
                exit 0
            fi
            
            perform_update "$LATEST_VERSION" "$skip_backup" "$skip_health"
            ;;
            
        rollback)
            perform_rollback "$target_version"
            ;;
            
        status)
            show_status
            ;;
            
        history)
            show_history
            ;;
            
        schedule)
            if [[ -n "$cron_schedule" ]]; then
                setup_schedule "$cron_schedule"
            else
                setup_schedule  # Use default
            fi
            ;;
            
        unschedule)
            remove_schedule
            ;;
            
        ""|--help|-h)
            print_usage
            exit 0
            ;;
            
        *)
            log ERROR "Unknown command: $command"
            print_usage
            exit 1
            ;;
    esac
}

main "$@"
