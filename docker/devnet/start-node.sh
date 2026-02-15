#!/bin/bash
export PATH="/run/xdc:/tmp:/var/tmp:$PATH"
set -e

# XDC Devnet Node Startup Script
# Chain ID: 551

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
            # Simple TOML parser - extracts key = "value" lines
            while IFS= read -r line; do
                # Skip comments and empty lines
                [[ "$line" =~ ^[[:space:]]*# ]] && continue
                [[ -z "${line// /}" ]] && continue
                
                # Parse key = "value" or key = number
                if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
                    local key="${BASH_REMATCH[1]}"
                    local value="${BASH_REMATCH[2]}"
                    # Remove quotes if present
                    value="${value%\"}"
                    value="${value#\"}"
                    # Remove trailing comments
                    value="${value%%#*}"
                    value="${value% }"
                    # Export as env var (uppercase)
                    export "${key^^}=$value"
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

# Ensure XDC binary is available
if ! command -v XDC &>/dev/null; then
    for bin in XDC XDC-devnet XDC-testnet XDC-mainnet; do
        if command -v "$bin" &>/dev/null; then
            for dest in /run/xdc/XDC /tmp/XDC /var/tmp/XDC /usr/bin/XDC; do cp "$(which "$bin")" "$dest" 2>/dev/null && chmod +x "$dest" 2>/dev/null && break; done
            echo "Resolved $bin → XDC"
            break
        fi
    done
fi
command -v XDC &>/dev/null || { echo "FATAL: No XDC binary found!"; exit 1; }

echo "XDC Devnet Node"
echo "Chain ID: 551"

# Defaults - Only used if config.toml is missing
# Config.toml is the single source of truth
if [[ "$CONFIG_LOADED" != "true" ]]; then
    echo "WARN: No config file found, using hardcoded defaults"
    export SYNC_MODE="${SYNC_MODE:-full}"
    export GC_MODE="${GC_MODE:-full}"
    export LEVEL="${LEVEL:-3}"
    export INSTANCE_NAME="${INSTANCE_NAME:-xdc-devnet-node}"
    export ENABLED="${ENABLED:-true}"
    export ADDR="${ADDR:-0.0.0.0}"
    export PORT="${PORT:-8545}"
    export API="${API:-admin,eth,net,web3,XDPoS}"
    export WS_ADDR="${WS_ADDR:-0.0.0.0}"
    export WS_PORT="${WS_PORT:-8546}"
else
    # Use values from config.toml (loaded as env vars)
    export SYNC_MODE="${SYNC_MODE:-full}"
    export GC_MODE="${GC_MODE:-full}"
    export LOG_LEVEL="${LEVEL:-3}"
    export INSTANCE_NAME="${INSTANCE_NAME:-xdc-devnet-node}"
    export ENABLE_RPC="${ENABLED:-true}"
    export RPC_ADDR="${ADDR:-0.0.0.0}"
    export RPC_PORT="${PORT:-8545}"
    export RPC_API="${API:-admin,eth,net,web3,XDPoS}"
fi

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
    --ipcpath /tmp/XDC.ipc
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
