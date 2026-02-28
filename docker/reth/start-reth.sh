#!/bin/bash
set -e

#==============================================================================
# XDC Reth Start Script
# Handles initialization and startup of Reth XDC client
#==============================================================================

: "${NETWORK:=mainnet}"
: "${SYNC_MODE:=full}"
: "${RPC_PORT:=7073}"
: "${P2P_PORT:=40303}"
: "${DISCOVERY_PORT:=40304}"
: "${INSTANCE_NAME:=Reth_XDC_Node}"
: "${DEBUG_TIP:=}"
: "${BOOTNODES:=}"

# Network configuration
case "$NETWORK" in
    mainnet)
        CHAIN_ID=50
        CHAIN_NAME="xdc-mainnet"
        NETWORK_NAME="XDC Mainnet"
        ;;
    testnet|apothem)
        CHAIN_ID=51
        CHAIN_NAME="xdc-apothem"
        NETWORK_NAME="XDC Apothem Testnet"
        ;;
    devnet)
        CHAIN_ID=551
        CHAIN_NAME="xdc-devnet"
        NETWORK_NAME="XDC Devnet"
        ;;
    *)
        CHAIN_ID=50
        CHAIN_NAME="xdc-mainnet"
        NETWORK_NAME="XDC Mainnet"
        ;;
esac

echo "=== XDC Reth Node ==="
echo "Network: $NETWORK_NAME (Chain ID: $CHAIN_ID)"
echo "RPC Port: $RPC_PORT"
echo "P2P Port: $P2P_PORT"
echo "Discovery Port: $DISCOVERY_PORT"
echo "Instance: $INSTANCE_NAME"
echo ""

# Issue #71: Generate deterministic identity on first boot
DATADIR="/work/xdcchain"
if [ ! -f "$DATADIR/.node-identity" ]; then
  echo "[SkyNet] First boot detected - generating node identity..."
  # Generate a deterministic identifier
  IDENTITY_SEED="${HOSTNAME:-reth}-$(date +%Y%m)"
  echo "$IDENTITY_SEED" > "$DATADIR/.node-identity"
  echo "[SkyNet] Generated identity seed (node will generate its own p2p keys)"
fi

# Build Reth arguments
RETH_ARGS=(
    node
    --chain "$CHAIN_NAME"
    --datadir "$DATADIR"
    --http
    --http.port "${RPC_PORT}"
    --http.addr "127.0.0.1"  # SECURITY FIX #355: Localhost only
    --http.api "eth,net,web3,admin,debug,trace"
    --port "${P2P_PORT}"
    --discovery.port "${DISCOVERY_PORT}"
)

# Add debug.tip if provided (required for sync without CL)
if [[ -n "$DEBUG_TIP" ]]; then
    RETH_ARGS+=(--debug.tip "$DEBUG_TIP")
fi

# Add bootnodes if provided
if [[ -n "$BOOTNODES" ]]; then
    # Split by comma and add each as --bootnodes flag
    IFS=',' read -ra NODES <<< "$BOOTNODES"
    for node in "${NODES[@]}"; do
        RETH_ARGS+=(--bootnodes "$node")
    done
fi

# Add metrics if enabled
if [[ "${METRICS_ENABLED:-false}" == "true" ]]; then
    RETH_ARGS+=(--metrics "0.0.0.0:9001")
fi

# Set log level
RETH_ARGS+=(--log.stdout.filter "${LOG_LEVEL:-info}")

echo "Starting Reth..."
echo "Command: /reth/bin/xdc-reth ${RETH_ARGS[*]}"
echo ""

# Execute Reth
if [[ -x /reth/bin/xdc-reth ]]; then
    exec /reth/bin/xdc-reth "${RETH_ARGS[@]}" 2>&1 | tee -a /reth/logs/reth.log
else
    echo "ERROR: xdc-reth binary not found at /reth/bin/xdc-reth"
    ls -la /reth/bin/
    exit 1
fi
