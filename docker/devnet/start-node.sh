#!/bin/bash
set -e

# XDC Devnet Node Startup Script
# Chain ID: 551

# Load Config File (if exists)
CONFIG_FILE="${XDC_CONFIG:-/etc/xdc-node/xdc.conf}"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE" 2>/dev/null || true
    echo "Loaded config from $CONFIG_FILE"
elif [[ -f "/work/xdc.conf" ]]; then
    source "/work/xdc.conf" 2>/dev/null || true
    echo "Loaded config from /work/xdc.conf"
fi

# Ensure XDC binary is available
if ! command -v XDC &>/dev/null; then
    for bin in XDC XDC-devnet XDC-testnet XDC-mainnet; do
        if command -v "$bin" &>/dev/null; then
            ln -sf "$(which "$bin")" /usr/bin/XDC
            echo "Linked $bin → /usr/bin/XDC"
            break
        fi
    done
fi
command -v XDC &>/dev/null || { echo "FATAL: No XDC binary found!"; exit 1; }

echo "XDC Devnet Node"
echo "Chain ID: 551"

# Defaults
: "${SYNC_MODE:=full}"
: "${GC_MODE:=full}"
: "${LOG_LEVEL:=3}"
: "${INSTANCE_NAME:=xdc-devnet-node}"
: "${ENABLE_RPC:=true}"
: "${RPC_ADDR:=0.0.0.0}"
: "${RPC_PORT:=8545}"
: "${RPC_API:=admin,eth,net,web3,XDPoS}"
: "${WS_ADDR:=0.0.0.0}"
: "${WS_PORT:=8546}"

echo "Config: sync=$SYNC_MODE gc=$GC_MODE log=$LOG_LEVEL"

# Init wallet
if [ ! -d /work/xdcchain/XDC/chaindata ]; then
    wallet=$(XDC account new --password /work/.pwd --datadir /work/xdcchain 2>/dev/null | awk -F '[{}]' '{print $2}')
    echo "Initializing Devnet Genesis Block"
    echo "$wallet" > /work/xdcchain/coinbase.txt
    XDC init --datadir /work/xdcchain /work/genesis.json
else
    wallet=$(XDC account list --datadir /work/xdcchain 2>/dev/null | head -n 1 | awk -F '[{}]' '{print $2}')
fi
echo "Wallet: $wallet"

# Bootnodes
bootnodes=""
if [ -f /work/bootnodes.list ]; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [ -z "$bootnodes" ] && bootnodes="$line" || bootnodes="${bootnodes},$line"
    done < /work/bootnodes.list
fi

# Devnet uses networkid 551
LOG_FILE="/work/xdcchain/xdc-$(date +%Y%m%d-%H%M%S).log"

args=(
    --datadir /work/xdcchain
    --networkid 551
    --port 30303
    --syncmode "$SYNC_MODE"
    --gcmode "$GC_MODE"
    --verbosity "$LOG_LEVEL"
    --password /work/.pwd
    --mine
    --gasprice 1
    --targetgaslimit 420000000
    --ipcpath /work/xdcchain/XDC.ipc
)

# Add wallet
[ -n "$wallet" ] && args+=(--unlock "$wallet")

# Add bootnodes
[ -n "$bootnodes" ] && args+=(--bootnodes "$bootnodes")

# XDCx
args+=(--XDCx.datadir /work/xdcchain/XDCx)

# RPC flags
if echo "$ENABLE_RPC" | grep -iq "true"; then
    args+=(
        --rpc
        --rpcaddr "$RPC_ADDR"
        --rpcport "$RPC_PORT"
        --rpcapi "$RPC_API"
        --rpccorsdomain "*"
        --rpcvhosts "*"
        --store-reward
        --ws
        --wsaddr "$WS_ADDR"
        --wsport "$WS_PORT"
        --wsapi "eth,net,web3,XDPoS"
        --wsorigins "*"
    )
fi

echo "Starting XDC Devnet node..."
exec XDC "${args[@]}" 2>&1 | tee -a "$LOG_FILE"
