#!/bin/bash
#===============================================================================
# XDPoS 2.0 Consensus Monitoring Library
# Provides functions for QC validation, vote tracking, and epoch monitoring
#===============================================================================

set -euo pipefail

# XDPoS 2.0 Constants
readonly EPOCH_LENGTH=900
readonly MIN_QUORUM=73  # 2/3 of 108 masternodes
readonly QC_TIMEOUT_MS=5000
readonly MAX_VOTE_LATENCY_MS=2000

# RPC Configuration
XDC_RPC_URL="${XDC_RPC_URL:-http://localhost:8545}"

# Logging functions
log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_warn() { echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

#===============================================================================
# RPC Helpers
#===============================================================================

# Make JSON-RPC call to XDC node
rpc_call() {
    local method=$1
    local params=${2:-"[]"}
    
    curl -s -X POST "$XDC_RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        --max-time 10 2>/dev/null | jq -r '.result // empty'
}

# Get current block number
get_block_number() {
    local result
    result=$(rpc_call "eth_blockNumber")
    if [[ -n "$result" ]]; then
        printf '%d' "${result}" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Get block by number
get_block_by_number() {
    local block_num=$1
    local full_tx=${2:-false}
    rpc_call "eth_getBlockByNumber" "[\"$block_num\", $full_tx]"
}

#===============================================================================
# Epoch Functions
#===============================================================================

# Check if block is at epoch boundary
is_epoch_boundary() {
    local block_num=$1
    (( block_num % EPOCH_LENGTH == 0 ))
}

# Get current epoch number
get_current_epoch() {
    local block_num
    block_num=$(get_block_number)
    echo $(( block_num / EPOCH_LENGTH ))
}

# Get epoch start block
get_epoch_start_block() {
    local epoch=$1
    echo $(( epoch * EPOCH_LENGTH ))
}

#===============================================================================
# QC (Quorum Certificate) Functions
#===============================================================================

# Get QC data for a block
get_qc_data() {
    local block_num=$1
    rpc_call "XDPoS_getQC" "[\"$block_num\"]"
}

# Validate QC at checkpoint block
validate_qc() {
    local block_num=$1
    
    # Only validate at epoch boundaries
    if ! is_epoch_boundary "$block_num"; then
        return 0
    fi
    
    local qc_data
    qc_data=$(get_qc_data "$block_num")
    
    if [[ -z "$qc_data" ]] || [[ "$qc_data" == "null" ]]; then
        log_error "No QC data found for checkpoint block $block_num"
        return 1
    fi
    
    # Count signatures
    local sig_count
    sig_count=$(echo "$qc_data" | jq -r '.signatures // [] | length')
    
    if [[ "$sig_count" -lt "$MIN_QUORUM" ]]; then
        log_error "QC validation failed: $sig_count signatures (min: $MIN_QUORUM)"
        return 1
    fi
    
    log_info "QC validated: $sig_count signatures for block $block_num"
    return 0
}

# Get QC formation time
get_qc_formation_time() {
    local block_num=$1
    local qc_data
    qc_data=$(get_qc_data "$block_num")
    
    if [[ -n "$qc_data" ]]; then
        echo "$qc_data" | jq -r '.proposalTime // 0'
    else
        echo "0"
    fi
}

#===============================================================================
# Vote Functions
#===============================================================================

# Get votes for a block
get_votes() {
    local block_num=$1
    rpc_call "XDPoS_getVotesByNumber" "[\"$block_num\"]"
}

# Count votes for a block
count_votes() {
    local block_num=$1
    local votes
    votes=$(get_votes "$block_num")
    
    if [[ -n "$votes" ]]; then
        echo "$votes" | jq -r 'length'
    else
        echo "0"
    fi
}

# Get vote latency for a masternode
get_vote_latency() {
    local block_num=$1
    local masternode=$2
    
    local votes
    votes=$(get_votes "$block_num")
    
    if [[ -n "$votes" ]]; then
        echo "$votes" | jq -r --arg mn "$masternode" '.[] | select(.masternode == $mn) | .timestamp'
    fi
}

#===============================================================================
# Masternode Functions
#===============================================================================

# Get current masternode list
get_masternodes() {
    rpc_call "XDPoS_getMasternodesByNumber" "[\"latest\"]"
}

# Get masternode count
get_masternode_count() {
    local mn_data
    mn_data=$(get_masternodes)
    
    if [[ -n "$mn_data" ]]; then
        echo "$mn_data" | jq -r '.Masternodes // [] | length'
    else
        echo "0"
    fi
}

# Check if address is a masternode
is_masternode() {
    local address=$1
    local mn_data
    mn_data=$(get_masternodes)
    
    if [[ -n "$mn_data" ]]; then
        echo "$mn_data" | jq -r --arg addr "$address" '.Masternodes // [] | contains([$addr])'
    else
        echo "false"
    fi
}

#===============================================================================
# Gap Block Detection
#===============================================================================

# Check if block is a gap block (empty at epoch boundary)
is_gap_block() {
    local block_num=$1
    
    # Gap blocks only occur at epoch boundaries
    if ! is_epoch_boundary "$((block_num + 1))"; then
        return 1
    fi
    
    local block_data
    block_data=$(get_block_by_number "$block_num")
    
    if [[ -n "$block_data" ]]; then
        local tx_count
        tx_count=$(echo "$block_data" | jq -r '.transactions // [] | length')
        [[ "$tx_count" -eq 0 ]]
    else
        return 1
    fi
}

# Detect gap blocks in range
detect_gap_blocks() {
    local start_block=$1
    local end_block=$2
    local gap_blocks=()
    
    for (( b=start_block; b<=end_block; b++ )); do
        if is_epoch_boundary "$((b + 1))" && is_gap_block "$b"; then
            gap_blocks+=("$b")
        fi
    done
    
    printf '%s\n' "${gap_blocks[@]}"
}

#===============================================================================
# Consensus Health Monitoring
#===============================================================================

# Get comprehensive consensus health metrics
get_consensus_health() {
    local block_num
    block_num=$(get_block_number)
    local epoch
    epoch=$(get_current_epoch)
    
    local mn_count
    mn_count=$(get_masternode_count)
    local qc_data
    qc_data=$(get_qc_data "$block_num")
    local vote_count
    vote_count=$(count_votes "$block_num")
    
    # Build health report
    cat <<EOF
{
  "timestamp": $(date +%s),
  "blockNumber": $block_num,
  "epoch": $epoch,
  "masternodeCount": $mn_count,
  "voteCount": $vote_count,
  "qcData": $qc_data,
  "isEpochBoundary": $(is_epoch_boundary "$block_num" && echo "true" || echo "false")
}
EOF
}

# Check consensus health and return status code
check_consensus_health() {
    local block_num
    block_num=$(get_block_number)
    
    # Check if we have enough masternodes
    local mn_count
    mn_count=$(get_masternode_count)
    if [[ "$mn_count" -lt "$MIN_QUORUM" ]]; then
        log_error "Insufficient masternodes: $mn_count (min: $MIN_QUORUM)"
        return 2
    fi
    
    # Validate QC at epoch boundaries
    if is_epoch_boundary "$block_num"; then
        if ! validate_qc "$block_num"; then
            return 1
        fi
    fi
    
    log_info "Consensus health check passed"
    return 0
}

#===============================================================================
# Export functions for use in other scripts
#===============================================================================

export -f rpc_call get_block_number get_block_by_number
export -f is_epoch_boundary get_current_epoch get_epoch_start_block
export -f get_qc_data validate_qc get_qc_formation_time
export -f get_votes count_votes get_vote_latency
export -f get_masternodes get_masternode_count is_masternode
export -f is_gap_block detect_gap_blocks
export -f get_consensus_health check_consensus_health
