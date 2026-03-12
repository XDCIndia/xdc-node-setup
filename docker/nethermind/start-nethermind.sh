#!/bin/bash
# Security Fix (#492 #493 #508): Secure RPC defaults + error handling
set -euo pipefail
trap 'echo "ERROR at line $LINENO"' ERR

#==============================================================================
# XDC Nethermind Start Script - Production Hardened
# Handles initialization and startup of Nethermind XDC client
# Security: RPC binds to 127.0.0.1 by default — set RPC_ADDR=0.0.0.0 for external access
# Issue #234: Added connection resilience, peer monitoring, auto-restart
#==============================================================================

# Security Fix (#492 #493): Secure defaults — localhost only
: "${NETWORK:=mainnet}"
: "${SYNC_MODE:=full}"
: "${RPC_PORT:=8545}"
: "${RPC_ADDR:=127.0.0.1}"  # Security: localhost only by default
: "${RPC_ALLOW_ORIGINS:=localhost}"  # Security: no CORS wildcard
: "${RPC_VHOSTS:=localhost}"  # Security: localhost vhosts only
: "${P2P_PORT:=30303}"
: "${INSTANCE_NAME:=Nethermind_XDC_Node}"

# Bug #517: Support for extra CLI arguments via environment variable
# Usage: NETHERMIND_EXTRA_ARGS="--Network.P2PPort=30305 --JsonRpc.Port=8546"
: "${NETHERMIND_EXTRA_ARGS:=}"

# Bug #515: Trusted peers for connecting to GP5 nodes (prevent 'Sleeping: All')
# Default XDC mainnet GP5 nodes - override with TRUSTED_PEERS env var
: "${TRUSTED_PEERS:=enode://e1a69a7d766576e694adc3fc78d801a8a66926cbe8f4fe95b85f3b481444700a5d1b6d440b2715b5bb7cf4824df6a6702740afc8c52b20c72bc8c16f1ccde1f3@95.217.112.125:30303,enode://874589626a2b4fd7c57202533315885815eba51dbc434db88bbbebcec9b22cf2a01eafad2fd61651306fe85321669a30b3f41112eca230137ded24b86e064ba8@135.181.117.109:30303,enode://ccdef92053c8b9622180d02a63edffb3e143e7627737ea812b930eacea6c51f0c93a5da3397f59408c3d3d1a9a381f7e0b07440eae47314685b649a03408cfdd@167.235.13.113:30303}"

# Network configuration
case "$NETWORK" in
    mainnet)
        CHAIN_ID=50
        NETWORK_NAME="XDC Mainnet"
        ;;
    testnet|apothem)
        CHAIN_ID=51
        NETWORK_NAME="XDC Apothem Testnet"
        ;;
    devnet)
        CHAIN_ID=551
        NETWORK_NAME="XDC Devnet"
        ;;
    *)
        CHAIN_ID=50
        NETWORK_NAME="XDC Mainnet"
        ;;
esac

echo "=== XDC Nethermind Node ==="
echo "Network: $NETWORK_NAME (Chain ID: $CHAIN_ID)"
echo "RPC Port: $RPC_PORT"
echo "P2P Port: $P2P_PORT"
echo "Instance: $INSTANCE_NAME"
echo ""

# Issue #71: Generate deterministic identity on first boot
DATADIR="/nethermind/data"
if [ ! -f "$DATADIR/.node-identity" ]; then
  echo "[SkyNet] First boot detected - generating node identity..."
  # Generate a deterministic private key using hostname and date
  # This ensures the same node gets the same identity on restart
  IDENTITY_SEED="${HOSTNAME:-nethermind}-$(date +%Y%m)"
  PRIVKEY=$(echo -n "$IDENTITY_SEED" | sha256sum | cut -d' ' -f1)
  echo "$PRIVKEY" > "$DATADIR/.node-privkey"
  echo "[SkyNet] Generated identity seed (coinbase will be read from RPC after start)"
fi

# Check if chainspec exists
if [[ ! -f /nethermind/chainspec/xdc.json ]]; then
    echo "ERROR: Chainspec file not found at /nethermind/chainspec/xdc.json"
    exit 1
fi

# Check if config exists
if [[ ! -f /nethermind/configs/xdc.json ]]; then
    echo "WARNING: Config file not found at /nethermind/configs/xdc.json, using defaults"
fi

# Parse bootnodes from bootnodes.list
BOOTNODES=""
STATIC_PEERS=""
if [[ -f /nethermind/bootnodes.list ]]; then
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ -z "$BOOTNODES" ]]; then
            BOOTNODES="$line"
        else
            BOOTNODES="$BOOTNODES,$line"
        fi
        # Add all bootnodes as static peers too for redundancy
        if [[ -z "$STATIC_PEERS" ]]; then
            STATIC_PEERS="$line"
        else
            STATIC_PEERS="$STATIC_PEERS,$line"
        fi
    done < /nethermind/bootnodes.list
    echo "Loaded bootnodes from bootnodes.list"
fi

# Build Nethermind arguments
NETHERMIND_ARGS=(
    --datadir /nethermind/data
    --config xdc
    --JsonRpc.Enabled true
    --JsonRpc.Host "${RPC_ADDR}"
    --JsonRpc.Port "${RPC_PORT}"
    --JsonRpc.EnabledModules "${NETHERMIND_JSONRPCCONFIG_ENABLEDMODULES:-eth,net,web3,admin,debug,trace,txpool}"
    --JsonRpc.CorsOrigins "${RPC_ALLOW_ORIGINS}"
    --Network.P2PPort "${P2P_PORT}"
    --Network.DiscoveryPort "${P2P_PORT}"
    --Network.ExternalIp "${EXTERNAL_IP:-}"
    --Network.MaxActivePeers 50
    --EthStats.Enabled true
    --EthStats.Name "${INSTANCE_NAME}"
    --EthStats.Secret "xdc-nethermind-stats"
    --EthStats.Server "wss://stats.xinfin.network/api"
    --Metrics.Enabled true
    --Metrics.ExposePort 6060
)

# Add bootnodes if available
if [[ -n "$BOOTNODES" ]]; then
    NETHERMIND_ARGS+=(--Discovery.Bootnodes "$BOOTNODES")
fi

# Add static peers for connection resilience
if [[ -n "$STATIC_PEERS" ]]; then
    NETHERMIND_ARGS+=(--Network.StaticPeers "$STATIC_PEERS")
fi

# Set sync mode with XDC-specific optimizations
if [[ "$SYNC_MODE" == "snap" ]]; then
    NETHERMIND_ARGS+=(--Sync.FastSync true)
    NETHERMIND_ARGS+=(--Sync.SnapSync true)
    NETHERMIND_ARGS+=(--Sync.UseGethLimitsInFastBlocks false)
else
    NETHERMIND_ARGS+=(--Sync.FastSync false)
fi

# Bug #517: Append extra CLI arguments from NETHERMIND_EXTRA_ARGS env var
if [ -n "$NETHERMIND_EXTRA_ARGS" ]; then
    read -ra EXTRA <<< "$NETHERMIND_EXTRA_ARGS"
    NETHERMIND_ARGS+=("${EXTRA[@]}")
    echo "Added extra arguments: $NETHERMIND_EXTRA_ARGS"
fi

# Bug #515: Add trusted peers to ensure connections to GP5 nodes
if [ -n "$TRUSTED_PEERS" ]; then
    NETHERMIND_ARGS+=(--Network.TrustedPeers "$TRUSTED_PEERS")
    echo "Added trusted peers for GP5 connectivity"
fi

echo "Starting Nethermind..."
echo "Command: /nethermind/nethermind ${NETHERMIND_ARGS[*]}"
echo ""

# =============================================================================
# Issue #234: Connection Resilience Monitoring
# =============================================================================

# Function to check peer count via RPC
check_peers() {
    local response
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
        http://localhost:${RPC_PORT} 2>/dev/null || echo "")
    
    if [[ -n "$response" ]]; then
        # Extract peer count from hex response
        local peer_hex=$(echo "$response" | grep -o '"result":"0x[^"]*"' | cut -d'"' -f4)
        if [[ -n "$peer_hex" ]]; then
            echo $((16#${peer_hex#0x}))
        else
            echo "0"
        fi
    else
        echo "-1"  # Node not responding
    fi
}

# Function to check current block
check_block() {
    local response
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:${RPC_PORT} 2>/dev/null || echo "")
    
    if [[ -n "$response" ]]; then
        local block_hex=$(echo "$response" | grep -o '"result":"0x[^"]*"' | cut -d'"' -f4)
        if [[ -n "$block_hex" ]]; then
            echo $((16#${block_hex#0x}))
        else
            echo "0"
        fi
    else
        echo "-1"
    fi
}

# Function to log peer status
log_peer_status() {
    local peers=$1
    local block=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] Nethermind Status - Peers: $peers, Block: $block"
}

# Background monitoring function
monitor_nethermind() {
    local start_time=$(date +%s)
    local last_block=0
    local last_block_time=$start_time
    local peer_retry_count=0
    local max_peer_retries=3
    
    echo "[Monitor] Starting Nethermind connection resilience monitor..."
    
    # Wait for node to start responding
    sleep 30
    
    while true; do
        sleep 60
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local peers=$(check_peers)
        local current_block=$(check_block)
        
        # Log status every 60 seconds
        log_peer_status "$peers" "$current_block"
        
        # Check for zero peers after 5 minutes
        if [[ "$elapsed" -gt 300 && "$peers" == "0" ]]; then
            peer_retry_count=$((peer_retry_count + 1))
            echo "[Monitor] WARNING: No peers connected after ${elapsed}s (retry $peer_retry_count/$max_peer_retries)"
            
            if [[ "$peer_retry_count" -ge "$max_peer_retries" ]]; then
                echo "[Monitor] CRITICAL: Peer connection retry limit reached. Triggering restart..."
                # Send signal to restart the container
                kill -TERM 1
                exit 1
            fi
        elif [[ "$peers" -gt 0 ]]; then
            peer_retry_count=0
        fi
        
        # Check for stuck block (same block for >30 minutes)
        if [[ "$current_block" -gt 0 && "$current_block" == "$last_block" ]]; then
            local block_stuck_time=$((current_time - last_block_time))
            if [[ "$block_stuck_time" -gt 1800 ]]; then
                echo "[Monitor] CRITICAL: Block stuck at $current_block for ${block_stuck_time}s. Triggering restart..."
                kill -TERM 1
                exit 1
            elif [[ "$block_stuck_time" -gt 900 ]]; then
                echo "[Monitor] WARNING: Block stuck at $current_block for ${block_stuck_time}s"
            fi
        else
            last_block=$current_block
            last_block_time=$current_time
        fi
    done
}

# Start monitoring in background
monitor_nethermind &
MONITOR_PID=$!

# Function to cleanup monitor on exit
cleanup() {
    echo "[Monitor] Shutting down monitor process..."
    kill $MONITOR_PID 2>/dev/null || true
}
trap cleanup EXIT

# =============================================================================
# Execute Nethermind (binary name is lowercase 'nethermind' in newer builds)
# =============================================================================
if [[ -x /nethermind/nethermind ]]; then
    exec /nethermind/nethermind "${NETHERMIND_ARGS[@]}" 2>&1 | tee -a /nethermind/logs/nethermind.log
elif [[ -x /nethermind/Nethermind.Runner ]]; then
    exec /nethermind/Nethermind.Runner "${NETHERMIND_ARGS[@]}" 2>&1 | tee -a /nethermind/logs/nethermind.log
else
    echo "ERROR: No Nethermind binary found!"
    ls -la /nethermind/
    exit 1
fi
