#!/usr/bin/env bash

# Source utility functions
source "$(dirname "$0")/lib/utils.sh" || { echo "Failed to load utils"; exit 1; }
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }

#==============================================================================
# XDC SkyOne SSL Setup Script
# Automates Let's Encrypt SSL certificate setup for SkyOne Dashboard
#==============================================================================

readonly SCRIPT_VERSION="1.0.0"
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Configuration
PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
NGINX_CONF_TEMPLATE="${PROJECT_DIR}/configs/nginx/skyone-ssl.conf"
CERTBOT_DIR="/etc/letsencrypt"
WEBROOT_PATH="/var/www/certbot"
DASHBOARD_PORT="${DASHBOARD_PORT:-7070}"
DOMAIN=""
EMAIL=""
STAGING=false
FORCE_RENEW=false
DRY_RUN=false

#==============================================================================
# Utility Functions
#==============================================================================


show_help() {
    cat << EOF
XDC SkyOne SSL Setup - Let's Encrypt automation for SkyOne Dashboard

Usage: $(basename "$0") [OPTIONS]

Options:
  -d, --domain DOMAIN       Domain name (required)
  -e, --email EMAIL         Email for Let's Encrypt notifications (required)
  -p, --port PORT           Dashboard port (default: 7070)
  -s, --staging             Use Let's Encrypt staging environment
  -f, --force-renew         Force certificate renewal
  --dry-run                 Test without making changes
  --renew                   Renew existing certificates only
  --revoke                  Revoke certificate (use with --domain)
  -h, --help                Show this help message
  --version                 Show version information

Examples:
  # Initial setup with new domain
  ./setup-ssl.sh --domain dashboard.example.com --email admin@example.com

  # Test with staging environment (no rate limits)
  ./setup-ssl.sh --domain dashboard.example.com --email admin@example.com --staging

  # Force renewal
  ./setup-ssl.sh --domain dashboard.example.com --force-renew

  # Using xdc CLI
  xdc ssl --domain dashboard.example.com --email admin@example.com

EOF
}

#==============================================================================
# Prerequisite Checks
#==============================================================================

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root. Try: sudo $0"
    fi
    
    # Check nginx
    if ! command -v nginx &>/dev/null; then
        warn "Nginx not found. Installing..."
        if command -v apt-get &>/dev/null; then
            apt-get update && apt-get install -y nginx
        elif command -v yum &>/dev/null; then
            yum install -y nginx
        elif command -v dnf &>/dev/null; then
            dnf install -y nginx
        else
            die "Could not install nginx. Please install it manually."
        fi
    fi
    
    # Check certbot
    if ! command -v certbot &>/dev/null; then
        warn "Certbot not found. Installing..."
        if command -v apt-get &>/dev/null; then
            apt-get update && apt-get install -y certbot python3-certbot-nginx
        elif command -v yum &>/dev/null; then
            yum install -y certbot python3-certbot-nginx
        elif command -v dnf &>/dev/null; then
            dnf install -y certbot python3-certbot-nginx
        else
            die "Could not install certbot. Please install it manually."
        fi
    fi
    
    # Check template file
    if [[ ! -f "$NGINX_CONF_TEMPLATE" ]]; then
        die "Nginx config template not found: $NGINX_CONF_TEMPLATE"
    fi
    
    log "Prerequisites check passed"
}

#==============================================================================
# Validation Functions
#==============================================================================

validate_domain() {
    local domain="$1"
    
    # Basic domain format validation
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        die "Invalid domain format: $domain"
    fi
    
    # Check DNS resolution
    info "Checking DNS resolution for $domain..."
    local resolved_ip
    resolved_ip=$(dig +short "$domain" 2>/dev/null || nslookup "$domain" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | tail -1 | awk '{print $2}' || echo "")
    
    if [[ -z "$resolved_ip" ]]; then
        warn "Could not resolve $domain. Make sure DNS is configured correctly."
        warn "Continuing anyway..."
    else
        # Get local IPs
        local local_ips
        local_ips=$(hostname -I 2>/dev/null || ifconfig | grep "inet " | awk '{print $2}' | tr '\n' ' ')
        
        if [[ "$local_ips" == *"$resolved_ip"* ]] || [[ "$resolved_ip" == "127.0.0.1" ]]; then
            log "DNS check passed: $domain resolves to this server ($resolved_ip)"
        else
            warn "$domain resolves to $resolved_ip"
            warn "Local IPs: $local_ips"
            warn "Make sure your domain points to this server's IP address"
        fi
    fi
}

validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        die "Invalid email format: $email"
    fi
}

#==============================================================================
# SSL Setup Functions
#==============================================================================

setup_webroot() {
    info "Setting up webroot for Let's Encrypt..."
    mkdir -p "$WEBROOT_PATH"
    chown -R www-data:www-data "$WEBROOT_PATH" 2>/dev/null || chown -R nginx:nginx "$WEBROOT_PATH" 2>/dev/null || true
    chmod 755 "$WEBROOT_PATH"
    log "Webroot directory created: $WEBROOT_PATH"
}

generate_nginx_config() {
    local domain="$1"
    local port="$2"
    local output_file="$3"
    
    info "Generating nginx configuration..."
    
    local cert_path key_path
    cert_path="${CERTBOT_DIR}/live/${domain}/fullchain.pem"
    key_path="${CERTBOT_DIR}/live/${domain}/privkey.pem"
    
    # Copy and replace template variables
    sed -e "s|{{DOMAIN}}|${domain}|g" \
        -e "s|{{DASHBOARD_PORT}}|${port}|g" \
        -e "s|{{SSL_CERT_PATH}}|${cert_path}|g" \
        -e "s|{{SSL_KEY_PATH}}|${key_path}|g" \
        "$NGINX_CONF_TEMPLATE" > "$output_file"
    
    log "Nginx config generated: $output_file"
}

obtain_certificate() {
    local domain="$1"
    local email="$2"
    
    info "Requesting Let's Encrypt certificate for $domain..."
    
    local certbot_args=(
        certonly
        --agree-tos
        --non-interactive
        --webroot
        -w "$WEBROOT_PATH"
        -d "$domain"
        -m "$email"
    )
    
    if [[ "$STAGING" == "true" ]]; then
        certbot_args+=(--staging)
        info "Using Let's Encrypt staging environment"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        certbot_args+=(--dry-run)
        info "Running in dry-run mode"
    fi
    
    if [[ "$FORCE_RENEW" == "true" ]]; then
        certbot_args+=(--force-renewal)
    fi
    
    if certbot "${certbot_args[@]}"; then
        log "Certificate obtained successfully!"
        return 0
    else
        error "Failed to obtain certificate"
        return 1
    fi
}

renew_certificates() {
    info "Renewing certificates..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        certbot renew --dry-run
    else
        certbot renew --quiet
        # Reload nginx to pick up new certificates
        systemctl reload nginx
        log "Certificates renewed successfully"
    fi
}

revoke_certificate() {
    local domain="$1"
    
    info "Revoking certificate for $domain..."
    
    if certbot revoke --cert-name "$domain" --non-interactive; then
        log "Certificate revoked successfully"
        
        # Remove nginx config
        if [[ -f "/etc/nginx/sites-enabled/${domain}" ]]; then
            rm -f "/etc/nginx/sites-enabled/${domain}"
        fi
        if [[ -f "/etc/nginx/sites-available/${domain}" ]]; then
            rm -f "/etc/nginx/sites-available/${domain}"
        fi
        
        systemctl reload nginx
        log "Nginx configuration removed"
    else
        error "Failed to revoke certificate"
    fi
}

#==============================================================================
# Main Setup
#==============================================================================

setup_ssl() {
    local domain="$1"
    local email="$2"
    
    print_banner
    
    check_prerequisites
    validate_domain "$domain"
    validate_email "$email"
    setup_webroot
    
    # Generate nginx config paths
    local nginx_available="/etc/nginx/sites-available/${domain}"
    local nginx_enabled="/etc/nginx/sites-enabled/${domain}"
    local nginx_default="/etc/nginx/sites-enabled/default"
    
    # Generate initial nginx config (HTTP only for initial validation)
    generate_nginx_config "$domain" "$DASHBOARD_PORT" "$nginx_available"
    
    # Enable site
    mkdir -p /etc/nginx/sites-enabled
    if [[ -f "$nginx_enabled" ]]; then
        rm -f "$nginx_enabled"
    fi
    ln -s "$nginx_available" "$nginx_enabled"
    
    # Remove default site to avoid conflicts
    if [[ -f "$nginx_default" ]]; then
        rm -f "$nginx_default"
        log "Removed default nginx site"
    fi
    
    # Test nginx configuration
    if ! nginx -t; then
        die "Nginx configuration test failed"
    fi
    
    # Start/reload nginx
    systemctl start nginx 2>/dev/null || true
    systemctl reload nginx || systemctl restart nginx
    
    # Obtain certificate
    if ! obtain_certificate "$domain" "$email"; then
        warn "Certificate issuance failed. Common issues:"
        warn "  1. Domain not pointing to this server"
        warn "  2. Firewall blocking port 80"
        warn "  3. Rate limits (use --staging for testing)"
        die "SSL setup failed"
    fi
    
    # Test final nginx configuration with SSL
    if ! nginx -t; then
        die "Nginx configuration test failed (SSL)"
    fi
    
    # Reload nginx with SSL
    systemctl reload nginx
    
    # Setup auto-renewal cron job
    setup_renewal_cron
    
    # Success output
    echo ""
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  SSL Setup Complete!${NC}"
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    log "Domain: https://${domain}"
    log "Dashboard Port: ${DASHBOARD_PORT}"
    log "Certificate: ${CERTBOT_DIR}/live/${domain}/"
    log "Nginx Config: ${nginx_available}"
    log "Auto-renewal: Enabled (cron daily)"
    echo ""
    info "Your SkyOne dashboard is now accessible via HTTPS"
    echo ""
}

setup_renewal_cron() {
    info "Setting up auto-renewal..."
    
    # Create renewal script
    local renew_script="/usr/local/bin/xdc-ssl-renew"
    cat > "$renew_script" << 'EOF'
#!/bin/bash
# Auto-renew Let's Encrypt certificates for XDC SkyOne

LOG_FILE="/var/log/xdc-ssl-renew.log"

echo "[$(date)] Starting certificate renewal check..." >> "$LOG_FILE"

if certbot renew --quiet --deploy-hook "systemctl reload nginx"; then
    echo "[$(date)] Certificate renewal successful" >> "$LOG_FILE"
else
    echo "[$(date)] Certificate renewal failed or not needed" >> "$LOG_FILE"
fi
EOF
    chmod +x "$renew_script"
    
    # Add cron job if not exists
    if ! crontab -l 2>/dev/null | grep -q "xdc-ssl-renew"; then
        (crontab -l 2>/dev/null; echo "0 3 * * * $renew_script > /dev/null 2>&1") | crontab -
        log "Auto-renewal cron job added (runs daily at 3:00 AM)"
    fi
}

#==============================================================================
# Parse Arguments & Main
#==============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--domain)
                DOMAIN="$2"
                shift 2
                ;;
            -e|--email)
                EMAIL="$2"
                shift 2
                ;;
            -p|--port)
                DASHBOARD_PORT="$2"
                shift 2
                ;;
            -s|--staging)
                STAGING=true
                shift
                ;;
            -f|--force-renew)
                FORCE_RENEW=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --renew)
                renew_certificates
                exit 0
                ;;
            --revoke)
                if [[ -z "$DOMAIN" ]]; then
                    die "Domain required for revocation. Use --domain"
                fi
                revoke_certificate "$DOMAIN"
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --version)
                echo "SkyOne SSL Setup v${SCRIPT_VERSION}"
                exit 0
                ;;
            *)
                warn "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

main() {
    parse_args "$@"
    
    if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
        show_help
        die "Domain and email are required. Use --domain and --email"
    fi
    
    setup_ssl "$DOMAIN" "$EMAIL"
}

main "$@"
