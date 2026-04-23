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

# Detect available binary (XDC or geth)
if command -v XDC >/dev/null 2>&1; then
    BINARY="XDC"
elif command -v geth >/dev/null 2>&1; then
    BINARY="geth"
else
    echo "ERROR: No XDC or geth binary found in PATH"
    exit 1
fi

echo "=============================================="
echo "Starting XDC GP5 node..."
echo "Binary: $BINARY"
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

# Init genesis if needed
if [ ! -d "$CHAINDATA_DIR" ]; then
    echo "No existing chaindata found, initializing..."
    
    if [ -f "$PWD_FILE" ]; then
        echo "Creating new wallet..."
        wallet=$($BINARY account new --password "$PWD_FILE" --datadir "$DATADIR" 2>/dev/null | grep -oE '\{[^}]+\}' | tr -d '{}' | head -1)
        [ -n "$wallet" ] && echo "$wallet" > "$DATADIR/coinbase.txt"
        echo "Wallet: $wallet"
    fi
    
    if [ -f "$GENESIS_FILE" ]; then
        echo "Initializing Genesis Block..."
        $BINARY init --datadir "$DATADIR" "$GENESIS_FILE"
        echo "Genesis initialized successfully"
    else
        echo "ERROR: No genesis file at $GENESIS_FILE"
        exit 1
    fi
else
    echo "Existing chaindata found at $CHAINDATA_DIR"
    if [ -f "$PWD_FILE" ]; then
        wallet=$($BINARY account list --datadir "$DATADIR" 2>/dev/null | head -n 1 | grep -oE '\{[^}]+\}' | tr -d '{}')
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

# Write config.toml with static/trusted nodes (GP5 / geth 1.17+ uses config.toml)
CONFIG_DIR="$(dirname "$CONFIG_FILE")"
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" << 'EOF'
[Eth]
NetworkId = NETWORK_ID_PLACEHOLDER
SyncMode = "SYNC_MODE_PLACEHOLDER"

[Node]
DataDir = "DATADIR_PLACEHOLDER"

EOF

# Replace placeholders with actual values
sed -i "s/NETWORK_ID_PLACEHOLDER/$NETWORK_ID/" "$CONFIG_FILE"
sed -i "s/SYNC_MODE_PLACEHOLDER/$SYNC_MODE/" "$CONFIG_FILE"
sed -i "s|DATADIR_PLACEHOLDER|$DATADIR|" "$CONFIG_FILE"

# Add Node.P2P section with static/trusted nodes
if [ -n "${STATIC_NODES:-}" ] || [ -n "${TRUSTED_NODES:-}" ] || [ "${NO_DISCOVER:-false}" = "true" ]; then
    cat >> "$CONFIG_FILE" << 'EOF'
[Node.P2P]
EOF
    echo "ListenAddr = \":${P2P_PORT:-30303}\"" >> "$CONFIG_FILE"
    if [ "${NO_DISCOVER:-false}" = "true" ]; then
        echo "NoDiscovery = true" >> "$CONFIG_FILE"
    fi
    if [ -n "${STATIC_NODES:-}" ]; then
        echo "StaticNodes = [" >> "$CONFIG_FILE"
        first=true
        OLD_IFS="$IFS"
        IFS=','
        for node in $STATIC_NODES; do
            node=$(echo "$node" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [ -z "$node" ] && continue
            if [ "$first" = "true" ]; then
                first=false
                echo "  \"$node\"" >> "$CONFIG_FILE"
            else
                echo "  ,\"$node\"" >> "$CONFIG_FILE"
            fi
        done
        IFS="$OLD_IFS"
        echo "]" >> "$CONFIG_FILE"
    fi
    if [ -n "${TRUSTED_NODES:-}" ]; then
        echo "TrustedNodes = [" >> "$CONFIG_FILE"
        first=true
        OLD_IFS="$IFS"
        IFS=','
        for node in $TRUSTED_NODES; do
            node=$(echo "$node" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [ -z "$node" ] && continue
            if [ "$first" = "true" ]; then
                first=false
                echo "  \"$node\"" >> "$CONFIG_FILE"
            else
                echo "  ,\"$node\"" >> "$CONFIG_FILE"
            fi
        done
        IFS="$OLD_IFS"
        echo "]" >> "$CONFIG_FILE"
    fi
    echo "Wrote config.toml with Node.P2P settings"
else
    echo "Wrote minimal config.toml"
fi

# Also write legacy static-nodes.json and trusted-nodes.json for backward compatibility
if [ -n "${STATIC_NODES:-}" ]; then
    static_nodes_file="$DATADIR/geth/static-nodes.json"
    mkdir -p "$(dirname "$static_nodes_file")"
    json_nodes="["
    first=true
    OLD_IFS="$IFS"
    IFS=','
    for node in $STATIC_NODES; do
        node=$(echo "$node" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$node" ] && continue
        if [ "$first" = "true" ]; then
            first=false
        else
            json_nodes="$json_nodes,"
        fi
        json_nodes="$json_nodes\"$node\""
    done
    IFS="$OLD_IFS"
    json_nodes="$json_nodes]"
    echo "$json_nodes" > "$static_nodes_file"
    echo "Wrote static-nodes.json (legacy)"
fi

if [ -n "${TRUSTED_NODES:-}" ]; then
    trusted_nodes_file="$DATADIR/geth/trusted-nodes.json"
    mkdir -p "$(dirname "$trusted_nodes_file")"
    json_nodes="["
    first=true
    OLD_IFS="$IFS"
    IFS=','
    for node in $TRUSTED_NODES; do
        node=$(echo "$node" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$node" ] && continue
        if [ "$first" = "true" ]; then
            first=false
        else
            json_nodes="$json_nodes,"
        fi
        json_nodes="$json_nodes\"$node\""
    done
    IFS="$OLD_IFS"
    json_nodes="$json_nodes]"
    echo "$json_nodes" > "$trusted_nodes_file"
    echo "Wrote trusted-nodes.json (legacy)"
fi

# Ethstats
netstats="${INSTANCE_NAME}:${STATS_SECRET:-xdc_openscan_stats_2026}@${STATS_SERVER:-stats.xdcindia.com:443}"

# Build command line (GP5 / geth 1.17+ style flags)
ARGS="--datadir $DATADIR"
ARGS="$ARGS --config $CONFIG_FILE"
ARGS="$ARGS --networkid $NETWORK_ID"

# Add --apothem flag for Apothem testnet (chainId 51)
if [ "$NETWORK_ID" = "51" ] || [ "$NETWORK" = "testnet" ] || [ "$NETWORK" = "apothem" ]; then
    ARGS="$ARGS --apothem"
fi

ARGS="$ARGS --port ${P2P_PORT:-30303}"
ARGS="$ARGS --syncmode $SYNC_MODE"
ARGS="$ARGS --gcmode $GC_MODE"
ARGS="$ARGS --authrpc.port ${AUTHRPC_PORT:-8551}"
ARGS="$ARGS --verbosity $LOG_LEVEL"

# No-discover mode
if [ "${NO_DISCOVER:-false}" = "true" ]; then
    ARGS="$ARGS --nodiscover"
    echo "Discovery disabled (no-discover mode)"
fi

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
exec $BINARY $ARGS
