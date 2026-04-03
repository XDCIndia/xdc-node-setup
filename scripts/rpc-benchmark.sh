#!/bin/bash
#===============================================================================
# XDC Node Setup - RPC Performance Benchmarking (#110)
# Batch RPC latency test across all clients.
# Tests: eth_blockNumber, eth_getBalance, eth_getBlockByNumber
# Outputs p50/p95/p99 latency table.
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-lib.sh"

# Default settings
ITERATIONS="${ITERATIONS:-30}"
TIMEOUT_S="${TIMEOUT_S:-5}"
SAMPLE_ADDRESS="${SAMPLE_ADDRESS:-0x0000000000000000000000000000000000000001}"

# Client RPC endpoints
declare -A CLIENTS=(
    ["geth"]="http://127.0.0.1:7070"
    ["erigon"]="http://127.0.0.1:7071"
    ["nethermind"]="http://127.0.0.1:7072"
    ["reth"]="http://127.0.0.1:8588"
)

#-------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [client...]

Benchmark RPC latency across XDC clients.
If no clients specified, tests all reachable ones.

Options:
  -n N       Number of iterations per method (default: ${ITERATIONS})
  -t SEC     Request timeout in seconds (default: ${TIMEOUT_S})
  -c CLIENT  Only benchmark this client (repeatable)
  -j         Output JSON instead of table
  -h         Show this help

Methods tested:
  eth_blockNumber         — current head
  eth_getBalance          — account balance lookup
  eth_getBlockByNumber    — full block fetch

Examples:
  $(basename "$0")
  $(basename "$0") -n 50 -c geth -c erigon
  $(basename "$0") -j | jq .
EOF
}

#-------------------------------------------------------------------------------
# Send one RPC call, return elapsed ms or "ERR"
rpc_call_ms() {
    local endpoint="$1"
    local method="$2"
    local params="$3"
    
    local start end elapsed
    start=$(date +%s%N)
    
    local result
    result=$(curl -sf \
        --max-time "${TIMEOUT_S}" \
        -X POST \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":${params},\"id\":1}" \
        "${endpoint}" 2>/dev/null) || { echo "ERR"; return; }
    
    end=$(date +%s%N)
    elapsed=$(( (end - start) / 1000000 ))
    
    # Check for RPC-level error
    if echo "$result" | grep -q '"error"'; then
        echo "ERR"
        return
    fi
    
    echo "$elapsed"
}

#-------------------------------------------------------------------------------
# Compute percentile from sorted array
percentile() {
    local pct="$1"
    shift
    local values=("$@")
    local n=${#values[@]}
    
    if [[ $n -eq 0 ]]; then echo "N/A"; return; fi
    
    # Sort
    IFS=$'\n' sorted=($(sort -n <<< "${values[*]}")); unset IFS
    
    local idx=$(( (n * pct / 100) ))
    [[ $idx -ge $n ]] && idx=$(( n - 1 ))
    echo "${sorted[$idx]}"
}

#-------------------------------------------------------------------------------
benchmark_client() {
    local name="$1"
    local endpoint="$2"
    local json_mode="${3:-false}"
    
    # First check if endpoint is reachable
    if ! curl -sf --max-time 2 -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "${endpoint}" &>/dev/null; then
        [[ "$json_mode" == "true" ]] || warn "  ${name}: not reachable — skipping"
        echo "UNREACHABLE"
        return
    fi
    
    # Get a recent block number for eth_getBlockByNumber
    local block_hex
    block_hex=$(curl -sf --max-time "${TIMEOUT_S}" -X POST \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "${endpoint}" 2>/dev/null | grep -o '"result":"0x[^"]*"' | cut -d'"' -f4) || block_hex="0x1"
    [[ -z "$block_hex" ]] && block_hex="0x1"
    
    declare -A method_samples
    local methods=("eth_blockNumber" "eth_getBalance" "eth_getBlockByNumber")
    local params_eth_blockNumber='[]'
    local params_eth_getBalance="[\"${SAMPLE_ADDRESS}\",\"latest\"]"
    local params_eth_getBlockByNumber="[\"${block_hex}\",false]"
    
    for method in "${methods[@]}"; do
        local param_var="params_${method}"
        local params="${!param_var}"
        local samples=()
        local errors=0
        
        for (( i=0; i<ITERATIONS; i++ )); do
            local ms
            ms=$(rpc_call_ms "$endpoint" "$method" "$params")
            if [[ "$ms" == "ERR" ]]; then
                ((errors++))
            else
                samples+=("$ms")
            fi
        done
        
        method_samples["${method}_p50"]=$(percentile 50 "${samples[@]:-0}")
        method_samples["${method}_p95"]=$(percentile 95 "${samples[@]:-0}")
        method_samples["${method}_p99"]=$(percentile 99 "${samples[@]:-0}")
        method_samples["${method}_errors"]="$errors"
        method_samples["${method}_ok"]="${#samples[@]}"
    done
    
    # Output result as "name p50_bn p95_bn p99_bn p50_bal p95_bal p99_bal p50_blk p95_blk p99_blk"
    echo "${name}" \
        "${method_samples[eth_blockNumber_p50]}" \
        "${method_samples[eth_blockNumber_p95]}" \
        "${method_samples[eth_blockNumber_p99]}" \
        "${method_samples[eth_getBalance_p50]}" \
        "${method_samples[eth_getBalance_p95]}" \
        "${method_samples[eth_getBalance_p99]}" \
        "${method_samples[eth_getBlockByNumber_p50]}" \
        "${method_samples[eth_getBlockByNumber_p95]}" \
        "${method_samples[eth_getBlockByNumber_p99]}" \
        "${method_samples[eth_blockNumber_errors]}" \
        "${method_samples[eth_getBalance_errors]}" \
        "${method_samples[eth_getBlockByNumber_errors]}"
}

#-------------------------------------------------------------------------------
print_table() {
    local results=("$@")
    
    printf "\n"
    printf "%-14s │ %-22s │ %-22s │ %-22s\n" \
        "CLIENT" "eth_blockNumber (ms)" "eth_getBalance (ms)" "eth_getBlockByNumber (ms)"
    printf "%-14s │ %-6s %-6s %-6s  │ %-6s %-6s %-6s  │ %-6s %-6s %-6s\n" \
        "" "p50" "p95" "p99" "p50" "p95" "p99" "p50" "p95" "p99"
    printf '%s\n' "$(printf '─%.0s' {1..80})"
    
    for row in "${results[@]}"; do
        read -r name p50_bn p95_bn p99_bn p50_bal p95_bal p99_bal p50_blk p95_blk p99_blk _ _ _ <<< "$row"
        printf "%-14s │ %-6s %-6s %-6s  │ %-6s %-6s %-6s  │ %-6s %-6s %-6s\n" \
            "$name" "$p50_bn" "$p95_bn" "$p99_bn" \
            "$p50_bal" "$p95_bal" "$p99_bal" \
            "$p50_blk" "$p95_blk" "$p99_blk"
    done
    printf '\n'
}

#-------------------------------------------------------------------------------
print_json() {
    local results=("$@")
    local first=true
    
    echo "{"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"iterations\": ${ITERATIONS},"
    echo "  \"clients\": {"
    
    for row in "${results[@]}"; do
        read -r name p50_bn p95_bn p99_bn p50_bal p95_bal p99_bal p50_blk p95_blk p99_blk err_bn err_bal err_blk <<< "$row"
        $first || echo ","
        first=false
        cat <<EOF
    "${name}": {
      "eth_blockNumber":      {"p50": ${p50_bn},  "p95": ${p95_bn},  "p99": ${p99_bn},  "errors": ${err_bn}},
      "eth_getBalance":       {"p50": ${p50_bal}, "p95": ${p95_bal}, "p99": ${p99_bal}, "errors": ${err_bal}},
      "eth_getBlockByNumber": {"p50": ${p50_blk}, "p95": ${p95_blk}, "p99": ${p99_blk}, "errors": ${err_blk}}
    }
EOF
    done
    
    echo "  }"
    echo "}"
}

#-------------------------------------------------------------------------------
main() {
    local json_mode=false
    local selected_clients=()
    
    while getopts "n:t:c:jh" opt; do
        case "$opt" in
            n) ITERATIONS="$OPTARG" ;;
            t) TIMEOUT_S="$OPTARG" ;;
            c) selected_clients+=("$OPTARG") ;;
            j) json_mode=true ;;
            h) usage; exit 0 ;;
            *) usage; exit 1 ;;
        esac
    done
    
    # Build target client list
    declare -A targets
    if [[ ${#selected_clients[@]} -gt 0 ]]; then
        for c in "${selected_clients[@]}"; do
            if [[ -n "${CLIENTS[$c]:-}" ]]; then
                targets["$c"]="${CLIENTS[$c]}"
            else
                warn "Unknown client: $c (known: ${!CLIENTS[*]})"
            fi
        done
    else
        for c in "${!CLIENTS[@]}"; do
            targets["$c"]="${CLIENTS[$c]}"
        done
    fi
    
    if [[ ${#targets[@]} -eq 0 ]]; then
        die "No valid clients to benchmark"
    fi
    
    [[ "$json_mode" == "false" ]] && {
        info "XDC RPC Benchmark — ${ITERATIONS} iterations per method"
        info "Clients: ${!targets[*]}"
    }
    
    local results=()
    for name in $(echo "${!targets[@]}" | tr ' ' '\n' | sort); do
        local endpoint="${targets[$name]}"
        [[ "$json_mode" == "false" ]] && info "Benchmarking ${name} @ ${endpoint}..."
        
        local row
        row=$(benchmark_client "$name" "$endpoint" "$json_mode")
        [[ "$row" == "UNREACHABLE" ]] && continue
        results+=("$row")
    done
    
    if [[ ${#results[@]} -eq 0 ]]; then
        die "No reachable clients found"
    fi
    
    if $json_mode; then
        print_json "${results[@]}"
    else
        print_table "${results[@]}"
        info "Iterations: ${ITERATIONS} | Timeout: ${TIMEOUT_S}s"
    fi
}

main "$@"
