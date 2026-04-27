#!/usr/bin/env bash
#===============================================================================
# XDC Snapshot Extra Data Export/Import
# Handles XDPoS voting snapshots stored in a separate Pebble/LevelDB directory.
# These are NOT included in standard chaindata snapshots and cause nil pointer
# panics on restart if missing.
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

# Find XDPoS snapshot DB directory (separate from chaindata)
find_xdpos_dir() {
    local datadir="$1"
    local subdir=""
    subdir=$(find_chaindata_subdir_or_default "$datadir" 2>/dev/null || echo "")
    
    # XDPoS snapshots are stored in a separate Pebble/LevelDB instance
    # Common locations across XDC client versions
    local candidates=(
        "$datadir${subdir:+/$subdir}/XDPoS"
        "$datadir/XDPoS"
        "$datadir/geth/XDPoS"
        "$datadir/xdcchain/XDPoS"
        "$datadir${subdir:+/$subdir}/chaindata/XDPoS"
        "$datadir/xdpos"
        "$datadir/geth/xdpos"
    )
    
    for cand in "${candidates[@]}"; do
        if [[ -d "$cand" ]]; then
            # Verify it looks like a Pebble/LevelDB (has CURRENT or MANIFEST)
            if [[ -f "$cand/CURRENT" ]] || [[ -n $(find "$cand" -maxdepth 1 -name 'MANIFEST-*' -print -quit 2>/dev/null) ]]; then
                echo "$cand"
                return 0
            fi
        fi
    done
    
    return 1
}

# Check if node is running (to warn about DB locks)
check_node_running() {
    local datadir="$1"
    # Check for lock file in chaindata
    local subdir
    subdir=$(find_chaindata_subdir_or_default "$datadir" 2>/dev/null || echo "")
    local chaindata="$datadir${subdir:+/$subdir}/chaindata"
    
    if [[ -f "$chaindata/LOCK" ]]; then
        return 0  # Running
    fi
    
    # Also check XDPoS dir
    local xdpos_dir
    xdpos_dir=$(find_xdpos_dir "$datadir" 2>/dev/null || echo "")
    if [[ -n "$xdpos_dir" ]] && [[ -f "$xdpos_dir/LOCK" ]]; then
        return 0
    fi
    
    return 1  # Not running
}

# Export XDPoS voting snapshots
cmd_export() {
    local datadir="${1:-}"
    local outdir="${2:-}"
    
    [[ -z "$datadir" ]] && die "Usage: xdc-snapshot-extra.sh export <datadir> <output-dir>"
    [[ -z "$outdir" ]] && outdir="$(pwd)/xdc-snapshot-extra-$(date +%Y%m%d-%H%M%S)"
    [[ -d "$datadir" ]] || die "Data directory not found: $datadir"
    
    # Warn if node is running (Pebble holds exclusive lock)
    if check_node_running "$datadir"; then
        warn "Node appears to be running (LOCK file found)"
        warn "Stop the node before export to avoid DB corruption"
        warn "Continuing anyway in 3 seconds..."
        sleep 3
    fi
    
    mkdir -p "$outdir"
    
    info "Exporting XDPoS extra data from $datadir"
    
    local xdpos_dir
    xdpos_dir=$(find_xdpos_dir "$datadir" 2>/dev/null || echo "")
    
    if [[ -n "$xdpos_dir" ]]; then
        info "Found XDPoS DB: $xdpos_dir"
        
        # Copy the entire XDPoS Pebble/LevelDB directory
        cp -a "$xdpos_dir" "$outdir/"
        ok "Copied XDPoS DB directory ($(du -sh "$xdpos_dir" | cut -f1))"
    else
        warn "No XDPoS DB directory found"
        warn "Searched: $datadir/**/XDPoS, $datadir/**/xdpos"
    fi
    
    # Copy checkpoint info if present
    local subdir
    subdir=$(find_chaindata_subdir_or_default "$datadir" 2>/dev/null || echo "")
    local checkpoint_file="$datadir${subdir:+/$subdir}/checkpoint.txt"
    if [[ -f "$checkpoint_file" ]]; then
        cp "$checkpoint_file" "$outdir/"
        ok "Copied checkpoint.txt"
    fi
    
    # Copy state root cache if present
    local cache_src=""
    local cache_candidates=(
        "$datadir/xdc-state-root-cache.csv"
        "$datadir${subdir:+/$subdir}/xdc-state-root-cache.csv"
        "$datadir/geth/xdc-state-root-cache.csv"
        "$datadir/XDC/xdc-state-root-cache.csv"
    )
    for cand in "${cache_candidates[@]}"; do
        if [[ -f "$cand" ]]; then
            cache_src="$cand"
            break
        fi
    done
    
    if [[ -n "$cache_src" ]]; then
        cp "$cache_src" "$outdir/"
        ok "Copied state root cache: $(basename "$cache_src")"
    else
        warn "State root cache not found — may cause state root mismatches on restore"
    fi
    
    # Write metadata
    cat > "$outdir/META.json" <<EOF
{
  "exported_at": "$(date -Iseconds)",
  "datadir": "$datadir",
  "xdpos_dir": "${xdpos_dir:-null}",
  "has_xdpos_db": $( [[ -n "$xdpos_dir" ]] && echo "true" || echo "false" ),
  "note": "XDPoS voting snapshots must be restored alongside chaindata to prevent nil pointer panics"
}
EOF
    
    ok "Export complete: $outdir"
    echo ""
    info "Include this directory when creating cold snapshots:"
    info "  tar -czf full-snapshot.tar.gz chaindir/ xdc-snapshot-extra/"
}

# Import XDPoS voting snapshots
cmd_import() {
    local datadir="${1:-}"
    local indir="${2:-}"
    
    [[ -z "$datadir" || -z "$indir" ]] && die "Usage: xdc-snapshot-extra.sh import <datadir> <input-dir>"
    [[ -d "$datadir" ]] || die "Data directory not found: $datadir"
    [[ -d "$indir" ]] || die "Input directory not found: $indir"
    
    # Warn if node is running
    if check_node_running "$datadir"; then
        die "Node is running. Stop it before importing XDPoS snapshots."
    fi
    
    info "Importing XDPoS extra data to $datadir"
    
    # 1. Restore XDPoS DB directory
    if [[ -d "$indir/XDPoS" ]]; then
        local subdir
        subdir=$(find_chaindata_subdir_or_default "$datadir" 2>/dev/null || echo "")
        local target_dir="$datadir${subdir:+/$subdir}/XDPoS"
        
        # Remove existing XDPoS DB if present
        if [[ -d "$target_dir" ]]; then
            warn "Removing existing XDPoS DB: $target_dir"
            rm -rf "$target_dir"
        fi
        
        cp -a "$indir/XDPoS" "$target_dir"
        ok "Restored XDPoS DB to $target_dir"
    elif [[ -d "$indir/xdpos" ]]; then
        local target_dir="$datadir/xdpos"
        [[ -d "$target_dir" ]] && rm -rf "$target_dir"
        cp -a "$indir/xdpos" "$target_dir"
        ok "Restored xdpos DB to $target_dir"
    else
        warn "No XDPoS DB found in $indir"
    fi
    
    # 2. Restore checkpoint info
    if [[ -f "$indir/checkpoint.txt" ]]; then
        local subdir
        subdir=$(find_chaindata_subdir_or_default "$datadir" 2>/dev/null || echo "")
        cp "$indir/checkpoint.txt" "$datadir${subdir:+/$subdir}/"
        ok "Restored checkpoint.txt"
    fi
    
    # 3. Restore state root cache
    if [[ -f "$indir/xdc-state-root-cache.csv" ]]; then
        cp "$indir/xdc-state-root-cache.csv" "$datadir/"
        ok "Restored state root cache"
    fi
    
    ok "Import complete"
    info "Start node and verify no nil pointer panic in logs"
}

# Verify XDPoS snapshot integrity
cmd_verify() {
    local datadir="${1:-}"
    [[ -z "$datadir" ]] && die "Usage: xdc-snapshot-extra.sh verify <datadir>"
    [[ -d "$datadir" ]] || die "Data directory not found: $datadir"
    
    info "Verifying XDPoS snapshot integrity in $datadir"
    
    local errors=0
    
    # Check for XDPoS DB
    local xdpos_dir
    xdpos_dir=$(find_xdpos_dir "$datadir" 2>/dev/null || echo "")
    
    if [[ -n "$xdpos_dir" ]]; then
        local db_size
        db_size=$(du -sh "$xdpos_dir" | cut -f1)
        ok "Found XDPoS DB: $xdpos_dir ($db_size)"
        
        # Verify it has Pebble/LevelDB structure
        if [[ -f "$xdpos_dir/CURRENT" ]] || [[ -n $(find "$xdpos_dir" -maxdepth 1 -name 'MANIFEST-*' -print -quit 2>/dev/null) ]]; then
            ok "XDPoS DB structure valid"
        else
            warn "XDPoS DB missing CURRENT/MANIFEST — may be corrupted"
            errors=$((errors + 1))
        fi
    else
        error "NO XDPoS DB found!"
        error "Node will likely panic on restart with nil pointer dereference"
        error "Run: xdc-snapshot-extra.sh export <source-datadir> <output-dir>"
        errors=$((errors + 1))
    fi
    
    # Check state root cache
    local cache_found=false
    local subdir
    subdir=$(find_chaindata_subdir_or_default "$datadir" 2>/dev/null || echo "")
    local cache_candidates=(
        "$datadir/xdc-state-root-cache.csv"
        "$datadir${subdir:+/$subdir}/xdc-state-root-cache.csv"
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
  # Before creating cold snapshot (stop node first!)
  docker compose stop xdc-node
  xdc-snapshot-extra.sh export /data/apothem/xdcchain /backup/xdc-extra
  tar -czf full-snapshot.tar.gz /data/apothem/xdcchain /backup/xdc-extra

  # After restoring cold snapshot
  xdc-snapshot-extra.sh import /data/apothem/xdcchain /backup/xdc-extra
  xdc-snapshot-extra.sh verify /data/apothem/xdcchain
  docker compose start xdc-node
EOF
}

case "${1:-help}" in
    export) shift; cmd_export "$@" ;;
    import) shift; cmd_import "$@" ;;
    verify) shift; cmd_verify "$@" ;;
    help|--help|-h) usage ;;
    *) error "Unknown command: $1"; usage; exit 1 ;;
esac
