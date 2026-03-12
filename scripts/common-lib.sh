#!/bin/bash
#===============================================================================
# XDC Node Setup - Common Functions Library
# Source this file in other scripts to use shared utilities
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/common-lib.sh"
#===============================================================================

set -euo pipefail

# Prevent double-sourcing
if [[ -n "${XDC_COMMON_LIB_SOURCED:-}" ]]; then
    return 0
fi
readonly XDC_COMMON_LIB_SOURCED=1

#===============================================================================
# Color Definitions
#===============================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

#===============================================================================
# Logging Functions
#===============================================================================

log() {
    echo -e "${GREEN}✓${NC} $1"
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1" >&2
}

error() {
    echo -e "${RED}✗${NC} $1" >&2
}

die() {
    error "$1"
    exit "${2:-1}"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

#===============================================================================
# Utility Functions
#===============================================================================

# Check if required commands exist
check_commands() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required commands: ${missing[*]}"
        return 1
    fi
    return 0
}

# Detect network type from node configuration
detect_network() {
    local config_file="${1:-/opt/xdc-node/config.json}"
    
    if [[ -f "$config_file" ]]; then
        local network
        network=$(jq -r '.network // empty' "$config_file" 2>/dev/null || echo "")
        if [[ -n "$network" ]]; then
            echo "$network"
            return 0
        fi
    fi
    
    # Fallback detection
    if [[ -d "/opt/xdc-node/testnet" ]] || [[ -f "/opt/xdc-node/testnet/.env" ]]; then
        echo "testnet"
    elif [[ -d "/opt/xdc-node/mainnet" ]] || [[ -f "/opt/xdc-node/mainnet/.env" ]]; then
        echo "mainnet"
    elif [[ -f "/opt/xdc-node/.env" ]]; then
        grep -q "TESTNET=true" /opt/xdc-node/.env 2>/dev/null && echo "testnet" || echo "mainnet"
    else
        echo "mainnet"
    fi
}

# Get current XDC block height via RPC
get_block_height() {
    local rpc_url="${1:-http://localhost:8545}"
    
    local response
    response=$(curl -s -m 5 -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null || echo "")
    
    if [[ -n "$response" ]]; then
        local block_hex
        block_hex=$(echo "$response" | jq -r '.result // empty' 2>/dev/null || echo "")
        if [[ -n "$block_hex" ]]; then
            printf '%d' "$block_hex" 2>/dev/null || echo "0"
            return 0
        fi
    fi
    echo "0"
}

# Check if node is synced
check_sync_status() {
    local rpc_url="${1:-http://localhost:8545}"
    
    local response
    response=$(curl -s -m 5 -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' 2>/dev/null || echo "")
    
    if [[ -z "$response" ]]; then
        echo "unknown"
        return 1
    fi
    
    local syncing
    syncing=$(echo "$response" | jq -r '.result // false')
    
    if [[ "$syncing" == "false" ]]; then
        echo "synced"
    else
        echo "syncing"
    fi
}

# Get peer count
get_peer_count() {
    local rpc_url="${1:-http://localhost:8545}"
    
    local response
    response=$(curl -s -m 5 -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null || echo "")
    
    if [[ -n "$response" ]]; then
        local peer_hex
        peer_hex=$(echo "$response" | jq -r '.result // empty' 2>/dev/null || echo "")
        if [[ -n "$peer_hex" ]]; then
            printf '%d' "$peer_hex" 2>/dev/null || echo "0"
            return 0
        fi
    fi
    echo "0"
}

#===============================================================================
# Validation Functions
#===============================================================================

# Validate JSON file
validate_json() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        error "File not found: $file"
        return 1
    fi
    
    if ! jq empty "$file" 2>/dev/null; then
        error "Invalid JSON: $file"
        return 1
    fi
    return 0
}

# Validate IP address
validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    fi
    return 1
}

# Validate port number
validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && (( port > 0 && port <= 65535 )); then
        return 0
    fi
    return 1
}

#===============================================================================
# Time/Date Functions
#===============================================================================

# Get ISO timestamp
iso_timestamp() {
    date -Iseconds
}

# Get Unix timestamp
timestamp() {
    date +%s
}

# Format duration from seconds
format_duration() {
    local seconds="$1"
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    if (( hours > 0 )); then
        printf "%dh %dm %ds" "$hours" "$minutes" "$secs"
    elif (( minutes > 0 )); then
        printf "%dm %ds" "$minutes" "$secs"
    else
        printf "%ds" "$secs"
    fi
}

#===============================================================================
# Docker Functions
#===============================================================================

# Check if Docker container is running
is_container_running() {
    local container_name="$1"
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"
}

# Get container health status
get_container_health() {
    local container_name="$1"
    docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "unknown"
}

#===============================================================================
# File/Directory Functions
#===============================================================================

# Ensure directory exists
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || die "Failed to create directory: $dir"
    fi
}

# Backup file with timestamp
backup_file() {
    local file="$1"
    local backup_dir="${2:-./backups}"
    
    if [[ ! -f "$file" ]]; then
        error "File not found: $file"
        return 1
    fi
    
    ensure_dir "$backup_dir"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local basename
    basename=$(basename "$file")
    local backup_path="${backup_dir}/${basename}.${timestamp}.bak"
    
    cp "$file" "$backup_path" || return 1
    echo "$backup_path"
}

#===============================================================================
# Print Functions
#===============================================================================

# Print banner
print_banner() {
    local title="$1"
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}$title${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
}

# Print section header
print_section() {
    echo -e "\n${CYAN}▶ $1${NC}"
    echo -e "${CYAN}$(printf '=%.0s' $(seq 1 ${#1}))${NC}"
}

# Print table row
print_row() {
    printf "%-20s %s\n" "$1" "$2"
}

# Print progress bar
print_progress() {
    local current="$1"
    local total="$2"
    local width="${3:-40}"
    local label="${4:-Progress}"
    
    local percent=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))
    
    printf "\r%s: [%s%s] %3d%% (%d/%d)" \
        "$label" \
        "$(printf '#%.0s' $(seq 1 $filled))" \
        "$(printf ' %.0s' $(seq 1 $empty))" \
        "$percent" \
        "$current" \
        "$total"
}

#===============================================================================
# Error Handling
#===============================================================================

# Set error handler
set_error_handler() {
    local cleanup_func="${1:-}"
    
    handle_error() {
        local line=$1
        local script=$2
        error "Error in $script at line $line"
        if [[ -n "$cleanup_func" ]] && declare -f "$cleanup_func" >/dev/null; then
            $cleanup_func
        fi
        exit 1
    }
    
    trap 'handle_error $LINENO "${BASH_SOURCE[0]}"' ERR
}

#===============================================================================
# RPC Helper Functions
#===============================================================================

# Make JSON-RPC call
xdc_rpc_call() {
    local method="$1"
    local params="${2:-[]}"
    local rpc_url="${3:-http://localhost:8545}"
    
    local payload
    payload=$(jq -n \
        --arg method "$method" \
        --argjson params "$params" \
        '{jsonrpc:"2.0",method:$method,params:$params,id:1}')
    
    curl -s -m 10 -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null
}

#===============================================================================
# Version Functions
#===============================================================================

# Get node version
get_node_version() {
    local rpc_url="${1:-http://localhost:8545}"
    
    local response
    response=$(xdc_rpc_call "web3_clientVersion" "[]" "$rpc_url")
    echo "$response" | jq -r '.result // "unknown"' 2>/dev/null || echo "unknown"
}

# Compare version strings (returns 0 if v1 >= v2)
version_gte() {
    local v1="$1"
    local v2="$2"
    
    # Remove 'v' prefix if present
    v1="${v1#v}"
    v2="${v2#v}"
    
    # Use sort -V for version comparison
    local higher
    higher=$(printf '%s\n%s' "$v1" "$v2" | sort -V | tail -n1)
    
    [[ "$higher" == "$v1" ]]
}

#===============================================================================
# Export Functions
#===============================================================================

# Export all functions for use when sourced
export -f log info warn error die success
export -f check_commands detect_network get_block_height check_sync_status get_peer_count
export -f validate_json validate_ip validate_port
export -f iso_timestamp timestamp format_duration
export -f is_container_running get_container_health
export -f ensure_dir backup_file
export -f print_banner print_section print_row print_progress
export -f set_error_handler
export -f xdc_rpc_call get_node_version version_gte
