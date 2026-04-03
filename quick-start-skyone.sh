#!/bin/bash
# =============================================================================
# XDC SkyOne Agent - Quick Start Script
# Usage: ./quick-start-skyone.sh [external|full|validator]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker/docker-compose.skyone.yml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

print_banner() {
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║          XDC SkyOne Agent - Quick Start                       ║
║                                                               ║
║   Unified Dashboard + SkyNet Agent + XDC Node                 ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker first."
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose not found. Please install Docker Compose."
        exit 1
    fi
    
    log_success "Docker and Docker Compose are installed"
}

get_compose_cmd() {
    if docker compose version &> /dev/null; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

setup_skynet_config() {
    if [ ! -f "${SCRIPT_DIR}/skynet.conf" ]; then
        log_info "Creating SkyNet configuration..."
        
        read -p "Enter your SkyNet API Key (optional): " skynet_key
        read -p "Enter node name [$(hostname)]: " node_name
        node_name=${node_name:-$(hostname)}
        
        cat > "${SCRIPT_DIR}/skynet.conf" << EOF
SKYNET_API_URL=https://skynet.xdcindia.com/api
SKYNET_API_KEY=${skynet_key}
SKYNET_NODE_NAME=${node_name}
SKYNET_ROLE=fullnode
EOF
        
        log_success "SkyNet configuration created at ${SCRIPT_DIR}/skynet.conf"
        
        if [ -z "$skynet_key" ]; then
            log_warn "No SkyNet API key provided - SkyNet features will be disabled"
            log_info "Get your API key at: https://skynet.xdcindia.com"
        fi
    fi
}

deploy_external() {
    log_info "Deploying SkyOne Agent (External Node Monitoring)..."
    
    read -p "Enter XDC RPC URL [http://host.docker.internal:8545]: " rpc_url
    rpc_url=${rpc_url:-http://host.docker.internal:8545}
    
    export XDC_RPC_URL="$rpc_url"
    
    $(get_compose_cmd) -f "$COMPOSE_FILE" --profile external up -d
    
    log_success "SkyOne Agent deployed!"
    log_info "Dashboard: http://localhost:7070"
    log_info "Metrics: http://localhost:6060/metrics"
}

deploy_full() {
    log_info "Deploying XDC SkyOne Full Stack (Node + Dashboard + SkyNet)..."
    
    read -p "Select network [mainnet/testnet/devnet/apothem]: " network
    network=${network:-mainnet}
    
    read -p "Select client [stable/geth-pr5/erigon/nethermind]: " client
    client=${client:-stable}
    
    read -p "Enter node name [$(hostname)]: " node_name
    node_name=${node_name:-$(hostname)}
    
    export NETWORK="$network"
    export CLIENT="$client"
    export INSTANCE_NAME="$node_name"
    
    $(get_compose_cmd) -f "$COMPOSE_FILE" --profile full up -d
    
    log_success "XDC SkyOne Full Stack deployed!"
    log_info "Dashboard: http://localhost:7070"
    log_info "RPC: http://localhost:8545"
    log_info "P2P: 30303"
    log_info ""
    log_warn "Note: First sync may take several hours depending on network"
}

deploy_validator() {
    log_info "Deploying XDC SkyOne Validator Node..."
    log_warn "This requires a valid validator wallet!"
    
    read -p "Enter validator address (0x...): " validator_addr
    
    if [ -z "$validator_addr" ]; then
        log_error "Validator address is required"
        exit 1
    fi
    
    # Check for keystore
    if [ ! -d "${SCRIPT_DIR}/validator-secrets" ]; then
        log_warn "Creating validator-secrets directory..."
        mkdir -p "${SCRIPT_DIR}/validator-secrets"
        log_info "Please place your keystore file in: ${SCRIPT_DIR}/validator-secrets/"
        read -p "Press Enter when ready..."
    fi
    
    export VALIDATOR_ADDRESS="$validator_addr"
    export INSTANCE_NAME="XDC-Validator-${validator_addr:0:10}"
    
    $(get_compose_cmd) -f "$COMPOSE_FILE" --profile validator up -d
    
    log_success "XDC Validator deployed!"
    log_info "Dashboard: http://localhost:7070"
    log_info "Validator Address: $validator_addr"
}

show_status() {
    log_info "Checking SkyOne Agent status..."
    
    $(get_compose_cmd) -f "$COMPOSE_FILE" ps
    
    echo ""
    log_info "Recent logs:"
    $(get_compose_cmd) -f "$COMPOSE_FILE" logs --tail=20
}

show_help() {
    cat << EOF
Usage: $0 [COMMAND]

Commands:
    external    Deploy dashboard monitoring external XDC node
    full        Deploy full stack (node + dashboard + skynet)
    validator   Deploy validator node
    stop        Stop all services
    logs        Show recent logs
    status      Show service status
    help        Show this help message

Examples:
    $0 external    # Monitor existing XDC node
    $0 full        # Run complete XDC node with dashboard
    $0 validator   # Run validator node

Documentation: docs/SKYONE_AGENT_DOCUMENTATION.md
EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    print_banner
    check_docker
    
    local cmd="${1:-help}"
    
    case "$cmd" in
        external)
            setup_skynet_config
            deploy_external
            ;;
        full)
            setup_skynet_config
            deploy_full
            ;;
        validator)
            setup_skynet_config
            deploy_validator
            ;;
        stop)
            log_info "Stopping all SkyOne services..."
            $(get_compose_cmd) -f "$COMPOSE_FILE" down
            log_success "Services stopped"
            ;;
        logs)
            show_status
            ;;
        status)
            $(get_compose_cmd) -f "$COMPOSE_FILE" ps
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
