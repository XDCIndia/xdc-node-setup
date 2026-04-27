#!/bin/bash
#===============================================================================
# XDC Node Start Script with Genesis Guard Integration
# Security Fix (#492 #493 #508): Secure RPC defaults + error handling
# Genesis Guard: Validates chainId on startup, wipes chaindata on mismatch
#===============================================================================
set -euo pipefail
trap 'echo "ERROR at line $LINENO"' ERR

export PATH="/run/xdc:/tmp:/var/tmp:$PATH"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Source common utilities
# shellcheck source=/dev/null
source "$(dirname "$0")/../scripts/lib/common.sh" 2>/dev/null || {
    log_warn "common.sh not found, using built-in defaults"
    load_config_standard() { return 1; }
    ensure_xdc_binary() { command -v XDC >/dev/null 2>&1; }
    detect_rpc_style() { echo "legacy"; }
    load_bootnodes() { grep -v "^#" "${1:-/work/bootnodes.list}" 2>/dev/null | grep -v "^$" | tr "\n" "," | sed 's/,$//'; }
}

#===============================================================================
# GENESIS GUARD - Validates genesis and wipes chaindata on mismatch
#===============================================================================
genesis_guard() {
    local datadir="${1:-/work/xdcchain}"
    local genesis_file="${2:-/work/genesis.json}"
    local network="${NETWORK:-mainnet}"
    
    log_info "Genesis Guard: Validating genesis configuration..."
    
    # Expected chain IDs
    local expected_chain_id
    case "$network" in
        mainnet|xdc) expected_chain_id=50 ;;
        apothem|testnet) expected_chain_id=51 ;;
        *) 
            log_warn "Unknown network '$network', skipping genesis guard"
            return 0
            ;;
    esac
    
    # Check if genesis file exists
    if [[ ! -f "$genesis_file" ]]; then
        log_error "Genesis file not found: $genesis_file"
        log_error "Please ensure genesis.json is mounted at /work/genesis.json"
        exit 1
    fi
    
    # Extract chainId from genesis file
    local genesis_chain_id
    if command -v python3 >/dev/null 2>&1; then
        genesis_chain_id=$(python3 -c "
import json
with open('$genesis_file') as f:
    g = json.load(f)
    print(g.get('config', {}).get('chainId', g.get('chainId', '')))
" 2>/dev/null || echo "")
    elif command -v jq >/dev/null 2>&1; then
        genesis_chain_id=$(jq -r '.config.chainId // .chainId // ""' "$genesis_file" 2>/dev/null || echo "")
    else
        # Fallback: grep for chainId
        genesis_chain_id=$(grep -oP '"chainId"\s*:\s*\K\d+' "$genesis_file" 2>/dev/null | head -1 || echo "")
    fi
    
    if [[ -z "$genesis_chain_id" ]]; then
        log_error "Could not extract chainId from genesis file"
        exit 1
    fi
    
    log_info "Genesis chainId: $genesis_chain_id, Expected: $expected_chain_id"
    
    # Check for mismatch
    if [[ "$genesis_chain_id" != "$expected_chain_id" ]]; then
        log_error "GENESIS MISMATCH DETECTED!"
        log_error "Genesis file chainId ($genesis_chain_id) does not match expected ($expected_chain_id)"
        log_error "This genesis file is NOT for $network"
        exit 1
    fi
    
    # Check existing chaindata for chain ID mismatch
    local chaindata_dir="$datadir/XDC/chaindata"
    local network_marker="$datadir/.network"
    
    if [[ -f "$network_marker" ]]; then
        local stored_network
        stored_network=$(cat "$network_marker" 2>/dev/null || echo "")
        
        if [[ -n "$stored_network" ]] && [[ "$stored_network" != "$network" ]]; then
            log_warn "Network mismatch detected!"
            log_warn "Stored network: $stored_network, Current: $network"
            
            if [[ "${GENESIS_GUARD_AUTO_WIPE:-false}" == "true" ]]; then
                log_warn "GENESIS_GUARD_AUTO_WIPE enabled - wiping chaindata..."
                rm -rf "$chaindata_dir" "$datadir/XDC/nodes" "$datadir/XDC/lightchaindata" 2>/dev/null || true
                rm -f "$network_marker"
                log_success "Chaindata wiped for network switch"
            else
                log_error "Set GENESIS_GUARD_AUTO_WIPE=true to auto-wipe chaindata"
                log_error "Or manually delete: $chaindata_dir"
                exit 1
            fi
        fi
    fi
    
    # Store current network
    echo "$network" > "$network_marker"
    
    log_success "Genesis Guard: Validation passed (Chain ID: $genesis_chain_id)"
}

#===============================================================================
# SkyOne Auto-Registration
#===============================================================================
skyone_register() {
    local node_id="${SKYNET_NODE_ID:-}"
    local skynet_endpoint="${SKYNET_ENDPOINT:-https://skynet.xdcindia.com}"
    local rpc_port="${RPC_PORT:-8545}"
    
    if [[ "${SKYNET_ENABLED:-false}" != "true" ]]; then
        log_info "SkyNet registration disabled"
        return 0
    fi
    
    # Generate node ID if not set
    if [[ -z "$node_id" ]]; then
        local hostname_part="${HOSTNAME:-$(hostname)}"
        local client_name="${CLIENT_NAME:-geth}"
        node_id="${client_name}-${hostname_part}-$(date +%s | tail -c 5)"
        log_info "Generated SkyNet node ID: $node_id"
    fi
    
    # Store node ID
    echo "$node_id" > /work/xdcchain/.skyone_node_id
    
    # Background registration (non-blocking)
    (
        sleep 30  # Wait for node to start
        local retries=5
        while [[ $retries -gt 0 ]]; do
            local block_number
            block_number=$(curl -s -X POST "http://localhost:$rpc_port" \
                -H "Content-Type: application/json" \
                -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | \
                grep -oP '"result"\s*:\s*"0x\K[0-9a-fA-F]+' || echo "")
            
            if [[ -n "$block_number" ]]; then
                log_success "SkyOne: Node syncing at block 0x$block_number"
                # Heartbeat registration would go here
                break
            fi
            
            log_warn "SkyOne: Waiting for node RPC to be ready..."
            sleep 10
            ((retries--))
        done
    ) &
    
    log_info "SkyOne registration initiated (node_id: $node_id)"
}

#===============================================================================
# Load Config File
#===============================================================================
if ! load_config_standard "${XDC_CONFIG:-}"; then
    log_warn "No config file found, using hardcoded defaults"
fi

# Ensure XDC binary is available
ensure_xdc_binary || {
    log_error "XDC binary not found in PATH"
    exit 1
}

# Detect XDC client version
XDC_VERSION=$(XDC version 2>/dev/null | head -1 || echo "unknown")
log_info "XDC version: $XDC_VERSION"

RPC_STYLE=$(detect_rpc_style)
log_info "RPC flag style: $RPC_STYLE"

#===============================================================================
# Configuration Defaults
# Security Fix (#492 #493): Secure RPC defaults — localhost only
#===============================================================================
export NETWORK="${NETWORK:-mainnet}"
export SYNC_MODE="${SYNC_MODE:-full}"
export GC_MODE="${GC_MODE:-full}"
export LOG_LEVEL="${LEVEL:-2}"
export INSTANCE_NAME="${INSTANCE_NAME:-XDC_Node}"
export ENABLE_RPC="${ENABLED:-true}"
export RPC_ADDR="${RPC_ADDR:-${ADDR:-127.0.0.1}}"
export RPC_PORT="${HTTP_PORT:-${RPC_PORT:-8545}}"
export RPC_API="${API:-admin,eth,net,web3,XDPoS}"
export RPC_ALLOW_ORIGINS="${RPC_ALLOW_ORIGINS:-${CORS_DOMAIN:-${RPC_CORS:-localhost}}}"
export RPC_CORS_DOMAIN="$RPC_ALLOW_ORIGINS"
export RPC_VHOSTS="${RPC_VHOSTS:-${VHOSTS:-localhost}}"
export WS_ADDR="${WS_ADDR:-127.0.0.1}"
export WS_PORT="${WS_PORT:-8546}"
export WS_API="${WS_API:-eth,net,web3,XDPoS}"
export WS_ORIGINS="${WS_ORIGINS:-localhost}"

log_info "Config: network=$NETWORK sync=$SYNC_MODE gc=$GC_MODE rpc=$ENABLE_RPC"

#===============================================================================
# Genesis Guard Validation
#===============================================================================
DATADIR="/work/xdcchain"
GENESIS_FILE="/work/genesis.json"

# Run genesis guard
genesis_guard "$DATADIR" "$GENESIS_FILE"

#===============================================================================
# Initialize Wallet and Genesis
#===============================================================================
if [ ! -d "$DATADIR/keystore" ] || [ -z "$(ls $DATADIR/keystore/ 2>/dev/null)" ]; then
    log_info "First boot detected - creating new node account..."
    echo "" | XDC account new --datadir "$DATADIR" --password /dev/stdin 2>/dev/null
    ACCOUNT=$(XDC account list --datadir "$DATADIR" 2>/dev/null | head -1 | grep -oP '0x[0-9a-fA-F]{40}' || echo "")
    if [ -n "$ACCOUNT" ]; then
        echo "$ACCOUNT" > "$DATADIR/.node-identity"
        log_success "Created account: $ACCOUNT"
    fi
fi

if [ ! -d "$DATADIR/XDC/chaindata" ]; then
    wallet=$(XDC account new --password /work/.pwd --datadir "$DATADIR" 2>/dev/null | awk -F '[{}]' '{print $2}' || echo "")
    log_info "Initializing Genesis Block"
    echo "$wallet" > "$DATADIR/coinbase.txt"
    XDC init --datadir "$DATADIR" "$GENESIS_FILE"
else
    wallet=$(XDC account list --datadir "$DATADIR" 2>/dev/null | head -n 1 | awk -F '[{}]' '{print $2}' || echo "")
fi

log_info "Wallet: $wallet"

# Read etherbase
ETHERBASE=""
if [ -f "$DATADIR/.node-identity" ]; then
    ETHERBASE=$(cat "$DATADIR/.node-identity")
    log_info "Using coinbase for etherbase: $ETHERBASE"
fi

#===============================================================================
# Load Bootnodes
#===============================================================================
bootnodes=$(load_bootnodes /work/bootnodes.list)

# Network ID
NETWORK_ID=50
case "$NETWORK" in
    mainnet|xdc) NETWORK_ID=50 ;;
    apothem|testnet) NETWORK_ID=51 ;;
esac

#===============================================================================
# SkyOne Registration
#===============================================================================
skyone_register

#===============================================================================
# Build Command Args
#===============================================================================
LOG_FILE="/work/xdcchain/xdc-$(date +%Y%m%d-%H%M%S).log"

args=(
    --datadir "$DATADIR"
    --networkid "$NETWORK_ID"
    --port 30303
    --syncmode "$SYNC_MODE"
    --gcmode "$GC_MODE"
    --verbosity "$LOG_LEVEL"
    --password /work/.pwd
    --mine
    --miner.gasprice 1
    --miner.gaslimit 420000000
    --ipcpath /tmp/XDC.ipc
    --nat=any
)

[ -n "$wallet" ] && args+=(--unlock "$wallet")
[ -n "$bootnodes" ] && args+=(--bootnodes "$bootnodes")
[ -n "$ETHERBASE" ] && args+=(--miner.etherbase "$ETHERBASE")

# ethstats
netstats="${INSTANCE_NAME}:${STATS_SECRET:-xdc_openscan_stats_2026}@${STATS_SERVER:-stats.xdcindia.com:443}"
[[ "$NETWORK" == "apothem" ]] && netstats="${INSTANCE_NAME}:${STATS_SECRET:-xdc_openscan_stats_2026}@${STATS_SERVER:-stats.xdcindia.com:443}"
args+=(--ethstats "$netstats")
args+=(--XDCx.datadir /work/xdcchain/XDCx)

#===============================================================================
# RPC/HTTP Configuration
#===============================================================================
if echo "$ENABLE_RPC" | grep -iq "true"; then
    if [ "$RPC_STYLE" = "new" ]; then
        args+=(
            --http --http.addr "$RPC_ADDR" --http.port "$RPC_PORT"
            --http.api "$RPC_API" --http.corsdomain "$RPC_CORS_DOMAIN" --http.vhosts "$RPC_VHOSTS"
            --ws --ws.addr "$WS_ADDR" --ws.port "$WS_PORT" --ws.api "$WS_API" --ws.origins "$WS_ORIGINS"
        )
    else
        args+=(
            --rpc --rpcaddr "$RPC_ADDR" --rpcport "$RPC_PORT"
            --rpcapi "$RPC_API" --rpccorsdomain "$RPC_CORS_DOMAIN" --rpcvhosts "$RPC_VHOSTS"
            --store-reward
            --ws --wsaddr "$WS_ADDR" --wsport "$WS_PORT" --wsapi "$WS_API" --wsorigins "$WS_ORIGINS"
        )
    fi
fi

args+=("$@")

log_info "Starting XDC node..."
log_info "Args: ${args[*]}"
exec XDC "${args[@]}" 2>&1 | tee -a "$LOG_FILE"
