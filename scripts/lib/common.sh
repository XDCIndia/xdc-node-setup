#!/bin/bash
# Common utility functions for XDC Node Setup scripts
# Consolidates duplicate functions across multiple scripts

# Color codes for terminal output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_info() {
    log "$@"
}

info() {
    log "$@"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_error() {
    error "$@"
}

die() {
    error "$@"
    exit 1
}

# Banner printing
print_banner() {
    local title="$1"
    echo "=========================================="
    echo "  $title"
    echo "=========================================="
}

# Help/usage functions
show_help() {
    local script_name="${1:-$0}"
    cat <<EOF
Usage: $script_name [OPTIONS]

For detailed help, see documentation.
EOF
}

show_usage() {
    show_help "$@"
}

# Network detection
detect_network() {
    local network_id="${1:-}"
    
    case "$network_id" in
        50) echo "mainnet" ;;
        51) echo "testnet" ;;
        551) echo "devnet" ;;
        *) echo "unknown" ;;
    esac
}

# Prerequisites checking
check_prerequisites() {
    local required_commands=("docker" "docker-compose" "jq" "curl")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            die "$cmd is required but not installed"
        fi
    done
}

# Configuration loading
load_config() {
    local config_file="${1:-.env}"
    
    if [ -f "$config_file" ]; then
        # shellcheck disable=SC1090
        source "$config_file"
    else
        warn "Config file $config_file not found"
    fi
}

# RPC utilities
rpc_call() {
    local url="${1:-http://localhost:8545}"
    local method="$2"
    shift 2
    local params="$*"
    
    curl -s -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":[$params],\"id\":1}"
}

json_rpc() {
    rpc_call "$@"
}

# Hex conversion
hex_to_dec() {
    local hex="$1"
    hex="${hex#0x}"  # Remove 0x prefix
    printf '%d\n' "0x$hex"
}

dec_to_hex() {
    printf '0x%x\n' "$1"
}

# Summary printing
print_summary() {
    local title="$1"
    shift
    
    print_banner "$title"
    for line in "$@"; do
        echo "  $line"
    done
    echo "=========================================="
}

# Report generation
generate_report() {
    local report_file="${1:-report.txt}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > "$report_file" <<EOF
XDC Node Setup Report
Generated: $timestamp
==========================================================
EOF
}

# History display
show_history() {
    local log_file="${1:-/var/log/xdc-node/setup.log}"
    
    if [ -f "$log_file" ]; then
        tail -n 50 "$log_file"
    else
        warn "Log file $log_file not found"
    fi
}

# Ensure this script is sourced, not executed
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    die "This script should be sourced, not executed directly"
fi
