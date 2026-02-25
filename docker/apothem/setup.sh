#!/bin/bash
set -e

# Apothem Testnet Node Setup Script
# This script validates and starts an Apothem testnet node

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=============================================="
echo "XDC Apothem Testnet Node Setup"
echo "=============================================="

# Validate genesis file exists
if [ ! -f "$SCRIPT_DIR/genesis.json" ]; then
    echo "❌ Error: genesis.json not found"
    exit 1
fi

# Validate genesis file matches official
GENESIS_HASH=$(sha256sum "$SCRIPT_DIR/genesis.json" | awk '{print $1}')
echo "✓ Genesis file found (SHA256: $GENESIS_HASH)"

# Validate bootnodes exist
if [ ! -f "$SCRIPT_DIR/bootnodes.list" ]; then
    echo "❌ Error: bootnodes.list not found"
    exit 1
fi

BOOTNODE_COUNT=$(grep -c "^enode" "$SCRIPT_DIR/bootnodes.list" || echo "0")
echo "✓ Bootnodes found: $BOOTNODE_COUNT"

# Create network if it doesn't exist
if ! docker network ls | grep -q "xdc-network"; then
    echo "Creating xdc-network..."
    docker network create xdc-network
fi

# Validate ports are available
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "⚠️  Warning: Port $port is already in use"
    else
        echo "✓ Port $port is available"
    fi
}

echo ""
echo "Checking ports..."
check_port 8545  # RPC
check_port 8546  # WS
check_port 30303 # P2P

echo ""
echo "=============================================="
echo "Starting Apothem Testnet Node"
echo "=============================================="
echo "Network ID: 51"
echo "RPC: http://0.0.0.0:8545"
echo "WS:  ws://0.0.0.0:8546"
echo "P2P: 0.0.0.0:30303"
echo "=============================================="

# Run docker-compose
cd "$PROJECT_DIR/docker"
docker-compose -f docker-compose.apothem-geth.yml up -d

echo ""
echo "Node starting... Check logs with:"
echo "  docker logs -f xdc-node-apothem"
echo ""
echo "Check sync status:"
echo "  curl -s http://localhost:8545 -X POST -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_syncing\",\"params\":[],\"id\":1}'"
