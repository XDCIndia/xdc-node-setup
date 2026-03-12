#!/bin/bash
# Security Fix (#492 #493 #508): Secure RPC defaults + error handling
set -euo pipefail
trap 'echo "ERROR at line $LINENO"' ERR

echo "[Reth-XDC] Starting Reth XDC client for Apothem Testnet..."

# Security Fix (#492 #493): Secure defaults — localhost only
: "${NETWORK:=apothem}"
: "${RPC_PORT:=8588}"
: "${RPC_ADDR:=127.0.0.1}"  # Security: localhost only by default
: "${RPC_ALLOW_ORIGINS:=localhost}"  # Security: no CORS wildcard
: "${P2P_PORT:=30309}"
: "${DISCOVERY_PORT:=40304}"
: "${DATA_DIR:=/work/xdcchain}"

echo "[Reth-XDC] Network: $NETWORK"
echo "[Reth-XDC] RPC Port: $RPC_PORT (bind: $RPC_ADDR)"
echo "[Reth-XDC] P2P Port: $P2P_PORT"

# Apothem bootnodes
BOOTNODES="enode://ee1e11e3f56b015b2b391eb9c45292159713583b4adfe29d24675238f73d33e6ec0a62397847823e2bca622c91892075c517fc383c9355d43a89bb7532e834a0@157.173.120.219:30312,enode://729d763db071595bacbbf33037a8e7639d8e9a97bfcfcda3afe963435d919cb95634f27375f0aadf6494dad47e506c888bf15cb5633d5f81dbb793b05b27e676@207.90.192.100:30312,enode://49c7586c221250cac7070df41c1b6c77180c5d9051e20d1d2b77dfa0dc80b8dc48a8e3c7ca068ac757429223530d6445a06a32ab4af20819cfaa1d47282a0401@80.243.180.121:30312,enode://946cc4d00c4f3e9ffb50fda9d351672d8deaf546e3406228587f8e7131e3c1ad1a0f5ca2d0e2172463a04d747b3e7b29167d93684195952734f4535e7da58351@209.209.10.19:30312,enode://83a51d04ca4056d3630bc2f4e3028de4d041ab346fa5f7ca5bacfb88f4f30b6a055ec34e6350685103abf21cbfed2e79afa229df734909b659c81efc81d3df1c@38.143.58.153:30312"

# Start Reth with secure defaults (localhost binding)
exec xdc-reth node \
  --datadir "$DATA_DIR" \
  --chain xdc-apothem \
  --http \
  --http.addr "$RPC_ADDR" \
  --http.port "$RPC_PORT" \
  --http.api "eth,net,web3,admin,debug" \
  --http.corsdomain "$RPC_ALLOW_ORIGINS" \
  --port "$P2P_PORT" \
  --discovery.port "$DISCOVERY_PORT" \
  --bootnodes "$BOOTNODES"
