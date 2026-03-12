#!/bin/bash
# =============================================================================
# XDC SkyOne Agent - Entrypoint Script
# Handles initialization, configuration, and service startup
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# =============================================================================
# Configuration Setup
# =============================================================================

setup_skynet_config() {
    local config_file="/etc/xdc-node/skynet.conf"
    
    # If config doesn't exist or is a directory (Docker mount artifact), create it
    if [ ! -f "$config_file" ] || [ -d "$config_file" ]; then
        [ -d "$config_file" ] && rm -rf "$config_file"
        
        log_info "Creating SkyNet configuration..."
        cat > "$config_file" << EOF
# Auto-generated SkyNet Configuration
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

SKYNET_API_URL=${SKYNET_API_URL:-https://net.xdc.network/api}
SKYNET_API_KEY=${SKYNET_API_KEY:-}
SKYNET_NODE_ID=${SKYNET_NODE_ID:-}
SKYNET_NODE_NAME=${SKYNET_NODE_NAME:-$(hostname)}
SKYNET_ROLE=${SKYNET_ROLE:-fullnode}
EOF
        chmod 600 "$config_file"
        log_success "SkyNet configuration created"
    fi
    
    # Export config values
    set -a
    source "$config_file"
    set +a
}

setup_nginx_config() {
    local dashboard_port="${DASHBOARD_PORT:-7070}"
    local rpc_url="${XDC_RPC_URL:-http://localhost:8545}"
    
    log_info "Configuring Nginx for dashboard on port $dashboard_port..."
    
    cat > /etc/nginx/conf.d/default.conf << EOF
server {
    listen ${dashboard_port};
    server_name localhost;
    
    access_log /var/log/xdc/nginx-access.log;
    error_log /var/log/xdc/nginx-error.log;
    
    # Dashboard static files
    location / {
        root /app/dashboard/html;
        try_files \$uri \$uri/ /index.html;
        
        # Cache static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }
    
    # Dashboard API
    location /api/ {
        proxy_pass http://localhost:3000/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Prometheus metrics proxy
    location /metrics {
        proxy_pass http://localhost:6060/metrics;
        proxy_http_version 1.1;
    }
}
EOF
    
    log_success "Nginx configuration created"
}

# =============================================================================
# Service Initialization
# =============================================================================

init_directories() {
    log_info "Initializing directories..."
    
    mkdir -p /var/log/xdc /var/log/supervisor /run/nginx
    chown -R nobody:nobody /var/log/xdc /app/dashboard
    
    # Create Prometheus textfile directory
    mkdir -p /var/lib/node_exporter/textfile_collector
}

wait_for_dependencies() {
    local max_wait=30
    local waited=0
    
    # If running with external XDC node, verify connectivity
    if [ "${XDC_RPC_URL:-}" != "http://localhost:8545" ]; then
        log_info "Waiting for XDC node at $XDC_RPC_URL..."
        
        while [ $waited -lt $max_wait ]; do
            if curl -sf -m 2 -X POST "$XDC_RPC_URL" \
                -H "Content-Type: application/json" \
                -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' > /dev/null 2>&1; then
                log_success "XDC node is accessible"
                return 0
            fi
            sleep 1
            ((waited++))
        done
        
        log_warn "XDC node not responding after ${max_wait}s - dashboard may show errors"
    fi
}

# Bug #516: Setup private key for XDC node (xinfinorg/xdposchain:v2.6.8)
setup_xdc_private_key() {
    if [ -n "${PRIVATE_KEY:-}" ]; then
        log_info "Setting up PRIVATE_KEY for XDC node..."
        mkdir -p ~/.xdc
        echo "$PRIVATE_KEY" > ~/.xdc/private_key
        chmod 600 ~/.xdc/private_key
        log_success "Private key written to ~/.xdc/private_key"
    fi
}

# =============================================================================
# Main Entrypoint
# =============================================================================

main() {
    log_info "========================================"
    log_info "XDC SkyOne Agent v3.0.0"
    log_info "========================================"
    log_info "Node Type: ${NODE_TYPE:-full}"
    log_info "Network: ${NETWORK:-mainnet}"
    log_info "Dashboard Port: ${DASHBOARD_PORT:-7070}"
    log_info "XDC RPC: ${XDC_RPC_URL:-http://localhost:8545}"
    log_info "SkyNet: ${SKYNET_ENABLED:-true}"
    log_info "========================================"
    
    # Initialize
    init_directories
    setup_skynet_config
    setup_nginx_config
    setup_xdc_private_key
    
    # Wait for external dependencies
    wait_for_dependencies
    
    # Create supervisord config if not exists
    if [ ! -f /etc/supervisord.conf ]; then
        cat > /etc/supervisord.conf << 'EOF'
[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log
pidfile=/run/supervisord.pid
childlogdir=/var/log/supervisor

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///run/supervisord.sock

[unix_http_server]
file=/run/supervisord.sock
chmod=0700

[include]
files = /etc/supervisor.d/*.ini
EOF
    fi
    
    log_success "Initialization complete!"
    log_info "Starting services..."
    log_info "Dashboard will be available at: http://localhost:${DASHBOARD_PORT:-7070}"
    log_info ""
    
    # Execute the command (default: supervisord)
    exec "$@"
}

# Run main function
main "$@"
