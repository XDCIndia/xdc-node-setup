#!/bin/bash
# fix-skynet-all-nodes.sh
# Fixes SkyNet configuration across all XDC nodes

set -e

echo "=============================================="
echo "SkyNet Fix Script - All Nodes"
echo "=============================================="
echo ""

# Generate unique UUID for a node
generate_uuid() {
    uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(date +%s)-$(hostname)-$$"
}

# Fix SkyNet for a specific node
fix_skynet() {
    local network=$1
    local node_name=$2
    local port=$3
    
    echo "Fixing SkyNet for $network ($node_name)..."
    
    # Create .xdc-node directory if not exists
    mkdir -p $network/.xdc-node
    
    # Generate unique node ID
    local node_id=$(generate_uuid)
    
    # Create SkyNet config
    cat > $network/.xdc-node/skynet.conf << EOF
SKYNET_API_URL=https://skynet.xdcindia.com/api
SKYNET_API_KEY=xdc-netown-key-2026-prod
SKYNET_NODE_ID=$node_id
SKYNET_NODE_NAME=$node_name
SKYNET_ROLE=fullnode
EOF
    
    echo "  Created: $network/.xdc-node/skynet.conf"
    echo "  Node ID: $node_id"
    echo "  Node Name: $node_name"
}

# Fix all mainnet nodes
echo "1. Fixing TEST nodes..."
fix_skynet "mainnet" "xdc-gp5-168-mainnet" "8582"
fix_skynet "mainnet" "xdc-stable-168-mainnet" "8580"

echo ""
echo "2. Fixing Apothem nodes..."
fix_skynet "apothem" "xdc-gp5-168-apothem" "8584"

echo ""
echo "=============================================="
echo "SkyNet configs created!"
echo "=============================================="
echo ""
echo "Next steps:"
echo "1. Restart agents: docker compose restart xdc-agent-*"
echo "2. Check logs: docker logs xdc-agent-* | grep SkyNet"
echo ""
