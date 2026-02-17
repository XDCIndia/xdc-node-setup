#!/bin/bash
set -e

#==============================================================================
# XDC Nethermind Start Script
# Handles initialization and startup of Nethermind XDC client
#==============================================================================

: "${NETWORK:=mainnet}"
: "${SYNC_MODE:=full}"
: "${RPC_PORT:=8545}"
: "${P2P_PORT:=30303}"
: "${INSTANCE_NAME:=Nethermind_XDC_Node}"

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
if [[ -f /nethermind/bootnodes.list ]]; then
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ -z "$BOOTNODES" ]]; then
            BOOTNODES="$line"
        else
            BOOTNODES="$BOOTNODES,$line"
        fi
    done < /nethermind/bootnodes.list
    echo "Loaded bootnodes from bootnodes.list"
fi

# Build Nethermind arguments
NETHERMIND_ARGS=(
    --datadir /nethermind/data
    --config xdc
    --JsonRpc.Enabled true
    --JsonRpc.Host 0.0.0.0
    --JsonRpc.Port "${RPC_PORT}"
    --JsonRpc.EnabledModules "${NETHERMIND_JSONRPCCONFIG_ENABLEDMODULES:-eth,net,web3,admin,debug}"
    --Network.P2PPort "${P2P_PORT}"
    --Network.DiscoveryPort "${P2P_PORT}"
    --Network.ExternalIp "${EXTERNAL_IP:-}"
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

# Set sync mode
if [[ "$SYNC_MODE" == "snap" ]]; then
    NETHERMIND_ARGS+=(--Sync.FastSync true)
else
    NETHERMIND_ARGS+=(--Sync.FastSync false)
fi

echo "Starting Nethermind..."
echo "Command: /nethermind/nethermind ${NETHERMIND_ARGS[*]}"
echo ""

# Execute Nethermind (binary name is lowercase 'nethermind' in newer builds)
if [[ -x /nethermind/nethermind ]]; then
    exec /nethermind/nethermind "${NETHERMIND_ARGS[@]}" 2>&1 | tee -a /nethermind/logs/nethermind.log
elif [[ -x /nethermind/Nethermind.Runner ]]; then
    exec /nethermind/Nethermind.Runner "${NETHERMIND_ARGS[@]}" 2>&1 | tee -a /nethermind/logs/nethermind.log
else
    echo "ERROR: No Nethermind binary found!"
    ls -la /nethermind/
    exit 1
fi
