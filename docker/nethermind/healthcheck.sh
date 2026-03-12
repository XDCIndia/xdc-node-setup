#!/bin/bash
#===============================================================================
# Nethermind Health Check Script
# Performs comprehensive health checks for Nethermind XDC client
#===============================================================================

set -e

RPC_PORT="${RPC_PORT:-8545}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-5}"

# Check if process is running
if ! pgrep -f "nethermind" > /dev/null 2>&1; then
    echo "ERROR: Nethermind process not running"
    exit 1
fi

# Check RPC endpoint with timeout
health_check() {
    local response
    response=$(curl -sf -m "$HEALTH_CHECK_TIMEOUT" "http://localhost:${RPC_PORT}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' 2>/dev/null) || {
        echo "ERROR: RPC endpoint not responding"
        exit 1
    }
    
    # Parse syncing status
    local syncing
    syncing=$(echo "$response" | jq -r '.result // false')
    
    # Check peer count as additional health indicator
    local peer_response
    peer_response=$(curl -sf -m "$HEALTH_CHECK_TIMEOUT" "http://localhost:${RPC_PORT}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null) || {
        echo "WARN: Peer count check failed"
        peer_response='{"result":"0x0"}'
    }
    
    local peer_count
    peer_count=$(echo "$peer_response" | jq -r '.result // "0x0"')
    peer_count_dec=$((peer_count))
    
    # Health criteria:
    # - Either not syncing (synced) OR
    # - Has at least 1 peer (making progress)
    if [[ "$syncing" == "false" ]] || [[ $peer_count_dec -gt 0 ]]; then
        echo "HEALTHY: syncing=$syncing, peers=$peer_count_dec"
        exit 0
    else
        echo "UNHEALTHY: syncing=$syncing, peers=$peer_count_dec"
        exit 1
    fi
}

health_check
