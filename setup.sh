#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDC Node Setup Script
# Production-ready XDC Network node deployment toolkit
# Supports: Linux (Ubuntu/Debian/CentOS/RHEL), macOS, and WSL2
# Modes: Simple (default) and Advanced (--advanced)
#==============================================================================

# Script metadata
readonly SCRIPT_VERSION="2.2.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source cross-platform utilities
# shellcheck source=scripts/lib/utils.sh
source "${SCRIPT_DIR}/scripts/lib/utils.sh" || {
    echo "ERROR: Failed to load utilities from scripts/lib/utils.sh" >&2
    exit 1
}

# Ensure OS is set
if [[ -z "${OS:-}" ]]; then
    readonly OS=$(detect_os)
fi

#==============================================================================
# Docker Environment Detection
#==============================================================================
# Issue: Snap-installed Docker has sandboxing that prevents access to /tmp
# and other paths. Detect and warn, or use alternative docker binary.
detect_docker_environment() {
    local docker_bin
    docker_bin=$(command -v docker 2>/dev/null || true)
    
    if [[ -n "$docker_bin" && "$docker_bin" == /snap/* ]]; then
        echo "WARNING: Snap Docker detected at $docker_bin" >&2
        echo "WARNING: Snap sandboxing may prevent compose from finding files in /tmp" >&2
        echo "INFO: Workarounds:" >&2
        echo "  1. Install Docker from official repo (not snap): https://docs.docker.com/engine/install/" >&2
        echo "  2. Run setup from a non-snap path like /opt or /var/lib" >&2
        echo "  3. Use sudo snap remove docker && install via apt" >&2
        
        # Check if we can find a non-snap docker
        if [[ -x /usr/bin/docker ]]; then
            echo "INFO: Found non-snap Docker at /usr/bin/docker — will prefer this" >&2
            export DOCKER_BIN="/usr/bin/docker"
        else
            export DOCKER_BIN="$docker_bin"
        fi
    else
        export DOCKER_BIN="${docker_bin:-docker}"
    fi
    
    # Also check for docker-compose binary
    if command -v docker-compose &>/dev/null; then
        export DOCKER_COMPOSE_BIN="$(command -v docker-compose)"
        export DOCKER_COMPOSE_USE_ARRAY=false
    else
        export DOCKER_COMPOSE_BIN="${DOCKER_BIN}"
        export DOCKER_COMPOSE_ARGS="compose"
        export DOCKER_COMPOSE_USE_ARRAY=true
    fi
}

# Run detection early
detect_docker_environment

#==============================================================================
# Colors & UI
#==============================================================================
# Set OS-specific paths
# Project root is the directory containing setup.sh (repo root), NOT where it's called from
readonly PROJECT_ROOT="${SCRIPT_DIR}"
readonly LOG_FILE="${PROJECT_ROOT}/xdc-node-setup.log"

#==============================================================================
# Colors & UI
#==============================================================================
# Guard to prevent "readonly variable" error if colors already defined (e.g., from utils.sh)
if ! declare -p RED &>/dev/null; then
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
fi

#==============================================================================
# Logging
#==============================================================================
init_logging() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if [[ "$OS" == "linux" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || true
        touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/xdc-node-setup.log"
    else
        mkdir -p "$log_dir"
        touch "$LOG_FILE"
    fi
    chmod 640 "$LOG_FILE" 2>/dev/null || true
}

# Issue #547 & #552: Ensure path is a file, not a directory
# Docker creates directories for missing volume mount sources
ensure_file_path() {
    local f="$1"
    if [[ -d "$f" ]]; then
        echo "  Removing directory: $f (Docker will mount this as file)"
        rm -rf "$f"
    fi
    mkdir -p "$(dirname "$f")"
    # Actually create the file to prevent Docker from creating it as a directory
    if [[ ! -f "$f" ]]; then
        touch "$f"
    fi
}

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${GREEN}✓${NC} $1" | sed 's/\\033\[[0-9;]*m//g' >> "$LOG_FILE" 2>/dev/null || true
    echo -e "${GREEN}✓${NC} $1"
}

info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1"
    echo -e "$msg" | sed 's/\\033\[[0-9;]*m//g' >> "$LOG_FILE" 2>/dev/null || true
    echo -e "${BLUE}ℹ${NC} $1"
}

warn() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1"
    echo -e "$msg" | sed 's/\\033\[[0-9;]*m//g' >> "$LOG_FILE" 2>/dev/null || true
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"
    echo -e "$msg" | sed 's/\\033\[[0-9;]*m//g' >> "$LOG_FILE" 2>/dev/null || true
    echo -e "${RED}✗${NC} $1" >&2
}

fatal() {
    error "$1"
    exit 1
}

#==============================================================================
# Spinner for long operations
#==============================================================================
spinner() {
    local pid=$1
    local message="${2:-Processing...}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r${CYAN}%s${NC} %s" "${spin:$i:1}" "$message"
        sleep 0.1
    done
    printf "\r%-50s\r" ""
    tput cnorm 2>/dev/null || true
}

run_with_spinner() {
    local message="$1"
    shift
    "$@" > /dev/null 2>&1 &
    local pid=$!
    spinner "$pid" "$message"
    wait "$pid" 2>/dev/null || return $?
}

#==============================================================================
# Banner
#==============================================================================
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'

    ██╗  ██╗██████╗  ██████╗    ███╗   ██╗ ██████╗ ██████╗ ███████╗
    ╚██╗██╔╝██╔══██╗██╔════╝    ████╗  ██║██╔═══██╗██╔══██╗██╔════╝
     ╚███╔╝ ██║  ██║██║         ██╔██╗ ██║██║   ██║██║  ██║█████╗  
     ██╔██╗ ██║  ██║██║         ██║╚██╗██║██║   ██║██║  ██║██╔══╝  
    ██╔╝ ██╗██████╔╝╚██████╗    ██║ ╚████║╚██████╔╝██████╔╝███████╗
    ╚═╝  ╚═╝╚═════╝  ╚═════╝    ╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝

EOF
    echo -e "${NC}"
    echo -e "${BOLD}XDC Node Setup v${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}Production-ready XDC Network node deployment${NC}"
    echo ""
}

show_help() {
    cat << EOF
XDC Node Setup - Production-ready XDC Network node deployment

Usage: $(basename "$0") [OPTIONS]

Options:
  --simple            Run in simple mode (default, minimal prompts)
  --advanced          Run in advanced mode (interactive prompts)
  --email EMAIL       Email for SkyNet alerts (optional)
  --tg, --telegram    Telegram handle for SkyNet alerts (optional)
  --client CLIENT     Client type: xdc, geth (default: xdc)
  --type TYPE         Node type: full, archive, masternode (default: full)
  --network NETWORK   Network: mainnet, testnet, devnet, apothem (default: mainnet)
  --status            Check current installation status
  --uninstall         Remove XDC node and all configurations
  --help, -h          Show this help message
  --version, -v       Show version information

Environment Variables:
  NODE_TYPE           Node type: full, archive, rpc, masternode (default: full)
  NETWORK             Network: mainnet, testnet (default: mainnet)
  DATA_DIR            Data directory (default: /root/xdcchain or ~/xdcchain)
  RPC_PORT            RPC port (default: 9545)
  P2P_PORT            P2P port (default: 30303)
  SYNC_MODE           Sync mode: full, snap (default: full)
  ENABLE_MONITORING   Enable monitoring (Prometheus/Grafana): true/false (default: false)
  ENABLE_SKYNET       Enable SkyNet fleet monitoring: true/false (default: false)
  ENABLE_SECURITY     Enable security hardening: true/false (default: true)
  ENABLE_UPDATES      Enable auto-updates: true/false (default: true)
  HTTP_PROXY          HTTP proxy URL
  HTTPS_PROXY         HTTPS proxy URL

Examples:
  # Simple mode (default)
  curl -sSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/setup.sh | sudo bash

  # With SkyNet registration (email + Telegram alerts)
  curl -sSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/setup.sh | sudo bash -s -- --email anil@xinfin.org --tg @anilchinchawale

  # Advanced mode with all options
  sudo ./setup.sh --advanced --email alerts@example.com --type archive

  # Enable Prometheus/Grafana monitoring
  sudo ./setup.sh --advanced  # then select monitoring when prompted
  # OR set ENABLE_MONITORING=true

  # Check status
  sudo ./setup.sh --status

  # Uninstall
  sudo ./setup.sh --uninstall

Documentation: https://github.com/AnilChinchawale/xdc-node-setup/docs
EOF
}

#==============================================================================
# System Checks
#==============================================================================
check_root() {
    if [[ "$OS" == "linux" && $EUID -ne 0 ]]; then
        fatal "This script must be run as root on Linux. Try: sudo $0"
    fi
}

check_os_compatibility() {
    case "$OS" in
        linux|wsl2)
            if [[ -f /etc/os-release ]]; then
                # shellcheck source=/dev/null
                source /etc/os-release
                case "$ID" in
                    ubuntu)
                        local version
                        version=$(echo "$VERSION_ID" | cut -d. -f1)
                        if [[ "$version" -ge 20 ]]; then
                            log "Detected Ubuntu $VERSION_ID (supported)"
                            [[ "$OS" == "wsl2" ]] && info "Running on WSL2"
                            return 0
                        fi
                        ;;
                    debian)
                        local version
                        version=$(echo "$VERSION_ID" | cut -d. -f1)
                        if [[ "$version" -ge 11 ]]; then
                            log "Detected Debian $VERSION_ID (supported)"
                            return 0
                        fi
                        ;;
                    centos|rhel|fedora|rocky|almalinux)
                        log "Detected $NAME (supported)"
                        warn "CentOS/RHEL/Fedora support is experimental"
                        return 0
                        ;;
                esac
            fi
            warn "Unsupported Linux distribution. Ubuntu 20.04+/Debian 11+ recommended."
            ;;
        macos)
            local mac_version
            mac_version=$(sw_vers -productVersion | cut -d. -f1-2)
            log "Detected macOS $mac_version"
            info "Note: Docker Desktop is required on macOS"
            ;;
        windows)
            fatal "Windows is not directly supported. Please use WSL2 with Docker Desktop."
            ;;
        *)
            fatal "Unsupported operating system: $OSTYPE"
            ;;
    esac
}

check_hardware() {
    info "Checking hardware requirements..."
    
    local cpu_cores ram_gb disk_gb
    
    if [[ "$OS" == "macos" ]]; then
        cpu_cores=$(sysctl -n hw.ncpu)
        ram_gb=$(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))
        disk_gb=$(($(df -k "$HOME" | awk 'NR==2 {print $4}') / 1024 / 1024))
    else
        cpu_cores=$(nproc)
        ram_gb=$(free -g | awk '/^Mem:/{print $2}')
        disk_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    fi
    
    echo -e "  ${BLUE}CPU Cores:${NC} $cpu_cores"
    echo -e "  ${BLUE}RAM:${NC} ${ram_gb}GB"
    echo -e "  ${BLUE}Disk Available:${NC} ${disk_gb}GB"
    
    # Check minimums
    local warnings=0
    
    if [[ $cpu_cores -lt 4 ]]; then
        warn "Minimum 4 CPU cores recommended (found: $cpu_cores)"
        warnings=$((warnings + 1))
    fi
    
    if [[ $ram_gb -lt 16 ]]; then
        warn "Minimum 16GB RAM recommended (found: ${ram_gb}GB)"
        warnings=$((warnings + 1))
    fi
    
    if [[ $disk_gb -lt 500 ]]; then
        warn "Minimum 500GB disk space recommended (found: ${disk_gb}GB)"
        warnings=$((warnings + 1))
    fi
    
    if [[ $warnings -gt 0 ]]; then
        warn "Hardware does not meet recommended specs — node may run slowly"
        warn "Proceeding with setup anyway..."
        sleep 2
    fi
    
    log "Hardware check complete"
}

check_docker() {
    if command -v docker &> /dev/null; then
        if docker info &> /dev/null; then
            return 0
        fi
    fi
    return 1
}

#==============================================================================
# Docker Installation
#==============================================================================
install_docker_linux() {
    log "Installing Docker on Linux..."
    
    # Respect proxy settings
    local env_vars=""
    [[ -n "${HTTP_PROXY:-}" ]] && env_vars="$env_vars -e HTTP_PROXY=$HTTP_PROXY"
    [[ -n "${HTTPS_PROXY:-}" ]] && env_vars="$env_vars -e HTTPS_PROXY=$HTTPS_PROXY"
    
    # Install dependencies
    apt-get update -qq
    apt-get install -y -qq \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common
    
    # Add Docker GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || \
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start Docker
    systemctl enable docker
    systemctl start docker
    
    # Add user to docker group if not root
    if [[ -n "${SUDO_USER:-}" ]]; then
        usermod -aG docker "$SUDO_USER" 2>/dev/null || true
    fi
    
    log "Docker installed successfully"
}

check_docker_macos() {
    if ! command -v docker &> /dev/null; then
        fatal "Docker Desktop is required on macOS. Please install from https://www.docker.com/products/docker-desktop"
    fi
    
    if ! docker info &> /dev/null; then
        fatal "Docker Desktop is installed but not running. Please start Docker Desktop."
    fi
    
    log "Docker Desktop detected and running"
}

install_docker() {
    if check_docker; then
        log "Docker already installed"
        return 0
    fi
    
    if [[ "$OS" == "macos" ]]; then
        check_docker_macos
    else
        install_docker_linux
    fi
}

#==============================================================================
# Dependencies
#==============================================================================
install_dependencies() {
    log "Installing dependencies..."
    
    if [[ "$OS" == "macos" ]]; then
        # macOS dependencies
        if ! command -v brew &> /dev/null; then
            fatal "Homebrew is required. Install from https://brew.sh"
        fi
        
        local deps=(jq curl wget)
        for dep in "${deps[@]}"; do
            if ! command -v "$dep" &> /dev/null; then
                brew install "$dep" 2>/dev/null || warn "Failed to install $dep"
            fi
        done
    else
        # Linux dependencies
        apt-get update -qq
        apt-get install -y -qq \
            curl \
            wget \
            jq \
            git \
            htop \
            logrotate \
            rsync \
            ufw \
            fail2ban \
            2>/dev/null || true
    fi
    
    log "Dependencies installed"
}

#==============================================================================
# Configuration Variables (with defaults)
#==============================================================================
find_free_port() {
    local port="$1"
    local max_tries=10
    local i=0
    while [ $i -lt $max_tries ]; do
        if ! ss -tlnH "sport = :$port" 2>/dev/null | grep -q ":$port" && \
           ! docker ps --format '{{.Ports}}' 2>/dev/null | grep -q "0.0.0.0:$port->"; then
            echo "$port"
            return 0
        fi
        port=$((port + 1))
        i=$((i + 1))
    done
    echo "$1"  # fallback to original
}

init_config() {
    # Node configuration with environment variable overrides
    NODE_TYPE="${NODE_TYPE:-full}"
    NETWORK="${NETWORK:-mainnet}"
    CLIENT="${CLIENT:-stable}"  # Preserves value set by --client flag
    SYNC_MODE="${SYNC_MODE:-full}"
    RPC_PORT="${RPC_PORT:-9545}"
    P2P_PORT="${P2P_PORT:-30303}"
    WS_PORT="${WS_PORT:-8546}"
    DASHBOARD_PORT="${DASHBOARD_PORT:-7070}"

    # ERIGON-specific ports (for multi-client mode)
    ERIGON_RPC_PORT="${ERIGON_RPC_PORT:-8547}"
    ERIGON_AUTHRPC_PORT="${ERIGON_AUTHRPC_PORT:-8561}"
    ERIGON_P2P_PORT="${ERIGON_P2P_PORT:-30304}"
    ERIGON_P2P_PORT_68="${ERIGON_P2P_PORT_68:-30311}"
    ERIGON_DASHBOARD_PORT="${ERIGON_DASHBOARD_PORT:-7071}"

    # NETHERMIND-specific ports (for multi-client mode)
    NETHERMIND_RPC_PORT="${NETHERMIND_RPC_PORT:-8556}"
    NETHERMIND_P2P_PORT="${NETHERMIND_P2P_PORT:-30306}"
    NETHERMIND_DASHBOARD_PORT="${NETHERMIND_DASHBOARD_PORT:-7072}"

    # Auto-resolve port conflicts
    RPC_PORT=$(find_free_port "$RPC_PORT")
    P2P_PORT=$(find_free_port "$P2P_PORT")
    WS_PORT=$(find_free_port "$WS_PORT")
    DASHBOARD_PORT=$(find_free_port "$DASHBOARD_PORT")
    
    # Derive paths from NETWORK and PROJECT_ROOT
    DATA_DIR="${DATA_DIR:-${PROJECT_ROOT}/${NETWORK}/xdcchain}"
    STATE_DIR="${PROJECT_ROOT}/${NETWORK}/.xdc-node"
    CONFIG_DIR="${PROJECT_ROOT}/configs"
    
    # Feature flags
    ENABLE_MONITORING="${ENABLE_MONITORING:-false}"
    ENABLE_SKYNET="${ENABLE_SKYNET:-false}"
    ENABLE_SECURITY="${ENABLE_SECURITY:-true}"
    ENABLE_NOTIFICATIONS="${ENABLE_NOTIFICATIONS:-false}"
    ENABLE_UPDATES="${ENABLE_UPDATES:-true}"
    INSTALL_CLI="${INSTALL_CLI:-true}"
    
    # Chain ID based on network
    case "${NETWORK:-mainnet}" in
        mainnet)
            CHAIN_ID=50
            ;;
        testnet|apothem)
            CHAIN_ID=51
            ;;
        devnet)
            CHAIN_ID=551
            ;;
        *)
            CHAIN_ID=50
            ;;
    esac

    # Apothem testnet flag configuration
    if [[ "$NETWORK" == "apothem" || "$NETWORK" == "testnet" ]]; then
        APOTHEM_FLAG="--apothem"
        NETWORK_ID=51
        ETHSTATS_FLAG=" "  # No ethstats for apothem (space = skip default)
    else
        APOTHEM_FLAG=""
        NETWORK_ID=${CHAIN_ID:-50}
        ETHSTATS_FLAG=""  # Empty = use default ethstats
    fi
}

#==============================================================================
# Interactive Prompts (Advanced Mode)
#==============================================================================
prompt_network() {
    echo ""
    echo -e "${BOLD}Network Selection${NC}"
    echo "===================="
    echo "1) Mainnet (XDC Network - Production) - Chain ID: 50"
    echo "2) Testnet (Apothem - Development) - Chain ID: 51"
    echo "3) Devnet (Local Development) - Chain ID: 551"
    echo ""
    
    while true; do
        read -rp "Select network [1-3] (default: 1): " choice
        choice=${choice:-1}
        case $choice in
            1) NETWORK="mainnet"; CHAIN_ID=50; break ;;
            2) NETWORK="testnet"; CHAIN_ID=51; break ;;
            3) NETWORK="devnet"; CHAIN_ID=551; break ;;
            *) echo "Invalid selection. Please choose 1-3." ;;
        esac
    done
    
    log "Selected network: $NETWORK (Chain ID: $CHAIN_ID)"
}

prompt_node_type() {
    echo ""
    echo -e "${BOLD}Node Type Selection${NC}"
    echo "======================"
    echo "1) Full Node - Standard full node (recommended, ~500GB)"
    echo "2) Archive Node - Complete blockchain history (~4TB)"
    echo "3) RPC Node - Optimized for RPC requests"
    echo "4) Masternode - XDC Network validator node"
    echo ""
    
    while true; do
        read -rp "Select node type [1-4] (default: 1): " choice
        choice=${choice:-1}
        case $choice in
            1) NODE_TYPE="full"; break ;;
            2) NODE_TYPE="archive"; break ;;
            3) NODE_TYPE="rpc"; break ;;
            4) NODE_TYPE="masternode"; break ;;
            *) echo "Invalid selection. Please choose 1-4." ;;
        esac
    done
    
    log "Selected node type: $NODE_TYPE"
}

prompt_client() {
    echo ""
    echo -e "${BOLD}Client Selection${NC}"
    echo "================="
    echo "1) XDC Stable (v2.6.8) - Official Docker image (recommended)"
    echo "2) XDC Geth PR5 - Latest geth with XDPoS (Docker Hub: anilchinchawale/gx)"
    echo "3) Erigon-XDC - Multi-client diversity (Docker Hub: anilchinchawale/erix)"
    echo "4) Nethermind-XDC - .NET-based client (Docker Hub: anilchinchawale/nmx)"
    echo "5) All Clients - Run all 4 clients simultaneously"
    echo ""
    echo -e "${YELLOW}Note: Clients 2-4 use pre-built Docker Hub images — no compilation needed${NC}"
    echo ""
    
    while true; do
        read -rp "Select client [1-4] (default: 1): " choice
        choice=${choice:-1}
        case $choice in
            1) CLIENT="stable"; break ;;
            2) CLIENT="geth-pr5"; break ;;
            3) CLIENT="erigon"; break ;;
            4) CLIENT="nethermind"; break ;;
            5) CLIENT="all"; break ;;
            *) echo "Invalid selection. Please choose 1-5." ;;
        esac
    done
    
    log "Selected client: $CLIENT"
}

prompt_sync_mode() {
    echo ""
    echo -e "${BOLD}Sync Mode Selection${NC}"
    echo "======================"
    echo "1) Full Sync - Complete verification (slower, most secure)"
    echo "2) Snap Sync - Fast snapshot sync (faster, recommended)"
    echo ""
    
    while true; do
        read -rp "Select sync mode [1-2] (default: 2): " choice
        choice=${choice:-2}
        case $choice in
            1) SYNC_MODE="full"; break ;;
            2) SYNC_MODE="snap"; break ;;
            *) echo "Invalid selection. Please choose 1-2." ;;
        esac
    done
    
    log "Selected sync mode: $SYNC_MODE"
}

prompt_data_dir() {
    echo ""
    echo -e "${BOLD}Data Directory${NC}"
    echo "==============="
    local default_data_dir="${PROJECT_ROOT}/${NETWORK}/xdcchain"
    read -rp "Data directory [$default_data_dir]: " input
    DATA_DIR="${input:-$default_data_dir}"
    log "Data directory: $DATA_DIR"
}

prompt_ports() {
    echo ""
    echo -e "${BOLD}Port Configuration${NC}"
    echo "==================="
    
    read -rp "RPC port [9545]: " input
    RPC_PORT="${input:-9545}"
    
    read -rp "P2P port [30303]: " input
    P2P_PORT="${input:-30303}"
    
    log "RPC port: $RPC_PORT, P2P port: $P2P_PORT"
}

prompt_features() {
    echo ""
    echo -e "${BOLD}Feature Configuration${NC}"
    echo "======================"
    
    read -rp "Enable monitoring (Grafana + Prometheus)? [y/N]: " input
    [[ "${input:-N}" =~ ^[Yy]$ ]] && ENABLE_MONITORING="true" || ENABLE_MONITORING="false"
    
    read -rp "Enable SkyNet fleet monitoring? [y/N]: " input
    [[ "${input:-N}" =~ ^[Yy]$ ]] && ENABLE_SKYNET="true" || ENABLE_SKYNET="false"
    
    if [[ "$OS" == "linux" ]]; then
        read -rp "Enable security hardening (SSH, UFW, fail2ban)? [Y/n]: " input
        [[ ! "${input:-Y}" =~ ^[Nn]$ ]] && ENABLE_SECURITY="true" || ENABLE_SECURITY="false"
    fi
    
    read -rp "Enable notifications? [y/N]: " input
    [[ "${input:-N}" =~ ^[Yy]$ ]] && ENABLE_NOTIFICATIONS="true" || ENABLE_NOTIFICATIONS="false"
    
    read -rp "Enable auto-updates? [Y/n]: " input
    [[ ! "${input:-Y}" =~ ^[Nn]$ ]] && ENABLE_UPDATES="true" || ENABLE_UPDATES="false"
    
    read -rp "Install CLI tool (xdc-node)? [Y/n]: " input
    [[ ! "${input:-Y}" =~ ^[Nn]$ ]] && INSTALL_CLI="true" || INSTALL_CLI="false"
    
    log "Monitoring: $ENABLE_MONITORING, SkyNet: $ENABLE_SKYNET, Security: $ENABLE_SECURITY, Notifications: $ENABLE_NOTIFICATIONS, Updates: $ENABLE_UPDATES, CLI: $INSTALL_CLI"
}

prompt_advanced() {
    echo ""
    echo -e "${CYAN}${BOLD}Advanced Mode${NC} - Configure your XDC node"
    echo ""
    
    prompt_network
    prompt_node_type
    prompt_client
    prompt_sync_mode
    prompt_data_dir
    prompt_ports
    prompt_features
}

#==============================================================================
# Node Configuration
#==============================================================================
configure_node() {
    log "Configuring XDC node..."
    
    # Create directory structure only for the selected network
    mkdir -p "${PROJECT_ROOT}/${NETWORK}/xdcchain"/{XDC,keystore}
    mkdir -p "${PROJECT_ROOT}/${NETWORK}/.xdc-node/logs"
    mkdir -p "${PROJECT_ROOT}"/{configs,scripts,logs}
    
    # Set permissions
    chmod 750 "$DATA_DIR"
    chmod 700 "$DATA_DIR/keystore" 2>/dev/null || true
    
    # Create environment file
    ensure_file_path "$STATE_DIR/node.env"
    cat > "$STATE_DIR/node.env" << EOF
# XDC Node Configuration
# Generated on $(date)
NETWORK=$NETWORK
CHAIN_ID=$CHAIN_ID
NODE_TYPE=$NODE_TYPE
CLIENT=$CLIENT
SYNC_MODE=$SYNC_MODE
DATA_DIR=$DATA_DIR
STATE_DIR=$STATE_DIR
CONFIG_DIR=$CONFIG_DIR
RPC_PORT=$RPC_PORT
WS_PORT=$WS_PORT
P2P_PORT=$P2P_PORT
ENABLE_MONITORING=$ENABLE_MONITORING
ENABLE_SECURITY=$ENABLE_SECURITY
ENABLE_NOTIFICATIONS=$ENABLE_NOTIFICATIONS
ENABLE_UPDATES=$ENABLE_UPDATES
EOF
    
    chmod 600 "$STATE_DIR/node.env"
    
    # Create client.conf for CLI to detect client type
    ensure_file_path "$STATE_DIR/client.conf"
    cat > "$STATE_DIR/client.conf" << EOF
# XDC Client Configuration
# Generated on $(date)
CLIENT=$CLIENT
EOF
    chmod 600 "$STATE_DIR/client.conf"
    
    log "Node configuration saved (client: $CLIENT)"
}

#==============================================================================
# Generate config.toml
#==============================================================================
generate_config_toml() {
    log "Generating config.toml..."
    
    local config_toml="$STATE_DIR/config.toml"
    local template="$CONFIG_DIR/config.toml.template"
    
    # Check if template exists
    if [[ ! -f "$template" ]]; then
        warn "config.toml.template not found, skipping TOML generation"
        return 0
    fi
    
    # Set defaults for TOML generation
    local MAX_PEERS="${MAX_PEERS:-25}"
    local CACHE_SIZE="${CACHE_SIZE:-4096}"
    local TRIE_CACHE=$((CACHE_SIZE / 4))
    local DIRTY_CACHE=$((CACHE_SIZE / 4))
    local SNAPSHOT_CACHE=$((CACHE_SIZE / 4))
    local GAS_LIMIT="${GAS_LIMIT:-420000000}"
    local GAS_PRICE="${GAS_PRICE:-1}"
    local METRICS_ENABLED="true"
    local METRICS_PORT="${METRICS_PORT:-6060}"
    local VERBOSITY="${VERBOSITY:-3}"
    
    # Archive nodes don't prune
    local NO_PRUNING="false"
    [[ "$NODE_TYPE" == "archive" ]] && NO_PRUNING="true"
    
    # Load bootnodes based on network
    local BOOTNODES=""
    local bootnode_file="$CONFIG_DIR/bootnodes-${NETWORK}.json"
    if [[ -f "$bootnode_file" ]]; then
        BOOTNODES=$(jq -r '.bootnodes[].enode' "$bootnode_file" 2>/dev/null | sed 's/^/  "/' | sed 's/$/"/' | paste -sd, - || echo "")
    fi
    
    # Fallback to hardcoded mainnet bootnodes if empty
    if [[ -z "$BOOTNODES" && "$NETWORK" == "mainnet" ]]; then
        BOOTNODES='  "enode://9a977b1ac4320fa2c862dcaf536aaaea3a8f8f7cd14e3bcde32e5a1c0152bd17bd18bfdc3c2ca8c4a0f3da153c62935fea1dc040cc1e66d2c07d6b4c91e2ed42@bootnode.xinfin.network:30303"'
    fi
    
    # RPC API modules
    local RPC_API='"admin", "eth", "net", "web3", "XDPoS"'
    local WS_API='"admin", "eth", "net", "web3", "XDPoS"'
    
    # Create config.toml from template
    cp "$template" "$config_toml"
    
    # Replace placeholders
    sed_inplace "s|{{DATA_DIR}}|/work/xdcchain|g" "$config_toml"
    sed_inplace "s|{{CHAIN_ID}}|$CHAIN_ID|g" "$config_toml"
    sed_inplace "s|{{SYNC_MODE}}|$SYNC_MODE|g" "$config_toml"
    sed_inplace "s|{{P2P_PORT}}|$P2P_PORT|g" "$config_toml"
    sed_inplace "s|{{MAX_PEERS}}|$MAX_PEERS|g" "$config_toml"
    sed_inplace "s|{{BOOTNODES}}|$BOOTNODES|g" "$config_toml"
    sed_inplace "s|{{RPC_PORT}}|8545|g" "$config_toml"
    sed_inplace "s|{{RPC_API}}|$RPC_API|g" "$config_toml"
    sed_inplace "s|{{WS_PORT}}|8546|g" "$config_toml"
    sed_inplace "s|{{WS_API}}|$WS_API|g" "$config_toml"
    sed_inplace "s|{{NO_PRUNING}}|$NO_PRUNING|g" "$config_toml"
    sed_inplace "s|{{CACHE_SIZE}}|$CACHE_SIZE|g" "$config_toml"
    sed_inplace "s|{{TRIE_CACHE}}|$TRIE_CACHE|g" "$config_toml"
    sed_inplace "s|{{DIRTY_CACHE}}|$DIRTY_CACHE|g" "$config_toml"
    sed_inplace "s|{{SNAPSHOT_CACHE}}|$SNAPSHOT_CACHE|g" "$config_toml"
    sed_inplace "s|{{GAS_LIMIT}}|$GAS_LIMIT|g" "$config_toml"
    sed_inplace "s|{{GAS_PRICE}}|$GAS_PRICE|g" "$config_toml"
    sed_inplace "s|{{METRICS_ENABLED}}|$METRICS_ENABLED|g" "$config_toml"
    sed_inplace "s|{{METRICS_PORT}}|$METRICS_PORT|g" "$config_toml"
    sed_inplace "s|{{VERBOSITY}}|$VERBOSITY|g" "$config_toml"
    
    chmod 644 "$config_toml"
    log "config.toml generated at $config_toml"
}

#==============================================================================
# Docker Compose Setup
#==============================================================================
setup_docker_compose() {
    log "Setting up Docker Compose..."
    
    mkdir -p "$PROJECT_ROOT/docker"
    
    # Determine Docker image based on platform
    local arch
    arch=$(uname -m)
    local xdc_image="xinfinorg/xdposchain:v2.6.8"
    local platform_flag=""
    if [[ "$arch" == "arm64" || "$arch" == "aarch64" ]]; then
        # Check if ARM image exists, otherwise use platform emulation
        platform_flag="platform: linux/amd64"
        warn "ARM64 detected — using linux/amd64 emulation (may be slower)"
        info "Ensure Docker Desktop has 'Use Rosetta for x86_64/amd64 emulation' enabled"
    fi
    local docker_dir="$PROJECT_ROOT/docker"
    local network_dir="$docker_dir/mainnet"
    
    mkdir -p "$network_dir"
    
    # Download official XDC node files from XinFinOrg
    log "Downloading XDC node configuration files..."
    local base_url="https://raw.githubusercontent.com/XinFinOrg/XinFin-Node/master/mainnet"
    
    # Try multiple sources for config files
    local bundled_dir="$SCRIPT_DIR/docker/mainnet"
    local alt_bundled="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/docker/mainnet"
    local alt_url="https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/docker/mainnet"
    
    for f in genesis.json start-node.sh bootnodes.list; do
        # 1. Try bundled from SCRIPT_DIR
        if [[ -f "$bundled_dir/$f" ]]; then
            [[ "$(realpath "$bundled_dir/$f")" != "$(realpath "$network_dir/$f" 2>/dev/null)" ]] && cp "$bundled_dir/$f" "$network_dir/$f"
            log "Using bundled $f"
        # 2. Try alternate bundled path
        elif [[ -f "$alt_bundled/$f" ]]; then
            [[ "$(realpath "$alt_bundled/$f")" != "$(realpath "$network_dir/$f" 2>/dev/null)" ]] && cp "$alt_bundled/$f" "$network_dir/$f"
            log "Using bundled $f"
        # 3. Try official XinFin URL
        elif curl -fsSL --connect-timeout 15 --retry 2 "$base_url/$f" -o "$network_dir/$f" 2>/dev/null && [[ -s "$network_dir/$f" ]]; then
            log "Downloaded $f from XinFin"
        # 4. Try our repo URL
        elif curl -fsSL --connect-timeout 15 --retry 2 "$alt_url/$f" -o "$network_dir/$f" 2>/dev/null && [[ -s "$network_dir/$f" ]]; then
            log "Downloaded $f from xdc-node-setup"
        else
            # 5. Last resort: generate minimal inline versions
            case "$f" in
                start-node.sh)
                    warn "Generating start-node.sh from inline template..."
                    # Copy the full start-node.sh from bundled docker/mainnet if possible
                    if [[ -f "$SCRIPT_DIR/docker/mainnet/start-node.sh" ]]; then
                        cp "$SCRIPT_DIR/docker/mainnet/start-node.sh" "$network_dir/start-node.sh"
                    else
                        cat > "$network_dir/start-node.sh" << STARTEOF
#!/bin/bash
set -e
for bin in XDC XDC-mainnet XDC-testnet XDC-devnet; do
    command -v "\$bin" &>/dev/null && { [ "\$bin" != "XDC" ] && ln -sf "\$(which "\$bin")" /usr/bin/XDC; break; }
done
command -v XDC &>/dev/null || { echo "FATAL: No XDC binary"; exit 1; }
: "\${SYNC_MODE:=full}" "\${GC_MODE:=full}" "\${LOG_LEVEL:=2}" "\${RPC_ADDR:=0.0.0.0}" "\${RPC_PORT:=8545}"
: "\${RPC_API:=admin,eth,net,web3,XDPoS}" "\${WS_ADDR:=0.0.0.0}" "\${WS_PORT:=8546}"
if [ ! -d /work/xdcchain/XDC/chaindata ]; then
    wallet=\$(XDC account new --password /work/.pwd --datadir /work/xdcchain 2>/dev/null | awk -F '[{}]' '{print \$2}')
    echo "\$wallet" > /work/xdcchain/coinbase.txt
    XDC init --datadir /work/xdcchain /work/genesis.json
else
    wallet=\$(XDC account list --datadir /work/xdcchain 2>/dev/null | head -1 | awk -F '[{}]' '{print \$2}')
fi
bootnodes=""; [ -f /work/bootnodes.list ] && while IFS= read -r l; do [ -z "\$l" ] && continue; [ -z "\$bootnodes" ] && bootnodes="\$l" || bootnodes="\$bootnodes,\$l"; done < /work/bootnodes.list
# Detect flag style
if XDC --help 2>&1 | grep -q '\\-\\-http.addr'; then
    RPC_FLAGS="--http --http.addr \$RPC_ADDR --http.port \$RPC_PORT --http.api \$RPC_API --http.corsdomain * --http.vhosts * --ws --ws.addr \$WS_ADDR --ws.port \$WS_PORT --ws.origins *"
else
    RPC_FLAGS="--rpc --rpcaddr \$RPC_ADDR --rpcport \$RPC_PORT --rpcapi \$RPC_API --rpccorsdomain * --rpcvhosts * --ws --wsaddr \$WS_ADDR --wsport \$WS_PORT --wsorigins *"
fi
exec XDC --datadir /work/xdcchain --networkid \${NETWORK_ID:-50} --port 30303 --syncmode "\$SYNC_MODE" --gcmode "\$GC_MODE" \\
    --verbosity "\$LOG_LEVEL" --password /work/.pwd --mine --gasprice 1 --targetgaslimit 420000000 \\
    \${wallet:+--unlock "\$wallet"} \${bootnodes:+--bootnodes "\$bootnodes"} \\
    \${APOTHEM_FLAG:-} \\
    \${ETHSTATS_FLAG:---ethstats "\${INSTANCE_NAME:-XDC_Node}:\${STATS_SECRET:-xdc_openscan_stats_2026}@\${STATS_SERVER:-stats.xdcindia.com:443}"} \\
    --XDCx.datadir /work/xdcchain/XDCx \$RPC_FLAGS "\$@" 2>&1 | tee -a /work/xdcchain/xdc.log
STARTEOF
                    fi
                    chmod +x "$network_dir/start-node.sh"
                    ;;
                bootnodes.list)
                    warn "Generating bootnodes.list with default XDC bootnodes..."
                    if [[ "$NETWORK" == "apothem" || "$NETWORK" == "testnet" ]]; then
                        cat > "$network_dir/bootnodes.list" << 'BNEOF'
enode://91e59fa1b034ae35e9f4e8a99cc6621f09d74e76a6220abb6c93b29ed41a9e1fc4e5b70e2c5fc43f883cffbdcd6f4f6cbc1d23af077f28c2aecc22403355d4b1@bootnodes.apothem.network:30312
BNEOF
                    else
                        cat > "$network_dir/bootnodes.list" << 'BNEOF'
enode://9a977b1ac4320fa2c862dcaf536aaaea3a8f8f7cd14e3bcde32e5a1c0152bd17bd18bfdc3c2ca8c4a0f3da153c62935fea1dc040cc1e66d2c07d6b4c91e2ed42@bootnode.xinfin.network:30303
BNEOF
                    fi
                    ;;
                *)
                    warn "Failed to get $f from all sources. Place manually in $network_dir/"
                    ;;
            esac
        fi
    done
    chmod +x "$network_dir/start-node.sh" 2>/dev/null || true
    
    # Create entrypoint wrapper that ensures XDC binary exists
    cat > "$docker_dir/entrypoint.sh" << 'ENTRYEOF'
#!/bin/sh
# Ensure XDC binary is available (image may have XDC-mainnet instead)
if ! command -v XDC >/dev/null 2>&1; then
    for bin in XDC-mainnet XDC-testnet XDC-devnet XDC-local; do
        if command -v "$bin" >/dev/null 2>&1; then
            ln -sf "$(which "$bin")" /usr/bin/XDC
            echo "Linked $bin → /usr/bin/XDC"
            break
        fi
    done
fi
if ! command -v XDC >/dev/null 2>&1; then
    echo "FATAL: No XDC binary found in image!"
    exit 1
fi
exec /work/start.sh "$@"
ENTRYEOF
    chmod +x "$docker_dir/entrypoint.sh"
    
    # Create .env file
    ensure_file_path "$STATE_DIR/.env"
    cat > "$STATE_DIR/.env" << ENVEOF
INSTANCE_NAME=XDC_Node
CONTACT_DETAILS=admin@localhost
SYNC_MODE=${SYNC_MODE}
GC_MODE=full
NETWORK=${NETWORK}
NETWORK_ID=${NETWORK_ID:-50}
APOTHEM_FLAG=${APOTHEM_FLAG:-}
ETHSTATS_FLAG=${ETHSTATS_FLAG:-}
PRIVATE_KEY=0000000000000000000000000000000000000000000000000000000000000000
LOG_LEVEL=2
ENABLE_RPC=true
ENABLE_WS=true
RPC_ADDR=0.0.0.0
RPC_PORT=8545
RPC_API=admin,eth,net,web3,XDPoS
RPC_CORS_DOMAIN=*
RPC_VHOSTS=*
WS_ADDR=0.0.0.0
WS_PORT=8546
WS_API=admin,eth,net,web3,XDPoS
WS_ORIGINS=*
P2P_PORT=${P2P_PORT:-30303}
DASHBOARD_PORT=${DASHBOARD_PORT:-7070}

# ERIGON-specific ports (for multi-client mode)
# These ports are used when running erigon alongside geth
ERIGON_RPC_PORT=8547
ERIGON_AUTHRPC_PORT=8561
ERIGON_P2P_PORT=30304
ERIGON_P2P_PORT_68=30311
ERIGON_DASHBOARD_PORT=7071
ERIGON_RPC_URL=http://xdc-erigon:8547

# NETHERMIND-specific ports (for multi-client mode)
# These ports are used when running nethermind alongside geth
NETHERMIND_RPC_PORT=8556
NETHERMIND_P2P_PORT=30306
NETHERMIND_DASHBOARD_PORT=7072
NETHERMIND_RPC_URL=http://xdc-nethermind:8556
ENVEOF

    # Create password file (remove if Docker created it as a directory)
    if [[ -d "$network_dir/.pwd" ]]; then
        rm -rf "$network_dir/.pwd"
    fi
    if [[ ! -f "$network_dir/.pwd" ]]; then
        # Create empty password file (XDC will use empty password for account)
        touch "$network_dir/.pwd"
        chmod 600 "$network_dir/.pwd"
        info "Created empty password file (.pwd)"
    fi
    
    # Use existing docker-compose.yml if present (from repo clone), otherwise generate
    if [[ -f "$docker_dir/docker-compose.yml" ]]; then
        log "Using existing docker-compose.yml (from repository)"
        return 0
    fi

    # Generate docker-compose.yml (only when installing from scratch / curl pipe)
    cat > "$docker_dir/docker-compose.yml" << EOF
services:
  xdc-node:
    image: $xdc_image
    ${platform_flag:+$platform_flag}
    container_name: xdc-node
    restart: always
    ports:
      - "127.0.0.1:${RPC_PORT}:8545"
      - "127.0.0.1:${WS_PORT}:8546"
      - "${P2P_PORT}:30303"
      - "${P2P_PORT}:30303/udp"
    volumes:
      - ../${NETWORK}/xdcchain:/work/xdcchain
      - ./${NETWORK}/genesis.json:/work/genesis.json
      - ./${NETWORK}/start-node.sh:/work/start.sh
      - ./entrypoint.sh:/work/entrypoint.sh
      - ./${NETWORK}/bootnodes.list:/work/bootnodes.list
      - ./${NETWORK}/.pwd:/work/.pwd
      - ../${NETWORK}/.xdc-node/config.toml:/etc/xdc-node/config.toml:ro
    env_file:
      - ../${NETWORK}/.xdc-node/.env
    environment:
      - NETWORK_ID=${NETWORK_ID:-50}
      - APOTHEM_FLAG=${APOTHEM_FLAG:-}
    entrypoint: ["/bin/bash", "/work/entrypoint.sh"]
    networks:
      - xdc-network
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8545 -X POST -H 'Content-Type: application/json' -d '{\\"jsonrpc\\":\\"2.0\\",\\"method\\":\\"eth_syncing\\",\\"params\\":[],\\"id\\":1}' || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF

    # Add monitoring services if enabled
    if [[ "$ENABLE_MONITORING" == "true" ]]; then
        cat >> "$PROJECT_ROOT/docker/docker-compose.yml" << 'EOF'

  prometheus:
    image: prom/prometheus:latest
    container_name: xdc-prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
    networks:
      - xdc-network

  grafana:
    image: grafana/grafana:latest
    container_name: xdc-grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    networks:
      - xdc-network
    depends_on:
      - prometheus

  node-exporter:
    image: prom/node-exporter:latest
    container_name: xdc-node-exporter
    restart: unless-stopped
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - xdc-network
EOF
    fi

    # Add unified xdc-monitoring container (Prometheus exporter + SkyNet agent)
    cat >> "$PROJECT_ROOT/docker/docker-compose.yml" << EOF

  xdc-monitoring:
    image: alpine:3.19
    container_name: xdc-monitoring
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./skynet-agent.sh:/opt/skynet/agent.sh:ro
      - ../${NETWORK}/.xdc-node/skynet.conf:/etc/xdc-node/skynet.conf:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /etc/ssh/sshd_config:/host/sshd_config:ro
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
    environment:
      - SKYNET_CONF=/etc/xdc-node/skynet.conf
      - XDC_RPC_URL=http://127.0.0.1:${RPC_PORT:-9545}
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        apk add --no-cache bash curl jq bc procps >/dev/null 2>&1
        chmod +x /opt/skynet/agent.sh
        echo "=== XDC Monitoring Container ==="
        echo "SkyNet Agent: heartbeat every 60s"
        while true; do
          /opt/skynet/agent.sh 2>/dev/null && echo "[\$(date '+%H:%M:%S')] heartbeat ok" || echo "[\$(date '+%H:%M:%S')] heartbeat failed"
          sleep 60
        done
    depends_on:
      xdc-node:
        condition: service_healthy
    profiles:
      - skynet

  dashboard:
    image: nginx:alpine
    container_name: xdc-dashboard
    restart: unless-stopped
    ports:
      - "0.0.0.0:3001:3000"
    volumes:
      - ../dashboard/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - ../dashboard/html:/usr/share/nginx/html:ro
      - ./skynet-agent.sh:/agent.sh:ro
      - ../${NETWORK}/.xdc-node/skynet.conf:/etc/xdc-node/skynet.conf:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /etc/ssh/sshd_config:/host/sshd_config:ro
      - /proc:/host/proc:ro
    environment:
      - SKYNET_CONF=/etc/xdc-node/skynet.conf
      - RPC_URL=http://xdc-node:8545
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        apk add --no-cache curl jq bash bc procps >/dev/null 2>&1
        echo "Starting SkyNet Agent in background..."
        (
          while true; do
            /agent.sh 2>/dev/null
            sleep 60
          done
        ) &
        echo "Starting nginx..."
        exec nginx -g 'daemon off;'
    networks:
      - xdc-network
    depends_on:
      xdc-node:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:3000/api/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF
    
    # Copy skynet agent files
    cp "$SCRIPT_DIR/scripts/skynet-agent.sh" "$PROJECT_ROOT/docker/skynet-agent.sh" 2>/dev/null || \
        curl -sSL "https://raw.githubusercontent.com/XDC-Node-Setup/main/scripts/skynet-agent.sh" -o "$PROJECT_ROOT/docker/skynet-agent.sh"
    chmod +x "$PROJECT_ROOT/docker/skynet-agent.sh"
    
    # Create initial skynet.conf from template (will be updated after registration)
    # Docker creates a directory if mount source doesn't exist — remove it first
    if [[ -d "$STATE_DIR/skynet.conf" ]]; then
        rm -rf "$STATE_DIR/skynet.conf"
    fi
    if [[ ! -f "$STATE_DIR/skynet.conf" ]]; then
        cp "$SCRIPT_DIR/configs/skynet.conf.template" "$STATE_DIR/skynet.conf" 2>/dev/null || \
            curl -sSL "https://raw.githubusercontent.com/XDC-Node-Setup/main/configs/skynet.conf.template" -o "$STATE_DIR/skynet.conf" 2>/dev/null || \
            touch "$STATE_DIR/skynet.conf"
        # Pre-fill SkyNet API URL and prompt for API key
        sed -i.bak "s|^SKYNET_API_URL=.*|SKYNET_API_URL=https://skynet.xdcindia.com/api/v1|" "$STATE_DIR/skynet.conf" 2>/dev/null
        sed -i.bak "s|^SKYNET_NODE_NAME=.*|SKYNET_NODE_NAME=$(hostname)-${NETWORK}|" "$STATE_DIR/skynet.conf" 2>/dev/null
        sed -i.bak "s|^SKYNET_ROLE=.*|SKYNET_ROLE=fullnode|" "$STATE_DIR/skynet.conf" 2>/dev/null
        rm -f "$STATE_DIR/skynet.conf.bak" 2>/dev/null
        chmod 600 "$STATE_DIR/skynet.conf"
    fi
    
    # Also create skynet-erigon.conf for multi-client setups (erigon agent needs separate config)
    if [[ -d "$STATE_DIR/skynet-erigon.conf" ]]; then
        rm -rf "$STATE_DIR/skynet-erigon.conf"
    fi
    if [[ ! -f "$STATE_DIR/skynet-erigon.conf" ]]; then
        cp "$SCRIPT_DIR/configs/skynet.conf.template" "$STATE_DIR/skynet-erigon.conf" 2>/dev/null || \
            cp "$STATE_DIR/skynet.conf" "$STATE_DIR/skynet-erigon.conf" 2>/dev/null || \
            cat > "$STATE_DIR/skynet-erigon.conf" << 'ERIGON_CONF_EOF'
SKYNET_API_URL=https://skynet.xdcindia.com/api/v1
SKYNET_API_KEY=
SKYNET_NODE_ID=
SKYNET_NODE_NAME=
SKYNET_ROLE=fullnode
ERIGON_CONF_EOF
        chmod 600 "$STATE_DIR/skynet-erigon.conf"
    fi

    # Close the compose file
    cat >> "$PROJECT_ROOT/docker/docker-compose.yml" << EOF

networks:
  xdc-network:
    driver: bridge

volumes:
  prometheus-data:
  grafana-data:
EOF

    log "Docker Compose configuration created"
}

#==============================================================================
# Monitoring Setup
#==============================================================================
setup_monitoring() {
    [[ "$ENABLE_MONITORING" != "true" ]] && return 0
    
    log "Setting up monitoring stack..."
    
    mkdir -p "$PROJECT_ROOT/docker/grafana/provisioning"/{dashboards,datasources}
    
    # Create Prometheus config
    ensure_file_path "$PROJECT_ROOT/docker/prometheus.yml"
    cat > "$PROJECT_ROOT/docker/prometheus.yml" << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'xdc-node'
    static_configs:
      - targets: ['xdc-node:8545']
    metrics_path: /debug/metrics/prometheus

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
EOF

    # Create Grafana datasource config
    ensure_file_path "$PROJECT_ROOT/docker/grafana/provisioning/datasources/datasource.yml"
    cat > "$PROJECT_ROOT/docker/grafana/provisioning/datasources/datasource.yml" << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
EOF

    # Create Grafana dashboard provider config
    ensure_file_path "$PROJECT_ROOT/docker/grafana/provisioning/dashboards/dashboard.yml"
    cat > "$PROJECT_ROOT/docker/grafana/provisioning/dashboards/dashboard.yml" << 'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards
EOF

    log "Monitoring stack configured"
}

#==============================================================================
# Security Hardening
#==============================================================================
setup_security() {
    [[ "$ENABLE_SECURITY" != "true" || "$OS" == "macos" ]] && return 0
    
    log "Applying security hardening..."
    
    # UFW Firewall — only add rules that don't already exist
    if command -v ufw &> /dev/null; then
        ufw default deny incoming 2>/dev/null || true
        ufw default allow outgoing 2>/dev/null || true
        
        # Helper: add rule only if not already present
        ufw_allow_if_missing() {
            local rule="$1"
            local comment="${2:-}"
            if ! ufw status | grep -q "$rule"; then
                if [[ -n "$comment" ]]; then
                    ufw allow "$rule" comment "$comment" 2>/dev/null || true
                else
                    ufw allow "$rule" 2>/dev/null || true
                fi
                info "Added firewall rule: $rule"
            else
                info "Firewall rule already exists: $rule (skipped)"
            fi
        }
        
        ufw_allow_if_missing "22/tcp" "SSH"
        # RPC intentionally NOT exposed — bound to 127.0.0.1 only (internal monitoring)
        ufw_allow_if_missing "${P2P_PORT}/tcp" "XDC P2P"
        ufw_allow_if_missing "${P2P_PORT}/udp" "XDC P2P UDP"
        
        if [[ "$ENABLE_MONITORING" == "true" ]]; then
            ufw_allow_if_missing "3000/tcp" "Grafana"
            ufw_allow_if_missing "9090/tcp" "Prometheus"
        fi
        
        ufw --force enable 2>/dev/null || true
        log "UFW firewall configured"
    fi
    
    # Fail2ban
    if command -v fail2ban-client &> /dev/null; then
        systemctl enable fail2ban
        systemctl start fail2ban
        log "Fail2ban enabled"
    fi
    
    # Security rotation reminders are now handled by: xdc monitor
    # No cron job needed - users can check with 'xdc monitor' command
    
    log "Security hardening complete"
}

#==============================================================================
# Log Rotation Cron Setup
#==============================================================================
setup_log_rotation_cron() {
    log "Setting up log rotation..."
    
    # Install logrotate configuration file (Issue #29)
    local logrotate_conf_src="${SCRIPT_DIR}/configs/logrotate/xdc-node"
    local logrotate_conf_dest="/etc/logrotate.d/xdc-node"
    
    if [[ -f "$logrotate_conf_src" ]]; then
        if [[ -d "/etc/logrotate.d" ]]; then
            cp "$logrotate_conf_src" "$logrotate_conf_dest"
            chmod 644 "$logrotate_conf_dest"
            log "Logrotate config installed to $logrotate_conf_dest"
        else
            warn "/etc/logrotate.d not found, skipping system logrotate config"
        fi
    else
        warn "Logrotate config not found at $logrotate_conf_src"
    fi
    
    # Ensure log directory exists
    mkdir -p /var/log/xdc
    chmod 755 /var/log/xdc
    
    # Ensure log rotation script exists and is executable
    local log_rotate_script="${SCRIPT_DIR}/scripts/log-rotate.sh"
    if [[ ! -f "$log_rotate_script" ]]; then
        warn "Log rotation script not found at $log_rotate_script, skipping cron setup"
        return 0
    fi
    
    chmod +x "$log_rotate_script"
    
    # Create cron job for log rotation (runs daily at 2:00 AM)
    local cron_cmd="0 2 * * * ${log_rotate_script} >> /var/log/xdc-logrotate.log 2>&1"
    local cron_comment="# XDC Node log rotation (daily 2:00 AM)"
    
    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -qF "$log_rotate_script"; then
        info "Log rotation cron job already exists"
        return 0
    fi
    
    # Add cron job
    (
        crontab -l 2>/dev/null || true
        echo ""
        echo "$cron_comment"
        echo "$cron_cmd"
    ) | crontab -
    
    log "Log rotation cron job installed (runs daily at 2:00 AM)"
    info "Log rotation policy: compress daily, keep 90 days, auto-delete old logs"
    info "Manual rotation: xdc logs --rotate"
    info "Clean old logs: xdc logs --clean"
    
    # Ensure log directory exists
    mkdir -p /var/log
    touch /var/log/xdc-logrotate.log
    chmod 644 /var/log/xdc-logrotate.log
}

#==============================================================================
# CLI Tool Installation
#==============================================================================
install_cli_tool() {
    [[ "${INSTALL_CLI:-true}" != "true" ]] && return 0
    
    log "Installing XDC CLI tool..."
    
    # Prefer the dedicated installer script if available
    if [[ -f "${SCRIPT_DIR}/cli/install.sh" ]]; then
        if bash "${SCRIPT_DIR}/cli/install.sh" >/dev/null 2>&1; then
            log "CLI installed via cli/install.sh"
            return 0
        fi
        warn "cli/install.sh failed, falling back to manual install"
    fi
    
    # Copy CLI script — prefer cli/xdc (full version) over cli/xdc-node (legacy)
    local cli_source="${SCRIPT_DIR}/cli/xdc"
    [[ ! -f "$cli_source" ]] && cli_source="${SCRIPT_DIR}/cli/xdc-node"
    
    mkdir -p "$PROJECT_ROOT/scripts"
    
    if [[ -f "$cli_source" ]]; then
        cp "$cli_source" "$PROJECT_ROOT/scripts/xdc-node"
        chmod +x "$PROJECT_ROOT/scripts/xdc-node"
        log "Installed CLI from bundled $(basename "$cli_source")"
    else
        warn "CLI source not found, downloading..."
        curl -fsSL "https://raw.githubusercontent.com/XDCIndia/xdc-node-setup/main/cli/xdc" \
            -o "$PROJECT_ROOT/scripts/xdc-node" 2>/dev/null || \
        curl -fsSL "https://raw.githubusercontent.com/XDCIndia/xdc-node-setup/main/cli/xdc-node" \
            -o "$PROJECT_ROOT/scripts/xdc-node" 2>/dev/null || {
            error "Failed to download CLI tool"
            return 1
        }
        chmod +x "$PROJECT_ROOT/scripts/xdc-node"
    fi
    
    # Create state directories for CLI (legacy location for shared state)
    mkdir -p /var/lib/xdc-node
    chmod 750 /var/lib/xdc-node
    
    # Ensure network-specific directories exist (already created in configure_node)
    mkdir -p "${PROJECT_ROOT}/mainnet/.xdc-node"
    mkdir -p "${PROJECT_ROOT}/testnet/.xdc-node"
    mkdir -p "${PROJECT_ROOT}/devnet/.xdc-node"
    
    # Create symlink — try /usr/local/bin first, fall back to ~/.local/bin
    if [[ -w /usr/local/bin ]]; then
        ln -sf "$PROJECT_ROOT/scripts/xdc-node" /usr/local/bin/xdc
        log "CLI installed at /usr/local/bin/xdc"
    elif sudo ln -sf "$PROJECT_ROOT/scripts/xdc-node" /usr/local/bin/xdc 2>/dev/null; then
        log "CLI installed at /usr/local/bin/xdc (via sudo)"
    else
        mkdir -p "$HOME/.local/bin"
        ln -sf "$PROJECT_ROOT/scripts/xdc-node" "$HOME/.local/bin/xdc"
        log "CLI installed at $HOME/.local/bin/xdc"
        # Add to PATH if needed
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc" 2>/dev/null || true
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc" 2>/dev/null || true
            export PATH="$HOME/.local/bin:$PATH"
            warn "Added ~/.local/bin to PATH. Run: source ~/.zshrc (or restart terminal)"
        fi
    fi
    
    log "CLI tool installed. Use: xdc help"
    
    # Install man pages
    install_man_pages || warn "Man page installation failed (non-fatal)"
}

#==============================================================================
# Man Pages Installation
#==============================================================================
install_man_pages() {
    log "Installing man pages..."
    
    local man_source_dir="${SCRIPT_DIR}/docs/man"
    local man_install_dir="/usr/local/share/man/man1"
    
    # Check if man pages exist
    if [[ ! -d "$man_source_dir" ]]; then
        warn "Man pages source directory not found: $man_source_dir"
        return 0
    fi
    
    # Check if any man pages exist
    if ! ls "$man_source_dir"/*.1 >/dev/null 2>&1; then
        warn "No man pages found in: $man_source_dir"
        return 0
    fi
    
    # Create man directory if needed
    if [[ ! -d "$man_install_dir" ]]; then
        if [[ -w /usr/local/share/man ]]; then
            mkdir -p "$man_install_dir"
        elif sudo mkdir -p "$man_install_dir" 2>/dev/null; then
            :
        else
            warn "Cannot create man directory: $man_install_dir"
            return 0
        fi
    fi
    
    # Install man pages
    local installed=0
    for manpage in "$man_source_dir"/*.1; do
        if [[ -f "$manpage" ]]; then
            local manpage_name
            manpage_name=$(basename "$manpage")
            
            if [[ -w "$man_install_dir" ]]; then
                cp "$manpage" "$man_install_dir/"
                chmod 644 "$man_install_dir/$manpage_name"
                ((installed++))
            elif sudo cp "$manpage" "$man_install_dir/" 2>/dev/null; then
                sudo chmod 644 "$man_install_dir/$manpage_name"
                ((installed++))
            else
                warn "Failed to install man page: $manpage_name"
            fi
        fi
    done
    
    # Update man database
    if [[ $installed -gt 0 ]]; then
        log "Installed $installed man page(s)"
        if command -v mandb >/dev/null 2>&1; then
            mandb -q 2>/dev/null || sudo mandb -q 2>/dev/null || true
        fi
    fi
}

#==============================================================================
# Start Services
#==============================================================================
start_services() {
    log "Starting XDC node services..."
    
    cd "$PROJECT_ROOT/docker"
    
    # Pull images
    info "Pulling Docker images..."
    "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" pull &
    run_with_spinner "Pulling XDC Docker image..." wait $! || true
    
    # Check for conflicting container names and remove them
    for svc in xdc-node xdc-prometheus xdc-grafana xdc-node-exporter xdc-monitoring; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${svc}$"; then
            local svc_id
            svc_id=$(docker ps -aq -f name="^${svc}$")
            # Only remove if it belongs to a different compose project
            local svc_project
            svc_project=$(docker inspect "$svc_id" --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null || echo "")
            local our_project
            our_project=$(basename "$PWD" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
            if [[ -n "$svc_project" && "$svc_project" != "$our_project" ]]; then
                warn "Removing conflicting container '$svc' from project '$svc_project'"
                docker rm -f "$svc_id" 2>/dev/null || true
            fi
        fi
    done
    
    # Issue #547 & #552: Verify critical files exist and are actual files (not directories)
    # Docker creates directories when volume mount source is missing
    log "Pre-flight check: ensuring config files are files, not directories..."
    
    # Network-specific files to check
    local config_files=(
        "${NETWORK}/start-node.sh"
        "${NETWORK}/genesis.json"
        "${NETWORK}/.pwd"
        "${NETWORK}/bootnodes.list"
    )
    
    # Additional config files that Docker might create as directories
    local state_config_files=(
        "../${NETWORK}/.xdc-node/skynet.conf"
        "../${NETWORK}/.xdc-node/config.toml"
        "../${NETWORK}/.xdc-node/.env"
    )
    
    for f in "${config_files[@]}"; do
        local fpath="$PROJECT_ROOT/docker/$f"
        if [[ -d "$fpath" ]]; then
            warn "$f was created as a directory (Docker artifact). Removing and recreating..."
            rm -rf "$fpath"
        fi
        
        # Ensure parent directory exists
        mkdir -p "$(dirname "$fpath")"
        
        if [[ ! -f "$fpath" ]]; then
            case "$(basename "$f")" in
                start-node.sh|genesis.json|bootnodes.list)
                    warn "$f is missing. Attempting to download..."
                    local base_url="https://raw.githubusercontent.com/XinFinOrg/XinFin-Node/master/${NETWORK}"
                    local fname=$(basename "$f")
                    if ! curl -fsSL --connect-timeout 10 "$base_url/$fname" -o "$fpath" 2>/dev/null || [[ ! -s "$fpath" ]]; then
                        # Fallback: try mainnet if network-specific file not found
                        [[ "$NETWORK" != "mainnet" ]] && curl -fsSL --connect-timeout 10 \
                            "https://raw.githubusercontent.com/XinFinOrg/XinFin-Node/master/mainnet/$fname" \
                            -o "$fpath" 2>/dev/null || true
                    fi
                    [[ "$fname" == "start-node.sh" ]] && chmod +x "$fpath" 2>/dev/null || true
                    ;;
                .pwd)
                    touch "$fpath"
                    chmod 600 "$fpath"
                    log "Created empty password file: $f"
                    ;;
            esac
        fi
        
        # Final check: if still directory or doesn't exist, create empty file
        if [[ -d "$fpath" ]]; then
            rm -rf "$fpath"
            touch "$fpath"
            warn "Force-created $f as empty file (was directory)"
        elif [[ ! -f "$fpath" ]]; then
            touch "$fpath"
            info "Created placeholder for: $f"
        fi
    done
    
    # Check state config files (relative to docker dir)
    for f in "${state_config_files[@]}"; do
        local fpath="$PROJECT_ROOT/docker/$f"
        if [[ -d "$fpath" ]]; then
            warn "$(basename "$fpath") was created as directory. Removing..."
            rm -rf "$fpath"
        fi
        # These are created by other setup functions, just ensure they're not directories
        if [[ ! -f "$fpath" ]]; then
            mkdir -p "$(dirname "$fpath")"
            touch "$fpath"
            info "Pre-created: $(basename "$fpath")"
        fi
    done
    
    log "✓ Config file pre-flight check complete"
    
    # Also remove any Docker-created directories in the data volume
    local container_name="xdc-node"
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        docker rm -f "$container_name" 2>/dev/null || true
    fi
    
    # Start services (remove orphans from other projects sharing this dir)
    info "Starting containers..."
    if [[ "$CLIENT" == "all" ]]; then
        log "Network: $NETWORK, Chain ID: $CHAIN_ID, Network ID: $NETWORK_ID"
        # Check if apothem full compose exists for multi-client apothem
        if [[ ("$NETWORK" == "apothem" || "$NETWORK" == "testnet") ]]; then
            if [[ -f "docker-compose.apothem-full.yml" ]]; then
                info "Multi-client mode (Apothem): starting all 4 clients from docker-compose.apothem-full.yml..."
                "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" -f docker-compose.apothem-full.yml up -d
            else
                warn "docker-compose.apothem-full.yml not found in $(pwd), falling back to individual clients..."
                # Fall through to individual client startup below
                docker network create docker_xdc-network 2>/dev/null || true
                export NETWORK="$NETWORK" NETWORK_ID="$NETWORK_ID" APOTHEM_FLAG="$APOTHEM_FLAG"
                # Start geth v2.6.8 with apothem
                "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" up -d --remove-orphans
                for f in docker-compose.geth-pr5-standalone.yml docker-compose.erigon-standalone.yml docker-compose.nethermind-standalone.yml; do
                    [[ -f "$f" ]] && "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" -f "$f" up -d || true
                done
            fi
        else
            # Multi-client: start geth first, then others standalone
            info "Multi-client mode: starting geth + geth-pr5 + erigon + nethermind..."
            "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" up -d --remove-orphans
            docker network create docker_xdc-network 2>/dev/null || true
            export NETWORK_ID="${NETWORK_ID:-50}" APOTHEM_FLAG="${APOTHEM_FLAG:-}" NETWORK="${NETWORK:-mainnet}"
            if [[ -f "docker-compose.geth-pr5-standalone.yml" ]]; then
                "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" -f docker-compose.geth-pr5-standalone.yml up -d || warn "Failed to start Geth PR5"
            fi
            if [[ -f "docker-compose.erigon-standalone.yml" ]]; then
                "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" -f docker-compose.erigon-standalone.yml up -d || warn "Failed to start Erigon"
            fi
            if [[ -f "docker-compose.nethermind-standalone.yml" ]]; then
                "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" -f docker-compose.nethermind-standalone.yml up -d || warn "Failed to start Nethermind"
            fi
        fi
    elif [[ "$CLIENT" == "geth-pr5" ]]; then
        info "Starting Geth PR5 using Docker Hub image (anilchinchawale/gx)..."
        docker network create docker_xdc-network 2>/dev/null || true
        export NETWORK_ID="${NETWORK_ID:-50}" APOTHEM_FLAG="${APOTHEM_FLAG:-}"
        export NETWORK="${NETWORK:-mainnet}"
        if [[ -f "docker-compose.geth-pr5-standalone.yml" ]]; then
            "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" -f docker-compose.geth-pr5-standalone.yml up -d
        elif [[ -f "docker-compose.geth-pr5.yml" ]]; then
            "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" -f docker-compose.geth-pr5.yml up -d
        else
            # Fallback: run directly from Docker Hub image
            docker run -d --name xdc-node-geth-pr5 \
                --network docker_xdc-network \
                --restart unless-stopped \
                -p "127.0.0.1:${GP5_RPC_PORT:-8557}:8557" \
                -p "${GP5_P2P_PORT:-30307}:30307" \
                -v "${NETWORK:-mainnet}-geth-pr5-data:/data/xdc" \
                anilchinchawale/gx:latest \
                --datadir=/data/xdc --networkid=${NETWORK_ID:-50} --port=30307 \
                --http --http.addr=0.0.0.0 --http.port=8557 --http.vhosts="*" \
                --http.api=eth,net,web3,txpool,debug,admin \
                --syncmode=full --state.scheme="${STATE_SCHEME:-hash}" \
                ${APOTHEM_FLAG:-}
        fi
    elif [[ "$CLIENT" == "erigon" ]]; then
        if [[ -f "docker-compose.erigon-standalone.yml" ]]; then
            docker network create xdc-network 2>/dev/null || true
            "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" -f docker-compose.erigon-standalone.yml up -d
        else
            "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" -f docker-compose.yml -f docker-compose.erigon-apothem.yml up -d --remove-orphans
        fi
    elif [[ "$CLIENT" == "nethermind" ]]; then
        if [[ -f "docker-compose.nethermind-standalone.yml" ]]; then
            docker network create xdc-network 2>/dev/null || true
            "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" -f docker-compose.nethermind-standalone.yml up -d
        else
            "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" -f docker-compose.yml -f docker-compose.nethermind.yml up -d --remove-orphans
        fi
    else
        "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" up -d --remove-orphans
    fi
    
    # Wait for startup
    sleep 5
    
    # Check status
    if "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" ps | grep -q "Up"; then
        log "Services started successfully"
        
        # Auto-add peers if node has 0 peers after startup
        info "Checking peer connectivity..."
        sleep 10
        local peer_count
        peer_count=$(curl -s -m 5 -X POST http://127.0.0.1:${RPC_PORT:-9545} \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null | jq -r '.result // "0x0"' 2>/dev/null || echo "0x0")
        peer_count=$((16#${peer_count#0x})) 2>/dev/null || peer_count=0
        
        if [[ "$peer_count" -eq 0 ]]; then
            warn "No peers connected. Adding bootstrap peers..."
            local bootnodes=(
                "enode://3a942f2d4c31eb97e3e5ed72a0e5a4f4b4f5b5a5c5d5e5f5a5b5c5d5e5f5a5b5c5d5e5f5a5b5c5d5e5f5a5b5c5d5e5f5a5b5c5d5e5f5a5b5c@bootnode.xinfin.network:30303"
            )
            # Fetch live healthy peers from SkyNet
            local skynet_peers
            skynet_peers=$(curl -s -m 10 "https://skynet.xdcindia.com/api/v1/peers/healthy?format=enode&limit=10" 2>/dev/null | jq -r '.peers[]?.enode // empty' 2>/dev/null || true)
            if [[ -n "$skynet_peers" ]]; then
                while IFS= read -r enode; do
                    [[ -z "$enode" ]] && continue
                    curl -s -m 5 -X POST http://127.0.0.1:${RPC_PORT:-9545} \
                        -H "Content-Type: application/json" \
                        -d "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addPeer\",\"params\":[\"$enode\"],\"id\":1}" >/dev/null 2>&1 || true
                done <<< "$skynet_peers"
                log "Added peers from SkyNet network"
            fi
            # Also add from bootnodes.list if available
            if [[ -f "$PROJECT_ROOT/docker/mainnet/bootnodes.list" ]]; then
                while IFS= read -r enode; do
                    [[ -z "$enode" || "$enode" == \#* ]] && continue
                    curl -s -m 5 -X POST http://127.0.0.1:${RPC_PORT:-9545} \
                        -H "Content-Type: application/json" \
                        -d "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addPeer\",\"params\":[\"$enode\"],\"id\":1}" >/dev/null 2>&1 || true
                done < "$PROJECT_ROOT/docker/mainnet/bootnodes.list"
                log "Added peers from bootnodes.list"
            fi
        else
            log "Connected to $peer_count peers"
        fi
    else
        warn "Some services may not have started properly. Check logs with: "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" logs"
    fi
}

#==============================================================================
# Status Check
#==============================================================================
get_node_status() {
    local status="not installed"
    local block_height="N/A"
    local peers="N/A"
    local sync_status="unknown"
    
    if [[ -f "$CONFIG_DIR/node.env" ]]; then
        status="installed"
        
        if docker ps --format '{{.Names}}' | grep -q "xdc"; then
            status="running"
            
            # Try to get block height
            local response
            response=$(curl -s -m 5 -X POST \
                -H "Content-Type: application/json" \
                -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
                http://localhost:${RPC_PORT} 2>/dev/null || echo '{}')
            
            local hex_height
            hex_height=$(echo "$response" | jq -r '.result // "0x0"' 2>/dev/null || echo "0x0")
            if [[ "$hex_height" != "0x0" && "$hex_height" != "null" ]]; then
                block_height=$((16#${hex_height#0x}))
            fi
            
            # Check sync status
            response=$(curl -s -m 5 -X POST \
                -H "Content-Type: application/json" \
                -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
                http://localhost:${RPC_PORT} 2>/dev/null || echo '{}')
            
            local syncing
            syncing=$(echo "$response" | jq -r '.result' 2>/dev/null || echo "false")
            if [[ "$syncing" == "false" ]]; then
                sync_status="synced"
            elif [[ "$syncing" != "null" ]]; then
                sync_status="syncing"
            fi
        fi
    fi
    
    echo "$status|$block_height|$peers|$sync_status"
}

show_status() {
    init_config
    
    echo -e "${BOLD}XDC Node Status${NC}"
    echo "==============="
    echo ""
    
    local status block_height peers sync_status
    IFS='|' read -r status block_height peers sync_status <<< "$(get_node_status)"
    
    # Load config if exists
    if [[ -f "$CONFIG_DIR/node.env" ]]; then
        source "$CONFIG_DIR/node.env"
    fi
    
    echo -e "  ${BLUE}Status:${NC}      $status"
    echo -e "  ${BLUE}Network:${NC}     ${NETWORK:-unknown} (Chain ID: ${CHAIN_ID:-N/A})"
    echo -e "  ${BLUE}Node Type:${NC}   ${NODE_TYPE:-unknown}"
    echo -e "  ${BLUE}Data Dir:${NC}    ${DATA_DIR:-unknown}"
    echo -e "  ${BLUE}RPC:${NC}         http://127.0.0.1:${RPC_PORT:-9545}"
    echo -e "  ${BLUE}Block Height:${NC} $block_height"
    echo -e "  ${BLUE}Sync Status:${NC} $sync_status"
    echo ""
    
    if [[ "$status" == "running" ]]; then
        echo -e "${GREEN}Node is running!${NC}"
        echo ""
        echo "Useful commands:"
        echo "  xdc logs    - View logs"
        echo "  xdc sync    - Check sync status"
        echo "  xdc health  - Health check"
    elif [[ "$status" == "installed" ]]; then
        echo -e "${YELLOW}Node is installed but not running.${NC}"
        echo "Start with: (cd $PROJECT_ROOT/docker && "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" up -d)"
    else
        echo -e "${RED}XDC node is not installed.${NC}"
        echo "Run this script to install: $0"
    fi
}

#==============================================================================
# Uninstall
#==============================================================================
uninstall_node() {
    warn "This will remove the XDC node and all configuration!"
    read -rp "Are you sure? Type 'yes' to confirm: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        echo "Uninstall cancelled."
        exit 0
    fi
    
    log "Uninstalling XDC node..."
    
    # Stop and remove containers
    if [[ -f "$PROJECT_ROOT/docker/docker-compose.yml" ]]; then
        (cd "$PROJECT_ROOT/docker" && "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" down -v 2>/dev/null) || true
    fi
    
    # Remove systemd service
    if [[ "$OS" == "linux" ]]; then
        systemctl stop xdc-node 2>/dev/null || true
        systemctl disable xdc-node 2>/dev/null || true
        rm -f /etc/systemd/system/xdc-node.service
        systemctl daemon-reload 2>/dev/null || true
    fi
    
    # Remove CLI symlink
    rm -f /usr/local/bin/xdc "$HOME/.local/bin/xdc-node"
    
    # Ask about data
    read -rp "Remove blockchain data? [y/N]: " remove_data
    if [[ "$remove_data" =~ ^[Yy]$ ]]; then
        if [[ -d "$DATA_DIR" ]]; then
            rm -rf "$DATA_DIR"
            log "Blockchain data removed"
        fi
    else
        log "Blockchain data preserved at: $DATA_DIR"
    fi
    
    # Remove installation (configs, scripts, logs, docker)
    rm -rf "$PROJECT_ROOT/configs"
    rm -rf "$PROJECT_ROOT/scripts"
    rm -rf "$PROJECT_ROOT/logs"
    rm -rf "$PROJECT_ROOT/docker"
    
    log "XDC node uninstalled successfully"
    echo ""
    echo -e "${GREEN}Uninstall complete.${NC}"
    echo "Note: Docker images were not removed. To remove: docker rmi xinfinorg/xinfinnetwork:v1.4.7"
}

#==============================================================================
# SkyNet Registration
#==============================================================================
register_with_skynet() {
    local email="${SKYNET_EMAIL:-}"
    local telegram="${SKYNET_TELEGRAM:-}"
    local hostname
    local public_ip
    local node_role
    local rpc_port
    local skynet_conf="$PROJECT_ROOT/${NETWORK:-mainnet}/.xdc-node/skynet.conf"
    
    log "Setting up SkyNet registration..."
    
    # Check if already registered
    if [[ -f "$skynet_conf" ]]; then
        # shellcheck source=/dev/null
        source "$skynet_conf"
        if [[ -n "${SKYNET_API_KEY:-}" ]]; then
            info "Node already registered with SkyNet (API key found)"
            return 0
        fi
    fi
    
    # Mask sensitive input: show first 2 and last 2 chars, rest as *
    mask_value() {
        local val="$1"
        local len=${#val}
        if [[ $len -le 4 ]]; then
            printf '%*s' "$len" | tr ' ' '*'
        else
            echo "${val:0:2}$(printf '%*s' $((len - 4)) | tr ' ' '*')${val: -2}"
        fi
    }
    
    # If email/telegram not provided via CLI, prompt interactively
    if [[ -z "$email" || -z "$telegram" ]]; then
        echo ""
        echo -e "${CYAN}${BOLD}📡 SkyNet Dashboard Registration${NC}"
        echo "Register your node for monitoring and alerts on https://skynet.xdcindia.com"
        echo ""
    fi
    
    if [[ -z "$email" ]]; then
        read -rp "* Email for alerts (optional, press Enter to skip): " email
        if [[ -n "$email" && ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            warn "Invalid email format — skipping"
            email=""
        elif [[ -n "$email" ]]; then
            info "Email: $(mask_value "$email")"
        fi
    else
        info "Using email from command line: $(mask_value "$email")"
    fi
    
    if [[ -z "$telegram" ]]; then
        read -rp "* Telegram handle for alerts (optional, e.g. @username — press Enter to skip): " telegram
        if [[ -n "$telegram" ]]; then
            info "Telegram: $(mask_value "$telegram")"
        fi
    else
        info "Using Telegram from command line: $(mask_value "$telegram")"
    fi
    
    # Auto-detect node information
    hostname=$(hostname -s)
    public_ip=$(curl -s -m 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    # Determine node role from config
    case "${NODE_TYPE:-full}" in
        archive|archivenode)
            node_role="archive"
            ;;
        validator|masternode)
            node_role="masternode"
            ;;
        *)
            node_role="fullnode"
            ;;
    esac
    
    rpc_port="${RPC_PORT:-9545}"
    
    # Detect OS type
    local os_short
    case "$(uname -s)" in
        Linux*)  os_short="linux";;
        Darwin*) os_short="macos";;
        *)       os_short="unknown";;
    esac
    
    # Get IP last octets (e.g. 12.32 from 192.168.12.32)
    local ip_suffix
    ip_suffix=$(echo "$public_ip" | awk -F'.' '{print $(NF-1)"."$NF}')
    [[ -z "$ip_suffix" || "$ip_suffix" == "." ]] && ip_suffix=$(echo "$public_ip" | tail -c 8)
    
    # Detect location
    local location_city location_country
    local geo_json
    geo_json=$(curl -s -m 5 "http://ip-api.com/json/?fields=city,countryCode" 2>/dev/null || echo '{}')
    location_city=$(echo "$geo_json" | jq -r '.city // "unknown"' 2>/dev/null || echo "unknown")
    location_country=$(echo "$geo_json" | jq -r '.countryCode // "XX"' 2>/dev/null || echo "XX")
    local location_short
    location_short=$(echo "${location_city}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | cut -c1-10)
    
    # Try to get coinbase (first 6 chars) from running node
    local coinbase_short=""
    local cb
    cb=$(curl -s -m 3 -X POST http://127.0.0.1:${rpc_port} \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_coinbase","params":[],"id":1}' 2>/dev/null | jq -r '.result // ""' 2>/dev/null || true)
    if [[ -n "$cb" && "$cb" != "0x0" && "$cb" != "0x0000000000000000000000000000000000000000" && "$cb" != "null" ]]; then
        coinbase_short="${cb:2:6}"
    fi
    
    # Build smart node name: [coinbase]-[os]-[ip_suffix]-[location]
    local node_name
    if [[ -n "$coinbase_short" ]]; then
        node_name="${coinbase_short}-${os_short}-${ip_suffix}-${location_short}"
    else
        node_name="${hostname}-${os_short}-${ip_suffix}-${location_short}"
    fi
    # Sanitize: only alphanumeric, dash, underscore, dot
    node_name=$(echo "$node_name" | sed 's/[^a-zA-Z0-9._-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
    
    info "Auto-detected configuration:"
    echo "  Node Name: $node_name"
    echo "  Hostname: $hostname"
    echo "  Public IP: $public_ip"
    echo "  OS: $os_short ($(uname -m))"
    echo "  Location: $location_city, $location_country"
    echo "  Node Role: $node_role"
    echo "  RPC Port: $rpc_port"
    [[ -n "$coinbase_short" ]] && echo "  Coinbase: 0x${coinbase_short}..."
    echo ""
    
    # Prepare registration payload
    local payload
    payload=$(cat <<EOF
{
    "name": "${node_name}",
    "host": "${public_ip}",
    "rpcUrl": "http://${public_ip}:${rpc_port}",
    "role": "${node_role}",
    "email": "${email:-}",
    "telegram": "${telegram:-}",
    "locationCity": "${location_city}",
    "locationCountry": "${location_country}"
}
EOF
)
    
    info "Registering node with SkyNet dashboard..."
    
    # Call registration API
    local response
    response=$(curl -s -m 15 -X POST "https://skynet.xdcindia.com/api/v1/nodes/register" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null || echo '{"error":"connection_failed"}')
    
    info "Registration response: $response"
    
    # Check for API key in response (try multiple response shapes, fallback without jq)
    local api_key="" node_id=""
    if command -v jq >/dev/null 2>&1; then
        api_key=$(echo "$response" | jq -r '.apiKey // .data.apiKey // .data.api_key // empty' 2>/dev/null || echo "")
        node_id=$(echo "$response" | jq -r '.nodeId // .data.nodeId // .data.node_id // .data.id // empty' 2>/dev/null || echo "")
    else
        # Fallback: grep-based parsing
        api_key=$(echo "$response" | grep -o '"apiKey":"[^"]*"' | head -1 | cut -d'"' -f4)
        node_id=$(echo "$response" | grep -o '"nodeId":"[^"]*"' | head -1 | cut -d'"' -f4)
    fi
    
    # Always write skynet.conf with whatever we have (email, telegram, role at minimum)
    mkdir -p "$(dirname "$skynet_conf")"
    cat > "$skynet_conf" <<EOF
# XDC SkyNet Agent Configuration
# Auto-generated during node setup

SKYNET_API_URL=https://skynet.xdcindia.com/api/v1
SKYNET_NODE_ID=${node_id}
SKYNET_NODE_NAME=${node_name}
SKYNET_API_KEY=${api_key}
SKYNET_ROLE=${node_role}
SKYNET_EMAIL=${email:-}
SKYNET_TELEGRAM=${telegram:-}
EOF
    chmod 600 "$skynet_conf"
    
    if [[ -n "$api_key" && "$api_key" != "null" ]]; then
        log "✅ Node registered successfully with SkyNet!"
        [[ -n "$node_id" ]] && info "Node ID: $node_id"
        
        # Start xdc-monitoring container for heartbeat reporting
        if [[ -f "$PROJECT_ROOT/docker/skynet-agent.sh" ]]; then
            if grep -q "xdc-monitoring:" "$PROJECT_ROOT/docker/docker-compose.yml" 2>/dev/null; then
                (cd "$PROJECT_ROOT/docker" && "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" up -d xdc-monitoring 2>/dev/null) || \
                    warn "Could not start xdc-monitoring container. Start manually with: cd $PROJECT_ROOT/docker && "${DOCKER_COMPOSE_BIN}" "${DOCKER_COMPOSE_ARGS}" up -d xdc-monitoring"
            fi
            
            log "SkyNet agent running as Docker container (heartbeat every 60s)"
        fi
        
        echo ""
        echo -e "${GREEN}${BOLD}✅ SkyNet Registration Complete!${NC}"
        echo ""
        echo -e "${YELLOW}To receive alert notifications, edit:${NC}"
        echo "  $skynet_conf"
        echo ""
        echo "And add your:"
        echo "  SKYNET_EMAIL=your@email.com"
        echo "  SKYNET_TELEGRAM=@your_telegram_handle"
        echo ""
        echo "View your node at: https://skynet.xdcindia.com"
        return 0
    else
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error // "Registration failed"' 2>/dev/null || echo "Registration failed")
        warn "SkyNet registration failed: $error_msg"
        info "Config saved to $skynet_conf (email/telegram preserved, fill in API key manually)"
        echo ""
        echo "You can manually register later by running:"
        echo "  $0 --register-skynet"
        return 1
    fi
}

#==============================================================================
# Print Summary
#==============================================================================
print_summary() {
    local status block_height peers sync_status
    IFS='|' read -r status block_height peers sync_status <<< "$(get_node_status)"
    
    echo ""
    echo -e "${GREEN}${BOLD}✅ XDC Node Setup Complete!${NC}"
    echo ""
    echo -e "   ${BOLD}Network:${NC}    $NETWORK (Chain ID: $CHAIN_ID)"
    echo -e "   ${BOLD}Node Type:${NC}  $(echo "$NODE_TYPE" | awk '{print toupper(substr($0,1,1)) substr($0,2)}') Node"
    echo -e "   ${BOLD}Data Dir:${NC}   $DATA_DIR"
    echo -e "   ${BOLD}RPC:${NC}        http://127.0.0.1:$RPC_PORT"
    echo -e "   ${BOLD}P2P:${NC}        $P2P_PORT"
    echo -e "   ${BOLD}Status:${NC}     $(echo "$sync_status" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')..."
    echo ""
    
    if [[ "$ENABLE_MONITORING" == "true" ]]; then
        echo -e "   ${BOLD}Monitoring:${NC} xdc start --monitoring (Prometheus + Grafana)"
    fi
    
    echo -e "   ${BOLD}CLI Commands:${NC}"
    echo "     xdc status     — Node status, block height, peers, sync %"
    echo "     xdc sync       — Detailed sync progress with progress bar"
    echo "     xdc health     — Comprehensive health check (score 0-100)"
    echo "     xdc security   — Server security audit (score 0-100)"
    echo "     xdc snapshot   — Restore from snapshot (with resume)"
    echo "     xdc attach     — Attach to node console"
    echo "     xdc info       — Node info (network, version, enode)"
    echo "     xdc peers      — List connected peers"
    echo "     xdc backup     — Backup keystore and configs"
    echo "     xdc monitor    — Security rotation reminders"
    echo "     xdc logs       — View node logs"
    echo "     xdc help       — Show all commands"
    echo ""
    echo -e "   ${BOLD}Dashboard:${NC}  http://localhost:${DASHBOARD_PORT:-7070}"
    echo ""
    echo -e "   ${BOLD}Next Steps:${NC}"
    echo "   1. Wait for sync to complete (~2-3 days for full node)"
    echo "   2. Check sync status: xdc sync"
    echo "   3. Monitor health: xdc health"
    echo "   4. Check security: xdc security"
    echo ""
    echo -e "   ${YELLOW}${BOLD}🔒 Security Recommendations:${NC}"
    echo "   • RPC is bound to 127.0.0.1 only (not exposed externally)"
    echo "   • Change default SSH port: edit /etc/ssh/sshd_config → Port <custom>"
    echo "   • Rotate credentials every 90 days: xdc monitor"
    echo "   • Disable root login: PermitRootLogin no"
    echo "   • Use SSH key auth and disable password auth after setup"
    echo "   • Review firewall rules: ufw status numbered"
    echo ""
    echo -e "   ${BOLD}Documentation:${NC} https://github.com/AnilChinchawale/xdc-node-setup/docs"
    echo ""
}

#==============================================================================
# Main
#==============================================================================
main() {
    # Parse arguments
    MODE="simple"
    SKYNET_EMAIL=""
    SKYNET_TELEGRAM=""
    NODE_CLIENT="xdc"
    NODE_TYPE="full"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --advanced)
                MODE="advanced"
                shift
                ;;
            --simple)
                MODE="simple"
                shift
                ;;
            --email)
                SKYNET_EMAIL="$2"
                shift 2
                ;;
            --tg|--telegram)
                SKYNET_TELEGRAM="$2"
                shift 2
                ;;
            --client)
                NODE_CLIENT="$2"
                shift 2
                ;;
            --type)
                NODE_TYPE="$2"
                shift 2
                ;;
            --network)
                NETWORK="$2"
                shift 2
                ;;
            --status)
                init_logging
                init_config
                show_status
                exit 0
                ;;
            --uninstall)
                init_logging
                init_config
                uninstall_node
                exit 0
                ;;
            --help|-h)
                show_banner
                show_help
                exit 0
                ;;
            --version|-v)
                echo "XDC Node Setup v$SCRIPT_VERSION"
                exit 0
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    # Map CLI args to config variables (before init_config)
    # --client flag sets NODE_CLIENT; map to CLIENT used by the rest of the script
    case "${NODE_CLIENT:-xdc}" in
        all)      CLIENT="all" ;;
        erigon)   CLIENT="erigon" ;;
        geth-pr5) CLIENT="geth-pr5" ;;
        nethermind) CLIENT="nethermind" ;;
        stable|xdc|geth) CLIENT="stable" ;;
        *) CLIENT="stable" ;;
    esac
    export CLIENT

    # Initialize
    init_logging
    show_banner
    
    log "Starting XDC Node Setup v$SCRIPT_VERSION"
    log "Mode: $(echo "$MODE" | tr '[:lower:]' '[:upper:]')"
    log "OS: $OS"
    
    # Checks
    check_root
    check_os_compatibility
    check_hardware
    
    # Initialize configuration
    init_config
    
    # Interactive prompts for advanced mode
    if [[ "$MODE" == "advanced" ]]; then
        prompt_advanced
    fi
    
    # Install dependencies
    install_dependencies
    install_docker
    
    # Configure and setup
    configure_node
    generate_config_toml
    setup_docker_compose
    setup_monitoring || warn "Monitoring setup had issues (non-fatal)"
    setup_security || warn "Security setup had issues (non-fatal)"
    setup_log_rotation_cron || warn "Log rotation cron setup had issues (non-fatal)"
    install_cli_tool || warn "CLI tool installation had issues (non-fatal)"
    
    # Start services — this is the critical step
    start_services
    
    # Register with SkyNet (non-fatal if API is unreachable)
    register_with_skynet || warn "SkyNet registration skipped — you can retry later with: xdc node --register-skynet"
    
    # Show summary
    print_summary
    
    log "Setup complete!"
}

main "$@"
