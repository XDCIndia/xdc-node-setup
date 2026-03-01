#!/bin/bash
# Multi-client status checker for XDC nodes

set -euo pipefail

# Fallback logging functions
info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
error() { echo "[ERROR] $*" >&2; }

# Client RPC ports (default)
GETH_PORT="${GETH_PORT:-8545}"
ERIGON_PORT="${ERIGON_PORT:-8547}"
NETHERMIND_PORT="${NETHERMIND_PORT:-8558}"
RETH_PORT="${RETH_PORT:-8588}"

check_client() {
    local client_name=$1
    local port=$2
    local rpc_url="http://localhost:$port"
    
    info "Checking $client_name on port $port..."
    
    if ! nc -z localhost "$port" 2>/dev/null; then
        warn "$client_name not running (port $port closed)"
        return 1
    fi
    
    local version=$(curl -s -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
        | jq -r '.result // "Unknown"')
    
    local block_hex=$(curl -s -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        | jq -r '.result // "0x0"')
    local block_num=$(printf "%d" "$block_hex" 2>/dev/null || echo 0)
    
    local peer_hex=$(curl -s -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
        | jq -r '.result // "0x0"')
    local peer_count=$(printf "%d" "$peer_hex" 2>/dev/null || echo 0)
    
    local syncing=$(curl -s -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
        | jq -r '.result')
    
    local sync_status="Synced ✓"
    [[ "$syncing" != "false" ]] && sync_status="Syncing..."
    
    echo "  Version: $version"
    echo "  Block: $block_num"
    echo "  Peers: $peer_count"
    echo "  Status: $sync_status"
    echo ""
}

compare_clients() {
    info "==================================="
    info "Multi-Client Status Comparison"
    info "==================================="
    echo ""
    
    declare -A blocks
    declare -A statuses
    
    for client_info in "Geth:$GETH_PORT" "Erigon:$ERIGON_PORT" "Nethermind:$NETHERMIND_PORT" "Reth:$RETH_PORT"; do
        IFS=':' read -r name port <<< "$client_info"
        
        if nc -z localhost "$port" 2>/dev/null; then
            block_hex=$(curl -s -X POST "http://localhost:$port" \
                -H "Content-Type: application/json" \
                -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
                | jq -r '.result // "0x0"')
            blocks[$name]=$(printf "%d" "$block_hex" 2>/dev/null || echo 0)
            statuses[$name]="✓"
        else
            blocks[$name]=0
            statuses[$name]="✗"
        fi
    done
    
    highest=0
    for block in "${blocks[@]}"; do
        ((block > highest)) && highest=$block
    done
    
    echo "Client Status Overview:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-15s %-15s %-10s %-10s\n" "Client" "Block Height" "Status" "Behind"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    for name in Geth Erigon Nethermind Reth; do
        block=${blocks[$name]:-0}
        status=${statuses[$name]:-✗}
        behind=$((highest - block))
        
        if [[ $block -eq 0 ]]; then
            printf "%-15s %-15s %-10s %-10s\n" "$name" "N/A" "$status" "N/A"
        else
            printf "%-15s %-15d %-10s %-10d\n" "$name" "$block" "$status" "$behind"
        fi
    done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main() {
    check_client "Geth" "$GETH_PORT" || true
    check_client "Erigon" "$ERIGON_PORT" || true
    check_client "Nethermind" "$NETHERMIND_PORT" || true
    check_client "Reth" "$RETH_PORT" || true
    compare_clients
}

main "$@"
