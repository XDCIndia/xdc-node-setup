#!/bin/bash
# Security Fix (#492 #493 #508): Secure RPC defaults + error handling
set -euo pipefail
trap 'echo "ERROR at line $LINENO"' ERR

export PATH="/run/xdc:/tmp:/var/tmp:$PATH"

# Source common utilities
# shellcheck source=/dev/null
source "$(dirname "$0")/../scripts/lib/common.sh" 2>/dev/null || {
    echo "WARN: common.sh not found, using built-in defaults"
}

#==============================================================================
# Load Config File (if exists) - env vars override config file
#==============================================================================
if ! load_config_standard "${XDC_CONFIG}"; then
    echo "WARN: No config file found, using hardcoded defaults"
fi

# Ensure XDC binary is available
ensure_xdc_binary

# Detect XDC client version to determine flag style
XDC_VERSION=$(XDC version 2>/dev/null | head -1 || echo "unknown")
log_info "XDC version: $XDC_VERSION"

RPC_STYLE=$(detect_rpc_style)
log_info "RPC flag style: $RPC_STYLE"

# ============================================================
# Defaults - Only used if config.toml is missing
# Config.toml is the single source of truth
# ============================================================
export SYNC_MODE="${SYNC_MODE:-full}"
export GC_MODE="${GC_MODE:-full}"
export LOG_LEVEL="${LEVEL:-2}"
export INSTANCE_NAME="${INSTANCE_NAME:-XDC_Node}"
export ENABLE_RPC="${ENABLED:-true}"
# Security Fix (#492 #493): Secure RPC defaults — localhost only, no wildcards
# Use RPC_ADDR=0.0.0.0 explicitly for production deployments
export RPC_ADDR="${RPC_ADDR:-${ADDR:-127.0.0.1}}"
# XNS Standard: Use port 9545 (not 8545) for RPC
export RPC_PORT="${HTTP_PORT:-${RPC_PORT:-9545}}"
export RPC_API="${API:-admin,eth,net,web3,XDPoS}"
# Security Fix (#492): Default CORS to localhost only (not * wildcard)
export RPC_ALLOW_ORIGINS="${RPC_ALLOW_ORIGINS:-${CORS_DOMAIN:-${RPC_CORS:-localhost}}}"
export RPC_CORS_DOMAIN="$RPC_ALLOW_ORIGINS"
# Security Fix (#492): Default vhosts to localhost only (not * wildcard)
export RPC_VHOSTS="${RPC_VHOSTS:-${VHOSTS:-localhost}}"
# Security: Default to localhost for WebSocket
export WS_ADDR="${WS_ADDR:-127.0.0.1}"
# XNS Standard: Use port 9546 (not 8546) for WebSocket
export WS_PORT="${WS_PORT:-9546}"
export WS_API="${WS_API:-eth,net,web3,XDPoS}"
# Security: Default to localhost for WS origins
export WS_ORIGINS="${WS_ORIGINS:-localhost}"

echo "Config: sync=$SYNC_MODE gc=$GC_MODE log=$LOG_LEVEL rpc=$ENABLE_RPC"

# ============================================================
# Init or recover wallet
# Issue #71: Auto-create account on first boot
# ============================================================
DATADIR="/work/xdcchain"

# Issue #71: Check if we need to create a new account (first boot)
if [ ! -d "$DATADIR/keystore" ] || [ -z "$(ls $DATADIR/keystore/ 2>/dev/null)" ]; then
  echo "[SkyNet] First boot detected - creating new node account..."
  # Create account with empty password
  echo "" | XDC account new --datadir "$DATADIR" --password /dev/stdin 2>/dev/null
  ACCOUNT=$(XDC account list --datadir "$DATADIR" 2>/dev/null | head -1 | grep -oP '0x[0-9a-fA-F]{40}')
  if [ -n "$ACCOUNT" ]; then
    echo "$ACCOUNT" > "$DATADIR/.node-identity"
    echo "[SkyNet] Created account: $ACCOUNT"
  fi
fi

if [ ! -d /work/xdcchain/XDC/chaindata ]; then
    wallet=$(XDC account new --password /work/.pwd --datadir /work/xdcchain 2>/dev/null | awk -F '[{}]' '{print $2}')
    echo "Initializing Genesis Block"
    echo "$wallet" > /work/xdcchain/coinbase.txt
    XDC init --datadir /work/xdcchain /work/genesis.json
else
    wallet=$(XDC account list --datadir /work/xdcchain 2>/dev/null | head -n 1 | awk -F '[{}]' '{print $2}')
fi
echo "Wallet: $wallet"

# Issue #71: Read coinbase address for etherbase
ETHERBASE=""
if [ -f "$DATADIR/.node-identity" ]; then
  ETHERBASE=$(cat "$DATADIR/.node-identity")
  echo "[SkyNet] Using coinbase for etherbase: $ETHERBASE"
fi

# ============================================================
# Bootnodes
# ============================================================
bootnodes=$(load_bootnodes /work/bootnodes.list)

# ============================================================
# Build args
# ============================================================
LOG_FILE="/work/xdcchain/xdc-$(date +%Y%m%d-%H%M%S).log"

# Ethstats configuration for network visibility
netstats="${INSTANCE_NAME:-xdc-node}:${STATS_SECRET:-xdc_openscan_stats_2026}@${STATS_SERVER:-stats.xdcindia.com:443}"

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
    --ipcpath /tmp/XDC.ipc
    --nat=any
)

# Add wallet unlock if available
[ -n "$wallet" ] && args+=(--unlock "$wallet")

# Add bootnodes if available
[ -n "$bootnodes" ] && args+=(--bootnodes "$bootnodes")

# Add ethstats
args+=(--ethstats "$netstats")

# XDCx data dir
args+=(--XDCx.datadir /work/xdcchain/XDCx)

# Issue #71: Add miner.etherbase if coinbase is set
[ -n "$ETHERBASE" ] && args+=(--miner.etherbase "$ETHERBASE")

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
