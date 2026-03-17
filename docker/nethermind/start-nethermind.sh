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

# Issue #557: Ensure KZG trusted setup file exists
# Nethermind requires kzg_trusted_setup.txt for EIP-4844 (blob transactions)
KZG_FILE="/nethermind/kzg_trusted_setup.txt"
if [[ ! -f "$KZG_FILE" ]]; then
    echo "⚠ Warning: kzg_trusted_setup.txt not found at $KZG_FILE"
    echo "Attempting to copy from embedded resources..."
    
    # Try to copy from Nethermind binary resources
    if [[ -f "/nethermind/Data/kzg_trusted_setup.txt" ]]; then
        cp "/nethermind/Data/kzg_trusted_setup.txt" "$KZG_FILE"
        echo "✓ Copied KZG setup from /nethermind/Data/"
    elif [[ -f "/nethermind/data/kzg_trusted_setup.txt" ]]; then
        cp "/nethermind/data/kzg_trusted_setup.txt" "$KZG_FILE"
        echo "✓ Copied KZG setup from /nethermind/data/"
    else
        # Download from official Ethereum KZG ceremony
        echo "Downloading KZG trusted setup from Ethereum Foundation..."
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL -o "$KZG_FILE" \
                "https://raw.githubusercontent.com/ethereum/c-kzg-4844/main/src/trusted_setup.txt" 2>/dev/null || \
            curl -fsSL -o "$KZG_FILE" \
                "https://github.com/ethereum/consensus-specs/raw/dev/presets/mainnet/trusted_setups/trusted_setup.txt" 2>/dev/null || \
            echo "ERROR: Failed to download KZG trusted setup"
        elif command -v wget >/dev/null 2>&1; then
            wget -q -O "$KZG_FILE" \
                "https://raw.githubusercontent.com/ethereum/c-kzg-4844/main/src/trusted_setup.txt" 2>/dev/null || \
            wget -q -O "$KZG_FILE" \
                "https://github.com/ethereum/consensus-specs/raw/dev/presets/mainnet/trusted_setups/trusted_setup.txt" 2>/dev/null || \
            echo "ERROR: Failed to download KZG trusted setup"
        fi
        
        if [[ -f "$KZG_FILE" && -s "$KZG_FILE" ]]; then
            echo "✓ Downloaded KZG trusted setup ($(wc -c < "$KZG_FILE") bytes)"
        else
            echo "ERROR: KZG trusted setup file is missing or empty"
            echo "Nethermind may crash with 'SetupKeyStore' or 'KZG' errors"
            echo ""
            echo "Manual fix: Copy kzg_trusted_setup.txt to docker volume:"
            echo "  docker cp kzg_trusted_setup.txt <container>:/nethermind/kzg_trusted_setup.txt"
            # Don't exit - let Nethermind try to start anyway (may work on older versions)
        fi
    fi
else
    echo "✓ KZG trusted setup file exists ($(wc -c < "$KZG_FILE") bytes)"
fi

# Issue #557: Ensure keystore directory exists
KEYSTORE_DIR="/nethermind/keystore"
if [[ ! -d "$KEYSTORE_DIR" ]]; then
    echo "Creating keystore directory: $KEYSTORE_DIR"
    mkdir -p "$KEYSTORE_DIR"
    chmod 700 "$KEYSTORE_DIR"
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
