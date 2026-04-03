#!/bin/bash
# Deploy per-client SkyOne monitoring agents for XDC mainnet multi-client setup
# 
# IMPORTANT: Uses bridge network (not host) to avoid port 3000 conflicts.
# Each SkyOne container must connect to its node via container IP + INTERNAL port.
#
# Internal ports (NOT host-mapped ports):
#   gp5    -> container:8545  (host: 8545)
#   erigon -> container:8545  (host: 8546) ← same internal port, different host port
#   nm     -> container:8545  (host: 8547) ← same internal port
#   reth   -> container:7073  (host: 8548) ← different internal port
#
# Why container IP + internal port?
#   Docker bridge DNAT rules don't apply to intra-bridge traffic.
#   Using host.docker.internal:HOST_PORT returns 0 from bridge containers.
#   Must use container IP + the port the service actually listens on inside the container.
#
# Usage: bash deploy-mainnet-agents.sh
# Re-run anytime to update IPs after container restarts.

set -euo pipefail

SKYNET_API_URL="${SKYNET_API_URL:-https://skynet.xdcindia.com/api}"
CONF_DIR="${CONF_DIR:-/mnt/data/mainnet/.xdc-node}"
IMAGE="${IMAGE:-anilchinchawale/xdc-skyone:latest}"

# Internal RPC port each client listens on INSIDE its container
declare -A INTERNAL_PORTS=(
  [gp5]=8545
  [erigon]=8545
  [nm]=8545
  [reth]=7073
)

# Client type labels for SkyNet
declare -A CLIENT_TYPES=(
  [gp5]=geth
  [erigon]=erigon
  [nm]=nethermind
  [reth]=reth
)

# Dashboard ports (host-side)
declare -A DASH_PORTS=(
  [gp5]=7070
  [erigon]=7071
  [nm]=7072
  [reth]=7073
)

get_container_ip() {
  local container="$1"
  docker inspect "$container" 2>/dev/null | python3 -c \
    'import json,sys; nets=json.load(sys.stdin)[0]["NetworkSettings"]["Networks"]; print(list(nets.values())[0]["IPAddress"])' 2>/dev/null
}

deploy_agent() {
  local CLIENT="$1"
  local CONTAINER="xdc-mainnet-${CLIENT}"
  local INTERNAL_PORT="${INTERNAL_PORTS[$CLIENT]}"
  local CTYPE="${CLIENT_TYPES[$CLIENT]}"
  local DASH_PORT="${DASH_PORTS[$CLIENT]}"
  local CONF="${CONF_DIR}/skynet-${CLIENT}.conf"

  # Ensure node container is running
  if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "⚠️  ${CONTAINER} is not running — skipping ${CLIENT}"
    return 1
  fi

  # Get current container IP
  local CONTAINER_IP
  CONTAINER_IP=$(get_container_ip "$CONTAINER")
  if [ -z "$CONTAINER_IP" ]; then
    echo "❌ Could not get IP for ${CONTAINER}"
    return 1
  fi

  local RPC_URL="http://${CONTAINER_IP}:${INTERNAL_PORT}"

  # Update conf file with correct RPC URL (persists across restarts)
  if [ -f "$CONF" ]; then
    sed -i "s|RPC_URL=.*|RPC_URL=${RPC_URL}|g" "$CONF"
  fi

  # Stop and remove old agent
  docker stop "skyone-mainnet-${CLIENT}" 2>/dev/null || true
  docker rm   "skyone-mainnet-${CLIENT}" 2>/dev/null || true

  # Start new agent
  docker run -d \
    --name "skyone-mainnet-${CLIENT}" \
    --restart unless-stopped \
    -v "${CONF}:/etc/xdc-node/skynet.conf:ro" \
    -e RPC_URL="${RPC_URL}" \
    -e CLIENT_TYPE="${CTYPE}" \
    -e XDC_CONTAINER_NAME="${CONTAINER}" \
    -e INSTANCE_NAME="${CLIENT}" \
    -p "${DASH_PORT}:3000" \
    "$IMAGE"

  echo "✅ skyone-mainnet-${CLIENT} | RPC=${RPC_URL} | dashboard->:${DASH_PORT}"
}

echo "=== Deploying XDC Mainnet SkyOne Agents ==="
echo "Conf dir: $CONF_DIR"
echo ""

for CLIENT in gp5 erigon nm reth; do
  deploy_agent "$CLIENT" || true
done

echo ""
echo "Done. Run update-agent-ips.sh to refresh IPs after container restarts."
