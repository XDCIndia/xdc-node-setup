#!/bin/bash
#==============================================================================
# XDC Node Deployment Script
# Wrapper that runs preflight checks before docker-compose up
# Handles container conflicts automatically
#==============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly DOCKER_DIR="${PROJECT_ROOT}/docker"

# Colors for output
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    GREEN=''
    YELLOW=''
    RED=''
    BLUE=''
    CYAN=''
    NC=''
fi

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_step() {
    echo -e "${CYAN}▶${NC} $1"
}

#==============================================================================
# Configuration
#==============================================================================

# Default compose file
COMPOSE_FILE="${DOCKER_DIR}/docker-compose.yml"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-xdc-node}"

# Auto-resolve conflicts in CI/non-interactive environments
AUTO_RESOLVE="${XDC_DEPLOY_AUTO:-false}"

#==============================================================================
# Main
#==============================================================================

main() {
    echo "XDC Node Deployment Script"
    echo "=========================="
    echo ""
    echo "This script handles Docker container conflicts automatically."
    echo ""
    echo "Usage:"
    echo "  ./deploy.sh [up|down|restart|status]"
    echo ""
    echo "Options:"
    echo "  -f, --file FILE    Use specific docker-compose file"
    echo "  -a, --auto         Auto-resolve conflicts"
    echo "  -h, --help         Show this help"
    echo ""
    echo "Examples:"
    echo "  ./deploy.sh                    # Deploy with defaults"
    echo "  ./deploy.sh -f docker/docker-compose.geth-pr5.yml"
    echo "  ./deploy.sh --auto             # Auto-resolve conflicts"
    echo "  ./deploy.sh down               # Stop containers"
    echo ""
    
    # Run preflight check
    "${SCRIPT_DIR}/preflight-check.sh" resolve
    
    # Start deployment
    log_step "Starting deployment..."
    docker compose -f "$COMPOSE_FILE" up -d
    
    log_success "Deployment complete!"
}

main "$@"
