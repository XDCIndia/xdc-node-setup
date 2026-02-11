#!/usr/bin/env bash
#==============================================================================
# XDC Node Metrics Collector
# Collects XDC-specific metrics and writes them in Prometheus textfile format
# For use with node_exporter's textfile collector
#==============================================================================

set -euo pipefail

# Configuration (override via environment variables)
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
TEXTFILE_DIR="${TEXTFILE_DIR:-/var/lib/node_exporter/textfile_collector}"
METRICS_FILE="${TEXTFILE_DIR}/xdc_metrics.prom"
METRICS_TMP="${METRICS_FILE}.$$"

# Ensure textfile directory exists
mkdir -p "$TEXTFILE_DIR"

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

# Check if RPC is available
check_rpc() {
    local response
    response=$(curl -s -m 5 -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null || echo '{}')
    
    if echo "$response" | grep -q '"result"'; then
        return 0
    fi
    return 1
}

# Get block number
get_block_number() {
    local response
    response=$(curl -s -m 10 -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null || echo '{"result":"0x0"}')
    
    local hex_result
    hex_result=$(echo "$response" | jq -r '.result // "0x0"')
    hex_to_dec "$hex_result"
}

# Get peer count
get_peer_count() {
    local response
    response=$(curl -s -m 10 -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null || echo '{"result":"0x0"}')
    
    local hex_result
    hex_result=$(echo "$response" | jq -r '.result // "0x0"')
    hex_to_dec "$hex_result"
}

# Get syncing status (0 = synced, 1 = syncing)
get_syncing_status() {
    local response
    response=$(curl -s -m 10 -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' 2>/dev/null || echo '{"result":false}')
    
    local result
    result=$(echo "$response" | jq -r '.result')
    
    if [[ "$result" == "false" ]]; then
        echo "0"
    else
        echo "1"
    fi
}

# Get chain ID
get_chain_id() {
    local response
    response=$(curl -s -m 10 -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null || echo '{"result":"0x0"}')
    
    local hex_result
    hex_result=$(echo "$response" | jq -r '.result // "0x0"')
    hex_to_dec "$hex_result"
}

# Get client version
get_client_version() {
    local response
    response=$(curl -s -m 10 -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' 2>/dev/null || echo '{"result":"unknown"}')
    
    echo "$response" | jq -r '.result // "unknown"'
}

# Get block by number to extract timestamp
get_block_timestamp() {
    local block_hex="$1"
    local response
    response=$(curl -s -m 10 -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${block_hex}\",false],\"id\":1}" 2>/dev/null || echo '{}')
    
    local ts_hex
    ts_hex=$(echo "$response" | jq -r '.result.timestamp // "0x0"')
    hex_to_dec "$ts_hex"
}

# Calculate epoch number (XDC: 1 epoch = 900 blocks)
calculate_epoch() {
    local block="$1"
    echo $((block / 900))
}

# Calculate epoch progress (0-100)
calculate_epoch_progress() {
    local block="$1"
    local epoch_block=$((block % 900))
    awk "BEGIN {printf \"%.2f\", ($epoch_block / 900) * 100}"
}

# Get masternode info if available (requires XDPoS API)
get_masternode_info() {
    local response
    response=$(curl -s -m 10 -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"XDPoS_getMasternodesByNumber","params":["latest"],"id":1}' 2>/dev/null || echo '{}')
    
    echo "$response"
}

#==============================================================================
# Main Collection Logic
#==============================================================================

main() {
    # Check if RPC is available
    if ! check_rpc; then
        log "ERROR: XDC RPC not available at $RPC_URL"
        
        # Write minimal metrics showing node is down
        cat > "$METRICS_TMP" << EOF
# HELP xdc_metrics_collection_failed Whether metrics collection failed
# TYPE xdc_metrics_collection_failed gauge
xdc_metrics_collection_failed 1
# HELP xdc_metrics_last_attempt_timestamp Last attempt timestamp
# TYPE xdc_metrics_last_attempt_timestamp gauge
xdc_metrics_last_attempt_timestamp $(date +%s)
EOF
        mv "$METRICS_TMP" "$METRICS_FILE"
        exit 1
    fi
    
    # Collect metrics
    local BLOCK_NUMBER PEER_COUNT SYNCING CHAIN_ID CLIENT_VERSION EPOCH EPOCH_PROGRESS
    
    BLOCK_NUMBER=$(get_block_number)
    PEER_COUNT=$(get_peer_count)
    SYNCING=$(get_syncing_status)
    CHAIN_ID=$(get_chain_id)
    CLIENT_VERSION=$(get_client_version)
    EPOCH=$(calculate_epoch "$BLOCK_NUMBER")
    EPOCH_PROGRESS=$(calculate_epoch_progress "$BLOCK_NUMBER")
    
    # Get current timestamp
    local TIMESTAMP
    TIMESTAMP=$(date +%s)
    
    # Get block timestamp for calculating block time
    local BLOCK_TIMESTAMP CURRENT_TIME AVG_BLOCK_TIME
    CURRENT_TIME=$(date +%s)
    BLOCK_TIMESTAMP=$(get_block_timestamp "0x$(printf '%x' $BLOCK_NUMBER)")
    
    # Estimate average block time (2 seconds for XDC, but calculate from recent blocks if possible)
    AVG_BLOCK_TIME="2.0"
    
    # Sanitize client version for labels
    CLIENT_VERSION_CLEAN=$(echo "$CLIENT_VERSION" | tr ' "\\' '_' | cut -c1-50)
    
    # Write metrics file
    cat > "$METRICS_TMP" << EOF
# HELP xdc_block_number Current block number
# TYPE xdc_block_number gauge
xdc_block_number{chain_id="${CHAIN_ID}",client_version="${CLIENT_VERSION_CLEAN}"} ${BLOCK_NUMBER}

# HELP xdc_peer_count Number of connected peers
# TYPE xdc_peer_count gauge
xdc_peer_count{chain_id="${CHAIN_ID}"} ${PEER_COUNT}

# HELP xdc_syncing Whether the node is syncing (0=synced, 1=syncing)
# TYPE xdc_syncing gauge
xdc_syncing{chain_id="${CHAIN_ID}"} ${SYNCING}

# HELP xdc_epoch_number Current epoch number (XDC: 900 blocks per epoch)
# TYPE xdc_epoch_number gauge
xdc_epoch_number{chain_id="${CHAIN_ID}"} ${EPOCH}

# HELP xdc_epoch_progress Epoch progress percentage (0-100)
# TYPE xdc_epoch_progress gauge
xdc_epoch_progress{chain_id="${CHAIN_ID}"} ${EPOCH_PROGRESS}

# HELP xdc_chain_id Chain ID
# TYPE xdc_chain_id gauge
xdc_chain_id ${CHAIN_ID}

# HELP xdc_client_version Client version as label
# TYPE xdc_client_version gauge
xdc_client_version{version="${CLIENT_VERSION_CLEAN}"} 1

# HELP xdc_avg_block_time Average block time in seconds
# TYPE xdc_avg_block_time gauge
xdc_avg_block_time{chain_id="${CHAIN_ID}"} ${AVG_BLOCK_TIME}

# HELP xdc_metrics_last_collection_timestamp Last successful collection timestamp
# TYPE xdc_metrics_last_collection_timestamp gauge
xdc_metrics_last_collection_timestamp ${TIMESTAMP}

# HELP xdc_metrics_collection_failed Whether metrics collection failed
# TYPE xdc_metrics_collection_failed gauge
xdc_metrics_collection_failed 0
EOF
    
    # Atomically move temp file to final location
    mv "$METRICS_TMP" "$METRICS_FILE"
    
    log "Metrics collected: block=${BLOCK_NUMBER}, epoch=${EPOCH}, peers=${PEER_COUNT}, syncing=${SYNCING}"
}

# Run main function
main "$@"
