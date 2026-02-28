#!/bin/bash
# Multi-Client Comparison Script
# Compares block hashes, state roots, and performance across Geth, Erigon, Nethermind, Reth
# Author: anilcinchawale <anil24593@gmail.com>

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default RPC endpoints
GETH_RPC="${GETH_RPC:-http://localhost:8545}"
ERIGON_RPC="${ERIGON_RPC:-http://localhost:8547}"
NETHERMIND_RPC="${NETHERMIND_RPC:-http://localhost:8556}"
RETH_RPC="${RETH_RPC:-http://localhost:8588}"

# Configuration
CONFIRMATION_DEPTH="${CONFIRMATION_DEPTH:-10}"
CHECK_INTERVAL="${CHECK_INTERVAL:-300}"  # 5 minutes
OUTPUT_FILE="${OUTPUT_FILE:-multi-client-compare.log}"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$OUTPUT_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$OUTPUT_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$OUTPUT_FILE"
}

log_divergence() {
    echo -e "${RED}[DIVERGENCE]${NC} $1" | tee -a "$OUTPUT_FILE"
}

json_rpc() {
    local endpoint=$1
    local method=$2
    local params=${3:-'[]'}
    
    curl -sf -X POST "$endpoint" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" 2>/dev/null \
        | jq -r '.result'
}

get_block_number() {
    local endpoint=$1
    local hex=$(json_rpc "$endpoint" "eth_blockNumber" 2>/dev/null)
    if [[ -n "$hex" && "$hex" != "null" ]]; then
        printf "%d" "$hex" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

get_block_by_number() {
    local endpoint=$1
    local block_num=$2
    local block_hex=$(printf "0x%x" "$block_num")
    
    json_rpc "$endpoint" "eth_getBlockByNumber" "[\"$block_hex\",false]" 2>/dev/null
}

get_client_version() {
    local endpoint=$1
    json_rpc "$endpoint" "web3_clientVersion" 2>/dev/null || echo "unknown"
}

get_peer_count() {
    local endpoint=$1
    local hex=$(json_rpc "$endpoint" "net_peerCount" 2>/dev/null)
    if [[ -n "$hex" && "$hex" != "null" ]]; then
        printf "%d" "$hex" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

check_client_status() {
    local name=$1
    local endpoint=$2
    
    local version=$(get_client_version "$endpoint")
    local block=$(get_block_number "$endpoint")
    local peers=$(get_peer_count "$endpoint")
    
    if [[ "$block" == "0" ]]; then
        log_warn "$name: NOT AVAILABLE at $endpoint"
        return 1
    fi
    
    log_info "$name: Block $block, Peers $peers, Version: $version"
    return 0
}

compare_block_hashes() {
    local block_num=$1
    
    log_info "=== Comparing Block #$block_num ==="
    
    declare -A block_hashes
    declare -A state_roots
    declare -A tx_roots
    
    # Fetch from Geth
    if check_client_status "Geth" "$GETH_RPC" &>/dev/null; then
        local geth_block=$(get_block_by_number "$GETH_RPC" "$block_num")
        block_hashes["geth"]=$(echo "$geth_block" | jq -r '.hash // "null"')
        state_roots["geth"]=$(echo "$geth_block" | jq -r '.stateRoot // "null"')
        tx_roots["geth"]=$(echo "$geth_block" | jq -r '.transactionsRoot // "null"')
    fi
    
    # Fetch from Erigon
    if check_client_status "Erigon" "$ERIGON_RPC" &>/dev/null; then
        local erigon_block=$(get_block_by_number "$ERIGON_RPC" "$block_num")
        block_hashes["erigon"]=$(echo "$erigon_block" | jq -r '.hash // "null"')
        state_roots["erigon"]=$(echo "$erigon_block" | jq -r '.stateRoot // "null"')
        tx_roots["erigon"]=$(echo "$erigon_block" | jq -r '.transactionsRoot // "null"')
    fi
    
    # Fetch from Nethermind
    if check_client_status "Nethermind" "$NETHERMIND_RPC" &>/dev/null; then
        local nm_block=$(get_block_by_number "$NETHERMIND_RPC" "$block_num")
        block_hashes["nethermind"]=$(echo "$nm_block" | jq -r '.hash // "null"')
        state_roots["nethermind"]=$(echo "$nm_block" | jq -r '.stateRoot // "null"')
        tx_roots["nethermind"]=$(echo "$nm_block" | jq -r '.transactionsRoot // "null"')
    fi
    
    # Fetch from Reth
    if check_client_status "Reth" "$RETH_RPC" &>/dev/null; then
        local reth_block=$(get_block_by_number "$RETH_RPC" "$block_num")
        block_hashes["reth"]=$(echo "$reth_block" | jq -r '.hash // "null"')
        state_roots["reth"]=$(echo "$reth_block" | jq -r '.stateRoot // "null"')
        tx_roots["reth"]=$(echo "$reth_block" | jq -r '.transactionsRoot // "null"')
    fi
    
    # Compare block hashes
    local unique_hashes=$(printf '%s\n' "${block_hashes[@]}" | grep -v "null" | sort -u | wc -l)
    
    if [[ $unique_hashes -gt 1 ]]; then
        log_divergence "BLOCK HASH DIVERGENCE detected at block $block_num!"
        for client in "${!block_hashes[@]}"; do
            log_error "  $client: ${block_hashes[$client]}"
        done
        return 1
    else
        log_info "✓ Block hashes match: ${block_hashes[geth]}"
    fi
    
    # Compare state roots
    local unique_states=$(printf '%s\n' "${state_roots[@]}" | grep -v "null" | sort -u | wc -l)
    
    if [[ $unique_states -gt 1 ]]; then
        log_divergence "STATE ROOT DIVERGENCE detected at block $block_num!"
        for client in "${!state_roots[@]}"; do
            log_error "  $client: ${state_roots[$client]}"
        done
        return 1
    else
        log_info "✓ State roots match: ${state_roots[geth]}"
    fi
    
    # Compare transaction roots
    local unique_txs=$(printf '%s\n' "${tx_roots[@]}" | grep -v "null" | sort -u | wc -l)
    
    if [[ $unique_txs -gt 1 ]]; then
        log_divergence "TRANSACTION ROOT DIVERGENCE detected at block $block_num!"
        for client in "${!tx_roots[@]}"; do
            log_error "  $client: ${tx_roots[$client]}"
        done
        return 1
    else
        log_info "✓ Transaction roots match: ${tx_roots[geth]}"
    fi
    
    return 0
}

performance_benchmark() {
    log_info "=== Performance Benchmark ==="
    
    declare -A latencies
    
    for client in geth erigon nethermind reth; do
        local endpoint=""
        case $client in
            geth) endpoint="$GETH_RPC" ;;
            erigon) endpoint="$ERIGON_RPC" ;;
            nethermind) endpoint="$NETHERMIND_RPC" ;;
            reth) endpoint="$RETH_RPC" ;;
        esac
        
        local start=$(date +%s%N)
        local block=$(get_block_number "$endpoint" 2>/dev/null)
        local end=$(date +%s%N)
        
        if [[ "$block" != "0" ]]; then
            local latency_ms=$(( (end - start) / 1000000 ))
            latencies["$client"]=$latency_ms
            log_info "$client: ${latency_ms}ms RPC latency"
        fi
    done
    
    # Find fastest
    local fastest_client=""
    local fastest_time=999999
    for client in "${!latencies[@]}"; do
        if [[ ${latencies[$client]} -lt $fastest_time ]]; then
            fastest_time=${latencies[$client]}
            fastest_client=$client
        fi
    done
    
    log_info "Fastest client: $fastest_client (${fastest_time}ms)"
}

continuous_monitor() {
    log_info "Starting continuous monitoring (Ctrl+C to stop)"
    log_info "Check interval: ${CHECK_INTERVAL}s"
    log_info "Confirmation depth: $CONFIRMATION_DEPTH blocks"
    
    while true; do
        local highest_block=0
        
        # Find highest block among all clients
        for endpoint in "$GETH_RPC" "$ERIGON_RPC" "$NETHERMIND_RPC" "$RETH_RPC"; do
            local block=$(get_block_number "$endpoint" 2>/dev/null)
            if [[ $block -gt $highest_block ]]; then
                highest_block=$block
            fi
        done
        
        if [[ $highest_block -gt 0 ]]; then
            # Check block with confirmation depth
            local check_block=$((highest_block - CONFIRMATION_DEPTH))
            if [[ $check_block -gt 0 ]]; then
                compare_block_hashes "$check_block"
            fi
        fi
        
        log_info "Next check in ${CHECK_INTERVAL}s..."
        sleep "$CHECK_INTERVAL"
    done
}

# Main execution
main() {
    log_info "╔══════════════════════════════════════════════════════╗"
    log_info "║   Multi-Client Comparison Tool                       ║"
    log_info "╚══════════════════════════════════════════════════════╝"
    log_info "Timestamp: $(date -Iseconds)"
    log_info ""
    
    log_info "=== Client Status ==="
    check_client_status "Geth" "$GETH_RPC" || true
    check_client_status "Erigon" "$ERIGON_RPC" || true
    check_client_status "Nethermind" "$NETHERMIND_RPC" || true
    check_client_status "Reth" "$RETH_RPC" || true
    echo ""
    
    performance_benchmark
    echo ""
    
    if [[ "${1:-}" == "--monitor" ]]; then
        continuous_monitor
    else
        # One-time check
        local highest_block=0
        for endpoint in "$GETH_RPC" "$ERIGON_RPC" "$NETHERMIND_RPC" "$RETH_RPC"; do
            local block=$(get_block_number "$endpoint" 2>/dev/null)
            if [[ $block -gt $highest_block ]]; then
                highest_block=$block
            fi
        done
        
        if [[ $highest_block -gt 0 ]]; then
            local check_block=$((highest_block - CONFIRMATION_DEPTH))
            if [[ $check_block -gt 0 ]]; then
                compare_block_hashes "$check_block"
            fi
        fi
    fi
    
    log_info "═══════════════════════════════════════════════════════"
    log_info "Comparison complete"
}

# Show usage
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --monitor             Continuous monitoring mode"
    echo "  --geth-rpc URL        Geth RPC endpoint"
    echo "  --erigon-rpc URL      Erigon RPC endpoint"
    echo "  --nethermind-rpc URL  Nethermind RPC endpoint"
    echo "  --reth-rpc URL        Reth RPC endpoint"
    echo "  --depth N             Confirmation depth (default: 10)"
    echo "  --interval N          Check interval in seconds (default: 300)"
    echo "  -h, --help            Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  GETH_RPC              Geth RPC endpoint"
    echo "  ERIGON_RPC            Erigon RPC endpoint"
    echo "  NETHERMIND_RPC        Nethermind RPC endpoint"
    echo "  RETH_RPC              Reth RPC endpoint"
    echo "  CONFIRMATION_DEPTH    Confirmation depth"
    echo "  CHECK_INTERVAL        Check interval"
    echo ""
    echo "Examples:"
    echo "  $0                    # One-time check"
    echo "  $0 --monitor          # Continuous monitoring"
    echo "  $0 --geth-rpc http://localhost:8545 --erigon-rpc http://localhost:8547"
    exit 0
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --monitor)
            MONITOR=true
            shift
            ;;
        --geth-rpc)
            GETH_RPC="$2"
            shift 2
            ;;
        --erigon-rpc)
            ERIGON_RPC="$2"
            shift 2
            ;;
        --nethermind-rpc)
            NETHERMIND_RPC="$2"
            shift 2
            ;;
        --reth-rpc)
            RETH_RPC="$2"
            shift 2
            ;;
        --depth)
            CONFIRMATION_DEPTH="$2"
            shift 2
            ;;
        --interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

main "$@"
