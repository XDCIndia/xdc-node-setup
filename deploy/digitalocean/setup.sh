#!/bin/bash
# DigitalOcean Marketplace Setup Script
# Runs during image creation

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== XDC Node - DigitalOcean Marketplace Setup ==="

# Update system
apt-get update
apt-get upgrade -y

# Install dependencies
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    jq \
    git \
    htop \
    iotop \
    unzip \
    fail2ban \
    ufw

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
usermod -aG docker root
systemctl enable docker

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Create XDC directories
mkdir -p /opt/xdc-node/{configs,scripts,monitoring,reports}
mkdir -p /var/lib/xdc-node/{xdcchain,logs}
mkdir -p /var/lib/node_exporter/textfile_collector

# Set up firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 30303/tcp
ufw allow 30303/udp
ufw allow 8545/tcp
ufw allow 8546/tcp
ufw allow 7070/tcp
ufw --force enable

# Configure fail2ban
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF

systemctl enable fail2ban

# Create first boot service
cat > /etc/systemd/system/xdc-first-boot.service << 'EOF'
[Unit]
Description=XDC Node First Boot Configuration
After=docker.service
Wants=docker.service

[Service]
Type=oneshot
ExecStart=/opt/xdc-node/scripts/first-boot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable xdc-first-boot.service

# Clean up
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
rm -rf /var/tmp/*
rm -f /root/.bash_history

echo "=== Setup Complete ==="
