#!/bin/sh
#==============================================================================
# Container Health Check Script (Issue #343, #490)
# Used by Docker HEALTHCHECK to verify node is operational
#==============================================================================

RPC_URL="${XDC_RPC_URL:-http://127.0.0.1:8545}"
TIMEOUT=5

# Check 1: RPC responds
response=$(curl -sf -m $TIMEOUT -X POST "$RPC_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null)

if [ -z "$response" ]; then
    echo "UNHEALTHY: RPC not responding at $RPC_URL"
    exit 1
fi

# Check 2: Block number is valid
block_hex=$(echo "$response" | grep -o '"result":"0x[^"]*"' | cut -d'"' -f4)
if [ -z "$block_hex" ]; then
    echo "UNHEALTHY: Invalid block number response"
    exit 1
fi

block_num=$(printf "%d" "$block_hex" 2>/dev/null || echo "0")

# Check 3: Peer count
peer_response=$(curl -sf -m $TIMEOUT -X POST "$RPC_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null)

peer_hex=$(echo "$peer_response" | grep -o '"result":"0x[^"]*"' | cut -d'"' -f4)
peer_count=$(printf "%d" "$peer_hex" 2>/dev/null || echo "0")

echo "HEALTHY: block=$block_num peers=$peer_count"
exit 0
