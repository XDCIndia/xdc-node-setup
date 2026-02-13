#!/bin/bash
set -e

# Ensure XDC binary is available (some images use XDC-mainnet instead of XDC)
if ! command -v XDC &>/dev/null; then
    for bin in XDC-mainnet XDC-testnet XDC-devnet XDC-local; do
        if command -v "$bin" &>/dev/null; then
            ln -sf "$(which "$bin")" /usr/bin/XDC
            echo "Linked $bin → /usr/bin/XDC"
            break
        fi
    done
fi
command -v XDC &>/dev/null || { echo "FATAL: No XDC binary found!"; exit 1; }

# Detect XDC client version to determine flag style
# Old XDPoS (v2.x): uses --rpc, --rpcaddr, --rpcport
# New geth-based: uses --http, --http.addr, --http.port
XDC_VERSION=$(XDC version 2>/dev/null | head -1 || echo "unknown")
echo "XDC version: $XDC_VERSION"

detect_rpc_style() {
    # v2.6.8 supports --http-addr (dash) but NOT --http.addr (dot)
    # Newer geth supports --http.addr (dot)
    # Check for dot-style first (true new geth), then dash-style, then old --rpc
    if XDC --help 2>&1 | grep -q "\-\-http\.addr"; then
        echo "new"       # geth-style --http.addr --http.port
    elif XDC --help 2>&1 | grep -q "\-\-http-addr"; then
        echo "dash"      # v2.6.8 style --http-addr --http-port
    else
        echo "old"       # legacy --rpcaddr --rpcport
    fi
}
RPC_STYLE=$(detect_rpc_style)
echo "RPC flag style: $RPC_STYLE"

# ============================================================
# Defaults (env vars override these)
# ============================================================
: "${SYNC_MODE:=full}"
: "${GC_MODE:=full}"
: "${LOG_LEVEL:=2}"
: "${INSTANCE_NAME:=XDC_Node}"
: "${ENABLE_RPC:=true}"
: "${RPC_ADDR:=0.0.0.0}"
: "${RPC_PORT:=8545}"
: "${RPC_API:=admin,eth,net,web3,XDPoS}"
: "${RPC_CORS_DOMAIN:=*}"
: "${RPC_VHOSTS:=*}"
: "${WS_ADDR:=0.0.0.0}"
: "${WS_PORT:=8546}"
: "${WS_API:=eth,net,web3,XDPoS}"
: "${WS_ORIGINS:=*}"

echo "Config: sync=$SYNC_MODE gc=$GC_MODE log=$LOG_LEVEL rpc=$ENABLE_RPC"

# ============================================================
# Init or recover wallet
# ============================================================
if [ ! -d /work/xdcchain/XDC/chaindata ]; then
    wallet=$(XDC account new --password /work/.pwd --datadir /work/xdcchain 2>/dev/null | awk -F '[{}]' '{print $2}')
    echo "Initializing Genesis Block"
    echo "$wallet" > /work/xdcchain/coinbase.txt
    XDC init --datadir /work/xdcchain /work/genesis.json
else
    wallet=$(XDC account list --datadir /work/xdcchain 2>/dev/null | head -n 1 | awk -F '[{}]' '{print $2}')
fi
echo "Wallet: $wallet"

# ============================================================
# Bootnodes
# ============================================================
bootnodes=""
if [ -f /work/bootnodes.list ]; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [ -z "$bootnodes" ] && bootnodes="$line" || bootnodes="${bootnodes},$line"
    done < /work/bootnodes.list
fi

# ============================================================
# Ethstats
# ============================================================
INSTANCE_IP=$(curl -s https://checkip.amazonaws.com 2>/dev/null || echo "unknown")
netstats="${INSTANCE_NAME}:xinfin_xdpos_hybrid_network_stats@stats.xinfin.network:3000"

# ============================================================
# Build args
# ============================================================
LOG_FILE="/work/xdcchain/xdc-$(date +%Y%m%d-%H%M%S).log"

args=(
    --datadir /work/xdcchain
    --networkid 50
    --port 30303
    --syncmode "$SYNC_MODE"
    --gcmode "$GC_MODE"
    --verbosity "$LOG_LEVEL"
    --password /work/.pwd
    --mine
    --gasprice 1
    --targetgaslimit 420000000
    --ipcdisable
)

# Add wallet unlock if available
[ -n "$wallet" ] && args+=(--unlock "$wallet")

# Add bootnodes if available
[ -n "$bootnodes" ] && args+=(--bootnodes "$bootnodes")

# Add ethstats
args+=(--ethstats "$netstats")

# XDCx data dir
args+=(--XDCx.datadir /work/xdcchain/XDCx)

# ============================================================
# RPC/HTTP flags (style-dependent)
# ============================================================
if echo "$ENABLE_RPC" | grep -iq "true"; then
    if [ "$RPC_STYLE" = "new" ]; then
        # New geth-style flags (--http.*)
        args+=(
            --http
            --http.addr "$RPC_ADDR"
            --http.port "$RPC_PORT"
            --http.api "$RPC_API"
            --http.corsdomain "$RPC_CORS_DOMAIN"
            --http.vhosts "$RPC_VHOSTS"
            --ws
            --ws.addr "$WS_ADDR"
            --ws.port "$WS_PORT"
            --ws.api "$WS_API"
            --ws.origins "$WS_ORIGINS"
        )
    elif [ "$RPC_STYLE" = "dash" ]; then
        # XDC v2.6.x supports both --http-addr and --rpcaddr; use legacy --rpc* per reference
        args+=(
            --rpc
            --rpcaddr "$RPC_ADDR"
            --rpcport "$RPC_PORT"
            --rpcapi "$RPC_API"
            --rpccorsdomain "$RPC_CORS_DOMAIN"
            --rpcvhosts "$RPC_VHOSTS"
            --store-reward
            --ws
            --wsaddr "$WS_ADDR"
            --wsport "$WS_PORT"
            --wsapi "$WS_API"
            --wsorigins "$WS_ORIGINS"
        )
    else
        # Legacy XDPoS flags (--rpc*)
        args+=(
            --rpc
            --rpcaddr "$RPC_ADDR"
            --rpcport "$RPC_PORT"
            --rpcapi "$RPC_API"
            --rpccorsdomain "$RPC_CORS_DOMAIN"
            --rpcvhosts "$RPC_VHOSTS"
            --store-reward
            --ws
            --wsaddr "$WS_ADDR"
            --wsport "$WS_PORT"
            --wsapi "$WS_API"
            --wsorigins "$WS_ORIGINS"
        )
    fi
fi

# ============================================================
# Add any extra args passed via docker command
# ============================================================
args+=("$@")

echo "Starting XDC node..."
echo "Args: ${args[*]}"
exec XDC "${args[@]}" 2>&1 | tee -a "$LOG_FILE"
