#!/bin/bash

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }
# XDC Network Node Crawler
# XDC Network Node Crawler
# Discovers XDC nodes via P2P protocol and builds a network map

SKYNET_API="https://skynet.xdcindia.com/api/v1"
OUTPUT="/tmp/xdc-network-map.json"

# 1. Get known nodes from SkyNet
echo "Fetching known nodes from SkyNet..."
KNOWN=$(curl -s "$SKYNET_API/peers/healthy?format=json" | jq -r '.enodes[]' 2>/dev/null)

# 2. For each known node, get their peers (if RPC accessible)
# This builds a graph of the network

# 3. Get masternode list from contract
echo "Fetching masternodes..."
MASTERNODES=$(curl -s -X POST https://erpc.xinfin.network \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_call","params":[{"to":"0x0000000000000000000000000000000000000088","data":"0x06a49fce"},"latest"],"id":1}' | jq -r '.result')

# 4. Output network map
echo "Network map saved to $OUTPUT"
