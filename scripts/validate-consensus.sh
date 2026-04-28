#!/usr/bin/env bash
# XDC Consensus Validation Harness
# Compares state roots between GP5 and v2.6.8 at critical blocks

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/validation.log"

# Configuration
APOTHEM_V2_SWITCH=56828700
MAINNET_V2_SWITCH=80370000

# RPC endpoints (override with env vars)
GP5_RPC="${GP5_RPC:-http://localhost:9547}"
V26_RPC="${V26_RPC:-http://localhost:8545}"

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Get block hash by number
get_block_hash() {
    local rpc="$1"
    local block_num="$2"
    curl -sf "$rpc" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$(printf '0x%x' "$block_num")\",false],\"id\":1}" \
        2>/dev/null | jq -r '.result.hash // empty'
}

# Get state root by block number
get_state_root() {
    local rpc="$1"
    local block_num="$2"
    curl -sf "$rpc" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$(printf '0x%x' "$block_num")\",false],\"id\":1}" \
        2>/dev/null | jq -r '.result.stateRoot // empty'
}

# Get validator set at block
get_validators() {
    local rpc="$1"
    local block_num="$2"
    curl -sf "$rpc" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"xdc_getValidatorStatus\",\"params\":[\"$(printf '0x%x' "$block_num")\"],\"id\":1}" \
        2>/dev/null | jq -r '.result // empty'
}

# Compare state roots at a specific block
compare_block() {
    local block_num="$1"
    local desc="$2"
    
    log "=== Block $block_num ($desc) ==="
    
    local gp5_root v26_root
    gp5_root=$(get_state_root "$GP5_RPC" "$block_num")
    v26_root=$(get_state_root "$V26_RPC" "$block_num")
    
    if [[ -z "$gp5_root" || -z "$v26_root" ]]; then
        log "ERROR: Could not fetch state root (GP5: ${gp5_root:-EMPTY}, v2.6.8: ${v26_root:-EMPTY})"
        return 1
    fi
    
    if [[ "$gp5_root" == "$v26_root" ]]; then
        log "✅ MATCH: $gp5_root"
        return 0
    else
        log "❌ DIVERGENCE:"
        log "   GP5:     $gp5_root"
        log "   v2.6.8:  $v26_root"
        return 1
    fi
}

# Run validation at critical blocks
run_validation() {
    log "Starting XDC Consensus Validation"
    log "GP5 RPC: $GP5_RPC"
    log "v2.6.8 RPC: $V26_RPC"
    log ""
    
    local failed=0
    
    # Pre-V2 blocks
    compare_block $((APOTHEM_V2_SWITCH - 1)) "Apothem pre-V2" || ((failed++))
    compare_block $((APOTHEM_V2_SWITCH)) "Apothem V2 switch" || ((failed++))
    compare_block $((APOTHEM_V2_SWITCH + 1)) "Apothem post-V2" || ((failed++))
    
    # Epoch boundaries
    local epoch_size=900
    local epoch_block=$(( (APOTHEM_V2_SWITCH / epoch_size) * epoch_size ))
    compare_block "$epoch_block" "Apothem epoch boundary" || ((failed++))
    
    log ""
    log "=== Results ==="
    if [[ $failed -eq 0 ]]; then
        log "✅ All blocks validated — state roots match"
        return 0
    else
        log "❌ $failed block(s) diverged — investigation needed"
        return 1
    fi
}

# Main
case "${1:-run}" in
    run)
        run_validation
        ;;
    block)
        compare_block "$2" "manual check"
        ;;
    *)
        echo "Usage: $0 [run|block <number>]"
        exit 1
        ;;
esac
