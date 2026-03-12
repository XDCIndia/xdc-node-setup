#!/bin/bash
set -e

echo "[INFO] Starting Erigon for XDC Apothem Testnet (Network ID: 51)..."

# Load bootnodes
BOOTNODES=$(grep -v "^#" /work/bootnodes.list | grep -v "^$" | tr "\n" "," | sed "s/,$//")

echo "[INFO] Loaded $(echo "$BOOTNODES" | tr "," "\n" | wc -l) bootnodes"

# Start Erigon with Apothem configuration
exec erigon \
  --datadir /work/erigon \
  --chain xdc-apothem \
  --networkid 51 \
  --port 30304 \
  --http \
  --http.addr 127.0.0.1 \  # SECURITY FIX #355: Localhost only
  --http.port 8555 \
  --http.vhosts "*" \
  --http.corsdomain "*" \
  --http.api eth,net,web3,txpool,debug,erigon \
  --ws \
  --ws.addr 0.0.0.0 \
  --ws.port 8556 \
  --private.api.addr 0.0.0.0:9090 \
  --bootnodes "$BOOTNODES" \
  --metrics \
  --metrics.addr 0.0.0.0 \
  --metrics.port 6060 \
  --pprof \
  --pprof.addr 0.0.0.0 \
  --pprof.port 6061
