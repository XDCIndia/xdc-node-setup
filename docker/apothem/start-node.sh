#!/bin/bash
set -e

# Source common utilities
# shellcheck source=/dev/null
source "$(dirname "$0")/../scripts/lib/common.sh" 2>/dev/null || {
    # Fallback bootnode loader if common.sh not available
    load_bootnodes() {
        local bootnodes_file="${1:-/work/bootnodes.list}"
        grep -v "^#" "$bootnodes_file" 2>/dev/null | grep -v "^$" | tr "\n" "," | sed 's/,$//'
    }
}

log_info "Starting XDC Apothem Testnet Node (Network ID: 51)..."

# Load bootnodes
BOOTNODES=$(load_bootnodes /work/bootnodes.list)

log_info "Loaded $(echo "$BOOTNODES" | tr "," "\n" | wc -l) bootnodes"

# Start XDC with proper Apothem testnet flags
exec XDC \
  --datadir /work/xdcchain \
  --networkid 51 \
  --port 30303 \
  --syncmode full \
  --gcmode full \
  --verbosity 2 \
  --mine \
  --gasprice 1 \
  --targetgaslimit 420000000 \
  --ipcpath /tmp/XDC.ipc \
  --nat=any \
  --bootnodes "$BOOTNODES" \
  --ethstats "${INSTANCE_NAME:-xdc-node}:${STATS_SECRET:-xdc_openscan_stats_2026}@${STATS_SERVER:-stats.xdcindia.com:443}" \
  --XDCx.datadir /work/xdcchain/XDCx \
  --rpc \
  --rpcaddr 127.0.0.1 \  # SECURITY FIX #355: Localhost only
  --rpcport 9545 \
  --rpcapi admin,eth,net,web3,XDPoS \
  --rpccorsdomain "${RPC_CORS:-*}" \
  --rpcvhosts "*" \
  --store-reward \
  --ws \
  --wsaddr 127.0.0.1 \
  --wsport 9546 \
  --wsapi eth,net,web3,txpool,debug,XDPoS \
  --wsorigins "*"
