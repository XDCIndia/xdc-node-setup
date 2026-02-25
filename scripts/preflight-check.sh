#!/bin/bash
#==============================================================================
# XDC Node Pre-flight Check Script
# Detects and handles Docker container name conflicts before deployment
#==============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DOCKER_DIR="${SCRIPT_DIR}/docker"

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

#==============================================================================
# Container Name Detection
#==============================================================================

# List of all container names used in the project
get_container_names() {
    cat << 'EOF'
xdc-node
xdc-node-geth-pr5
xdc-node-reth
xdc-node-erigon
xdc-node-erigon-testnet
xdc-node-apothem
xdc-node-gx-apothem
xdc-node-erigon-apothem
xdc-node-nethermind-apothem
xdc-node-nethermind
xdc-agent
xdc-agent-gp5
xdc-agent-reth
xdc-agent-erigon-testnet
xdc-agent-nethermind
xdc-agent-reth
skynet-agent-geth
skynet-agent-gx
skynet-agent-erigon
skynet-agent-nethermind
peer-connector
EOF
}

# Check if a container with the given name is running or exists
check_container() {
    local name="$1"
    local status
    
    # Check if container exists (running or stopped)
    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        # Check if it's running
        if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
            echo "running"
        else
            echo "stopped"
        fi
    else
        echo "none"
    fi
}

# Get container info for display
get_container_info() {
    local name="$1"
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}" | grep "^${name}" || true
}

#==============================================================================
# Conflict Resolution
#==============================================================================

stop_container() {
    local name="$1"
    log_info "Stopping container: $name"
    if docker stop "$name" >/dev/null 2>&1; then
        log_success "Container stopped: $name"
        return 0
    else
        log_error "Failed to stop container: $name"
        return 1
    fi
}

remove_container() {
    local name="$1"
    log_info "Removing container: $name"
    if docker rm "$name" >/dev/null 2>&1; then
        log_success "Container removed: $name"
        return 0
    else
        log_error "Failed to remove container: $name"
        return 1
    fi
}

stop_and_remove_container() {
    local name="$1"
    local status
    status=$(check_container "$name")
    
    if [[ "$status" == "running" ]]; then
        stop_container "$name" || return 1
    fi
    
    if [[ "$status" != "none" ]]; then
        remove_container "$name" || return 1
    fi
    
    return 0
}

#==============================================================================
# Main Check Functions
#==============================================================================

check_all_containers() {
    log_info "Checking for existing XDC containers..."
    echo ""
    
    local conflicts=()
    local running=()
    local stopped=()
    
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        
        local status
        status=$(check_container "$name")
        
        case "$status" in
            running)
                running+=("$name")
                ;;
            stopped)
                stopped+=("$name")
                ;;
        esac
    done < <(get_container_names)
    
    # Display results
    if [[ ${#running[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Running containers detected:${NC}"
        printf '  - %s\n' "${running[@]}"
        echo ""
    fi
    
    if [[ ${#stopped[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Stopped containers detected:${NC}"
        printf '  - %s\n' "${stopped[@]}"
        echo ""
    fi
    
    if [[ ${#running[@]} -eq 0 && ${#stopped[@]} -eq 0 ]]; then
        log_success "No existing XDC containers found"
        return 0
    fi
    
    return 1
}

check_specific_compose() {
    local compose_file="$1"
    local base_name
    base_name=$(basename "$compose_file" .yml)
    
    log_info "Checking containers for: $base_name"
    
    # Extract container names from docker-compose file
    local containers
    containers=$(grep -E "^\s+container_name:" "$compose_file" 2>/dev/null | sed 's/.*container_name:\s*//' | tr -d '"' || true)
    
    if [[ -z "$containers" ]]; then
        log_info "No explicit container names found in $compose_file"
        return 0
    fi
    
    local conflicts=()
    
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        
        local status
        status=$(check_container "$name")
        
        if [[ "$status" != "none" ]]; then
            conflicts+=("$name ($status)")
        fi
    done <<< "$containers"
    
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Conflicts detected for $base_name:${NC}"
        printf '  - %s\n' "${conflicts[@]}"
        return 1
    else
        log_success "No conflicts for $base_name"
        return 0
    fi
}

#==============================================================================
# Interactive Resolution
#==============================================================================

resolve_interactive() {
    log_info "Resolving container conflicts interactively..."
    echo ""
    
    local containers=()
    
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        
        local status
        status=$(check_container "$name")
        
        if [[ "$status" != "none" ]]; then
            containers+=("$name")
        fi
    done < <(get_container_names)
    
    if [[ ${#containers[@]} -eq 0 ]]; then
        return 0
    fi
    
    echo "The following containers already exist:"
    printf '  - %s\n' "${containers[@]}"
    echo ""
    
    # Auto-resolve in non-interactive mode
    if [[ ! -t 0 ]] || [[ "${XDC_PREFLIGHT_AUTO:-false}" == "true" ]]; then
        log_info "Auto-resolving conflicts (non-interactive mode)..."
        for name in "${containers[@]}"; do
            stop_and_remove_container "$name" || true
        done
        return 0
    fi
    
    # Interactive mode
    echo "Options:"
    echo "  1) Stop and remove all conflicting containers (recommended)"
    echo "  2) Stop containers only (keep for inspection)"
    echo "  3) Skip and continue anyway (may cause errors)"
    echo "  4) Cancel deployment"
    echo ""
    
    read -rp "Select option [1-4]: " choice
    
    case "$choice" in
        1)
            log_info "Stopping and removing all conflicting containers..."
            for name in "${containers[@]}"; do
                stop_and_remove_container "$name" || true
            done
            ;;
        2)
            log_info "Stopping all conflicting containers..."
            for name in "${containers[@]}"; do
                local status
                status=$(check_container "$name")
                if [[ "$status" == "running" ]]; then
                    stop_container "$name" || true
                fi
            done
            ;;
        3)
            log_warning "Continuing with potential conflicts..."
            return 0
            ;;
        4|*)
            log_error "Deployment cancelled by user"
            exit 1
            ;;
    esac
}

#==============================================================================
# Command Line Interface
#==============================================================================

show_help() {
    cat << 'EOF'
XDC Node Pre-flight Check Script

Usage: preflight-check.sh [OPTIONS] [COMMAND]

Commands:
    check           Check for container conflicts (default)
    resolve         Check and resolve conflicts interactively
    clean           Stop and remove all XDC containers
    status          Show status of all XDC containers

Options:
    -f, --file FILE Check specific docker-compose file
    -a, --auto      Auto-resolve conflicts (non-interactive)
    -q, --quiet     Quiet mode (exit code only)
    -h, --help      Show this help message

Environment Variables:
    XDC_PREFLIGHT_AUTO=true    Enable auto-resolve mode

Examples:
    # Check for conflicts
    ./preflight-check.sh

    # Check and resolve interactively
    ./preflight-check.sh resolve

    # Clean up all XDC containers
    ./preflight-check.sh clean

    # Check specific compose file
    ./preflight-check.sh -f docker/docker-compose.geth-pr5.yml

    # Auto-resolve in scripts
    XDC_PREFLIGHT_AUTO=true ./preflight-check.sh resolve
EOF
}

#==============================================================================
# Main
#==============================================================================

main() {
    local command="check"
    local compose_file=""
    local quiet=false
    local auto=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--file)
                compose_file="$2"
                shift 2
                ;;
            -a|--auto)
                auto=true
                shift
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            check|resolve|clean|status)
                command="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Set auto mode from environment if not set via flag
    if [[ "$auto" == "false" && "${XDC_PREFLIGHT_AUTO:-false}" == "true" ]]; then
        auto=true
    fi
    
    if [[ "$auto" == "true" ]]; then
        export XDC_PREFLIGHT_AUTO=true
    fi
    
    case "$command" in
        check)
            if [[ -n "$compose_file" ]]; then
                if ! check_specific_compose "$compose_file"; then
                    exit 1
                fi
            else
                if ! check_all_containers; then
                    exit 1
                fi
            fi
            ;;
        resolve)
            if [[ -n "$compose_file" ]]; then
                check_specific_compose "$compose_file" || true
            else
                check_all_containers || true
            fi
            resolve_interactive
            ;;
        clean)
            log_info "Cleaning up all XDC containers..."
            while IFS= read -r name; do
                [[ -z "$name" ]] && continue
                stop_and_remove_container "$name" || true
            done < <(get_container_names)
            log_success "Cleanup complete"
            ;;
        status)
            echo "XDC Container Status:"
            echo "====================="
            echo ""
            
            local found=false
            while IFS= read -r name; do
                [[ -z "$name" ]] && continue
                
                local status
                status=$(check_container "$name")
                
                if [[ "$status" != "none" ]]; then
                    found=true
                    local color="$NC"
                    case "$status" in
                        running) color="$GREEN" ;;
                        stopped) color="$YELLOW" ;;
                    esac
                    echo -e "${color}${name}${NC}: ${status}"
                    get_container_info "$name"
                    echo ""
                fi
            done < <(get_container_names)
            
            if [[ "$found" == "false" ]]; then
                log_info "No XDC containers found"
            fi
            ;;
    esac
}

main "$@"
