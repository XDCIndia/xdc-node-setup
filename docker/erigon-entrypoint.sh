#!/bin/bash
# Security Fix (#492 #493 #508): Secure RPC defaults + error handling
set -euo pipefail
trap 'echo "Error on line $LINENO" >&2' ERR

#==============================================================================
# XDC Erigon Entrypoint Script
# Security: RPC binds to 127.0.0.1 by default — set RPC_ADDR=0.0.0.0 for external access
#==============================================================================

# Security Fix (#492 #493): Secure defaults — localhost only
: "${NETWORK:=mainnet}"
: "${NETWORK_ID:=50}"
: "${RPC_ADDR:=127.0.0.1}"  # Security: localhost only by default
: "${RPC_VHOSTS:=localhost}"  # Security: no vhosts wildcard
: "${RPC_ALLOW_ORIGINS:=localhost}"  # Security: no CORS wildcard
: "${RPC_CORS:=http://localhost:3000}"  # Default CORS for backwards compat

echo "[Erigon] Starting for network: $NETWORK (ID: $NETWORK_ID)"

# Load bootnodes if file exists
BOOTNODES=""
if [ -f /work/bootnodes.list ]; then
    BOOTNODES=$(grep -v "^#" /work/bootnodes.list | grep -v "^$" | tr "\n" "," | sed "s/,$//" || echo "")
    if [ -n "$BOOTNODES" ]; then
        echo "[Erigon] Loaded $(echo "$BOOTNODES" | tr "," "\n" | wc -l) bootnodes"
    fi
fi

# Determine chain name based on network ID
CHAIN="mainnet"
case "$NETWORK_ID" in
    50) CHAIN="mainnet" ;;
    51) CHAIN="apothem" ;;
    551) CHAIN="devnet" ;;
    *) CHAIN="mainnet" ;;
esac

echo "[Erigon] Chain: $CHAIN"

# Build erigon command
# Security Fix (#492 #493): Use localhost-only defaults instead of wildcards
ERIGON_ARGS=(
    "--datadir=/home/erigon/.local/share/erigon"
    "--chain=$CHAIN"
    "--networkid=$NETWORK_ID"
    "--port=30304"
    "--http"
    "--http.addr=${RPC_ADDR}"
    "--http.port=8555"
    "--http.vhosts=${RPC_VHOSTS}"
    "--http.corsdomain=${RPC_ALLOW_ORIGINS}"
    "--http.api=eth,net,web3,txpool,debug,erigon"
    "--ws"
    "--private.api.addr=127.0.0.1:9090"  # SECURITY: localhost only
    "--metrics"
    "--metrics.addr=127.0.0.1"  # SECURITY: localhost only
    "--metrics.port=6060"
)

# Add bootnodes if available
if [ -n "$BOOTNODES" ]; then
    ERIGON_ARGS+=("--bootnodes=$BOOTNODES")
fi

echo "[Erigon] Starting with args: ${ERIGON_ARGS[@]}"

# Note: Erigon may not have XDC-specific chain configs yet
# This is a placeholder for when XDC Erigon support is available
echo "[Erigon] WARNING: XDC Erigon support may require custom chain configuration"
echo "[Erigon] For now, this will attempt to run with standard Erigon"

# Execute erigon (if binary exists)
if command -v erigon >/dev/null 2>&1; then
    exec erigon "${ERIGON_ARGS[@]}"
else
    echo "[Erigon] ERROR: erigon binary not found in container"
    echo "[Erigon] XDC Erigon client may not be available yet"
    exit 1
fi
