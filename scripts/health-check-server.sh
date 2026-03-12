#!/bin/bash
# XDC Node Health Check Server
# Provides Kubernetes-compatible health check endpoints
# Usage: ./health-check-server.sh [port]
# Default port: 8080

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || true

# Configuration
HEALTH_PORT="${1:-8080}"
RPC_URL="${XDC_RPC_URL:-http://127.0.0.1:8545}"
HEALTH_LOG="${HEALTH_LOG:-/var/log/xdc-health.log}"

# State tracking
LAST_BLOCK=0
LAST_BLOCK_TIME=0
SYNC_CHECK_INTERVAL=30

echo "Starting XDC Health Check Server on port ${HEALTH_PORT}"
echo "RPC Endpoint: ${RPC_URL}"

# =============================================================================
# Health Check Functions
# =============================================================================

# Liveness check - is the node process running?
check_liveness() {
    # Check if we can get a response from RPC
    local response
    if response=$(curl -s -m 2 -X POST "${RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' 2>/dev/null); then
        if echo "$response" | grep -q "result"; then
            return 0
        fi
    fi
    return 1
}

# Readiness check - is the node ready to accept traffic?
check_readiness() {
    local block_hex sync_status peers
    
    # Get current block number
    block_hex=$(curl -s -m 5 -X POST "${RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('result','0x0'))" 2>/dev/null || echo "0x0")
    
    local block=$((16#${block_hex#0x}))
    
    # Check if we have peers
    peers=$(curl -s -m 5 -X POST "${RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('result','0x0'))" 2>/dev/null || echo "0x0")
    
    local peer_count=$((16#${peers#0x}))
    
    # Check syncing status
    sync_status=$(curl -s -m 5 -X POST "${RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if d.get('result') not in [False, 'false'] else 'false')" 2>/dev/null || echo "true")
    
    # Node is ready if:
    # - Has at least 1 peer
    # - Is not syncing (or has completed initial sync)
    # - Has a valid block number
    if [[ "$peer_count" -ge 1 ]] && [[ "$sync_status" == "false" ]] && [[ "$block" -gt 0 ]]; then
        echo "{\"ready\":true,\"block\":$block,\"peers\":$peer_count}"
        return 0
    elif [[ "$block" -gt 0 ]] && [[ "$sync_status" == "true" ]]; then
        # Still syncing but making progress
        echo "{\"ready\":false,\"block\":$block,\"peers\":$peer_count,\"syncing\":true,\"reason\":\"initial_sync\"}"
        return 1
    else
        echo "{\"ready\":false,\"block\":$block,\"peers\":$peer_count,\"reason\":\"not_ready\"}"
        return 1
    fi
}

# Sync status check - detailed sync information
check_sync() {
    local block_hex head_hex peers chain_id
    
    # Current block
    block_hex=$(curl -s -m 5 -X POST "${RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('result','0x0'))" 2>/dev/null || echo "0x0")
    
    local block=$((16#${block_hex#0x}))
    
    # Sync status
    local sync_data
    sync_data=$(curl -s -m 5 -X POST "${RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' 2>/dev/null | \
        python3 -c "
import sys,json
d=json.load(sys.stdin).get('result')
if d in [False, 'false']:
    print('{}')
else:
    print(json.dumps(d))
" 2>/dev/null || echo "{}")
    
    # Peer count
    peers=$(curl -s -m 5 -X POST "${RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('result','0x0'))" 2>/dev/null || echo "0x0")
    
    local peer_count=$((16#${peers#0x}))
    
    # Chain ID
    chain_id=$(curl -s -m 5 -X POST "${RPC_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin).get('result','0x0'); print(int(d,16))" 2>/dev/null || echo "0")
    
    # Calculate sync percentage if syncing
    local sync_pct="100"
    local is_syncing="false"
    if [[ "$sync_data" != "{}" ]] && [[ -n "$sync_data" ]]; then
        is_syncing="true"
        local current_block highest_block
        current_block=$(echo "$sync_data" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('currentBlock','0x0'))" 2>/dev/null || echo "0x0")
        highest_block=$(echo "$sync_data" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('highestBlock','0x0'))" 2>/dev/null || echo "0x0")
        
        local current=$((16#${current_block#0x}))
        local highest=$((16#${highest_block#0x}))
        
        if [[ "$highest" -gt 0 ]]; then
            sync_pct=$(python3 -c "print(f'{(current / highest) * 100:.2f}')")
        fi
    fi
    
    # Timestamp
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    cat << EOF
{
  "currentBlock": $block,
  "highestBlock": ${highest:-$block},
  "syncProgress": "$sync_pct",
  "syncing": $is_syncing,
  "peers": $peer_count,
  "chainId": $chain_id,
  "timestamp": "$timestamp"
}
EOF
}

# =============================================================================
# HTTP Server
# =============================================================================

handle_request() {
    local method path
    read -r method path _ <<< "$(head -1)"
    
    # Read headers (consume them)
    while IFS= read -r line; do
        [[ "$line" == $'\r' ]] && break
    done
    
    case "$path" in
        "/health/live")
            if check_liveness; then
                echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n{\"status\":\"alive\"}"
            else
                echo -e "HTTP/1.1 503 Service Unavailable\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n{\"status\":\"not_responding\"}"
            fi
            ;;
        "/health/ready")
            local result
            if result=$(check_readiness); then
                echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n$result"
            else
                echo -e "HTTP/1.1 503 Service Unavailable\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n$result"
            fi
            ;;
        "/health/sync")
            local result
            result=$(check_sync)
            echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n$result"
            ;;
        "/health"|"/")
            echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n{\"endpoints\":[\"/health/live\",\"/health/ready\",\"/health/sync\"]}"
            ;;
        *)
            echo -e "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n{\"error\":\"not_found\"}"
            ;;
    esac
}

# Log startup
{
    echo "=========================================="
    echo "XDC Health Check Server"
    echo "Started: $(date)"
    echo "Port: ${HEALTH_PORT}"
    echo "RPC: ${RPC_URL}"
    echo "=========================================="
} >> "${HEALTH_LOG}" 2>&1

# Main server loop using netcat
while true; do
    handle_request | nc -l -p "${HEALTH_PORT}" -q 1 2>&1 || true
done
