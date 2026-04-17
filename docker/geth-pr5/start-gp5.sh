#!/bin/sh
set -e

#==============================================================================
# XDC GP5 (go-ethereum PR5) Start Script
# Uses NEW-style flags (--miner.*, --http.*)
# Compatible with geth 1.17+ / GP5
#==============================================================================

CONFIG_FILE="/etc/xdc-node/config.toml"
GENESIS_FILE="/work/genesis.json"
BOOTNODES_FILE="/work/bootnodes.list"
PWD_FILE="/work/.pwd"
DATADIR="/work/xdcchain"

echo "=============================================="
echo "Starting XDC GP5 node..."
echo "Datadir: $DATADIR"
echo "=============================================="

# Defaults
SYNC_MODE="${SYNC_MODE:-full}"
GC_MODE="${GC_MODE:-full}"
LOG_LEVEL="${LEVEL:-3}"
INSTANCE_NAME="${INSTANCE_NAME:-XDC_GP5}"
# RPC/HTTP settings - use 0.0.0.0 in Docker for port mapping to work
# Set HTTP_ADDR=127.0.0.1 for bare-metal installs where security matters
RPC_ADDR="${HTTP_ADDR:-${ADDR:-0.0.0.0}}"
RPC_PORT="${HTTP_PORT:-${PORT:-8545}}"
RPC_API="${HTTP_API:-admin,eth,net,web3}"
RPC_CORS_DOMAIN="${HTTP_CORS_DOMAIN:-*}"
RPC_VHOSTS="${HTTP_VHOSTS:-*}"  # Allow all vhosts for Docker; restrict in production
WS_ADDR="${WS_ADDR:-0.0.0.0}"
WS_PORT="${WS_PORT:-8546}"
WS_API="${WS_API:-eth,net,web3}"
WS_ORIGINS="${WS_ORIGINS:-*}"
NETWORK_ID="${NETWORK_ID:-50}"

echo "Config: sync=$SYNC_MODE gc=$GC_MODE network=$NETWORK_ID"

# Init genesis if needed
if [ ! -d "$DATADIR/XDC/chaindata" ]; then
    echo "No existing chaindata found, initializing..."
    
    if [ -f "$PWD_FILE" ]; then
        echo "Creating new wallet..."
        wallet=$(XDC account new --password "$PWD_FILE" --datadir "$DATADIR" 2>/dev/null | grep -oE '\{[^}]+\}' | tr -d '{}' | head -1)
        [ -n "$wallet" ] && echo "$wallet" > "$DATADIR/coinbase.txt"
        echo "Wallet: $wallet"
    fi
    
    if [ -f "$GENESIS_FILE" ]; then
        echo "Initializing Genesis Block..."
        XDC init --datadir "$DATADIR" "$GENESIS_FILE"
        echo "Genesis initialized successfully"
    else
        echo "ERROR: No genesis file at $GENESIS_FILE"
        exit 1
    fi
else
    echo "Existing chaindata found at $DATADIR/XDC/chaindata"
    if [ -f "$PWD_FILE" ]; then
        wallet=$(XDC account list --datadir "$DATADIR" 2>/dev/null | head -n 1 | grep -oE '\{[^}]+\}' | tr -d '{}')
        [ -n "$wallet" ] && echo "Wallet: $wallet"
    fi
fi

# Build bootnodes list
bootnodes=""
if [ -f "$BOOTNODES_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        case "$line" in \#*) continue ;; esac
        if [ -z "$bootnodes" ]; then
            bootnodes="$line"
        else
            bootnodes="${bootnodes},$line"
        fi
    done < "$BOOTNODES_FILE"
    echo "Loaded bootnodes from $BOOTNODES_FILE"
fi

# Get external IP
if [ -z "$EXTERNAL_IP" ]; then
    EXTERNAL_IP=$(wget -qO- https://checkip.amazonaws.com 2>/dev/null || curl -s https://checkip.amazonaws.com 2>/dev/null || echo "")
fi
[ -n "$EXTERNAL_IP" ] && echo "External IP: $EXTERNAL_IP"

# Ethstats
netstats="${INSTANCE_NAME}:${STATS_SECRET:-xdc_openscan_stats_2026}@${STATS_SERVER:-stats.xdcindia.com:443}"

# Build command line (GP5 / geth 1.17+ style flags)
ARGS="--datadir $DATADIR"
ARGS="$ARGS --networkid $NETWORK_ID"
ARGS="$ARGS --port 30303"
ARGS="$ARGS --syncmode $SYNC_MODE"
ARGS="$ARGS --gcmode $GC_MODE"
ARGS="$ARGS --verbosity $LOG_LEVEL"

# Miner settings (GP5 uses --miner.* style flags)
ARGS="$ARGS --miner.gasprice 1"
ARGS="$ARGS --miner.gaslimit 420000000"

# Wallet unlock for mining
if [ -n "$wallet" ] && [ -f "$PWD_FILE" ]; then
    ARGS="$ARGS --password $PWD_FILE"
    ARGS="$ARGS --unlock $wallet"
    ARGS="$ARGS --allow-insecure-unlock"
    ARGS="$ARGS --mine"
fi

# Bootnodes
[ -n "$bootnodes" ] && ARGS="$ARGS --bootnodes $bootnodes"

# NAT
[ -n "$EXTERNAL_IP" ] && ARGS="$ARGS --nat extip:$EXTERNAL_IP"

# Ethstats (conditional)
if [ "${ETHSTATS_ENABLED:-true}" != "false" ]; then
    ARGS="$ARGS --ethstats $netstats"
    echo "Ethstats enabled: reporting to ${STATS_SERVER:-stats.xdcindia.com:443} as ${INSTANCE_NAME:-XDC_GP5}"
else
    echo "Ethstats disabled"
fi

# HTTP/RPC (GP5 uses --http.* style flags)
ARGS="$ARGS --http"
ARGS="$ARGS --http.addr=$RPC_ADDR"
ARGS="$ARGS --http.port=$RPC_PORT"
ARGS="$ARGS --http.api=$RPC_API"
ARGS="$ARGS --http.corsdomain=$RPC_CORS_DOMAIN"
ARGS="$ARGS --http.vhosts=$RPC_VHOSTS"

# WebSocket (GP5 uses --ws.* style flags)
ARGS="$ARGS --ws"
ARGS="$ARGS --ws.addr=$WS_ADDR"
ARGS="$ARGS --ws.port=$WS_PORT"
ARGS="$ARGS --ws.api=$WS_API"
ARGS="$ARGS --ws.origins=$WS_ORIGINS"

# Pass through any extra args
ARGS="$ARGS $*"

echo "=============================================="
echo "Starting XDC with args:"
echo "$ARGS" | tr ' ' '\n' | grep -v '^$'
echo "=============================================="

# shellcheck disable=SC2086
exec XDC $ARGS
