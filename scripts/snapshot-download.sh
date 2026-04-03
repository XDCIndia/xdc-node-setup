#!/usr/bin/env bash
#==============================================================================
# XDC Snapshot Downloader from xdc.network (Issue #112)
# Downloads snapshots from https://xdc.network/snapshots/<client>-mainnet-latest.tar.gz
# Verifies checksum, extracts to data/<network>/<client>/
# Shows progress with curl
#==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ── Configuration ─────────────────────────────────────────────────────────────
SNAPSHOT_BASE_URL="${SNAPSHOT_BASE_URL:-https://xdc.network/snapshots}"
NETWORK="${NETWORK:-mainnet}"
DATA_DIR="${DATA_DIR:-${PROJECT_DIR}/data}"
DOWNLOAD_CACHE="${DOWNLOAD_CACHE:-/tmp/xdc-snapshots}"
PARALLEL_DOWNLOADS="${PARALLEL_DOWNLOADS:-1}"

# Supported clients
SUPPORTED_CLIENTS=(gp5 erigon reth nm v268)

# Client name mappings for snapshot filenames
declare -A CLIENT_SNAPSHOT_NAMES=(
    [gp5]="gp5"
    [erigon]="erigon"
    [reth]="reth"
    [nm]="nethermind"
    [v268]="v268"
)

declare -A CLIENT_LABELS=(
    [gp5]="GP5 (go-xdc)"
    [erigon]="Erigon XDC"
    [reth]="Reth XDC"
    [nm]="Nethermind XDC"
    [v268]="XDC v2.6.8"
)

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
die()  { echo -e "${RED}✗ Error: $*${RESET}" >&2; exit 1; }
info() { echo -e "${CYAN}ℹ  $*${RESET}"; }
ok()   { echo -e "${GREEN}✓ $*${RESET}"; }
warn() { echo -e "${YELLOW}⚠  $*${RESET}"; }

human_size() {
    local size="$1"
    if   [[ "$size" -ge $((1024*1024*1024)) ]]; then printf "%.1f GB" "$(echo "scale=1; $size/1024/1024/1024" | bc)"
    elif [[ "$size" -ge $((1024*1024))      ]]; then printf "%.1f MB" "$(echo "scale=1; $size/1024/1024" | bc)"
    elif [[ "$size" -ge 1024               ]]; then printf "%.1f KB" "$(echo "scale=1; $size/1024" | bc)"
    else echo "${size} B"; fi
}

check_deps() {
    local missing=()
    for cmd in curl tar sha256sum; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required tools: ${missing[*]}. Install with: apt-get install -y ${missing[*]}"
    fi
    # bc is optional for human_size
    command -v bc >/dev/null 2>&1 || true
}

validate_client() {
    local client="$1"
    for c in "${SUPPORTED_CLIENTS[@]}"; do
        [[ "$c" == "$client" ]] && return 0
    done
    die "Unknown client '${client}'. Supported: ${SUPPORTED_CLIENTS[*]}"
}

check_disk_space() {
    local target_dir="$1" required_bytes="${2:-107374182400}"  # default 100 GB
    local avail_bytes
    avail_bytes=$(df -B1 "$target_dir" 2>/dev/null | awk 'NR==2{print $4}' || echo "0")
    if [[ "$avail_bytes" -lt "$required_bytes" ]]; then
        local req_human avail_human
        req_human=$(human_size "$required_bytes")
        avail_human=$(human_size "$avail_bytes")
        warn "Low disk space in ${target_dir}: ${avail_human} available, ~${req_human} may be needed"
        echo -n "  Continue anyway? [y/N] "
        read -r confirm < /dev/tty
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "Aborted." && exit 0
    fi
}

# ── Download with progress ────────────────────────────────────────────────────
download_file() {
    local url="$1" dest="$2" label="${3:-file}"
    local tmp_dest="${dest}.partial"

    echo -e "${BOLD}📥 Downloading ${label}...${RESET}"
    echo -e "  URL:  ${url}"
    echo -e "  Dest: ${dest}"

    # Check if partial download exists (resume support)
    local resume_flag=()
    if [[ -f "$tmp_dest" ]]; then
        local partial_size
        partial_size=$(stat -c%s "$tmp_dest" 2>/dev/null || echo "0")
        if [[ "$partial_size" -gt 0 ]]; then
            warn "Found partial download ($(human_size "$partial_size")). Attempting resume..."
            resume_flag+=(-C -)
        fi
    fi

    # Download with progress bar
    if curl "${resume_flag[@]}" \
        --progress-bar \
        --location \
        --fail \
        --retry 3 \
        --retry-delay 5 \
        --retry-max-time 300 \
        --connect-timeout 30 \
        -o "$tmp_dest" \
        "$url"; then
        mv "$tmp_dest" "$dest"
        local final_size
        final_size=$(stat -c%s "$dest" 2>/dev/null || echo "0")
        ok "Download complete: $(human_size "$final_size")"
        return 0
    else
        local exit_code=$?
        echo -e "${RED}✗ Download failed (curl exit code: ${exit_code})${RESET}"
        echo -e "  Partial file kept at: ${tmp_dest}"
        return 1
    fi
}

# ── Checksum verification ─────────────────────────────────────────────────────
verify_checksum() {
    local file="$1" checksum_file="${2:-}"

    if [[ -z "$checksum_file" || ! -f "$checksum_file" ]]; then
        warn "No checksum file available — skipping verification"
        return 0
    fi

    echo -e "${BOLD}🔐 Verifying checksum...${RESET}"
    local expected_hash file_name
    file_name=$(basename "$file")

    # Try to find hash in checksum file
    expected_hash=$(grep "$file_name" "$checksum_file" | awk '{print $1}' | head -1 || echo "")

    if [[ -z "$expected_hash" ]]; then
        # Checksum file might just contain the hash
        expected_hash=$(cat "$checksum_file" | awk '{print $1}' | head -1 || echo "")
    fi

    if [[ -z "$expected_hash" ]]; then
        warn "Could not parse expected hash from checksum file — skipping verification"
        return 0
    fi

    echo -e "  Expected: ${expected_hash}"
    echo -n "  Computing hash (this may take a moment for large files)... "
    local actual_hash
    actual_hash=$(sha256sum "$file" | awk '{print $1}')
    echo "$actual_hash"

    if [[ "$actual_hash" == "$expected_hash" ]]; then
        ok "Checksum verified ✓"
        return 0
    else
        echo -e "${RED}${BOLD}✗ CHECKSUM MISMATCH!${RESET}"
        echo -e "  Expected: ${expected_hash}"
        echo -e "  Got:      ${actual_hash}"
        die "Checksum verification failed for ${file}. The download may be corrupted."
    fi
}

# ── Extract snapshot ──────────────────────────────────────────────────────────
extract_snapshot() {
    local archive="$1" target_dir="$2"

    echo ""
    echo -e "${BOLD}📦 Extracting snapshot...${RESET}"
    echo -e "  Archive: ${archive}"
    echo -e "  Target:  ${target_dir}"

    mkdir -p "$target_dir"

    # Detect compression
    local tar_flags="-xf"
    if file "$archive" 2>/dev/null | grep -q "gzip"; then
        tar_flags="-xzf"
    elif file "$archive" 2>/dev/null | grep -q "bzip2"; then
        tar_flags="-xjf"
    elif file "$archive" 2>/dev/null | grep -q "XZ"; then
        tar_flags="-xJf"
    fi

    # Extract with progress (using pv if available, else basic)
    local archive_size
    archive_size=$(stat -c%s "$archive" 2>/dev/null || echo "0")
    echo -e "  Size: $(human_size "$archive_size")"
    echo ""

    if command -v pv >/dev/null 2>&1; then
        pv "$archive" | tar "$tar_flags" - -C "$target_dir" --strip-components=1 2>&1 || \
            tar "$tar_flags" "$archive" -C "$target_dir" --strip-components=1
    else
        # Show periodic progress
        echo -e "  ${DIM}Extracting (no pv found — install 'pv' for progress bar)...${RESET}"
        local start_time=$SECONDS
        if tar "$tar_flags" "$archive" -C "$target_dir" --strip-components=1 \
            --checkpoint=10000 \
            --checkpoint-action="ttyout=Checkpoint #%u\r" 2>/dev/null || \
           tar "$tar_flags" "$archive" -C "$target_dir"; then
            local elapsed=$(( SECONDS - start_time ))
            ok "Extraction complete in ${elapsed}s"
        else
            die "Extraction failed"
        fi
    fi

    # Show extracted size
    local extracted_size
    extracted_size=$(du -sh "$target_dir" 2>/dev/null | awk '{print $1}' || echo "?")
    ok "Extracted to ${target_dir} (${extracted_size})"
}

# ── Main download flow ────────────────────────────────────────────────────────
download_snapshot() {
    local client="$1" network="${2:-$NETWORK}"
    validate_client "$client"

    local snap_name="${CLIENT_SNAPSHOT_NAMES[$client]}"
    local snap_file="${snap_name}-${network}-latest.tar.gz"
    local snap_url="${SNAPSHOT_BASE_URL}/${snap_file}"
    local checksum_url="${snap_url}.sha256"
    local target_dir="${DATA_DIR}/${network}/${client}"

    echo ""
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${CYAN}  XDC Snapshot Download — ${CLIENT_LABELS[$client]}   ${RESET}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════${RESET}"
    echo ""
    echo -e "  Client:  ${CLIENT_LABELS[$client]}"
    echo -e "  Network: ${network}"
    echo -e "  Source:  ${snap_url}"
    echo -e "  Target:  ${target_dir}"
    echo ""

    # Check dependencies
    check_deps

    # Create download cache dir
    mkdir -p "$DOWNLOAD_CACHE"

    # Check disk space
    mkdir -p "$(dirname "$target_dir")"
    check_disk_space "$(dirname "$target_dir")"

    local snap_dest="${DOWNLOAD_CACHE}/${snap_file}"
    local checksum_dest="${DOWNLOAD_CACHE}/${snap_file}.sha256"

    # Download checksum first (small file, no progress needed)
    echo -e "${BOLD}🔑 Fetching checksum...${RESET}"
    if curl -sf --max-time 30 -L --fail "$checksum_url" -o "$checksum_dest" 2>/dev/null; then
        ok "Checksum downloaded: ${checksum_dest}"
    else
        warn "Checksum file not available at ${checksum_url} — will skip verification"
        rm -f "$checksum_dest"
    fi

    # Download snapshot
    if [[ -f "$snap_dest" && ! -f "${snap_dest}.partial" ]]; then
        local existing_size
        existing_size=$(stat -c%s "$snap_dest" 2>/dev/null || echo "0")
        warn "Archive already exists ($(human_size "$existing_size"))"
        echo -n "  Re-download? [y/N] "
        read -r confirm < /dev/tty
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            rm -f "$snap_dest"
            download_file "$snap_url" "$snap_dest" "${CLIENT_LABELS[$client]} snapshot"
        else
            info "Using existing archive."
        fi
    else
        download_file "$snap_url" "$snap_dest" "${CLIENT_LABELS[$client]} snapshot"
    fi

    # Verify checksum
    verify_checksum "$snap_dest" "$checksum_dest"

    # Check if target already has data
    if [[ -d "$target_dir" ]] && [[ -n "$(ls -A "$target_dir" 2>/dev/null)" ]]; then
        warn "Target directory '${target_dir}' already contains data."
        echo -n "  Overwrite existing data? [y/N] "
        read -r confirm < /dev/tty
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Aborted. Snapshot downloaded to ${snap_dest} but not extracted."
            exit 0
        fi
        # Backup existing data
        local backup_dir="${target_dir}.backup-$(date '+%Y%m%d-%H%M%S')"
        echo -e "  Backing up existing data to: ${backup_dir}"
        mv "$target_dir" "$backup_dir" || warn "Could not backup existing data"
    fi

    # Extract
    extract_snapshot "$snap_dest" "$target_dir"

    # Cleanup
    echo ""
    echo -n "  Remove downloaded archive to save disk space? [Y/n] "
    read -r confirm < /dev/tty
    if [[ "$confirm" != "n" && "$confirm" != "N" ]]; then
        rm -f "$snap_dest" "$checksum_dest"
        ok "Cleaned up download cache"
    else
        info "Archive kept at: ${snap_dest}"
    fi

    echo ""
    echo -e "${GREEN}${BOLD}✅ Snapshot ready at: ${target_dir}${RESET}"
    echo ""
}

# ── List available snapshots ──────────────────────────────────────────────────
cmd_list() {
    echo ""
    echo -e "${BOLD}${CYAN}📋 Available XDC Snapshots${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────${RESET}"
    printf "${BOLD}%-12s %-10s %-50s${RESET}\n" "CLIENT" "NETWORK" "URL"

    for client in "${SUPPORTED_CLIENTS[@]}"; do
        local snap_name="${CLIENT_SNAPSHOT_NAMES[$client]}"
        for network in mainnet testnet; do
            local url="${SNAPSHOT_BASE_URL}/${snap_name}-${network}-latest.tar.gz"
            printf "%-12s %-10s %-50s\n" "${client}" "${network}" "${url}"
        done
    done
    echo ""
    echo -e "${DIM}Checksum URLs: append .sha256 to any URL above${RESET}"
    echo ""
}

# ── Status: show existing snapshots ──────────────────────────────────────────
cmd_status() {
    echo ""
    echo -e "${BOLD}${CYAN}📊 Local Snapshot Status${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────${RESET}"
    printf "${BOLD}%-12s %-10s %-10s %-30s${RESET}\n" "CLIENT" "NETWORK" "SIZE" "PATH"

    for client in "${SUPPORTED_CLIENTS[@]}"; do
        for network in mainnet testnet; do
            local dir="${DATA_DIR}/${network}/${client}"
            if [[ -d "$dir" ]]; then
                local sz
                sz=$(du -sh "$dir" 2>/dev/null | awk '{print $1}' || echo "?")
                printf "${GREEN}%-12s${RESET} %-10s %-10s %-30s\n" "$client" "$network" "$sz" "$dir"
            else
                printf "${DIM}%-12s %-10s %-10s %-30s${RESET}\n" "$client" "$network" "-" "(not present)"
            fi
        done
    done
    echo ""
}

# ── Entry point ───────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  download <client> [network]   Download and extract snapshot (default: mainnet)"
    echo "  list                          Show available snapshot URLs"
    echo "  status                        Show locally downloaded snapshots"
    echo ""
    echo "Clients: ${SUPPORTED_CLIENTS[*]}"
    echo "Networks: mainnet, testnet"
    echo ""
    echo "Examples:"
    echo "  $0 download gp5              # Download GP5 mainnet snapshot"
    echo "  $0 download erigon testnet   # Download Erigon testnet snapshot"
    echo "  $0 list                      # List all available snapshots"
    echo ""
    echo "Environment:"
    echo "  SNAPSHOT_BASE_URL   Override base URL (default: https://xdc.network/snapshots)"
    echo "  NETWORK             Default network (default: mainnet)"
    echo "  DATA_DIR            Extraction root (default: <project>/data)"
    echo "  DOWNLOAD_CACHE      Temp download dir (default: /tmp/xdc-snapshots)"
}

case "${1:-help}" in
    download) download_snapshot "${2:-}" "${3:-$NETWORK}" ;;
    list)     cmd_list ;;
    status)   cmd_status ;;
    --help|-h|help) usage ;;
    *) echo "Unknown command: $1"; usage; exit 1 ;;
esac
