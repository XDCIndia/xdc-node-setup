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
# Snapshot Validation
#==============================================================================

deploy_validate_snapshot() {
    local datadir="${XDC_DATA:-${PROJECT_ROOT}/mainnet/xdcchain}"
    local skip_validation="${XDC_SKIP_SNAPSHOT_VALIDATION:-false}"

    if [[ "$skip_validation" == "true" ]]; then
        log_warning "Skipping snapshot validation (XDC_SKIP_SNAPSHOT_VALIDATION=true)"
        return 0
    fi

    # Only validate if chaindata exists (not a fresh deploy)
    if [[ ! -d "$datadir" ]]; then
        log_info "No existing datadir found — fresh deployment, skipping validation"
        return 0
    fi

    log_step "Running pre-deployment snapshot validation..."

    local validation_script="${SCRIPT_DIR}/validate-snapshot-deep.sh"
    if [[ ! -f "$validation_script" ]]; then
        log_warning "Deep validator not found, falling back to preflight only"
        return 0
    fi

    local report_file=$(mktemp)
    if ! bash "$validation_script" --quick --json --output "$report_file" --datadir "$datadir" >/dev/null 2>&1; then
        log_error "Pre-deployment snapshot validation FAILED"
        if command -v jq &>/dev/null && [[ -f "$report_file" ]]; then
            local errors=$(jq -r '.checks | to_entries[] | select(.value.passed==false) | "  - \(.key): \(.value.detail // "failed")"' "$report_file" 2>/dev/null)
            echo "$errors" | while read line; do log_error "$line"; done
        fi
        rm -f "$report_file"

        # Notify operators
        if [[ -f "${SCRIPT_DIR}/lib/notify.sh" ]]; then
            source "${SCRIPT_DIR}/lib/notify.sh"
            notify_load_config
            notify_alert "critical" "Snapshot Validation Failed" \
                "Pre-deployment validation failed for ${NOTIFY_NODE_HOST}. Deployment aborted. Check datadir: $datadir"
        fi

        log_error "Deployment aborted. To force deployment anyway, set XDC_SKIP_SNAPSHOT_VALIDATION=true"
        exit 1
    fi

    log_success "Pre-deployment snapshot validation passed"
    rm -f "$report_file"
    return 0
}

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
    
    # Run pre-deployment snapshot validation
    deploy_validate_snapshot
    
    # Start deployment
    log_step "Starting deployment..."
    docker compose -f "$COMPOSE_FILE" up -d
    
    log_success "Deployment complete!"
}

main "$@"
