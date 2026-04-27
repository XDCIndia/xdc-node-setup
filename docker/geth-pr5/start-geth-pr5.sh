#!/bin/sh
set -e

#==============================================================================
# XDC Geth PR5 Start Script (POSIX sh compatible)
# Feature branch: xdc-network  
# Compatible with geth 1.17+ (new-style flags)
#==============================================================================

# Config files
CONFIG_FILE="/etc/xdc-node/config.toml"
GENESIS_FILE="/work/genesis.json"
BOOTNODES_FILE="/work/bootnodes.list"
PWD_FILE="/work/.pwd"
DATADIR="/work/xdcchain"

echo "=============================================="
echo "Starting XDC Geth PR5 node..."
echo "Datadir: $DATADIR"
echo "=============================================="
# Issue #550: Peer compatibility warning
echo ""
echo "⚠️  PEER WARNING: GP5 nodes should ONLY peer with GP5 nodes."
echo "   Cross-client peering (GP5<->Erigon) causes 'invalid ancestor' errors."
echo "   Run: scripts/generate-static-nodes.sh gp5"
echo ""

# ============================================================
# Defaults
# ============================================================
SYNC_MODE="${SYNC_MODE:-full}"
GC_MODE="${GC_MODE:-full}"
LOG_LEVEL="${LEVEL:-3}"
INSTANCE_NAME="${INSTANCE_NAME:-XDC_Geth_PR5}"
RPC_ADDR="${HTTP_ADDR:-${ADDR:-0.0.0.0}}"
RPC_PORT="${HTTP_PORT:-${PORT:-8545}}"
RPC_API="${HTTP_API:-admin,eth,net,web3}"
RPC_CORS_DOMAIN="${HTTP_CORS_DOMAIN:-*}"
RPC_VHOSTS="${HTTP_VHOSTS:-*}"
WS_ADDR="${WS_ADDR:-0.0.0.0}"
WS_PORT="${WS_PORT:-8546}"
WS_API="${WS_API:-eth,net,web3}"
WS_ORIGINS="${WS_ORIGINS:-*}"
NETWORK_ID="${NETWORK_ID:-50}"

echo "Config: sync=$SYNC_MODE gc=$GC_MODE network=$NETWORK_ID"

# ============================================================
# Init genesis if needed
# ============================================================

# Issue #548: Pre-flight check for genesis.json
if [ ! -f "$GENESIS_FILE" ]; then
    echo "=============================================="
    echo "ERROR: Genesis file not found!"
    echo "=============================================="
    echo "Expected location: $GENESIS_FILE"
    echo ""
    echo "This file is required to initialize the blockchain."
    echo "Without it, the node will sync to Ethereum mainnet instead of XDC Network."
    echo ""
    echo "Please ensure genesis.json is mounted correctly in docker-compose.yml:"
    echo "  volumes:"
    echo "    - ./mainnet/genesis.json:/work/genesis.json:ro"
    echo "=============================================="
    exit 1
fi

# Detect chaindata subdirectory (geth/ vs XDC/ vs xdcchain/)
find_chaindata_subdir() {
    _base="$1"
    if [ -d "$_base/geth/chaindata" ]; then
        echo "geth"
    elif [ -d "$_base/XDC/chaindata" ]; then
        echo "XDC"
    elif [ -d "$_base/xdcchain/chaindata" ]; then
        echo "xdcchain"
    elif [ -d "$_base/chaindata" ]; then
        echo ""
    else
        echo "geth"
    fi
}

CHAIN_SUBDIR=$(find_chaindata_subdir "$DATADIR")
if [ -n "$CHAIN_SUBDIR" ]; then
    CHAINDATA_DIR="$DATADIR/$CHAIN_SUBDIR/chaindata"
else
    CHAINDATA_DIR="$DATADIR/chaindata"
fi

if [ ! -d "$CHAINDATA_DIR" ]; then
    echo "No existing chaindata found, initializing..."
    
    # Create wallet if password file exists
    if [ -f "$PWD_FILE" ]; then
        echo "Creating new wallet..."
        wallet=$(XDC account new --password "$PWD_FILE" --datadir "$DATADIR" 2>/dev/null | grep -oE '\{[^}]+\}' | tr -d '{}' | head -1)
        [ -n "$wallet" ] && echo "$wallet" > "$DATADIR/coinbase.txt"
        echo "Wallet: $wallet"
    fi
    
    # Initialize genesis
    echo "Initializing Genesis Block..."
    XDC init --datadir "$DATADIR" "$GENESIS_FILE"
    echo "Genesis initialized successfully"
    
    # Issue #548: Verify genesis hash after initialization
    echo "Verifying genesis block hash..."
    sleep 2
    
    # Query block 0 to get genesis hash
    # Start XDC in background temporarily to query genesis
    XDC --datadir "$DATADIR" --networkid ${NETWORK_ID:-50} --port 0 --nodiscover --maxpeers 0 \
        --http --http.addr 127.0.0.1 --http.port 18545 --http.api eth &
    XDC_PID=$!
    
    # Wait for RPC to become available
    for i in $(seq 1 10); do
        if curl -sf -X POST http://127.0.0.1:18545 \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    
    # Get genesis block hash
    GENESIS_HASH=$(curl -sf -X POST http://127.0.0.1:18545 \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x0",false],"id":1}' 2>/dev/null \
        | grep -o '"hash":"0x[^"]*"' | cut -d'"' -f4 | sed 's/^0x//')
    
    # Stop temporary XDC instance
    kill $XDC_PID 2>/dev/null || true
    wait $XDC_PID 2>/dev/null || true
    
    # Expected XDC mainnet genesis hash
    EXPECTED_GENESIS="4a9d748bd78a8d0385b67788c2435dcdb914f98a96250b68863a1f8b7642d6b1"
    
    if [ -n "$GENESIS_HASH" ]; then
        echo "Genesis hash: 0x$GENESIS_HASH"
        if [ "$GENESIS_HASH" = "$EXPECTED_GENESIS" ]; then
            echo "✓ Genesis hash verified (XDC mainnet)"
        else
            echo "⚠ Warning: Genesis hash does not match XDC mainnet"
            echo "  Got:      0x$GENESIS_HASH"
            echo "  Expected: 0x$EXPECTED_GENESIS"
            echo "  Proceeding anyway (may be testnet/devnet)..."
        fi
    else
        echo "⚠ Warning: Could not verify genesis hash (RPC unavailable)"
        echo "  Node will start but please verify network after sync"
    fi
else
    echo "Existing chaindata found at $CHAINDATA_DIR"
    # Get existing wallet
    if [ -f "$PWD_FILE" ]; then
        wallet=$(XDC account list --datadir "$DATADIR" 2>/dev/null | head -n 1 | grep -oE '\{[^}]+\}' | tr -d '{}')
        [ -n "$wallet" ] && echo "Wallet: $wallet"
    fi
fi

# ============================================================
# Bootnodes
# ============================================================
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

# ============================================================
# Get external IP
# ============================================================
if [ -z "$EXTERNAL_IP" ]; then
    EXTERNAL_IP=$(wget -qO- https://checkip.amazonaws.com 2>/dev/null || curl -s https://checkip.amazonaws.com 2>/dev/null || echo "")
fi
[ -n "$EXTERNAL_IP" ] && echo "External IP: $EXTERNAL_IP"

# ============================================================
# Ethstats
# ============================================================
netstats="${INSTANCE_NAME}:${STATS_SECRET:-xdc_openscan_stats_2026}@${STATS_SERVER:-stats.xdcindia.com:443}"

# ============================================================
# Build command line (GP5 / geth 1.17+ style flags)
# ============================================================
ARGS="--datadir $DATADIR"
ARGS="$ARGS --networkid $NETWORK_ID"
ARGS="$ARGS --port 30303"
ARGS="$ARGS --syncmode $SYNC_MODE"
ARGS="$ARGS --gcmode $GC_MODE"
ARGS="$ARGS --verbosity $LOG_LEVEL"

# Miner settings - use --miner.* style flags (GP5 / geth 1.17+)
ARGS="$ARGS --miner.gasprice 1"
ARGS="$ARGS --miner.gaslimit 420000000"

# Wallet unlock for mining
if [ -n "$wallet" ] && [ -f "$PWD_FILE" ]; then
    ARGS="$ARGS --password $PWD_FILE"
    ARGS="$ARGS --unlock $wallet"
    ARGS="$ARGS --mine"
fi

# Bootnodes
[ -n "$bootnodes" ] && ARGS="$ARGS --bootnodes $bootnodes"

# NAT
[ -n "$EXTERNAL_IP" ] && ARGS="$ARGS --nat extip:$EXTERNAL_IP"

# Ethstats
ARGS="$ARGS --ethstats $netstats"

# HTTP/RPC (XDC uses old geth-style flags)
ARGS="$ARGS --rpc"
ARGS="$ARGS --rpcaddr $RPC_ADDR"
ARGS="$ARGS --rpcport $RPC_PORT"
ARGS="$ARGS --rpcapi $RPC_API"
ARGS="$ARGS --rpccorsdomain $RPC_CORS_DOMAIN"
ARGS="$ARGS --rpcvhosts $RPC_VHOSTS"

# WebSocket (XDC uses old geth-style flags)
ARGS="$ARGS --ws"
ARGS="$ARGS --wsaddr $WS_ADDR"
ARGS="$ARGS --wsport $WS_PORT"
ARGS="$ARGS --wsapi $WS_API"
ARGS="$ARGS --wsorigins $WS_ORIGINS"

# Pass through any extra args
ARGS="$ARGS $*"

echo "=============================================="
echo "Starting XDC with args:"
echo "$ARGS" | tr ' ' '\n' | grep -v '^$'
echo "=============================================="

# shellcheck disable=SC2086
exec XDC $ARGS
