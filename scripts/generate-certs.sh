#!/bin/bash
# =============================================================================
# XDC Node Setup - Self-Signed Certificate Generator
# =============================================================================
# Generates self-signed TLS certificates for RPC proxy
#
# Usage:
#   ./scripts/generate-certs.sh [output_dir]
#
# Default output directory: ./certs
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CERTS_DIR="${1:-${PROJECT_ROOT}/certs}"
DAYS_VALID=365
KEY_SIZE=2048

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if openssl is installed
if ! command -v openssl &> /dev/null; then
    log_error "openssl is not installed. Please install it first."
    exit 1
fi

# Create certs directory if it doesn't exist
mkdir -p "${CERTS_DIR}"

log_info "Generating self-signed TLS certificates..."
log_info "Output directory: ${CERTS_DIR}"
log_info "Certificate validity: ${DAYS_VALID} days"

# Generate private key and certificate
openssl req -x509 -nodes -days "${DAYS_VALID}" -newkey "rsa:${KEY_SIZE}" \
    -keyout "${CERTS_DIR}/server.key" \
    -out "${CERTS_DIR}/server.crt" \
    -subj "/C=US/ST=State/L=City/O=XDC Network/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,DNS:*.localhost,IP:127.0.0.1,IP:::1"

# Set appropriate permissions
chmod 600 "${CERTS_DIR}/server.key"
chmod 644 "${CERTS_DIR}/server.crt"

log_info "Certificates generated successfully!"
log_info "  - Private key: ${CERTS_DIR}/server.key"
log_info "  - Certificate: ${CERTS_DIR}/server.crt"

log_warn "These are self-signed certificates. Browsers will show a warning."
log_warn "For production, use Let's Encrypt or obtain certificates from a trusted CA."

# Generate Docker Compose override snippet
cat > "${CERTS_DIR}/docker-compose.tls.yml" << 'EOF'
# TLS-enabled Docker Compose override
# Add this to your docker-compose command:
#   docker compose -f docker-compose.yml -f certs/docker-compose.tls.yml up -d

services:
  nginx:
    volumes:
      - ./certs:/certs:ro
    ports:
      - "443:443"
    environment:
      - TLS_ENABLED=true
EOF

log_info "Docker Compose TLS override created: ${CERTS_DIR}/docker-compose.tls.yml"
