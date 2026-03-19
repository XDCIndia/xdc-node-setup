#!/bin/bash
# XDC Genesis Initialization Script
# Supports both Mainnet (Chain 50) and Apothem (Chain 51)
# Initializes all 4 client data directories

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Genesis hashes
GENESIS_HASH_MAINNET="0x4a9d748bd78a8d0385b67788c2435dcdb914f98a96250b68863a1f8b7642d6b1"
GENESIS_HASH_APOTHEM="0xbdea512b4f12ff1135ec92c00dc047ffb93890c2ea1aa0eefe9b013d80640075"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Function to display usage
usage() {
    cat << EOF
XDC Genesis Initialization Script

Usage: $0 [OPTIONS]

Options:
    -n, --network NETWORK    Network to initialize (mainnet|apothem) [default: mainnet]
    -c, --client CLIENT      Client to initialize (gp5|erigon|nm|reth|all) [default: all]
    -f, --force              Force re-initialization (wipes existing data)
    -h, --help               Show this help message

Examples:
    $0                                    # Initialize all clients for mainnet
    $0 -n apothem                         # Initialize all clients for apothem
    $0 -n mainnet -c gp5                  # Initialize only GP5 for mainnet
    $0 -n apothem -c all -f               # Force re-initialize all for apothem

EOF
    exit 0
}

# Parse arguments
NETWORK="mainnet"
CLIENT="all"
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--network)
            NETWORK="$2"
            shift 2
            ;;
        -c|--client)
            CLIENT="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate network
if [[ "$NETWORK" != "mainnet" && "$NETWORK" != "apothem" ]]; then
    print_error "Invalid network: $NETWORK. Must be 'mainnet' or 'apothem'"
    exit 1
fi

# Set network-specific variables
if [[ "$NETWORK" == "mainnet" ]]; then
    GENESIS_URL="https://raw.githubusercontent.com/XinFinOrg/XinFin-Node/master/genesis.json"
    EXPECTED_CHAIN_ID=50
    EXPECTED_HASH="$GENESIS_HASH_MAINNET"
else
    GENESIS_URL="https://raw.githubusercontent.com/XinFinOrg/XinFin-Node/apothem/genesis.json"
    EXPECTED_CHAIN_ID=51
    EXPECTED_HASH="$GENESIS_HASH_APOTHEM"
fi

print_status "Initializing XDC $NETWORK (Chain ID: $EXPECTED_CHAIN_ID)"

# Create data directories
mkdir -p data/{gp5,erigon,nm,reth}

# Download and validate genesis
if [[ ! -f genesis.json ]] || [[ "$FORCE" == true ]]; then
    print_status "Downloading genesis.json for $NETWORK..."
    curl -sL "$GENESIS_URL" -o genesis.json
    
    # Validate genesis
    if [[ ! -f genesis.json ]]; then
        print_error "Failed to download genesis.json"
        exit 1
    fi
    
    # Extract and verify chainId
    CHAIN_ID=$(cat genesis.json | grep -o '"chainId":[[:space:]]*[0-9]*' | grep -o '[0-9]*' | head -1)
    
    if [[ "$CHAIN_ID" != "$EXPECTED_CHAIN_ID" ]]; then
        print_error "Invalid chainId in genesis.json: $CHAIN_ID (expected $EXPECTED_CHAIN_ID)"
        exit 1
    fi
    
    print_status "Genesis validated: chainId=$CHAIN_ID"
else
    print_status "Using existing genesis.json"
fi

# Function to initialize GP5
init_gp5() {
    print_status "Initializing Geth-PR5 (GP5)..."
    
    local datadir="data/gp5"
    
    if [[ -d "$datadir/XDC/chaindata" ]]; then
        if [[ "$FORCE" == true ]]; then
            print_warning "Wiping existing GP5 data..."
            rm -rf "$datadir/XDC"
        else
            print_status "GP5 already initialized, skipping (use -f to force)"
            return
        fi
    fi
    
    docker run --rm \
        -v "$(pwd)/$datadir:/work/xdcchain" \
        -v "$(pwd)/genesis.json:/work/genesis.json:ro" \
        anilchinchawale/gx:latest \
        init /work/genesis.json --datadir /work/xdcchain
    
    print_status "GP5 initialized successfully"
}

# Function to initialize Erigon
init_erigon() {
    print_status "Initializing Erigon..."
    
    local datadir="data/erigon"
    
    if [[ -d "$datadir/chaindata" ]]; then
        if [[ "$FORCE" == true ]]; then
            print_warning "Wiping existing Erigon data..."
            rm -rf "$datadir"/*
        else
            print_status "Erigon already initialized, skipping (use -f to force)"
            return
        fi
    fi
    
    # Erigon doesn't need explicit init, just directory structure
    mkdir -p "$datadir"/{chaindata,nodes,snapshots}
    
    print_status "Erigon directories created"
}

# Function to initialize Nethermind
init_nm() {
    print_status "Initializing Nethermind..."
    
    local datadir="data/nm"
    
    if [[ -d "$datadir/nethermind" ]]; then
        if [[ "$FORCE" == true ]]; then
            print_warning "Wiping existing Nethermind data..."
            rm -rf "$datadir/nethermind"
        else
            print_status "Nethermind already initialized, skipping (use -f to force)"
            return
        fi
    fi
    
    # Create directory structure
    mkdir -p "$datadir/nethermind"/{db,logs}
    
    print_status "Nethermind directories created"
}

# Function to initialize Reth
init_reth() {
    print_status "Initializing Reth..."
    
    local datadir="data/reth"
    
    if [[ -d "$datadir/reth.toml" ]] || [[ -d "$datadir/db" ]]; then
        if [[ "$FORCE" == true ]]; then
            print_warning "Wiping existing Reth data..."
            rm -rf "$datadir"/*
        else
            print_status "Reth already initialized, skipping (use -f to force)"
            return
        fi
    fi
    
    # Create directory structure
    mkdir -p "$datadir"/{db,logs}
    
    print_status "Reth directories created"
}

# Initialize requested clients
case $CLIENT in
    gp5)
        init_gp5
        ;;
    erigon)
        init_erigon
        ;;
    nm|nethermind)
        init_nm
        ;;
    reth)
        init_reth
        ;;
    all)
        init_gp5
        init_erigon
        init_nm
        init_reth
        ;;
    *)
        print_error "Unknown client: $CLIENT"
        exit 1
        ;;
esac

# Create environment file for docker-compose
cat > .env << EOF
# XDC Multi-Client Configuration
NETWORK=$NETWORK
GENESIS_HASH=$EXPECTED_HASH

# SkyOne Node IDs (generate unique IDs for each client)
SKYNET_GP5_NODE_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "gp5-$(date +%s)")
SKYNET_ERIGON_NODE_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "erigon-$(date +%s)")
SKYNET_NM_NODE_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "nm-$(date +%s)")
SKYNET_RETH_NODE_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "reth-$(date +%s)")

# Client-specific settings
XDC_BYPASS_STATE_ROOT=1
XDC_CHECKPOINT_AUTH_BYPASS=1
EOF

print_status "Environment file (.env) created"

# Summary
echo ""
echo "=========================================="
echo -e "${GREEN}XDC Genesis Initialization Complete${NC}"
echo "=========================================="
echo "Network: $NETWORK (Chain ID: $EXPECTED_CHAIN_ID)"
echo "Genesis Hash: $EXPECTED_HASH"
echo ""
echo "Next steps:"
echo "  1. Review .env file and update SkyOne Node IDs if needed"
echo "  2. Start clients: docker-compose -f docker-compose.multi-client.yml up -d"
echo "  3. Monitor sync: docker-compose logs -f"
echo ""
echo "Client RPC endpoints:"
echo "  GP5:       http://localhost:8545"
echo "  Erigon:    http://localhost:8546"
echo "  Nethermind: http://localhost:8547"
echo "  Reth:      http://localhost:8548"
echo "=========================================="
