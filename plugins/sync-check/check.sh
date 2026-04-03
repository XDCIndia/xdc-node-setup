#!/bin/bash
#===============================================================================
# Plugin: sync-check
# Checks XDC node sync status via eth_syncing RPC.
# Output: JSON with syncing flag, currentBlock, highestBlock, lag.
#===============================================================================

PORT="${XDC_RPC_PORT:-8545}"
TIMEOUT="${XDC_TIMEOUT:-5}"
ENDPOINT="http://127.0.0.1:${PORT}"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

_err() {
    printf '{"plugin":"sync-check","timestamp":"%s","status":"err","metrics":{},"error":"%s"}\n' "$TS" "$1"
    exit 2
}

# Query eth_syncing
sync_result=$(curl -sf --max-time "$TIMEOUT" \
    -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
    "$ENDPOINT" 2>/dev/null) || _err "rpc_unreachable"

# Query eth_blockNumber for current head
block_result=$(curl -sf --max-time "$TIMEOUT" \
    -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":2}' \
    "$ENDPOINT" 2>/dev/null) || _err "block_number_failed"

# Parse syncing: result=false means synced; object means syncing
sync_field=$(echo "$sync_result" | grep -o '"result":[^,}]*' | head -1 | cut -d: -f2-)

current_block_hex=$(echo "$block_result" | grep -o '"result":"0x[^"]*"' | cut -d'"' -f4)
current_block=$(( 16#${current_block_hex#0x} )) 2>/dev/null || current_block=0

if echo "$sync_field" | grep -q "false"; then
    # Fully synced
    status="ok"
    syncing="false"
    highest_block=$current_block
    lag=0
else
    # Actively syncing — extract fields
    syncing="true"
    current_hex=$(echo "$sync_result" | grep -o '"currentBlock":"0x[^"]*"' | cut -d'"' -f4)
    highest_hex=$(echo "$sync_result" | grep -o '"highestBlock":"0x[^"]*"' | cut -d'"' -f4)
    
    current_sync=$(( 16#${current_hex#0x} )) 2>/dev/null || current_sync=0
    highest_block=$(( 16#${highest_hex#0x} )) 2>/dev/null || highest_block=0
    lag=$(( highest_block - current_sync ))
    
    if [[ $lag -gt 100 ]]; then
        status="warn"
    else
        status="ok"
    fi
fi

printf '{"plugin":"sync-check","timestamp":"%s","status":"%s","metrics":{"syncing":%s,"current_block":%d,"highest_block":%d,"lag_blocks":%d},"error":null}\n' \
    "$TS" "$status" "$syncing" "$current_block" "$highest_block" "$lag"
