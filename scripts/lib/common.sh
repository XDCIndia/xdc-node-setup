#!/bin/bash
# Common utility functions shared across XDC Node Setup scripts
# Avoids duplication of logging, RPC, and helper functions

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
log() { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1" >&2; }
error() { echo -e "${RED}✗${NC} $1" >&2; }
die() { error "$1"; exit 1; }

# RPC helper
rpc_call() {
    local method="$1"
    local params="${2:-[]}"
    local rpc_url="${RPC_URL:-http://127.0.0.1:8545}"
    
    curl -sf -m 10 -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}"
}

# Hex to decimal conversion
hex_to_dec() {
    local hex="$1"
    hex="${hex#0x}"  # Remove 0x prefix if present
    echo $((16#$hex))
}

# Format bytes to human readable
format_bytes() {
    local bytes=$1
    if (( bytes < 1024 )); then
        echo "${bytes}B"
    elif (( bytes < 1048576 )); then
        echo "$(( bytes / 1024 ))KB"
    elif (( bytes < 1073741824 )); then
        echo "$(( bytes / 1048576 ))MB"
    else
        echo "$(( bytes / 1073741824 ))GB"
    fi
}

# Wei to XDC conversion
wei_to_xdc() {
    local wei=$1
    awk "BEGIN {printf \"%.2f\", $wei / 1000000000000000000}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Ensure required commands are available
check_prerequisites() {
    local required_cmds=("$@")
    local missing=()
    
    for cmd in "${required_cmds[@]}"; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        die "Missing required commands: ${missing[*]}"
    fi
}

