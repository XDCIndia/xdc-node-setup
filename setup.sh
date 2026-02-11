#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDC Node Setup Script
# Enterprise-grade XDC Network node deployment toolkit
# Implements Section 8 of XDC-NODE-STANDARDS.md
# Supports: Interactive and --non-interactive modes
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/xdc-node-setup.log"

# Non-interactive mode variables
NON_INTERACTIVE=false
NODE_TYPE="${NODE_TYPE:-full}"      # full, archive, rpc
NETWORK="${NETWORK:-mainnet}"      # mainnet, testnet
SKIP_SECURITY="${SKIP_SECURITY:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#==============================================================================
# Logging Functions
#==============================================================================
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

#==============================================================================
# System Checks
#==============================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot determine OS version"
    fi
    
    source /etc/os-release
    
    if [[ "$ID" != "ubuntu" ]]; then
        error "This script only supports Ubuntu. Detected: $ID"
    fi
    
    UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d. -f1-2)
    SUPPORTED_VERSIONS=("20.04" "22.04" "24.04")
    
    if [[ ! " ${SUPPORTED_VERSIONS[*]} " =~ " ${UBUNTU_VERSION} " ]]; then
        error "Ubuntu $UBUNTU_VERSION is not supported. Supported versions: ${SUPPORTED_VERSIONS[*]}"
    fi
    
    log "✓ Detected Ubuntu $UBUNTU_VERSION (supported)"
}

check_hardware() {
    CPU_CORES=$(nproc)
    TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
    DISK_AVAIL=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    
    info "Hardware Check:"
    info "  CPU Cores: $CPU_CORES"
    info "  RAM: ${TOTAL_RAM}GB"
    info "  Disk Available: ${DISK_AVAIL}GB"
    
    local warnings=0
    
    if [[ $CPU_CORES -lt 8 ]]; then
        warn "Recommended: 8+ CPU cores (found: $CPU_CORES)"
        warnings=$((warnings + 1))
    fi
    
    if [[ $TOTAL_RAM -lt 32 ]]; then
        warn "Recommended: 32GB+ RAM (found: ${TOTAL_RAM}GB)"
        warnings=$((warnings + 1))
    fi
    
    if [[ $DISK_AVAIL -lt 100 ]]; then
        warn "Recommended: 100GB+ disk space (found: ${DISK_AVAIL}GB)"
        warnings=$((warnings + 1))
    fi
    
    if [[ $warnings -gt 0 && "$NON_INTERACTIVE" != true ]]; then
        read -rp "Continue anyway? [y/N]: " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
    fi
}

#==============================================================================
# User Input (Interactive Mode)
#==============================================================================
select_node_type() {
    echo ""
    echo "=================================="
    echo "    XDC Node Type Selection"
    echo "=================================="
    echo ""
    echo "1) Full Node - Standard full node (recommended)"
    echo "2) Archive Node - Complete blockchain history (~4TB)"
    echo "3) RPC Node - Optimized for RPC requests"
    echo ""
    
    while true; do
        read -rp "Select node type [1-3]: " choice
        case $choice in
            1) NODE_TYPE="full"; break ;;
            2) NODE_TYPE="archive"; break ;;
            3) NODE_TYPE="rpc"; break ;;
            *) echo "Invalid selection. Please choose 1-3." ;;
        esac
    done
    
    log "Selected node type: $NODE_TYPE"
}

select_network() {
    echo ""
    echo "=================================="
    echo "      Network Selection"
    echo "=================================="
    echo ""
    echo "1) Mainnet (XDC Network - Production)"
    echo "2) Testnet (Apothem - Development)"
    echo ""
    
    while true; do
        read -rp "Select network [1-2]: " choice
        case $choice in
            1) NETWORK="mainnet"; CHAIN_ID=50; break ;;
            2) NETWORK="testnet"; CHAIN_ID=51; break ;;
            *) echo "Invalid selection. Please choose 1-2." ;;
        esac
    done
    
    log "Selected network: $NETWORK (Chain ID: $CHAIN_ID)"
}

#==============================================================================
# Installation
#==============================================================================
install_dependencies() {
    log "Installing dependencies..."
    
    apt-get update -qq
    
    # Install essential packages
    apt-get install -y -qq \
        curl \
        wget \
        jq \
        git \
        ufw \
        fail2ban \
        auditd \
        audispd-plugins \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        unzip \
        htop \
        iotop \
        ncdu \
        logrotate \
        unattended-upgrades \
        rsync \
        gpg
    
    # Install Docker
    if ! command -v docker &> /dev/null; then
        log "Installing Docker..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
        # Enable Docker
        systemctl enable docker
        systemctl start docker
        log "✓ Docker installed"
    else
        log "✓ Docker already installed"
    fi
    
    # Install Docker Compose v2 (plugin)
    if ! docker compose version &> /dev/null; then
        log "Installing Docker Compose plugin..."
        apt-get install -y -qq docker-compose-plugin
    fi
    
    # Add current user to docker group (if not root)
    if [[ -n "${SUDO_USER:-}" ]]; then
        usermod -aG docker "$SUDO_USER" 2>/dev/null || true
    fi
    
    log "✓ Dependencies installed"
}

#==============================================================================
# Node Configuration
#==============================================================================
configure_node() {
    log "Configuring XDC node..."
    
    # Create data directories
    mkdir -p /root/xdcchain/{XDC,keystore}
    mkdir -p /opt/xdc-node/{configs,scripts,reports,logs}
    
    # Set permissions
    chmod 750 /root/xdcchain
    chmod 700 /root/xdcchain/keystore
    chmod 750 /opt/xdc-node
    
    # Copy configuration files
    if [[ -f "$SCRIPT_DIR/configs/${NETWORK}.env" ]]; then
        cp "$SCRIPT_DIR/configs/${NETWORK}.env" /opt/xdc-node/configs/node.env
    else
        # Create default env file
        cat > /opt/xdc-node/configs/node.env << EOF
# XDC Node Configuration
NETWORK=$NETWORK
CHAIN_ID=${CHAIN_ID:-50}
RPC_PORT=8545
WS_PORT=8546
P2P_PORT=30303
DATA_DIR=/root/xdcchain
SYNC_MODE=$NODE_TYPE
EOF
    fi
    
    # Copy versions.json
    if [[ -f "$SCRIPT_DIR/configs/versions.json" ]]; then
        cp "$SCRIPT_DIR/configs/versions.json" /opt/xdc-node/configs/
    fi
    
    # Set permissions
    chmod 600 /opt/xdc-node/configs/*.env 2>/dev/null || true
    chmod 600 /opt/xdc-node/configs/*.json 2>/dev/null || true
    
    log "✓ Node configuration created"
}

#==============================================================================
# Genesis Configuration
#==============================================================================
download_genesis() {
    log "Downloading genesis configuration for $NETWORK..."
    
    local genesis_file="/root/xdcchain/genesis.json"
    local genesis_url=""
    
    if [[ "$NETWORK" == "mainnet" ]]; then
        genesis_url="https://raw.githubusercontent.com/XinFinOrg/XDPoSChain/master/genesis/mainnet.json"
    else
        genesis_url="https://raw.githubusercontent.com/XinFinOrg/XDPoSChain/master/genesis/testnet.json"
    fi
    
    if curl -fsSL -o "$genesis_file" "$genesis_url" 2>> "$LOG_FILE"; then
        log "✓ Genesis downloaded from $genesis_url"
    else
        warn "Failed to download genesis, will use default"
        create_fallback_genesis "$genesis_file"
    fi
}

create_fallback_genesis() {
    cat > "$1" << 'EOF'
{
  "config": {
    "chainId": 50,
    "homesteadBlock": 1,
    "eip150Block": 2,
    "eip155Block": 3,
    "eip158Block": 3,
    "byzantiumBlock": 4,
    "XDPoS": {
      "period": 2,
      "epoch": 900,
      "reward": 5000,
      "rewardCheckpoint": 900,
      "gap": 450,
      "foudationWalletAddr": "xdc0000000000000000000000000000000000000068",
      "foudationRewardAddr": "xdc0000000000000000000000000000000000000069"
    }
  },
  "nonce": "0x0",
  "timestamp": "0x5d21a752",
  "extraData": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "gasLimit": "0x47b760",
  "difficulty": "0x1",
  "mixHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "coinbase": "xdc0000000000000000000000000000000000000000",
  "alloc": {},
  "number": "0x0",
  "gasUsed": "0x0",
  "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000"
}
EOF
    log "✓ Fallback genesis created"
}

#==============================================================================
# Docker Compose Setup
#==============================================================================
setup_docker_compose() {
    log "Setting up Docker Compose..."
    
    mkdir -p /opt/xdc-node/docker
    
    # Copy docker-compose.yml
    if [[ -f "$SCRIPT_DIR/docker/docker-compose.yml" ]]; then
        cp "$SCRIPT_DIR/docker/docker-compose.yml" /opt/xdc-node/docker/
        log "✓ docker-compose.yml copied"
    else
        error "docker-compose.yml not found in $SCRIPT_DIR/docker/"
    fi
    
    # Copy Dockerfile if exists
    if [[ -f "$SCRIPT_DIR/docker/Dockerfile" ]]; then
        cp "$SCRIPT_DIR/docker/Dockerfile" /opt/xdc-node/docker/
    fi
    
    log "✓ Docker Compose configuration ready"
}

#==============================================================================
# Monitoring Setup
#==============================================================================
setup_monitoring() {
    log "Setting up monitoring stack (Prometheus + Grafana)..."
    
    mkdir -p /opt/xdc-node/monitoring/grafana/{dashboards,datasources}
    
    # Copy monitoring configs
    if [[ -f "$SCRIPT_DIR/monitoring/prometheus.yml" ]]; then
        cp "$SCRIPT_DIR/monitoring/prometheus.yml" /opt/xdc-node/monitoring/
    fi
    
    if [[ -f "$SCRIPT_DIR/monitoring/alerts.yml" ]]; then
        cp "$SCRIPT_DIR/monitoring/alerts.yml" /opt/xdc-node/monitoring/
    fi
    
    # Copy Grafana dashboards
    if [[ -d "$SCRIPT_DIR/monitoring/grafana/dashboards" ]]; then
        cp -r "$SCRIPT_DIR/monitoring/grafana/dashboards/"* /opt/xdc-node/monitoring/grafana/dashboards/ 2>/dev/null || true
    fi
    
    # Create datasources config
    cat > /opt/xdc-node/monitoring/grafana/datasources.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
EOF
    
    # Create dashboard provisioning config
    cat > /opt/xdc-node/monitoring/grafana/dashboards.yml << 'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF
    
    log "✓ Monitoring stack configured"
}

#==============================================================================
# Security Hardening
#==============================================================================
run_security_hardening() {
    if [[ "$SKIP_SECURITY" == true ]]; then
        warn "Skipping security hardening (SKIP_SECURITY=true)"
        return 0
    fi
    
    log "Running security hardening..."
    
    if [[ -f "$SCRIPT_DIR/scripts/security-harden.sh" ]]; then
        cp "$SCRIPT_DIR/scripts/security-harden.sh" /opt/xdc-node/scripts/
        chmod +x /opt/xdc-node/scripts/security-harden.sh
        /opt/xdc-node/scripts/security-harden.sh 2>> "$LOG_FILE"
        log "✓ Security hardening complete"
    else
        warn "security-harden.sh not found, skipping"
    fi
}

#==============================================================================
# Scripts Installation
#==============================================================================
install_scripts() {
    log "Installing helper scripts..."
    
    mkdir -p /opt/xdc-node/scripts
    
    # Copy scripts
    for script in node-health-check.sh version-check.sh backup.sh; do
        if [[ -f "$SCRIPT_DIR/scripts/$script" ]]; then
            cp "$SCRIPT_DIR/scripts/$script" /opt/xdc-node/scripts/
            chmod +x "/opt/xdc-node/scripts/$script"
            log "✓ Installed: $script"
        fi
    done
    
    log "✓ Scripts installed to /opt/xdc-node/scripts/"
}

#==============================================================================
# Cron Jobs
#==============================================================================
setup_cron() {
    log "Setting up cron jobs..."
    
    # Run cron setup script if available
    if [[ -f "$SCRIPT_DIR/cron/setup-crons.sh" ]]; then
        cp "$SCRIPT_DIR/cron/setup-crons.sh" /opt/xdc-node/
        chmod +x /opt/xdc-node/setup-crons.sh
        /opt/xdc-node/setup-crons.sh 2>> "$LOG_FILE"
    else
        # Create basic cron jobs
        cat > /etc/cron.d/xdc-node << 'EOF'
# XDC Node Scheduled Tasks
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Health check every 15 minutes
*/15 * * * * root /opt/xdc-node/scripts/node-health-check.sh >> /var/log/xdc-health-check.log 2>&1

# Version check every 6 hours
17 */6 * * * root /opt/xdc-node/scripts/version-check.sh >> /var/log/xdc-version-check.log 2>&1

# Daily backup at 3:00 AM
0 3 * * * root /opt/xdc-node/scripts/backup.sh >> /var/log/xdc-backup.log 2>&1

# Weekly backup (Sunday 2:00 AM)
0 2 * * 0 root /opt/xdc-node/scripts/backup.sh >> /var/log/xdc-backup.log 2>&1

# Daily security check at 6:00 AM
0 6 * * * root /opt/xdc-node/scripts/node-health-check.sh --full >> /var/log/xdc-health-check.log 2>&1
EOF
        chmod 644 /etc/cron.d/xdc-node
    fi
    
    # Create log files
    touch /var/log/xdc-{health-check,version-check,backup,security-harden}.log 2>/dev/null || true
    chmod 640 /var/log/xdc-*.log 2>/dev/null || true
    
    log "✓ Cron jobs configured"
}

#==============================================================================
# Systemd Service
#==============================================================================
setup_systemd() {
    log "Setting up systemd service..."
    
    if [[ -f "$SCRIPT_DIR/systemd/xdc-node.service" ]]; then
        cp "$SCRIPT_DIR/systemd/xdc-node.service" /etc/systemd/system/
    else
        # Create default service file
        cat > /etc/systemd/system/xdc-node.service << 'EOF'
[Unit]
Description=XDC Network Node
Documentation=https://docs.xdc.community
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/xdc-node/docker
ExecStartPre=/usr/bin/docker compose pull --quiet
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose restart
TimeoutStartSec=300
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF
    fi
    
    systemctl daemon-reload
    systemctl enable xdc-node.service
    
    log "✓ Systemd service configured"
}

#==============================================================================
# Start Services
#==============================================================================
start_services() {
    log "Starting XDC node services..."
    
    cd /opt/xdc-node/docker
    
    # Pull latest images
    log "Pulling Docker images..."
    docker compose pull 2>> "$LOG_FILE"
    
    # Start services
    log "Starting containers..."
    docker compose up -d 2>> "$LOG_FILE"
    
    # Wait for containers to start
    sleep 5
    
    # Check status
    if docker compose ps | grep -q "Up"; then
        log "✓ Services started successfully"
    else
        warn "Some services may not have started properly"
    fi
}

#==============================================================================
# Get Node Status
#==============================================================================
get_node_status() {
    local status="unknown"
    local block_height="N/A"
    local peers="N/A"
    
    if docker ps | grep -q "xdc-node"; then
        status="running"
        
        # Try to get block height
        local response
        response=$(curl -s -m 5 -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            http://localhost:8545 2>/dev/null || echo '{}')
        
        local hex_height
        hex_height=$(echo "$response" | jq -r '.result // "0x0"')
        if [[ "$hex_height" != "0x0" ]]; then
            block_height=$((16#${hex_height#0x}))
        fi
        
        # Try to get peer count
        response=$(curl -s -m 5 -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
            http://localhost:8545 2>/dev/null || echo '{}')
        
        local hex_peers
        hex_peers=$(echo "$response" | jq -r '.result // "0x0"')
        if [[ -n "$hex_peers" ]]; then
            peers=$((16#${hex_peers#0x}))
        fi
    else
        status="not running"
    fi
    
    echo "$status|$block_height|$peers"
}

#==============================================================================
# Print Summary
#==============================================================================
print_summary() {
    local node_status
    local block_height
    local peers
    
    IFS='|' read -r node_status block_height peers <<< "$(get_node_status)"
    
    echo ""
    echo "=================================="
    echo "    XDC Node Setup Complete!"
    echo "=================================="
    echo ""
    echo "Configuration:"
    echo "  Node Type: $NODE_TYPE"
    echo "  Network: $NETWORK (Chain ID: ${CHAIN_ID:-50})"
    echo "  Data Directory: /root/xdcchain"
    echo "  Config Directory: /opt/xdc-node/configs"
    echo ""
    echo "Node Status:"
    echo "  Status: $node_status"
    echo "  Block Height: $block_height"
    echo "  Peers: $peers"
    echo ""
    echo "Services:"
    echo "  Docker: docker compose -f /opt/xdc-node/docker/docker-compose.yml ps"
    echo "  Logs:   docker compose -f /opt/xdc-node/docker/docker-compose.yml logs -f"
    echo "  Stop:   systemctl stop xdc-node"
    echo "  Start:  systemctl start xdc-node"
    echo ""
    echo "Dashboards:"
    echo "  Grafana:    http://localhost:3000 (admin/admin)"
    echo "  Prometheus: http://localhost:9090"
    echo ""
    echo "Useful Commands:"
    echo "  Health Check: /opt/xdc-node/scripts/node-health-check.sh"
    echo "  Security:     /opt/xdc-node/scripts/security-harden.sh"
    echo "  Backup:       /opt/xdc-node/scripts/backup.sh"
    echo ""
    echo "Next Steps:"
    echo "  1. Update Grafana password: docker exec xdc-grafana grafana-cli admin reset-admin-password <new-password>"
    echo "  2. Configure Telegram alerts in /opt/xdc-node/configs/versions.json"
    echo "  3. Run security hardening if not already done"
    echo "  4. Monitor sync progress: watch -n 30 'curl -s localhost:8545 -X POST ...'"
    echo ""
    echo "Documentation: https://github.com/AnilChinchawale/XDC-Node-Setup"
    echo ""
    
    # Save summary to file
    cat > /opt/xdc-node/SETUP_SUMMARY.txt << EOF
XDC Node Setup Summary
======================
Date: $(date)
Node Type: $NODE_TYPE
Network: $NETWORK
Status: $node_status
Block Height: $block_height
Peers: $peers

Quick Commands:
  docker compose -f /opt/xdc-node/docker/docker-compose.yml ps
  docker compose -f /opt/xdc-node/docker/docker-compose.yml logs -f
  systemctl status xdc-node

URLs:
  Grafana: http://localhost:3000
  Prometheus: http://localhost:9090
EOF
}

#==============================================================================
# Usage / Help
#==============================================================================
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

XDC Node Setup - Enterprise-grade XDC Network node deployment

Options:
  --non-interactive    Run in non-interactive mode (uses environment variables)
  --help, -h           Show this help message

Environment Variables (for --non-interactive):
  NODE_TYPE            Node type: full, archive, rpc (default: full)
  NETWORK              Network: mainnet, testnet (default: mainnet)
  SKIP_SECURITY        Skip security hardening: true/false (default: false)
  TELEGRAM_BOT_TOKEN   Telegram bot token for notifications
  TELEGRAM_CHAT_ID     Telegram chat ID for notifications

Examples:
  # Interactive mode (default)
  sudo ./setup.sh

  # Non-interactive mode
  sudo NODE_TYPE=full NETWORK=mainnet ./setup.sh --non-interactive

  # Archive node on testnet
  sudo NODE_TYPE=archive NETWORK=testnet ./setup.sh --non-interactive

EOF
}

#==============================================================================
# Main
#==============================================================================
main() {
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
        esac
    done
    
    # Initialize log
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    log "========================================"
    log "XDC Node Setup Starting"
    log "========================================"
    log "Mode: $([[ "$NON_INTERACTIVE" == true ]] && echo "NON-INTERACTIVE" || echo "INTERACTIVE")"
    
    check_root
    check_os
    check_hardware
    
    if [[ "$NON_INTERACTIVE" == true ]]; then
        # Validate environment variables
        case "$NODE_TYPE" in
            full|archive|rpc) ;;
            *) error "Invalid NODE_TYPE: $NODE_TYPE (must be full, archive, or rpc)" ;;
        esac
        
        case "$NETWORK" in
            mainnet) CHAIN_ID=50 ;;
            testnet) CHAIN_ID=51 ;;
            *) error "Invalid NETWORK: $NETWORK (must be mainnet or testnet)" ;;
        esac
        
        log "Configuration from environment:"
        log "  NODE_TYPE: $NODE_TYPE"
        log "  NETWORK: $NETWORK"
        log "  SKIP_SECURITY: $SKIP_SECURITY"
    else
        # Interactive mode
        select_node_type
        select_network
    fi
    
    install_dependencies
    configure_node
    download_genesis
    setup_docker_compose
    setup_monitoring
    install_scripts
    setup_systemd
    setup_cron
    run_security_hardening
    start_services
    
    print_summary
    
    log "========================================"
    log "Setup Complete!"
    log "========================================"
    log "See SETUP_SUMMARY.txt for details"
}

main "$@"
