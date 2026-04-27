#!/bin/bash
export PATH="/run/xdc:/tmp:/var/tmp:$PATH"
#==============================================================================
# XDC Testnet (Apothem) Node Startup Script - Production Grade
# 
# This script is called by the official entry.sh after it creates the
# XDC binary symlink. It handles node initialization, configuration,
# and graceful shutdown for the XDC testnet.
#==============================================================================

# Strict error handling - exit on any error, undefined vars, pipe failures
set -euo pipefail

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
            echo "[INFO] Loaded bash config from $config_file"
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
            echo "[INFO] Loaded TOML config from $config_file"
            ;;
        json)
            # Simple JSON parser using jq if available
            if command -v jq &>/dev/null; then
                while IFS='=' read -r key value; do
                    export "$key=$value"
                done < <(jq -r 'to_entries | .[] | "\(.key)=\(.value)"' "$config_file")
                echo "[INFO] Loaded JSON config from $config_file"
            else
                echo "[WARN] jq not available, cannot parse JSON config"
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

#------------------------------------------------------------------------------
# Configuration via Environment Variables
# Config.toml is the single source of truth - these are fallback defaults
#------------------------------------------------------------------------------

if [[ "$CONFIG_LOADED" != "true" ]]; then
    echo "[WARN] No config file found, using hardcoded defaults"
fi

# Network configuration (defaults to testnet)
NETWORK="${NAME:-${NETWORK:-testnet}}"
INSTANCE_NAME="${INSTANCE_NAME:-${NAME:-xdc-testnet-node}}"

# Sync and storage configuration
SYNC_MODE="${SYNC_MODE:-full}"           # full or fast
GC_MODE="${GC_MODE:-archive}"            # full or archive
LOG_LEVEL="${LEVEL:-${LOG_LEVEL:-2}}"    # 0=silent, 1=error, 2=warn, 3=info, 4=debug, 5=detail

# RPC configuration (enabled by default)
ENABLE_RPC="${ENABLED:-${ENABLE_RPC:-true}}"
RPC_ADDR="${ADDR:-${RPC_ADDR:-0.0.0.0}}"
RPC_PORT="${PORT:-${RPC_PORT:-8545}}"
RPC_API="${API:-${RPC_API:-admin,eth,net,web3,XDPoS}}"
RPC_CORS_DOMAIN="${CORS_DOMAIN:-${RPC_CORS:-localhost,https://*.xdc.network,https://*.xinfin.org}}"
RPC_VHOSTS="${VHOSTS:-${RPC_VHOSTS:-*}}"

# WebSocket configuration
WS_ADDR="${WS_ADDR:-0.0.0.0}"
WS_PORT="${WS_PORT:-8546}"
WS_API="${WS_API:-eth,net,web3,XDPoS}"
WS_ORIGINS="${WS_ORIGINS:-*}"

# Network ports
PORT="${PORT:-30303}"
NAT="${NAT:-any}"

# Metrics and profiling
METRICS="${METRICS:-true}"
METRICS_ADDR="${METRICS_ADDR:-0.0.0.0}"
METRICS_PORT="${METRICS_PORT:-6060}"
PPROF="${PPROF:-true}"
PPROF_ADDR="${PPROF_ADDR:-0.0.0.0}"
PPROF_PORT="${PPROF_PORT:-6060}"

# Log rotation
MAX_LOG_SIZE="${MAX_LOG_SIZE:-1073741824}"  # 1GB in bytes

#------------------------------------------------------------------------------
# Safety Fallback: Ensure XDC binary exists
#------------------------------------------------------------------------------

# Create symlink if it doesn't exist (in case entry.sh wasn't used)
# The official image has binaries at /usr/bin/XDC-mainnet, /usr/bin/XDC-testnet, etc.
if [[ ! -f /usr/bin/XDC ]]; then
    echo "[INFO] Creating XDC binary symlink for network: ${NETWORK}"
    for dest in /run/xdc/XDC /tmp/XDC /var/tmp/XDC /usr/bin/XDC; do cp "/usr/bin/XDC-${NETWORK}" "$dest" 2>/dev/null && chmod +x "$dest" 2>/dev/null && break; done
fi

# Verify the binary exists and is executable
if [[ ! -x /usr/bin/XDC ]]; then
    echo "[ERROR] XDC binary not found or not executable at /usr/bin/XDC"
    echo "[ERROR] Please ensure the Docker image is correct and NETWORK is set properly"
    exit 1
fi

#------------------------------------------------------------------------------
# Graceful Shutdown Handler
#------------------------------------------------------------------------------

# Global variable to track shutdown state
SHUTDOWN_IN_PROGRESS=false

shutdown_handler() {
    local signal=$1
    echo ""
    echo "[INFO] Received signal ${signal}, initiating graceful shutdown..."
    SHUTDOWN_IN_PROGRESS=true
    
    # If we have a node process running, give it time to shut down gracefully
    if [[ -n "${XDC_PID:-}" ]] && kill -0 "${XDC_PID}" 2>/dev/null; then
        echo "[INFO] Stopping XDC node (PID: ${XDC_PID})..."
        kill -TERM "${XDC_PID}" 2>/dev/null || true
        
        # Wait up to 30 seconds for graceful shutdown
        local count=0
        while kill -0 "${XDC_PID}" 2>/dev/null && [[ $count -lt 30 ]]; do
            sleep 1
            ((count++))
            echo -n "."
        done
        
        if kill -0 "${XDC_PID}" 2>/dev/null; then
            echo ""
            echo "[WARN] Node did not stop gracefully, forcing shutdown..."
            kill -KILL "${XDC_PID}" 2>/dev/null || true
        else
            echo ""
            echo "[INFO] Node stopped gracefully"
        fi
    fi
    
    echo "[INFO] Shutdown complete"
    exit 0
}

# Set up signal handlers
trap 'shutdown_handler SIGTERM' SIGTERM
trap 'shutdown_handler SIGINT' SIGINT

#------------------------------------------------------------------------------
# Node Initialization
#------------------------------------------------------------------------------

initialize_node() {
    echo "[INFO] Initializing XDC testnet node..."
    echo "[INFO] Network: ${NETWORK}"
    echo "[INFO] Sync Mode: ${SYNC_MODE}"
    echo "[INFO] GC Mode: ${GC_MODE}"
    
    # Create data directory if it doesn't exist
    mkdir -p /work/xdcchain
    
    # Check if this is a fresh node that needs initialization
    if [[ ! -d /work/xdcchain/XDC/chaindata ]]; then
        echo "[INFO] Fresh node detected, creating new wallet and initializing genesis..."
        
        # Create new wallet
        local wallet
        wallet=$(XDC account new --password /work/.pwd --datadir /work/xdcchain | awk -F '[{}]' '{print $2}')
        
        if [[ -z "${wallet}" ]]; then
            echo "[ERROR] Failed to create wallet"
            exit 1
        fi
        
        echo "[INFO] Created wallet: ${wallet}"
        
        # Save coinbase address
        local coinbase_file="/work/xdcchain/coinbase.txt"
        echo "${wallet}" > "${coinbase_file}"
        echo "[INFO] Coinbase saved to ${coinbase_file}"
        
        # Initialize genesis block
        echo "[INFO] Initializing genesis block..."
        XDC init --datadir /work/xdcchain /work/genesis.json
        
        echo "[INFO] Node initialization complete"
    else
        # Existing node - retrieve wallet address
        local wallet
        wallet=$(XDC account list --datadir /work/xdcchain | head -n 1 | awk -F '[{}]' '{print $2}')
        echo "[INFO] Existing node detected, using wallet: ${wallet}"
    fi
}

#------------------------------------------------------------------------------
# Bootnodes Configuration
#------------------------------------------------------------------------------

load_bootnodes() {
    local bootnodes_file="/work/bootnodes.list"
    local bootnodes=""
    
    if [[ ! -f "${bootnodes_file}" ]]; then
        echo "[WARN] Bootnodes file not found at ${bootnodes_file}"
        return
    fi
    
    while IFS= read -r line || [[ -n "${line}" ]]; do
        # Skip empty lines and comments
        [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
        
        if [[ -z "${bootnodes}" ]]; then
            bootnodes="${line}"
        else
            bootnodes="${bootnodes},${line}"
        fi
    done < "${bootnodes_file}"
    
    echo "[INFO] Loaded bootnodes configuration"
    BOOTNODES="${bootnodes}"
}

#------------------------------------------------------------------------------
# Log Rotation Check
#------------------------------------------------------------------------------

# Find the most recent log file or create a new one
get_log_file() {
    local log_dir="/work/xdcchain"
    local log_prefix="xdc-"
    local latest_log=""
    local latest_time=0
    
    # Find the most recent log file
    for logfile in "${log_dir}/${log_prefix}"*.log; do
        [[ -f "${logfile}" ]] || continue
        local mtime
        mtime=$(stat -c %Y "${logfile}" 2>/dev/null || echo "0")
        if [[ ${mtime} -gt ${latest_time} ]]; then
            latest_time=${mtime}
            latest_log="${logfile}"
        fi
    done
    
    # Check if we need to rotate (file size exceeds MAX_LOG_SIZE)
    if [[ -n "${latest_log}" && -f "${latest_log}" ]]; then
        local filesize
        filesize=$(stat -c %s "${latest_log}" 2>/dev/null || echo "0")
        if [[ ${filesize} -ge ${MAX_LOG_SIZE} ]]; then
            echo "[INFO] Log file size (${filesize} bytes) exceeds maximum (${MAX_LOG_SIZE} bytes), rotating..."
            latest_log=""  # Force creation of new log file
        fi
    fi
    
    # Create new log file if needed
    if [[ -z "${latest_log}" ]]; then
        local timestamp
        timestamp=$(date +%Y%m%d-%H%M%S)
        latest_log="${log_dir}/${log_prefix}${timestamp}.log"
        echo "[INFO] Creating new log file: ${latest_log}"
    fi
    
    echo "${latest_log}"
}

#------------------------------------------------------------------------------
# Build Node Arguments
#------------------------------------------------------------------------------

build_node_args() {
    local wallet=$1
    local args=()
    
    # Get instance IP for ethstats (Apothem testnet stats server)
    local instance_ip
    instance_ip=$(curl -s --max-time 5 https://checkip.amazonaws.com 2>/dev/null || echo "unknown")
    local netstats="${INSTANCE_NAME}:${STATS_SECRET:-xdc_openscan_stats_2026}@${STATS_SERVER:-stats.xdcindia.com:443}"
    
    # Core node arguments - testnet uses networkid 51
    args+=(
        --ethstats "${netstats}"
        --bootnodes "${BOOTNODES}"
        --syncmode "${SYNC_MODE}"
        --gcmode "${GC_MODE}"
        --datadir /work/xdcchain
        --XDCx.datadir /work/xdcchain/XDCx
        --networkid 51
        --port "${PORT}"
        --nat "${NAT}"
        --unlock "${wallet}"
        --password /work/.pwd
        --mine
        --miner.gasprice "1"
        --miner.gaslimit "420000000"
        --verbosity "${LOG_LEVEL}"
    )
    
    # Add metrics arguments
    if [[ "${METRICS}" == "true" ]]; then
        args+=(
            --metrics
            --metrics.addr "${METRICS_ADDR}"
            --metrics.port "${METRICS_PORT}"
        )
    fi
    
    # Add pprof arguments
    if [[ "${PPROF}" == "true" ]]; then
        args+=(
            --pprof
            --pprof.addr "${PPROF_ADDR}"
            --pprof.port "${PPROF_PORT}"
        )
    fi
    
    # Add RPC/WebSocket arguments (enabled by default)
    if [[ "${ENABLE_RPC}" == "true" ]]; then
        args+=(
            --rpc
            --rpcaddr "${RPC_ADDR}"
            --rpcport "${RPC_PORT}"
            --rpcapi "${RPC_API}"
            --rpccorsdomain "${RPC_CORS_DOMAIN}"
            --rpcvhosts "${RPC_VHOSTS}"
            --store-reward
            --ws
            --wsaddr "${WS_ADDR}"
            --wsport "${WS_PORT}"
            --wsapi "${WS_API}"
            --wsorigins "${WS_ORIGINS}"
        )
    fi
    
    echo "${args[@]}"
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------

main() {
    echo "=============================================================================="
    echo "XDC Testnet (Apothem) Node Startup - $(date)"
    echo "=============================================================================="
    
    # Initialize node (creates wallet if needed)
    initialize_node
    
    # Get wallet address
    local wallet
    wallet=$(XDC account list --datadir /work/xdcchain | head -n 1 | awk -F '[{}]' '{print $2}')
    if [[ -z "${wallet}" ]]; then
        echo "[ERROR] Could not retrieve wallet address"
        exit 1
    fi
    echo "[INFO] Using wallet: ${wallet}"
    
    # Load bootnodes
    load_bootnodes
    
    # Get log file
    LOG_FILE=$(get_log_file)
    echo "[INFO] Logging to: ${LOG_FILE}"
    
    # Build node arguments
    local node_args
    node_args=$(build_node_args "${wallet}")
    
    echo "[INFO] Starting XDC testnet node with arguments:"
    echo "       ${node_args}"
    echo "=============================================================================="
    
    # Start the node in the background and capture PID
    XDC ${node_args} 2>&1 | tee -a "${LOG_FILE}" &
    XDC_PID=$!
    
    echo "[INFO] XDC testnet node started with PID: ${XDC_PID}"
    
    # Wait for the node process
    wait ${XDC_PID} || true
    
    # If we get here without shutdown being requested, the node crashed
    if [[ "${SHUTDOWN_IN_PROGRESS}" == "false" ]]; then
        echo ""
        echo "[ERROR] XDC node process exited unexpectedly!"
        exit 1
    fi
    
    exit 0
}

# Run main function
main "$@"
