#!/usr/bin/env bash
#==============================================================================
# Deploy SkyOne Agents (Issue #574)
# Properly configures RPC_URL with host IP (not host.docker.internal)
#
# Usage: ./deploy-skyone-agents.sh [server-ip] [gp5-port] [erigon-port] [nm-port]
#==============================================================================
set -euo pipefail

HOST_IP="${1:-$(hostname -I | awk '{print $1}')}"
GP5_RPC_PORT="${2:-8545}"
ERIGON_RPC_PORT="${3:-8546}"
NM_RPC_PORT="${4:-8547}"

SKYNET_API="https://net.xdc.network/api"
SKYNET_KEY="${SKYNET_API_KEY:-xdc-netown-key-2026-prod}"
SKYONE_IMAGE="anilchinchawale/xdc-skyone:latest"

echo "🚀 Deploying SkyOne agents on $HOST_IP"
echo ""

# Ensure UFW allows Docker bridge → host traffic
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    if ! ufw status | grep -q "172.17.0.0/16"; then
        echo "Adding UFW rule for Docker bridge..."
        ufw allow from 172.17.0.0/16 to any comment "Docker bridge to host (SkyOne)" >/dev/null
    fi
fi

# Deploy function
deploy_agent() {
    local name="$1"
    local node_id="$2"
    local rpc_port="$3"
    local host_port="$4"
    local client_type="$5"

    echo -n "  $name (port $rpc_port → :$host_port)... "
    
    # Stop existing
    docker stop "$name" 2>/dev/null || true
    docker rm "$name" 2>/dev/null || true
    
    # Verify RPC is reachable
    if ! curl -sf -m 3 -X POST "http://$HOST_IP:$rpc_port" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' >/dev/null 2>&1; then
        echo "⚠️  SKIP (RPC not reachable on port $rpc_port)"
        return 0
    fi
    
    docker run -d --name "$name" \
        --restart unless-stopped \
        -e SKYNET_API_URL="$SKYNET_API" \
        -e SKYNET_API_KEY="$SKYNET_KEY" \
        -e SKYNET_NODE_ID="$node_id" \
        -e RPC_URL="http://${HOST_IP}:${rpc_port}" \
        -e NODE_NAME="$name" \
        -e NETWORK=mainnet \
        -e CLIENT_TYPE="$client_type" \
        -p "$host_port:3000" \
        "$SKYONE_IMAGE" >/dev/null 2>&1
    
    echo "✅"
}

# GP5 uses host network (port 7070 via host network, no mapping needed)
# Erigon and NM use bridge network with port mapping

echo "Deploying agents..."

# Detect node IDs from environment or use auto-registration
GP5_NODE_ID="${GP5_NODE_ID:-}"
ERIGON_NODE_ID="${ERIGON_NODE_ID:-}"
NM_NODE_ID="${NM_NODE_ID:-}"

IP_SUFFIX="${HOST_IP##*.}"

if [[ -n "$ERIGON_NODE_ID" ]]; then
    deploy_agent "skyone-mainnet-erigon" "$ERIGON_NODE_ID" "$ERIGON_RPC_PORT" "7071" "erigon"
fi

if [[ -n "$NM_NODE_ID" ]]; then
    deploy_agent "skyone-mainnet-nm" "$NM_NODE_ID" "$NM_RPC_PORT" "7072" "nethermind"
fi

echo ""
echo "✅ SkyOne agents deployed"
echo "   Key fix: Using host IP ($HOST_IP) instead of host.docker.internal"
echo "   UFW rule ensures Docker bridge can reach host ports"
