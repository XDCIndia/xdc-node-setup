#!/usr/bin/env bash
# ============================================================
# bootstrap-setup.sh — Deploy v2.6.8 bootstrap + GP5 fast-sync
# Issue: #143
# Usage: ./bootstrap-setup.sh --network mainnet|apothem
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
source "${SCRIPT_DIR}/lib/naming.sh"

# Parse args
NETWORK="mainnet"
ENABLE_SKYNET=true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --network) NETWORK="$2"; shift 2 ;;
        --no-skynet) ENABLE_SKYNET=false; shift ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

SERVER_ID="$(get_server_id)"
LOCATION="$(get_location "$SERVER_ID")"
HOST_IP="$(hostname -I | awk '{print $1}')"
DATA_DIR="${REPO_DIR}/data"

# Names
XDC_NAME="$(build_node_name xdc "$NETWORK" full hbss "$SERVER_ID")"
GETH_NAME="$(build_node_name geth "$NETWORK" full pbss "$SERVER_ID")"

echo "╔══════════════════════════════════════════════╗"
echo "║  XDC Bootstrap + GP5 Fast-Sync Setup         ║"
echo "╠══════════════════════════════════════════════╣"
echo "║  Server:  ${LOCATION} (${HOST_IP})            "
echo "║  Network: ${NETWORK}                          "
echo "║  XDC:     ${XDC_NAME}                         "
echo "║  Geth:    ${GETH_NAME}                        "
echo "╚══════════════════════════════════════════════╝"
echo ""

# Port assignment
if [[ "$NETWORK" == "mainnet" ]]; then
    XDC_RPC=8550; XDC_WS=8551; XDC_P2P=30303; NETWORK_ID=50
    GETH_RPC=8545; GETH_WS=8549; GETH_P2P=30305; GETH_AUTH=8560
    XDC_BINARY="/usr/bin/XDC-mainnet"
else
    XDC_RPC=8550; XDC_WS=8551; XDC_P2P=30303; NETWORK_ID=51
    GETH_RPC=8545; GETH_WS=8549; GETH_P2P=30305; GETH_AUTH=8560
    XDC_BINARY="/usr/bin/XDC-testnet"
fi

# Ethstats config
ETHSTATS_HOST="${ETHSTATS_HOST:-stats.xdcindia.com:443}"
ETHSTATS_SECRET="${ETHSTATS_SECRET:-xdcnetworkstats}"

# ── Step 1: Deploy v2.6.8 (xdc) bootstrap ──────────────────
echo "📦 Step 1: Deploying v2.6.8 bootstrap node..."
mkdir -p "${DATA_DIR}/${NETWORK}/xdc"

docker stop "$XDC_NAME" 2>/dev/null || true
docker rm "$XDC_NAME" 2>/dev/null || true

docker run -d \
    --name "$XDC_NAME" \
    --restart unless-stopped \
    --network host \
    -v "${DATA_DIR}/${NETWORK}/xdc:/work/xdcchain" \
    --entrypoint "$XDC_BINARY" \
    xinfinorg/xdposchain:v2.6.8 \
    --datadir /work/xdcchain --networkid "$NETWORK_ID" \
    --port "$XDC_P2P" --syncmode full --gcmode full --cache 4096 \
    --rpc --rpcaddr 0.0.0.0 --rpcport "$XDC_RPC" \
    --rpccorsdomain "*" --rpcvhosts "*" \
    --rpcapi eth,net,web3,debug,txpool,admin \
    --ws --wsaddr 0.0.0.0 --wsport "$XDC_WS" --wsorigins "*" --wsapi eth,net,web3 \
    --maxpeers 50 --verbosity 3 \
    --ethstats "${XDC_NAME}:${ETHSTATS_SECRET}@${ETHSTATS_HOST}" >/dev/null

echo "   ✅ ${XDC_NAME} started (RPC: ${XDC_RPC}, P2P: ${XDC_P2P})"

# ── Step 2: Wait for v2.6.8 peers ──────────────────────────
echo ""
echo "⏳ Step 2: Waiting for v2.6.8 to find peers..."
for i in $(seq 1 30); do
    PEERS=$(curl -sf -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
        "http://localhost:${XDC_RPC}" 2>/dev/null | jq -r '.result' | xargs printf "%d" 2>/dev/null || echo "0")
    BLOCK=$(curl -sf -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "http://localhost:${XDC_RPC}" 2>/dev/null | jq -r '.result' | xargs printf "%d" 2>/dev/null || echo "0")
    echo "   [${i}/30] peers=${PEERS} block=${BLOCK}"
    [[ "$PEERS" -ge 3 ]] && break
    sleep 10
done

if [[ "$PEERS" -lt 1 ]]; then
    echo "   ⚠️  No peers found after 5 min. GP5 may sync slowly."
fi

# ── Step 3: Extract v2.6.8 enode ────────────────────────────
echo ""
echo "🔗 Step 3: Extracting v2.6.8 enode for trusted peer..."
V268_ENODE=$(curl -sf -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' \
    "http://localhost:${XDC_RPC}" | jq -r '.result.enode' 2>/dev/null)

# Replace 127.0.0.1 with actual IP for external access, keep localhost for local
V268_ENODE_LOCAL=$(echo "$V268_ENODE" | sed "s/@127.0.0.1:/@127.0.0.1:/")
echo "   Enode: ${V268_ENODE_LOCAL:0:80}..."

# Write static-nodes.json for GP5
mkdir -p "${DATA_DIR}/${NETWORK}/geth/XDC"
echo "[\"${V268_ENODE_LOCAL}\"]" > "${DATA_DIR}/${NETWORK}/geth/XDC/static-nodes.json"
echo "   ✅ static-nodes.json written"

# ── Step 4: Deploy GP5 (geth) with trusted peer ────────────
echo ""
echo "📦 Step 4: Deploying GP5 (geth) with v2.6.8 as trusted peer..."
mkdir -p "${DATA_DIR}/${NETWORK}/geth"

docker stop "$GETH_NAME" 2>/dev/null || true
docker rm "$GETH_NAME" 2>/dev/null || true

docker run -d \
    --name "$GETH_NAME" \
    --restart unless-stopped \
    --network host \
    -v "${DATA_DIR}/${NETWORK}/geth:/data" \
    anilchinchawale/gx:fix-7ae44d3fd \
    --datadir /data --networkid "$NETWORK_ID" \
    --port "$GETH_P2P" --syncmode full --gcmode full --cache 4096 \
    --http --http.addr 0.0.0.0 --http.port "$GETH_RPC" \
    --http.corsdomain "*" --http.vhosts "*" \
    --http.api admin,eth,debug,net,txpool,web3,xdpos \
    --ws --ws.addr 0.0.0.0 --ws.port "$GETH_WS" --ws.origins "*" --ws.api eth,net,web3 \
    --authrpc.port "$GETH_AUTH" \
    --maxpeers 50 --verbosity 3 \
    --bootnodes "$V268_ENODE_LOCAL" \
    --ethstats "${GETH_NAME}:${ETHSTATS_SECRET}@${ETHSTATS_HOST}" >/dev/null

echo "   ✅ ${GETH_NAME} started (RPC: ${GETH_RPC}, P2P: ${GETH_P2P})"

# ── Step 5: Deploy SkyOne agents ────────────────────────────
if [[ "$ENABLE_SKYNET" == "true" ]]; then
    echo ""
    echo "🛰️  Step 5: Deploying SkyOne agents..."
    bash "${SCRIPT_DIR}/deploy-skyone.sh" "$XDC_NAME" "$XDC_RPC" "XDC" "$NETWORK"
    bash "${SCRIPT_DIR}/deploy-skyone.sh" "$GETH_NAME" "$GETH_RPC" "geth" "$NETWORK"
fi

# ── Step 6: Verify ──────────────────────────────────────────
echo ""
echo "✅ Step 6: Verification"
sleep 5
for name_port in "${XDC_NAME}:${XDC_RPC}" "${GETH_NAME}:${GETH_RPC}"; do
    name="${name_port%%:*}"
    port="${name_port##*:}"
    block=$(curl -sf -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "http://localhost:${port}" 2>/dev/null | jq -r '.result' | xargs printf "%d" 2>/dev/null || echo "?")
    peers=$(curl -sf -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
        "http://localhost:${port}" 2>/dev/null | jq -r '.result' | xargs printf "%d" 2>/dev/null || echo "?")
    printf "   %-45s block=%-10s peers=%s\n" "$name" "$block" "$peers"
done

echo ""
echo "📦 Containers:"
docker ps --format '   {{.Names}} ({{.Status}})' | grep -E "${LOCATION}" | sort
echo ""
echo "🎉 Bootstrap setup complete for ${NETWORK} on ${LOCATION}!"
