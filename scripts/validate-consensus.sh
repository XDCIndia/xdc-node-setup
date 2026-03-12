#!/bin/bash
# XDPoS 2.0 Consensus Parameter Validator

source "$(dirname "$0")/lib/logging.sh"
set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"

EPOCH_LENGTH=900
GAP_BLOCKS=450
QC_THRESHOLD=0.67
RPC_URL="${RPC_URL:-http://localhost:8545}"


validate_epoch_parameters() {
    local client_type=$1
    log_info "Validating $client_type consensus parameters..."
    
    # Get current block
    local current_block_hex=$(curl -s -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        | jq -r '.result' | sed 's/0x//')
    
    if [[ -n "$current_block_hex" ]]; then
        local block_num=$((16#$current_block_hex))
        local epoch_position=$((block_num % EPOCH_LENGTH))
        local blocks_until_epoch_end=$((EPOCH_LENGTH - epoch_position))
        
        log_info "Current block: $block_num"
        log_info "Position in epoch: $epoch_position/$EPOCH_LENGTH"
        log_info "Blocks until epoch end: $blocks_until_epoch_end"
        
        if [[ $blocks_until_epoch_end -le $GAP_BLOCKS ]]; then
            log_warn "Currently in gap period (last $GAP_BLOCKS blocks of epoch) - voting disabled"
        fi
    fi
}

check_qc_formation() {
    log_info "Checking QC formation capability..."
    
    # Check if RPC supports XDPoS methods
    local qc_check=$(curl -s -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"XDPoS_getLatestQCs","params":[],"id":1}' 2>/dev/null || echo "{}")
    
    if echo "$qc_check" | jq -e '.result' >/dev/null 2>&1; then
        local qc_count=$(echo "$qc_check" | jq '.result | length')
        log_info "QC formation active: $qc_count recent QCs found"
    else
        log_warn "XDPoS RPC methods not available or QC data unavailable"
    fi
}

main() {
    log_info "========================================"
    log_info "XDPoS 2.0 Consensus Validation"
    log_info "========================================"
    log_info "Epoch Length: $EPOCH_LENGTH blocks"
    log_info "Gap Blocks: $GAP_BLOCKS blocks"
    log_info "QC Threshold: $(echo "$QC_THRESHOLD * 100" | bc)%"
    log_info "========================================"
    
    validate_epoch_parameters "XDC"
    check_qc_formation
    
    log_info "========================================"
    log_info "Consensus validation complete"
    log_info "========================================"
}

main "$@"
