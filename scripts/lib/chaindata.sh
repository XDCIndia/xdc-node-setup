#!/usr/bin/env bash
# ============================================================
# chaindata.sh — Chaindata Directory Auto-Detection Library
# Issue: #164 — XNS Chaindata Directory Standardization
# ============================================================
# Provides portable helpers to resolve the correct chaindata
# subdirectory across legacy (XDC/, xdcchain/) and standard
# (geth/) naming conventions.
#
# Priority: geth/ > XDC/ > xdcchain/ > direct chaindata/ > geth/
# ============================================================

[[ "${_XDC_CHAINDATA_LOADED:-}" == "1" ]] && return 0
_XDC_CHAINDATA_LOADED=1

# Cross-platform directory size in bytes
_dir_size_bytes() {
    local path="$1"
    if command -v stat &>/dev/null && stat -f%z "$path" &>/dev/null 2>&1; then
        # macOS/BSD
        stat -f%z "$path" 2>/dev/null || echo "0"
    else
        # Linux
        du -sb "$path" 2>/dev/null | cut -f1 || echo "0"
    fi
}

# ------------------------------------------------------------
# find_chaindata_dir <base_dir> [min_size_bytes]
# ------------------------------------------------------------
# Detects which subdirectory under base_dir contains chaindata.
# Prints the subdirectory name (e.g. "geth", "XDC", "xdcchain"
# or empty string for direct chaindata/).  Defaults to "geth"
# when nothing exists, creating the directory.
#
# Usage examples:
#   subdir=$(find_chaindata_dir "/mnt/data/node")
#   chaindata="/mnt/data/node/$subdir/chaindata"
# ------------------------------------------------------------
find_chaindata_dir() {
    local base_dir="${1:-}"
    local min_size="${2:-10000000000}"  # 10 GB default

    if [[ -z "$base_dir" ]]; then
        echo "geth"
        return 0
    fi

    # Priority 1: geth/ (standard Geth 1.17+ naming)
    if [[ -d "$base_dir/geth/chaindata" ]]; then
        local geth_size
        geth_size=$(_dir_size_bytes "$base_dir/geth/chaindata")
        if [[ -n "$geth_size" && "$geth_size" -gt "$min_size" ]]; then
            echo "geth"
            return 0
        fi
    fi

    # Priority 2: XDC/ (GP5 legacy naming)
    if [[ -d "$base_dir/XDC/chaindata" ]]; then
        local xdc_size
        xdc_size=$(_dir_size_bytes "$base_dir/XDC/chaindata")
        if [[ -n "$xdc_size" && "$xdc_size" -gt "$min_size" ]]; then
            echo "XDC"
            return 0
        fi
    fi

    # Priority 3: xdcchain/ (XNS legacy naming)
    if [[ -d "$base_dir/xdcchain/chaindata" ]]; then
        local legacy_size
        legacy_size=$(_dir_size_bytes "$base_dir/xdcchain/chaindata")
        if [[ -n "$legacy_size" && "$legacy_size" -gt "$min_size" ]]; then
            echo "xdcchain"
            return 0
        fi
    fi

    # Priority 4: direct chaindata/ under base_dir
    if [[ -d "$base_dir/chaindata" ]]; then
        echo ""
        return 0
    fi

    # Priority 5: default to geth/ for new installations
    mkdir -p "$base_dir/geth"
    echo "geth"
    return 0
}

# ------------------------------------------------------------
# find_chaindata_subdir_or_default <base_dir>
# ------------------------------------------------------------
# Same as find_chaindata_dir but with min_size=0 so that
# existing directories are detected even when very small
# (e.g. after a fresh init).
# ------------------------------------------------------------
find_chaindata_subdir_or_default() {
    find_chaindata_dir "$1" 0
}

# ------------------------------------------------------------
# chaindata_has_data <base_dir> [subdir]
# ------------------------------------------------------------
# Returns 0 if the given base_dir/subdir/chaindata exists and
# has content, otherwise 1.
# ------------------------------------------------------------
chaindata_has_data() {
    local base_dir="$1"
    local subdir="${2:-$(find_chaindata_subdir_or_default "$base_dir")}"
    local chaindata_path="$base_dir/${subdir:+$subdir/}chaindata"
    [[ -d "$chaindata_path" ]] && [[ -n "$(ls -A "$chaindata_path" 2>/dev/null)" ]]
}

# ------------------------------------------------------------
# chaindata_path <base_dir> [subdir]
# ------------------------------------------------------------
# Prints the full path to chaindata directory.
# ------------------------------------------------------------
chaindata_path() {
    local base_dir="$1"
    local subdir="${2:-$(find_chaindata_subdir_or_default "$base_dir")}"
    if [[ -n "$subdir" ]]; then
        echo "$base_dir/$subdir/chaindata"
    else
        echo "$base_dir/chaindata"
    fi
}

# ------------------------------------------------------------
# normalize_snapshot_layout <source_datadir> <staging_dir>
# ------------------------------------------------------------
# Creates a normalized snapshot staging directory with standard
# geth/ layout. Handles: XDC/ → geth/, xdcchain/ → geth/,
# direct chaindata/ → geth/chaindata/.
# Preserves: triedb/ subtree (PBSS), ancient/, keystore/, nodekey,
# jwtsecret, transactions.rlp, blobpool, nodes, LOCK.
# Copies state root cache to staging root.
# Writes .snapshot-layout marker.
# Returns: 0 on success, sets NORMALIZED_STAGING_DIR env var
# ------------------------------------------------------------
normalize_snapshot_layout() {
    local src="$1"
    local staging="${2:-$(mktemp -d)}"

    mkdir -p "$staging/geth"

    # Detect source subdir
    local src_subdir=""
    src_subdir=$(find_chaindata_subdir_or_default "$src")

    # Migrate chaindata
    local src_chaindata="$src/${src_subdir:+$src_subdir/}chaindata"
    if [[ -d "$src_chaindata" ]]; then
        if [[ -d "$staging/geth/chaindata" ]]; then
            rm -rf "$staging/geth/chaindata"
        fi
        cp -a "$src_chaindata" "$staging/geth/chaindata"
    fi

    # Migrate triedb (PBSS path-based state scheme)
    local src_triedb="$src/${src_subdir:+$src_subdir/}triedb"
    if [[ -d "$src_triedb" ]]; then
        cp -a "$src_triedb" "$staging/geth/triedb"
    fi

    # Migrate metadata files
    for item in keystore nodekey jwtsecret transactions.rlp blobpool nodes; do
        local src_item="$src/${src_subdir:+$src_subdir/}$item"
        if [[ -e "$src_item" ]]; then
            cp -a "$src_item" "$staging/geth/"
        fi
    done

    # Migrate LOCK file if present
    local src_lock="$src/${src_subdir:+$src_subdir/}LOCK"
    if [[ -f "$src_lock" ]]; then
        cp -a "$src_lock" "$staging/geth/" 2>/dev/null || true
    fi

    # Migrate state root cache (from any location to staging root)
    for cand in "$src/xdc-state-root-cache.csv" "$src/${src_subdir:+$src_subdir/}xdc-state-root-cache.csv"; do
        if [[ -f "$cand" ]]; then
            cp -a "$cand" "$staging/"
            break
        fi
    done

    # Write layout marker
    echo "normalized:geth:$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$staging/.snapshot-layout"

    NORMALIZED_STAGING_DIR="$staging"
    echo "$staging"
    return 0
}
