#!/bin/bash
# DigitalOcean First Boot Script
# Runs on first droplet boot

set -euo pipefail

LOG_FILE="/var/log/xdc-first-boot.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== XDC Node First Boot - $(date) ==="

# Check if already configured
if [ -f /opt/xdc-node/.configured ]; then
    echo "Already configured, skipping..."
    exit 0
fi

# Get metadata
DROPLET_ID=$(curl -s http://169.254.169.254/metadata/v1/id)
DROPLET_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)
REGION=$(curl -s http://169.254.169.254/metadata/v1/region)

echo "Droplet ID: $DROPLET_ID"
echo "IP: $DROPLET_IP"
echo "Region: $REGION"

# Download and install XDC Node Setup
cd /opt/xdc-node

# Clone or download latest setup scripts
curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/install.sh | bash

# Run setup
xdc setup --network mainnet --type full

# Create MOTD
cat > /etc/update-motd.d/99-xdc-node << 'EOF'
#!/bin/bash
echo ""
echo "============================================"
echo "    XDC Network Node - DigitalOcean"
echo "============================================"
echo ""
if command -v xdc &> /dev/null; then
    xdc status --short 2>/dev/null || echo "Node is starting..."
else
    echo "Node setup in progress..."
fi
echo ""
echo "Dashboard: http://$(hostname -I | awk '{print $1}'):7070"
echo "Help: xdc --help"
echo "============================================"
EOF

chmod +x /etc/update-motd.d/99-xdc-node

# Mark as configured
touch /opt/xdc-node/.configured

# Start services
xdc start || true

echo "=== First Boot Complete - $(date) ==="
echo ""
echo "Your XDC Node is now running!"
echo "Dashboard: http://${DROPLET_IP}:7070"
echo ""
echo "Check status with: xdc status"
