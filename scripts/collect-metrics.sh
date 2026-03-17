#!/usr/bin/env bash
#==============================================================================
# Client Performance Metrics Collector (Issue #468)
# Collects and outputs Prometheus-compatible metrics
#==============================================================================
set -euo pipefail

RPC_URL="${1:-http://127.0.0.1:8545}"
CLIENT_NAME="${2:-unknown}"
NETWORK="${3:-mainnet}"

rpc() {
    curl -sf -m 5 -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$1\",\"params\":${2:-[]},\"id\":1}" 2>/dev/null
}

# Collect metrics
BLOCK_HEX=$(rpc "eth_blockNumber" | grep -o '"result":"0x[^"]*"' | cut -d'"' -f4)
BLOCK_NUM=$(printf "%d" "${BLOCK_HEX:-0x0}" 2>/dev/null || echo "0")

PEER_HEX=$(rpc "net_peerCount" | grep -o '"result":"0x[^"]*"' | cut -d'"' -f4)
PEER_NUM=$(printf "%d" "${PEER_HEX:-0x0}" 2>/dev/null || echo "0")

SYNCING=$(rpc "eth_syncing")
IS_SYNCING=0
if echo "$SYNCING" | grep -q '"currentBlock"'; then
    IS_SYNCING=1
    CURRENT=$(echo "$SYNCING" | grep -o '"currentBlock":"0x[^"]*"' | cut -d'"' -f4)
    HIGHEST=$(echo "$SYNCING" | grep -o '"highestBlock":"0x[^"]*"' | cut -d'"' -f4)
    CURRENT_NUM=$(printf "%d" "${CURRENT:-0x0}" 2>/dev/null || echo "0")
    HIGHEST_NUM=$(printf "%d" "${HIGHEST:-0x0}" 2>/dev/null || echo "0")
fi

GAS_HEX=$(rpc "eth_gasPrice" | grep -o '"result":"0x[^"]*"' | cut -d'"' -f4)
GAS_PRICE=$(printf "%d" "${GAS_HEX:-0x0}" 2>/dev/null || echo "0")

CHAIN_HEX=$(rpc "eth_chainId" | grep -o '"result":"0x[^"]*"' | cut -d'"' -f4)
CHAIN_ID=$(printf "%d" "${CHAIN_HEX:-0x0}" 2>/dev/null || echo "0")

# Output Prometheus format
cat << PROM
# HELP xdc_block_height Current block height
# TYPE xdc_block_height gauge
xdc_block_height{client="$CLIENT_NAME",network="$NETWORK",chain_id="$CHAIN_ID"} $BLOCK_NUM

# HELP xdc_peer_count Connected peer count
# TYPE xdc_peer_count gauge
xdc_peer_count{client="$CLIENT_NAME",network="$NETWORK"} $PEER_NUM

# HELP xdc_is_syncing Whether node is syncing (1=yes, 0=no)
# TYPE xdc_is_syncing gauge
xdc_is_syncing{client="$CLIENT_NAME",network="$NETWORK"} $IS_SYNCING

# HELP xdc_gas_price Current gas price in wei
# TYPE xdc_gas_price gauge
xdc_gas_price{network="$NETWORK"} $GAS_PRICE
PROM

if [[ $IS_SYNCING -eq 1 ]]; then
cat << SYNC
# HELP xdc_sync_current Current sync block
# TYPE xdc_sync_current gauge
xdc_sync_current{client="$CLIENT_NAME"} ${CURRENT_NUM:-0}

# HELP xdc_sync_highest Highest known block
# TYPE xdc_sync_highest gauge
xdc_sync_highest{client="$CLIENT_NAME"} ${HIGHEST_NUM:-0}

# HELP xdc_sync_percent Sync percentage
# TYPE xdc_sync_percent gauge
xdc_sync_percent{client="$CLIENT_NAME"} $(echo "scale=2; ${CURRENT_NUM:-0} * 100 / ${HIGHEST_NUM:-1}" | bc 2>/dev/null || echo "0")
SYNC
fi
