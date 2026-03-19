#!/bin/bash
#===============================================================================
# XDCSync Genesis Initialization Script
# Downloads, validates, and initializes genesis for XDC Network clients
# Supports both mainnet (chainId 50) and apothem (chainId 51)
#===============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

GENESIS_DIR="${ROOT_DIR}/docker"
DATA_DIR="${DATA_DIR:-${ROOT_DIR}/data}"
NETWORK="${NETWORK:-mainnet}"
FORCE_INIT="${FORCE_INIT:-false}"

MAINNET_GENESIS_URL="https://raw.githubusercontent.com/XinFinOrg/XDPoSChain/master/genesis/mainnet.json"
APOTHEM_GENESIS_URL="https://raw.githubusercontent.com/XinFinOrg/XDPoSChain/master/genesis/testnet.json"

MAINNET_CHAIN_ID=50
APOTHEM_CHAIN_ID=51

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Initialize genesis configuration for XDC Network nodes

OPTIONS:
    -n, --network NETWORK    Network type: mainnet|apothem (default: mainnet)
    -f, --force              Force re-initialization (wipes existing data)
    -d, --data-dir PATH      Data directory path (default: ./data)
    -c, --client CLIENT      Initialize specific client: gp5|erigon|nethermind|reth|all
    -h, --help               Show this help message

EXAMPLES:
    $0 --network mainnet
    $0 --network apothem --client gp5
    $0 --network mainnet --force
EOF
}

download_genesis() {
    local network="$1"
    local output_file="$2"
    local url
    case "$network" in
        mainnet) url="$MAINNET_GENESIS_URL" ;;
        apothem) url="$APOTHEM_GENESIS_URL" ;;
        *) log_error "Unknown network: $network"; exit 1 ;;
    esac
    log_info "Downloading genesis for $network..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output_file" || { log_error "Download failed"; exit 1; }
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$output_file" || { log_error "Download failed"; exit 1; }
    else
        log_error "curl or wget required"; exit 1
    fi
    log_success "Genesis downloaded to $output_file"
}

validate_genesis() {
    local genesis_file="$1"
    local expected_chain_id="$2"
    log_info "Validating genesis file..."
    if [[ ! -f "$genesis_file" ]]; then
        log_error "Genesis file not found: $genesis_file"
        return 1
    fi
    if ! python3 -m json.tool "$genesis_file" >/dev/null 2>&1; then
        log_error "Invalid JSON in genesis file"
        return 1
    fi
    local chain_id
    chain_id=$(python3 -c "
import json
with open('$genesis_file') as f:
    genesis = json.load(f)
    print(genesis.get('config', {}).get('chainId', genesis.get('chainId', 'null')))
" 2>/dev/null || echo "null")
    if [[ "$chain_id" == "null" ]] || [[ -z "$chain_id" ]]; then
        log_error "Could not extract chainId from genesis file"
        return 1
    fi
    if [[ "$chain_id" != "$expected_chain_id" ]]; then
        log_error "Chain ID mismatch! Expected: $expected_chain_id, Found: $chain_id"
        return 1
    fi
    log_success "Genesis validated - Chain ID: $chain_id matches $NETWORK"
}

init_client_datadir() {
    local client="$1"
    local genesis_file="$2"
    local client_data_dir="$DATA_DIR/$client"
    log_info "Initializing $client data directory..."
    mkdir -p "$client_data_dir"
    if [[ -d "$client_data_dir/chaindata" ]] && [[ "$FORCE_INIT" != "true" ]]; then
        log_warn "$client already initialized. Use --force to re-initialize."
        return 0
    fi
    if [[ "$FORCE_INIT" == "true" ]] && [[ -d "$client_data_dir" ]]; then
        log_warn "Force mode: wiping $client data directory..."
        rm -rf "$client_data_dir"/*
    fi
    cp "$genesis_file" "$client_data_dir/genesis.json"
    echo "$(date -Iseconds)" > "$client_data_dir/.genesis_init"
    echo "$NETWORK" > "$client_data_dir/.network"
    log_success "$client initialized"
}

main() {
    local client="all"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--network) NETWORK="$2"; shift 2 ;;
            -f|--force) FORCE_INIT="true"; shift ;;
            -d|--data-dir) DATA_DIR="$2"; shift 2 ;;
            -c|--client) client="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) log_error "Unknown option: $1"; usage; exit 1 ;;
        esac
    done
    case "$NETWORK" in
        mainnet|apothem) log_info "Initializing for network: $NETWORK" ;;
        *) log_error "Invalid network: $NETWORK"; exit 1 ;;
    esac
    local expected_chain_id
    [[ "$NETWORK" == "mainnet" ]] && expected_chain_id=$MAINNET_CHAIN_ID || expected_chain_id=$APOTHEM_CHAIN_ID
    mkdir -p "$DATA_DIR"
    local genesis_file="$GENESIS_DIR/$NETWORK/genesis.json"
    local downloaded_genesis=false
    if [[ ! -f "$genesis_file" ]] || [[ "$FORCE_INIT" == "true" ]]; then
        download_genesis "$NETWORK" "$genesis_file"
        downloaded_genesis=true
    else
        log_info "Using existing genesis: $genesis_file"
    fi
    if ! validate_genesis "$genesis_file" "$expected_chain_id"; then
        [[ "$downloaded_genesis" == "true" ]] && rm -f "$genesis_file"
        exit 1
    fi
    case "$client" in
        all)
            init_client_datadir "gp5" "$genesis_file"
            init_client_datadir "erigon" "$genesis_file"
            init_client_datadir "nethermind" "$genesis_file"
            init_client_datadir "reth" "$genesis_file"
            ;;
        gp5|geth-pr5) init_client_datadir "gp5" "$genesis_file" ;;
        erigon) init_client_datadir "erigon" "$genesis_file" ;;
        nethermind|nm) init_client_datadir "nethermind" "$genesis_file" ;;
        reth) init_client_datadir "reth" "$genesis_file" ;;
        *) log_error "Unknown client: $client"; exit 1 ;;
    esac
    log_success "Genesis initialization complete!"
    log_info "Data directory: $DATA_DIR"
    log_info "Network: $NETWORK (Chain ID: $expected_chain_id)"
}

main "$@"
