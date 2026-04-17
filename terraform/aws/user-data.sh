#!/bin/bash
set -euo pipefail

# XDC Node User Data Script
# This script runs on first boot to set up the XDC node

exec 1> >(logger -s -t "$(basename "$0")" 2>&1)
exec 2>&1

echo "Starting XDC node setup..."

# Update system
apt-get update
apt-get upgrade -y

# Install dependencies
apt-get install -y curl wget git build-essential jq

# Clone and run setup script
cd /root
git clone https://github.com/XDCIndia/xdc-node-setup.git XDC-Node-Setup
cd XDC-Node-Setup

# Run setup with environment variables
export NODE_TYPE="${node_type}"
export NETWORK="${network}"
export CLIENT="${client}"

./setup.sh --non-interactive

# Ensure XNS CLI is installed
if [ -f "./cli/install.sh" ]; then
    bash ./cli/install.sh
fi

echo "XDC node setup complete!"
