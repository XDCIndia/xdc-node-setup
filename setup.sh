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
source "${SCRIPT_DIR}/scripts/lib/utils.sh" 2>/dev/null || {
    # Fallback if utils.sh is not available
    detect_os() {
        case "$(uname -s)" in
            Linux*)
                if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
                    echo "wsl2"
                else
                    echo "linux"
                fi
                ;;
            Darwin*)    echo "macos";;
            MINGW*|CYGWIN*|MSYS*) echo "windows";;
            *)          echo "unknown";;
        esac
    }
    readonly OS=$(detect_os)

    sed_inplace() {
        local pattern="$1"
        local file="$2"
        if [[ "$OS" == "macos" ]]; then
            sed -i '' "$pattern" "$file"
        else
            sed -i "$pattern" "$file"
        fi
    }

    to_upper() { echo "$1" | tr '[:lower:]' '[:upper:]'; }
    to_lower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }
}

# Ensure OS is set
if [[ -z "${OS:-}" ]]; then
    readonly OS=$(detect_os)
fi

# Set OS-specific paths
if [[ "$OS" == "macos" ]]; then
    readonly DEFAULT_DATA_DIR="${PWD}/xdcchain"
    readonly LOG_FILE="${PWD}/xdc-node-setup.log"
    readonly INSTALL_DIR="${PWD}/.xdc-node"
    readonly CONFIG_DIR="${PWD}/.xdc-config"
else
    readonly DEFAULT_DATA_DIR="${PWD}/xdcchain"
    readonly LOG_FILE="${PWD}/xdc-node-setup.log"
    readonly INSTALL_DIR="${PWD}/.xdc-node"
    readonly CONFIG_DIR="${PWD}/.xdc-config"
fi

#==============================================================================
# Colors & UI
#==============================================================================
# Guard to prevent "readonly variable" error if colors already defined (e.g., from utils.sh)
if [[ -z "${RED:-}" ]]; then
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

# Ensure path is a file, not a directory (Docker creates dirs for missing volume mounts)
ensure_file_path() {
    local f="$1"
    if [[ -d "$f" ]]; then
        rm -rf "$f"
    fi
    mkdir -p "$(dirname "$f")"
    # Actually create the file to prevent Docker from creating it as a directory
    touch "$f"
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
 __  ______   ____  _   _______________________ 
 \ \/ /  _ \ / __ \/ | / / ____/_  __/  _/ __ \
  \  / / / / / / /  |/ / __/   / /  / // /_/ /
  / / /_/ / /_/ / /|  / /___  / / _/ // ____/ 
 /_/_____/\____/_/ |_/_____/ /_/ /___/_/      
                                               
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
  --network NETWORK   Network: mainnet, testnet, apothem (default: mainnet)
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
init_config() {
    # Node configuration with environment variable overrides
    NODE_TYPE="${NODE_TYPE:-full}"
    NETWORK="${NETWORK:-mainnet}"
    SYNC_MODE="${SYNC_MODE:-full}"
    DATA_DIR="${DATA_DIR:-$DEFAULT_DATA_DIR}"
    RPC_PORT="${RPC_PORT:-9545}"
    P2P_PORT="${P2P_PORT:-30303}"
    WS_PORT="${WS_PORT:-8546}"
    
    # Feature flags
    ENABLE_MONITORING="${ENABLE_MONITORING:-false}"
    ENABLE_SKYNET="${ENABLE_SKYNET:-false}"
    ENABLE_SECURITY="${ENABLE_SECURITY:-true}"
    ENABLE_NOTIFICATIONS="${ENABLE_NOTIFICATIONS:-false}"
    ENABLE_UPDATES="${ENABLE_UPDATES:-true}"
    INSTALL_CLI="${INSTALL_CLI:-true}"
    
    # Chain ID based on network
    if [[ "$NETWORK" == "mainnet" ]]; then
        CHAIN_ID=50
    else
        CHAIN_ID=51
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
    echo ""
    
    while true; do
        read -rp "Select network [1-2] (default: 1): " choice
        choice=${choice:-1}
        case $choice in
            1) NETWORK="mainnet"; CHAIN_ID=50; break ;;
            2) NETWORK="testnet"; CHAIN_ID=51; break ;;
            *) echo "Invalid selection. Please choose 1-2." ;;
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
    read -rp "Data directory [$DEFAULT_DATA_DIR]: " input
    DATA_DIR="${input:-$DEFAULT_DATA_DIR}"
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
    
    # Create directories
    mkdir -p "$DATA_DIR"/{XDC,keystore}
    mkdir -p "$INSTALL_DIR"/{configs,scripts,logs}
    
    # Set permissions
    chmod 750 "$DATA_DIR"
    chmod 700 "$DATA_DIR/keystore" 2>/dev/null || true
    chmod 750 "$INSTALL_DIR"
    
    # Create environment file
    ensure_file_path "$INSTALL_DIR/configs/node.env"
    cat > "$INSTALL_DIR/configs/node.env" << EOF
# XDC Node Configuration
# Generated on $(date)
NETWORK=$NETWORK
CHAIN_ID=$CHAIN_ID
NODE_TYPE=$NODE_TYPE
SYNC_MODE=$SYNC_MODE
DATA_DIR=$DATA_DIR
RPC_PORT=$RPC_PORT
WS_PORT=$WS_PORT
P2P_PORT=$P2P_PORT
ENABLE_MONITORING=$ENABLE_MONITORING
ENABLE_SECURITY=$ENABLE_SECURITY
ENABLE_NOTIFICATIONS=$ENABLE_NOTIFICATIONS
ENABLE_UPDATES=$ENABLE_UPDATES
EOF
    
    chmod 600 "$INSTALL_DIR/configs/node.env"
    log "Node configuration saved"
}

#==============================================================================
# Docker Compose Setup
#==============================================================================
setup_docker_compose() {
    log "Setting up Docker Compose..."
    
    mkdir -p "$INSTALL_DIR/docker"
    
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
    local docker_dir="$INSTALL_DIR/docker"
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
            cp "$bundled_dir/$f" "$network_dir/$f"
            log "Using bundled $f"
        # 2. Try alternate bundled path
        elif [[ -f "$alt_bundled/$f" ]]; then
            cp "$alt_bundled/$f" "$network_dir/$f"
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
                        cat > "$network_dir/start-node.sh" << 'STARTEOF'
#!/bin/bash
set -e
for bin in XDC XDC-mainnet XDC-testnet XDC-devnet; do
    command -v "$bin" &>/dev/null && { [ "$bin" != "XDC" ] && ln -sf "$(which "$bin")" /usr/bin/XDC; break; }
done
command -v XDC &>/dev/null || { echo "FATAL: No XDC binary"; exit 1; }
: "${SYNC_MODE:=full}" "${GC_MODE:=full}" "${LOG_LEVEL:=2}" "${RPC_ADDR:=0.0.0.0}" "${RPC_PORT:=8545}"
: "${RPC_API:=eth,net,web3,XDPoS}" "${WS_ADDR:=0.0.0.0}" "${WS_PORT:=8546}"
if [ ! -d /work/xdcchain/XDC/chaindata ]; then
    wallet=$(XDC account new --password /work/.pwd --datadir /work/xdcchain 2>/dev/null | awk -F '[{}]' '{print $2}')
    echo "$wallet" > /work/xdcchain/coinbase.txt
    XDC init --datadir /work/xdcchain /work/genesis.json
else
    wallet=$(XDC account list --datadir /work/xdcchain 2>/dev/null | head -1 | awk -F '[{}]' '{print $2}')
fi
bootnodes=""; [ -f /work/bootnodes.list ] && while IFS= read -r l; do [ -z "$l" ] && continue; [ -z "$bootnodes" ] && bootnodes="$l" || bootnodes="$bootnodes,$l"; done < /work/bootnodes.list
# Detect flag style
if XDC --help 2>&1 | grep -q '\-\-http.addr'; then
    RPC_FLAGS="--http --http.addr $RPC_ADDR --http.port $RPC_PORT --http.api $RPC_API --http.corsdomain * --http.vhosts * --ws --ws.addr $WS_ADDR --ws.port $WS_PORT --ws.origins *"
else
    RPC_FLAGS="--rpc --rpcaddr $RPC_ADDR --rpcport $RPC_PORT --rpcapi $RPC_API --rpccorsdomain * --rpcvhosts * --ws --wsaddr $WS_ADDR --wsport $WS_PORT --wsorigins *"
fi
exec XDC --datadir /work/xdcchain --networkid 50 --port 30303 --syncmode "$SYNC_MODE" --gcmode "$GC_MODE" \
    --verbosity "$LOG_LEVEL" --password /work/.pwd --mine --gasprice 1 --targetgaslimit 420000000 \
    ${wallet:+--unlock "$wallet"} ${bootnodes:+--bootnodes "$bootnodes"} \
    --ethstats "${INSTANCE_NAME:-XDC_Node}:xinfin_xdpos_hybrid_network_stats@stats.xinfin.network:3000" \
    --XDCx.datadir /work/xdcchain/XDCx $RPC_FLAGS "$@" 2>&1 | tee -a /work/xdcchain/xdc.log
STARTEOF
                    fi
                    chmod +x "$network_dir/start-node.sh"
                    ;;
                bootnodes.list)
                    warn "Generating bootnodes.list with default XDC bootnodes..."
                    cat > "$network_dir/bootnodes.list" << 'BNEOF'
enode://9a977b1ac4320fa2c862dcaf536aaaea3a8f8f7cd14e3bcde32e5a1c0152bd17bd18bfdc3c2ca8c4a0f3da153c62935fea1dc040cc1e66d2c07d6b4c91e2ed42@bootnode.xinfin.network:30303
BNEOF
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
    ensure_file_path "$network_dir/.env"
    cat > "$network_dir/.env" << ENVEOF
INSTANCE_NAME=XDC_Node
CONTACT_DETAILS=admin@localhost
SYNC_MODE=${SYNC_MODE}
GC_MODE=full
NETWORK=${NETWORK}
PRIVATE_KEY=0000000000000000000000000000000000000000000000000000000000000000
LOG_LEVEL=2
ENABLE_RPC=true
ENABLE_WS=true
RPC_ADDR=0.0.0.0
RPC_PORT=8545
RPC_API=eth,net,web3,XDPoS
RPC_CORS_DOMAIN=*
RPC_VHOSTS=*
WS_ADDR=0.0.0.0
WS_PORT=8546
WS_API=eth,net,web3,XDPoS
WS_ORIGINS=*
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
    
    # Create docker-compose.yml
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
      - ${DATA_DIR}:/work/xdcchain
      - ./mainnet/genesis.json:/work/genesis.json
      - ./mainnet/start-node.sh:/work/start.sh
      - ./entrypoint.sh:/work/entrypoint.sh
      - ./mainnet/bootnodes.list:/work/bootnodes.list
      - ./mainnet/.pwd:/work/.pwd
    env_file:
      - ./mainnet/.env
    entrypoint: /work/entrypoint.sh
      --ws
      --wsaddr 0.0.0.0
      --wsport 8546
      --wsorigins *
      --port 30303
      --maxpeers 50
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
        cat >> "$INSTALL_DIR/docker/docker-compose.yml" << 'EOF'

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
    cat >> "$INSTALL_DIR/docker/docker-compose.yml" << 'EOF'

  xdc-monitoring:
    image: alpine:3.19
    container_name: xdc-monitoring
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./skynet-agent.sh:/opt/skynet/agent.sh:ro
      - ./skynet.conf:/etc/xdc-node/skynet.conf:ro
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
          /opt/skynet/agent.sh 2>/dev/null && echo "[$(date '+%H:%M:%S')] heartbeat ok" || echo "[$(date '+%H:%M:%S')] heartbeat failed"
          sleep 60
        done
    depends_on:
      - xdc-node
    profiles:
      - skynet
EOF
    
    # Copy skynet agent files
    cp "$SCRIPT_DIR/scripts/skynet-agent.sh" "$INSTALL_DIR/docker/skynet-agent.sh" 2>/dev/null || \
        curl -sSL "https://raw.githubusercontent.com/XDC-Node-Setup/main/scripts/skynet-agent.sh" -o "$INSTALL_DIR/docker/skynet-agent.sh"
    chmod +x "$INSTALL_DIR/docker/skynet-agent.sh"
    
    # Create initial skynet.conf from template (will be updated after registration)
    if [[ ! -f "$INSTALL_DIR/docker/skynet.conf" ]]; then
        cp "$SCRIPT_DIR/configs/skynet.conf.template" "$INSTALL_DIR/docker/skynet.conf" 2>/dev/null || \
            curl -sSL "https://raw.githubusercontent.com/XDC-Node-Setup/main/configs/skynet.conf.template" -o "$INSTALL_DIR/docker/skynet.conf"
    fi

    # Close the compose file
    cat >> "$INSTALL_DIR/docker/docker-compose.yml" << EOF

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
    
    mkdir -p "$INSTALL_DIR/docker/grafana/provisioning"/{dashboards,datasources}
    
    # Create Prometheus config
    ensure_file_path "$INSTALL_DIR/docker/prometheus.yml"
    cat > "$INSTALL_DIR/docker/prometheus.yml" << EOF
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
    ensure_file_path "$INSTALL_DIR/docker/grafana/provisioning/datasources/datasource.yml"
    cat > "$INSTALL_DIR/docker/grafana/provisioning/datasources/datasource.yml" << 'EOF'
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
    ensure_file_path "$INSTALL_DIR/docker/grafana/provisioning/dashboards/dashboard.yml"
    cat > "$INSTALL_DIR/docker/grafana/provisioning/dashboards/dashboard.yml" << 'EOF'
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
# CLI Tool Installation
#==============================================================================
install_cli_tool() {
    [[ "$INSTALL_CLI" != "true" ]] && return 0
    
    log "Installing XDC CLI tool..."
    
    # Copy CLI script from bundled cli/xdc-node
    local cli_source="${SCRIPT_DIR}/cli/xdc-node"
    
    mkdir -p "$INSTALL_DIR/scripts"
    
    if [[ -f "$cli_source" ]]; then
        cp "$cli_source" "$INSTALL_DIR/scripts/xdc-node"
        chmod +x "$INSTALL_DIR/scripts/xdc-node"
        log "Installed CLI from bundled cli/xdc-node"
    else
        warn "CLI source not found at $cli_source, downloading..."
        curl -fsSL "https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/cli/xdc-node" \
            -o "$INSTALL_DIR/scripts/xdc-node" 2>/dev/null || {
            error "Failed to download CLI tool"
            return 1
        }
        chmod +x "$INSTALL_DIR/scripts/xdc-node"
    fi
    
    # Create state directories for CLI
    mkdir -p /var/lib/xdc-node
    chmod 750 /var/lib/xdc-node
    
    # Create symlink — try /usr/local/bin first, fall back to ~/.local/bin
    if [[ -w /usr/local/bin ]]; then
        ln -sf "$INSTALL_DIR/scripts/xdc-node" /usr/local/bin/xdc
        log "CLI installed at /usr/local/bin/xdc"
    elif sudo ln -sf "$INSTALL_DIR/scripts/xdc-node" /usr/local/bin/xdc 2>/dev/null; then
        log "CLI installed at /usr/local/bin/xdc (via sudo)"
    else
        mkdir -p "$HOME/.local/bin"
        ln -sf "$INSTALL_DIR/scripts/xdc-node" "$HOME/.local/bin/xdc"
        log "CLI installed at $HOME/.local/bin/xdc"
        # Add to PATH if needed
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc" 2>/dev/null || true
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc" 2>/dev/null || true
            export PATH="$HOME/.local/bin:$PATH"
            warn "Added ~/.local/bin to PATH. Run: source ~/.zshrc (or restart terminal)"
        fi
    fi
    
    log "CLI tool installed. Use: xdc-node help"
}

#==============================================================================
# Start Services
#==============================================================================
start_services() {
    log "Starting XDC node services..."
    
    cd "$INSTALL_DIR/docker"
    
    # Pull images
    info "Pulling Docker images..."
    docker compose pull &
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
    
    # Verify critical files exist and are actual files (not directories)
    for f in mainnet/start-node.sh mainnet/genesis.json mainnet/.pwd; do
        local fpath="$INSTALL_DIR/docker/$f"
        if [[ -d "$fpath" ]]; then
            warn "$f was created as a directory (Docker artifact). Removing and recreating..."
            rm -rf "$fpath"
        fi
        if [[ ! -f "$fpath" || ! -s "$fpath" ]]; then
            warn "$f is missing or empty. Re-downloading..."
            local base_url="https://raw.githubusercontent.com/XinFinOrg/XinFin-Node/master/mainnet"
            local fname=$(basename "$f")
            curl -fsSL "$base_url/$fname" -o "$fpath" 2>/dev/null || warn "Failed to download $fname"
            [[ "$fname" == "start-node.sh" ]] && chmod +x "$fpath" 2>/dev/null || true
            [[ "$fname" == ".pwd" ]] && { touch "$fpath"; chmod 600 "$fpath"; }
        fi
    done
    
    # Also remove any Docker-created directories in the data volume
    local container_name="xdc-node"
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        docker rm -f "$container_name" 2>/dev/null || true
    fi
    
    # Start services (remove orphans from other projects sharing this dir)
    info "Starting containers..."
    docker compose up -d --remove-orphans
    
    # Wait for startup
    sleep 5
    
    # Check status
    if docker compose ps | grep -q "Up"; then
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
            skynet_peers=$(curl -s -m 10 "https://net.xdc.network/api/v1/peers/healthy?format=enode&limit=10" 2>/dev/null | jq -r '.peers[]?.enode // empty' 2>/dev/null || true)
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
            if [[ -f "$INSTALL_DIR/docker/mainnet/bootnodes.list" ]]; then
                while IFS= read -r enode; do
                    [[ -z "$enode" || "$enode" == \#* ]] && continue
                    curl -s -m 5 -X POST http://127.0.0.1:${RPC_PORT:-9545} \
                        -H "Content-Type: application/json" \
                        -d "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addPeer\",\"params\":[\"$enode\"],\"id\":1}" >/dev/null 2>&1 || true
                done < "$INSTALL_DIR/docker/mainnet/bootnodes.list"
                log "Added peers from bootnodes.list"
            fi
        else
            log "Connected to $peer_count peers"
        fi
    else
        warn "Some services may not have started properly. Check logs with: docker compose logs"
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
    
    if [[ -f "$INSTALL_DIR/configs/node.env" ]]; then
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
    if [[ -f "$INSTALL_DIR/configs/node.env" ]]; then
        source "$INSTALL_DIR/configs/node.env"
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
        echo "  xdc-node logs    - View logs"
        echo "  xdc sync    - Check sync status"
        echo "  xdc health  - Health check"
    elif [[ "$status" == "installed" ]]; then
        echo -e "${YELLOW}Node is installed but not running.${NC}"
        echo "Start with: (cd $INSTALL_DIR/docker && docker compose up -d)"
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
    if [[ -f "$INSTALL_DIR/docker/docker-compose.yml" ]]; then
        (cd "$INSTALL_DIR/docker" && docker compose down -v 2>/dev/null) || true
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
    
    # Remove installation
    rm -rf "$INSTALL_DIR"
    rm -f "$CONFIG_DIR"
    
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
    local skynet_conf="$INSTALL_DIR/docker/skynet.conf"
    
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
        echo "Register your node for monitoring and alerts on https://net.xdc.network"
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
    response=$(curl -s -m 15 -X POST "https://net.xdc.network/api/v1/nodes/register" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null || echo '{"error":"connection_failed"}')
    
    # Check for API key in response
    local api_key
    api_key=$(echo "$response" | jq -r '.apiKey // empty' 2>/dev/null || echo "")
    
    if [[ -n "$api_key" && "$api_key" != "null" ]]; then
        log "✅ Node registered successfully with SkyNet!"
        
        # Create skynet.conf with the API key
        mkdir -p "$(dirname "$skynet_conf")"
        cat > "$skynet_conf" <<EOF
# XDC SkyNet Agent Configuration
# Auto-generated during node setup

SKYNET_API_URL=https://net.xdc.network/api/v1
SKYNET_NODE_NAME=${node_name}
SKYNET_API_KEY=${api_key}
SKYNET_ROLE=${node_role}
SKYNET_EMAIL=${email:-}
SKYNET_TELEGRAM=${telegram:-}
EOF
        chmod 600 "$skynet_conf"
        
        # Start xdc-monitoring container for heartbeat reporting
        if [[ -f "$INSTALL_DIR/docker/skynet-agent.sh" ]]; then
            if grep -q "xdc-monitoring:" "$INSTALL_DIR/docker/docker-compose.yml" 2>/dev/null; then
                (cd "$INSTALL_DIR/docker" && docker compose up -d xdc-monitoring 2>/dev/null) || \
                    warn "Could not start xdc-monitoring container. Start manually with: cd $INSTALL_DIR/docker && docker compose up -d xdc-monitoring"
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
        echo "View your node at: https://net.xdc.network"
        return 0
    else
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error // "Registration failed"' 2>/dev/null || echo "Registration failed")
        warn "SkyNet registration failed: $error_msg"
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
        echo -e "   ${BOLD}Dashboards:${NC}"
        echo -e "     Grafana:   http://localhost:3000 (admin/admin)"
        echo -e "     Dashboard: http://localhost:3001 (run: cd dashboard && npm run dev)"
    fi
    
    echo -e "   ${BOLD}CLI Commands:${NC}"
    echo "     xdc status     — Node status, block height, peers, sync %"
    echo "     xdc sync       — Detailed sync progress with progress bar"
    echo "     xdc health     — Comprehensive health check (score 0-100)"
    echo "     xdc-node security   — Server security audit (score 0-100)"
    echo "     xdc snapshot   — Restore from snapshot (with resume)"
    echo "     xdc attach     — Attach to node console"
    echo "     xdc-node info       — Node info (network, version, enode)"
    echo "     xdc-node peers      — List connected peers"
    echo "     xdc-node backup     — Backup keystore and configs"
    echo "     xdc monitor    — Security rotation reminders"
    echo "     xdc-node logs       — View node logs"
    echo "     xdc-node help       — Show all commands"
    echo ""
    echo -e "   ${BOLD}Next Steps:${NC}"
    echo "   1. Wait for sync to complete (~2-3 days for full node)"
    echo "   2. Check sync status: xdc sync"
    echo "   3. Monitor health: xdc health"
    echo "   4. Check security: xdc-node security"
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
    setup_docker_compose
    setup_monitoring || warn "Monitoring setup had issues (non-fatal)"
    setup_security || warn "Security setup had issues (non-fatal)"
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
