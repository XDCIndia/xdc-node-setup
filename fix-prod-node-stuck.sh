#!/bin/bash
# Fix for PROD server stuck at block 0
# Issue #455

set -euo pipefail

PROD_SERVER="65.21.27.213"
SSH_PORT="12141"

echo "[$(date)] Starting PROD node recovery for $PROD_SERVER"

# 1. Check current status
echo "Checking current block height..."
ssh -p $SSH_PORT root@$PROD_SERVER "curl -s http://localhost:8545 -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"

# 2. Stop the stuck node
echo "Stopping stuck geth-pr5 node..."
ssh -p $SSH_PORT root@$PROD_SERVER "docker stop xdc-node-geth-pr5 || true"

# 3. Remove old chaindata
echo "Removing corrupted chaindata..."
ssh -p $SSH_PORT root@$PROD_SERVER "docker run --rm -v xdc-node-geth-pr5:/xdcchain anilchinchawale/xdc-geth-pr5:rlp-fix rm -rf /xdcchain/XDC/chaindata || true"

# 4. Download latest snapshot
echo "Downloading latest mainnet snapshot..."
ssh -p $SSH_PORT root@$PROD_SERVER << 'REMOTE'
cd /tmp
wget -c https://download.xinfin.network/XDC-mainnet.tar || true
if [ -f XDC-mainnet.tar ]; then
  docker run --rm -v xdc-node-geth-pr5:/xdcchain -v /tmp:/backup anilchinchawale/xdc-geth-pr5:rlp-fix tar -xvf /backup/XDC-mainnet.tar -C /xdcchain/
  rm -f XDC-mainnet.tar
fi
REMOTE

# 5. Restart node
echo "Restarting node..."
ssh -p $SSH_PORT root@$PROD_SERVER "docker start xdc-node-geth-pr5"

# 6. Wait and verify
sleep 30
echo "Verifying new block height..."
ssh -p $SSH_PORT root@$PROD_SERVER "curl -s http://localhost:8545 -X POST -H 'Content-Type: application/json' --data '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"

echo "[$(date)] Recovery complete!"
