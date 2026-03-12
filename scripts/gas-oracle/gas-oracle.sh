#!/bin/bash
set -euo pipefail

# XDC Gas Price Oracle
# Issue #525: Local gas price calculation for XDC transactions
# Provides optimal gas price recommendations based on network conditions

readonly SCRIPT_VERSION="1.0.0"
readonly CONFIG_DIR="${XDC_CONFIG_DIR:-$HOME/.xdc-node}"
readonly CACHE_FILE="$CONFIG_DIR/gas-price-cache.json"
readonly LOG_FILE="${XDC_LOG_DIR:-/var/log/xdc}/gas-oracle.log"

# Default configuration
RPC_URL="${RPC_URL:-http://localhost:8545}"
CACHE_TTL="${GAS_ORACLE_CACHE_TTL:-30}"  # seconds
HISTORY_BLOCKS="${GAS_ORACLE_HISTORY_BLOCKS:-20}"

# Logging functions
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
info() { log "INFO: $*"; }
warn() { log "WARN: $*" >&2; }
error() { log "ERROR: $*" >&2; }

# Ensure directories exist
init() {
    mkdir -p "$CONFIG_DIR" "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
}

# RPC call helper
rpc_call() {
    local method=$1
    local params=${2:-'[]'}
    
    curl -sf -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        2>/dev/null || echo '{}'
}

# Get recent blocks and their gas prices
get_recent_blocks() {
    local count=$1
    local blocks=()
    
    # Get latest block number
    local latest_result
    latest_result=$(rpc_call "eth_blockNumber")
    local latest_hex
    latest_hex=$(echo "$latest_result" | jq -r '.result // "0x0"')
    local latest
    latest=$(printf '%d' "$latest_hex" 2>/dev/null || echo 0)
    
    # Fetch recent blocks
    for i in $(seq 0 $((count - 1))); do
        local block_num=$((latest - i))
        if [[ $block_num -lt 0 ]]; then break; fi
        
        local block_hex="0x$(printf '%x' $block_num)"
        local result
        result=$(rpc_call "eth_getBlockByNumber" "[\"$block_hex\",false]")
        
        local gas_price
        gas_price=$(echo "$result" | jq -r '.result.baseFeePerGas // "0x0"')
        if [[ "$gas_price" != "0x0" && -n "$gas_price" ]]; then
            blocks+=("$gas_price")
        fi
    done
    
    printf '%s\n' "${blocks[@]}"
}

# Calculate gas price statistics
calculate_gas_prices() {
    local gas_prices=($(get_recent_blocks "$HISTORY_BLOCKS"))
    
    if [[ ${#gas_prices[@]} -eq 0 ]]; then
        # Fallback to default XDC gas prices
        echo '{"safeLow":"20000000000","standard":"25000000000","fast":"30000000000","rapid":"50000000000","blockNumber":0}'
        return
    fi
    
    # Convert hex to decimal and sort
    local decimals=()
    for gp in "${gas_prices[@]}"; do
        local dec
        dec=$(printf '%d' "$gp" 2>/dev/null || echo 0)
        decimals+=($dec)
    done
    
    IFS=$'\n' sorted=($(sort -n <<<"${decimals[*]}")); unset IFS
    
    local count=${#sorted[@]}
    local safe_low=${sorted[$((count / 4))]}      # 25th percentile
    local standard=${sorted[$((count / 2))]}      # 50th percentile
    local fast=${sorted[$((count * 3 / 4))]}      # 75th percentile
    local rapid=${sorted[$((count - 1))]}         # Max
    
    # Add buffer for different strategies
    standard=$((standard * 110 / 100))  # +10%
    fast=$((fast * 120 / 100))          # +20%
    rapid=$((rapid * 150 / 100))        # +50%
    
    # Get current block number
    local latest_result
    latest_result=$(rpc_call "eth_blockNumber")
    local block_num
    block_num=$(printf '%d' "$(echo "$latest_result" | jq -r '.result // "0x0"')" 2>/dev/null || echo 0)
    
    # Output JSON
    jq -n \
        --arg safeLow "$safe_low" \
        --arg standard "$standard" \
        --arg fast "$fast" \
        --arg rapid "$rapid" \
        --arg blockNumber "$block_num" \
        '{safeLow: $safeLow, standard: $standard, fast: $fast, rapid: $rapid, blockNumber: ($blockNumber | tonumber)}'
}

# Cache gas prices to file
cache_gas_prices() {
    local data=$1
    local timestamp
    timestamp=$(date +%s)
    
    echo "$data" | jq --arg ts "$timestamp" '. + {timestamp: ($ts | tonumber)}' > "$CACHE_FILE"
}

# Get cached gas prices (if not expired)
get_cached_gas_prices() {
    if [[ ! -f "$CACHE_FILE" ]]; then
        return 1
    fi
    
    local cache_data
    cache_data=$(cat "$CACHE_FILE")
    
    local cache_time
    cache_time=$(echo "$cache_data" | jq -r '.timestamp // 0')
    local now
    now=$(date +%s)
    
    if [[ $((now - cache_time)) -gt $CACHE_TTL ]]; then
        return 1
    fi
    
    echo "$cache_data"
}

# Get gas prices (from cache or calculate)
get_gas_prices() {
    local cached
    if cached=$(get_cached_gas_prices); then
        echo "$cached" | jq '{safeLow, standard, fast, rapid, blockNumber}'
    else
        local calculated
        calculated=$(calculate_gas_prices)
        cache_gas_prices "$calculated"
        echo "$calculated"
    fi
}

# Get gas price history
get_gas_price_history() {
    local hours=${1:-24}
    local blocks_to_fetch=$((hours * 120))  # ~120 blocks per hour
    
    local prices=()
    local timestamps=()
    
    # Get latest block number
    local latest_result
    latest_result=$(rpc_call "eth_blockNumber")
    local latest
    latest=$(printf '%d' "$(echo "$latest_result" | jq -r '.result // "0x0"')" 2>/dev/null || echo 0)
    
    # Sample blocks over the time period
    local step=$((blocks_to_fetch / 24))
    [[ $step -lt 1 ]] && step=1
    
    for i in $(seq 0 $step $blocks_to_fetch); do
        local block_num=$((latest - i))
        [[ $block_num -lt 0 ]] && break
        
        local block_hex="0x$(printf '%x' $block_num)"
        local result
        result=$(rpc_call "eth_getBlockByNumber" "[\"$block_hex\",false]")
        
        local gas_price
        gas_price=$(echo "$result" | jq -r '.result.baseFeePerGas // "0x0"')
        local timestamp
        timestamp=$(echo "$result" | jq -r '.result.timestamp // "0x0"')
        
        if [[ "$gas_price" != "0x0" ]]; then
            local dec_price
            dec_price=$(printf '%d' "$gas_price" 2>/dev/null || echo 0)
            local dec_time
            dec_time=$(printf '%d' "$timestamp" 2>/dev/null || echo 0)
            prices+=("{\"timestamp\":$dec_time,\"price\":$dec_price}")
        fi
    done
    
    # Output history array
    printf '[%s]' "$(IFS=,; echo "${prices[*]}")"
}

# Format output for CLI
format_output() {
    local data=$1
    local strategy=$2
    
    if [[ -n "$strategy" ]]; then
        # Return specific strategy
        local value
        value=$(echo "$data" | jq -r ".${strategy} // empty")
        if [[ -n "$value" ]]; then
            echo "$value"
        else
            error "Unknown strategy: $strategy"
            error "Available: safeLow, standard, fast, rapid"
            exit 1
        fi
    else
        # Pretty print all
        local safeLow standard fast rapid blockNumber
        safeLow=$(echo "$data" | jq -r '.safeLow')
        standard=$(echo "$data" | jq -r '.standard')
        fast=$(echo "$data" | jq -r '.fast')
        rapid=$(echo "$data" | jq -r '.rapid')
        blockNumber=$(echo "$data" | jq -r '.blockNumber')
        
        echo "╔════════════════════════════════════════════════╗"
        echo "║        XDC Gas Price Oracle v$SCRIPT_VERSION        ║"
        echo "╠════════════════════════════════════════════════╣"
        printf "║ Safe Low  (5-10 blocks):  %18s ║\n" "${safeLow} wei"
        printf "║ Standard  (3-5 blocks):   %18s ║\n" "${standard} wei"
        printf "║ Fast      (1-2 blocks):   %18s ║\n" "${fast} wei"
        printf "║ Rapid     (immediate):    %18s ║\n" "${rapid} wei"
        echo "╠════════════════════════════════════════════════╣"
        printf "║ Block Number:             %18s ║\n" "$blockNumber"
        echo "╚════════════════════════════════════════════════╝"
    fi
}

# Start API server
start_api() {
    local port=${1:-8080}
    
    info "Starting Gas Price Oracle API on port $port"
    
    # Create simple HTTP server using netcat
    while true; do
        {
            read -r request
            
            # Parse request
            if [[ "$request" == *"GET /gas-price"* ]]; then
                local response
                response=$(get_gas_prices)
                
                echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\n\r\n$response"
            else
                echo -e "HTTP/1.1 404 Not Found\r\n\r\n{\"error\":\"Not found\"}"
            fi
        } | nc -l -p "$port" -q 1
    done
}

# Main
main() {
    init
    
    case "${1:-}" in
        --api)
            start_api "${2:-8080}"
            ;;
        --history)
            get_gas_price_history "${2:-24}"
            ;;
        --strategy)
            get_gas_prices | jq -r ".${2:-standard} // empty"
            ;;
        --help|-h)
            cat <<'EOF'
XDC Gas Price Oracle v1.0.0

Usage: gas-oracle.sh [options]

Options:
  --api [port]          Start API server (default port: 8080)
  --history [hours]     Get gas price history (default: 24h)
  --strategy [type]     Get specific strategy (safeLow|standard|fast|rapid)
  --help               Show this help

Environment Variables:
  RPC_URL              XDC node RPC endpoint (default: http://localhost:8545)
  GAS_ORACLE_CACHE_TTL Cache TTL in seconds (default: 30)
  GAS_ORACLE_HISTORY_BLOCKS Blocks to analyze (default: 20)

Examples:
  gas-oracle.sh                    # Display current gas prices
  gas-oracle.sh --strategy fast    # Get fast gas price only
  gas-oracle.sh --api 8080         # Start API server
  gas-oracle.sh --history 48       # Get 48h history
EOF
            ;;
        *)
            get_gas_prices | format_output - "${1:-}"
            ;;
    esac
}

main "$@"
