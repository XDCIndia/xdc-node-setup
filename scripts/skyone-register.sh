#!/bin/bash
#===============================================================================
# SkyOne Auto-Registration Script for Multi-Client XDC Nodes
# Auto-registers all running clients with SkyNet monitoring
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
SKYNET_ENDPOINT="${SKYNET_ENDPOINT:-https://skynet.xdcindia.com}"
SKYNET_API_KEY="${SKYNET_API_KEY:-}"
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-60}"

# Client RPC endpoints (defaults)
GP5_RPC="${GP5_RPC:-http://localhost:7070}"
ERIGON_RPC="${ERIGON_RPC:-http://localhost:7072}"
NETHERMIND_RPC="${NETHERMIND_RPC:-http://localhost:7074}"
RETH_RPC="${RETH_RPC:-http://localhost:8588}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[SkyOne]${NC} $1"; }
log_success() { echo -e "${GREEN}[SkyOne]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[SkyOne]${NC} $1"; }
log_error() { echo -e "${RED}[SkyOne]${NC} $1"; }

#===============================================================================
# RPC Helper Functions
#===============================================================================

rpc_call() {
    local endpoint="$1"
    local method="$2"
    local params="${3:-[]}"
    
    curl -s -X POST "$endpoint" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        --connect-timeout 5 \
        --max-time 10 2>/dev/null || echo '{"error":"connection_failed"}'
}

get_block_number() {
    local endpoint="$1"
    local result
    result=$(rpc_call "$endpoint" "eth_blockNumber")
    echo "$result" | grep -oP '"result"\s*:\s*"\K0x[0-9a-fA-F]+' | head -1 || echo "0x0"
}

get_peer_count() {
    local endpoint="$1"
    local result
    result=$(rpc_call "$endpoint" "net_peerCount")
    echo "$result" | grep -oP '"result"\s*:\s*"\K0x[0-9a-fA-F]+' | head -1 || echo "0x0"
}

get_syncing() {
    local endpoint="$1"
    local result
    result=$(rpc_call "$endpoint" "eth_syncing")
    if echo "$result" | grep -q '"result":false'; then
        echo "synced"
    elif echo "$result" | grep -q '"currentBlock"'; then
        echo "syncing"
    else
        echo "unknown"
    fi
}

hex_to_dec() {
    printf "%d" "$1" 2>/dev/null || echo "0"
}

#===============================================================================
# Client Registration
#===============================================================================

register_client() {
    local client_name="$1"
    local rpc_endpoint="$2"
    local node_id="${3:-}"
    
    # Generate node ID if not provided
    if [[ -z "$node_id" ]]; then
        local hostname_part="${HOSTNAME:-$(hostname)}"
        node_id="${client_name}-${hostname_part}"
    fi
    
    log_info "Registering $client_name (node_id: $node_id)..."
    
    # Check if client is responsive
    local block_hex
    block_hex=$(get_block_number "$rpc_endpoint")
    
    if [[ "$block_hex" == "0x0" ]]; then
        log_warn "$client_name not responding at $rpc_endpoint"
        return 1
    fi
    
    local block_number
    block_number=$(hex_to_dec "$block_hex")
    local peer_count_hex
    peer_count_hex=$(get_peer_count "$rpc_endpoint")
    local peer_count
    peer_count=$(hex_to_dec "$peer_count_hex")
    local sync_status
    sync_status=$(get_syncing "$rpc_endpoint")
    
    log_success "$client_name: block=$block_number peers=$peer_count status=$sync_status"
    
    # Store registration info
    local reg_file="/tmp/skyone_${client_name}.json"
    cat > "$reg_file" <<EOF
{
    "nodeId": "$node_id",
    "client": "$client_name",
    "rpcEndpoint": "$rpc_endpoint",
    "blockNumber": $block_number,
    "peerCount": $peer_count,
    "syncStatus": "$sync_status",
    "timestamp": "$(date -Iseconds)",
    "hostname": "${HOSTNAME:-$(hostname)}"
}
EOF
    
    # Send to SkyNet if API key is set
    if [[ -n "$SKYNET_API_KEY" ]]; then
        curl -s -X POST "$SKYNET_ENDPOINT/api/v1/nodes/heartbeat" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $SKYNET_API_KEY" \
            -d @"$reg_file" --connect-timeout 5 --max-time 10 2>/dev/null || true
    fi
    
    return 0
}

#===============================================================================
# Multi-Client Registration
#===============================================================================

register_all_clients() {
    log_info "Starting multi-client registration..."
    
    local registered=0
    local failed=0
    
    # GP5
    if register_client "gp5" "$GP5_RPC" "${GP5_NODE_ID:-}"; then
        ((registered++))
    else
        ((failed++))
    fi
    
    # Erigon
    if register_client "erigon" "$ERIGON_RPC" "${ERIGON_NODE_ID:-}"; then
        ((registered++))
    else
        ((failed++))
    fi
    
    # Nethermind
    if register_client "nethermind" "$NETHERMIND_RPC" "${NETHERMIND_NODE_ID:-}"; then
        ((registered++))
    else
        ((failed++))
    fi
    
    # Reth (experimental)
    if register_client "reth" "$RETH_RPC" "${RETH_NODE_ID:-}"; then
        ((registered++))
    else
        ((failed++))
    fi
    
    log_info "Registration complete: $registered clients registered, $failed failed"
}

#===============================================================================
# Heartbeat Loop
#===============================================================================

heartbeat_loop() {
    log_info "Starting heartbeat loop (interval: ${HEARTBEAT_INTERVAL}s)..."
    
    while true; do
        register_all_clients
        sleep "$HEARTBEAT_INTERVAL"
    done
}

#===============================================================================
# Main
#===============================================================================

case "${1:-register}" in
    register)
        register_all_clients
        ;;
    heartbeat)
        heartbeat_loop
        ;;
    status)
        log_info "Checking client status..."
        for client in "gp5:$GP5_RPC" "erigon:$ERIGON_RPC" "nethermind:$NETHERMIND_RPC" "reth:$RETH_RPC"; do
            name="${client%%:*}"
            rpc="${client#*:}"
            block=$(get_block_number "$rpc")
            peers=$(get_peer_count "$rpc")
            sync=$(get_syncing "$rpc")
            if [[ "$block" != "0x0" ]]; then
                log_success "$name: block=$(hex_to_dec $block) peers=$(hex_to_dec $peers) status=$sync"
            else
                log_warn "$name: not responding"
            fi
        done
        ;;
    *)
        echo "Usage: $0 {register|heartbeat|status}"
        exit 1
        ;;
esac
