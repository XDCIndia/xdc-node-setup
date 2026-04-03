#!/bin/bash
#===============================================================================
# Plugin: peer-check
# Checks XDC node peer count via net_peerCount RPC.
# Output: JSON with peer_count and health status.
#===============================================================================

PORT="${XDC_RPC_PORT:-8545}"
TIMEOUT="${XDC_TIMEOUT:-5}"
MIN_PEERS="${XDC_MIN_PEERS:-3}"
ENDPOINT="http://127.0.0.1:${PORT}"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

_err() {
    printf '{"plugin":"peer-check","timestamp":"%s","status":"err","metrics":{},"error":"%s"}\n' "$TS" "$1"
    exit 2
}

# Query net_peerCount
result=$(curl -sf --max-time "$TIMEOUT" \
    -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
    "$ENDPOINT" 2>/dev/null) || _err "rpc_unreachable"

peer_hex=$(echo "$result" | grep -o '"result":"0x[^"]*"' | cut -d'"' -f4)
[[ -z "$peer_hex" ]] && _err "no_peer_count_in_response"

peer_count=$(( 16#${peer_hex#0x} )) 2>/dev/null || _err "parse_error"

# Determine health
if [[ $peer_count -eq 0 ]]; then
    status="err"
elif [[ $peer_count -lt $MIN_PEERS ]]; then
    status="warn"
else
    status="ok"
fi

printf '{"plugin":"peer-check","timestamp":"%s","status":"%s","metrics":{"peer_count":%d,"min_peers":%d},"error":null}\n' \
    "$TS" "$status" "$peer_count" "$MIN_PEERS"
