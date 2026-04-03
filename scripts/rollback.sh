#!/bin/bash
#===============================================================================
# XDC Node Setup - Real Rollback Action (#136)
# Uses debug_setHead to roll back a node to a specific block number.
# Usage: rollback.sh <client> <block_number>
# Saves current block before rollback for recovery.
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-lib.sh"

ROLLBACK_STATE_DIR="${ROLLBACK_STATE_DIR:-/opt/xdc-node/rollback}"
TIMEOUT_S="${TIMEOUT_S:-10}"

declare -A CLIENT_RPC_PORTS=(
    ["geth"]="7070"
    ["erigon"]="7071"
    ["nethermind"]="7072"
    ["reth"]="8588"
)

#-------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") <client> <block_number> [OPTIONS]

Roll back an XDC node to a specific block using debug_setHead.
Saves the current head block before rolling back for recovery.

Arguments:
  client          Client to roll back: geth, erigon, nethermind, reth
  block_number    Target block number (decimal or 0x hex)

Options:
  -r, --recover   Recover from last saved state (roll forward isn't possible
                  with setHead; this shows the saved block for manual restart)
  -s, --status    Show current block and last rollback state for client
  -n, --dry-run   Show what would happen without executing
  -h              Show this help

Examples:
  $(basename "$0") geth 5000000
  $(basename "$0") erigon 0x4C4B40
  $(basename "$0") geth --status
  $(basename "$0") geth --recover

WARNING:
  debug_setHead is irreversible without re-syncing or restoring a snapshot.
  Always ensure you have a snapshot/backup before rolling back.
EOF
}

#-------------------------------------------------------------------------------
get_rpc_port() {
    local client="$1"
    local port="${CLIENT_RPC_PORTS[$client]:-}"
    if [[ -z "$port" ]]; then
        die "Unknown client: ${client}. Known: ${!CLIENT_RPC_PORTS[*]}"
    fi
    echo "$port"
}

#-------------------------------------------------------------------------------
get_current_block() {
    local endpoint="$1"
    local result
    result=$(curl -sf --max-time "$TIMEOUT_S" \
        -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$endpoint" 2>/dev/null) || die "Cannot reach RPC at ${endpoint}"
    
    local hex
    hex=$(echo "$result" | grep -o '"result":"0x[^"]*"' | cut -d'"' -f4)
    [[ -z "$hex" ]] && die "Failed to parse block number from response"
    echo "$hex"
}

#-------------------------------------------------------------------------------
save_rollback_state() {
    local client="$1"
    local current_block_hex="$2"
    local target_block_hex="$3"
    
    mkdir -p "${ROLLBACK_STATE_DIR}"
    local state_file="${ROLLBACK_STATE_DIR}/${client}.json"
    local current_dec
    current_dec=$(( 16#${current_block_hex#0x} ))
    local target_dec
    target_dec=$(( 16#${target_block_hex#0x} ))
    
    cat > "$state_file" <<EOF
{
  "client":             "${client}",
  "timestamp":          "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "pre_rollback_block": {
    "hex": "${current_block_hex}",
    "dec": ${current_dec}
  },
  "target_block": {
    "hex": "${target_block_hex}",
    "dec": ${target_dec}
  }
}
EOF
    log "Rollback state saved: ${state_file}"
}

#-------------------------------------------------------------------------------
show_status() {
    local client="$1"
    local port
    port=$(get_rpc_port "$client")
    local endpoint="http://127.0.0.1:${port}"
    
    info "=== Rollback Status: ${client} ==="
    
    # Current block
    local current_hex
    current_hex=$(get_current_block "$endpoint")
    local current_dec
    current_dec=$(( 16#${current_hex#0x} ))
    info "Current block: ${current_dec} (${current_hex})"
    
    # Last saved state
    local state_file="${ROLLBACK_STATE_DIR}/${client}.json"
    if [[ -f "$state_file" ]]; then
        info "Last rollback state:"
        cat "$state_file"
    else
        info "No previous rollback state found"
    fi
}

#-------------------------------------------------------------------------------
show_recovery() {
    local client="$1"
    local state_file="${ROLLBACK_STATE_DIR}/${client}.json"
    
    if [[ ! -f "$state_file" ]]; then
        die "No rollback state found for ${client} at ${state_file}"
    fi
    
    warn "=== Recovery Information for ${client} ==="
    cat "$state_file"
    printf "\n"
    warn "IMPORTANT: debug_setHead cannot roll forward."
    warn "To recover to pre-rollback block, you must:"
    warn "  1. Stop the ${client} node"
    warn "  2. Restore from a snapshot taken before the rollback"
    warn "  3. OR let the node re-sync from peers"
    warn "Pre-rollback block was: $(grep pre_rollback_block -A2 "$state_file" | grep dec | grep -o '[0-9]*')"
}

#-------------------------------------------------------------------------------
do_rollback() {
    local client="$1"
    local target_block="$2"
    local dry_run="${3:-false}"
    
    local port
    port=$(get_rpc_port "$client")
    local endpoint="http://127.0.0.1:${port}"
    
    # Normalize target to hex
    local target_hex
    if [[ "$target_block" == 0x* ]]; then
        target_hex="$target_block"
    else
        # Decimal to hex
        target_hex=$(printf "0x%x" "$target_block")
    fi
    
    local target_dec
    target_dec=$(( 16#${target_hex#0x} ))
    
    info "=== XDC Node Rollback ==="
    info "Client:       ${client}"
    info "RPC endpoint: ${endpoint}"
    info "Target block: ${target_dec} (${target_hex})"
    
    # Get current block
    info "Fetching current block..."
    local current_hex
    current_hex=$(get_current_block "$endpoint")
    local current_dec
    current_dec=$(( 16#${current_hex#0x} ))
    info "Current block: ${current_dec} (${current_hex})"
    
    # Sanity checks
    if [[ $target_dec -ge $current_dec ]]; then
        die "Target block (${target_dec}) must be less than current block (${current_dec}). debug_setHead only rolls BACK."
    fi
    
    local diff=$(( current_dec - target_dec ))
    warn "This will roll back ${diff} blocks."
    warn "This operation is NOT easily reversible."
    
    if $dry_run; then
        warn "DRY RUN — would execute: debug_setHead(${target_hex})"
        return 0
    fi
    
    # Confirm
    printf "Type 'yes' to confirm rollback: "
    read -r confirm
    [[ "$confirm" == "yes" ]] || { info "Aborted."; exit 0; }
    
    # Save state before rollback
    save_rollback_state "$client" "$current_hex" "$target_hex"
    
    # Execute rollback
    info "Executing debug_setHead(${target_hex})..."
    local result
    result=$(curl -sf --max-time "$TIMEOUT_S" \
        -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"debug_setHead\",\"params\":[\"${target_hex}\"],\"id\":1}" \
        "$endpoint" 2>/dev/null) || die "RPC call failed — is debug API enabled?"
    
    # Check for errors
    if echo "$result" | grep -q '"error"'; then
        local err_msg
        err_msg=$(echo "$result" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        die "RPC error: ${err_msg:-unknown error}. Ensure --rpc.enabledModules includes debug."
    fi
    
    log "Rollback submitted."
    
    # Verify
    sleep 2
    local new_hex
    new_hex=$(get_current_block "$endpoint") || { warn "Could not verify new block"; return; }
    local new_dec
    new_dec=$(( 16#${new_hex#0x} ))
    
    if [[ $new_dec -eq $target_dec ]]; then
        log "Rollback confirmed: node is now at block ${new_dec}"
    else
        warn "Node is at block ${new_dec} — may still be processing (expected ${target_dec})"
    fi
    
    info "State saved to: ${ROLLBACK_STATE_DIR}/${client}.json"
    info "Run '$(basename "$0") ${client} --recover' to see recovery options"
}

#-------------------------------------------------------------------------------
main() {
    if [[ $# -lt 1 ]]; then
        usage
        exit 1
    fi
    
    local client="$1"
    shift
    
    local block_number=""
    local dry_run=false
    local do_status=false
    local do_recover=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)   dry_run=true ;;
            -s|--status)    do_status=true ;;
            -r|--recover)   do_recover=true ;;
            -h|--help)      usage; exit 0 ;;
            -*)             error "Unknown option: $1"; usage; exit 1 ;;
            *)              block_number="$1" ;;
        esac
        shift
    done
    
    # Validate client
    if [[ -z "${CLIENT_RPC_PORTS[$client]:-}" ]]; then
        die "Unknown client: ${client}. Known: ${!CLIENT_RPC_PORTS[*]}"
    fi
    
    if $do_status; then
        show_status "$client"
        exit 0
    fi
    
    if $do_recover; then
        show_recovery "$client"
        exit 0
    fi
    
    if [[ -z "$block_number" ]]; then
        error "Block number required"
        usage
        exit 1
    fi
    
    do_rollback "$client" "$block_number" "$dry_run"
}

main "$@"
