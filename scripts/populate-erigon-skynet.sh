#!/bin/bash

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }
#
#
# Populate skynet-erigon.conf with registered node details
# Run this after your erigon node has been registered on SkyNet
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NETWORK="${NETWORK:-mainnet}"
CONF_FILE="$PROJECT_ROOT/$NETWORK/.xdc-node/skynet-erigon.conf"

# Check if already populated
if [[ -f "$CONF_FILE" ]] && grep -q "SKYNET_NODE_ID=.\+" "$CONF_FILE" 2>/dev/null; then
    echo "✅ $CONF_FILE already configured with NODE_ID"
    grep "SKYNET_NODE_ID\|SKYNET_NODE_NAME" "$CONF_FILE"
    exit 0
fi

# Get values from geth conf as reference
GETH_CONF="$PROJECT_ROOT/$NETWORK/.xdc-node/skynet.conf"
if [[ -f "$GETH_CONF" ]]; then
    echo "📋 Loading defaults from $GETH_CONF..."
    source "$GETH_CONF" || true
fi

# Prompt for values
echo ""
echo "🔧 Erigon SkyNet Configuration"
echo "================================"
echo ""
echo "Your erigon node needs a separate registration from geth."
echo "If you already registered it, enter the node ID below."
echo "Otherwise, leave it empty and the agent will auto-register."
echo ""

read -p "SKYNET_NODE_ID (or press Enter to auto-register): " NODE_ID
read -p "SKYNET_NODE_NAME [mac-erigon-xdc-mumbai]: " NODE_NAME
NODE_NAME="${NODE_NAME:-mac-erigon-xdc-mumbai}"

# Copy email/telegram from geth conf if available
EMAIL="${SKYNET_EMAIL:-}"
TELEGRAM="${SKYNET_TELEGRAM:-}"

if [[ -z "$EMAIL" ]]; then
    read -p "Email for alerts (optional): " EMAIL
fi

if [[ -z "$TELEGRAM" ]]; then
    read -p "Telegram handle (optional): " TELEGRAM
fi

# Write config
cat > "$CONF_FILE" << EOF
SKYNET_API_URL=https://net.xdc.network/api/v1
SKYNET_API_KEY=
SKYNET_NODE_ID=${NODE_ID}
SKYNET_NODE_NAME=${NODE_NAME}
SKYNET_ROLE=fullnode
SKYNET_EMAIL=${EMAIL}
SKYNET_TELEGRAM=${TELEGRAM}
EOF

chmod 600 "$CONF_FILE"

echo ""
echo "✅ Created $CONF_FILE"
echo ""
echo "Next steps:"
echo "  1. docker compose -f docker/docker-compose.erigon-standalone.yml restart xdc-agent-erigon"
echo "  2. Check logs: docker compose -f docker/docker-compose.erigon-standalone.yml logs -f xdc-agent-erigon"
echo ""
