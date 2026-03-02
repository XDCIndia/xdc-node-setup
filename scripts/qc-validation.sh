#!/bin/bash
# QC (Quorum Certificate) Validation Script for XDPoS 2.0
# Validates that blocks have proper QC signatures (2/3+ of 108 masternodes)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || true

# Configuration
RPC_URL="${RPC_URL:-http://localhost:8545}"
REQUIRED_SIGNATURES=73  # 2/3 of 108 masternodes
ALERT_THRESHOLD=5       # Alert if QC failures exceed this count

# State
QC_FAILURES=0
LAST_CHECKED_BLOCK=0

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Get current block number
get_block_number() {
    curl -s "$RPC_URL" -X POST -H 'Content-Type: application/json' \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        | jq -r '.result' | xargs printf '%d\n' 2>/dev/null || echo "0"
}

# Get block by number
get_block() {
    local block_num=$1
    local hex_block=$(printf "0x%x" "$block_num")
    
    curl -s "$RPC_URL" -X POST -H 'Content-Type: application/json' \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$hex_block\",false],\"id\":1}" \
        | jq -r '.result'
}

# Extract QC signature count from extraData
# XDPoS 2.0 block extraData structure:
# - Bytes 0-31: Vanity
# - Bytes 32-63: Validators bitmask
# - Bytes 64+: Signatures (65 bytes each)
validate_qc() {
    local block_data=$1
    local block_number=$2
    
    # Extract extraData
    local extra_data=$(echo "$block_data" | jq -r '.extraData // "0x"')
    
    # Check if we have enough data
    local extra_len=${#extra_data}
    if [[ $extra_len -lt 130 ]]; then
        error "Block $block_number: extraData too short ($extra_len bytes)"
        return 1
    fi
    
    # Extract validator bitmask (bytes 32-63)
    local validator_mask=${extra_data:66:64}
    
    # Count set bits in validator mask (number of validators who signed)
    local sign_count=0
    for ((i=0; i<${#validator_mask}; i+=2)); do
        local byte="${validator_mask:$i:2}"
        if [[ "$byte" != "00" ]]; then
            local decimal=$((16#$byte))
            # Count bits
            while [[ $decimal -gt 0 ]]; do
                ((sign_count += decimal & 1))
                ((decimal >>= 1))
            done
        fi
    done
    
    # Validate signature count
    if [[ $sign_count -ge $REQUIRED_SIGNATURES ]]; then
        log "Block $block_number: QC valid ($sign_count/$REQUIRED_SIGNATURES signatures)"
        return 0
    else
        error "Block $block_number: QC INVALID ($sign_count/$REQUIRED_SIGNATURES signatures)"
        ((QC_FAILURES++))
        
        # Send alert if threshold exceeded
        if [[ $QC_FAILURES -ge $ALERT_THRESHOLD ]]; then
            send_alert "CRITICAL" "QC validation failures: $QC_FAILURES blocks with insufficient signatures"
        fi
        
        return 1
    fi
}

# Send alert (integrate with SkyNet)
send_alert() {
    local severity=$1
    local message=$2
    
    log "ALERT [$severity]: $message"
    
    # Send to SkyNet if configured
    if [[ -n "${SKYNET_ENDPOINT:-}" ]]; then
        curl -s -X POST "$SKYNET_ENDPOINT/api/v1/alerts" \
            -H 'Content-Type: application/json' \
            -d "{
                \"severity\": \"$severity\",
                \"type\": \"qc_validation\",
                \"message\": \"$message\",
                \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
            }" || true
    fi
}

# Main validation loop
main() {
    log "Starting QC validation monitor..."
    log "RPC: $RPC_URL"
    log "Required signatures: $REQUIRED_SIGNATURES (2/3 of 108 masternodes)"
    
    while true; do
        current_block=$(get_block_number)
        
        if [[ $current_block -eq 0 ]]; then
            error "Failed to get current block number"
            sleep 30
            continue
        fi
        
        # Validate blocks since last check
        if [[ $LAST_CHECKED_BLOCK -eq 0 ]]; then
            LAST_CHECKED_BLOCK=$((current_block - 1))
        fi
        
        for ((block=$LAST_CHECKED_BLOCK+1; block<=current_block; block++)); do
            block_data=$(get_block "$block")
            
            if [[ -n "$block_data" ]] && [[ "$block_data" != "null" ]]; then
                validate_qc "$block_data" "$block"
            fi
        done
        
        LAST_CHECKED_BLOCK=$current_block
        
        # Sleep before next check
        sleep 30
    done
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
