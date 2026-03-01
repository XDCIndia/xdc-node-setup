#!/bin/bash
# Gap Block Monitor for XDPoS 2.0
# Detects and validates gap blocks every 900 blocks
# Issue #404

set -euo pipefail

EPOCH_LENGTH=900
RPC_URL="${RPC_URL:-http://localhost:8545}"
LOG_FILE="${LOG_FILE:-/var/log/xdc-node/gap-blocks.log}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Get current block number
get_current_block() {
    curl -s -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | \
        jq -r '.result' | sed 's/0x//' | xargs -I{} printf '%d' "0x{}"
}

# Get block data
get_block_data() {
    local block_number=$1
    local hex_block=$(printf '0x%x' "$block_number")
    
    curl -s -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$hex_block\", false],\"id\":1}"
}

# Check if block is a gap block
is_gap_block() {
    local block_number=$1
    local epoch_position=$((block_number % EPOCH_LENGTH))
    
    if [ $epoch_position -eq 0 ]; then
        return 0  # Is gap block
    else
        return 1  # Not gap block
    fi
}

# Validate gap block
validate_gap_block() {
    local block_number=$1
    local block_data=$2
    
    # Extract transaction count
    local tx_count=$(echo "$block_data" | jq -r '.result.transactions | length')
    
    # Gap blocks should have no transactions
    if [ "$tx_count" -ne 0 ]; then
        log "ERROR: Gap block $block_number contains $tx_count transactions!"
        return 1
    fi
    
    # Extract and validate extraData
    local extra_data=$(echo "$block_data" | jq -r '.result.extraData')
    local epoch=$((block_number / EPOCH_LENGTH))
    
    log "INFO: Gap block $block_number validated for epoch $epoch (txs: $tx_count)"
    return 0
}

# Monitor gap blocks
monitor_gap_blocks() {
    log "Starting gap block monitoring..."
    
    local current_block=$(get_current_block)
    log "Current block: $current_block"
    
    # Check if current block is a gap block
    if is_gap_block "$current_block"; then
        local block_data=$(get_block_data "$current_block")
        
        if validate_gap_block "$current_block" "$block_data"; then
            echo "Gap block $current_block is valid"
        else
            echo "Gap block $current_block validation FAILED" >&2
            exit 1
        fi
    else
        # Calculate blocks until next gap block
        local blocks_to_gap=$((EPOCH_LENGTH - (current_block % EPOCH_LENGTH)))
        log "INFO: $blocks_to_gap blocks until next gap block"
    fi
}

# Main execution
main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    
    if [ "${1:-}" = "--continuous" ]; then
        while true; do
            monitor_gap_blocks || true
            sleep 30
        done
    else
        monitor_gap_blocks
    fi
}

main "$@"
