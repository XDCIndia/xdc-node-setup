#!/bin/bash
# Fix for Issue #455 - PROD Server Stuck at Block 678K
# Manual execution required on PROD server

set -euo pipefail

echo "🔴 CRITICAL: Node Stuck at Block 678K Fix Script"
echo "=============================================="
echo ""
echo "This script will:"
echo "1. Stop the XDC node"
echo "2. Backup current chaindata"
echo "3. Clear corrupted chaindata"
echo "4. Download latest snapshot"
echo "5. Restart node with snapshot"
echo ""
read -p "Continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

# Stop node
echo "⏹️  Stopping XDC node..."
docker-compose stop xdc-node-geth-pr5

# Backup current data
echo "💾 Backing up current chaindata..."
BACKUP_DIR="/backup/chaindata-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
mv /xdcchain/XDC "$BACKUP_DIR/" || true

# Download snapshot
echo "📥 Downloading latest mainnet snapshot..."
wget -O snapshot.tar https://download.xinfin.network/xdcchain-snapshot-latest.tar
tar -xvf snapshot.tar -C /xdcchain/

# Restart node
echo "🚀 Restarting node..."
docker-compose up -d xdc-node-geth-pr5

echo "✅ Fix applied. Monitor sync with: docker logs -f xdc-node-geth-pr5"
echo "Expected sync time: 4-6 hours"
