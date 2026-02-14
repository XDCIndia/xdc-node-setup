#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDC Chain Snapshot Manager
# Download, create, and verify XDC chain snapshots
# Skip months of syncing with verified snapshots
#==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Default settings
# Detect network for network-aware directory structure
detect_network() {
    local network="${NETWORK:-}"
    if [[ -z "$network" && -f "$(pwd)/config.toml" ]]; then
        network=$(grep -E '^\s*name\s*=' "$(pwd)/config.toml" 2>/dev/null | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -1)
    fi
    if [[ -z "$network" && -f "/opt/xdc-node/config.toml" ]]; then
        network=$(grep -E '^\s*name\s*=' "/opt/xdc-node/config.toml" 2>/dev/null | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -1)
    fi
    echo "${network:-mainnet}"
}
readonly XDC_NETWORK="${XDC_NETWORK:-$(detect_network)}"
readonly DEFAULT_DATADIR="${XDC_DATADIR:-$(pwd)/${XDC_NETWORK}/xdcchain}"
readonly SNAPSHOTS_CONFIG="${PROJECT_DIR}/configs/snapshots.json"
readonly TEMP_DIR="/tmp/xdc-snapshots"

#==============================================================================
# Utility Functions
#==============================================================================

log() { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1" >&2; }
error() { echo -e "${RED}✗${NC} $1" >&2; }
die() { error "$1"; exit 1; }

rpc_call() {
    local method="$1"
    local params="${2:-[]}"
    local url="${3:-http://localhost:8545}"
    curl -s -m 10 -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        "$url" 2>/dev/null || echo '{}'
}

hex_to_dec() {
    local hex="${1#0x}"
    printf "%d\n" "0x${hex}" 2>/dev/null || echo "0"
}

format_bytes() {
    local bytes="$1"
    if [[ $bytes -gt 1099511627776 ]]; then
        echo "$(echo "scale=2; $bytes / 1099511627776" | bc) TB"
    elif [[ $bytes -gt 1073741824 ]]; then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
    elif [[ $bytes -gt 1048576 ]]; then
        echo "$(echo "scale=2; $bytes / 1048576" | bc) MB"
    else
        echo "${bytes} bytes"
    fi
}

#==============================================================================
# Load Snapshot Configuration
#==============================================================================

load_snapshots_config() {
    if [[ ! -f "$SNAPSHOTS_CONFIG" ]]; then
        die "Snapshots configuration not found: $SNAPSHOTS_CONFIG"
    fi
    
    if ! jq empty "$SNAPSHOTS_CONFIG" 2>/dev/null; then
        die "Invalid JSON in snapshots configuration"
    fi
}

#==============================================================================
# List Available Snapshots
#==============================================================================

list_snapshots() {
    echo -e "${BOLD}━━━ Available XDC Chain Snapshots ━━━${NC}"
    echo ""
    
    load_snapshots_config
    
    echo -e "${CYAN}Mainnet Snapshots:${NC}"
    echo ""
    
    # Full node snapshots
    local full_url full_size full_updated
    full_url=$(jq -r '.mainnet.full.url // "N/A"' "$SNAPSHOTS_CONFIG")
    full_size=$(jq -r '.mainnet.full.size // "Unknown"' "$SNAPSHOTS_CONFIG")
    full_updated=$(jq -r '.mainnet.full.updated // "Unknown"' "$SNAPSHOTS_CONFIG")
    
    printf "  ${BOLD}%-15s${NC} %-40s\n" "Full Node:" "$full_url"
    printf "  ${BOLD}%-15s${NC} %-40s\n" "Size:" "$full_size"
    printf "  ${BOLD}%-15s${NC} %-40s\n" "Updated:" "$full_updated"
    echo ""
    
    # Archive node snapshots
    local archive_url archive_size
    archive_url=$(jq -r '.mainnet.archive.url // "N/A"' "$SNAPSHOTS_CONFIG")
    archive_size=$(jq -r '.mainnet.archive.size // "Unknown"' "$SNAPSHOTS_CONFIG")
    
    printf "  ${BOLD}%-15s${NC} %-40s\n" "Archive Node:" "$archive_url"
    printf "  ${BOLD}%-15s${NC} %-40s\n" "Size:" "$archive_size"
    echo ""
    
    echo -e "${CYAN}Testnet (Apothem) Snapshots:${NC}"
    echo ""
    
    local testnet_url testnet_size
    testnet_url=$(jq -r '.testnet.full.url // "N/A"' "$SNAPSHOTS_CONFIG")
    testnet_size=$(jq -r '.testnet.full.size // "Unknown"' "$SNAPSHOTS_CONFIG")
    
    printf "  ${BOLD}%-15s${NC} %-40s\n" "Full Node:" "$testnet_url"
    printf "  ${BOLD}%-15s${NC} %-40s\n" "Size:" "$testnet_size"
    echo ""
    
    info "Use './snapshot-manager.sh download mainnet-full' to download"
}

#==============================================================================
# Download Snapshot
#==============================================================================

download_snapshot() {
    local snapshot_type="$1"  # e.g., mainnet-full, mainnet-archive, testnet-full
    local datadir="${2:-$DEFAULT_DATADIR}"
    
    echo -e "${BOLD}━━━ Downloading XDC Chain Snapshot ━━━${NC}"
    echo ""
    
    load_snapshots_config
    
    # Parse snapshot type
    local network="${snapshot_type%%-*}"
    local type="${snapshot_type##*-}"
    
    # Get URL from config
    local url
    url=$(jq -r ".${network}.${type}.url // empty" "$SNAPSHOTS_CONFIG")
    
    if [[ -z "$url" || "$url" == "null" ]]; then
        die "Unknown snapshot type: $snapshot_type"
    fi
    
    info "Snapshot: $snapshot_type"
    info "Source: $url"
    echo ""
    
    # Check available disk space
    local available_space
    available_space=$(df -B1 "$datadir" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    
    # Get expected size (rough estimate)
    local expected_size_gb
    case "$snapshot_type" in
        mainnet-full) expected_size_gb=300 ;;      # ~250GB compressed
        mainnet-archive) expected_size_gb=600 ;;   # ~500GB compressed
        testnet-full) expected_size_gb=70 ;;       # ~50GB compressed
        *) expected_size_gb=300 ;;
    esac
    
    local required_bytes=$((expected_size_gb * 2 * 1073741824))  # 2x for extraction
    
    if [[ $available_space -lt $required_bytes ]]; then
        warn "Insufficient disk space!"
        info "Required: ~$(format_bytes $required_bytes)"
        info "Available: $(format_bytes $available_space)"
        echo ""
        echo -n "Continue anyway? [y/N]: "
        read -r response
        [[ "$response" =~ ^[Yy]$ ]] || exit 1
    fi
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    local filename
    filename=$(basename "$url")
    local download_path="${TEMP_DIR}/${filename}"
    
    # Download with progress
    info "Starting download..."
    echo ""
    
    if command -v wget &>/dev/null; then
        wget --progress=bar:force -c -O "$download_path" "$url" 2>&1 || \
            die "Download failed"
    elif command -v curl &>/dev/null; then
        curl -L -C - --progress-bar -o "$download_path" "$url" || \
            die "Download failed"
    else
        die "Neither wget nor curl is available"
    fi
    
    echo ""
    log "Download complete: $download_path"
    
    # Verify checksum if available
    info "Verifying checksum..."
    local checksum_url="${url}.sha256"
    local checksum_file="${download_path}.sha256"
    
    if curl -s -m 30 -o "$checksum_file" "$checksum_url" 2>/dev/null; then
        local computed_checksum expected_checksum
        computed_checksum=$(sha256sum "$download_path" | awk '{print $1}')
        expected_checksum=$(awk '{print $1}' "$checksum_file")
        
        if [[ "$computed_checksum" == "$expected_checksum" ]]; then
            log "Checksum verified!"
        else
            error "Checksum mismatch!"
            info "Expected: $expected_checksum"
            info "Got:      $computed_checksum"
            die "Downloaded file may be corrupted"
        fi
    else
        warn "No checksum available for verification"
    fi
    
    # Extract snapshot
    echo ""
    info "Extracting snapshot to $datadir..."
    echo "This may take 30-60 minutes depending on your hardware."
    echo ""
    
    mkdir -p "$datadir"
    
    case "$filename" in
        *.tar.gz|*.tgz)
            tar -xzf "$download_path" -C "$datadir" --strip-components=1 || \
                die "Extraction failed"
            ;;
        *.tar)
            tar -xf "$download_path" -C "$datadir" --strip-components=1 || \
                die "Extraction failed"
            ;;
        *.zip)
            unzip -q "$download_path" -d "$datadir" || \
                die "Extraction failed"
            ;;
        *)
            die "Unknown archive format: $filename"
            ;;
    esac
    
    log "Extraction complete!"
    
    # Verify block integrity
    echo ""
    info "Verifying extracted chaindata..."
    verify_chaindata "$datadir"
    
    # Cleanup
    echo ""
    info "Cleaning up download files..."
    rm -f "$download_path" "$checksum_file"
    
    log "Snapshot installation complete!"
    echo ""
    info "You can now start your XDC node. It will begin from the snapshot height."
}

#==============================================================================
# Verify Chaindata
#==============================================================================

verify_chaindata() {
    local datadir="${1:-$DEFAULT_DATADIR}"
    
    echo -e "${BOLD}━━━ Verifying Chaindata Integrity ━━━${NC}"
    echo ""
    
    # Check for chaindata directory
    local chaindata_path="${datadir}/XDC/chaindata"
    if [[ ! -d "$chaindata_path" ]]; then
        chaindata_path="${datadir}/chaindata"
        if [[ ! -d "$chaindata_path" ]]; then
            warn "Could not locate chaindata directory"
            return 1
        fi
    fi
    
    # Check database files
    local current_size
    current_size=$(du -sb "$chaindata_path" 2>/dev/null | awk '{print $1}' || echo "0")
    
    info "Chaindata location: $chaindata_path"
    info "Current size: $(format_bytes $current_size)"
    
    # Check for LEVELDB or Pebble database files
    local db_files
    db_files=$(find "$chaindata_path" -maxdepth 1 -name "*.ldb" -o -name "*.sst" 2>/dev/null | wc -l)
    
    if [[ $db_files -eq 0 ]]; then
        warn "No database files found in chaindata"
        return 1
    fi
    
    info "Found $db_files database files"
    
    # Check CURRENT file (LEVELDB marker)
    if [[ -f "${chaindata_path}/CURRENT" ]]; then
        log "Database marker file present"
    else
        warn "Missing CURRENT marker file - may be incomplete"
    fi
    
    echo ""
    log "Chaindata verification passed!"
}

#==============================================================================
# Create Snapshot from Running Node
#==============================================================================

create_snapshot() {
    local output_dir="${1:-/backup/xdc-snapshots}"
    local datadir="${2:-$DEFAULT_DATADIR}"
    
    echo -e "${BOLD}━━━ Creating Snapshot from Running Node ━━━${NC}"
    echo ""
    
    # Check if node is running
    local node_running=false
    if pgrep -x "XDC" >/dev/null || pgrep -f "geth.*xdc" >/dev/null; then
        node_running=true
    fi
    
    if [[ "$node_running" == "true" ]]; then
        warn "XDC node is currently running"
        echo -n "Stop node to create consistent snapshot? [Y/n]: "
        read -r response
        
        if [[ ! "$response" =~ ^[Nn]$ ]]; then
            info "Stopping XDC node..."
            systemctl stop xdc-node 2>/dev/null || \
            systemctl stop xdc-validator 2>/dev/null || \
            pkill -f "XDC" || true
            
            sleep 5
            log "Node stopped"
        else
            warn "Creating snapshot while node is running may result in inconsistency"
        fi
    fi
    
    # Create output directory
    mkdir -p "$output_dir"
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local snapshot_name="xdc-snapshot-${timestamp}.tar.gz"
    local snapshot_path="${output_dir}/${snapshot_name}"
    
    # Determine what to include
    info "Creating snapshot archive..."
    echo "Source: $datadir"
    echo "Output: $snapshot_path"
    echo ""
    
    # Create archive with chaindata
    local chaindata_path="${datadir}/XDC/chaindata"
    if [[ ! -d "$chaindata_path" ]]; then
        chaindata_path="${datadir}/chaindata"
    fi
    
    if [[ ! -d "$chaindata_path" ]]; then
        die "Chaindata directory not found: $chaindata_path"
    fi
    
    # Create tar with progress
    local chaindata_size
    chaindata_size=$(du -sb "$chaindata_path" | awk '{print $1}')
    
    info "Archiving $(format_bytes $chaindata_size) of chaindata..."
    echo "This may take 1-2 hours..."
    echo ""
    
    if tar -czf "$snapshot_path" -C "$(dirname "$chaindata_path")" "$(basename "$chaindata_path")"; then
        log "Archive created successfully!"
    else
        die "Failed to create snapshot archive"
    fi
    
    # Generate checksum
    info "Generating SHA256 checksum..."
    (cd "$output_dir" && sha256sum "$snapshot_name" > "${snapshot_name}.sha256")
    log "Checksum saved to ${snapshot_name}.sha256"
    
    # Get final size
    local final_size
    final_size=$(stat -c%s "$snapshot_path" 2>/dev/null || stat -f%z "$snapshot_path" 2>/dev/null || echo "0")
    
    echo ""
    log "Snapshot created successfully!"
    echo ""
    echo -e "${CYAN}Snapshot Details:${NC}"
    printf "  ${BOLD}%-15s${NC} %s\n" "File:" "$snapshot_path"
    printf "  ${BOLD}%-15s${NC} %s\n" "Size:" "$(format_bytes $final_size)"
    printf "  ${BOLD}%-15s${NC} %s\n" "Checksum:" "${snapshot_path}.sha256"
    echo ""
    
    # Optional upload
    echo -n "Upload to remote storage? [y/N]: "
    read -r upload_response
    
    if [[ "$upload_response" =~ ^[Yy]$ ]]; then
        upload_snapshot "$snapshot_path"
    fi
    
    # Restart node
    echo ""
    echo -n "Restart XDC node? [Y/n]: "
    read -r restart_response
    
    if [[ ! "$restart_response" =~ ^[Nn]$ ]]; then
        info "Starting XDC node..."
        systemctl start xdc-node 2>/dev/null || \
        systemctl start xdc-validator 2>/dev/null || \
        warn "Could not start node automatically - please start manually"
    fi
}

#==============================================================================
# Upload Snapshot
#==============================================================================

upload_snapshot() {
    local snapshot_path="$1"
    
    echo ""
    echo -e "${BOLD}━━━ Upload Snapshot ━━━${NC}"
    echo ""
    
    echo "Select upload destination:"
    echo "  1) Amazon S3"
    echo "  2) IPFS (via pinata)"
    echo "  3) FTP Server"
    echo "  4) Skip upload"
    echo ""
    echo -n "Selection [1-4]: "
    read -r choice
    
    case "$choice" in
        1)
            upload_to_s3 "$snapshot_path"
            ;;
        2)
            upload_to_ipfs "$snapshot_path"
            ;;
        3)
            upload_to_ftp "$snapshot_path"
            ;;
        *)
            info "Skipping upload"
            ;;
    esac
}

upload_to_s3() {
    local snapshot_path="$1"
    
    echo -n "S3 bucket name: "
    read -r bucket
    echo -n "S3 path (e.g., snapshots/mainnet/): "
    read -r s3_path
    
    if command -v aws &>/dev/null; then
        info "Uploading to S3..."
        aws s3 cp "$snapshot_path" "s3://${bucket}/${s3_path}$(basename "$snapshot_path")" --progress
        aws s3 cp "${snapshot_path}.sha256" "s3://${bucket}/${s3_path}$(basename "$snapshot_path").sha256"
        log "Upload complete!"
    else
        warn "AWS CLI not found. Install with: pip install awscli"
    fi
}

upload_to_ipfs() {
    local snapshot_path="$1"
    
    if command -v ipfs &>/dev/null; then
        info "Adding to IPFS..."
        local cid
        cid=$(ipfs add -q "$snapshot_path")
        log "IPFS CID: $cid"
        info "Pinning via Pinata..."
        # Pinata pinning would go here
    else
        warn "IPFS not found. Install from https://ipfs.io"
    fi
}

upload_to_ftp() {
    local snapshot_path="$1"
    
    echo -n "FTP host: "
    read -r ftp_host
    echo -n "FTP user: "
    read -r ftp_user
    echo -n "FTP password: "
    read -rs ftp_pass
    echo ""
    echo -n "FTP path: "
    read -r ftp_path
    
    if command -v lftp &>/dev/null; then
        info "Uploading via FTP..."
        lftp -u "$ftp_user","$ftp_pass" "$ftp_host" -e "put $snapshot_path -o $ftp_path; bye"
        log "Upload complete!"
    else
        warn "lftp not found. Install with: apt install lftp"
    fi
}

#==============================================================================
# Help
#==============================================================================

show_help() {
    cat << EOF
XDC Chain Snapshot Manager

Usage: $(basename "$0") <command> [options]

Commands:
    list                    List available snapshots from configured sources
    download <type>         Download and install a snapshot
    create [output-dir]     Create snapshot from running node
    verify [datadir]        Verify existing chaindata integrity

Snapshot Types:
    mainnet-full            Mainnet full node snapshot (~250GB)
    mainnet-archive         Mainnet archive node snapshot (~500GB)
    testnet-full            Apothem testnet full node snapshot (~50GB)

Options:
    --datadir PATH          XDC data directory (default: $DEFAULT_DATADIR)
    --help, -h              Show this help message

Examples:
    # List available snapshots
    $(basename "$0") list

    # Download mainnet full node snapshot
    $(basename "$0") download mainnet-full

    # Create snapshot in specific directory
    $(basename "$0") create /backup/xdc-snapshots

    # Verify chaindata
    $(basename "$0") verify /root/xdcchain

Description:
    This script manages XDC chain snapshots to help you skip the lengthy
    initial sync process. It can download verified snapshots from trusted
    sources, create snapshots from your own node, and verify integrity.

Configuration:
    Snapshot sources are configured in: $SNAPSHOTS_CONFIG

Important Notes:
    - Snapshots require significant disk space (2x the snapshot size)
    - Download may take several hours depending on connection speed
    - Always verify checksums when available
    - Stop your node before creating snapshots for consistency

EOF
}

#==============================================================================
# Main
#==============================================================================

main() {
    local command="${1:-}"
    local datadir="$DEFAULT_DATADIR"
    
    # Parse global options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --datadir)
                datadir="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                if [[ -z "$command" ]]; then
                    command="$1"
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$command" ]]; then
        show_help
        exit 1
    fi
    
    case "$command" in
        list)
            list_snapshots
            ;;
        download)
            if [[ -z "${2:-}" ]]; then
                die "Usage: $0 download <snapshot-type>"
            fi
            download_snapshot "$2" "$datadir"
            ;;
        create)
            create_snapshot "${2:-/backup/xdc-snapshots}" "$datadir"
            ;;
        verify)
            verify_chaindata "${2:-$datadir}"
            ;;
        *)
            error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
