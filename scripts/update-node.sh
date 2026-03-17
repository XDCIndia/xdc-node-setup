#!/usr/bin/env bash
#==============================================================================
# Secure Node Update Manager (Issue #104)
# Safely updates XDC node software with rollback support
#==============================================================================
set -euo pipefail

source "$(dirname "$0")/lib/common.sh" 2>/dev/null || true

CLIENT="${1:-gp5}"
NETWORK="${2:-mainnet}"
CONTAINER="xdc-${NETWORK}-${CLIENT}"
BACKUP_TAG="backup-$(date +%Y%m%d-%H%M%S)"

echo "🔄 XDC Node Update Manager"
echo "Client: $CLIENT | Network: $NETWORK"
echo ""

# Step 1: Pre-update health check
echo "📋 Pre-update health check..."
RPC_PORT=8545
case "$CLIENT" in
    erigon) RPC_PORT=8546 ;;
    nm|nethermind) RPC_PORT=8547 ;;
    reth) RPC_PORT=8548 ;;
esac

BLOCK_BEFORE=$(curl -sf -m 5 -X POST "http://localhost:$RPC_PORT" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | \
    grep -o '"result":"0x[^"]*"' | cut -d'"' -f4 || echo "0x0")
BLOCK_BEFORE_DEC=$(printf "%d" "$BLOCK_BEFORE" 2>/dev/null || echo "0")
echo "Current block: $BLOCK_BEFORE_DEC"

# Step 2: Backup current image
echo ""
echo "💾 Backing up current image..."
CURRENT_IMAGE=$(docker inspect "$CONTAINER" --format '{{.Config.Image}}' 2>/dev/null || echo "")
if [[ -n "$CURRENT_IMAGE" ]]; then
    docker tag "$CURRENT_IMAGE" "${CURRENT_IMAGE%:*}:$BACKUP_TAG" 2>/dev/null || true
    echo "Backed up: $CURRENT_IMAGE → ${CURRENT_IMAGE%:*}:$BACKUP_TAG"
fi

# Step 3: Pull new image
echo ""
echo "📥 Pulling latest image..."
NEW_IMAGE="${NEW_IMAGE:-$CURRENT_IMAGE}"
docker pull "$NEW_IMAGE" || { echo "❌ Failed to pull $NEW_IMAGE"; exit 1; }

# Step 4: Stop, update, start
echo ""
echo "🔄 Updating container..."
docker stop "$CONTAINER" 2>/dev/null || true

# Get existing container config for recreation
VOLUMES=$(docker inspect "$CONTAINER" --format '{{range .Mounts}}-v {{.Source}}:{{.Destination}} {{end}}' 2>/dev/null || echo "")
ENV_VARS=$(docker inspect "$CONTAINER" --format '{{range .Config.Env}}-e {{.}} {{end}}' 2>/dev/null || echo "")
NETWORK_MODE=$(docker inspect "$CONTAINER" --format '{{.HostConfig.NetworkMode}}' 2>/dev/null || echo "bridge")

docker rm "$CONTAINER" 2>/dev/null || true

# Recreate with new image
eval "docker run -d --name $CONTAINER --restart unless-stopped --network $NETWORK_MODE $VOLUMES $ENV_VARS $NEW_IMAGE"

# Step 5: Post-update verification
echo ""
echo "⏳ Waiting for node to start (30s)..."
sleep 30

BLOCK_AFTER=$(curl -sf -m 5 -X POST "http://localhost:$RPC_PORT" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | \
    grep -o '"result":"0x[^"]*"' | cut -d'"' -f4 || echo "0x0")
BLOCK_AFTER_DEC=$(printf "%d" "$BLOCK_AFTER" 2>/dev/null || echo "0")

if [[ "$BLOCK_AFTER_DEC" -gt 0 ]]; then
    echo "✅ Update successful! Block: $BLOCK_AFTER_DEC"
else
    echo "❌ Node not responding after update!"
    echo "🔙 Rolling back to backup image..."
    docker stop "$CONTAINER" 2>/dev/null || true
    docker rm "$CONTAINER" 2>/dev/null || true
    eval "docker run -d --name $CONTAINER --restart unless-stopped --network $NETWORK_MODE $VOLUMES $ENV_VARS ${CURRENT_IMAGE%:*}:$BACKUP_TAG"
    echo "Rolled back to $BACKUP_TAG"
    exit 1
fi
