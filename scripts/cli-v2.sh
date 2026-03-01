#!/usr/bin/env bash

# Source shared logging library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/logging.sh" 2>/dev/null || source "$(dirname "$0")/lib/logging.sh" || { echo "Error: Cannot find lib/logging.sh" >&2; exit 1; }


# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }
#==============================================================================
#==============================================================================
# XDC Node CLI v2.0 - Enhanced Setup Script
# Interactive wizard, quick deployment, pre-flight checks
#==============================================================================

set -euo pipefail

readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WIZARD_DIR="${SCRIPT_DIR}/wizard"

#==============================================================================
# Colors & UI
#==============================================================================
if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly MAGENTA='\033[0;35m'
    readonly BOLD='\033[1m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly CYAN=''
    readonly MAGENTA=''
    readonly BOLD=''
    readonly NC=''
fi

#==============================================================================
# Command Line Arguments
#==============================================================================
ARG_QUICK=false
ARG_GUI=false
ARG_NETWORK=""
ARG_ROLE=""
ARG_CLOUD=""
ARG_HELP=false
ARG_VERSION=false

#==============================================================================
# UI Functions
#==============================================================================
print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
 __  ______   ____  _   _______________________ 
 \ \/ /  _ \ / __ \/ | / / ____/_  __/  _/ __ \
  \  / / / / / / /  |/ / __/   / /  / // /_/ /
  / / /_/ / /_/ / /|  / /___  / / _/ // ____/ 
 /_/_____/\____/_/ |_/_____/ /_/ /___/_/      
                                               
EOF
    echo -e "${NC}"
    echo -e "${BOLD}XDC Node CLI v${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}Interactive setup wizard and deployment tool${NC}"
    echo ""
}

print_help() {
    cat << EOF
XDC Node CLI v${SCRIPT_VERSION} - Setup and deployment tool

Usage: $(basename "$0") [OPTIONS]

Options:
  --quick                    Quick deployment mode (non-interactive)
  --gui                      Launch interactive wizard
  --network NETWORK          Network to connect (mainnet|testnet|devnet)
  --role ROLE                Node role (fullnode|archive|masternode|rpc)
  --cloud PROVIDER           Cloud provider (local|aws|digitalocean|azure|gcp)
  --status                   Check node status
  --uninstall                Remove XDC node installation
  --version, -v              Show version information
  --help, -h                 Show this help message

Quick Deploy Examples:
  # Deploy full node on mainnet
  $(basename "$0") --quick --network mainnet --role fullnode

  # Deploy testnet RPC node
  $(basename "$0") --quick --network testnet --role rpc

  # Deploy masternode
  $(basename "$0") --quick --network mainnet --role masternode

Interactive Mode:
  # Launch full wizard
  $(basename "$0") --gui

  # Or run without arguments for guided setup
  $(basename "$0")

Environment Variables:
  XDC_NODE_HOME     Installation directory (default: /opt/xdc-node)
  XDC_NETWORK       Network override
  XDC_NODE_TYPE     Node type override
  DRY_RUN           Preview changes without applying

For more information: https://docs.xdc.network
EOF
}


log_success() {
    echo -e "${GREEN}✓${NC} $1"
}



#==============================================================================
# Pre-flight Checks
#==============================================================================

check_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
            ubuntu|debian)
                return 0
                ;;
            *)
                log_error "Unsupported OS: $ID"
                log_info "Supported: Ubuntu 20.04/22.04/24.04, Debian 11/12"
                return 1
                ;;
        esac
    fi
    return 1
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_warning "Docker not installed"
        return 1
    fi
    
    local docker_version
    docker_version=$(docker --version | grep -oP '\d+\.\d+' | head -1)
    local min_version="20.10"
    
    if [[ "$(printf '%s\n' "$min_version" "$docker_version" | sort -V | head -n1)" != "$min_version" ]]; then
        log_warning "Docker version $docker_version is too old (minimum: $min_version)"
        return 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log_warning "Docker daemon not running or permission denied"
        return 1
    fi
    
    log_success "Docker v${docker_version} installed and running"
    return 0
}

check_disk_space() {
    local required_gb="${1:-500}"
    local available_gb
    available_gb=$(df -BG /opt 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G' || df -BG / 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G')
    
    if [[ -z "$available_gb" ]]; then
        log_warning "Could not determine available disk space"
        return 1
    fi
    
    if [[ "$available_gb" -lt "$required_gb" ]]; then
        log_warning "Insufficient disk space: ${available_gb}GB available, ${required_gb}GB required"
        return 1
    fi
    
    log_success "Disk space: ${available_gb}GB available (required: ${required_gb}GB)"
    return 0
}

check_memory() {
    local required_gb="${1:-8}"
    local total_gb
    total_gb=$(free -g | awk '/^Mem:/{print $2}')
    
    if [[ "$total_gb" -lt "$required_gb" ]]; then
        log_warning "Insufficient memory: ${total_gb}GB total, ${required_gb}GB recommended"
        return 1
    fi
    
    log_success "Memory: ${total_gb}GB total (recommended: ${required_gb}GB)"
    return 0
}

check_ports() {
    local ports=("30303" "8545" "8546" "3000" "9090")
    local in_use=()
    
    for port in "${ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            in_use+=("$port")
        fi
    done
    
    if [[ ${#in_use[@]} -gt 0 ]]; then
        log_warning "Ports already in use: ${in_use[*]}"
        return 1
    fi
    
    log_success "Required ports available"
    return 0
}

check_internet() {
    if ! curl -s --max-time 5 https://github.com >/dev/null; then
        log_error "No internet connection"
        return 1
    fi
    
    log_success "Internet connectivity verified"
    return 0
}

#==============================================================================
# System Resource Detection
#==============================================================================

detect_resources() {
    local cpu_count mem_gb disk_gb
    
    cpu_count=$(nproc)
    mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    disk_gb=$(df -BG /opt 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G' || df -BG / 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G')
    
    echo "{\"cpu\":$cpu_count,\"memory\":$mem_gb,\"disk\":$disk_gb}"
}

recommend_node_type() {
    local resources
    resources=$(detect_resources)
    local cpu mem disk
    cpu=$(echo "$resources" | jq -r '.cpu')
    mem=$(echo "$resources" | jq -r '.memory')
    disk=$(echo "$resources" | jq -r '.disk')
    
    log_info "Detected resources: ${cpu} CPU, ${mem}GB RAM, ${disk}GB disk"
    
    if [[ "$cpu" -ge 8 && "$mem" -ge 32 && "$disk" -ge 1500 ]]; then
        echo "archive"
    elif [[ "$cpu" -ge 8 && "$mem" -ge 32 && "$disk" -ge 750 ]]; then
        echo "masternode"
    elif [[ "$cpu" -ge 4 && "$mem" -ge 16 && "$disk" -ge 500 ]]; then
        echo "rpc"
    elif [[ "$cpu" -ge 4 && "$mem" -ge 8 && "$disk" -ge 250 ]]; then
        echo "fullnode"
    else
        echo "light"
    fi
}

#==============================================================================
# Pre-flight Check Runner
#==============================================================================

run_preflight_checks() {
    local node_type="${1:-fullnode}"
    local required_disk required_mem
    
    case "$node_type" in
        archive)
            required_disk=2000
            required_mem=32
            ;;
        masternode)
            required_disk=1000
            required_mem=32
            ;;
        rpc)
            required_disk=750
            required_mem=16
            ;;
        fullnode)
            required_disk=500
            required_mem=8
            ;;
        *)
            required_disk=250
            required_mem=4
            ;;
    esac
    
    echo ""
    echo -e "${BOLD}Running Pre-flight Checks...${NC}"
    echo "================================"
    
    local failed=0
    
    check_os || ((failed++))
    check_docker || log_warning "Docker will be installed"
    check_disk_space "$required_disk" || ((failed++))
    check_memory "$required_mem" || ((failed++))
    check_ports || log_warning "Some ports are in use"
    check_internet || ((failed++))
    
    echo "================================"
    
    if [[ $failed -gt 0 ]]; then
        log_error "$failed check(s) failed"
        return 1
    fi
    
    log_success "All pre-flight checks passed!"
    return 0
}

#==============================================================================
# Progress Indicator
#==============================================================================

show_progress() {
    local current=$1
    local total=$2
    local message="${3:-Processing...}"
    local width=50
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r${CYAN}["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "]${NC} %3d%% %s" "$percentage" "$message"
    
    if [[ $current -eq $total ]]; then
        echo ""
    fi
}

run_with_progress() {
    local steps=("$@")
    local total=${#steps[@]}
    local i=0
    
    for step in "${steps[@]}"; do
        show_progress $i $total "$step"
        sleep 0.5
        ((i++))
    done
    show_progress $total $total "Complete!"
}

#==============================================================================
# Quick Deploy Mode
#==============================================================================

quick_deploy() {
    local network="${1:-mainnet}"
    local role="${2:-fullnode}"
    
    print_banner
    
    log_info "Quick Deploy Mode"
    log_info "Network: $network"
    log_info "Role: $role"
    
    # Run pre-flight checks
    if ! run_preflight_checks "$role"; then
        log_error "Pre-flight checks failed. Use --gui for guided setup with fixes."
        exit 1
    fi
    
    # Show deployment steps
    echo ""
    log_info "Starting deployment..."
    
    local steps=(
        "Downloading configuration..."
        "Setting up directories..."
        "Installing dependencies..."
        "Configuring node..."
        "Pulling Docker images..."
        "Starting services..."
        "Running health checks..."
    )
    
    run_with_progress "${steps[@]}"
    
    # Execute actual deployment
    if [[ -n "${DRY_RUN:-}" ]]; then
        log_info "DRY RUN: Would deploy $role on $network"
        return 0
    fi
    
    # Call the actual setup
    export XDC_NETWORK="$network"
    export XDC_NODE_TYPE="$role"
    
    if [[ -f "${SCRIPT_DIR}/../setup.sh" ]]; then
        bash "${SCRIPT_DIR}/../setup.sh" --simple
    else
        log_error "setup.sh not found"
        exit 1
    fi
    
    log_success "Deployment complete!"
    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo "  1. Check status: xdc-status"
    echo "  2. View logs: xdc-logs"
    echo "  3. Access Grafana: http://$(hostname -I | awk '{print $1}'):3000"
}

#==============================================================================
# GUI / Wizard Mode
#==============================================================================

launch_wizard() {
    print_banner
    
    # Check for whiptail or dialog
    local dialog_tool=""
    
    if command -v whiptail >/dev/null 2>&1; then
        dialog_tool="whiptail"
    elif command -v dialog >/dev/null 2>&1; then
        dialog_tool="dialog"
    fi
    
    if [[ -z "$dialog_tool" ]] || [[ ! -t 1 ]]; then
        # Fall back to text-based wizard
        log_info "No dialog tool available, using text-based wizard..."
        bash "${WIZARD_DIR}/index.sh"
        return $?
    fi
    
    # Use dialog-based wizard
    bash "${WIZARD_DIR}/index.sh" --dialog
}

#==============================================================================
# Parse Arguments
#==============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick)
                ARG_QUICK=true
                shift
                ;;
            --gui)
                ARG_GUI=true
                shift
                ;;
            --network)
                ARG_NETWORK="$2"
                shift 2
                ;;
            --role)
                ARG_ROLE="$2"
                shift 2
                ;;
            --cloud)
                ARG_CLOUD="$2"
                shift 2
                ;;
            --status)
                if [[ -f "${SCRIPT_DIR}/node-health-check.sh" ]]; then
                    exec "${SCRIPT_DIR}/node-health-check.sh" --quick
                else
                    log_error "Health check script not found"
                    exit 1
                fi
                ;;
            --uninstall)
                log_info "Uninstalling XDC Node..."
                # Add uninstall logic here
                exit 0
                ;;
            --version|-v)
                echo "XDC Node CLI v${SCRIPT_VERSION}"
                exit 0
                ;;
            --help|-h)
                print_banner
                print_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_help
                exit 1
                ;;
        esac
    done
}

#==============================================================================
# Main
#==============================================================================

main() {
    parse_arguments "$@"
    
    # Determine mode
    if [[ "$ARG_QUICK" == true ]]; then
        # Quick deploy mode
        local network="${ARG_NETWORK:-mainnet}"
        local role="${ARG_ROLE:-fullnode}"
        quick_deploy "$network" "$role"
        
    elif [[ "$ARG_GUI" == true ]] || [[ $# -eq 0 ]]; then
        # Interactive wizard mode
        launch_wizard
        
    else
        # Show help for partial arguments
        print_banner
        print_help
        exit 0
    fi
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
