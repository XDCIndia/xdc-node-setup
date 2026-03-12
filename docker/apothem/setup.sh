#!/bin/bash
#
# Apothem Testnet Setup Validation Script
# Validates genesis, bootnodes, and ports before node startup
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKER_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Official Apothem testnet constants
APOTHEM_CHAIN_ID=51
APOTHEM_FOUNDATION_WALLET="xdc746249c61f5832c5eed53172776b460491bdcd5c"
APOTHEM_GENESIS_HASH="bdea512b4f12ff1135ec92c00dc047ffb93890c2ea1aa0eefe9b013d80640075"

echo "=========================================="
echo "Apothem Testnet Setup Validation"
echo "=========================================="
echo

# Track validation status
VALIDATION_FAILED=0

# Function to log success
log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# Function to log error
log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    VALIDATION_FAILED=1
}

# Function to log warning
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if genesis.json exists
echo "[1/5] Checking genesis.json..."
if [ ! -f "$SCRIPT_DIR/genesis.json" ]; then
    log_error "genesis.json not found in $SCRIPT_DIR"
else
    log_success "genesis.json exists"
    
    # Validate chainId
    CHAIN_ID=$(jq -r '.config.chainId' "$SCRIPT_DIR/genesis.json" 2>/dev/null || echo "null")
    if [ "$CHAIN_ID" != "$APOTHEM_CHAIN_ID" ]; then
        log_error "Invalid chainId: expected $APOTHEM_CHAIN_ID, got $CHAIN_ID"
    else
        log_success "chainId is correct ($APOTHEM_CHAIN_ID)"
    fi
    
    # Validate foundation wallet address
    FOUNDATION_WALLET=$(jq -r '.config.XDPoS.foudationWalletAddr' "$SCRIPT_DIR/genesis.json" 2>/dev/null || echo "null")
    if [ "$FOUNDATION_WALLET" != "$APOTHEM_FOUNDATION_WALLET" ]; then
        log_error "Invalid foundationWalletAddr: expected $APOTHEM_FOUNDATION_WALLET, got $FOUNDATION_WALLET"
    else
        log_success "foundationWalletAddr is correct"
    fi
    
    # Check for XDPoS configuration
    XDPOS_PERIOD=$(jq -r '.config.XDPoS.period' "$SCRIPT_DIR/genesis.json" 2>/dev/null || echo "null")
    XDPOS_EPOCH=$(jq -r '.config.XDPoS.epoch' "$SCRIPT_DIR/genesis.json" 2>/dev/null || echo "null")
    
    if [ "$XDPOS_PERIOD" != "2" ] || [ "$XDPOS_EPOCH" != "900" ]; then
        log_error "Invalid XDPoS config: period=$XDPOS_PERIOD, epoch=$XDPOS_EPOCH (expected 2, 900)"
    else
        log_success "XDPoS configuration is valid (period=2, epoch=900)"
    fi
fi

# Check bootnodes
echo
echo "[2/5] Checking bootnodes..."
if [ ! -f "$SCRIPT_DIR/bootnodes.list" ]; then
    log_error "bootnodes.list not found"
else
    BOOTNODE_COUNT=$(wc -l < "$SCRIPT_DIR/bootnodes.list" | tr -d ' ')
    if [ "$BOOTNODE_COUNT" -eq 0 ]; then
        log_error "bootnodes.list is empty"
    else
        log_success "Found $BOOTNODE_COUNT bootnodes"
    fi
    
    # Validate bootnode format (should start with enode://)
    INVALID_BOOTNODES=$(grep -v "^enode://" "$SCRIPT_DIR/bootnodes.list" 2>/dev/null || true)
    if [ -n "$INVALID_BOOTNODES" ]; then
        log_warn "Some bootnodes have invalid format (should start with enode://)"
    else
        log_success "All bootnodes have valid format"
    fi
fi

# Check port availability
echo
echo "[3/5] Checking port availability..."

# Default ports for Apothem
RPC_PORT=${RPC_PORT:-8545}
P2P_PORT=${P2P_PORT:-30303}
WS_PORT=${WS_PORT:-8546}

check_port() {
    local port=$1
    local name=$2
    if lsof -Pi :"$port" -sTCP:LISTEN -t >/dev/null 2>&1 || netstat -tuln 2>/dev/null | grep -q ":$port "; then
        log_warn "$name port $port is already in use"
    else
        log_success "$name port $port is available"
    fi
}

check_port "$RPC_PORT" "RPC"
check_port "$P2P_PORT" "P2P"
check_port "$WS_PORT" "WebSocket"

# Check Docker Compose files
echo
echo "[4/5] Checking Docker Compose files..."

COMPOSE_FILES=(
    "$DOCKER_DIR/docker-compose.apothem-geth.yml"
    "$DOCKER_DIR/docker-compose.apothem-nethermind.yml"
    "$DOCKER_DIR/docker-compose.apothem-full.yml"
)

for compose_file in "${COMPOSE_FILES[@]}"; do
    if [ -f "$compose_file" ]; then
        log_success "Found $(basename "$compose_file")"
    else
        log_warn "Missing $(basename "$compose_file")"
    fi
done

# Check environment variables
echo
echo "[5/5] Checking environment configuration..."

# Check if .env file exists in expected locations
ENV_FILES=(
    "$SCRIPT_DIR/.env"
    "$DOCKER_DIR/.env"
)

ENV_FOUND=0
for env_file in "${ENV_FILES[@]}"; do
    if [ -f "$env_file" ]; then
        log_success "Found .env file at $env_file"
        ENV_FOUND=1
        
        # Check for required variables
        if grep -q "NETWORK" "$env_file" 2>/dev/null; then
            NETWORK=$(grep "NETWORK" "$env_file" | cut -d= -f2 | tr -d '"' | tr -d "'" | xargs)
            if [ "$NETWORK" = "apothem" ] || [ "$NETWORK" = "testnet" ]; then
                log_success "  NETWORK is set to '$NETWORK'"
            else
                log_warn "  NETWORK is set to '$NETWORK' (expected 'apothem' or 'testnet')"
            fi
        else
            log_warn "  NETWORK variable not set"
        fi
        
        if grep -q "CHAIN_ID" "$env_file" 2>/dev/null; then
            CHAIN_ID_ENV=$(grep "CHAIN_ID" "$env_file" | cut -d= -f2 | tr -d '"' | tr -d "'" | xargs)
            if [ "$CHAIN_ID_ENV" = "$APOTHEM_CHAIN_ID" ]; then
                log_success "  CHAIN_ID is correct ($APOTHEM_CHAIN_ID)"
            else
                log_error "  CHAIN_ID is $CHAIN_ID_ENV (expected $APOTHEM_CHAIN_ID)"
            fi
        fi
    fi
done

if [ $ENV_FOUND -eq 0 ]; then
    log_warn "No .env file found in standard locations"
fi

# Final summary
echo
echo "=========================================="
if [ $VALIDATION_FAILED -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS]${NC} All validations passed!"
    echo "You can safely start the Apothem testnet node."
    echo
    echo "To start the node, run:"
    echo "  docker-compose -f docker/docker-compose.apothem-geth.yml up -d"
    echo "  docker-compose -f docker/docker-compose.apothem-nethermind.yml up -d"
    echo "=========================================="
    exit 0
else
    echo -e "${RED}[FAILED]${NC} Validation failed!"
    echo "Please fix the errors above before starting the node."
    echo "=========================================="
    exit 1
fi