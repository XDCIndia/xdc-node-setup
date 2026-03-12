#!/bin/bash
# Remove duplicate logging functions across XDC-Node-Setup
# Centralizes all logging to scripts/lib/logging.sh

set -euo pipefail

echo "Refactoring duplicate logging functions..."

# 1. Update common.sh to source logging.sh instead of duplicating
cat > scripts/lib/common.sh << 'COMMON'
#!/bin/bash
# Common utility functions for XDC Node Setup scripts
# Sources unified logging library

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source unified logging
source "${SCRIPT_DIR}/logging.sh"

# Color codes (for backward compatibility)
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Backward compatibility aliases
log() {
    log_info "$@"
}

info() {
    log_info "$@"
}

warn() {
    log_warn "$@"
}

error() {
    log_error "$@"
}

# Rest of common.sh utility functions remain unchanged
get_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
}

command_exists() {
    command -v "$1" &> /dev/null
}

retry() {
    local max_attempts=${1}
    shift
    local delay=5
    local attempt=1

    until "$@"; do
        if ((attempt == max_attempts)); then
            error "Command failed after $max_attempts attempts"
            return 1
        fi
        log_warn "Attempt $attempt/$max_attempts failed. Retrying in ${delay}s..."
        sleep $delay
        ((attempt++))
        ((delay *= 2))
    done
}

wait_for_port() {
    local host="${1:-localhost}"
    local port="${2:-8545}"
    local timeout="${3:-120}"
    local elapsed=0
    local interval=5

    log_info "Waiting for $host:$port to be ready..."
    
    while ! nc -z "$host" "$port" 2>/dev/null; do
        if ((elapsed >= timeout)); then
            log_error "Timeout waiting for $host:$port"
            return 1
        fi
        sleep $interval
        ((elapsed += interval))
    done
    
    log_info "$host:$port is ready!"
}

ensure_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log_info "Created directory: $dir"
    fi
}

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp "$file" "${file}.backup.$(date +%Y%m%d-%H%M%S)"
        log_info "Backed up: $file"
    fi
}

get_latest_github_release() {
    local repo="$1"
    curl -s "https://api.github.com/repos/$repo/releases/latest" \
        | grep '"tag_name":' \
        | sed -E 's/.*"([^"]+)".*/\1/'
}

download_with_progress() {
    local url="$1"
    local output="$2"
    
    if command_exists wget; then
        wget --progress=bar:force -O "$output" "$url"
    elif command_exists curl; then
        curl -# -L -o "$output" "$url"
    else
        log_error "Neither wget nor curl found"
        return 1
    fi
}
COMMON

echo "✅ Updated scripts/lib/common.sh to source logging.sh"

# 2. Update cis-benchmark.sh to use logging.sh
sed -i '131,133d' scripts/cis-benchmark.sh
sed -i '7a source "$(dirname "$0")/lib/logging.sh"' scripts/cis-benchmark.sh

echo "✅ Updated scripts/cis-benchmark.sh to use lib/logging.sh"

# 3. Update validate-consensus.sh to use logging.sh
sed -i '15,16d' scripts/validate-consensus.sh
sed -i '3a source "$(dirname "$0")/lib/logging.sh"' scripts/validate-consensus.sh

echo "✅ Updated scripts/validate-consensus.sh to use lib/logging.sh"

echo ""
echo "Duplicate logging functions removed successfully!"
echo "All scripts now use centralized scripts/lib/logging.sh"
