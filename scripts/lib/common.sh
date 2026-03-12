#!/bin/bash
#===============================================================================
# Common Utility Functions Library for XDC Node Setup
# Consolidates duplicate functions from across the codebase
# Version: 2.0.0
#===============================================================================

# Prevent multiple sourcing
[[ -n "${XDC_COMMON_SOURCED:-}" ]] && return 0
XDC_COMMON_SOURCED=1

# Source dependent libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/logging.sh" 2>/dev/null || true

#===============================================================================
# Colors & UI
#===============================================================================
if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly MAGENTA='\033[0;35m'
    readonly BOLD='\033[1m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly CYAN=''
    readonly MAGENTA=''
    readonly BOLD=''
    readonly NC=''
fi

#===============================================================================
# Basic Logging (for scripts not using logging.sh)
#===============================================================================
log() { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1" >&2; }
error() { echo -e "${RED}✗${NC} $1" >&2; }
die() { error "$1"; exit 1; }

#===============================================================================
# RPC Helpers
#===============================================================================
rpc_call() {
    local method="$1"
    local params="${2:-[]}"
    local rpc_url="${RPC_URL:-http://127.0.0.1:8545}"
    
    if ! curl -sf -m "$timeout" "$endpoint" \
         -X POST \
         -H "Content-Type: application/json" \
         --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
         >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

json_rpc() {
    local endpoint="$1"
    local method="$2"
    local params="${3:-[]}"
    
    curl -sf "$endpoint" \
        -X POST \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        | jq -r '.result // empty'
}

xrpc_call() {
    local method="$1"
    local params="${2:-[]}"
    local rpc_url="${RPC_URL:-http://127.0.0.1:8545}"
    
    local response
    response=$(curl -sf -m 10 -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" 2>/dev/null)
    
    if [[ -n "$response" ]]; then
        echo "$response" | jq -r '.result // empty' 2>/dev/null
    fi
}

#===============================================================================
# Number/Format Conversions
#===============================================================================
hex_to_dec() {
    local hex="${1#0x}"
    printf '%d\n' "0x${hex}" 2>/dev/null || echo "0"
}

dec_to_hex() {
    printf '0x%x\n' "$1" 2>/dev/null || echo "0x0"
}

wei_to_xdc() {
    local wei="$1"
    awk "BEGIN {printf \"%.6f\", $wei / 1000000000000000000}"
}

xdc_to_wei() {
    local xdc="$1"
    awk "BEGIN {printf \"%.0f\", $xdc * 1000000000000000000}"
}

format_bytes() {
    local bytes=$1
    if (( bytes < 1024 )); then
        echo "${bytes}B"
    elif (( bytes < 1048576 )); then
        echo "$(( bytes / 1024 ))KB"
    elif (( bytes < 1073741824 )); then
        echo "$(( bytes / 1048576 ))MB"
    elif (( bytes < 1099511627776 )); then
        echo "$(( bytes / 1073741824 ))GB"
    else
        echo "$(( bytes / 1099511627776 ))TB"
    fi
}

format_duration() {
    local seconds=$1
    if (( seconds < 60 )); then
        echo "${seconds}s"
    elif (( seconds < 3600 )); then
        echo "$(( seconds / 60 ))m"
    elif (( seconds < 86400 )); then
        echo "$(( seconds / 3600 ))h"
    else
        echo "$(( seconds / 86400 ))d"
    fi
}

#===============================================================================
# Prerequisites & Validation
#===============================================================================
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_prerequisites() {
    local missing=()
    
    command -v docker >/dev/null 2>&1 || missing+=("docker")
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing prerequisites: ${missing[*]}"
        log_error "Install with: apt-get install -y ${missing[*]}"
        return 1
    fi
    
    return 0
}

# ============================================
# Directory Management
# ============================================

ensure_directories() {
    local dirs=("$@")
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir" || {
                log_error "Failed to create directory: $dir"
                return 1
            }
        fi
    done
    
    return 0
}

# ============================================
# Formatting Utilities
# ============================================

format_duration() {
    local seconds="$1"
    local days=$((seconds / 86400))
    local hours=$(( (seconds % 86400) / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$((seconds % 60))
    
    if [[ $days -gt 0 ]]; then
        printf "%dd %dh %dm %ds" "$days" "$hours" "$minutes" "$secs"
    elif [[ $hours -gt 0 ]]; then
        printf "%dh %dm %ds" "$hours" "$minutes" "$secs"
    elif [[ $minutes -gt 0 ]]; then
        printf "%dm %ds" "$minutes" "$secs"
    else
        printf "%ds" "$secs"
    fi
}

check_docker() {
    if command_exists docker; then
        if docker info >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

ensure_directories() {
    for dir in "$@"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir" || die "Failed to create directory: $dir"
        fi
    done
}

#===============================================================================
# Node Information
#===============================================================================
get_block_height() {
    local rpc_url="${1:-${RPC_URL:-http://127.0.0.1:8545}}"
    local response
    response=$(curl -sf -m 5 -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null)
    
    if [[ -n "$response" ]]; then
        local hex=$(echo "$response" | jq -r '.result // empty' 2>/dev/null)
        hex_to_dec "$hex"
    else
        echo "0"
    fi
}

get_peer_count() {
    local rpc_url="${1:-${RPC_URL:-http://127.0.0.1:8545}}"
    local response
    response=$(curl -sf -m 5 -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null)
    
    if [[ -n "$response" ]]; then
        local hex=$(echo "$response" | jq -r '.result // empty' 2>/dev/null)
        hex_to_dec "$hex"
    else
        echo "0"
    fi
}

is_syncing() {
    local rpc_url="${1:-${RPC_URL:-http://127.0.0.1:8545}}"
    local response
    response=$(curl -sf -m 5 -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' 2>/dev/null)
    
    if [[ -n "$response" ]]; then
        local result=$(echo "$response" | jq -r '.result // false' 2>/dev/null)
        [[ "$result" != "false" ]] && echo "true" || echo "false"
    else
        echo "false"
    fi
}

get_sync_progress() {
    local rpc_url="${1:-${RPC_URL:-http://127.0.0.1:8545}}"
    local response
    response=$(curl -sf -m 5 -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' 2>/dev/null)
    
    if [[ -n "$response" ]]; then
        local result=$(echo "$response" | jq -r '.result // false' 2>/dev/null)
        if [[ "$result" != "false" ]]; then
            local current=$(echo "$result" | jq -r '.currentBlock // "0x0"' 2>/dev/null)
            local highest=$(echo "$result" | jq -r '.highestBlock // "0x0"' 2>/dev/null)
            local current_dec=$(hex_to_dec "$current")
            local highest_dec=$(hex_to_dec "$highest")
            if (( highest_dec > 0 )); then
                awk "BEGIN {printf \"%.2f\", ($current_dec / $highest_dec) * 100}"
            else
                echo "0.00"
            fi
        else
            echo "100.00"
        fi
    else
        echo "0.00"
    fi
}

#===============================================================================
# XDPoS 2.0 Consensus Helpers
#===============================================================================
get_current_epoch() {
    local rpc_url="${1:-${RPC_URL:-http://127.0.0.1:8545}}"
    local block_height=$(get_block_height "$rpc_url")
    local epoch_size=900
    echo $(( (block_height / epoch_size) + 1 ))
}

get_blocks_until_epoch() {
    local rpc_url="${1:-${RPC_URL:-http://127.0.0.1:8545}}"
    local block_height=$(get_block_height "$rpc_url")
    local epoch_size=900
    local current_epoch_block=$(( (block_height / epoch_size) * epoch_size ))
    echo $(( epoch_size - (block_height - current_epoch_block) ))
}

is_gap_block() {
    local block_number=$1
    local epoch_size=900
    local gap_threshold=50
    local blocks_into_epoch=$(( block_number % epoch_size ))
    
    if (( blocks_into_epoch >= (epoch_size - gap_threshold) )) || (( blocks_into_epoch == 0 )); then
        return 0
    else
        return 1
    fi
}

#===============================================================================
# Report Generation
#===============================================================================
generate_report() {
    local report_type="$1"
    local output_file="$2"
    
    case "$report_type" in
        health)
            generate_health_report "$output_file"
            ;;
        status)
            generate_status_report "$output_file"
            ;;
        consensus)
            generate_consensus_report "$output_file"
            ;;
        *)
            error "Unknown report type: $report_type"
            return 1
            ;;
    esac
}

generate_health_report() {
    local output_file="${1:-/tmp/health_report.json}"
    local timestamp=$(date -Iseconds)
    local block_height=$(get_block_height)
    local peer_count=$(get_peer_count)
    local syncing=$(is_syncing)
    local sync_progress=$(get_sync_progress)
    
    cat > "$output_file" << EOF
{
    "timestamp": "$timestamp",
    "block_height": $block_height,
    "peer_count": $peer_count,
    "syncing": $syncing,
    "sync_progress": $sync_progress,
    "status": "healthy"
}
EOF
}

generate_status_report() {
    local output_file="${1:-/tmp/status_report.txt}"
    
    {
        echo "=== XDC Node Status Report ==="
        echo "Generated: $(date)"
        echo ""
        echo "Block Height: $(get_block_height)"
        echo "Peer Count: $(get_peer_count)"
        echo "Sync Progress: $(get_sync_progress)%"
        echo "Current Epoch: $(get_current_epoch)"
        echo "Blocks Until Next Epoch: $(get_blocks_until_epoch)"
    } > "$output_file"
}

#===============================================================================
# Utility Functions
#===============================================================================
spinner() {
    local pid=$1
    local message="${2:-Processing...}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r${CYAN}%s${NC} %s" "${spin:$i:1}" "$message"
        sleep 0.1
    done
    printf "\r%-50s\r" ""
    tput cnorm 2>/dev/null || true
}

run_with_spinner() {
    local message="$1"
    shift
    "$@" >/dev/null 2>&1 &
    local pid=$!
    spinner "$pid" "$message"
    wait "$pid" 2>/dev/null || return $?
}

print_banner() {
    local title="$1"
    local width=60
    local padding=$(( (width - ${#title}) / 2 ))
    
    echo ""
    printf "${BOLD}${BLUE}%${padding}s${NC}" ""
    echo -e "${BOLD}${BLUE}$title${NC}"
    printf "${BLUE}%${width}s${NC}\n" "" | tr ' ' '='
}

print_summary() {
    echo ""
    printf "${BOLD}${GREEN}%60s${NC}\n" "" | tr ' ' '='
    echo -e "${BOLD}${GREEN}  Summary${NC}"
    printf "${GREEN}%60s${NC}\n" "" | tr ' ' '='
    for item in "$@"; do
        echo "  ✓ $item"
    done
    printf "${GREEN}%60s${NC}\n" "" | tr ' ' '='
    echo ""
}

#===============================================================================
# Export Functions
#===============================================================================
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f log info warn error die
    export -f rpc_call xrpc_call
    export -f hex_to_dec dec_to_hex wei_to_xdc xdc_to_wei
    export -f format_bytes format_duration
    export -f command_exists check_prerequisites check_docker ensure_directories
    export -f get_block_height get_peer_count is_syncing get_sync_progress
    export -f get_current_epoch get_blocks_until_epoch is_gap_block
    export -f generate_report generate_health_report generate_status_report
    export -f spinner run_with_spinner print_banner print_summary
fi
