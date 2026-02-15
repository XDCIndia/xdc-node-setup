#!/bin/bash
# DigitalOcean 1-Click - User Data Script
# Runs on first boot to configure the XDC node

set -e

exec > > (tee /var/log/xdc-node/userdata.log)
exec 2>&1

echo "=== XDC Node Setup - DigitalOcean 1-Click ==="
echo "Timestamp: $(date)"
echo "Droplet ID: $(curl -s http://169.254.169.254/metadata/v1/id)"
echo "Region: $(curl -s http://169.254.169.254/metadata/v1/region)"

# Get droplet metadata
DROPLET_ID=$(curl -s http://169.254.169.254/metadata/v1/id)
DROPLET_NAME=$(curl -s http://169.254.169.254/metadata/v1/hostname)
PUBLIC_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)
MEMORY_MB=$(free -m | awk '/^Mem:/{print $2}')
MEMORY_GB=$((MEMORY_MB / 1024))

echo "Detected: $MEMORY_GB GB RAM"

# Determine optimal client based on available resources
if [ "$MEMORY_GB" -lt 8 ]; then
  XDC_CLIENT="stable"
  echo "Using XDC Stable (recommended for <8GB RAM)"
else
  XDC_CLIENT="stable"
  echo "Using XDC Stable"
fi

# Default network (can be overridden via user-data)
XDC_NETWORK="${XDC_NETWORK:-mainnet}"
NODE_NAME="${XDC_NODE_NAME:-xdc-node-$DROPLET_ID}"

echo "Configuration:"
echo "  Network: $XDC_NETWORK"
echo "  Client: $XDC_CLIENT"
echo "  Node Name: $NODE_NAME"

# Wait for cloud-init to complete
echo "Waiting for cloud-init..."
cloud-init status --wait

# Ensure Docker is running
echo "Starting Docker..."
systemctl start docker
systemctl enable docker

# Create installation directory
mkdir -p /opt/xdc-node
cd /opt/xdc-node

# Download XDC Node Setup
echo "Downloading XDC Node Setup..."
git clone https://github.com/AnilChinchawale/XDC-Node-Setup.git . 2>/dev/null || true

# Create environment configuration
cat > /opt/xdc-node/.env <<EOF
# XDC Node Configuration
NETWORK=$XDC_NETWORK
CLIENT=$XDC_CLIENT
INSTANCE_NAME=$NODE_NAME
RPC_ENABLED=true
WS_ENABLED=true
RPC_PORT=8545
WS_PORT=8546
P2P_PORT=30303
INSTANCE_ID=$DROPLET_ID
EOF

# Set permissions
chmod +x /opt/xdc-node/install.sh
chmod +x /opt/xdc-node/setup.sh

# Run the installer
echo "Running XDC Node Setup..."
bash /opt/xdc-node/install.sh

# Create systemd service for XDC node
cat > /etc/systemd/system/xdc-node.service <<'EOF'
[Unit]
Description=XDC Network Node
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/xdc-node
ExecStart=/usr/bin/docker compose -f docker/docker-compose.yml up -d
ExecStop=/usr/bin/docker compose -f docker/docker-compose.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl daemon-reload
systemctl enable xdc-node.service
systemctl start xdc-node.service

# Create xdc CLI wrapper
cat > /usr/local/bin/xdc <<'EOF'
#!/bin/bash
# XDC CLI wrapper for DigitalOcean 1-Click

XDC_HOME=/opt/xdc-node

case "$1" in
  status)
    echo "=== XDC Node Status ==="
    docker ps --filter "name=xdc" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    echo "Sync Status:"
    curl -s -X POST http://localhost:8545 \
      -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' 2>/dev/null | jq . 2>/dev/null || echo "Node starting up..."
    ;;
  logs)
    docker logs xdc-node "${@:2}"
    ;;
  start)
    systemctl start xdc-node.service
    echo "XDC node started"
    ;;
  stop)
    systemctl stop xdc-node.service
    echo "XDC node stopped"
    ;;
  restart)
    systemctl restart xdc-node.service
    echo "XDC node restarted"
    ;;
  update)
    cd /opt/xdc-node && git pull
    docker compose -f docker/docker-compose.yml pull
    systemctl restart xdc-node.service
    echo "XDC node updated"
    ;;
  *)
    echo "XDC Node CLI"
    echo "Usage: xdc {status|logs|start|stop|restart|update}"
    ;;
esac
EOF
chmod +x /usr/local/bin/xdc

# Setup log rotation
cat > /etc/logrotate.d/xdc-node <<EOF
/var/log/xdc-node/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOF

# Create a README for the user
cat > /root/README-XDC.txt <<EOF
====================================
XDC Network Node - Quick Start Guide
====================================

Your XDC node has been automatically configured and started!

Droplet Information:
  Name: $DROPLET_NAME
  IP: $PUBLIC_IP
  Droplet ID: $DROPLET_ID

Access Points:
  RPC:       http://$PUBLIC_IP:8545
  WebSocket: ws://$PUBLIC_IP:8546
  Dashboard: http://$PUBLIC_IP:7070

Useful Commands:
  xdc status    - Check node status
  xdc logs      - View node logs
  xdc start     - Start the node
  xdc stop      - Stop the node
  xdc restart   - Restart the node
  xdc update    - Update to latest version

Configuration:
  Directory: /opt/xdc-node
  Logs:      /var/log/xdc-node/

Network: $XDC_NETWORK
Client:  $XDC_CLIENT

For more information:
  GitHub:    https://github.com/AnilChinchawale/XDC-Node-Setup
  XDC Docs:  https://docs.xdc.community/

To remove this message, delete this file.
EOF

# Also create for ubuntu user (if exists)
if [ -d /home/ubuntu ]; then
    cp /root/README-XDC.txt /home/ubuntu/
    chown ubuntu:ubuntu /home/ubuntu/README-XDC.txt
fi

# Signal completion
echo "=== XDC Node Setup - Complete ==="
echo "Timestamp: $(date)"
echo ""
echo "Your XDC node is now running!"
echo "RPC Endpoint: http://$PUBLIC_IP:8545"
echo "Dashboard: http://$PUBLIC_IP:7070"
