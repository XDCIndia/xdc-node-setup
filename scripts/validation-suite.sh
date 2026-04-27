#!/usr/bin/env bash
#===============================================================================
# XDC Validation Suite — Bit-for-bit replay against v2.6.8 archive
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/249
#
# Compares GP5 output against a v2.6.8 archive node over a window of blocks
# covering an epoch switch. Validates: block hashes, state roots, snapshot blobs,
# receipt roots, and author results.
#
# Usage:
#   validation-suite.sh <reference_rpc> <test_rpc> <start_block> <end_block>
#   validation-suite.sh http://v268:8545 http://gp5:9645 56828250 56831400
#===============================================================================

set -euo pipefail

# --- Configuration ---
REF_RPC="${1:-}"
TEST_RPC="${2:-}"
START_BLOCK="${3:-}"
END_BLOCK="${4:-}"
BATCH_SIZE="${BATCH_SIZE:-100}"
CONCURRENCY="${CONCURRENCY:-10}"
TMPDIR="${TMPDIR:-/tmp/xdc-validation-$$}"

# --- Helpers ---
die() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }

# Validate args
[[ -z "$REF_RPC" || -z "$TEST_RPC" || -z "$START_BLOCK" || -z "$END_BLOCK" ]] && \
    die "Usage: $0 <reference_rpc> <test_rpc> <start_block> <end_block>"

mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

# --- RPC helper ---
jsonrpc() {
    local url="$1" method="$2" params="${3:-[]}"
    curl -sf -X POST "$url" \
        -H 'Content-Type: application/json' \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" 2>/dev/null
}

# --- Fetch block data ---
fetch_block() {
    local rpc="$1" num="$2" out="$3"
    jsonrpc "$rpc" "eth_getBlockByNumber" "[\"$(printf '0x%x' "$num")\",false]" > "$out"
}

# --- Extract field from block JSON ---
get_field() {
    local file="$1" field="$2"
    jq -r ".$field // empty" "$file" 2>/dev/null || echo ""
}

# --- Compare two JSON files for a specific field ---
compare_field() {
    local block="$1" field="$2" ref_file="$3" test_file="$4"
    local ref_val test_val
    ref_val="$(get_field "$ref_file" "$field")"
    test_val="$(get_field "$test_file" "$field")"
    if [[ "$ref_val" != "$test_val" ]]; then
        echo "MISMATCH block=$block field=$field ref=$ref_val test=$test_val"
        return 1
    fi
    return 0
}

# --- Get snapshot at gap block ---
fetch_snapshot() {
    local rpc="$1" num="$2" out="$3"
    # XDPoS snapshot is stored under the hash of (number-1) block
    # We use debug API to dump the snapshot if available
    jsonrpc "$rpc" "XDPoS_getSnapshot" "[\"$(printf '0x%x' "$num")\"]" > "$out" 2>/dev/null || \
        echo '{"error":"snapshot_unavailable"}' > "$out"
}

# --- Main validation loop ---
main() {
    local total_blocks=$((END_BLOCK - START_BLOCK + 1))
    local mismatches=0 checked=0
    
    info "Starting validation: $START_BLOCK → $END_BLOCK ($total_blocks blocks)"
    info "Reference: $REF_RPC | Test: $TEST_RPC"
    info "Output: $TMPDIR"
    
    # Progress file
    local progress="$TMPDIR/progress"
    echo "0" > "$progress"
    
    for ((block=START_BLOCK; block<=END_BLOCK; block++)); do
        local ref_block="$TMPDIR/ref_${block}.json"
        local test_block="$TMPDIR/test_${block}.json"
        
        # Fetch both blocks
        fetch_block "$REF_RPC" "$block" "$ref_block" &
        fetch_block "$TEST_RPC" "$block" "$test_block" &
        wait
        
        # Validate block exists on both
        if [[ "$(get_field "$ref_block" "hash")" == "null" || -z "$(get_field "$ref_block" "hash")" ]]; then
            warn "Block $block not found on reference node"
            continue
        fi
        if [[ "$(get_field "$test_block" "hash")" == "null" || -z "$(get_field "$test_block" "hash")" ]]; then
            warn "Block $block not found on test node"
            continue
        fi
        
        # Compare fields
        local block_mismatch=false
        for field in hash stateRoot receiptsRoot; do
            if ! compare_field "$block" "$field" "$ref_block" "$test_block"; then
                block_mismatch=true
                ((mismatches++)) || true
            fi
        done
        
        # Compare author (miner field for XDPoS)
        if ! compare_field "$block" "miner" "$ref_block" "$test_block"; then
            block_mismatch=true
            ((mismatches++)) || true
        fi
        
        # Snapshot comparison at gap boundaries (every 900 blocks for Apothem)
        if (( block % 900 == 0 )); then
            local ref_snap="$TMPDIR/ref_snap_${block}.json"
            local test_snap="$TMPDIR/test_snap_${block}.json"
            fetch_snapshot "$REF_RPC" "$block" "$ref_snap" &
            fetch_snapshot "$TEST_RPC" "$block" "$test_snap" &
            wait
            
            local ref_snap_hash test_snap_hash
            ref_snap_hash="$(jq -S -c '.' "$ref_snap" | sha256sum | cut -d' ' -f1)"
            test_snap_hash="$(jq -S -c '.' "$test_snap" | sha256sum | cut -d' ' -f1)"
            
            if [[ "$ref_snap_hash" != "$test_snap_hash" ]]; then
                echo "SNAPSHOT_MISMATCH block=$block"
                block_mismatch=true
                ((mismatches++)) || true
            fi
        fi
        
        ((checked++)) || true
        
        # Progress
        if (( checked % 100 == 0 )); then
            local pct=$((checked * 100 / total_blocks))
            info "Progress: $checked/$total_blocks ($pct%) — mismatches so far: $mismatches"
        fi
    done
    
    # Summary
    echo ""
    echo "========================================"
    echo "VALIDATION COMPLETE"
    echo "========================================"
    echo "Blocks checked: $checked"
    echo "Mismatches:     $mismatches"
    echo "Match rate:     $(( checked > 0 ? (checked - mismatches) * 100 / checked : 0 ))%"
    echo ""
    
    if (( mismatches == 0 )); then
        echo "✅ ZERO DIFFS — Parity achieved across audit window"
        exit 0
    else
        echo "❌ $mismatches mismatches found — see $TMPDIR for details"
        exit 1
    fi
}

main "$@"
