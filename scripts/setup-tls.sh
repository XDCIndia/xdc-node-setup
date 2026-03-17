#!/usr/bin/env bash
#==============================================================================
# TLS/HTTPS Setup for Dashboard and RPC (Issue #497)
#==============================================================================
set -euo pipefail

DOMAIN="${1:-}"
EMAIL="${2:-}"

if [[ -z "$DOMAIN" ]]; then
    echo "Usage: $0 <domain> [email]"
    echo "Example: $0 rpc.xdc.network admin@xdc.network"
    exit 1
fi

echo "🔒 Setting up TLS for $DOMAIN..."

# Install certbot if needed
if ! command -v certbot >/dev/null 2>&1; then
    apt-get update && apt-get install -y certbot python3-certbot-nginx
fi

# Get certificate
certbot certonly --nginx -d "$DOMAIN" \
    ${EMAIL:+--email "$EMAIL"} \
    --agree-tos --non-interactive

echo "✅ TLS certificate installed for $DOMAIN"
echo "   Certificate: /etc/letsencrypt/live/$DOMAIN/"
echo "   Auto-renewal: certbot renew (via cron)"
