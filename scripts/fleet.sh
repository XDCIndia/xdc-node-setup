#!/bin/bash
#===============================================================================
# XDC Fleet Inventory and Deployment Helpers
# SSH port 12141 support for XDCIndia fleet
#===============================================================================

set -euo pipefail

# Default fleet configuration
FLEET_INVENTORY="${FLEET_INVENTORY:-${HOME}/.config/xdc/fleet.ini}"
SSH_PORT="${SSH_PORT:-12141}"
SSH_USER="${SSH_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/xdc_fleet_rsa}"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

die() { echo -e "${RED}ERROR: $1${NC}" >&2; exit 1; }
info() { echo -e "${GREEN}INFO: $1${NC}"; }
warn() { echo -e "${YELLOW}WARN: $1${NC}"; }
log() { echo -e "${BLUE}→ $1${NC}"; }

usage() {
    cat << 'EOF'
Usage: fleet.sh <command> [options]

Commands:
  list                  List all fleet nodes from inventory
  add <name> <ip>       Add a node to inventory
  remove <name>         Remove a node from inventory
  ssh <name>            SSH into a fleet node (port 12141)
  deploy <name> <dir>   Deploy XNS to a fleet node via rsync+ssh
  status                Check status of all fleet nodes
  cmd <name> <command>  Run a command on a fleet node
  sync-peers <name>     Sync peer list from one node to others

Environment:
  FLEET_INVENTORY       Path to fleet.ini (default: ~/.config/xdc/fleet.ini)
  SSH_PORT              SSH port (default: 12141)
  SSH_USER              SSH user (default: ubuntu)
  SSH_KEY               SSH private key path

Examples:
  fleet.sh list
  fleet.sh add xdc07 95.217.112.125
  fleet.sh ssh xdc07
  fleet.sh deploy xdc07 /data/apothem/gp5-pbss-125
  fleet.sh status
EOF
    exit 1
}

# Ensure inventory directory exists
ensure_inventory() {
    local dir
    dir=$(dirname "$FLEET_INVENTORY")
    [ -d "$dir" ] || mkdir -p "$dir"
    [ -f "$FLEET_INVENTORY" ] || touch "$FLEET_INVENTORY"
}

# Parse inventory file
list_nodes() {
    ensure_inventory
    if [ ! -s "$FLEET_INVENTORY" ]; then
        echo "No nodes in inventory. Add one with: fleet.sh add <name> <ip>"
        return
    fi
    printf "%-15s %-20s %-15s\n" "NAME" "IP" "STATUS"
    echo "─────────────────────────────────────────────────────────────"
    while IFS='=' read -r name ip; do
        [ -z "$name" ] && continue
        [ "${name:0:1}" = "#" ] && continue
        # Quick status check
        if timeout 5 bash -c "</dev/tcp/${ip}/${SSH_PORT}" 2>/dev/null; then
            status="online"
        else
            status="offline"
        fi
        printf "%-15s %-20s %-15s\n" "$name" "$ip" "$status"
    done < "$FLEET_INVENTORY"
}

# Add node
add_node() {
    local name="$1" ip="$2"
    ensure_inventory
    # Remove existing entry if present
    grep -v "^${name}=" "$FLEET_INVENTORY" > "${FLEET_INVENTORY}.tmp" 2>/dev/null || true
    mv "${FLEET_INVENTORY}.tmp" "$FLEET_INVENTORY"
    echo "${name}=${ip}" >> "$FLEET_INVENTORY"
    info "Added ${name} (${ip}) to fleet inventory"
}

# Remove node
remove_node() {
    local name="$1"
    ensure_inventory
    if ! grep -q "^${name}=" "$FLEET_INVENTORY"; then
        die "Node '${name}' not found in inventory"
    fi
    grep -v "^${name}=" "$FLEET_INVENTORY" > "${FLEET_INVENTORY}.tmp"
    mv "${FLEET_INVENTORY}.tmp" "$FLEET_INVENTORY"
    info "Removed ${name} from fleet inventory"
}

# Get IP for node
get_ip() {
    local name="$1"
    ensure_inventory
    local ip
    ip=$(grep "^${name}=" "$FLEET_INVENTORY" | cut -d= -f2)
    [ -z "$ip" ] && die "Node '${name}' not found in inventory"
    echo "$ip"
}

# SSH into node
ssh_node() {
    local name="$1"
    local ip
    ip=$(get_ip "$name")
    log "Connecting to ${name} (${ip}:${SSH_PORT})..."
    ssh -p "$SSH_PORT" -i "$SSH_KEY" "${SSH_USER}@${ip}"
}

# Run command on node
cmd_node() {
    local name="$1"
    shift
    local ip
    ip=$(get_ip "$name")
    log "Running on ${name}: $*"
    ssh -p "$SSH_PORT" -i "$SSH_KEY" "${SSH_USER}@${ip}" "$@"
}

# Deploy XNS to node
deploy_node() {
    local name="$1" local_dir="$2"
    local ip
    ip=$(get_ip "$name")
    
    [ -d "$local_dir" ] || die "Local directory not found: $local_dir"
    [ -f "$local_dir/docker-compose.yml" ] || warn "No docker-compose.yml in $local_dir"
    
    log "Deploying to ${name} (${ip})..."
    
    # Create remote directory
    ssh -p "$SSH_PORT" -i "$SSH_KEY" "${SSH_USER}@${ip}" "mkdir -p /data/xdc-nodes/$(basename "$local_dir")"
    
    # Rsync files
    rsync -avz -e "ssh -p ${SSH_PORT} -i ${SSH_KEY}" \
        --exclude='xdcchain/' \
        --exclude='*.log' \
        "$local_dir/" "${SSH_USER}@${ip}:/data/xdc-nodes/$(basename "$local_dir")/"
    
    info "Deployed to ${name}. Start with: fleet.sh cmd ${name} 'cd /data/xdc-nodes/$(basename "$local_dir") && docker compose up -d'"
}

# Check status of all nodes
status_all() {
    ensure_inventory
    info "Checking fleet status..."
    while IFS='=' read -r name ip; do
        [ -z "$name" ] && continue
        [ "${name:0:1}" = "#" ] && continue
        
        printf "%-15s %-20s " "$name" "$ip"
        
        # SSH check
        if timeout 5 ssh -p "$SSH_PORT" -i "$SSH_KEY" -o ConnectTimeout=3 "${SSH_USER}@${ip}" "echo OK" >/dev/null 2>&1; then
            # Check if XDC node is running
            if ssh -p "$SSH_PORT" -i "$SSH_KEY" "${SSH_USER}@${ip}" "docker ps --format '{{.Names}}' | grep -q xdc" >/dev/null 2>&1; then
                # Get block height - parse hex result from RPC
                block_hex=$(ssh -p "$SSH_PORT" -i "$SSH_KEY" "${SSH_USER}@${ip}" "curl -s -X POST http://localhost:8545 -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'" 2>/dev/null | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
                if [ -n "$block_hex" ] && [ "$block_hex" != "0x" ]; then
                    block=$(printf '%d' "$block_hex" 2>/dev/null || echo "N/A")
                else
                    block="N/A"
                fi
                echo "online | block: ${block}"
            else
                echo "online (no node)"
            fi
        else
            echo -e "${RED}offline${NC}"
        fi
    done < "$FLEET_INVENTORY"
}

# Sync peers from one node to others
sync_peers() {
    local source_name="$1"
    local source_ip
    source_ip=$(get_ip "$source_name")
    
    log "Getting peers from ${source_name}..."
    local peers
    peers=$(ssh -p "$SSH_PORT" -i "$SSH_KEY" "${SSH_USER}@${source_ip}" "curl -s -X POST http://localhost:8545 -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"admin_peers\",\"params\":[],\"id\":1}'" 2>/dev/null)
    
    [ -z "$peers" ] && die "Could not get peers from ${source_name}"
    
    info "Found peers on ${source_name}, syncing to fleet..."
    while IFS='=' read -r name ip; do
        [ -z "$name" ] && continue
        [ "${name:0:1}" = "#" ] && continue
        [ "$name" = "$source_name" ] && continue
        
        log "Syncing to ${name}..."
        printf '%s' "$peers" | ssh -p "$SSH_PORT" -i "$SSH_KEY" "${SSH_USER}@${ip}" "cat > /tmp/peers.json" || warn "Failed to sync to ${name}"
    done < "$FLEET_INVENTORY"
    
    info "Peer sync complete. Peers saved to /tmp/peers.json on each node."
    info "To apply: fleet.sh cmd <name> 'jq \"[.result[].enode]\" /tmp/peers.json > /work/xdcchain/\${CHAIN_SUBDIR:-geth}/static-nodes.json'"
}

# Main
case "${1:-}" in
    list) list_nodes ;;
    add) [ $# -ge 3 ] || usage; add_node "$2" "$3" ;;
    remove) [ $# -ge 2 ] || usage; remove_node "$2" ;;
    ssh) [ $# -ge 2 ] || usage; ssh_node "$2" ;;
    cmd) [ $# -ge 3 ] || usage; shift; cmd_node "$@" ;;
    deploy) [ $# -ge 3 ] || usage; deploy_node "$2" "$3" ;;
    status) status_all ;;
    sync-peers) [ $# -ge 2 ] || usage; sync_peers "$2" ;;
    *) usage ;;
esac
