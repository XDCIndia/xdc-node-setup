#!/bin/bash
# =============================================================================
# XDC Node Start Script for SkyOne Agent
# Handles XDC node startup with proper configuration
# =============================================================================

set -euo pipefail

# Configuration
NETWORK="${NETWORK:-mainnet}"
CLIENT="${CLIENT:-stable}"
SYNC_MODE="${SYNC_MODE:-snap}"
INSTANCE_NAME="${INSTANCE_NAME:-XDC-Node}"
DATA_DIR="${DATA_DIR:-/data/xdcchain}"
RPC_PORT="${RPC_PORT:-8545}"
WS_PORT="${WS_PORT:-8546}"
P2P_PORT="${P2P_PORT:-30303}"
METRICS_PORT="${METRICS_PORT:-6060}"

# RPC security
RPC_CORS="${RPC_CORS:-localhost}"
RPC_VHOSTS="${RPC_VHOSTS:-localhost,127.0.0.1}"

log() {
    echo "[$(date -Iseconds)] [XDC] $*"
}

# Ensure data directory exists
mkdir -p "$DATA_DIR"

# Build XDC arguments
XDC_ARGS=(
    --datadir "$DATA_DIR"
    --networkid 50
    --port "$P2P_PORT"
    --rpc
    --rpccorsdomain "$RPC_CORS"
    --rpcvhosts "$RPC_VHOSTS"
    --rpcport "$RPC_PORT"
    --rpcapi "eth,net,web3,admin,debug,personal,txpool,XDPoS"
    --ws
    --wsport "$WS_PORT"
    --wsorigins "$RPC_CORS"
    --wsapi "eth,net,web3,XDPoS"
    --metrics
    --metrics.port "$METRICS_PORT"
    --ethstats "$INSTANCE_NAME:${STATS_SECRET:-xdc_openscan_stats_2026}@${STATS_SERVER:-stats.xdcindia.com:443}"
    --gcmode archive
    --synctarget "$SYNC_MODE"
)

# Add bootnodes based on network
case "$NETWORK" in
    mainnet)
        XDC_ARGS+=(--bootnodes "enode://...")
        ;;
    testnet|apothem)
        XDC_ARGS+=(--bootnodes "enode://...")
        ;;
    devnet)
        XDC_ARGS+=(--bootnodes "enode://...")
        ;;
esac

# Sync mode
if [ "$SYNC_MODE" = "snap" ]; then
    XDC_ARGS+=(--syncmode snap)
else
    XDC_ARGS+=(--syncmode full)
fi

log "Starting XDC Node..."
log "Network: $NETWORK"
log "Client: $CLIENT"
log "Sync Mode: $SYNC_MODE"
log "Data Dir: $DATA_DIR"
log "RPC: http://localhost:$RPC_PORT"
log "P2P: port $P2P_PORT"

# Start XDC node
exec xdc "${XDC_ARGS[@]}" "$@"
