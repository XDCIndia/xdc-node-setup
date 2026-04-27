#!/usr/bin/env bash
#===============================================================================
# XDC Snapshot Version Manager
# Adds version metadata to snapshots and handles auto-rebuild on GP5 upgrade.
#
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/252
#
# Usage:
#   snapshot-version.sh tag <datadir> <version>     Tag snapshot with version
#   snapshot-version.sh check <datadir> [version]       Check version compatibility
#   snapshot-version.sh rebuild <datadir>              Trigger snapshot rebuild
#===============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source chaindata lib
source "${SCRIPT_DIR}/lib/chaindata.sh" 2>/dev/null || true

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
die()   { error "$*"; exit 1; }

# Find snapshot metadata directory
find_snapshot_meta_dir() {
    local datadir="$1"
    local subdir=""
    subdir=$(find_chaindata_subdir_or_default "$datadir" 2>/dev/null || echo "")
    
    # Snapshots stored in chaindata or separate XDPoS dir
    local candidates=(
        "$datadir${subdir:+/$subdir}/chaindata"
        "$datadir${subdir:+/$subdir}/XDPoS"
        "$datadir/chaindata"
        "$datadir/XDPoS"
    )
    
    for cand in "${candidates[@]}"; do
        if [[ -d "$cand" ]] && [[ -f "$cand/CURRENT" ]]; then
            echo "$cand"
            return 0
        fi
    done
    
    return 1
}

# Write version metadata to a marker file
cmd_tag() {
    local datadir="${1:-}"
    local version="${2:-}"
    
    [[ -z "$datadir" || -z "$version" ]] && die "Usage: snapshot-version.sh tag <datadir> <version>"
    [[ -d "$datadir" ]] || die "Data directory not found: $datadir"
    
    # Write version marker
    local marker="$datadir/.snapshot-version"
    echo "$version" > "$marker"
    
    # Also write to chaindata metadata for portability
    local meta_dir
    meta_dir=$(find_snapshot_meta_dir "$datadir" 2>/dev/null || echo "")
    if [[ -n "$meta_dir" ]]; then
        local meta_file="$meta_dir/snapshot-version.txt"
        echo "$version" > "$meta_file"
        ok "Tagged snapshot with version $version (marker + chaindata meta)"
    else
        ok "Tagged snapshot with version $version (marker only)"
    fi
    
    # Write compatibility info
    cat > "$datadir/.snapshot-compat.json" <<EOF
{
  "snapshot_version": "$version",
  "tagged_at": "$(date -Iseconds)",
  "compatible_with": ["$version"],
  "note": "Snapshots are compatible only within the same GP5 version code (e.g., v95 with v95)"
}
EOF
}

# Check version compatibility
cmd_check() {
    local datadir="${1:-}"
    local current_version="${2:-}"
    
    [[ -z "$datadir" ]] && die "Usage: snapshot-version.sh check <datadir> [current_version]"
    [[ -d "$datadir" ]] || die "Data directory not found: $datadir"
    
    # Read snapshot version
    local snapshot_version="unknown"
    local marker="$datadir/.snapshot-version"
    local meta_dir
    meta_dir=$(find_snapshot_meta_dir "$datadir" 2>/dev/null || echo "")
    
    if [[ -f "$marker" ]]; then
        snapshot_version="$(cat "$marker" | tr -d '[:space:]')"
    elif [[ -n "$meta_dir" ]] && [[ -f "$meta_dir/snapshot-version.txt" ]]; then
        snapshot_version="$(cat "$meta_dir/snapshot-version.txt" | tr -d '[:space:]')"
    fi
    
    info "Snapshot version: $snapshot_version"
    
    if [[ -z "$current_version" ]]; then
        # Just report, don't compare
        if [[ "$snapshot_version" == "unknown" ]]; then
            warn "No version metadata found — snapshot may be from an older GP5 version"
            warn "Consider running: snapshot-version.sh tag $datadir <version>"
            return 1
        fi
        ok "Snapshot version: $snapshot_version"
        return 0
    fi
    
    # Compare versions
    info "Current version: $current_version"
    
    if [[ "$snapshot_version" == "$current_version" ]]; then
        ok "Versions match — snapshot is compatible"
        return 0
    fi
    
    # Extract major.minor for compatibility check
    local snap_major="${snapshot_version%%.*}"
    local curr_major="${current_version%%.*}"
    
    if [[ "$snap_major" == "$curr_major" ]]; then
        warn "Minor version mismatch: snapshot=$snapshot_version, current=$current_version"
        warn "May be compatible but monitor for issues"
        return 0  # Soft warning, not fatal
    else
        error "MAJOR version mismatch: snapshot=$snapshot_version, current=$current_version"
        error "Snapshot is likely INCOMPATIBLE"
        error "Run: snapshot-version.sh rebuild $datadir"
        return 1
    fi
}

# Trigger snapshot rebuild
cmd_rebuild() {
    local datadir="${1:-}"
    local force=false
    
    # Parse flags
    while [[ "${2:-}" == --* ]]; do
        case "$2" in
            --yes|-y) force=true; shift ;;
            *) die "Unknown flag: $2" ;;
        esac
    done
    
    [[ -z "$datadir" ]] && die "Usage: snapshot-version.sh rebuild <datadir> [--yes]"
    [[ -d "$datadir" ]] || die "Data directory not found: $datadir"
    
    # Check if node is running (LOCK file)
    local subdir
    subdir=$(find_chaindata_subdir_or_default "$datadir" 2>/dev/null || echo "")
    local chaindata="$datadir${subdir:+/$subdir}/chaindata"
    if [[ -f "$chaindata/LOCK" ]]; then
        error "Node appears to be running (LOCK file found: $chaindata/LOCK)"
        die "Stop the node before rebuilding snapshots"
    fi
    
    warn "This will REMOVE existing snapshot data and trigger a rebuild"
    
    if [[ "$force" != "true" ]]; then
        read -p "Continue? [y/N] " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || die "Aborted"
    fi
    
    # Find and remove snapshot directories
    local subdir
    subdir=$(find_chaindata_subdir_or_default "$datadir" 2>/dev/null || echo "")
    
    local removed=false
    local snap_dirs=(
        "$datadir${subdir:+/$subdir}/XDPoS"
        "$datadir/XDPoS"
        "$datadir/geth/XDPoS"
        "$datadir${subdir:+/$subdir}/chaindata/XDPoS"
    )
    
    for d in "${snap_dirs[@]}"; do
        if [[ -d "$d" ]]; then
            info "Removing snapshot DB: $d"
            rm -rf "$d"
            removed=true
        fi
    done
    
    # Also remove version markers so new snapshot gets fresh tag
    rm -f "$datadir/.snapshot-version"
    rm -f "$datadir/.snapshot-compat.json"
    
    if [[ "$removed" == "true" ]]; then
        ok "Snapshot data removed. Start node to trigger automatic rebuild."
    else
        warn "No snapshot directories found to remove"
        warn "Snapshot may be embedded in chaindata — check logs on startup"
    fi
    
    info "On first startup after rebuild, expect slower performance while snapshot is reconstructed"
}

# ── usage ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}snapshot-version.sh${NC} — XDC Snapshot Version Manager

Issue #252: Snapshot version metadata and auto-rebuild on GP5 upgrade.

Usage:
  snapshot-version.sh tag <datadir> <version>      Tag snapshot with version
  snapshot-version.sh check <datadir> [version]     Check compatibility
  snapshot-version.sh rebuild <datadir>             Remove and rebuild snapshots

Examples:
  # After creating a snapshot with GP5 v95
  snapshot-version.sh tag /data/apothem/xdcchain v95

  # Before starting node with new image
  snapshot-version.sh check /data/apothem/xdcchain v96

  # Force rebuild after version mismatch
  snapshot-version.sh rebuild /data/apothem/xdcchain --yes

Integration with docker-compose (non-interactive):
  Add to pre-start hook:
    snapshot-version.sh check /data/xdcchain "\${GP5_VERSION}" || \
      snapshot-version.sh rebuild /data/xdcchain --yes
EOF
}

case "${1:-help}" in
    tag) shift; cmd_tag "$@" ;;
    check) shift; cmd_check "$@" ;;
    rebuild) shift; cmd_rebuild "$@" ;;
    help|--help|-h) usage ;;
    *) error "Unknown command: $1"; usage; exit 1 ;;
esac
