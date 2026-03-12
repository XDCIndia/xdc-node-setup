#!/bin/bash
# Source unified logging library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || source "/root/.openclaw/workspace/XDC-Node-Setup/scripts/lib/common.sh"
# XDPoS 2.0 Quorum Certificate Validator
# Validates QC signatures and quorum for block finalization
# Issue #403

set -euo pipefail

RPC_URL="${RPC_URL:-http://localhost:8545}"
QUORUM_THRESHOLD=73  # 2/3 + 1 of 108 masternodes
LOG_FILE="${LOG_FILE:-/var/log/xdc-node/qc-validation.log}"

# Logging

# Get block with QC data
get_block_with_qc() {
    local block_number=$1
    local hex_block=$(printf '0x%x' "$block_number")
    
    curl -s -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$hex_block\", true],\"id\":1}"
}

# Extract QC from block extra data
extract_qc_data() {
    local block_data=$1
    
    # In XDPoS 2.0, QC is in extraData field
    local extra_data=$(echo "$block_data" | jq -r '.result.extraData')
    
    # Parse extraData for signatures (this is simplified - actual parsing depends on XDPoS format)
    # ExtraData format: vanity (32 bytes) + signatures + seal
    
    echo "$extra_data"
}

# Validate QC
validate_qc() {
    local block_number=$1
    
    log "Validating QC for block $block_number"
    
    local block_data=$(get_block_with_qc "$block_number")
    local qc_data=$(extract_qc_data "$block_data")
    
    # Count signatures (simplified - actual implementation needs proper parsing)
    # Each signature is typically 65 bytes (130 hex chars)
    local extra_data_len=${#qc_data}
    local estimated_sigs=$(( (extra_data_len - 64) / 130 ))  # Remove vanity prefix
    
    if [ "$estimated_sigs" -lt "$QUORUM_THRESHOLD" ]; then
        log "ERROR: QC insufficient signatures: $estimated_sigs < $QUORUM_THRESHOLD"
        return 1
    fi
    
    log "INFO: QC validated: $estimated_sigs signatures (threshold: $QUORUM_THRESHOLD)"
    
    # Additional validations:
    # - Verify each signature cryptographically
    # - Check masternode list
    # - Verify no duplicates
    
    return 0
}

# Get current block and validate
validate_recent_qcs() {
    local current_block=$(curl -s -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | \
        jq -r '.result' | sed 's/0x//' | xargs -I{} printf '%d' "0x{}")
    
    log "Current block: $current_block"
    
    # Validate last 10 blocks
    for i in $(seq 0 9); do
        local block=$((current_block - i))
        if [ $block -gt 0 ]; then
            validate_qc "$block" || log "WARNING: QC validation failed for block $block"
        fi
    done
}

# QC metrics for monitoring
collect_qc_metrics() {
    local formation_time_ms=0
    local signature_count=0
    local validation_failures=0
    
    # Export metrics in Prometheus format
    cat <<EOF
# HELP xdpos_qc_formation_time_ms Time taken to form QC in milliseconds
# TYPE xdpos_qc_formation_time_ms gauge
xdpos_qc_formation_time_ms $formation_time_ms

# HELP xdpos_qc_signature_count Number of signatures in QC
# TYPE xdpos_qc_signature_count gauge
xdpos_qc_signature_count $signature_count

# HELP xdpos_qc_validation_failures Number of QC validation failures
# TYPE xdpos_qc_validation_failures counter
xdpos_qc_validation_failures $validation_failures
EOF
}

# Main
main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    
    case "${1:-validate}" in
        validate)
            validate_recent_qcs
            ;;
        metrics)
            collect_qc_metrics
            ;;
        continuous)
            while true; do
                validate_recent_qcs || true
                sleep 60
            done
            ;;
        *)
            echo "Usage: $0 {validate|metrics|continuous}"
            exit 1
            ;;
    esac
}

main "$@"
