#!/bin/bash
#==============================================================================
# XDC Node Owner Metrics Collector
# Collects owner-focused XDC metrics and writes them in Prometheus textfile format
# For use with node_exporter's textfile collector
# 
# Run frequency: Every 60 seconds via cron or docker sidecar
# Output: /var/lib/node_exporter/textfile_collector/xdc_owner.prom
#==============================================================================

set -euo pipefail

#==============================================================================
# Configuration (override via environment variables)
#==============================================================================
RPC_URL="${RPC_URL:-http://localhost:8545}"
DATADIR="${DATADIR:-/work/xdcchain}"
TEXTFILE_DIR="${TEXTFILE_DIR:-/var/lib/node_exporter/textfile_collector}"
METRICS_FILE="${TEXTFILE_DIR}/xdc_owner.prom"
METRICS_TMP="${METRICS_FILE}.$$"
METRICS_STATE_DIR="${TEXTFILE_DIR}/.xdc_metrics_state"
REWARD_HISTORY_FILE="${METRICS_STATE_DIR}/reward_history"
DISK_HISTORY_FILE="${METRICS_STATE_DIR}/disk_history"

# Ensure directories exist
mkdir -p "$TEXTFILE_DIR" "$METRICS_STATE_DIR"

#==============================================================================
# Helper Functions
#==============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

hex_to_dec() {
    local hex="${1#0x}"
    printf '%d' "0x${hex}" 2>/dev/null || echo "0"
}

# Format XDC value (wei to XDC with 18 decimals)
wei_to_xdc() {
    local wei="$1"
    if command -v bc >/dev/null 2>&1; then
        echo "scale=18; $wei / 1000000000000000000" | bc 2>/dev/null || echo "0"
    else
        # Fallback: divide by 10^18 using awk
        awk "BEGIN {printf \"%.18f\", $wei / 1000000000000000000}" 2>/dev/null || echo "0"
    fi
}

# RPC call helper
rpc_call() {
    local method="$1"
    local params="${2:-[]}"
    local timeout="${3:-10}"
    
    curl -s -m "$timeout" -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":${params},\"id\":1}" 2>/dev/null || echo '{}'
}

# Check if RPC is available
check_rpc() {
    local response
    response=$(rpc_call "eth_blockNumber" "[]" 5)
    echo "$response" | grep -q '"result"'
}

#==============================================================================
# Metric Collection Functions
#==============================================================================

# Get current block height
get_block_height() {
    local response
    response=$(rpc_call "eth_blockNumber")
    local hex_result
    hex_result=$(echo "$response" | jq -r '.result // "0x0"')
    hex_to_dec "$hex_result"
}

# Get highest known block (for sync progress)
get_highest_block() {
    local response
    response=$(rpc_call "eth_syncing")
    local result
    result=$(echo "$response" | jq -r '.result')
    
    if [[ "$result" == "false" ]]; then
        # Node is synced, current block is highest
        get_block_height
    else
        # Get highest block from syncing info
        local highest_hex
        highest_hex=$(echo "$result" | jq -r '.highestBlock // "0x0"')
        hex_to_dec "$highest_hex"
    fi
}

# Get syncing status details
get_syncing_info() {
    local response
    response=$(rpc_call "eth_syncing")
    local result
    result=$(echo "$response" | jq -r '.result')
    
    if [[ "$result" == "false" ]]; then
        echo "false|0|0"
    else
        local current_hex highest_hex
        current_hex=$(echo "$result" | jq -r '.currentBlock // "0x0"')
        highest_hex=$(echo "$result" | jq -r '.highestBlock // "0x0"')
        local current highest
        current=$(hex_to_dec "$current_hex")
        highest=$(hex_to_dec "$highest_hex")
        echo "true|${current}|${highest}"
    fi
}

# Get peer information
get_peer_info() {
    local response
    response=$(rpc_call "net_peerCount")
    local hex_result
    hex_result=$(echo "$response" | jq -r '.result // "0x0"')
    local total
    total=$(hex_to_dec "$hex_result")
    
    # Try to get detailed peer info for inbound/outbound counts
    local admin_peers
    admin_peers=$(rpc_call "admin_peers" "[]" 15)
    
    local inbound=0
    local outbound=0
    
    if echo "$admin_peers" | grep -q '"result"'; then
        # Count inbound vs outbound peers
        inbound=$(echo "$admin_peers" | jq '[.result[] | select(.network.remoteAddress | contains(":") and (.network.localAddress == null or .network.localAddress == ""))] | length' 2>/dev/null || echo "0")
        # Outbound = total - inbound (approximation)
        outbound=$((total - inbound))
        # Ensure non-negative
        if [[ $outbound -lt 0 ]]; then
            outbound=$total
            inbound=0
        fi
    fi
    
    echo "${total}|${inbound}|${outbound}"
}

# Get coinbase/wallet address
get_coinbase() {
    local response
    response=$(rpc_call "eth_coinbase")
    echo "$response" | jq -r '.result // "unknown"'
}

# Get node uptime (if available through RPC, otherwise use system)
get_node_uptime() {
    # Try to get from system first (for dockerized or systemd nodes)
    if [[ -f /proc/uptime ]]; then
        awk '{print int($1)}' /proc/uptime
    else
        echo "0"
    fi
}

# Get masternode status
get_masternode_status() {
    # 0=inactive, 1=active, 2=slashed
    local coinbase
    coinbase=$(get_coinbase)
    
    if [[ "$coinbase" == "unknown" || "$coinbase" == "0x0000000000000000000000000000000000000000" ]]; then
        echo "0|0|0"
        return
    fi
    
    # Get masternodes list
    local response
    response=$(rpc_call "XDPoS_getMasternodesByNumber" '["latest"]')
    
    if ! echo "$response" | grep -q '"result"'; then
        echo "0|0|0"
        return
    fi
    
    # Check if our coinbase is in the masternodes list
    local is_masternode
    is_masternode=$(echo "$response" | jq -r --arg addr "$coinbase" '.result.Masternodes[]? | select(.address == $addr) | .address' 2>/dev/null | wc -l)
    
    if [[ "$is_masternode" -gt 0 ]]; then
        local stake deposit
        stake=$(echo "$response" | jq -r --arg addr "$coinbase" '.result.Masternodes[] | select(.address == $addr) | .stake // "0"' 2>/dev/null)
        deposit=$(echo "$response" | jq -r --arg addr "$coinbase" '.result.Masternodes[] | select(.address == $addr) | .deposit // "0"' 2>/dev/null)
        
        # Convert wei to XDC
        local stake_xdc
        stake_xdc=$(wei_to_xdc "$stake")
        echo "1|${stake_xdc}|${deposit}"
    else
        echo "0|0|0"
    fi
}

# Get rewards for an address
get_rewards() {
    local address="$1"
    
    # Get balance at current block
    local response
    response=$(rpc_call "eth_getBalance" "[\"${address}\",\"latest\"]")
    local balance_hex
    balance_hex=$(echo "$response" | jq -r '.result // "0x0"')
    local balance_wei
    balance_wei=$(hex_to_dec "$balance_hex")
    
    # Get block number for historical tracking
    local block
    block=$(get_block_height)
    
    # Store history for reward calculations
    local timestamp
    timestamp=$(date +%s)
    
    # Append to history: timestamp|block|balance_wei
    echo "${timestamp}|${block}|${balance_wei}" >> "$REWARD_HISTORY_FILE"
    
    # Keep only last 30 days of history (assuming 1 entry per minute = ~43200 entries)
    if [[ -f "$REWARD_HISTORY_FILE" ]]; then
        local line_count
        line_count=$(wc -l < "$REWARD_HISTORY_FILE" 2>/dev/null || echo "0")
        if [[ "$line_count" -gt 50000 ]]; then
            tail -n 45000 "$REWARD_HISTORY_FILE" > "${REWARD_HISTORY_FILE}.tmp"
            mv "${REWARD_HISTORY_FILE}.tmp" "$REWARD_HISTORY_FILE"
        fi
    fi
    
    # Calculate rewards
    local total_rewards=0
    local rewards_24h=0
    local rewards_7d=0
    
    if [[ -f "$REWARD_HISTORY_FILE" && $(wc -l < "$REWARD_HISTORY_FILE" 2>/dev/null || echo "0") -gt 1 ]]; then
        # Get first recorded balance (oldest)
        local first_balance
        first_balance=$(head -1 "$REWARD_HISTORY_FILE" | cut -d'|' -f3)
        
        # Total rewards = current - first recorded (if first was 0, use current as approximation)
        if command -v bc >/dev/null 2>&1; then
            total_rewards=$(echo "scale=18; ($balance_wei - $first_balance) / 1000000000000000000" | bc 2>/dev/null || echo "0")
            if [[ $(echo "$total_rewards < 0" | bc 2>/dev/null) -eq 1 ]]; then
                total_rewards="0"
            fi
        else
            total_rewards=$(wei_to_xdc "$balance_wei")
        fi
        
        # Calculate 24h and 7d rewards
        local cutoff_24h cutoff_7d
        cutoff_24h=$((timestamp - 86400))
        cutoff_7d=$((timestamp - 604800))
        
        local balance_24h_ago balance_7d_ago
        balance_24h_ago=$(awk -F'|' -v cutoff="$cutoff_24h" '$1 >= cutoff {print $3; exit}' "$REWARD_HISTORY_FILE" 2>/dev/null || echo "$balance_wei")
        balance_7d_ago=$(awk -F'|' -v cutoff="$cutoff_7d" '$1 >= cutoff {print $3; exit}' "$REWARD_HISTORY_FILE" 2>/dev/null || echo "$balance_wei")
        
        if command -v bc >/dev/null 2>&1; then
            rewards_24h=$(echo "scale=18; ($balance_wei - $balance_24h_ago) / 1000000000000000000" | bc 2>/dev/null || echo "0")
            rewards_7d=$(echo "scale=18; ($balance_wei - $balance_7d_ago) / 1000000000000000000" | bc 2>/dev/null || echo "0")
            
            if [[ $(echo "$rewards_24h < 0" | bc 2>/dev/null) -eq 1 ]]; then rewards_24h="0"; fi
            if [[ $(echo "$rewards_7d < 0" | bc 2>/dev/null) -eq 1 ]]; then rewards_7d="0"; fi
        fi
    fi
    
    # Estimate monthly earnings based on 7-day average
    local monthly_estimate=0
    if command -v bc >/dev/null 2>&1 && [[ $(echo "$rewards_7d > 0" | bc 2>/dev/null) -eq 1 ]]; then
        monthly_estimate=$(echo "scale=2; $rewards_7d / 7 * 30" | bc 2>/dev/null || echo "0")
    fi
    
    local balance_xdc
    balance_xdc=$(wei_to_xdc "$balance_wei")
    
    echo "${balance_xdc}|${total_rewards}|${rewards_24h}|${rewards_7d}|${monthly_estimate}"
}

# Calculate epoch info
calculate_epoch_info() {
    local block="$1"
    local epoch=$((block / 900))
    local epoch_block=$((block % 900))
    local progress
    progress=$(awk "BEGIN {printf \"%.2f\", ($epoch_block / 900) * 100}")
    echo "${epoch}|${progress}"
}

# Get signing rate (requires masternode participation tracking)
get_signing_rate() {
    local coinbase="$1"
    
    # This would require tracking blocks signed over time
    # For now, return -1 to indicate not available
    # In production, this would query historical data or use XDPoS APIs
    echo "-1"
}

# Get penalty count
get_penalty_count() {
    local coinbase="$1"
    
    # Try to get penalties from XDPoS API
    local response
    response=$(rpc_call "XDPoS_getPendingPenalties" '["latest"]')
    
    if echo "$response" | grep -q '"result"'; then
        local penalties
        penalties=$(echo "$response" | jq --arg addr "$coinbase" '[.result[]? | select(contains($addr))] | length' 2>/dev/null || echo "0")
        echo "$penalties"
    else
        echo "0"
    fi
}

# Get chain data size
get_chain_data_size() {
    local datadir="$1"
    
    if [[ -d "$datadir" ]]; then
        # Get size in bytes
        du -sb "$datadir" 2>/dev/null | cut -f1 || echo "0"
    else
        # Try docker volume or default location
        if [[ -d /work/xdcchain ]]; then
            du -sb /work/xdcchain 2>/dev/null | cut -f1 || echo "0"
        else
            echo "0"
        fi
    fi
}

# Calculate disk growth rate and days until full
calculate_disk_growth() {
    local current_size="$1"
    local timestamp
    timestamp=$(date +%s)
    
    # Store history
    echo "${timestamp}|${current_size}" >> "$DISK_HISTORY_FILE"
    
    # Keep last 7 days of disk history
    local cutoff
    cutoff=$((timestamp - 604800))
    if [[ -f "$DISK_HISTORY_FILE" ]]; then
        awk -F'|' -v cutoff="$cutoff" '$1 >= cutoff' "$DISK_HISTORY_FILE" > "${DISK_HISTORY_FILE}.tmp" 2>/dev/null
        mv "${DISK_HISTORY_FILE}.tmp" "$DISK_HISTORY_FILE" 2>/dev/null || true
    fi
    
    local growth_rate=0
    local days_until_full=-1
    
    if [[ -f "$DISK_HISTORY_FILE" && $(wc -l < "$DISK_HISTORY_FILE" 2>/dev/null || echo "0") -gt 1 ]]; then
        # Calculate growth rate (bytes per day)
        local first_ts first_size last_ts last_size
        first_ts=$(head -1 "$DISK_HISTORY_FILE" | cut -d'|' -f1)
        first_size=$(head -1 "$DISK_HISTORY_FILE" | cut -d'|' -f2)
        last_ts=$(tail -1 "$DISK_HISTORY_FILE" | cut -d'|' -f1)
        last_size=$(tail -1 "$DISK_HISTORY_FILE" | cut -d'|' -f2)
        
        local time_diff=$((last_ts - first_ts))
        if [[ $time_diff -gt 3600 ]]; then # At least 1 hour of data
            local size_diff=$((last_size - first_size))
            if [[ $size_diff -gt 0 ]]; then
                growth_rate=$(awk "BEGIN {printf \"%.2f\", ($size_diff / $time_diff) * 86400}")
                
                # Calculate days until full
                local disk_total disk_avail
                disk_total=$(df -B1 "$DATADIR" 2>/dev/null | tail -1 | awk '{print $2}' || echo "0")
                disk_avail=$(df -B1 "$DATADIR" 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
                
                if [[ $(echo "$growth_rate > 0" | bc 2>/dev/null) -eq 1 && "$disk_avail" -gt 0 ]]; then
                    days_until_full=$(awk "BEGIN {printf \"%.0f\", $disk_avail / ($growth_rate / 86400 * 86400)}")
                fi
            fi
        fi
    fi
    
    echo "${growth_rate}|${days_until_full}"
}

#==============================================================================
# Main Collection Logic
#==============================================================================

main() {
    # Check if RPC is available
    if ! check_rpc; then
        log "WARNING: XDC RPC not available at $RPC_URL - writing error metrics"
        
        cat > "$METRICS_TMP" << 'EOF'
# HELP xdc_node_up Whether the XDC node RPC is accessible (1=up, 0=down)
# TYPE xdc_node_up gauge
xdc_node_up 0
# HELP xdc_metrics_collection_timestamp Last collection attempt timestamp
# TYPE xdc_metrics_collection_timestamp gauge
EOF
        echo "xdc_metrics_collection_timestamp $(date +%s)" >> "$METRICS_TMP"
        mv "$METRICS_TMP" "$METRICS_FILE"
        exit 0
    fi
    
    # Collect all metrics
    local BLOCK_HEIGHT SYNC_INFO SYNCING CURRENT_BLOCK HIGHEST_BLOCK SYNC_PERCENT
    local PEER_INFO PEER_COUNT PEER_INBOUND PEER_OUTBOUND
    local COINBASE UPTIME
    local MN_STATUS MN_STAKE MN_DEPOSIT
    local REWARD_INFO BALANCE TOTAL_REWARDS REWARDS_24H REWARDS_7D MONTHLY_EST
    local EPOCH_INFO EPOCH_NUMBER EPOCH_PROGRESS
    local SIGNING_RATE PENALTIES
    local CHAIN_SIZE GROWTH_INFO GROWTH_RATE DAYS_UNTIL_FULL
    
    BLOCK_HEIGHT=$(get_block_height)
    SYNC_INFO=$(get_syncing_info)
    SYNCING=$([[ "${SYNC_INFO%%|*}" == "true" ]] && echo "1" || echo "0")
    CURRENT_BLOCK=$(echo "$SYNC_INFO" | cut -d'|' -f2)
    HIGHEST_BLOCK=$(echo "$SYNC_INFO" | cut -d'|' -f3)
    
    # Calculate sync percentage
    if [[ "$HIGHEST_BLOCK" -gt 0 ]]; then
        SYNC_PERCENT=$(awk "BEGIN {printf \"%.2f\", ($CURRENT_BLOCK / $HIGHEST_BLOCK) * 100}")
    else
        SYNC_PERCENT="100.00"
    fi
    
    # Peer info
    PEER_INFO=$(get_peer_info)
    PEER_COUNT=$(echo "$PEER_INFO" | cut -d'|' -f1)
    PEER_INBOUND=$(echo "$PEER_INFO" | cut -d'|' -f2)
    PEER_OUTBOUND=$(echo "$PEER_INFO" | cut -d'|' -f3)
    
    # Node info
    COINBASE=$(get_coinbase)
    UPTIME=$(get_node_uptime)
    
    # Masternode info
    MN_INFO=$(get_masternode_status)
    MN_STATUS=$(echo "$MN_INFO" | cut -d'|' -f1)
    MN_STAKE=$(echo "$MN_INFO" | cut -d'|' -f2)
    MN_DEPOSIT=$(echo "$MN_INFO" | cut -d'|' -f3)
    
    # Rewards (only if we have a valid coinbase)
    if [[ "$COINBASE" != "unknown" && "$COINBASE" != "0x0000000000000000000000000000000000000000" ]]; then
        REWARD_INFO=$(get_rewards "$COINBASE")
        BALANCE=$(echo "$REWARD_INFO" | cut -d'|' -f1)
        TOTAL_REWARDS=$(echo "$REWARD_INFO" | cut -d'|' -f2)
        REWARDS_24H=$(echo "$REWARD_INFO" | cut -d'|' -f3)
        REWARDS_7D=$(echo "$REWARD_INFO" | cut -d'|' -f4)
        MONTHLY_EST=$(echo "$REWARD_INFO" | cut -d'|' -f5)
    else
        BALANCE="0"
        TOTAL_REWARDS="0"
        REWARDS_24H="0"
        REWARDS_7D="0"
        MONTHLY_EST="0"
    fi
    
    # Epoch info
    EPOCH_INFO=$(calculate_epoch_info "$BLOCK_HEIGHT")
    EPOCH_NUMBER=$(echo "$EPOCH_INFO" | cut -d'|' -f1)
    EPOCH_PROGRESS=$(echo "$EPOCH_INFO" | cut -d'|' -f2)
    
    # Signing rate and penalties
    SIGNING_RATE=$(get_signing_rate "$COINBASE")
    PENALTIES=$(get_penalty_count "$COINBASE")
    
    # Chain data
    CHAIN_SIZE=$(get_chain_data_size "$DATADIR")
    GROWTH_INFO=$(calculate_disk_growth "$CHAIN_SIZE")
    GROWTH_RATE=$(echo "$GROWTH_INFO" | cut -d'|' -f1)
    DAYS_UNTIL_FULL=$(echo "$GROWTH_INFO" | cut -d'|' -f2)
    
    # Timestamp
    local TIMESTAMP
    TIMESTAMP=$(date +%s)
    
    # Write metrics file
    cat > "$METRICS_TMP" << EOF
# HELP xdc_node_up Whether the XDC node RPC is accessible (1=up, 0=down)
# TYPE xdc_node_up gauge
xdc_node_up 1

# HELP xdc_node_block_height Current block height
# TYPE xdc_node_block_height gauge
xdc_node_block_height ${BLOCK_HEIGHT}

# HELP xdc_node_highest_block Highest known block for sync
# TYPE xdc_node_highest_block gauge
xdc_node_highest_block ${HIGHEST_BLOCK}

# HELP xdc_node_sync_percent Sync progress percentage (0-100)
# TYPE xdc_node_sync_percent gauge
xdc_node_sync_percent ${SYNC_PERCENT}

# HELP xdc_node_peer_count Total number of connected peers
# TYPE xdc_node_peer_count gauge
xdc_node_peer_count ${PEER_COUNT}

# HELP xdc_node_peer_inbound Number of inbound peer connections
# TYPE xdc_node_peer_inbound gauge
xdc_node_peer_inbound ${PEER_INBOUND}

# HELP xdc_node_peer_outbound Number of outbound peer connections
# TYPE xdc_node_peer_outbound gauge
xdc_node_peer_outbound ${PEER_OUTBOUND}

# HELP xdc_node_is_syncing Whether node is currently syncing (1=yes, 0=no)
# TYPE xdc_node_is_syncing gauge
xdc_node_is_syncing ${SYNCING}

# HELP xdc_node_uptime_seconds Node uptime in seconds
# TYPE xdc_node_uptime_seconds gauge
xdc_node_uptime_seconds ${UPTIME}

# HELP xdc_node_coinbase Node coinbase/wallet address
# TYPE xdc_node_coinbase gauge
xdc_node_coinbase{address="${COINBASE}"} 1

# HELP xdc_masternode_status Masternode status (0=inactive, 1=active, 2=slashed)
# TYPE xdc_masternode_status gauge
xdc_masternode_status ${MN_STATUS}

# HELP xdc_masternode_stake_xdc Masternode stake amount in XDC
# TYPE xdc_masternode_stake_xdc gauge
xdc_masternode_stake_xdc ${MN_STAKE}

# HELP xdc_masternode_deposit_xdc Masternode deposit amount in XDC
# TYPE xdc_masternode_deposit_xdc gauge
xdc_masternode_deposit_xdc ${MN_DEPOSIT}

# HELP xdc_masternode_rewards_total Total rewards earned in XDC
# TYPE xdc_masternode_rewards_total gauge
xdc_masternode_rewards_total ${TOTAL_REWARDS}

# HELP xdc_masternode_rewards_24h Rewards earned in last 24h in XDC
# TYPE xdc_masternode_rewards_24h gauge
xdc_masternode_rewards_24h ${REWARDS_24H}

# HELP xdc_masternode_rewards_7d Rewards earned in last 7 days in XDC
# TYPE xdc_masternode_rewards_7d gauge
xdc_masternode_rewards_7d ${REWARDS_7D}

# HELP xdc_masternode_rewards_monthly_estimate Estimated monthly rewards in XDC
# TYPE xdc_masternode_rewards_monthly_estimate gauge
xdc_masternode_rewards_monthly_estimate ${MONTHLY_EST}

# HELP xdc_masternode_balance_xdc Current wallet balance in XDC
# TYPE xdc_masternode_balance_xdc gauge
xdc_masternode_balance_xdc ${BALANCE}

# HELP xdc_masternode_signing_rate Block signing rate percentage (0-100)
# TYPE xdc_masternode_signing_rate gauge
xdc_masternode_signing_rate ${SIGNING_RATE}

# HELP xdc_masternode_penalties Number of penalties incurred
# TYPE xdc_masternode_penalties gauge
xdc_masternode_penalties ${PENALTIES}

# HELP xdc_chain_epoch_number Current epoch number
# TYPE xdc_chain_epoch_number gauge
xdc_chain_epoch_number ${EPOCH_NUMBER}

# HELP xdc_chain_epoch_progress Epoch progress percentage (0-100)
# TYPE xdc_chain_epoch_progress gauge
xdc_chain_epoch_progress ${EPOCH_PROGRESS}

# HELP xdc_node_disk_chain_bytes Chain data size in bytes
# TYPE xdc_node_disk_chain_bytes gauge
xdc_node_disk_chain_bytes ${CHAIN_SIZE}

# HELP xdc_node_disk_growth_rate_bytes_daily Chain data growth rate in bytes per day
# TYPE xdc_node_disk_growth_rate_bytes_daily gauge
xdc_node_disk_growth_rate_bytes_daily ${GROWTH_RATE}

# HELP xdc_node_disk_days_until_full Estimated days until disk full (-1 if unknown)
# TYPE xdc_node_disk_days_until_full gauge
xdc_node_disk_days_until_full ${DAYS_UNTIL_FULL}

# HELP xdc_metrics_collection_timestamp Last successful collection timestamp
# TYPE xdc_metrics_collection_timestamp gauge
xdc_metrics_collection_timestamp ${TIMESTAMP}
EOF

    # Atomically move temp file to final location
    mv "$METRICS_TMP" "$METRICS_FILE"
    
    log "Metrics collected: block=${BLOCK_HEIGHT}, sync=${SYNC_PERCENT}%, peers=${PEER_COUNT}, masternode=${MN_STATUS}"
}

# Run main function
main "$@"
