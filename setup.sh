#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDC Node Setup Script
# Production-ready XDC Network node deployment toolkit
# Supports: Linux (Ubuntu/Debian) and macOS
# Modes: Simple (default) and Advanced (--advanced)
#==============================================================================

# Script metadata
readonly SCRIPT_VERSION="2.1.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#==============================================================================
# OS Detection & Paths
#==============================================================================
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [[ -f /etc/os-release ]]; then
            source /etc/os-release
            if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
                echo "linux"
                return 0
            fi
        fi
        echo "unsupported"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unsupported"
    fi
}

readonly OS=$(detect_os)

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
    exit 1
}

#==============================================================================
# Cross-platform utilities (GNU vs BSD)
#==============================================================================
sed_inplace() {
    local pattern="$1"
    local file="$2"
    if [[ "$OS" == "macos" ]]; then
        sed -i '' "$pattern" "$file"
    else
        sed -i "$pattern" "$file"
    fi
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
  --advanced          Run in advanced mode (interactive prompts)
  --simple            Run in simple mode (default, no prompts)
  --status            Check current installation status
  --uninstall         Remove XDC node and all configurations
  --help, -h          Show this help message
  --version, -v       Show version information

Environment Variables:
  NODE_TYPE           Node type: full, archive, rpc, masternode (default: full)
  NETWORK             Network: mainnet, testnet (default: mainnet)
  DATA_DIR            Data directory (default: /root/xdcchain or ~/xdcchain)
  RPC_PORT            RPC port (default: 8545)
  P2P_PORT            P2P port (default: 30303)
  SYNC_MODE           Sync mode: full, snap (default: full)
  ENABLE_MONITORING   Enable monitoring: true/false (default: true)
  ENABLE_NETOWN       Enable NetOwn fleet monitoring: true/false (default: false)
  ENABLE_SECURITY     Enable security hardening: true/false (default: true)
  ENABLE_UPDATES      Enable auto-updates: true/false (default: true)
  HTTP_PROXY          HTTP proxy URL
  HTTPS_PROXY         HTTPS proxy URL

Examples:
  # Simple mode (default)
  curl -sSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/setup.sh | sudo bash

  # Advanced mode
  curl -sSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/setup.sh | sudo bash -s -- --advanced

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
        error "This script must be run as root on Linux. Try: sudo $0"
    fi
}

check_os_compatibility() {
    case "$OS" in
        linux)
            if [[ -f /etc/os-release ]]; then
                source /etc/os-release
                if [[ "$ID" == "ubuntu" ]]; then
                    local version
                    version=$(echo "$VERSION_ID" | cut -d. -f1)
                    if [[ "$version" -ge 20 ]]; then
                        log "Detected Ubuntu $VERSION_ID (supported)"
                        return 0
                    fi
                elif [[ "$ID" == "debian" ]]; then
                    local version
                    version=$(echo "$VERSION_ID" | cut -d. -f1)
                    if [[ "$version" -ge 11 ]]; then
                        log "Detected Debian $VERSION_ID (supported)"
                        return 0
                    fi
                fi
            fi
            warn "Unsupported Linux distribution. Ubuntu 20.04+ or Debian 11+ recommended."
            ;;
        macos)
            local mac_version
            mac_version=$(sw_vers -productVersion | cut -d. -f1-2)
            log "Detected macOS $mac_version"
            info "Note: Docker Desktop is required on macOS"
            ;;
        *)
            error "Unsupported operating system: $OSTYPE"
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
    
    if [[ $warnings -gt 0 && "$MODE" == "advanced" ]]; then
        read -rp "Continue anyway? [y/N]: " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
    elif [[ $warnings -gt 0 ]]; then
        warn "Proceeding with suboptimal hardware..."
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
        error "Docker Desktop is required on macOS. Please install from https://www.docker.com/products/docker-desktop"
    fi
    
    if ! docker info &> /dev/null; then
        error "Docker Desktop is installed but not running. Please start Docker Desktop."
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
            error "Homebrew is required. Install from https://brew.sh"
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
    RPC_PORT="${RPC_PORT:-8545}"
    P2P_PORT="${P2P_PORT:-30303}"
    WS_PORT="${WS_PORT:-8546}"
    
    # Feature flags
    ENABLE_MONITORING="${ENABLE_MONITORING:-true}"
    ENABLE_NETOWN="${ENABLE_NETOWN:-false}"
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
    
    read -rp "RPC port [8545]: " input
    RPC_PORT="${input:-8545}"
    
    read -rp "P2P port [30303]: " input
    P2P_PORT="${input:-30303}"
    
    log "RPC port: $RPC_PORT, P2P port: $P2P_PORT"
}

prompt_features() {
    echo ""
    echo -e "${BOLD}Feature Configuration${NC}"
    echo "======================"
    
    read -rp "Enable monitoring (Grafana + Prometheus)? [Y/n]: " input
    [[ ! "${input:-Y}" =~ ^[Nn]$ ]] && ENABLE_MONITORING="true" || ENABLE_MONITORING="false"
    
    read -rp "Enable NetOwn fleet monitoring? [y/N]: " input
    [[ "${input:-N}" =~ ^[Yy]$ ]] && ENABLE_NETOWN="true" || ENABLE_NETOWN="false"
    
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
    
    log "Monitoring: $ENABLE_MONITORING, NetOwn: $ENABLE_NETOWN, Security: $ENABLE_SECURITY, Notifications: $ENABLE_NOTIFICATIONS, Updates: $ENABLE_UPDATES, CLI: $INSTALL_CLI"
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
    
    # Determine Docker image and flags based on node type
    local xdc_image="xinfinorg/xdposchain:v2.6.8"
    local docker_dir="$INSTALL_DIR/docker"
    local network_dir="$docker_dir/mainnet"
    
    mkdir -p "$network_dir"
    
    # Download official XDC node files from XinFinOrg
    log "Downloading XDC node configuration files..."
    local base_url="https://raw.githubusercontent.com/XinFinOrg/XinFin-Node/master/mainnet"
    
    # First try bundled files from the repo, then fall back to download
    local script_base="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local bundled_dir="$script_base/docker/mainnet"
    
    for f in genesis.json start-node.sh bootnodes.list; do
        if [[ -f "$bundled_dir/$f" ]]; then
            cp "$bundled_dir/$f" "$network_dir/$f"
            log "Using bundled $f"
        else
            if ! curl -fsSL --connect-timeout 10 "$base_url/$f" -o "$network_dir/$f" 2>/dev/null; then
                warn "Failed to download $f — check your internet connection"
                warn "You can manually place $f in $network_dir/"
            else
                log "Downloaded $f"
            fi
        fi
    done
    chmod +x "$network_dir/start-node.sh" 2>/dev/null || true
    
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
RPC_API=eth,net,web3,XDPoS
ENVEOF

    # Create password file (remove if Docker created it as a directory)
    if [[ -d "$network_dir/.pwd" ]]; then
        rm -rf "$network_dir/.pwd"
    fi
    if [[ ! -f "$network_dir/.pwd" ]]; then
        openssl rand -base64 32 > "$network_dir/.pwd" 2>/dev/null || echo "xdc-node-password" > "$network_dir/.pwd"
    fi
    chmod 600 "$network_dir/.pwd" 2>/dev/null || true
    
    # Create docker-compose.yml
    cat > "$docker_dir/docker-compose.yml" << EOF
services:
  xdc-node:
    image: $xdc_image
    container_name: xdc-node
    restart: always
    ports:
      - "${RPC_PORT}:8545"
      - "${WS_PORT}:8546"
      - "${P2P_PORT}:30303"
      - "${P2P_PORT}:30303/udp"
    volumes:
      - ${DATA_DIR}:/work/xdcchain
      - ./mainnet/genesis.json:/work/genesis.json
      - ./mainnet/start-node.sh:/work/start.sh
      - ./mainnet/bootnodes.list:/work/bootnodes.list
      - ./mainnet/.pwd:/work/.pwd
    env_file:
      - ./mainnet/.env
    entrypoint: /work/start.sh
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

    # Add NetOwn agent if enabled
    if [[ "$ENABLE_NETOWN" == "true" ]]; then
        cat >> "$INSTALL_DIR/docker/docker-compose.yml" << 'EOF'

  netown-agent:
    image: alpine:3.19
    container_name: netown-agent
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./netown-agent.sh:/agent.sh:ro
      - ./netown.conf:/etc/xdc-node/netown.conf:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /etc/ssh/sshd_config:/host/sshd_config:ro
      - /proc:/host/proc:ro
    environment:
      - NETOWN_CONF=/etc/xdc-node/netown.conf
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        apk add --no-cache bash curl jq bc procps >/dev/null 2>&1
        chmod +x /agent.sh
        echo "NetOwn Agent started - reporting every 60s"
        while true; do
          /agent.sh 2>/dev/null
          sleep 60
        done
    depends_on:
      - xdc-node
EOF
        
        # Copy netown agent files
        cp "$SCRIPT_DIR/scripts/netown-agent.sh" "$INSTALL_DIR/docker/netown-agent.sh" 2>/dev/null || \
            curl -sSL "https://raw.githubusercontent.com/XDC-Node-Setup/main/scripts/netown-agent.sh" -o "$INSTALL_DIR/docker/netown-agent.sh"
        chmod +x "$INSTALL_DIR/docker/netown-agent.sh"
        
        # Create netown.conf from template
        if [[ ! -f "$INSTALL_DIR/docker/netown.conf" ]]; then
            cp "$SCRIPT_DIR/configs/netown.conf.template" "$INSTALL_DIR/docker/netown.conf" 2>/dev/null || \
                curl -sSL "https://raw.githubusercontent.com/XDC-Node-Setup/main/configs/netown.conf.template" -o "$INSTALL_DIR/docker/netown.conf"
            warn "Please edit $INSTALL_DIR/docker/netown.conf with your NetOwn API credentials"
        fi
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
    
    # UFW Firewall
    if command -v ufw &> /dev/null; then
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow 22/tcp comment 'SSH'
        ufw allow ${RPC_PORT}/tcp comment 'XDC RPC'
        ufw allow ${P2P_PORT}/tcp comment 'XDC P2P'
        ufw allow ${P2P_PORT}/udp comment 'XDC P2P UDP'
        
        if [[ "$ENABLE_MONITORING" == "true" ]]; then
            ufw allow 3000/tcp comment 'Grafana'
            ufw allow 9090/tcp comment 'Prometheus (local only recommended)'
        fi
        
        ufw --force enable
        log "UFW firewall configured"
    fi
    
    # Fail2ban
    if command -v fail2ban-client &> /dev/null; then
        systemctl enable fail2ban
        systemctl start fail2ban
        log "Fail2ban enabled"
    fi
    
    log "Security hardening complete"
}

#==============================================================================
# CLI Tool Installation
#==============================================================================
install_cli_tool() {
    [[ "$INSTALL_CLI" != "true" ]] && return 0
    
    log "Installing XDC CLI tool..."
    
    # Create CLI script
    ensure_file_path "$INSTALL_DIR/scripts/xdc-node"
    cat > "$INSTALL_DIR/scripts/xdc-node" << 'EOF'
#!/usr/bin/env bash
# XDC Node CLI Tool

CMD="${1:-status}"
INSTALL_DIR="/opt/xdc-node"
[[ "$OSTYPE" == "darwin"* ]] && INSTALL_DIR="$HOME/.xdc-node"

case "$CMD" in
    status)
        echo "XDC Node Status"
        echo "==============="
        docker ps --filter "name=xdc-node" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Docker not available"
        ;;
    sync)
        echo "Checking sync status..."
        curl -s -X POST http://localhost:8545 \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' | jq . 2>/dev/null || echo "Node not responding"
        ;;
    health)
        echo "Health check..."
        curl -s -X POST http://localhost:8545 \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq . 2>/dev/null || echo "Node not responding"
        ;;
    logs)
        docker logs -f xdc-node 2>/dev/null || echo "Container not found"
        ;;
    stop)
        echo "Stopping XDC node..."
        (cd "$INSTALL_DIR/docker" && docker compose stop)
        ;;
    start)
        echo "Starting XDC node..."
        (cd "$INSTALL_DIR/docker" && docker compose start)
        ;;
    restart)
        echo "Restarting XDC node..."
        (cd "$INSTALL_DIR/docker" && docker compose restart)
        ;;
    update)
        echo "Updating XDC node..."
        (cd "$INSTALL_DIR/docker" && docker compose pull && docker compose up -d)
        ;;
    help|*)
        echo "XDC Node CLI"
        echo "Usage: xdc-node <command>"
        echo ""
        echo "Commands:"
        echo "  status   - Show node status"
        echo "  sync     - Check sync status"
        echo "  health   - Health check"
        echo "  logs     - View logs"
        echo "  stop     - Stop node"
        echo "  start    - Start node"
        echo "  restart  - Restart node"
        echo "  update   - Update to latest version"
        echo "  help     - Show this help"
        ;;
esac
EOF

    chmod +x "$INSTALL_DIR/scripts/xdc-node"
    
    # Create symlink
    if [[ "$OS" == "linux" ]]; then
        ln -sf "$INSTALL_DIR/scripts/xdc-node" /usr/local/bin/xdc-node
    else
        mkdir -p "$HOME/.local/bin"
        ln -sf "$INSTALL_DIR/scripts/xdc-node" "$HOME/.local/bin/xdc-node"
        # Add to PATH if needed
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc" 2>/dev/null || true
        fi
    fi
    
    log "CLI tool installed. Use: xdc-node <command>"
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
    
    # Start services
    info "Starting containers..."
    docker compose up -d
    
    # Wait for startup
    sleep 5
    
    # Check status
    if docker compose ps | grep -q "Up"; then
        log "Services started successfully"
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
        
        if docker ps --format '{{.Names}}' | grep -q "xdc-node"; then
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
    echo -e "  ${BLUE}RPC:${NC}         http://127.0.0.1:${RPC_PORT:-8545}"
    echo -e "  ${BLUE}Block Height:${NC} $block_height"
    echo -e "  ${BLUE}Sync Status:${NC} $sync_status"
    echo ""
    
    if [[ "$status" == "running" ]]; then
        echo -e "${GREEN}Node is running!${NC}"
        echo ""
        echo "Useful commands:"
        echo "  xdc-node logs    - View logs"
        echo "  xdc-node sync    - Check sync status"
        echo "  xdc-node health  - Health check"
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
    rm -f /usr/local/bin/xdc-node "$HOME/.local/bin/xdc-node"
    
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
    
    echo -e "   ${BOLD}CLI:${NC}        xdc-node status"
    echo ""
    echo -e "   ${BOLD}Next Steps:${NC}"
    echo "   1. Wait for sync to complete (~2-3 days for full node)"
    echo "   2. Check sync status: xdc-node sync"
    echo "   3. Monitor health: xdc-node health"
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
    
    for arg in "$@"; do
        case $arg in
            --advanced)
                MODE="advanced"
                shift
                ;;
            --simple)
                MODE="simple"
                shift
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
    setup_monitoring
    setup_security
    install_cli_tool
    
    # Start services
    start_services
    
    # Show summary
    print_summary
    
    log "Setup complete!"
}

main "$@"
