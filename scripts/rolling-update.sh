#!/usr/bin/env bash
#===============================================================================
# XDC Fleet Rolling Update with Auto-Rollback
# Safely updates fleet nodes with health checks and automatic rollback.
#
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/251
#
# Usage:
#   rolling-update.sh <fleet-name> <new-image> [options]
#===============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_INVENTORY="${XDC_FLEET_INVENTORY:-$HOME/.config/xdc/fleet.ini}"

# ── defaults ─────────────────────────────────────────────────────────────────
SSH_PORT="${XDC_SSH_PORT:-12141}"
SSH_USER="${XDC_SSH_USER:-ubuntu}"
SSH_KEY="${XDC_SSH_KEY:-$HOME/.ssh/xdc_fleet_rsa}"
HEALTH_TIMEOUT="${XDC_HEALTH_TIMEOUT:-300}"
ROLLBACK_ON_FAILURE="${XDC_ROLLBACK:-true}"
CONTAINER_NAME="${XDC_CONTAINER:-xdc-node}"

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
die()   { error "$*"; exit 1; }

# ── helpers ──────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}rolling-update.sh${NC} — Fleet Rolling Update with Auto-Rollback

Usage:
  rolling-update.sh <fleet-name> <new-image> [--dry-run]

Options:
  --dry-run       Show what would be done without executing
  --timeout=N     Health check timeout in seconds (default: 300)
  --no-rollback   Disable automatic rollback on failure

Examples:
  rolling-update.sh apothem xdcindia/gp5:v96
  rolling-update.sh apothem xdcindia/gp5:v96 --dry-run
  rolling-update.sh mainnet xdcindia/gp5:v96 --timeout=600
EOF
}

# SSH helper with common options
ssh_node() {
    local ip="$1"
    shift
    ssh -p "$SSH_PORT" -i "$SSH_KEY" \
        -o StrictHostKeyChecking=accept-new \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        "${SSH_USER}@${ip}" "$@"
}

# Get nodes for a fleet
get_fleet_nodes() {
    local fleet="$1"
    [[ -f "$FLEET_INVENTORY" ]] || die "Fleet inventory not found: $FLEET_INVENTORY"
    
    while IFS='=' read -r name ip_fleets; do
        [ -z "$name" ] && continue
        [ "${name:0:1}" = "#" ] && continue
        
        local ip="${ip_fleets%%#*}"
        local fleets="${ip_fleets#*#}"
        
        if [[ "$ip_fleets" == "$ip" ]]; then
            fleets="default"
        fi
        
        if [[ ",$fleets," == *",$fleet,"* ]]; then
            echo "$name $ip"
        fi
    done < "$FLEET_INVENTORY"
}

# Check node health via RPC
node_health() {
    local ip="$1"
    local block_hex
    block_hex=$(ssh_node "$ip" "curl -s -X POST http://localhost:8545 -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'" 2>/dev/null | \
        sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
    
    [ -n "$block_hex" ] && [ "$block_hex" != "0x" ]
}

# Get current image on node
get_current_image() {
    local ip="$1"
    local container="$2"
    
    ssh_node "$ip" "docker inspect --format='{{.Config.Image}}' $container 2>/dev/null || echo ''"
}

# Update a single node
update_node() {
    local name="$1" ip="$2" new_image="$3"
    local dry_run="${4:-false}"
    
    info "[$name] Starting update..."
    
    # Find compose directory
    local compose_dir
    compose_dir=$(ssh_node "$ip" "find /data/xdc-nodes -name 'docker-compose.yml' -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo ''")
    
    if [ -z "$compose_dir" ]; then
        error "[$name] No docker-compose.yml found in /data/xdc-nodes"
        return 1
    fi
    
    # Get current image
    local current_image
    current_image=$(get_current_image "$ip" "$CONTAINER_NAME")
    
    if [ -z "$current_image" ]; then
        error "[$name] Cannot determine current image — container $CONTAINER_NAME not found"
        return 1
    fi
    
    info "[$name] Current image: $current_image"
    
    if [ "$current_image" = "$new_image" ]; then
        ok "[$name] Already running $new_image — skipping"
        return 0
    fi
    
    if [ "$dry_run" = "true" ]; then
        info "[$name] DRY-RUN: Would update $current_image → $new_image"
        return 0
    fi
    
    # Backup compose file
    ssh_node "$ip" "cp -a '$compose_dir/docker-compose.yml' '$compose_dir/docker-compose.yml.bak.$(date +%s)'"
    
    # Pull new image
    info "[$name] Pulling $new_image..."
    if ! ssh_node "$ip" "docker pull $new_image" >/dev/null 2>&1; then
        error "[$name] Failed to pull $new_image"
        return 1
    fi
    
    # Update compose file (scoped to xdc-node service only)
    info "[$name] Updating compose config..."
    ssh_node "$ip" "cd '$compose_dir' && sed -i '/services:/,/^[^ ]/ { /$CONTAINER_NAME:/,/^[^ ]/ { s|image: .*|image: $new_image| } }' docker-compose.yml"
    
    # Stop and restart
    info "[$name] Stopping container..."
    ssh_node "$ip" "cd '$compose_dir' && docker compose stop $CONTAINER_NAME" 2>/dev/null || true
    
    info "[$name] Starting with new image..."
    if ! ssh_node "$ip" "cd '$compose_dir' && docker compose up -d $CONTAINER_NAME" >/dev/null 2>&1; then
        error "[$name] Failed to start with new image"
        
        # Attempt rollback
        if [ "$ROLLBACK_ON_FAILURE" = "true" ]; then
            warn "[$name] Attempting rollback..."
            ssh_node "$ip" "cd '$compose_dir' && sed -i '/services:/,/^[^ ]/ { /$CONTAINER_NAME:/,/^[^ ]/ { s|image: .*|image: $current_image| } }' docker-compose.yml"
            ssh_node "$ip" "cd '$compose_dir' && docker compose up -d $CONTAINER_NAME" 2>/dev/null || true
        fi
        return 1
    fi
    
    # Health check
    info "[$name] Health checking (timeout ${HEALTH_TIMEOUT}s)..."
    local healthy=false
    local elapsed=0
    
    while [ $elapsed -lt "$HEALTH_TIMEOUT" ]; do
        if node_health "$ip"; then
            healthy=true
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    if [ "$healthy" = "true" ]; then
        ok "[$name] Update successful — node healthy"
        return 0
    fi
    
    error "[$name] Health check FAILED after ${HEALTH_TIMEOUT}s"
    
    if [ "$ROLLBACK_ON_FAILURE" = "true" ]; then
        warn "[$name] Rolling back to $current_image..."
        ssh_node "$ip" "cd '$compose_dir' && docker compose stop $CONTAINER_NAME" 2>/dev/null || true
        ssh_node "$ip" "cd '$compose_dir' && sed -i '/services:/,/^[^ ]/ { /$CONTAINER_NAME:/,/^[^ ]/ { s|image: .*|image: $current_image| } }' docker-compose.yml"
        
        if ssh_node "$ip" "cd '$compose_dir' && docker compose up -d $CONTAINER_NAME" >/dev/null 2>&1; then
            sleep 30
            if node_health "$ip"; then
                ok "[$name] Rollback successful — node healthy"
                return 2
            fi
        fi
        error "[$name] Rollback FAILED — manual intervention required!"
    fi
    
    return 1
}

# ── main ─────────────────────────────────────────────────────────────────────
main() {
    local fleet="${1:-}"
    local new_image="${2:-}"
    local dry_run=false
    
    [ -z "$fleet" ] || [ -z "$new_image" ] && { usage; exit 1; }
    
    shift 2
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) dry_run=true ;;
            --timeout=*) HEALTH_TIMEOUT="${1#*=}" ;;
            --no-rollback) ROLLBACK_ON_FAILURE=false ;;
            *) warn "Unknown option: $1" ;;
        esac
        shift
    done
    
    info "Rolling update: fleet=$fleet, image=$new_image, timeout=$HEALTH_TIMEOUT, rollback=$ROLLBACK_ON_FAILURE"
    [ "$dry_run" = "true" ] && info "DRY-RUN MODE"
    
    local nodes
    nodes=$(get_fleet_nodes "$fleet")
    [ -z "$nodes" ] && die "No nodes found for fleet: $fleet"
    
    local total=0 success=0 failed=0 rolled_back=0
    
    while IFS=' ' read -r name ip; do
        [ -z "$name" ] && continue
        total=$((total + 1))
        
        local rc=0
        update_node "$name" "$ip" "$new_image" "$dry_run" || rc=$?
        
        case $rc in
            0) success=$((success + 1)) ;;
            2) rolled_back=$((rolled_back + 1)) ;;
            *) failed=$((failed + 1)) ;;
        esac
    done <<< "$nodes"
    
    echo ""
    info "Rolling update complete:"
    echo "  Total:       $total"
    echo "  Success:     $success"
    echo "  Rolled back: $rolled_back"
    echo "  Failed:      $failed"
    
    [ "$failed" -gt 0 ] && exit 1
}

main "$@"
