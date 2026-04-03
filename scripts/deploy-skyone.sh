#!/usr/bin/env bash
# ============================================================
# deploy-skyone.sh — Auto-deploy SkyOne agent for a node
# Issue: #142
# Usage: ./deploy-skyone.sh <node_name> <rpc_port> <client_type> <network>
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/naming.sh" 2>/dev/null || true

NODE_NAME="${1:?Usage: deploy-skyone.sh <node_name> <rpc_port> <client_type> <network>}"
RPC_PORT="${2:?RPC port required}"
CLIENT_TYPE="${3:?Client type required (xdc|geth|erigon|nethermind|reth)}"
NETWORK="${4:-mainnet}"

HOST_IP="${HOST_IP:-$(hostname -I | awk '{print $1}')}"
SKYNET_API="${SKYNET_API_URL:-https://skynet.xdcindia.com/api}"
SKYONE_IMAGE="${SKYONE_IMAGE:-anilchinchawale/xdc-agent:latest}"
SKYONE_NAME="skyone-${NODE_NAME}"

echo "🛰️  Deploying SkyOne: ${SKYONE_NAME}"
echo "   RPC: http://${HOST_IP}:${RPC_PORT}"
echo "   Client: ${CLIENT_TYPE}, Network: ${NETWORK}"

# Stop existing
docker stop "$SKYONE_NAME" 2>/dev/null || true
docker rm "$SKYONE_NAME" 2>/dev/null || true

# Register with SkyNet
echo "   Registering with SkyNet..."
REG_RESULT=$(curl -sf -X POST "${SKYNET_API}/v1/nodes/register" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"${NODE_NAME}\",
        \"host\": \"${HOST_IP}\",
        \"ip\": \"${HOST_IP}\",
        \"client\": \"${CLIENT_TYPE}\",
        \"network\": \"${NETWORK}\",
        \"role\": \"fullnode\"
    }" 2>/dev/null || echo '{"success":false}')

NODE_ID=$(echo "$REG_RESULT" | jq -r '.data.nodeId // empty' 2>/dev/null)
API_KEY=$(echo "$REG_RESULT" | jq -r '.data.apiKey // empty' 2>/dev/null)

if [[ -z "$NODE_ID" || -z "$API_KEY" ]]; then
    # Try loading saved credentials
    CREDS_DIR="$(dirname "$SCRIPT_DIR")/data/.skynet"
    if [[ -f "${CREDS_DIR}/${NODE_NAME}.env" ]]; then
        source "${CREDS_DIR}/${NODE_NAME}.env"
        NODE_ID="${SKYNET_NODE_ID:-}"
        API_KEY="${SKYNET_API_KEY:-}"
        echo "   ✅ Loaded saved credentials for ${NODE_NAME}"
    else
        echo "   ⚠️  Registration failed and no saved credentials found."
        NODE_ID="${SKYNET_NODE_ID:-}"
        API_KEY="${SKYNET_API_KEY:-}"
    fi
fi

# Save credentials
CREDS_DIR="$(dirname "$SCRIPT_DIR")/data/.skynet"
mkdir -p "$CREDS_DIR"
if [[ -n "$NODE_ID" && -n "$API_KEY" ]]; then
    cat > "${CREDS_DIR}/${NODE_NAME}.env" << EOF
SKYNET_NODE_ID=${NODE_ID}
SKYNET_API_KEY=${API_KEY}
NODE_NAME=${NODE_NAME}
EOF
    chmod 600 "${CREDS_DIR}/${NODE_NAME}.env"
    echo "   ✅ Credentials saved to ${CREDS_DIR}/${NODE_NAME}.env"
fi

# Deploy SkyOne agent
docker run -d \
    --name "$SKYONE_NAME" \
    --restart unless-stopped \
    --network host \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    -e NODE_NAME="$NODE_NAME" \
    -e RPC_URL="http://localhost:${RPC_PORT}" \
    -e CLIENT_TYPE="$CLIENT_TYPE" \
    -e NETWORK="$NETWORK" \
    -e SKYNET_API_URL="$SKYNET_API" \
    ${NODE_ID:+-e SKYNET_NODE_ID="$NODE_ID"} \
    ${API_KEY:+-e SKYNET_API_KEY="$API_KEY"} \
    -e XDC_CONTAINER_NAME="$NODE_NAME" \
    "$SKYONE_IMAGE" >/dev/null

echo "   ✅ SkyOne agent deployed: ${SKYONE_NAME}"
