#!/bin/bash
#===============================================================================
# XDC Node Setup - RPC Rate Limiting Setup Script
#===============================================================================
# Sets up nginx reverse proxy with rate limiting for XDC RPC endpoints
#
# Usage: sudo ./scripts/setup-rpc-rate-limiting.sh [install|remove|status]
#===============================================================================

set -euo pipefail

# Source common functions
source "$(dirname "$0")/../scripts/lib/common.sh" 2>/dev/null || {
    echo "ERROR: Could not source common.sh"
    exit 1
}

# Configuration
NGINX_CONFIG_SOURCE="${SCRIPT_DIR}/../nginx/rpc-proxy.conf"
NGINX_CONFIG_DEST="/etc/nginx/conf.d/xdc-rpc-proxy.conf"
SSL_CERT_DIR="/etc/xdc/certs"
RPC_PORT="${RPC_PORT:-8545}"
PROXY_PORT="${PROXY_PORT:-8546}"
WS_PORT="${WS_PORT:-8547}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARN:${NC} $*"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Install nginx and dependencies
install_nginx() {
    log "Installing nginx..."
    
    if command -v apt-get &>/dev/null; then
        apt-get update
        apt-get install -y nginx openssl
    elif command -v yum &>/dev/null; then
        yum install -y nginx openssl
    elif command -v dnf &>/dev/null; then
        dnf install -y nginx openssl
    else
        error "Unsupported package manager. Please install nginx manually."
        exit 1
    fi
    
    log "Nginx installed successfully"
}

# Generate self-signed SSL certificates (for initial setup)
generate_ssl_certs() {
    log "Generating SSL certificates..."
    
    mkdir -p "$SSL_CERT_DIR"
    
    if [[ -f "$SSL_CERT_DIR/node.crt" && -f "$SSL_CERT_DIR/node.key" ]]; then
        warn "SSL certificates already exist. Use existing? (y/n)"
        read -r response
        if [[ "$response" != "y" ]]; then
            log "Backing up existing certificates..."
            mv "$SSL_CERT_DIR/node.crt" "$SSL_CERT_DIR/node.crt.bak.$(date +%s)"
            mv "$SSL_CERT_DIR/node.key" "$SSL_CERT_DIR/node.key.bak.$(date +%s)"
        else
            return 0
        fi
    fi
    
    # Generate ECDSA private key and certificate
    openssl ecparam -genkey -name prime256v1 -out "$SSL_CERT_DIR/node.key"
    openssl req -new -x509 -key "$SSL_CERT_DIR/node.key" \
        -out "$SSL_CERT_DIR/node.crt" \
        -days 365 \
        -subj "/C=US/O=XDC Network/CN=xdc-node" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
    
    chmod 600 "$SSL_CERT_DIR/node.key"
    chmod 644 "$SSL_CERT_DIR/node.crt"
    
    log "SSL certificates generated at $SSL_CERT_DIR"
}

# Install nginx configuration
install_config() {
    log "Installing nginx configuration..."
    
    if [[ ! -f "$NGINX_CONFIG_SOURCE" ]]; then
        error "Nginx config not found at $NGINX_CONFIG_SOURCE"
        exit 1
    fi
    
    # Backup existing config
    if [[ -f "$NGINX_CONFIG_DEST" ]]; then
        cp "$NGINX_CONFIG_DEST" "$NGINX_CONFIG_DEST.bak.$(date +%s)"
    fi
    
    # Copy configuration
    cp "$NGINX_CONFIG_SOURCE" "$NGINX_CONFIG_DEST"
    
    # Update configuration with actual ports
    sed -i "s/server 127.0.0.1:8545/server 127.0.0.1:$RPC_PORT/" "$NGINX_CONFIG_DEST"
    
    # Test configuration
    if ! nginx -t; then
        error "Nginx configuration test failed"
        exit 1
    fi
    
    log "Nginx configuration installed"
}

# Start/restart nginx
start_nginx() {
    log "Starting nginx..."
    
    if systemctl is-active --quiet nginx; then
        systemctl reload nginx
    else
        systemctl start nginx
        systemctl enable nginx
    fi
    
    log "Nginx started successfully"
}

# Test rate limiting
test_rate_limit() {
    log "Testing rate limiting..."
    
    # Test normal request
    log "Testing normal request..."
    response=$(curl -sk -w "%{http_code}" -o /dev/null \
        -X POST https://localhost:$PROXY_PORT \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}')
    
    if [[ "$response" == "200" ]]; then
        log "✓ Normal request successful (HTTP 200)"
    else
        warn "✗ Normal request failed (HTTP $response)"
    fi
    
    # Test rate limit (send 15 requests rapidly)
    log "Testing rate limit (sending 15 rapid requests)..."
    local limited=0
    for i in {1..15}; do
        response=$(curl -sk -w "%{http_code}" -o /dev/null \
            -X POST https://localhost:$PROXY_PORT \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}')
        if [[ "$response" == "429" ]]; then
            limited=1
            break
        fi
    done
    
    if [[ "$limited" == "1" ]]; then
        log "✓ Rate limiting is working (HTTP 429 received)"
    else
        warn "✗ Rate limit not triggered (may need more requests)"
    fi
}

# Show current status
show_status() {
    log "Checking nginx status..."
    
    if systemctl is-active --quiet nginx; then
        log "✓ Nginx is running"
    else
        warn "✗ Nginx is not running"
        return 1
    fi
    
    # Check configuration
    if nginx -t &>/dev/null; then
        log "✓ Nginx configuration is valid"
    else
        warn "✗ Nginx configuration has errors"
        nginx -t
        return 1
    fi
    
    # Check ports
    if ss -tlnp | grep -q ":$PROXY_PORT"; then
        log "✓ Proxy port $PROXY_PORT is listening"
    else
        warn "✗ Proxy port $PROXY_PORT is not listening"
    fi
    
    # Show rate limit zones
    log "Rate limit zones:"
    grep "limit_req_zone" "$NGINX_CONFIG_DEST" 2>/dev/null || warn "No rate limit zones configured"
}

# Remove rate limiting setup
remove_setup() {
    log "Removing nginx rate limiting setup..."
    
    # Stop nginx
    systemctl stop nginx || true
    
    # Remove configuration
    if [[ -f "$NGINX_CONFIG_DEST" ]]; then
        mv "$NGINX_CONFIG_DEST" "$NGINX_CONFIG_DEST.removed.$(date +%s)"
    fi
    
    # Reload nginx main config (without our config)
    nginx -s reload 2>/dev/null || true
    
    log "Nginx rate limiting setup removed"
    log "Note: Nginx package was not removed. Use your package manager to remove it."
}

# Print usage
usage() {
    cat <<EOF
Usage: $0 [install|remove|status|test]

Commands:
    install   Install and configure nginx with rate limiting
    remove    Remove nginx rate limiting configuration
    status    Show current status
    test      Test rate limiting functionality
    help      Show this help message

Environment Variables:
    RPC_PORT      XDC RPC port (default: 8545)
    PROXY_PORT    Nginx proxy port (default: 8546)
    WS_PORT       WebSocket port (default: 8547)

Examples:
    sudo $0 install
    sudo $0 status
    sudo RPC_PORT=8555 $0 install
EOF
}

# Main function
main() {
    local command="${1:-install}"
    
    case "$command" in
        install)
            check_root
            install_nginx
            generate_ssl_certs
            install_config
            start_nginx
            test_rate_limit
            log "Rate limiting setup complete!"
            log "RPC endpoint available at: https://localhost:$PROXY_PORT"
            log "WebSocket endpoint available at: wss://localhost:$WS_PORT"
            ;;
        remove)
            check_root
            remove_setup
            ;;
        status)
            show_status
            ;;
        test)
            test_rate_limit
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
