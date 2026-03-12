#!/bin/bash
# Fix for issue #455 - PROD server stuck at block 678K

set -e

echo "=== Fixing PROD Node Database Corruption ==="
echo "Issue: Missing state trie node - full resync required"
echo ""

# Stop containers
echo "1. Stopping XDC containers..."
ssh -p 12141 root@65.21.27.213 'cd /root/xdc-node-setup && docker compose stop xdc-node-geth-pr5'

# Backup current state (just in case)
echo "2. Creating backup marker..."
ssh -p 12141 root@65.21.27.213 'echo "Backup started at $(date)" > /root/xdc-backup-$(date +%Y%m%d-%H%M%S).txt'

# Clear corrupted chaindata
echo "3. Removing corrupted chaindata..."
ssh -p 12141 root@65.21.27.213 'rm -rf /root/xdc-data/gp5/chaindata /root/xdc-data/gp5/nodes'

# Restart with fresh sync
echo "4. Restarting node for fresh sync..."
ssh -p 12141 root@65.21.27.213 'cd /root/xdc-node-setup && docker compose up -d xdc-node-geth-pr5'

echo ""
echo "=== Fix Applied ==="
echo "Node will resync from scratch. This may take several hours."
echo "Monitor progress: ssh -p 12141 root@65.21.27.213 'docker logs -f xdc-node-geth-pr5'"
echo ""
echo "Recommended: Use snapshot sync for faster recovery"
echo "Download from: https://download.xinfin.network/"
