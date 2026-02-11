#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDC Node Setup Script
# Enterprise-grade XDC Network node deployment toolkit
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/xdc-node-setup.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    
    log "Detected Ubuntu $UBUNTU_VERSION"
}

check_hardware() {
    CPU_CORES=$(nproc)
    TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
    DISK_AVAIL=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    
    info "Hardware Check:"
    info "  CPU Cores: $CPU_CORES"
    info "  RAM: ${TOTAL_RAM}GB"
    info "  Disk Available: ${DISK_AVAIL}GB"
    
    if [[ $CPU_CORES -lt 8 ]]; then
        warn "Recommended: 8+ CPU cores (found: $CPU_CORES)"
    fi
    
    if [[ $TOTAL_RAM -lt 32 ]]; then
        warn "Recommended: 32GB+ RAM (found: ${TOTAL_RAM}GB)"
    fi
    
    if [[ $DISK_AVAIL -lt 100 ]]; then
        warn "Recommended: 100GB+ disk space (found: ${DISK_AVAIL}GB)"
    fi
}

#==============================================================================
# User Input
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
        unattended-upgrades
    
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
    
    log "Dependencies installed successfully"
}

#==============================================================================
# Node Configuration
#==============================================================================
configure_node() {
    log "Configuring XDC node..."
    
    # Create data directories
    mkdir -p /root/xdcchain/{XDC,keystore}
    mkdir -p /opt/xdc-node/{configs,scripts,logs}
    
    # Copy configuration files
    if [[ -f "$SCRIPT_DIR/configs/${NETWORK}.env" ]]; then
        cp "$SCRIPT_DIR/configs/${NETWORK}.env" /opt/xdc-node/configs/node.env
    else
        # Create default env file
        cat > /opt/xdc-node/configs/node.env << EOF
NETWORK=$NETWORK
CHAIN_ID=$CHAIN_ID
RPC_PORT=8545
WS_PORT=8546
P2P_PORT=30303
DATA_DIR=/root/xdcchain
SYNC_MODE=$NODE_TYPE
BOOTNODES=enode://1c20e6b46ce608c1fe739e78691227b2a174e0d9e79d5ef9a72c8069931057b73e7dbad8a55d2a123658f520a47888d2657314b7c9a55569e2db5e89f1e288dd@5.189.144.192:30303,enode://1c20e6b46ce608c1fe739e78691227b2a174e0d9e79d5ef9a72c8069931057b73e7dbad8a55d2a123658f520a47888d2657314b7c9a55569e2db5e89f1e288dd@88.99.97.197:30303
EOF
    fi
    
    # Set permissions
    chmod 750 /root/xdcchain
    chmod 700 /root/xdcchain/keystore
    
    log "Node configuration created at /opt/xdc-node/configs/"
}

#==============================================================================
# Genesis Configuration
#==============================================================================
generate_genesis() {
    log "Generating genesis configuration for $NETWORK..."
    
    local genesis_file="/root/xdcchain/genesis.json"
    
    if [[ "$NETWORK" == "mainnet" ]]; then
        # Download mainnet genesis
        curl -fsSL -o "$genesis_file" "https://raw.githubusercontent.com/XinFinOrg/XDPoSChain/master/genesis/mainnet.json" || {
            warn "Failed to download mainnet genesis, using fallback..."
            create_mainnet_genesis "$genesis_file"
        }
    else
        # Download testnet genesis
        curl -fsSL -o "$genesis_file" "https://raw.githubusercontent.com/XinFinOrg/XDPoSChain/master/genesis/testnet.json" || {
            warn "Failed to download testnet genesis, using fallback..."
            create_testnet_genesis "$genesis_file"
        }
    fi
    
    log "Genesis configuration saved to $genesis_file"
}

create_mainnet_genesis() {
    cat > "$1" << 'EOF'
{
  "config": {
    "chainId": 50,
    "homesteadBlock": 1,
    "eip150Block": 2,
    "eip150Hash": "0x0000000000000000000000000000000000000000000000000000000000000000",
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
}

create_testnet_genesis() {
    cat > "$1" << 'EOF'
{
  "config": {
    "chainId": 51,
    "homesteadBlock": 1,
    "eip150Block": 2,
    "eip150Hash": "0x0000000000000000000000000000000000000000000000000000000000000000",
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
}

#==============================================================================
# Firewall Configuration
#==============================================================================
configure_firewall() {
    log "Configuring firewall (UFW)..."
    
    # Reset UFW
    ufw --force reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH (using non-standard port if configured)
    SSH_PORT=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    ufw allow "$SSH_PORT/tcp" comment "SSH"
    
    # XDC P2P
    ufw allow 30303/tcp comment "XDC P2P"
    ufw allow 30303/udp comment "XDC P2P Discovery"
    
    # Prometheus (localhost only)
    ufw allow from 127.0.0.1 to any port 9090 comment "Prometheus (local only)"
    
    # Grafana (if exposing)
    # ufw allow 3000/tcp comment "Grafana"
    
    # Enable firewall
    echo "y" | ufw enable
    
    log "Firewall configured"
    ufw status verbose
}

#==============================================================================
# Fail2ban Configuration
#==============================================================================
configure_fail2ban() {
    log "Configuring fail2ban..."
    
    SSH_PORT=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = auto

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3

[docker-compose]
enabled = true
filter = docker-compose
port = all
logpath = /var/log/auth.log
maxretry = 5
EOF
    
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    log "Fail2ban configured and started"
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
    else
        create_docker_compose
    fi
    
    # Copy or create Dockerfile
    if [[ -f "$SCRIPT_DIR/docker/Dockerfile" ]]; then
        cp "$SCRIPT_DIR/docker/Dockerfile" /opt/xdc-node/docker/
    fi
    
    log "Docker Compose configuration ready"
}

create_docker_compose() {
    cat > /opt/xdc-node/docker/docker-compose.yml << 'EOF'
version: '3.8'

services:
  xdc-node:
    image: xinfinorg/xdposchain:latest
    container_name: xdc-node
    restart: unless-stopped
    ports:
      - "30303:30303"
      - "30303:30303/udp"
      - "8545:8545"
      - "8546:8546"
    volumes:
      - /root/xdcchain:/xdcchain
      - /opt/xdc-node/configs/node.env:/.env:ro
    environment:
      - NETWORK=${NETWORK:-mainnet}
      - SYNC_MODE=${SYNC_MODE:-full}
    command: >
      --datadir /xdcchain/XDC
      --syncmode ${SYNC_MODE:-full}
      --rpc
      --rpcaddr 0.0.0.0
      --rpcport 8545
      --rpcapi eth,net,web3,XDPoS
      --rpcvhosts "*"
      --ws
      --wsaddr 0.0.0.0
      --wsport 8546
      --wsorigins "*"
      --port 30303
      --nat any
    networks:
      - xdc-network
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8545", "||", "exit", "1"]
      interval: 30s
      timeout: 10s
      retries: 3

  prometheus:
    image: prom/prometheus:latest
    container_name: xdc-prometheus
    restart: unless-stopped
    ports:
      - "127.0.0.1:9090:9090"
    volumes:
      - /opt/xdc-node/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
      - '--storage.tsdb.retention.time=30d'
    networks:
      - xdc-network

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

  grafana:
    image: grafana/grafana:latest
    container_name: xdc-grafana
    restart: unless-stopped
    ports:
      - "127.0.0.1:3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-admin}
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana-data:/var/lib/grafana
      - /opt/xdc-node/monitoring/grafana/dashboards:/etc/grafana/provisioning/dashboards:ro
      - /opt/xdc-node/monitoring/grafana/datasources.yml:/etc/grafana/provisioning/datasources/datasources.yml:ro
    networks:
      - xdc-network

networks:
  xdc-network:
    driver: bridge

volumes:
  prometheus-data:
  grafana-data:
EOF
}

#==============================================================================
# Systemd Service
#==============================================================================
setup_systemd() {
    log "Setting up systemd service..."
    
    # Copy systemd files
    if [[ -f "$SCRIPT_DIR/systemd/xdc-node.service" ]]; then
        cp "$SCRIPT_DIR/systemd/xdc-node.service" /etc/systemd/system/
    else
        create_systemd_service
    fi
    
    systemctl daemon-reload
    
    log "Systemd service configured"
}

create_systemd_service() {
    cat > /etc/systemd/system/xdc-node.service << 'EOF'
[Unit]
Description=XDC Network Node
Documentation=https://docs.xdc.community
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/xdc-node/docker
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose restart
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
}

#==============================================================================
# Monitoring Setup
#==============================================================================
setup_monitoring() {
    log "Setting up monitoring..."
    
    mkdir -p /opt/xdc-node/monitoring/grafana/dashboards
    mkdir -p /opt/xdc-node/monitoring/grafana/datasources
    
    # Copy monitoring configs
    if [[ -f "$SCRIPT_DIR/monitoring/prometheus.yml" ]]; then
        cp "$SCRIPT_DIR/monitoring/prometheus.yml" /opt/xdc-node/monitoring/
    else
        create_prometheus_config
    fi
    
    # Copy Grafana dashboards
    if [[ -f "$SCRIPT_DIR/monitoring/grafana/dashboards/xdc-node.json" ]]; then
        cp "$SCRIPT_DIR/monitoring/grafana/dashboards/xdc-node.json" /opt/xdc-node/monitoring/grafana/dashboards/
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
    
    log "Monitoring stack configured"
}

create_prometheus_config() {
    cat > /opt/xdc-node/monitoring/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: []

rule_files:
  - "alerts.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'xdc-node'
    static_configs:
      - targets: ['xdc-node:6060']
    metrics_path: /debug/metrics/prometheus
EOF
}

#==============================================================================
# Scripts Installation
#==============================================================================
install_scripts() {
    log "Installing helper scripts..."
    
    mkdir -p /opt/xdc-node/scripts
    
    # Copy scripts
    for script in node-health-check.sh version-check.sh backup.sh security-harden.sh; do
        if [[ -f "$SCRIPT_DIR/scripts/$script" ]]; then
            cp "$SCRIPT_DIR/scripts/$script" /opt/xdc-node/scripts/
            chmod +x "/opt/xdc-node/scripts/$script"
        fi
    done
    
    # Copy configs
    if [[ -f "$SCRIPT_DIR/configs/versions.json" ]]; then
        cp "$SCRIPT_DIR/configs/versions.json" /opt/xdc-node/configs/
    fi
    
    log "Scripts installed to /opt/xdc-node/scripts/"
}

#==============================================================================
# Cron Jobs
#==============================================================================
setup_cron() {
    log "Setting up cron jobs..."
    
    if [[ -f "$SCRIPT_DIR/cron/setup-crons.sh" ]]; then
        cp "$SCRIPT_DIR/cron/setup-crons.sh" /opt/xdc-node/
        chmod +x /opt/xdc-node/setup-crons.sh
    fi
    
    # Create initial cron jobs
    cat > /etc/cron.d/xdc-node << 'EOF'
# XDC Node Monitoring
*/15 * * * * root /opt/xdc-node/scripts/node-health-check.sh >> /var/log/xdc-health-check.log 2>&1

# Version Check (every 6 hours)
0 */6 * * * root /opt/xdc-node/scripts/version-check.sh >> /var/log/xdc-version-check.log 2>&1

# Daily Backup
0 3 * * * root /opt/xdc-node/scripts/backup.sh >> /var/log/xdc-backup.log 2>&1

# Weekly Log Rotation
0 0 * * 0 root /usr/sbin/logrotate -f /etc/logrotate.d/xdc-node 2>/dev/null || true
EOF
    
    chmod 644 /etc/cron.d/xdc-node
    
    log "Cron jobs configured"
}

#==============================================================================
# Start Services
#==============================================================================
start_services() {
    log "Starting XDC node services..."
    
    cd /opt/xdc-node/docker
    
    # Pull latest images
    docker compose pull
    
    # Start services
    docker compose up -d
    
    # Enable systemd service
    systemctl enable xdc-node.service
    
    log "Services started successfully"
}

#==============================================================================
# Print Status
#==============================================================================
print_status() {
    echo ""
    echo "=================================="
    echo "    XDC Node Setup Complete!"
    echo "=================================="
    echo ""
    echo "Node Type: $NODE_TYPE"
    echo "Network: $NETWORK (Chain ID: $CHAIN_ID)"
    echo "Data Directory: /root/xdcchain"
    echo "Config Directory: /opt/xdc-node/configs"
    echo ""
    echo "Services:"
    echo "  XDC Node:     docker compose -f /opt/xdc-node/docker/docker-compose.yml ps"
    echo "  Logs:         docker compose -f /opt/xdc-node/docker/docker-compose.yml logs -f"
    echo "  Grafana:      http://localhost:3000 (admin/admin)"
    echo "  Prometheus:   http://localhost:9090"
    echo ""
    echo "Useful Commands:"
    echo "  Stop:         systemctl stop xdc-node"
    echo "  Start:        systemctl start xdc-node"
    echo "  Restart:      systemctl restart xdc-node"
    echo "  Health Check: /opt/xdc-node/scripts/node-health-check.sh"
    echo ""
    echo "Security:"
    echo "  Run security hardening: /opt/xdc-node/scripts/security-harden.sh"
    echo ""
    echo "Documentation: https://github.com/AnilChinchawale/XDC-Node-Setup"
    echo ""
}

#==============================================================================
# Main
#==============================================================================
main() {
    log "Starting XDC Node Setup..."
    
    check_root
    check_os
    check_hardware
    
    select_node_type
    select_network
    
    install_dependencies
    configure_node
    generate_genesis
    configure_firewall
    configure_fail2ban
    setup_docker_compose
    setup_systemd
    setup_monitoring
    install_scripts
    setup_cron
    start_services
    
    print_status
    
    log "Setup complete!"
}

# Run main function
main "$@"
