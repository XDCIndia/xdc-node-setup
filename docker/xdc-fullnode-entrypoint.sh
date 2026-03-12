#!/bin/bash
# Entrypoint wrapper for XDC containers
# Handles both masternode and fullnode operation modes
# Issue #516: xinfinorg/xdposchain:v2.6.8 requires PRIVATE_KEY env for fullnode

set -e

# Detect operation mode
if [[ -n "${PRIVATE_KEY:-}" ]]; then
    # Masternode mode - use the standard entrypoint
    echo "[entrypoint] Starting in MASTERNODE mode"
    exec /entrypoint.sh "$@"
else
    # Fullnode mode - bypass masternode setup
    echo "[entrypoint] Starting in FULLNODE mode (no PRIVATE_KEY provided)"
    
    # Validate required environment
    if [[ -z "${NETWORK:-}" ]]; then
        echo "[entrypoint] ERROR: NETWORK environment variable must be set (mainnet/testnet/devnet)"
        exit 1
    fi
    
    # Set network-specific binary
    case "$NETWORK" in
        mainnet)
            XDC_BIN="${XDC_BIN:-/usr/bin/XDC}"
            ;;
        testnet|apothem)
            XDC_BIN="${XDC_BIN:-/usr/bin/XDC-testnet}"
            NETWORK="apothem"
            ;;
        devnet)
            XDC_BIN="${XDC_BIN:-/usr/bin/XDC}"
            ;;
        *)
            echo "[entrypoint] ERROR: Unknown NETWORK: $NETWORK (must be mainnet/testnet/devnet)"
            exit 1
            ;;
    esac
    
    # Verify binary exists
    if [[ ! -x "$XDC_BIN" ]]; then
        echo "[entrypoint] ERROR: XDC binary not found at $XDC_BIN"
        exit 1
    fi
    
    # Set default data directory
    DATA_DIR="${DATA_DIR:-/work/xdcchain}"
    mkdir -p "$DATA_DIR"
    
    # Build argument list
    ARGS=()
    
    # Required arguments
    ARGS+=("--datadir=$DATA_DIR")
    
    # Network selection
    case "$NETWORK" in
        mainnet)
            ARGS+=("--networkid=50")
            ;;
        apothem|testnet)
            ARGS+=("--networkid=51")
            ARGS+=("--apothem")
            ;;
        devnet)
            ARGS+=("--networkid=551")
            ARGS+=("--apothem")
            ;;
    esac
    
    # RPC configuration (secure defaults for fullnode)
    RPC_ADDR="${RPC_ADDR:-127.0.0.1}"
    RPC_PORT="${RPC_PORT:-8545}"
    
    if [[ "${RPC_ENABLED:-true}" == "true" ]]; then
        ARGS+=("--rpc")
        ARGS+=("--rpcaddr=$RPC_ADDR")
        ARGS+=("--rpcport=$RPC_PORT")
        ARGS+=("--rpcvhosts=${RPC_VHOSTS:-localhost}")
        ARGS+=("--rpccorsdomain=${RPC_ALLOW_ORIGINS:-localhost}")
        ARGS+=("--rpcapi=${RPC_API:-eth,net,web3,XDPoS}")
    fi
    
    # WebSocket configuration
    if [[ "${WS_ENABLED:-false}" == "true" ]]; then
        ARGS+=("--ws")
        ARGS+=("--wsaddr=${WS_ADDR:-127.0.0.1}")
        ARGS+=("--wsport=${WS_PORT:-8546}")
        ARGS+=("--wsorigins=${WS_ORIGINS:-localhost}")
        ARGS+=("--wsapi=${WS_API:-eth,net,web3}")
    fi
    
    # P2P configuration
    P2P_PORT="${P2P_PORT:-30303}"
    ARGS+=("--port=$P2P_PORT")
    
    # Bootnodes
    if [[ -n "${BOOTNODES:-}" ]]; then
        ARGS+=("--bootnodes=$BOOTNODES")
    fi
    
    # Sync mode
    SYNC_MODE="${SYNC_MODE:-full}"
    ARGS+=("--syncmode=$SYNC_MODE")
    
    # Gas price
    GAS_PRICE="${GAS_PRICE:-1}"
    ARGS+=("--gasprice=$GAS_PRICE")
    
    # Additional arguments from environment
    if [[ -n "${XDC_EXTRA_ARGS:-}" ]]; then
        # shellcheck disable=SC2086
        ARGS+=($XDC_EXTRA_ARGS)
    fi
    
    # Append any command-line arguments passed to this script
    ARGS+=("$@")
    
    echo "[entrypoint] Using binary: $XDC_BIN"
    echo "[entrypoint] Data directory: $DATA_DIR"
    echo "[entrypoint] Network: $NETWORK (ID: ${ARGS[*]} | grep -o 'networkid=[0-9]*' | cut -d= -f2)"
    echo "[entrypoint] RPC: $RPC_ADDR:$RPC_PORT (enabled: ${RPC_ENABLED:-true})"
    echo "[entrypoint] P2P port: $P2P_PORT"
    
    # Execute XDC binary
    echo "[entrypoint] Starting XDC node..."
    exec "$XDC_BIN" "${ARGS[@]}"
fi
