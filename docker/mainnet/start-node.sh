#!/bin/bash
export PATH="/run/xdc:/tmp:/var/tmp:$PATH"
set -e

#==============================================================================
# Load Config File (if exists) - env vars override config file
# Supports: .conf (bash), .toml (TOML), .json (JSON)
#
# NOTE: XDC binary (v2.6.8) does NOT support --config flag natively.
# We parse config.toml into env vars, then build CLI args from those vars.
# This makes config.toml the single source of truth for configuration.
#==============================================================================
load_config() {
    local config_file="$1"
    local ext="${config_file##*.}"
    
    case "$ext" in
        conf|sh)
            # shellcheck source=/dev/null
            source "$config_file"
            echo "Loaded bash config from $config_file"
            ;;
        toml)
            # Section-aware TOML parser - prefixes keys with section name
            local section=""
            while IFS= read -r line; do
                # Skip comments and empty lines
                [[ "$line" =~ ^[[:space:]]*# ]] && continue
                [[ -z "${line// /}" ]] && continue
                
                # Track section headers like [Node.HTTP]
                if [[ "$line" =~ ^[[:space:]]*\[([^]]+)\] ]]; then
                    section="${BASH_REMATCH[1]}"
                    # Normalize: Node.HTTP → HTTP, Node.WS → WS, Node.P2P → P2P
                    section="${section##*.}"
                    continue
                fi
                
                # Parse key = "value" or key = number (skip arrays)
                if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
                    local key="${BASH_REMATCH[1]}"
                    local value="${BASH_REMATCH[2]}"
                    # Skip array values
                    [[ "$value" == "["* ]] && continue
                    # Remove quotes if present
                    value="${value%\"}"
                    value="${value#\"}"
                    # Remove trailing comments
                    value="${value%%#*}"
                    value="${value% }"
                    # Export both section-prefixed and plain key
                    local ukey="${key^^}"
                    local usection="${section^^}"
                    [[ -n "$section" ]] && export "${usection}_${ukey}=$value"
                    export "${ukey}=$value"
                fi
            done < "$config_file"
            echo "Loaded TOML config from $config_file"
            ;;
        json)
            # Simple JSON parser using jq if available
            if command -v jq &>/dev/null; then
                while IFS='=' read -r key value; do
                    export "$key=$value"
                done < <(jq -r 'to_entries | .[] | "\(.key)=\(.value)"' "$config_file")
                echo "Loaded JSON config from $config_file"
            else
                echo "WARN: jq not available, cannot parse JSON config"
            fi
            ;;
    esac
}

# Try config files in order of preference
CONFIG_LOADED=false
for CONFIG_FILE in "${XDC_CONFIG}" "/etc/xdc-node/config.toml" "/etc/xdc-node/xdc.conf" "/work/config.toml" "/work/xdc.conf"; do
    if [[ -f "$CONFIG_FILE" ]]; then
        load_config "$CONFIG_FILE"
        CONFIG_LOADED=true
        break
    fi
done

# Ensure XDC binary is available (some images use XDC-mainnet instead of XDC)
if ! command -v XDC &>/dev/null; then
    for bin in XDC-mainnet XDC-testnet XDC-devnet XDC-local; do
        if command -v "$bin" &>/dev/null; then
            for dest in /run/xdc/XDC /tmp/XDC /var/tmp/XDC /usr/bin/XDC; do cp "$(which "$bin")" "$dest" 2>/dev/null && chmod +x "$dest" 2>/dev/null && break; done
            echo "Copied $bin → $dest"
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
# Defaults - Only used if config.toml is missing
# Config.toml is the single source of truth
# ============================================================
if [[ "$CONFIG_LOADED" != "true" ]]; then
    echo "WARN: No config file found, using hardcoded defaults"
    export SYNC_MODE="${SYNC_MODE:-full}"
    export GC_MODE="${GC_MODE:-full}"
    export LEVEL="${LEVEL:-2}"
    export INSTANCE_NAME="${INSTANCE_NAME:-XDC_Node}"
    export ENABLED="${ENABLED:-true}"
    export ADDR="${ADDR:-0.0.0.0}"
    export PORT="${PORT:-8545}"
    export API="${API:-admin,eth,net,web3,XDPoS}"
    export CORS_DOMAIN="${CORS_DOMAIN:-*}"
    export VHOSTS="${VHOSTS:-*}"
    export WS_ADDR="${WS_ADDR:-0.0.0.0}"
    export WS_PORT="${WS_PORT:-8546}"
    export WS_API="${WS_API:-eth,net,web3,XDPoS}"
    export WS_ORIGINS="${WS_ORIGINS:-*}"
else
    # Use values from config.toml (loaded as env vars)
    # Map TOML section.key format to flat env vars for backward compat
    export SYNC_MODE="${SYNC_MODE:-full}"
    export GC_MODE="${GC_MODE:-full}"
    export LOG_LEVEL="${LEVEL:-2}"
    export INSTANCE_NAME="${INSTANCE_NAME:-XDC_Node}"
    export ENABLE_RPC="${ENABLED:-true}"
    export RPC_ADDR="${ADDR:-0.0.0.0}"
    # Use section-prefixed HTTP_PORT from [Node.HTTP], not [Metrics] Port
    export RPC_PORT="${HTTP_PORT:-${RPC_PORT:-8545}}"
    export RPC_API="${API:-admin,eth,net,web3,XDPoS}"
    export RPC_CORS_DOMAIN="${CORS_DOMAIN:-*}"
    export RPC_VHOSTS="${VHOSTS:-*}"
fi

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
