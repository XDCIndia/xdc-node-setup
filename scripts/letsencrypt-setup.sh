#!/bin/bash
# =============================================================================
# XDC Node Setup - Let's Encrypt Certificate Setup
# =============================================================================
# Automates Let's Encrypt certificate generation for production use
#
# Usage:
#   ./scripts/letsencrypt-setup.sh -d node.example.com -e admin@example.com
#
# Requirements:
#   - Domain must point to this server's IP
#   - Ports 80 and 443 must be accessible from the internet
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CERTS_DIR="${PROJECT_ROOT}/certs"

# Default values
DOMAIN=""
EMAIL=""
STAGING=false
FORCE_RENEW=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

usage() {
    cat << EOF
Usage: $(basename "$0") -d <domain> -e <email> [OPTIONS]

Required:
  -d, --domain     Domain name (e.g., node.example.com)
  -e, --email      Contact email for Let's Encrypt

Optional:
  -s, --staging    Use Let's Encrypt staging server (for testing)
  -f, --force      Force certificate renewal
  -h, --help       Show this help message

Example:
  $(basename "$0") -d rpc.xdc.network -e admin@xdc.network
  $(basename "$0") -d rpc.xdc.network -e admin@xdc.network --staging
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -e|--email)
            EMAIL="$2"
            shift 2
            ;;
        -s|--staging)
            STAGING=true
            shift
            ;;
        -f|--force)
            FORCE_RENEW=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "${DOMAIN}" ]]; then
    log_error "Domain is required. Use -d or --domain"
    usage
    exit 1
fi

if [[ -z "${EMAIL}" ]]; then
    log_error "Email is required. Use -e or --email"
    usage
    exit 1
fi

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    log_step "Installing certbot..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y certbot
    elif command -v yum &> /dev/null; then
        sudo yum install -y certbot
    elif command -v apk &> /dev/null; then
        sudo apk add certbot
    else
        log_error "Could not install certbot automatically. Please install it manually."
        exit 1
    fi
fi

# Create necessary directories
mkdir -p "${CERTS_DIR}"
mkdir -p "${PROJECT_ROOT}/certbot/www"
mkdir -p "${PROJECT_ROOT}/certbot/conf"

log_step "Checking prerequisites..."

# Check if domain resolves to this server
log_info "Checking DNS resolution for ${DOMAIN}..."
PUBLIC_IP=$(curl -s https://api.ipify.org || echo "")
DOMAIN_IP=$(dig +short "${DOMAIN}" 2>/dev/null || nslookup "${DOMAIN}" 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}' || echo "")

if [[ -n "${PUBLIC_IP}" && -n "${DOMAIN_IP}" && "${PUBLIC_IP}" != "${DOMAIN_IP}" ]]; then
    log_warn "Domain ${DOMAIN} resolves to ${DOMAIN_IP}, but this server's IP is ${PUBLIC_IP}"
    log_warn "Please ensure your DNS A record points to this server before continuing"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    log_info "DNS check passed: ${DOMAIN} resolves to this server"
fi

# Check if ports are accessible
log_info "Checking port accessibility..."
if ! curl -s https://ports.yougetsignal.com/check-port.php &> /dev/null; then
    log_warn "Could not verify port accessibility automatically"
    log_warn "Ensure ports 80 and 443 are open in your firewall"
fi

log_step "Obtaining Let's Encrypt certificate..."

# Build certbot command
CERTBOT_ARGS=(
    certonly
    --agree-tos
    --non-interactive
    --email "${EMAIL}"
    -d "${DOMAIN}"
    --webroot
    -w "${PROJECT_ROOT}/certbot/www"
    --config-dir "${PROJECT_ROOT}/certbot/conf"
    --work-dir "${PROJECT_ROOT}/certbot/work"
    --logs-dir "${PROJECT_ROOT}/certbot/logs"
)

if [[ "${STAGING}" == true ]]; then
    CERTBOT_ARGS+=(--staging)
    log_warn "Using Let's Encrypt staging server (test certificates)"
fi

if [[ "${FORCE_RENEW}" == true ]]; then
    CERTBOT_ARGS+=(--force-renewal)
fi

# Run certbot
if certbot "${CERTBOT_ARGS[@]}"; then
    log_info "Certificate obtained successfully!"
    
    # Create symlinks for easier access
    ln -sf "${PROJECT_ROOT}/certbot/conf/live/${DOMAIN}/fullchain.pem" "${CERTS_DIR}/server.crt"
    ln -sf "${PROJECT_ROOT}/certbot/conf/live/${DOMAIN}/privkey.pem" "${CERTS_DIR}/server.key"
    
    log_info "Certificate paths:"
    log_info "  - Certificate: ${CERTS_DIR}/server.crt"
    log_info "  - Private key: ${CERTS_DIR}/server.key"
else
    log_error "Failed to obtain certificate"
    exit 1
fi

# Create renewal hook script
cat > "${PROJECT_ROOT}/certbot/renew-hook.sh" << EOF
#!/bin/bash
# Renew hook for XDC Node Setup
# Reload nginx after certificate renewal

echo "Certificate renewed for ${DOMAIN} - reloading nginx"

# Reload nginx container if running
if docker compose ps | grep -q nginx; then
    docker compose exec nginx nginx -s reload
fi
EOF
chmod +x "${PROJECT_ROOT}/certbot/renew-hook.sh"

# Create auto-renewal cron job
log_step "Setting up auto-renewal..."
CRON_JOB="0 3 * * * certbot renew --quiet --deploy-hook ${PROJECT_ROOT}/certbot/renew-hook.sh"

if ! (crontab -l 2>/dev/null | grep -q "certbot renew"); then
    (crontab -l 2>/dev/null; echo "${CRON_JOB}") | crontab -
    log_info "Auto-renewal cron job added (runs daily at 3:00 AM)"
else
    log_warn "Certbot renewal cron job already exists"
fi

# Create Docker Compose override
cat > "${CERTS_DIR}/docker-compose.letsencrypt.yml" << EOF
# Let's Encrypt TLS Docker Compose override
# Add this to your docker-compose command:
#   docker compose -f docker-compose.yml -f certs/docker-compose.letsencrypt.yml up -d

services:
  nginx:
    volumes:
      - ./certs:/certs:ro
      - ./certbot/www:/var/www/certbot:ro
      - ./certbot/conf:/etc/letsencrypt:ro
    ports:
      - "80:80"
      - "443:443"
    environment:
      - TLS_ENABLED=true
      - LETSENCRYPT_DOMAIN=${DOMAIN}
EOF

log_step "Setup complete!"
log_info "Next steps:"
log_info "  1. Start nginx with TLS: docker compose -f docker-compose.yml -f certs/docker-compose.letsencrypt.yml up -d"
log_info "  2. Test your HTTPS endpoint: https://${DOMAIN}"
log_info "  3. Certificates will auto-renew via cron job"

if [[ "${STAGING}" == true ]]; then
    log_warn "You used the staging server. Run again without --staging for production certificates."
fi
