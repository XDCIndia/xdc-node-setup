#!/usr/bin/env bash
#==============================================================================
# XDC SkyNet Agent — Auto-register + push heartbeats to XDC SkyNet Platform
# 
# Usage:
#   ./skynet-agent.sh                    # Run once (heartbeat)
#   ./skynet-agent.sh --register         # Force re-registration
#   ./skynet-agent.sh --daemon           # Run as daemon (every 30s)
#   ./skynet-agent.sh --install          # Install as systemd service + cron
#
# Config: /etc/xdc-node/skynet.conf
# State:  ${XDC_STATE_DIR}/skynet.json (default: /root/xdcchain/.state/skynet.json)
#==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#==============================================================================
# Configuration
#==============================================================================
CONF_FILE="${SKYNET_CONF:-/etc/xdc-node/skynet.conf}"
XDC_STATE_DIR="${XDC_STATE_DIR:-${XDC_DATA:-/root/xdcchain}/.state}"
STATE_FILE="${SKYNET_STATE:-${XDC_STATE_DIR}/skynet.json}"
RPC_URL="${XDC_RPC_URL:-http://127.0.0.1:8545}"
SKYNET_API="${SKYNET_API_URL:-https://net.xdc.network/api/v1}"
SKYNET_API_KEY="${SKYNET_API_KEY:-}"
NODE_NAME="${NODE_NAME:-$(hostname)}"
NODE_ROLE="${NODE_ROLE:-fullnode}"
HEARTBEAT_INTERVAL=30

# Load config file if exists
if [[ -f "$CONF_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONF_FILE"
fi

# State
NODE_ID=""
API_KEY=""

#==============================================================================
# Helpers
#==============================================================================
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $1" >&2; }
err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2; }

hex_to_dec() {
    local hex="${1#0x}"
    printf '%d' "0x${hex}" 2>/dev/null || echo "0"
}

rpc_call() {
    local method=$1
    local params=${2:-"[]"}
    curl -s -m 10 -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" 2>/dev/null || echo '{}'
}

api_call() {
    local method=$1
    local endpoint=$2
    local data=${3:-}
    local auth_key="${API_KEY:-$SKYNET_API_KEY}"
    
    local args=(-s -m 15 -X "$method" "${SKYNET_API}${endpoint}" -H "Content-Type: application/json")
    [[ -n "$auth_key" ]] && args+=(-H "Authorization: Bearer ${auth_key}")
    [[ -n "$data" ]] && args+=(-d "$data")
    
    curl "${args[@]}" 2>/dev/null || echo '{"error":"connection_failed"}'
}

#==============================================================================
# State Management
#==============================================================================
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        NODE_ID=$(jq -r '.nodeId // ""' "$STATE_FILE" 2>/dev/null || echo "")
        API_KEY=$(jq -r '.apiKey // ""' "$STATE_FILE" 2>/dev/null || echo "")
    fi
}

save_state() {
    mkdir -p "$(dirname "$STATE_FILE")"
    cat > "$STATE_FILE" <<EOF
{
    "nodeId": "$NODE_ID",
    "apiKey": "$API_KEY",
    "nodeName": "$NODE_NAME",
    "registeredAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "rpcUrl": "$RPC_URL",
    "apiUrl": "$SKYNET_API"
}
EOF
    chmod 600 "$STATE_FILE"
}

#==============================================================================
# Auto-Detection
#==============================================================================
detect_node_info() {
    # Detect location via ip-api.com (free, no key needed)
    local geo
    geo=$(curl -s -m 5 "http://ip-api.com/json/?fields=city,countryCode,lat,lon,isp" 2>/dev/null || echo '{}')
    
    DETECT_CITY=$(echo "$geo" | jq -r '.city // "Unknown"')
    DETECT_COUNTRY=$(echo "$geo" | jq -r '.countryCode // "XX"')
    DETECT_LAT=$(echo "$geo" | jq -r '.lat // 0')
    DETECT_LNG=$(echo "$geo" | jq -r '.lon // 0')
    DETECT_ISP=$(echo "$geo" | jq -r '.isp // "Unknown"')
    
    # Detect client version and type
    local node_info
    node_info=$(rpc_call "admin_nodeInfo")
    DETECT_VERSION=$(echo "$node_info" | jq -r '.result.name // "Unknown"')
    DETECT_ENODE=$(echo "$node_info" | jq -r '.result.enode // ""')
    
    # Detect client type from version string
    DETECT_CLIENT_TYPE="Unknown"
    if echo "$DETECT_VERSION" | grep -qi "XDC\|XDPoS"; then
        DETECT_CLIENT_TYPE="XDC"
    elif echo "$DETECT_VERSION" | grep -qi "erigon"; then
        DETECT_CLIENT_TYPE="Erigon"
    elif echo "$DETECT_VERSION" | grep -qi "geth\|go-ethereum"; then
        DETECT_CLIENT_TYPE="Geth"
    fi
    
    # Detect OS information
    DETECT_OS_TYPE=$(uname -s)
    DETECT_OS_RELEASE=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "Unknown")
    DETECT_OS_ARCH=$(uname -m)
    DETECT_KERNEL=$(uname -r)
    
    # Get public IPs
    DETECT_IPV4=$(curl -s -4 --max-time 2 https://ifconfig.me 2>/dev/null || curl -s -4 --max-time 2 https://api.ipify.org 2>/dev/null || echo "")
    DETECT_IPV6=$(curl -s -6 --max-time 2 https://ifconfig6.me 2>/dev/null || curl -s -6 --max-time 2 https://api6.ipify.org 2>/dev/null || echo "")
    
    # Detect if masternode with detailed node type
    local coinbase
    coinbase=$(rpc_call "eth_coinbase" | jq -r '.result // "0x0"')
    DETECT_COINBASE="$coinbase"
    DETECT_IS_MASTERNODE=false
    DETECT_NODE_TYPE="fullnode"
    
    if [[ "$coinbase" != "0x0" && "$coinbase" != "0x0000000000000000000000000000000000000000" && "$coinbase" != "null" ]]; then
        # Check if coinbase is a candidate
        local is_candidate=false
        local encoded_addr="${coinbase:2}"
        while [[ ${#encoded_addr} -lt 64 ]]; do
            encoded_addr="0${encoded_addr}"
        done
        local call_data="0x2d5b6ebf${encoded_addr}"
        
        local candidate_check
        candidate_check=$(rpc_call "eth_call" "[{\"to\":\"0x0000000000000000000000000000000000000088\",\"data\":\"${call_data}\"},\"latest\"]")
        if [[ "$(echo "$candidate_check" | jq -r '.result // "0x0"')" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]; then
            is_candidate=true
        fi
        
        # Check if in active masternode set
        local mn_check
        mn_check=$(rpc_call "XDPoS_getMasternodesByNumber" '["latest"]')
        local in_active_set=false
        if echo "$mn_check" | jq -r '.result[]?' 2>/dev/null | grep -qi "${coinbase#0x}"; then
            DETECT_IS_MASTERNODE=true
            in_active_set=true
        fi
        
        # Determine node type
        if [[ "$is_candidate" == "true" ]]; then
            if [[ "$in_active_set" == "true" ]]; then
                DETECT_NODE_TYPE="masternode"
                NODE_ROLE="masternode"
            else
                DETECT_NODE_TYPE="standby"
                NODE_ROLE="standby"
            fi
        else
            DETECT_NODE_TYPE="fullnode"
        fi
    fi
    
    # Detect Docker or native
    DETECT_RUNTIME="native"
    if [[ -f /.dockerenv ]] || grep -q docker /proc/1/cgroup 2>/dev/null; then
        DETECT_RUNTIME="docker"
    elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qi xdc; then
        DETECT_RUNTIME="docker-host"
    fi
}

#==============================================================================
# Security Detection
#==============================================================================
detect_security() {
    local score=100
    local issues=""
    local warnings=""
    
    # Check SSH port
    local ssh_port=""
    if [[ -f /etc/ssh/sshd_config ]]; then
        ssh_port=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    fi
    if [[ "$ssh_port" == "22" || -z "$ssh_port" ]]; then
        score=$((score - 10))
        issues="${issues}ssh_default_port,"
        warnings="${warnings}SSH running on default port 22 — Change to non-standard port
"
    fi
    
    # Check root login
    local root_login=""
    if [[ -f /etc/ssh/sshd_config ]]; then
        root_login=$(grep -E "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    fi
    if [[ "$root_login" != "no" && "$root_login" != "prohibit-password" ]]; then
        score=$((score - 10))
        issues="${issues}root_login_enabled,"
        warnings="${warnings}Root login via SSH is enabled — Disable in /etc/ssh/sshd_config
"
    fi
    
    # Check UFW
    if ! command -v ufw &>/dev/null || ! ufw status 2>/dev/null | grep -q "Status: active"; then
        score=$((score - 15))
        issues="${issues}no_firewall,"
        warnings="${warnings}No active firewall (UFW) — Install and enable UFW
"
    else
        warnings="${warnings}✅ Firewall active (UFW)
"
    fi
    
    # Check fail2ban
    if ! systemctl is-active fail2ban &>/dev/null 2>&1 && ! service fail2ban status &>/dev/null 2>&1; then
        score=$((score - 10))
        issues="${issues}no_fail2ban,"
        warnings="${warnings}Fail2ban is not running — Install fail2ban to protect against brute force
"
    else
        warnings="${warnings}✅ Fail2ban running
"
    fi
    
    # Check unattended upgrades
    if ! dpkg -l unattended-upgrades 2>/dev/null | grep -q "^ii"; then
        score=$((score - 5))
        issues="${issues}no_auto_updates,"
        warnings="${warnings}Unattended upgrades not installed — Enable automatic security updates
"
    fi
    
    # Check RPC exposure (check common RPC ports)
    if command -v ss &>/dev/null; then
        if ss -tlnp 2>/dev/null | grep -E ":(8545|8989|30303)" | grep -q "0\.0\.0\.0"; then
            score=$((score - 15))
            issues="${issues}rpc_exposed,"
            warnings="${warnings}RPC API exposed to all interfaces (0.0.0.0) — Bind to 127.0.0.1 only
"
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tlnp 2>/dev/null | grep -E ":(8545|8989|30303)" | grep -q "0\.0\.0\.0"; then
            score=$((score - 15))
            issues="${issues}rpc_exposed,"
            warnings="${warnings}RPC API exposed to all interfaces (0.0.0.0) — Bind to 127.0.0.1 only
"
        fi
    fi
    
    # Check Docker root
    if command -v docker &>/dev/null; then
        if docker info 2>/dev/null | grep -q "Root Dir.*var/lib/docker"; then
            score=$((score - 5))
            issues="${issues}docker_root,"
            warnings="${warnings}Docker running as root — Consider rootless Docker mode
"
        fi
    fi
    
    # Trim trailing comma from issues
    issues="${issues%,}"
    
    echo "{\"score\": $score, \"issues\": \"$issues\", \"warnings\": \"$(echo -n "$warnings" | base64 -w 0)\"}"
}

#==============================================================================
# Registration
#==============================================================================
register_node() {
    log "Registering node '$NODE_NAME' with XDC SkyNet..."
    
    detect_node_info
    
    local host
    host=$(curl -s -m 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    local payload
    payload=$(cat <<EOF
{
    "name": "$NODE_NAME",
    "host": "$host",
    "role": "$NODE_ROLE",
    "rpcUrl": "$RPC_URL",
    "location": {
        "city": "$DETECT_CITY",
        "country": "$DETECT_COUNTRY",
        "lat": $DETECT_LAT,
        "lng": $DETECT_LNG
    },
    "tags": ["$DETECT_RUNTIME", "auto-registered"],
    "version": "$DETECT_VERSION",
    "clientType": "$DETECT_CLIENT_TYPE",
    "nodeType": "$DETECT_NODE_TYPE",
    "ipv4": "$DETECT_IPV4",
    "ipv6": "$DETECT_IPV6",
    "os": {
        "type": "$DETECT_OS_TYPE",
        "release": "$DETECT_OS_RELEASE",
        "arch": "$DETECT_OS_ARCH",
        "kernel": "$DETECT_KERNEL"
    },
    "coinbase": "$DETECT_COINBASE"
}
EOF
)
    
    local response
    response=$(api_call POST "/nodes/register" "$payload")
    
    if echo "$response" | jq -e '.nodeId' >/dev/null 2>&1; then
        NODE_ID=$(echo "$response" | jq -r '.nodeId')
        API_KEY=$(echo "$response" | jq -r '.apiKey')
        save_state
        log "✅ Registered! nodeId=$NODE_ID"
        return 0
    else
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error // "Unknown error"')
        err "Registration failed: $error_msg"
        
        # If node already exists, try to get existing ID
        if [[ "$error_msg" == *"already exists"* || "$error_msg" == *"duplicate"* ]]; then
            warn "Node may already be registered. Use --register to force re-registration."
        fi
        return 1
    fi
}

#==============================================================================
# Collect Metrics
#==============================================================================
collect_metrics() {
    # Block height
    local block_hex
    block_hex=$(rpc_call "eth_blockNumber" | jq -r '.result // "0x0"')
    local block_height
    block_height=$(hex_to_dec "$block_hex")
    
    # Sync status
    local sync_resp
    sync_resp=$(rpc_call "eth_syncing")
    local is_syncing=false
    local sync_progress=""
    if [[ "$(echo "$sync_resp" | jq -r '.result')" != "false" ]]; then
        is_syncing=true
        local current_block highest_block
        current_block=$(hex_to_dec "$(echo "$sync_resp" | jq -r '.result.currentBlock // "0x0"')")
        highest_block=$(hex_to_dec "$(echo "$sync_resp" | jq -r '.result.highestBlock // "0x0"')")
        if [[ "$highest_block" -gt 0 ]]; then
            sync_progress=$(awk "BEGIN {printf \"%.2f\", ($current_block / $highest_block) * 100}")
        fi
    fi
    
    # Peers
    local peers_resp
    peers_resp=$(rpc_call "admin_peers")
    local peer_count
    peer_count=$(echo "$peers_resp" | jq -r '.result | length // 0' 2>/dev/null || echo "0")
    
    # Auto-inject peers if count is 0
    if [[ "$peer_count" -eq 0 ]]; then
        log "⚠️ No peers connected — auto-injecting from SkyNet..."
        inject_peers "$RPC_URL" && {
            # Re-fetch peer count after injection
            peers_resp=$(rpc_call "admin_peers")
            peer_count=$(echo "$peers_resp" | jq -r '.result | length // 0' 2>/dev/null || echo "0")
            log "📊 Peer count after injection: $peer_count"
        } || warn "Auto-injection failed"
    fi
    
    # Build peers array
    local peers_json="[]"
    if [[ "$peer_count" -gt 0 ]]; then
        peers_json=$(echo "$peers_resp" | jq '[.result[]? | {
            enode: .enode,
            name: .name,
            remoteAddress: .network.remoteAddress,
            protocols: (.protocols | keys),
            direction: (if .network.inbound then "inbound" else "outbound" end)
        }]' 2>/dev/null || echo "[]")
    fi
    
    # TX Pool
    local txpool_resp
    txpool_resp=$(rpc_call "txpool_status")
    local tx_pending tx_queued
    tx_pending=$(hex_to_dec "$(echo "$txpool_resp" | jq -r '.result.pending // "0x0"')" 2>/dev/null || echo "0")
    tx_queued=$(hex_to_dec "$(echo "$txpool_resp" | jq -r '.result.queued // "0x0"')" 2>/dev/null || echo "0")
    
    # Gas price
    local gas_resp
    gas_resp=$(rpc_call "eth_gasPrice")
    local gas_price
    gas_price=$(echo "$gas_resp" | jq -r '.result // "0x0"')
    
    # Coinbase
    local coinbase
    coinbase=$(rpc_call "eth_coinbase" | jq -r '.result // "0x0"')
    
    # Client version
    local node_info
    node_info=$(rpc_call "admin_nodeInfo")
    local client_version
    client_version=$(echo "$node_info" | jq -r '.result.name // "Unknown"')
    
    # Detect client type from version string
    local client_type="Unknown"
    if echo "$client_version" | grep -qi "XDC\|XDPoS"; then
        client_type="XDC"
    elif echo "$client_version" | grep -qi "erigon"; then
        client_type="Erigon"
    elif echo "$client_version" | grep -qi "geth\|go-ethereum"; then
        client_type="Geth"
    fi
    
    # Get public IPv4 with timeout and fallback
    local ipv4=""
    ipv4=$(curl -s -4 --max-time 2 https://ifconfig.me 2>/dev/null || curl -s -4 --max-time 2 https://api.ipify.org 2>/dev/null || echo "")
    
    # Get public IPv6 with timeout and fallback
    local ipv6=""
    ipv6=$(curl -s -6 --max-time 2 https://ifconfig6.me 2>/dev/null || curl -s -6 --max-time 2 https://api6.ipify.org 2>/dev/null || echo "")
    
    # Get OS information
    local os_type os_release os_arch kernel
    os_type=$(uname -s)
    os_release=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "Unknown")
    os_arch=$(uname -m)
    kernel=$(uname -r)
    
    # Masternode check with detailed node type detection
    local is_masternode=false
    local node_type="fullnode"
    if [[ "$coinbase" != "0x0" && "$coinbase" != "0x0000000000000000000000000000000000000000" && "$coinbase" != "null" ]]; then
        # Check if coinbase is a candidate using XDCValidator contract
        # XDCValidator proxy: 0x0000000000000000000000000000000000000088
        local is_candidate=false
        local candidate_check
        # Encode isCandidate(address) call: 0x2d5b6ebf + padded address
        local encoded_addr="${coinbase:2}"
        while [[ ${#encoded_addr} -lt 64 ]]; do
            encoded_addr="0${encoded_addr}"
        done
        local call_data="0x2d5b6ebf${encoded_addr}"
        
        candidate_check=$(rpc_call "eth_call" "[{\"to\":\"0x0000000000000000000000000000000000000088\",\"data\":\"${call_data}\"},\"latest\"]")
        if [[ "$(echo "$candidate_check" | jq -r '.result // "0x0"')" == "0x0000000000000000000000000000000000000000000000000000000000000001" ]]; then
            is_candidate=true
        fi
        
        # Check if in active masternode set
        local mn_check
        mn_check=$(rpc_call "XDPoS_getMasternodesByNumber" '["latest"]')
        local in_active_set=false
        if echo "$mn_check" | jq -r '.result[]?' 2>/dev/null | grep -qi "${coinbase#0x}"; then
            is_masternode=true
            in_active_set=true
        fi
        
        # Determine node type
        if [[ "$is_candidate" == "true" ]]; then
            if [[ "$in_active_set" == "true" ]]; then
                node_type="masternode"
            else
                node_type="standby"
            fi
        else
            node_type="fullnode"
        fi
    fi
    
    # System resources
    local cpu_percent mem_percent disk_percent disk_used disk_total
    cpu_percent=$(awk '/^cpu /{u=$2+$4; t=$2+$3+$4+$5+$6+$7+$8; printf "%.0f", u/t*100}' /proc/stat 2>/dev/null || echo "0")
    mem_percent=$(free 2>/dev/null | awk '/Mem:/ {printf "%.1f", $3/$2*100}' || echo "0")
    disk_percent=$(df -h / 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $5}' || echo "0")
    disk_used=$(df -BG / 2>/dev/null | awk 'NR==2 {gsub(/G/,""); print $3}' || echo "0")
    disk_total=$(df -BG / 2>/dev/null | awk 'NR==2 {gsub(/G/,""); print $2}' || echo "0")
    
    # RPC latency
    local rpc_start rpc_end rpc_latency
    rpc_start=$(date +%s%N)
    rpc_call "eth_blockNumber" >/dev/null
    rpc_end=$(date +%s%N)
    rpc_latency=$(( (rpc_end - rpc_start) / 1000000 ))
    
    # Security scan
    local security_json
    security_json=$(detect_security)
    
    # Build heartbeat payload
    cat <<EOF
{
    "nodeId": "$NODE_ID",
    "blockHeight": $block_height,
    "syncing": $is_syncing,
    $( [[ -n "$sync_progress" ]] && echo "\"syncProgress\": $sync_progress," || true )
    "peerCount": $peer_count,
    "peers": $peers_json,
    "txPool": {"pending": $tx_pending, "queued": $tx_queued},
    "gasPrice": "$gas_price",
    "coinbase": "$coinbase",
    "clientVersion": "$client_version",
    "clientType": "$client_type",
    "isMasternode": $is_masternode,
    "nodeType": "$node_type",
    "ipv4": "$ipv4",
    "ipv6": "$ipv6",
    "os": {
        "type": "$os_type",
        "release": "$os_release",
        "arch": "$os_arch",
        "kernel": "$kernel"
    },
    "system": {
        "cpuPercent": $cpu_percent,
        "memoryPercent": $mem_percent,
        "diskPercent": $disk_percent,
        "diskUsedGb": $disk_used,
        "diskTotalGb": $disk_total
    },
    "security": $security_json,
    "rpcLatencyMs": $rpc_latency,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

#==============================================================================
# Write Heartbeat Status File
#==============================================================================
write_heartbeat_status() {
    local status="$1"
    local error="${2:-}"
    
    # Write status to shared file for dashboard
    cat > /tmp/skynet-heartbeat.json <<EOF
{
    "lastHeartbeat": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "status": "$status",
    "skynetUrl": "$SKYNET_API",
    "nodeId": "$NODE_ID",
    "nodeName": "$NODE_NAME",
    "error": "$error"
}
EOF
}

#==============================================================================
# Push Heartbeat
#==============================================================================
push_heartbeat() {
    local payload
    payload=$(collect_metrics)
    
    local response
    response=$(api_call POST "/nodes/heartbeat" "$payload")
    
    if echo "$response" | jq -e '.ok' >/dev/null 2>&1; then
        write_heartbeat_status "success" ""
        local commands
        commands=$(echo "$response" | jq -r '.commands[]?' 2>/dev/null)
        if [[ -n "$commands" ]]; then
            log "📋 Received commands: $commands"
            execute_commands "$commands"
        fi
        return 0
    else
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error // "Unknown error"')
        err "Heartbeat failed: $error_msg"
        write_heartbeat_status "failed" "$error_msg"
        
        # If node not found, re-register
        if [[ "$error_msg" == *"not found"* || "$error_msg" == *"NOT_FOUND"* ]]; then
            warn "Node not found, re-registering..."
            register_node && push_heartbeat
        fi
        return 1
    fi
}

#==============================================================================
# Execute Remote Commands
#==============================================================================
execute_commands() {
    local commands="$1"
    while IFS= read -r cmd; do
        case "$cmd" in
            restart)
                log "🔄 Executing restart..."
                if docker ps --format '{{.Names}}' 2>/dev/null | grep -qi xdc; then
                    docker restart "$(docker ps --format '{{.Names}}' | grep -i xdc | head -1)" &
                else
                    systemctl restart xdc-node 2>/dev/null || true
                fi
                ;;
            update)
                log "📦 Executing update..."
                if [[ -x "${SCRIPT_DIR}/version-check.sh" ]]; then
                    "${SCRIPT_DIR}/version-check.sh" --auto-update &
                fi
                ;;
        esac
    done <<< "$commands"
}

#==============================================================================
# Peer Injection
#==============================================================================
inject_peers() {
    local rpc_url="${1:-$RPC_URL}"
    local added=0
    
    # Fetch healthy peers from SkyNet API
    local peers_resp
    peers_resp=$(curl -s -f "${SKYNET_API}/peers/healthy?limit=20" 2>/dev/null || echo "")
    
    if [[ -z "$peers_resp" ]]; then
        warn "Could not fetch peers from SkyNet API"
        return 1
    fi
    
    # Parse and add each peer
    local enodes
    enodes=$(echo "$peers_resp" | jq -r '.peers[]?.enode // empty' 2>/dev/null)
    
    if [[ -z "$enodes" ]]; then
        warn "No peers returned from SkyNet API"
        return 1
    fi
    
    while IFS= read -r enode; do
        [[ -z "$enode" ]] && continue
        
        local result
        result=$(curl -s -X POST "$rpc_url" \
            -H "Content-Type: application/json" \
            -d "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addPeer\",\"params\":[\"$enode\"],\"id\":1}" 2>/dev/null | jq -r '.result // false')
        
        if [[ "$result" == "true" ]]; then
            ((added++)) || true
        fi
    done <<< "$enodes"
    
    log "✅ Added $added peers from SkyNet"
    return 0
}

#==============================================================================
# Command Queue Processing
#==============================================================================
process_commands() {
    local commands="${1:-}"
    [[ -z "$commands" ]] && return 0
    
    while IFS='|' read -r cmd arg; do
        case "$cmd" in
            restart)
                log "🔄 Restart command received"
                ;;
            update)
                log "⬆️ Update command received (version: $arg)"
                ;;
            add_peers)
                log "🔗 Adding peers from SkyNet..."
                inject_peers || warn "Peer injection failed"
                ;;
            *)
                warn "Unknown command: $cmd"
                ;;
        esac
    done <<< "$commands"
}

#==============================================================================
# Daemon Mode
#==============================================================================
run_daemon() {
    log "🚀 Starting XDC SkyNet agent daemon (interval: ${HEARTBEAT_INTERVAL}s)"
    
    # Ensure registered
    load_state
    if [[ -z "$NODE_ID" ]]; then
        register_node || { err "Failed to register. Exiting."; exit 1; }
    fi
    
    while true; do
        push_heartbeat && log "💓 Heartbeat sent (node=$NODE_ID)" || warn "Heartbeat failed"
        sleep "$HEARTBEAT_INTERVAL"
    done
}

#==============================================================================
# Install as Service
#==============================================================================
install_service() {
    log "📦 Installing XDC SkyNet agent..."
    
    # Create config and state directories
    mkdir -p /etc/xdc-node "${XDC_STATE_DIR}"
    
    # Create config if not exists
    if [[ ! -f "$CONF_FILE" ]]; then
        cat > "$CONF_FILE" <<EOF
# XDC SkyNet Agent Configuration
SKYNET_API_URL=${SKYNET_API}
SKYNET_API_KEY=${SKYNET_API_KEY}
XDC_RPC_URL=${RPC_URL}
NODE_NAME=${NODE_NAME}
NODE_ROLE=${NODE_ROLE}
HEARTBEAT_INTERVAL=30
EOF
        chmod 600 "$CONF_FILE"
        log "Created config at $CONF_FILE"
    fi
    
    # Create systemd service
    cat > /etc/systemd/system/xdc-skynet-agent.service <<EOF
[Unit]
Description=XDC SkyNet Monitoring Agent
After=network.target docker.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=${SCRIPT_DIR}/skynet-agent.sh --daemon
Restart=always
RestartSec=10
EnvironmentFile=-/etc/xdc-node/skynet.conf

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable xdc-skynet-agent
    systemctl start xdc-skynet-agent
    
    log "✅ Agent installed and started as systemd service"
    log "   Config: $CONF_FILE"
    log "   State:  $STATE_FILE"
    log "   Service: systemctl status xdc-skynet-agent"
}

#==============================================================================
# Main
#==============================================================================
main() {
    local action="${1:-heartbeat}"
    
    case "$action" in
        --register|-r)
            load_state
            register_node
            ;;
        --daemon|-d)
            run_daemon
            ;;
        --install|-i)
            load_state
            if [[ -z "$NODE_ID" ]]; then
                register_node || { err "Registration failed"; exit 1; }
            fi
            install_service
            ;;
        --status|-s)
            load_state
            if [[ -n "$NODE_ID" ]]; then
                echo "Node ID:  $NODE_ID"
                echo "API URL:  $SKYNET_API"
                echo "RPC URL:  $RPC_URL"
                echo "State:    $STATE_FILE"
                api_call GET "/nodes/${NODE_ID}/status" | jq .
            else
                echo "Not registered. Run: $0 --register"
            fi
            ;;
        --add-peers|-p)
            log "🔗 Adding peers from SkyNet API..."
            inject_peers "$RPC_URL" || { err "Failed to add peers"; exit 1; }
            ;;
        --heartbeat|heartbeat|"")
            load_state
            if [[ -z "$NODE_ID" ]]; then
                log "Not registered yet, auto-registering..."
                register_node || { 
                    err "Registration failed"
                    write_heartbeat_status "registration_failed" "Failed to register node"
                    exit 1
                }
            fi
            if push_heartbeat; then
                log "✅ Heartbeat sent"
            else
                err "Heartbeat failed"
            fi
            ;;
        --help|-h)
            echo "XDC SkyNet Agent — Monitor your XDC node"
            echo ""
            echo "Usage: $0 [option]"
            echo ""
            echo "Options:"
            echo "  (none)       Send a heartbeat (auto-registers if needed)"
            echo "  --register   Force re-registration with XDC SkyNet"
            echo "  --daemon     Run as daemon (heartbeat every ${HEARTBEAT_INTERVAL}s)"
            echo "  --install    Install as systemd service"
            echo "  --status     Show registration status"
            echo "  --add-peers  Fetch and add peers from SkyNet API"
            echo "  --help       Show this help"
            echo ""
            echo "Config: $CONF_FILE"
            echo "API:    $SKYNET_API"
            ;;
        *)
            err "Unknown option: $action"
            echo "Run '$0 --help' for usage"
            exit 1
            ;;
    esac
}

main "$@"
