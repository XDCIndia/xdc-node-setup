#!/usr/bin/env bash
#==============================================================================
# Common Shell Library (Issue #508, #481, #507)
# Source this in all scripts for consistent error handling
#==============================================================================

# Strict mode
set -euo pipefail

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# Logging
log_info()  { echo -e "${GREEN}[INFO]${NC}  $(date '+%H:%M:%S') $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $(date '+%H:%M:%S') $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $*" >&2; }
log_debug() { [[ "${DEBUG:-0}" == "1" ]] && echo -e "${BLUE}[DEBUG]${NC} $(date '+%H:%M:%S') $*"; }

# Error trap - catches unexpected failures
trap_error() {
    local exit_code=$?
    local line_no=$1
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed at line $line_no with exit code $exit_code"
        log_error "Command: ${BASH_COMMAND:-unknown}"
    fi
}
trap 'trap_error ${LINENO}' ERR

# Cleanup trap
CLEANUP_FUNCTIONS=()
register_cleanup() {
    CLEANUP_FUNCTIONS+=("$1")
}

run_cleanup() {
    for fn in "${CLEANUP_FUNCTIONS[@]:-}"; do
        [[ -n "$fn" ]] && eval "$fn" 2>/dev/null || true
    done
}
trap run_cleanup EXIT

# Safe command execution with retry
safe_exec() {
    local retries="${1:-3}"
    local delay="${2:-5}"
    shift 2
    local cmd="$*"
    
    for ((i=1; i<=retries; i++)); do
        if eval "$cmd"; then
            return 0
        fi
        if [[ $i -lt $retries ]]; then
            log_warn "Command failed (attempt $i/$retries), retrying in ${delay}s..."
            sleep "$delay"
        fi
    done
    log_error "Command failed after $retries attempts: $cmd"
    return 1
}

# Issue #507: Secure download with checksum verification
secure_download() {
    local url="$1"
    local output="$2"
    local expected_checksum="${3:-}"
    
    log_info "Downloading: $url"
    
    # Use HTTPS only
    if [[ "$url" != https://* ]]; then
        log_error "Refusing to download from non-HTTPS URL: $url"
        return 1
    fi
    
    # Download
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --proto '=https' --tlsv1.2 -o "$output" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --https-only -O "$output" "$url"
    else
        log_error "Neither curl nor wget available"
        return 1
    fi
    
    # Verify checksum if provided
    if [[ -n "$expected_checksum" ]]; then
        local actual_checksum
        actual_checksum=$(sha256sum "$output" | cut -d' ' -f1)
        if [[ "$actual_checksum" != "$expected_checksum" ]]; then
            log_error "Checksum mismatch!"
            log_error "  Expected: $expected_checksum"
            log_error "  Got:      $actual_checksum"
            rm -f "$output"
            return 1
        fi
        log_info "Checksum verified ✅"
    fi
    
    return 0
}

# Check required commands exist
require_commands() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        return 1
    fi
}

# Check if running as root
require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Port availability check
check_port() {
    local port="$1"
    if ss -tlnp 2>/dev/null | grep -q ":${port} " || \
       netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
        return 1  # Port in use
    fi
    return 0  # Port available
}

# Docker helpers
docker_running() {
    docker info >/dev/null 2>&1
}

container_exists() {
    docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${1}$"
}

container_running() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${1}$"
}

# RPC helper
rpc_call() {
    local url="${RPC_URL:-http://127.0.0.1:8545}"
    local method="$1"
    local params="${2:-[]}"
    
    curl -sf -m 10 -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" 2>/dev/null
}
