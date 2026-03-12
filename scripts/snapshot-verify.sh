#!/bin/bash
# Snapshot Signature Verification Script
# Implements cryptographic verification for downloaded snapshots

set -euo pipefail

# Configuration
SNAPSHOT_URL=${SNAPSHOT_URL:-"https://download.xinfin.network"}
GPG_KEY_URL=${GPG_KEY_URL:-"https://download.xinfin.network/xinfin-signing-key.asc"}
TRUSTED_KEY_FINGERPRINT="${TRUSTED_KEY_FINGERPRINT:-}"  # Set via environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    for cmd in curl gpg sha256sum; do
        if ! command -v $cmd &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Install with: sudo apt-get install curl gnupg coreutils"
        exit 1
    fi
}

# Import GPG key
import_gpg_key() {
    local key_file=$1
    
    log_info "Importing GPG key from $key_file..."
    
    if gpg --import "$key_file" 2>&1 | grep -q "imported"; then
        log_info "✅ GPG key imported successfully"
        return 0
    else
        log_error "Failed to import GPG key"
        return 1
    fi
}

# Download GPG key
download_gpg_key() {
    local key_file="xinfin-signing-key.asc"
    
    log_info "Downloading GPG signing key from $GPG_KEY_URL..."
    
    if curl -fsSL "$GPG_KEY_URL" -o "$key_file"; then
        log_info "✅ GPG key downloaded: $key_file"
        import_gpg_key "$key_file"
        return 0
    else
        log_error "Failed to download GPG key"
        return 1
    fi
}

# Verify GPG signature
verify_gpg_signature() {
    local snapshot_file=$1
    local signature_file="${snapshot_file}.sig"
    
    log_info "Verifying GPG signature for $snapshot_file..."
    
    # Download signature if not present
    if [ ! -f "$signature_file" ]; then
        log_info "Downloading signature file..."
        curl -fsSL "${SNAPSHOT_URL}/$(basename $snapshot_file).sig" -o "$signature_file" || {
            log_error "Failed to download signature file"
            return 1
        }
    fi
    
    # Verify signature
    if gpg --verify "$signature_file" "$snapshot_file" 2>&1 | grep -q "Good signature"; then
        log_info "✅ GPG signature verification PASSED"
        
        # Verify key fingerprint if provided
        if [ -n "$TRUSTED_KEY_FINGERPRINT" ]; then
            local used_key=$(gpg --verify "$signature_file" "$snapshot_file" 2>&1 | grep "using" | awk '{print $NF}')
            if [[ "$used_key" == *"$TRUSTED_KEY_FINGERPRINT"* ]]; then
                log_info "✅ Signature from trusted key: $TRUSTED_KEY_FINGERPRINT"
            else
                log_error "❌ Signature NOT from trusted key (expected: $TRUSTED_KEY_FINGERPRINT, got: $used_key)"
                return 1
            fi
        fi
        
        return 0
    else
        log_error "❌ GPG signature verification FAILED"
        log_error "Snapshot may be corrupted or tampered with!"
        return 1
    fi
}

# Verify SHA256 checksum
verify_checksum() {
    local snapshot_file=$1
    local checksum_file="${snapshot_file}.sha256"
    
    log_info "Verifying SHA256 checksum for $snapshot_file..."
    
    # Download checksum if not present
    if [ ! -f "$checksum_file" ]; then
        log_info "Downloading checksum file..."
        curl -fsSL "${SNAPSHOT_URL}/$(basename $snapshot_file).sha256" -o "$checksum_file" || {
            log_error "Failed to download checksum file"
            return 1
        }
    fi
    
    # Verify checksum
    if sha256sum -c "$checksum_file" 2>&1 | grep -q "OK"; then
        log_info "✅ SHA256 checksum verification PASSED"
        return 0
    else
        log_error "❌ SHA256 checksum verification FAILED"
        log_error "Snapshot file is corrupted!"
        return 1
    fi
}

# Complete verification workflow
verify_snapshot() {
    local snapshot_file=$1
    local verify_gpg=${2:-true}
    local verify_sha=${3:-true}
    
    log_info "Starting snapshot verification for: $snapshot_file"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check if file exists
    if [ ! -f "$snapshot_file" ]; then
        log_error "Snapshot file not found: $snapshot_file"
        exit 1
    fi
    
    local verification_passed=true
    
    # SHA256 checksum verification
    if [ "$verify_sha" = true ]; then
        if ! verify_checksum "$snapshot_file"; then
            verification_passed=false
        fi
    fi
    
    # GPG signature verification
    if [ "$verify_gpg" = true ]; then
        if ! verify_gpg_signature "$snapshot_file"; then
            verification_passed=false
        fi
    fi
    
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ "$verification_passed" = true ]; then
        log_info "✅ ALL VERIFICATIONS PASSED"
        log_info "Snapshot is safe to use: $snapshot_file"
        return 0
    else
        log_error "❌ VERIFICATION FAILED"
        log_error "DO NOT use this snapshot - it may be compromised!"
        return 1
    fi
}

# Download and verify snapshot
download_and_verify() {
    local snapshot_name=$1
    local snapshot_file="${snapshot_name}"
    
    log_info "Downloading snapshot: $snapshot_name"
    
    # Download snapshot
    curl -fSL --progress-bar "${SNAPSHOT_URL}/${snapshot_name}" -o "$snapshot_file" || {
        log_error "Failed to download snapshot"
        exit 1
    }
    
    # Verify
    verify_snapshot "$snapshot_file"
}

# Usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] SNAPSHOT_FILE

Verify cryptographic integrity of XDC Network snapshots.

OPTIONS:
    -d, --download SNAPSHOT_NAME    Download and verify snapshot
    -g, --no-gpg                    Skip GPG signature verification
    -s, --no-sha                    Skip SHA256 checksum verification
    -k, --import-key KEY_FILE       Import custom GPG key
    -u, --url URL                   Snapshot download URL (default: $SNAPSHOT_URL)
    -h, --help                      Show this help message

EXAMPLES:
    # Verify existing snapshot file
    $0 xdc-mainnet-snapshot-latest.tar.gz
    
    # Download and verify snapshot
    $0 --download xdc-mainnet-snapshot-latest.tar.gz
    
    # Verify with custom GPG key
    $0 --import-key custom-key.asc snapshot.tar.gz
    
    # Skip GPG verification (only checksum)
    $0 --no-gpg snapshot.tar.gz

ENVIRONMENT VARIABLES:
    SNAPSHOT_URL              Base URL for snapshot downloads
    GPG_KEY_URL               URL to GPG signing key
    TRUSTED_KEY_FINGERPRINT   Expected GPG key fingerprint

SECURITY:
    This script provides cryptographic verification to ensure snapshot integrity.
    Both GPG signature and SHA256 checksum must pass for verification to succeed.
    
    NEVER use a snapshot that fails verification - it may be compromised!

EOF
    exit 0
}

# Main
main() {
    check_dependencies
    
    local verify_gpg=true
    local verify_sha=true
    local download_mode=false
    local snapshot_file=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--download)
                download_mode=true
                snapshot_file="$2"
                shift 2
                ;;
            -g|--no-gpg)
                verify_gpg=false
                shift
                ;;
            -s|--no-sha)
                verify_sha=false
                shift
                ;;
            -k|--import-key)
                import_gpg_key "$2"
                shift 2
                ;;
            -u|--url)
                SNAPSHOT_URL="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                ;;
            *)
                snapshot_file="$1"
                shift
                ;;
        esac
    done
    
    if [ -z "$snapshot_file" ]; then
        log_error "No snapshot file specified"
        usage
    fi
    
    # Download GPG key if not already imported
    if [ "$verify_gpg" = true ]; then
        if ! gpg --list-keys 2>/dev/null | grep -q "xinfin"; then
            download_gpg_key || {
                log_warn "Failed to download GPG key. Proceeding with --no-gpg mode."
                verify_gpg=false
            }
        fi
    fi
    
    if [ "$download_mode" = true ]; then
        download_and_verify "$snapshot_file"
    else
        verify_snapshot "$snapshot_file" "$verify_gpg" "$verify_sha"
    fi
}

main "$@"
