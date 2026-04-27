#!/usr/bin/env bash
#===============================================================================
# XDC Fleet Rolling Update with Auto-Rollback
# Safely updates fleet nodes with health checks and automatic rollback.
#
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/251
#
# Usage:
#   rolling-update.sh <fleet-name> <new-image> [options]
#   rolling-update.sh --dry-run <fleet-name> <new-image>
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
PARALLEL="${XDC_PARALLEL:-1}"

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
  rolling-update.sh <fleet-name> <new-image> [--dry-run] [--parallel=N]

Options:
  --dry-run       Show what would be done without executing
  --parallel=N    Update N nodes in parallel (default: 1)
  --no-rollback   Disable automatic rollback on failure

Examples:
  rolling-update.sh apothem xdcindia/gp5:v96
  rolling-update.sh apothem xdcindia/gp5:v96 --dry-run
  rolling-update.sh mainnet xdcindia/gp5:v96 --parallel=2
EOF
}

# Get nodes for a fleet
get_fleet_nodes() {
    local fleet="$1"
    [[ -f "$FLEET_INVENTORY" ]] || die "Fleet inventory not found: $FLEET_INVENTORY"
    
    # Parse fleet.ini: name=ip#fleet1,fleet2
    while IFS='=' read -r name ip_fleets; do
        [ -z "$name" ] && continue
        [ "${name:0:1}" = "#" ] && continue
        
        local ip="${ip_fleets%%#*}"
        local fleets="${ip_fleets#*#}"
        
        # If no fleet tag, include in default fleet
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
    local timeout="${2:-30}"
    
    # Try RPC block number check
    local block_hex
    block_hex=$(ssh -p "$SSH_PORT" -i "$SSH_KEY" -o ConnectTimeout=5 "${SSH_USER}@${ip}" \
        "curl -s -X POST http://localhost:8545 -H 'Content-Type: application/json' \
         -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'" 2>/dev/null | \
        sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
    
    if [ -n "$block_hex" ] && [ "$block_hex" != "0x" ]; then
        return 0  # Healthy
    fi
    
    return 1  # Unhealthy
}

# Get current image on node
get_current_image() {
    local ip="$1"
    local container="${2:-xdc-gp5-apothem}"
    
    ssh -p "$SSH_PORT" -i "$SSH_KEY" -o ConnectTimeout=5 "${SSH_USER}@${ip}" \
        "docker inspect --format='{{.Config.Image}}' $container 2>/dev/null || echo 'unknown'"
}

# Update a single node
update_node() {
    local name="$1" ip="$2" new_image="$3"
    local dry_run="${4:-false}"
    
    info "[$name] Starting update..."
    
    # Get current image for rollback
    local current_image
    current_image=$(get_current_image "$ip" "xdc-gp5-apothem")
    info "[$name] Current image: $current_image"
    
    if [[ "$current_image" == "$new_image" ]]; then
        ok "[$name] Already running $new_image — skipping"
        return 0
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        info "[$name] DRY-RUN: Would update $current_image → $new_image"
        return 0
    fi
    
    # Pull new image
    info "[$name] Pulling $new_image..."
    if ! ssh -p "$SSH_PORT" -i "$SSH_KEY" "${SSH_USER}@${ip}" "docker pull $new_image" >/dev/null 2>&1; then
        error "[$name] Failed to pull $new_image"
        return 1
    fi
    
    # Stop, update, start
    info "[$name] Stopping container..."
    ssh -p "$SSH_PORT" -i "$SSH_KEY" "${SSH_USER}@${ip}" "docker compose stop xdc-node || docker stop xdc-gp5-apothem" 2>/dev/null || true
    
    info "[$name] Updating compose config..."
    ssh -p "$SSH_PORT" -i "$SSH_KEY" "${SSH_USER}@${ip}" \
        "sed -i 's|image: .*|image: $new_image|' /data/xdc-nodes/*/docker-compose.yml 2>/dev/null || true"
    
    info "[$name] Starting with new image..."
    ssh -p "$SSH_PORT" -i "$SSH_KEY" "${SSH_USER}@${ip}" \
        "cd /data/xdc-nodes/* && docker compose up -d" 2>/dev/null || \
        ssh -p "$SSH_PORT" -i "$SSH_KEY" "${SSH_USER}@${ip}" \
        "docker run -d --name xdc-gp5-apothem --restart unless-stopped $new_image" 2>/dev/null || true
    
    # Health check
    info "[$name] Waiting for health check (${HEALTH_TIMEOUT}s)..."
    local healthy=false
    for i in $(seq 1 $((HEALTH_TIMEOUT / 10))); do
        sleep 10
        if node_health "$ip" 10; then
            healthy=true
            break
        fi
        info "[$name] Health check $i/$((HEALTH_TIMEOUT / 10))..."
    done
    
    if [[ "$healthy" == "true" ]]; then
        ok "[$name] Update successful — node healthy"
        return 0
    else
        error "[$name] Health check FAILED after update"
        
        if [[ "$ROLLBACK_ON_FAILURE" == "true" ]]; then
            warn "[$name] Rolling back to $current_image..."
            ssh -p "$SSH_PORT" -i "$SSH_KEY" "${SSH_USER}@${ip}" \
                "docker compose stop xdc-node 2>/dev/null; docker stop xdc-gp5-apothem 2>/dev/null || true"
            ssh -p "$SSH_PORT" -i "$SSH_KEY" "${SSH_USER}@${ip}" \
                "sed -i 's|image: .*|image: $current_image|' /data/xdc-nodes/*/docker-compose.yml 2>/dev/null || true"
            ssh -p "$SSH_PORT" -i "$SSH_KEY" "${SSH_USER}@${ip}" \
                "cd /data/xdc-nodes/* && docker compose up -d 2>/dev/null || docker start xdc-gp5-apothem 2>/dev/null || true"
            
            # Verify rollback health
            sleep 30
            if node_health "$ip" 10; then
                ok "[$name] Rollback successful — node healthy"
                return 2  # Special code: rollback occurred
            else
                error "[$name] Rollback FAILED — node still unhealthy!"
                return 1
            fi
        fi
        
        return 1
    fi
}

# ── main ─────────────────────────────────────────────────────────────────────
main() {
    local fleet="${1:-}"
    local new_image="${2:-}"
    local dry_run=false
    
    [[ -z "$fleet" || -z "$new_image" ]] && { usage; exit 1; }
    
    # Parse options
    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=true ;;
            --parallel=*) PARALLEL="${1#*=}" ;;
            --no-rollback) ROLLBACK_ON_FAILURE=false ;;
            *) warn "Unknown option: $1" ;;
        esac
        shift
    done
    
    info "Rolling update: fleet=$fleet, image=$new_image, parallel=$PARALLEL, rollback=$ROLLBACK_ON_FAILURE"
    [[ "$dry_run" == "true" ]] && info "DRY-RUN MODE — no changes will be made"
    
    # Get fleet nodes
    local nodes
    nodes=$(get_fleet_nodes "$fleet")
    [[ -z "$nodes" ]] && die "No nodes found for fleet: $fleet"
    
    local total=0 success=0 failed=0 rolled_back=0
    
    while IFS=' ' read -r name ip; do
        [[ -z "$name" ]] && continue
        ((total++))
        
        if update_node "$name" "$ip" "$new_image" "$dry_run"; then
            ((success++))
        elif [[ $? -eq 2 ]]; then
            ((rolled_back++))
        else
            ((failed++))
        fi
    done <<< "$nodes"
    
    echo ""
    info "Rolling update complete:"
    echo "  Total:     $total"
    echo "  Success:   $success"
    echo "  Rolled back: $rolled_back"
    echo "  Failed:    $failed"
    
    if [[ "$failed" -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
