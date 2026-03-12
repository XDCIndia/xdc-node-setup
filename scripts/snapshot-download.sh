#!/bin/bash
# Automated snapshot download with verification and resume support

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"

# Configuration
SNAPSHOT_URL="${SNAPSHOT_URL:-https://download.xinfin.network/xdcchain-testnet.tar}"
SNAPSHOT_CHECKSUM_URL="${SNAPSHOT_CHECKSUM_URL:-https://download.xinfin.network/xdcchain-testnet.tar.sha256}"
SNAPSHOT_DIR="${SNAPSHOT_DIR:-/tmp/xdc-snapshot}"
DATA_DIR="${DATA_DIR:-/xdcchain}"
MAX_RETRIES=3

info "XDC Snapshot Download Tool"
info "==========================="

# Create directories
mkdir -p "$SNAPSHOT_DIR"

download_with_resume() {
    local url=$1
    local output=$2
    local retry_count=0
    
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        info "Downloading $(basename "$output") (attempt $((retry_count + 1))/$MAX_RETRIES)..."
        
        if wget -c -O "$output" "$url" --progress=bar:force 2>&1; then
            info "Download complete: $output"
            return 0
        else
            warn "Download failed (attempt $((retry_count + 1)))"
            retry_count=$((retry_count + 1))
            sleep 5
        fi
    done
    
    error "Failed to download after $MAX_RETRIES attempts"
    return 1
}

verify_checksum() {
    local file=$1
    local checksum_file=$2
    
    if [[ ! -f "$checksum_file" ]]; then
        warn "Checksum file not found, skipping verification"
        return 0
    fi
    
    info "Verifying checksum..."
    if (cd "$(dirname "$file")" && sha256sum -c "$checksum_file"); then
        info "✓ Checksum verification passed"
        return 0
    else
        error "✗ Checksum verification failed!"
        return 1
    fi
}

extract_snapshot() {
    local snapshot_file=$1
    local target_dir=$2
    
    info "Extracting snapshot to $target_dir..."
    mkdir -p "$target_dir"
    
    if tar -xvf "$snapshot_file" -C "$target_dir" --strip-components=1; then
        info "✓ Extraction complete"
        return 0
    else
        error "✗ Extraction failed"
        return 1
    fi
}

main() {
    local snapshot_file="$SNAPSHOT_DIR/$(basename "$SNAPSHOT_URL")"
    local checksum_file="$SNAPSHOT_DIR/$(basename "$SNAPSHOT_CHECKSUM_URL")"
    
    # Download checksum
    if [[ -n "$SNAPSHOT_CHECKSUM_URL" ]]; then
        download_with_resume "$SNAPSHOT_CHECKSUM_URL" "$checksum_file" || {
            warn "Checksum download failed, proceeding without verification"
        }
    fi
    
    # Download snapshot with resume support
    download_with_resume "$SNAPSHOT_URL" "$snapshot_file" || exit 1
    
    # Verify checksum
    verify_checksum "$snapshot_file" "$checksum_file" || {
        error "Checksum mismatch - snapshot may be corrupted"
        exit 1
    }
    
    # Extract snapshot
    extract_snapshot "$snapshot_file" "$DATA_DIR" || exit 1
    
    info "==========================="
    info "Snapshot installation complete!"
    info "Data directory: $DATA_DIR"
}

main "$@"
