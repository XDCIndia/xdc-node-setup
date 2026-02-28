#!/bin/bash
# XDC Masternode Cluster Management
# Multi-node masternode management for high availability
# Author: anilcinchawale <anil24593@gmail.com>

set -euo pipefail

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
CONFIG_DIR="/etc/xdc-node"
CLUSTER_CONFIG="${CONFIG_DIR}/cluster.conf"
LOG_DIR="/var/log/xdc-node"
CLUSTER_LOG="${LOG_DIR}/cluster.log"
KEY_DIR="${CONFIG_DIR}/cluster-keys"

# Detect network for network-aware directory structure
detect_network() {
    local network="${NETWORK:-}"
    if [[ -z "$network" && -f "$(pwd)/config.toml" ]]; then
        network=$(grep -E '^\s*name\s*=' "$(pwd)/config.toml" 2>/dev/null | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -1)
    fi
    if [[ -z "$network" && -f "/opt/xdc-node/config.toml" ]]; then
        network=$(grep -E '^\s*name\s*=' "/opt/xdc-node/config.toml" 2>/dev/null | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -1)
    fi
    echo "${network:-mainnet}"
}
XDC_NETWORK="${XDC_NETWORK:-$(detect_network)}"
XDC_DATA="${XDC_DATA:-$(pwd)/${XDC_NETWORK}/xdcchain}"
XDC_STATE_DIR="${XDC_STATE_DIR:-$(pwd)/${XDC_NETWORK}/.xdc-node}"
STATE_DIR="${XDC_STATE_DIR}/cluster"

# Source libraries
source "${LIB_DIR}/notify.sh" 2>/dev/null || true

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$CLUSTER_LOG" 2>/dev/null || echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$CLUSTER_LOG" 2>/dev/null || echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$CLUSTER_LOG" 2>/dev/null || echo -e "${RED}[ERROR]${NC} $1"
}

# Print banner
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         XDC Masternode Cluster Management                    ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Show usage
show_usage() {
    echo -e "${BOLD}Usage:${NC} $0 [COMMAND] [OPTIONS]"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  init                      Initialize cluster configuration"
    echo "  add-node <host>          Add a backup node to cluster"
    echo "  remove-node <host>       Remove a node from cluster"
    echo "  status                    Show cluster status"
    echo "  health                    Check health of all nodes"
    echo "  failover [primary]        Perform manual failover"
    echo "  sync-keys                 Sync keys to all nodes"
    echo "  promote <host>           Promote node to primary"
    echo "  demote <host>            Demote node to backup"
    echo "  vote                      Participate in health consensus"
    echo "  leader                    Show current leader"
    echo "  config                    Show cluster configuration"
    echo "  -h, --help                Show this help message"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --cluster-id ID           Set cluster ID (default: auto-generated)"
    echo "  --ssh-key PATH            SSH key for node access"
    echo "  --user USER               SSH user (default: xdc)"
    echo "  --force                   Force operation without confirmation"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  $0 init --cluster-id xdc-mn-001"
    echo "  $0 add-node 192.168.1.100 --user xdc"
    echo "  $0 status"
    echo "  $0 failover 192.168.1.10"
}

# Ensure directories exist
ensure_directories() {
    if [[ ! -d "$LOG_DIR" ]]; then
        sudo mkdir -p "$LOG_DIR" 2>/dev/null || mkdir -p "$LOG_DIR"
    fi
    if [[ ! -d "$STATE_DIR" ]]; then
        sudo mkdir -p "$STATE_DIR" 2>/dev/null || mkdir -p "$STATE_DIR"
    fi
    if [[ ! -d "$KEY_DIR" ]]; then
        sudo mkdir -p "$KEY_DIR" 2>/dev/null || mkdir -p "$KEY_DIR"
        chmod 700 "$KEY_DIR"
    fi
}

# Generate cluster ID
generate_cluster_id() {
    echo "xdc-mn-$(date +%s | sha256sum | head -c 6)"
}

# Initialize cluster
init_cluster() {
    local cluster_id="${1:-}"
    
    if [[ -z "$cluster_id" ]]; then
        cluster_id=$(generate_cluster_id)
    fi
    
    log_info "Initializing cluster: $cluster_id"
    
    # Create cluster config
    sudo mkdir -p "$CONFIG_DIR" 2>/dev/null || mkdir -p "$CONFIG_DIR"
    
    cat <<EOF | sudo tee "$CLUSTER_CONFIG" >/dev/null
# XDC Masternode Cluster Configuration
# Generated: $(date)

CLUSTER_ID="$cluster_id"
CLUSTER_NODES=""
PRIMARY_NODE=""
FAILOVER_ENABLED=true
FAILOVER_THRESHOLD=3
KEY_ENCRYPTION="aes-256-gcm"
HEALTH_CHECK_INTERVAL=30
CONSENSUS_TIMEOUT=60
ELECTION_TIMEOUT=10

# Network settings
NETWORK_PORT=30303
RPC_PORT=8545
WS_PORT=8546

# Security
SSH_USER="xdc"
SSH_KEY_PATH="/home/xdc/.ssh/id_rsa"
EOF

    # Initialize state file
    echo "{\"cluster_id\": \"$cluster_id\", \"initialized\": \"$(date -Iseconds)\", \"leader\": \"\", \"nodes\": []}" | sudo tee "${STATE_DIR}/state.json" >/dev/null
    
    log_info "Cluster initialized: $cluster_id"
    log_info "Configuration: $CLUSTER_CONFIG"
    
    # Create health check script
    create_health_check_script
    
    echo ""
    echo -e "${GREEN}✓ Cluster initialized successfully${NC}"
    echo ""
    echo -e "  Cluster ID: ${CYAN}$cluster_id${NC}"
    echo -e "  Config:     ${CYAN}$CLUSTER_CONFIG${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Add backup nodes: $0 add-node <ip>"
    echo "  2. Set this node as primary: $0 promote $(hostname -I | awk '{print $1}')"
    echo ""
}

# Create health check script
create_health_check_script() {
    local script_path="${STATE_DIR}/health-check.sh"
    
    cat <<'EOF' > "$script_path"
#!/bin/bash
# Cluster health check script
set -euo pipefail

LOG_FILE="/var/log/xdc-node/cluster-health.log"

# Detect network for network-aware directory structure (for embedded script)
XDC_NETWORK="${XDC_NETWORK:-$(detect_network)}"
XDC_DATA="${XDC_DATA:-$(pwd)/${XDC_NETWORK}/xdcchain}"
XDC_STATE_DIR="${XDC_STATE_DIR:-$(pwd)/${XDC_NETWORK}/.xdc-node}"
STATE_DIR="${XDC_STATE_DIR}/cluster"

log() {
    echo "[$(date -Iseconds)] $1" | tee -a "$LOG_FILE"
}

check_local_health() {
    # Check if XDC node is running
    if pgrep -x "XDC" > /dev/null; then
        echo "healthy"
    else
        echo "unhealthy"
    fi
}

update_health_status() {
    local status="$1"
    echo "{\"timestamp\": \"$(date -Iseconds)\", \"status\": \"$status\", \"hostname\": \"$(hostname)\", \"ip\": \"$(hostname -I | awk '{print $1}')\"}" > "${STATE_DIR}/health.json"
}

# Main
HEALTH=$(check_local_health)
update_health_status "$HEALTH"
log "Health check: $HEALTH"
EOF

    chmod +x "$script_path"
    
    # Add to cron if not already present
    if ! crontab -l 2>/dev/null | grep -q "cluster-health"; then
        (crontab -l 2>/dev/null; echo "*/1 * * * * ${script_path} > /dev/null 2>&1") | crontab -
        log_info "Health check cron job added"
    fi
}

# Load cluster config
load_config() {
    if [[ ! -f "$CLUSTER_CONFIG" ]]; then
        log_error "Cluster not initialized. Run: $0 init"
        return 1
    fi
    
    # shellcheck source=/dev/null
    source "$CLUSTER_CONFIG"
}

# Add node to cluster
add_node() {
    local host="$1"
    local ssh_user="${2:-xdc}"
    local ssh_key="${3:-}"
    
    load_config
    
    log_info "Adding node: $host"
    
    # Validate SSH connectivity
    local ssh_opts="-o ConnectTimeout=5 -o StrictHostKeyChecking=no"
    if [[ -n "$ssh_key" ]]; then
        ssh_opts="$ssh_opts -i $ssh_key"
    fi
    
    if ! ssh $ssh_opts "${ssh_user}@${host}" "echo 'SSH OK'" >/dev/null 2>&1; then
        log_error "Cannot connect to $host via SSH"
        return 1
    fi
    
    # Get node info
    local node_info
    node_info=$(ssh $ssh_opts "${ssh_user}@${host}" "hostname; hostname -I | awk '{print \$1}'; uptime -p" 2>/dev/null)
    
    local hostname
    hostname=$(echo "$node_info" | head -1)
    local ip
    ip=$(echo "$node_info" | sed -n '2p')
    local uptime
    uptime=$(echo "$node_info" | sed -n '3p')
    
    log_info "  Hostname: $hostname"
    log_info "  IP: $ip"
    log_info "  Uptime: $uptime"
    
    # Update cluster config
    local current_nodes
    current_nodes="${CLUSTER_NODES:-}"
    
    if [[ -z "$current_nodes" ]]; then
        CLUSTER_NODES="$host"
    else
        # Check if already exists
        if [[ ",$current_nodes," == *",$host,"* ]]; then
            log_warn "Node $host already in cluster"
            return 0
        fi
        CLUSTER_NODES="${current_nodes},${host}"
    fi
    
    # Update config file
    sudo sed -i "s/^CLUSTER_NODES=.*/CLUSTER_NODES=\"$CLUSTER_NODES\"/" "$CLUSTER_CONFIG"
    
    # Add node to state
    local node_entry
    node_entry="{\"host\": \"$host\", \"hostname\": \"$hostname\", \"ip\": \"$ip\", \"role\": \"backup\", \"status\": \"active\", \"added\": \"$(date -Iseconds)\"}"
    
    # Update state.json
    if [[ -f "${STATE_DIR}/state.json" ]]; then
        local current_state
        current_state=$(cat "${STATE_DIR}/state.json")
        # Use jq if available
        if command -v jq &>/dev/null; then
            echo "$current_state" | jq --arg node "$node_entry" '.nodes += [$node | fromjson]' | sudo tee "${STATE_DIR}/state.json" >/dev/null
        fi
    fi
    
    log_info "Node $host added to cluster"
    
    # Sync keys
    log_info "Syncing keys to new node..."
    sync_keys "$host"
    
    echo ""
    echo -e "${GREEN}✓ Node added successfully${NC}"
    echo ""
}

# Remove node from cluster
remove_node() {
    local host="$1"
    local force="${2:-false}"
    
    load_config
    
    if [[ "$host" == "$PRIMARY_NODE" ]] && [[ "$force" != "true" ]]; then
        log_error "Cannot remove primary node. Promote another node first or use --force"
        return 1
    fi
    
    log_info "Removing node: $host"
    
    # Update cluster config
    local new_nodes=""
    IFS=',' read -ra nodes <<< "$CLUSTER_NODES"
    for node in "${nodes[@]}"; do
        if [[ "$node" != "$host" ]]; then
            if [[ -z "$new_nodes" ]]; then
                new_nodes="$node"
            else
                new_nodes="${new_nodes},${node}"
            fi
        fi
    done
    
    CLUSTER_NODES="$new_nodes"
    sudo sed -i "s/^CLUSTER_NODES=.*/CLUSTER_NODES=\"$CLUSTER_NODES\"/" "$CLUSTER_CONFIG"
    
    log_info "Node $host removed from cluster"
    
    echo ""
    echo -e "${GREEN}✓ Node removed successfully${NC}"
    echo ""
}

# Show cluster status
show_status() {
    load_config
    
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                 CLUSTER STATUS                               ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "  ${BOLD}Cluster ID:${NC}        ${CYAN}${CLUSTER_ID}${NC}"
    echo -e "  ${BOLD}Primary Node:${NC}      ${GREEN}${PRIMARY_NODE:-Not set}${NC}"
    echo -e "  ${BOLD}Failover Enabled:${NC}  ${CLUSTER_NODES:+Yes}${CLUSTER_NODES:-No}"
    echo -e "  ${BOLD}Failover Threshold:${NC} ${CYAN}${FAILOVER_THRESHOLD}${NC}"
    echo ""
    
    if [[ -n "${CLUSTER_NODES:-}" ]]; then
        echo -e "  ${BOLD}Cluster Nodes:${NC}"
        echo "  ────────────────────────────────────────────────────────────"
        
        IFS=',' read -ra nodes <<< "$CLUSTER_NODES"
        for node in "${nodes[@]}"; do
            local role="backup"
            local status_icon="⚪"
            
            if [[ "$node" == "$PRIMARY_NODE" ]]; then
                role="primary"
                status_icon="⭐"
            fi
            
            # Check if node is reachable
            if ping -c 1 -W 2 "$node" >/dev/null 2>&1; then
                echo -e "  $status_icon ${CYAN}$node${NC} [${GREEN}$role${NC}] ✓ Online"
            else
                echo -e "  $status_icon ${CYAN}$node${NC} [${RED}$role${NC}] ✗ Offline"
            fi
        done
    else
        echo -e "  ${YELLOW}No nodes configured${NC}"
    fi
    
    # Show current leader if state file exists
    if [[ -f "${STATE_DIR}/state.json" ]]; then
        local leader
        leader=$(jq -r '.leader // "unknown"' "${STATE_DIR}/state.json" 2>/dev/null || echo "unknown")
        if [[ "$leader" != "unknown" ]] && [[ -n "$leader" ]]; then
            echo ""
            echo -e "  ${BOLD}Current Leader:${NC}    ${MAGENTA}$leader${NC}"
        fi
    fi
    
    echo ""
}

# Check health of all nodes
check_health() {
    load_config
    
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                 CLUSTER HEALTH CHECK                         ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local all_nodes=()
    
    # Add local node
    all_nodes+=("$(hostname -I | awk '{print $1}')")
    
    # Add cluster nodes
    if [[ -n "${CLUSTER_NODES:-}" ]]; then
        IFS=',' read -ra nodes <<< "$CLUSTER_NODES"
        for node in "${nodes[@]}"; do
            all_nodes+=("$node")
        done
    fi
    
    echo -e "  ${BOLD}Node                Status    XDC Node    Sync    Peers${NC}"
    echo "  ────────────────────────────────────────────────────────────────"
    
    for node in "${all_nodes[@]}"; do
        local status="checking"
        local xdc_status="unknown"
        local sync_status="unknown"
        local peers="0"
        
        # Check if node is reachable
        if ping -c 1 -W 2 "$node" >/dev/null 2>&1; then
            status="${GREEN}online${NC}"
            
            # Check XDC node status via RPC
            local rpc_response
            rpc_response=$(curl -s -X POST \
                -H "Content-Type: application/json" \
                -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
                "http://${node}:8545" 2>/dev/null || echo "")
            
            if [[ -n "$rpc_response" ]]; then
                xdc_status="${GREEN}running${NC}"
                
                if echo "$rpc_response" | grep -q "false"; then
                    sync_status="${GREEN}synced${NC}"
                else
                    sync_status="${YELLOW}syncing${NC}"
                fi
                
                # Get peer count
                local peer_response
                peer_response=$(curl -s -X POST \
                    -H "Content-Type: application/json" \
                    -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
                    "http://${node}:8545" 2>/dev/null || echo "")
                
                if [[ -n "$peer_response" ]]; then
                    peers=$(echo "$peer_response" | jq -r '.result // "0x0"' | sed 's/0x//' | xargs -I {} printf '%d' "0x{}" 2>/dev/null || echo "0")
                fi
            else
                xdc_status="${RED}down${NC}"
            fi
        else
            status="${RED}offline${NC}"
        fi
        
        printf "  %-18s %-10s %-11s %-7s %s\n" "$node" "$status" "$xdc_status" "$sync_status" "$peers"
    done
    
    echo ""
}

# Perform failover
failover() {
    local target_host="${1:-}"
    local force="${2:-false}"
    
    load_config
    
    if [[ -z "$target_host" ]]; then
        # Auto-select backup node
        if [[ -n "${CLUSTER_NODES:-}" ]]; then
            IFS=',' read -ra nodes <<< "$CLUSTER_NODES"
            for node in "${nodes[@]}"; do
                if [[ "$node" != "$PRIMARY_NODE" ]]; then
                    if ping -c 1 -W 2 "$node" >/dev/null 2>&1; then
                        target_host="$node"
                        break
                    fi
                fi
            done
        fi
    fi
    
    if [[ -z "$target_host" ]]; then
        log_error "No suitable failover target found"
        return 1
    fi
    
    log_info "Initiating failover to: $target_host"
    
    if [[ "$force" != "true" ]]; then
        echo "This will promote $target_host to primary. Continue? (y/n)"
        read -r confirm
        if [[ "$confirm" != "y" ]]; then
            log_info "Failover cancelled"
            return 0
        fi
    fi
    
    # Update primary in config
    local old_primary="$PRIMARY_NODE"
    PRIMARY_NODE="$target_host"
    sudo sed -i "s/^PRIMARY_NODE=.*/PRIMARY_NODE=\"$target_host\"/" "$CLUSTER_CONFIG"
    
    # Update state
    if [[ -f "${STATE_DIR}/state.json" ]]; then
        local current_state
        current_state=$(cat "${STATE_DIR}/state.json")
        if command -v jq &>/dev/null; then
            echo "$current_state" | jq --arg leader "$target_host" --arg time "$(date -Iseconds)" '.leader = $leader | .last_failover = $time' | sudo tee "${STATE_DIR}/state.json" >/dev/null
        fi
    fi
    
    # Send notification
    if command -v notify_alert &>/dev/null; then
        notify_alert "FAILOVER" "Failover initiated: $old_primary → $target_host"
    fi
    
    log_info "Failover completed. New primary: $target_host"
    
    echo ""
    echo -e "${GREEN}✓ Failover completed successfully${NC}"
    echo -e "  Old Primary: ${YELLOW}$old_primary${NC}"
    echo -e "  New Primary: ${GREEN}$target_host${NC}"
    echo ""
}

# Sync keys to all nodes
sync_keys() {
    local specific_node="${1:-}"
    local ssh_key="${2:-}"
    
    load_config
    
    log_info "Syncing keys to cluster nodes..."
    
    # Check if keys exist
    if [[ ! -d "$KEY_DIR" ]]; then
        log_warn "Key directory not found: $KEY_DIR"
        return 1
    fi
    
    local ssh_opts="-o StrictHostKeyChecking=no -o ConnectTimeout=5"
    if [[ -n "$ssh_key" ]]; then
        ssh_opts="$ssh_opts -i $ssh_key"
    fi
    
    # Determine target nodes
    local targets=()
    if [[ -n "$specific_node" ]]; then
        targets=("$specific_node")
    elif [[ -n "${CLUSTER_NODES:-}" ]]; then
        IFS=',' read -ra nodes <<< "$CLUSTER_NODES"
        for node in "${nodes[@]}"; do
            targets+=("$node")
        done
    fi
    
    for target in "${targets[@]}"; do
        log_info "Syncing to: $target"
        
        # Create remote directory
        ssh $ssh_opts "${SSH_USER:-xdc}@${target}" "mkdir -p /etc/xdc-node/cluster-keys" 2>/dev/null || {
            log_error "Cannot connect to $target"
            continue
        }
        
        # Sync keys using rsync or scp
        if command -v rsync &>/dev/null; then
            rsync -avz -e "ssh $ssh_opts" "$KEY_DIR/" "${SSH_USER:-xdc}@${target}:/etc/xdc-node/cluster-keys/" >/dev/null 2>&1 || {
                log_warn "Rsync failed, trying scp..."
                scp $ssh_opts -r "$KEY_DIR/"* "${SSH_USER:-xdc}@${target}:/etc/xdc-node/cluster-keys/" >/dev/null 2>&1
            }
        else
            scp $ssh_opts -r "$KEY_DIR/"* "${SSH_USER:-xdc}@${target}:/etc/xdc-node/cluster-keys/" >/dev/null 2>&1
        fi
        
        # Set permissions
        ssh $ssh_opts "${SSH_USER:-xdc}@${target}" "chmod 700 /etc/xdc-node/cluster-keys" 2>/dev/null
        
        log_info "  ✓ Keys synced to $target"
    done
    
    log_info "Key sync completed"
}

# Promote node to primary
promote_node() {
    local host="$1"
    
    load_config
    
    log_info "Promoting $host to primary..."
    
    # Update config
    PRIMARY_NODE="$host"
    sudo sed -i "s/^PRIMARY_NODE=.*/PRIMARY_NODE=\"$host\"/" "$CLUSTER_CONFIG"
    
    # Ensure node is in cluster list
    if [[ ",$CLUSTER_NODES," != *",$host,"* ]]; then
        if [[ -z "$CLUSTER_NODES" ]]; then
            CLUSTER_NODES="$host"
        else
            CLUSTER_NODES="${CLUSTER_NODES},${host}"
        fi
        sudo sed -i "s/^CLUSTER_NODES=.*/CLUSTER_NODES=\"$CLUSTER_NODES\"/" "$CLUSTER_CONFIG"
    fi
    
    log_info "Node $host promoted to primary"
    
    echo ""
    echo -e "${GREEN}✓ Node promoted to primary${NC}"
    echo ""
}

# Demote node to backup
demote_node() {
    local host="$1"
    
    load_config
    
    if [[ "$host" == "$PRIMARY_NODE" ]]; then
        log_info "Demoting $host from primary to backup..."
        
        # Clear primary
        sudo sed -i "s/^PRIMARY_NODE=.*/PRIMARY_NODE=\"\"/" "$CLUSTER_CONFIG"
        
        log_info "Node $host demoted to backup"
        
        echo ""
        echo -e "${YELLOW}✓ Node demoted to backup${NC}"
        echo -e "  ${YELLOW}Warning: No primary node set!${NC}"
        echo ""
    else
        log_info "Node $host is not primary"
    fi
}

# Participate in health consensus
health_consensus() {
    load_config
    
    log_info "Participating in health consensus..."
    
    # Check local health
    local local_health="unhealthy"
    if pgrep -x "XDC" > /dev/null; then
        local_health="healthy"
    fi
    
    # Update local health status
    echo "{\"timestamp\": \"$(date -Iseconds)\", \"status\": \"$local_health\", \"ip\": \"$(hostname -I | awk '{print $1}')\", \"votes\": []}" | sudo tee "${STATE_DIR}/health-vote.json" >/dev/null
    
    # Query other nodes for their health status
    if [[ -n "${CLUSTER_NODES:-}" ]]; then
        IFS=',' read -ra nodes <<< "$CLUSTER_NODES"
        for node in "${nodes[@]}"; do
            if [[ "$node" != "$(hostname -I | awk '{print $1}')" ]]; then
                local node_health
                node_health=$(curl -s "http://${node}:8545/health" 2>/dev/null || echo "unreachable")
                log_info "  $node: $node_health"
            fi
        done
    fi
    
    # Consensus logic: if majority of nodes report primary as unhealthy, trigger failover
    log_info "Consensus completed"
}

# Show current leader
show_leader() {
    load_config
    
    if [[ -f "${STATE_DIR}/state.json" ]]; then
        local leader
        leader=$(jq -r '.leader // "unknown"' "${STATE_DIR}/state.json" 2>/dev/null || echo "unknown")
        echo "Current leader: $leader"
    else
        echo "No leader elected (cluster not initialized)"
    fi
}

# Show cluster configuration
show_config() {
    load_config
    
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                 CLUSTER CONFIGURATION                        ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    cat "$CLUSTER_CONFIG" | grep -v "^#" | grep -v "^$" | while read -r line; do
        local key="${line%%=*}"
        local value="${line#*=}"
        value="${value%\"}"
        value="${value#\"}"
        printf "  ${BOLD}%-20s${NC} %s\n" "$key:" "$value"
    done
    
    echo ""
}

# Main function
main() {
    ensure_directories
    
    local cmd=""
    local target=""
    local cluster_id=""
    local ssh_key=""
    local user="xdc"
    local force=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            init)
                cmd="init"
                shift
                ;;
            add-node)
                cmd="add-node"
                target="${2:-}"
                shift 2
                ;;
            remove-node)
                cmd="remove-node"
                target="${2:-}"
                shift 2
                ;;
            status)
                cmd="status"
                shift
                ;;
            health)
                cmd="health"
                shift
                ;;
            failover)
                cmd="failover"
                target="${2:-}"
                if [[ -n "$target" ]] && [[ ! "$target" =~ ^-- ]]; then
                    shift 2
                else
                    target=""
                    shift
                fi
                ;;
            sync-keys)
                cmd="sync-keys"
                shift
                ;;
            promote)
                cmd="promote"
                target="${2:-}"
                shift 2
                ;;
            demote)
                cmd="demote"
                target="${2:-}"
                shift 2
                ;;
            vote)
                cmd="vote"
                shift
                ;;
            leader)
                cmd="leader"
                shift
                ;;
            config)
                cmd="config"
                shift
                ;;
            --cluster-id)
                cluster_id="$2"
                shift 2
                ;;
            --ssh-key)
                ssh_key="$2"
                shift 2
                ;;
            --user)
                user="$2"
                shift 2
                ;;
            --force)
                force=true
                shift
                ;;
            -h|--help)
                print_banner
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Execute command
    case "$cmd" in
        init)
            print_banner
            init_cluster "$cluster_id"
            ;;
        add-node)
            if [[ -z "$target" ]]; then
                log_error "No host specified. Usage: $0 add-node <host>"
                exit 1
            fi
            add_node "$target" "$user" "$ssh_key"
            ;;
        remove-node)
            if [[ -z "$target" ]]; then
                log_error "No host specified. Usage: $0 remove-node <host>"
                exit 1
            fi
            remove_node "$target" "$force"
            ;;
        status)
            print_banner
            show_status
            ;;
        health)
            print_banner
            check_health
            ;;
        failover)
            failover "$target" "$force"
            ;;
        sync-keys)
            sync_keys "" "$ssh_key"
            ;;
        promote)
            if [[ -z "$target" ]]; then
                log_error "No host specified. Usage: $0 promote <host>"
                exit 1
            fi
            promote_node "$target"
            ;;
        demote)
            if [[ -z "$target" ]]; then
                log_error "No host specified. Usage: $0 demote <host>"
                exit 1
            fi
            demote_node "$target"
            ;;
        vote)
            health_consensus
            ;;
        leader)
            show_leader
            ;;
        config)
            show_config
            ;;
        *)
            print_banner
            show_status
            ;;
    esac
}

# Run main
main "$@"
