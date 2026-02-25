#!/bin/sh
set -e

#==============================================================================
# XDC Geth PR5 Start Script (POSIX sh compatible)
# Feature branch: feature/xdpos-consensus
# Fixed: Removed bash-isms for Alpine compatibility
#==============================================================================

# Config files
CONFIG_FILE="/etc/xdc-node/config.toml"
GENESIS_FILE="/work/genesis.json"
BOOTNODES_FILE="/work/bootnodes.list"
PWD_FILE="/work/.pwd"
DATADIR="/work/xdcchain"

echo "Starting XDC Geth PR5 node..."
echo "Datadir: $DATADIR"
echo "Config: $CONFIG_FILE"

# ============================================================
# Load config.toml - POSIX sh compatible parser
# ============================================================
load_config() {
    config_file="$1"
    [ ! -f "$config_file" ] && return
    
    section=""
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        case "$line" in
            \#*|"") continue ;;
        esac
        
        # Track section headers [section.name]
        case "$line" in
            \[*\])
                section=$(echo "$line" | sed 's/.*\[\([^]]*\)\].*/\1/' | sed 's/.*\.//')
                continue
                ;;
        esac
        
        # Parse key = "value" or key = value
        key=$(echo "$line" | sed -n 's/^[[:space:]]*\([a-zA-Z_][a-zA-Z0-9_]*\)[[:space:]]*=.*/\1/p')
        [ -z "$key" ] && continue
        
        value=$(echo "$line" | sed 's/^[^=]*=[[:space:]]*//' | sed 's/^"//' | sed 's/"$//' | sed 's/[[:space:]]*#.*//')
        
        # Skip array values
        case "$value" in
            \[*) continue ;;
        esac
        
        # Export as uppercase
        ukey=$(echo "$key" | tr '[:lower:]' '[:upper:]')
        if [ -n "$section" ]; then
            usection=$(echo "$section" | tr '[:lower:]' '[:upper:]')
            eval "export ${usection}_${ukey}='$value'"
        fi
        eval "export ${ukey}='$value'"
    done < "$config_file"
    echo "Loaded config from $config_file"
}

if [ -f "$CONFIG_FILE" ]; then
    load_config "$CONFIG_FILE"
fi

# ============================================================
# Defaults
# ============================================================
SYNC_MODE="${SYNC_MODE:-full}"
GC_MODE="${GC_MODE:-full}"
LOG_LEVEL="${LEVEL:-2}"
INSTANCE_NAME="${INSTANCE_NAME:-XDC_Geth_PR5}"
RPC_ADDR="${HTTP_ADDR:-${ADDR:-0.0.0.0}}"
RPC_PORT="${HTTP_PORT:-${PORT:-8545}}"
RPC_API="${HTTP_API:-${API:-admin,eth,net,web3,XDPoS}}"
RPC_CORS_DOMAIN="${HTTP_CORS_DOMAIN:-${CORS_DOMAIN:-*}}"
RPC_VHOSTS="${HTTP_VHOSTS:-${VHOSTS:-*}}"
WS_ADDR="${WS_ADDR:-0.0.0.0}"
WS_PORT="${WS_PORT:-8546}"
WS_API="${WS_API:-eth,net,web3,XDPoS}"
WS_ORIGINS="${WS_ORIGINS:-*}"

echo "Config: sync=$SYNC_MODE gc=$GC_MODE log=$LOG_LEVEL"

# ============================================================
# Init or recover wallet
# ============================================================
if [ ! -d "$DATADIR/XDC/chaindata" ]; then
    echo "Initializing new node..."
    
    # Create wallet
    if [ -f "$PWD_FILE" ]; then
        wallet=$(XDC account new --password "$PWD_FILE" --datadir "$DATADIR" 2>/dev/null | grep -oE '\{[^}]+\}' | tr -d '{}' | head -1)
        echo "$wallet" > "$DATADIR/coinbase.txt"
    fi
    
    # Initialize genesis
    if [ -f "$GENESIS_FILE" ]; then
        echo "Initializing Genesis Block from $GENESIS_FILE"
        XDC init --datadir "$DATADIR" "$GENESIS_FILE"
    else
        echo "WARNING: No genesis file found at $GENESIS_FILE"
    fi
else
    echo "Existing chaindata found, recovering wallet..."
    wallet=$(XDC account list --datadir "$DATADIR" 2>/dev/null | head -n 1 | grep -oE '\{[^}]+\}' | tr -d '{}')
fi

[ -n "$wallet" ] && echo "Wallet: $wallet"

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
# Get external IP for NAT
# ============================================================
if [ -z "$EXTERNAL_IP" ]; then
    EXTERNAL_IP=$(wget -qO- https://checkip.amazonaws.com 2>/dev/null || curl -s https://checkip.amazonaws.com 2>/dev/null || echo "")
fi

# ============================================================
# Ethstats
# ============================================================
netstats="${INSTANCE_NAME}:xinfin_xdpos_hybrid_network_stats@stats.xinfin.network:3000"

# ============================================================
# Build command line args
# ============================================================
ARGS="--datadir $DATADIR"
ARGS="$ARGS --networkid ${NETWORK_ID:-50}"
ARGS="$ARGS --port 30303"
ARGS="$ARGS --syncmode $SYNC_MODE"
ARGS="$ARGS --gcmode $GC_MODE"
ARGS="$ARGS --verbosity $LOG_LEVEL"

# Wallet unlock
if [ -n "$wallet" ] && [ -f "$PWD_FILE" ]; then
    ARGS="$ARGS --password $PWD_FILE"
    ARGS="$ARGS --unlock $wallet"
    ARGS="$ARGS --mine"
fi

ARGS="$ARGS --gasprice 1"
ARGS="$ARGS --targetgaslimit 420000000"

# Bootnodes
[ -n "$bootnodes" ] && ARGS="$ARGS --bootnodes $bootnodes"

# NAT
[ -n "$EXTERNAL_IP" ] && ARGS="$ARGS --nat extip:$EXTERNAL_IP"

# Ethstats
ARGS="$ARGS --ethstats $netstats"

# XDCx data dir
ARGS="$ARGS --XDCx.datadir $DATADIR/XDCx"

# HTTP/RPC - GP5 uses new-style --http.* flags
ARGS="$ARGS --http"
ARGS="$ARGS --http.addr $RPC_ADDR"
ARGS="$ARGS --http.port $RPC_PORT"
ARGS="$ARGS --http.api $RPC_API"
ARGS="$ARGS --http.corsdomain $RPC_CORS_DOMAIN"
ARGS="$ARGS --http.vhosts $RPC_VHOSTS"

# WebSocket
ARGS="$ARGS --ws"
ARGS="$ARGS --ws.addr $WS_ADDR"
ARGS="$ARGS --ws.port $WS_PORT"
ARGS="$ARGS --ws.api $WS_API"
ARGS="$ARGS --ws.origins $WS_ORIGINS"

# Store reward for consensus
ARGS="$ARGS --store-reward"

echo "=============================================="
echo "Starting XDC Geth PR5..."
echo "Args: $ARGS"
echo "=============================================="

# shellcheck disable=SC2086
exec XDC $ARGS
