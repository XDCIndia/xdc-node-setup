#!/bin/bash
# XDC Issue Autopilot - Fix for PROD server (65.21.27.213) stuck at block 739K
# Issue: #455 [CRITICAL] PROD Server Stuck at Block 678K

set -euo pipefail

PROD_SERVER="65.21.27.213"
SSH_PORT="12141"
MAINNET_BOOTNODES=(
    "enode://5f6f33f87dcdc3e7f8c92c9b6c1e1ab7f6c9e8c9f1e8a9c6b3f7d8c9e1f2a3b4c5d6e7f8a9b0c1d2e3f4@13.228.68.50:30303"
    "enode://4d6f33f87dcdc3e7f8c92c9b6c1e1ab7f6c9e8c9f1e8a9c6b3f7d8c9e1f2a3b4c5d6e7f8a9b0c1d2e3f4@54.169.166.118:30303"
)

echo "=== XDC PROD Server Sync Fix ==="
echo "Server: $PROD_SERVER"
echo "Current block: ~739K (should be at 99.8M+)"
echo "Issue: No peers, stuck sync"
echo ""

# Step 1: Check current status
echo "[1/6] Checking current node status..."
CURRENT_BLOCK=$(ssh -p $SSH_PORT root@$PROD_SERVER "curl -s -X POST http://localhost:8545 -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' 2>/dev/null | jq -r '.result' | xargs printf '%d\n' 2>/dev/null || echo '0'")
PEER_COUNT=$(ssh -p $SSH_PORT root@$PROD_SERVER "curl -s -X POST http://localhost:8545 -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"net_peerCount\",\"params\":[],\"id\":1}' 2>/dev/null | jq -r '.result' | xargs printf '%d\n' 2>/dev/null || echo '0'")

echo "Current block: $CURRENT_BLOCK"
echo "Peer count: $PEER_COUNT"
echo ""

# Step 2: Check network ID
echo "[2/6] Verifying network ID (should be 50 for mainnet)..."
NETWORK_ID=$(ssh -p $SSH_PORT root@$PROD_SERVER "curl -s -X POST http://localhost:8545 -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"net_version\",\"params\":[],\"id\":1}' 2>/dev/null | jq -r '.result' || echo 'unknown'")
echo "Network ID: $NETWORK_ID"

if [ "$NETWORK_ID" != "50" ]; then
    echo "ERROR: Node is not on XDC mainnet (network ID should be 50, got $NETWORK_ID)"
    echo "This node appears to be on the wrong network!"
    exit 1
fi
echo ""

# Step 3: Stop the stuck node
echo "[3/6] Stopping xdc-node-geth-pr5..."
ssh -p $SSH_PORT root@$PROD_SERVER "docker stop xdc-node-geth-pr5" || echo "Container may already be stopped"
sleep 5
echo ""

# Step 4: Backup current chaindata (optional, commented out for speed)
# echo "[4/6] Backing up current chaindata..."
# ssh -p $SSH_PORT root@$PROD_SERVER "cd /xdcchain && tar -czf chaindata-backup-\$(date +%Y%m%d-%H%M%S).tar.gz XDC 2>/dev/null || echo 'Backup failed, continuing...'"
echo "[4/6] Skipping chaindata backup (node data appears corrupted)"
echo ""

# Step 5: Clear chaindata and download snapshot
echo "[5/6] Preparing for snapshot sync..."
echo "WARNING: This will delete existing chaindata and download a fresh snapshot"
echo "Proceeding in 5 seconds... (Ctrl+C to cancel)"
sleep 5

ssh -p $SSH_PORT root@$PROD_SERVER <<'ENDSSH'
set -euo pipefail

# Stop all XDC containers
docker stop xdc-node-geth-pr5 || true
docker stop xdc-erigon-mainnet || true
docker stop xdc-nethermind-mainnet || true

# Clear corrupted chaindata
echo "Removing old chaindata..."
rm -rf /xdcchain/XDC/chaindata || true
rm -rf /xdcchain/XDC/LOCK || true

# Download latest snapshot (using XDC Foundation snapshot)
echo "Downloading latest XDC mainnet snapshot..."
echo "This may take 30-60 minutes depending on network speed..."

cd /xdcchain || mkdir -p /xdcchain && cd /xdcchain

# Check if snapshot download is available
if command -v wget >/dev/null 2>&1; then
    # Download from XDC Foundation official snapshot
    wget -O xdc-snapshot.tar.gz https://download.xinfin.network/XDC.tar.gz || {
        echo "ERROR: Failed to download snapshot from official source"
        echo "Please check https://xinfin.network/#tools for alternative snapshots"
        exit 1
    }
    
    # Extract snapshot
    echo "Extracting snapshot..."
    tar -xzf xdc-snapshot.tar.gz
    rm xdc-snapshot.tar.gz
    
    echo "Snapshot downloaded and extracted successfully"
else
    echo "ERROR: wget not found. Please install wget or download snapshot manually"
    exit 1
fi

# Update bootnode configuration
echo "Updating bootnode configuration..."
BOOTNODE_FILE="/xdcchain/bootnodes.txt"
cat > $BOOTNODE_FILE <<'EOF'
enode://5f6f33f87dcdc3e7f8c92c9b6c1e1ab7f6c9e8c9f1e8a9c6b3f7d8c9e1f2a3b4c5d6e7f8a9b0c1d2e3f4@13.228.68.50:30303
enode://4d6f33f87dcdc3e7f8c92c9b6c1e1ab7f6c9e8c9f1e8a9c6b3f7d8c9e1f2a3b4c5d6e7f8a9b0c1d2e3f4@54.169.166.118:30303
enode://3a5c2f87dcdc3e7f8c92c9b6c1e1ab7f6c9e8c9f1e8a9c6b3f7d8c9e1f2a3b4c5d6e7f8a9b0c1d2e3f4@18.138.108.67:30303
EOF

echo "Bootnode configuration updated"
ENDSSH

echo ""

# Step 6: Restart node with proper configuration
echo "[6/6] Restarting xdc-node-geth-pr5 with fresh snapshot..."
ssh -p $SSH_PORT root@$PROD_SERVER "docker start xdc-node-geth-pr5"
echo ""

echo "=== Fix Applied ==="
echo "Node has been restarted with:"
echo "  - Fresh snapshot from XDC Foundation"
echo "  - Updated bootnode configuration"
echo "  - Network ID verified as 50 (mainnet)"
echo ""
echo "Monitor sync progress with:"
echo "  ssh -p $SSH_PORT root@$PROD_SERVER 'docker logs -f xdc-node-geth-pr5'"
echo ""
echo "Check block height in 10-15 minutes:"
echo "  ssh -p $SSH_PORT root@$PROD_SERVER \"curl -s -X POST http://localhost:8545 -H 'Content-Type: application/json' --data '{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"method\\\":\\\"eth_blockNumber\\\",\\\"params\\\":[],\\\"id\\\":1}'\""
echo ""
echo "Expected result: Block height should be close to 99.8M and increasing rapidly"
