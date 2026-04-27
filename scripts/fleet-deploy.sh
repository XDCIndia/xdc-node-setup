#!/usr/bin/env bash
#===============================================================================
# XDC Fleet Dual-Network Deployment Script
# Deploys mainnet + apothem nodes across fleet with HBSS/PBSS coverage
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/188
#
# Usage:
#   fleet-deploy.sh <server_id> <network> [client] [scheme]
#   fleet-deploy.sh 125 mainnet geth pbss
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/naming.sh" 2>/dev/null || true

# --- Args ---
SERVER_ID="${1:-}"
NETWORK="${2:-}"
CLIENT="${3:-geth}"
SCHEME="${4:-pbss}"

[[ -z "$SERVER_ID" || -z "$NETWORK" ]] && {
    echo "Usage: $0 <server_id> <network> [client] [scheme]"
    echo "  server_id: 168, 183, 109, 113, 125, 4 (xdc07)"
    echo "  network: mainnet | apothem"
    echo "  client: geth (GP5) | xdc (v268) | erigon | nethermind | reth"
    echo "  scheme: pbss | hbss | archive"
    exit 1
}

# --- Config ---
LOCATION="$(get_location "$SERVER_ID" 2>/dev/null || echo "srv${SERVER_ID}")"
CLIENT_NORM="$(get_client_name "$CLIENT" 2>/dev/null || echo "$CLIENT")"
IMAGE_TAG="${IMAGE_TAG:-v94}"
NODE_NAME="$(build_node_name "$CLIENT_NORM" "$NETWORK" "full" "$SCHEME" "$SERVER_ID" "$IMAGE_TAG" "01" 2>/dev/null || echo "${LOCATION}-${CLIENT_NORM}-full-${SCHEME}-${NETWORK}-${SERVER_ID}")"
CONTAINER_NAME="${NODE_NAME}"

# Network-specific ports
if [[ "$NETWORK" == "mainnet" ]]; then
    P2P_PORT=30303
    HTTP_PORT=8545
    WS_PORT=8546
    AUTHRPC_PORT=8551
    NETWORK_ID=50
else
    P2P_PORT=30320
    HTTP_PORT=9645
    WS_PORT=9646
    AUTHRPC_PORT=9651
    NETWORK_ID=51
fi

# --- Datadir setup ---
BASE_DIR="${BASE_DIR:-/mnt/data/xdc-nodes}"
NODE_DIR="${BASE_DIR}/${NETWORK}/${NODE_NAME}"
DATADIR="${NODE_DIR}/datadir"
CONFIGDIR="${NODE_DIR}/config"
LOGDIR="${NODE_DIR}/logs"
SNAPSHOTDIR="${NODE_DIR}/snapshots"

echo "=== Fleet Deploy: ${NODE_NAME} ==="
echo "  Server:     ${LOCATION} (${SERVER_ID})"
echo "  Network:    ${NETWORK} (chainId ${NETWORK_ID})"
echo "  Client:     ${CLIENT_NORM}"
echo "  Scheme:     ${SCHEME}"
echo "  Datadir:    ${DATADIR}"
echo "  P2P Port:   ${P2P_PORT}"
echo "  HTTP Port:  ${HTTP_PORT}"
echo ""

# Create directory structure
mkdir -p "$DATADIR" "$CONFIGDIR" "$LOGDIR" "$SNAPSHOTDIR"

# --- Docker compose generation ---
COMPOSE_FILE="${NODE_DIR}/docker-compose.yml"

cat > "$COMPOSE_FILE" <<EOF
version: '3.8'
services:
  ${CONTAINER_NAME}:
    image: anilchinchawale/gp5-xdc:${IMAGE_TAG}-amd64
    platform: linux/amd64
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    stop_grace_period: 3m
    network_mode: host
    volumes:
      - ${DATADIR}:/work/xdcchain
      - ${CONFIGDIR}:/work/config:ro
      - ${LOGDIR}:/work/logs
      - ${SNAPSHOTDIR}:/work/snapshots
    environment:
      - NETWORK=${NETWORK}
      - NETWORK_ID=${NETWORK_ID}
      - SYNC_MODE=full
      - GC_MODE=full
      - STATE_SCHEME=${SCHEME}
      - CACHE=4096
      - MAXPEERS=50
      - HTTP_PORT=${HTTP_PORT}
      - WS_PORT=${WS_PORT}
      - AUTHRPC_PORT=${AUTHRPC_PORT}
      - P2P_PORT=${P2P_PORT}
      - EXTERNAL_IP=\${EXTERNAL_IP:-}
      - INSTANCE_NAME=${NODE_NAME}
      - HTTP_API=admin,eth,net,web3,xdpos
      - ETHSTATS_ENABLED=\${ETHSTATS_ENABLED:-true}
      - STATS_SECRET=\${STATS_SECRET}
      - STATS_SERVER=\${STATS_SERVER:-stats.xdcindia.com:443}
      - STATIC_NODES=\${STATIC_NODES}
      - TRUSTED_NODES=\${TRUSTED_NODES}
    healthcheck:
      test:
        - CMD-SHELL
        - 'wget -qO- http://localhost:${HTTP_PORT} --post-data=''{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'' --header=''Content-Type: application/json'' | grep -q ''result'' || exit 1'
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 180s
    logging:
      driver: json-file
      options:
        max-size: 100m
        max-file: '5'
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 12G
        reservations:
          cpus: '2.0'
          memory: 8G
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
EOF

echo "Generated: ${COMPOSE_FILE}"
echo ""
echo "To start:"
echo "  cd ${NODE_DIR} && docker compose up -d"
echo ""
echo "To add to Skynet:"
echo "  skynet-agent.sh register ${NODE_NAME} http://localhost:${HTTP_PORT}"
