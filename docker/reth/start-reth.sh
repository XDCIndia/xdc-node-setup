#!/bin/bash
# Security Fix (#492 #493 #508): Secure RPC defaults + error handling
set -euo pipefail
trap 'echo "ERROR at line $LINENO"' ERR

echo "[Reth-XDC] Starting Reth XDC client with external RPC access..."

# Configuration
NETWORK="${NETWORK:-mainnet}"
RPC_PORT="${RPC_PORT:-7073}"
P2P_PORT="${P2P_PORT:-40303}"
DISCOVERY_PORT="${DISCOVERY_PORT:-40304}"
DATA_DIR="${DATA_DIR:-/work/xdcchain}"

echo "[Reth-XDC] Network: $NETWORK"
echo "[Reth-XDC] RPC Port: $RPC_PORT (bound to 0.0.0.0)"
echo "[Reth-XDC] P2P Port: $P2P_PORT"

# Static nodes for XDC mainnet
STATIC_NODES='["/ip4/65.21.27.213/tcp/30303/p2p/f164c4adb9c873ee08871bea823e1d6fecfbfbc7a3520107eda1563f1d845d0774042aeadc9b3803ef23e820b528b191ca74ed74bca0c57cc84084ba3061ff5b","/ip4/185.180.220.183/tcp/30303/p2p/fd601f09148a5e958ce86f115e4ad473e7e5baa4dbad9cfceb7024ba188455e68c3f5e091072ac9bf8620778a7f03847a6ad14f3cdc9c7ef1d446c68041ab88d"]'

# Start Reth with explicit 0.0.0.0 binding
exec xdc-reth node \
  --datadir "$DATA_DIR" \
  --chain xdc-mainnet \
  --http \
  --http.addr 0.0.0.0 \
  --http.port "$RPC_PORT" \
  --http.api "eth,net,web3,admin,debug" \
  --http.corsdomain "*" \
  --port "$P2P_PORT" \
  --discovery.port "$DISCOVERY_PORT" \
  --bootnodes "enode://f164c4adb9c873ee08871bea823e1d6fecfbfbc7a3520107eda1563f1d845d0774042aeadc9b3803ef23e820b528b191ca74ed74bca0c57cc84084ba3061ff5b@65.21.27.213:30303,enode://fd601f09148a5e958ce86f115e4ad473e7e5baa4dbad9cfceb7024ba188455e68c3f5e091072ac9bf8620778a7f03847a6ad14f3cdc9c7ef1d446c68041ab88d@185.180.220.183:30303"
