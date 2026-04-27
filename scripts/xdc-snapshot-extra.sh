#!/usr/bin/env bash
#===============================================================================
# XDC Snapshot Extra Data Export/Import
# Handles XDPoS voting snapshots and pebble DB metadata not captured by
# standard chaindata snapshots.
#
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/257
#
# Usage:
#   xdc-snapshot-extra.sh export <datadir> <output-dir>
#   xdc-snapshot-extra.sh import <datadir> <input-dir>
#   xdc-snapshot-extra.sh verify <datadir>
#===============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source chaindata lib for subdir detection
source "${SCRIPT_DIR}/lib/chaindata.sh" 2>/dev/null || true

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
die()   { error "$*"; exit 1; }

# Find pebble/leveldb metadata directory
find_metadata_dir() {
    local datadir="$1"
    local subdir=""
    subdir=$(find_chaindata_subdir_or_default "$datadir" 2>/dev/null || echo "")
    
    # Try various locations for XDPoS snapshot DB
    local candidates=(
        "$datadir${subdir:+/$subdir}/XDPoS"
        "$datadir/XDPoS"
        "$datadir/geth/XDPoS"
        "$datadir/xdcchain/XDPoS"
        "$datadir${subdir:+/$subdir}/chaindata/XDPoS"
    )
    
    for cand in "${candidates[@]}"; do
        if [[ -d "$cand" ]]; then
            echo "$cand"
            return 0
        fi
    done
    
    # Check pebble DB for XDPoS keys
    local chaindata_dir="$datadir${subdir:+/$subdir}/chaindata"
    if [[ -d "$chaindata_dir" ]]; then
        # Look for XDPoS snapshot keys in pebble
        if command -v ldb &>/dev/null; then
            local has_xdpos
            has_xdpos=$(ldb scan --db="$chaindata_dir" --hex 2>/dev/null | grep -i "xdpos\|snapshot" | head -1 || true)
            if [[ -n "$has_xdpos" ]]; then
                echo "$chaindata_dir"
                return 0
            fi
        fi
    fi
    
    return 1
}

# Export XDPoS voting snapshots from pebble DB
cmd_export() {
    local datadir="${1:-}"
    local outdir="${2:-}"
    
    [[ -z "$datadir" ]] && die "Usage: xdc-snapshot-extra.sh export <datadir> <output-dir>"
    [[ -z "$outdir" ]] && outdir="$(pwd)/xdc-snapshot-extra-$(date +%Y%m%d-%H%M%S)"
    [[ -d "$datadir" ]] || die "Data directory not found: $datadir"
    
    mkdir -p "$outdir"
    
    info "Exporting XDPoS extra data from $datadir"
    
    local meta_dir
    meta_dir=$(find_metadata_dir "$datadir" 2>/dev/null || echo "")
    
    # 1. Export XDPoS snapshots from pebble DB if ldb is available
    if command -v ldb &>/dev/null && [[ -n "$meta_dir" ]]; then
        info "Found metadata dir: $meta_dir"
        info "Scanning for XDPoS snapshot keys..."
        
        # Export all XDPoS-related keys
        ldb scan --db="$meta_dir" --hex 2>/dev/null | \
            grep -i "xdpos\|snapshot\|masternode\|vote" > "$outdir/xdpos-keys.hex" 2>/dev/null || true
        
        if [[ -s "$outdir/xdpos-keys.hex" ]]; then
            ok "Exported XDPoS keys to $outdir/xdpos-keys.hex"
        else
            warn "No XDPoS keys found in DB"
        fi
        
        # Try to dump specific snapshot entries
        local snapshot_keys
        snapshot_keys=$(ldb scan --db="$meta_dir" --hex 2>/dev/null | \
            grep -i "snapshot" | awk '{print $1}' | head -100 || true)
        
        if [[ -n "$snapshot_keys" ]]; then
            echo "$snapshot_keys" > "$outdir/snapshot-keys.list"
            ok "Found $(echo "$snapshot_keys" | wc -l) snapshot key entries"
        fi
    else
        warn "ldb tool not available or metadata dir not found"
        warn "XDPoS snapshot export requires ldb (apt install leveldb-tools)"
    fi
    
    # 2. Copy XDPoS snapshot files if they exist as separate files
    local xdpos_files=(
        "$datadir/xdpos-snapshots.json"
        "$datadir/XDPoS-snapshots.json"
        "$datadir/geth/xdpos-snapshots.json"
    )
    for f in "${xdpos_files[@]}"; do
        if [[ -f "$f" ]]; then
            cp "$f" "$outdir/"
            ok "Copied $f"
        fi
    done
    
    # 3. Export checkpoint info
    local subdir
    subdir=$(find_chaindata_subdir_or_default "$datadir" 2>/dev/null || echo "")
    local checkpoint_file="$datadir${subdir:+/$subdir}/checkpoint.txt"
    if [[ -f "$checkpoint_file" ]]; then
        cp "$checkpoint_file" "$outdir/"
        ok "Copied checkpoint info"
    fi
    
    # 4. Write metadata
    cat > "$outdir/META.json" <<EOF
{
  "exported_at": "$(date -Iseconds)",
  "datadir": "$datadir",
  "meta_dir": "${meta_dir:-null}",
  "has_ldb": $(command -v ldb &>/dev/null && echo "true" || echo "false"),
  "note": "XDPoS voting snapshots must be restored alongside chaindata to prevent nil pointer panics"
}
EOF
    
    ok "Export complete: $outdir"
    echo ""
    info "Include this directory when creating cold snapshots:"
    info "  tar -czf snapshot.tar.gz chaindir/ xdc-snapshot-extra/"
}

# Import XDPoS voting snapshots
cmd_import() {
    local datadir="${1:-}"
    local indir="${2:-}"
    
    [[ -z "$datadir" || -z "$indir" ]] && die "Usage: xdc-snapshot-extra.sh import <datadir> <input-dir>"
    [[ -d "$datadir" ]] || die "Data directory not found: $datadir"
    [[ -d "$indir" ]] || die "Input directory not found: $indir"
    
    info "Importing XDPoS extra data to $datadir"
    
    # 1. Restore snapshot files
    if [[ -f "$indir/xdpos-snapshots.json" ]]; then
        cp "$indir/xdpos-snapshots.json" "$datadir/"
        ok "Restored xdpos-snapshots.json"
    fi
    
    # 2. Restore checkpoint info
    if [[ -f "$indir/checkpoint.txt" ]]; then
        local subdir
        subdir=$(find_chaindata_subdir_or_default "$datadir" 2>/dev/null || echo "")
        cp "$indir/checkpoint.txt" "$datadir${subdir:+/$subdir}/"
        ok "Restored checkpoint.txt"
    fi
    
    # 3. If we have hex keys and ldb, try to restore to pebble
    if [[ -f "$indir/xdpos-keys.hex" ]] && command -v ldb &>/dev/null; then
        warn "Manual intervention required to restore pebble keys"
        warn "Keys saved in $indir/xdpos-keys.hex"
        warn "Use: ldb load --db=<chaindata> < $indir/xdpos-keys.hex"
    fi
    
    ok "Import complete"
    info "Start node and verify snapshot recovery in logs"
}

# Verify XDPoS snapshot integrity
cmd_verify() {
    local datadir="${1:-}"
    [[ -z "$datadir" ]] && die "Usage: xdc-snapshot-extra.sh verify <datadir>"
    [[ -d "$datadir" ]] || die "Data directory not found: $datadir"
    
    info "Verifying XDPoS snapshot integrity in $datadir"
    
    local errors=0
    
    # Check for snapshot files
    local has_snapshots=false
    local xdpos_files=(
        "$datadir/xdpos-snapshots.json"
        "$datadir/XDPoS-snapshots.json"
        "$datadir/geth/xdpos-snapshots.json"
    )
    for f in "${xdpos_files[@]}"; do
        if [[ -f "$f" ]]; then
            has_snapshots=true
            ok "Found snapshot file: $f"
        fi
    done
    
    # Check pebble DB for XDPoS keys
    local meta_dir
    meta_dir=$(find_metadata_dir "$datadir" 2>/dev/null || echo "")
    if [[ -n "$meta_dir" ]] && command -v ldb &>/dev/null; then
        local key_count
        key_count=$(ldb scan --db="$meta_dir" --hex 2>/dev/null | grep -ci "xdpos\|snapshot" || echo "0")
        if [[ "$key_count" -gt 0 ]]; then
            ok "Found $key_count XDPoS keys in pebble DB"
            has_snapshots=true
        else
            warn "No XDPoS keys found in pebble DB"
        fi
    fi
    
    if [[ "$has_snapshots" == "false" ]]; then
        error "NO XDPoS snapshots found!"
        error "Node will panic on restart with nil pointer dereference"
        error "Run: xdc-snapshot-extra.sh export <source-datadir> <output-dir>"
        ((errors++))
    fi
    
    # Check state root cache
    local cache_found=false
    local cache_candidates=(
        "$datadir/xdc-state-root-cache.csv"
        "$datadir/geth/xdc-state-root-cache.csv"
        "$datadir/XDC/xdc-state-root-cache.csv"
    )
    for cand in "${cache_candidates[@]}"; do
        if [[ -f "$cand" ]]; then
            cache_found=true
            ok "Found state root cache: $cand"
            break
        fi
    done
    
    if [[ "$cache_found" == "false" ]]; then
        warn "State root cache not found — may cause state root mismatches"
    fi
    
    if [[ "$errors" -eq 0 ]]; then
        ok "XDPoS snapshot verification PASSED"
        return 0
    else
        error "XDPoS snapshot verification FAILED ($errors errors)"
        return 1
    fi
}

# ── usage ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}xdc-snapshot-extra.sh${NC} — XDPoS Snapshot Extra Data Manager

Issue #257: Cold snapshots missing XDPoS voting snapshots cause nil pointer panics.

Usage:
  xdc-snapshot-extra.sh export <datadir> [output-dir]   Export XDPoS snapshots
  xdc-snapshot-extra.sh import <datadir> <input-dir>    Import XDPoS snapshots
  xdc-snapshot-extra.sh verify <datadir>                Verify snapshot integrity

Examples:
  # Before creating cold snapshot
  xdc-snapshot-extra.sh export /data/apothem/xdcchain /backup/xdc-extra
  tar -czf full-snapshot.tar.gz /data/apothem/xdcchain /backup/xdc-extra

  # After restoring cold snapshot
  xdc-snapshot-extra.sh import /data/apothem/xdcchain /backup/xdc-extra
  xdc-snapshot-extra.sh verify /data/apothem/xdcchain
EOF
}

case "${1:-help}" in
    export) shift; cmd_export "$@" ;;
    import) shift; cmd_import "$@" ;;
    verify) shift; cmd_verify "$@" ;;
    help|--help|-h) usage ;;
    *) error "Unknown command: $1"; usage; exit 1 ;;
esac
