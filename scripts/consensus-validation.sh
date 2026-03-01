#!/bin/bash

# Source shared logging library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/logging.sh" 2>/dev/null || source "$(dirname "$0")/lib/logging.sh" || { echo "Error: Cannot find lib/logging.sh" >&2; exit 1; }


# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }
# XDPoS 2.0 Consensus Validation Script
# XDPoS 2.0 Consensus Validation Script
# Validates epoch boundaries, gap blocks, vote participation, and QC formation
# Author: anilcinchawale <anil24593@gmail.com>

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# XDPoS 2.0 Constants
EPOCH_LENGTH=900
GAP_BLOCKS=450
MIN_QUORUM=73  # 2/3 of 108 masternodes
QC_TIMEOUT_THRESHOLD=5000  # milliseconds
VOTE_LATENCY_THRESHOLD=2000  # milliseconds

# Configuration
RPC_ENDPOINT="${RPC_ENDPOINT:-http://localhost:8545}"
OUTPUT_FILE="${OUTPUT_FILE:-consensus-validation.log}"
VERBOSE="${VERBOSE:-false}"

# Functions



json_rpc() {
    local method=$1
    local params=${2:-'[]'}
    curl -sf -X POST "$RPC_ENDPOINT" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" 2>/dev/null | jq -r '.result'
}

get_block_number() {
    json_rpc "eth_blockNumber" | sed 's/0x//' | xargs -I{} printf "%d" 0x{}
}

get_epoch_info() {
    local block_hex=$1
    json_rpc "XDPoS_getEpochInfo" "[\"$block_hex\"]"
}

check_epoch_boundary() {
    log_info "=== Checking Epoch Boundary Handling ==="
    
    local current_block=$(get_block_number)
    local current_block_hex=$(printf "0x%x" "$current_block")
    local epoch=$((current_block / EPOCH_LENGTH))
    local position=$((current_block % EPOCH_LENGTH))
    local blocks_until_epoch_end=$((EPOCH_LENGTH - position))
    
    log_info "Current block: $current_block (Epoch $epoch, Position $position/$EPOCH_LENGTH)"
    log_info "Blocks until epoch end: $blocks_until_epoch_end"
    
    # Check if in gap period
    if [[ $blocks_until_epoch_end -le $GAP_BLOCKS ]]; then
        log_warn "Currently in gap period (last $GAP_BLOCKS blocks before epoch end)"
        log_info "Gap blocks are blocks 450-899 of each epoch - voting is disabled"
        return 1
    else
        log_info "Not in gap period - normal voting active"
        return 0
    fi
}

check_masternode_set() {
    log_info "=== Checking Masternode Set ==="
    
    local current_block=$(get_block_number)
    local current_block_hex=$(printf "0x%x" "$current_block")
    
    local masternodes=$(json_rpc "XDPoS_getMasternodes" "[\"$current_block_hex\"]" 2>/dev/null)
    if [[ -z "$masternodes" || "$masternodes" == "null" ]]; then
        log_error "Failed to retrieve masternode set"
        return 1
    fi
    
    local count=$(echo "$masternodes" | jq 'length' 2>/dev/null || echo 0)
    log_info "Current masternode count: $count"
    
    if [[ $count -lt $MIN_QUORUM ]]; then
        log_error "Insufficient masternodes for quorum: $count < $MIN_QUORUM"
        return 1
    else
        log_info "Sufficient masternodes for quorum: $count >= $MIN_QUORUM"
        return 0
    fi
}

check_qc_formation() {
    log_info "=== Checking QC Formation ==="
    
    local latest_qcs=$(json_rpc "XDPoS_getLatestQCs" 2>/dev/null)
    if [[ -z "$latest_qcs" || "$latest_qcs" == "null" ]]; then
        log_warn "No recent QCs found (method may not be implemented)"
        return 1
    fi
    
    local qc_count=$(echo "$latest_qcs" | jq 'length' 2>/dev/null || echo 0)
    log_info "Recent QC count: $qc_count"
    
    if [[ $qc_count -eq 0 ]]; then
        log_warn "No recent QCs - consensus may be stalled"
        return 1
    fi
    
    # Check QC age
    local now=$(date +%s)
    local oldest_qc_time=$(echo "$latest_qcs" | jq -r '.[-1].timestamp // 0' 2>/dev/null)
    if [[ $oldest_qc_time -gt 0 ]]; then
        local qc_age=$((now - oldest_qc_time))
        local threshold_sec=$((QC_TIMEOUT_THRESHOLD / 1000))
        
        if [[ $qc_age -gt $threshold_sec ]]; then
            log_warn "Oldest QC is ${qc_age}s old (threshold: ${threshold_sec}s)"
            return 1
        else
            log_info "QCs are recent (oldest: ${qc_age}s)"
        fi
    fi
    
    return 0
}

check_vote_participation() {
    log_info "=== Checking Vote Participation ==="
    
    local current_block=$(get_block_number)
    local current_block_hex=$(printf "0x%x" "$current_block")
    
    # Try to get vote stats (method may not exist)
    local vote_stats=$(json_rpc "XDPoS_getVoteStats" "[\"$current_block_hex\"]" 2>/dev/null)
    if [[ -z "$vote_stats" || "$vote_stats" == "null" ]]; then
        log_warn "Vote statistics not available (method not implemented)"
        log_info "Consider upgrading to XDC client with full XDPoS 2.0 monitoring support"
        return 1
    fi
    
    local total_votes=$(echo "$vote_stats" | jq -r '.totalVotes // 0')
    local node_votes=$(echo "$vote_stats" | jq -r '.nodeVotes // 0')
    
    log_info "Total votes in epoch: $total_votes"
    log_info "This node's votes: $node_votes"
    
    if [[ $node_votes -gt 0 ]]; then
        log_info "Node is actively voting"
        return 0
    else
        log_warn "Node has not cast any votes in current epoch"
        return 1
    fi
}

check_gap_block_handling() {
    log_info "=== Checking Gap Block Handling ==="
    
    local current_block=$(get_block_number)
    local epoch=$((current_block / EPOCH_LENGTH))
    
    # Calculate nearest gap block positions
    local current_epoch_start=$((epoch * EPOCH_LENGTH))
    local gap_start=$((current_epoch_start + EPOCH_LENGTH - GAP_BLOCKS))
    local gap_end=$((current_epoch_start + EPOCH_LENGTH - 1))
    
    log_info "Current epoch $epoch: blocks $current_epoch_start - $((current_epoch_start + EPOCH_LENGTH - 1))"
    log_info "Gap period: blocks $gap_start - $gap_end"
    
    if [[ $current_block -ge $gap_start && $current_block -le $gap_end ]]; then
        log_warn "Currently in gap block range - voting disabled"
        log_info "Gap blocks prevent voting conflicts during epoch transitions"
        return 0
    else
        log_info "Not in gap block range - normal consensus operation"
        return 0
    fi
}

# Main execution
main() {
    log_info "╔══════════════════════════════════════════════════════╗"
    log_info "║   XDPoS 2.0 Consensus Validation                    ║"
    log_info "╚══════════════════════════════════════════════════════╝"
    log_info "Timestamp: $(date -Iseconds)"
    log_info "RPC Endpoint: $RPC_ENDPOINT"
    log_info ""
    
    local overall_status=0
    
    check_epoch_boundary || ((overall_status++))
    echo ""
    
    check_gap_block_handling || ((overall_status++))
    echo ""
    
    check_masternode_set || ((overall_status++))
    echo ""
    
    check_qc_formation || ((overall_status++))
    echo ""
    
    check_vote_participation || ((overall_status++))
    echo ""
    
    log_info "═══════════════════════════════════════════════════════"
    if [[ $overall_status -eq 0 ]]; then
        log_info "✓ All consensus checks PASSED"
    else
        log_warn "⚠ Some checks FAILED or returned warnings (see above)"
        log_info "This may be normal if:"
        log_info "  - Node is not a masternode"
        log_info "  - Currently in gap period"
        log_info "  - RPC methods not fully implemented"
    fi
    log_info "═══════════════════════════════════════════════════════"
    
    return 0
}

# Show usage
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --rpc-endpoint URL    RPC endpoint (default: http://localhost:8545)"
    echo "  --output FILE         Output log file (default: consensus-validation.log)"
    echo "  --verbose             Enable verbose logging"
    echo "  -h, --help            Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  RPC_ENDPOINT          RPC endpoint override"
    echo "  OUTPUT_FILE           Output file override"
    echo "  VERBOSE               Enable verbose mode (true/false)"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 --rpc-endpoint http://localhost:8547"
    echo "  RPC_ENDPOINT=http://localhost:8556 $0"
    exit 0
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --rpc-endpoint)
            RPC_ENDPOINT="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

main "$@"
