#!/usr/bin/env bash
#==============================================================================
# Shared RPC Library - Unified RPC call handling for XDC nodes
# Consolidates duplicate rpc_call() functions across scripts
#==============================================================================

# Default RPC URL
: "${XDC_RPC_URL:=http://localhost:8545}"

#==============================================================================
# Core RPC Functions
#==============================================================================

# Make RPC call to XDC node
# Usage: rpc_call URL METHOD [PARAMS]
rpc_call() {
    local url="${1:-$XDC_RPC_URL}"
    local method="$2"
    local params="${3:-[]}"
    
    curl -s -m 15 -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        "$url" 2>/dev/null || echo '{}'
}

# Hex to decimal conversion
hex_to_dec() {
    local hex="${1#0x}"
    printf "%d\n" "0x${hex}" 2>/dev/null || echo "0"
}

# Get block number
get_block_number() {
    local url="${1:-$XDC_RPC_URL}"
    rpc_call "$url" "eth_blockNumber" | jq -r '.result // "0x0"' | hex_to_dec
}

# Get peer count
get_peer_count() {
    local url="${1:-$XDC_RPC_URL}"
    rpc_call "$url" "net_peerCount" | jq -r '.result // "0x0"' | hex_to_dec
}

# Get sync status
get_sync_status() {
    local url="${1:-$XDC_RPC_URL}"
    rpc_call "$url" "eth_syncing"
}

# Check if node is syncing
is_syncing() {
    local url="${1:-$XDC_RPC_URL}"
    local result
    result=$(get_sync_status "$url" | jq -r '.result')
    [[ "$result" != "false" ]]
}

#==============================================================================
# Export functions
#==============================================================================
export -f rpc_call
export -f hex_to_dec
export -f get_block_number
export -f get_peer_count
export -f get_sync_status
export -f is_syncing
