# XDC Node Setup - Complete Setup Guide
> SkyOne - Production-ready XDC Network node deployment

## Table of Contents

1. [Quick Start](#quick-start)
2. [System Requirements](#system-requirements)
3. [Pre-Installation](#pre-installation)
4. [Installation Methods](#installation-methods)
5. [Post-Installation](#post-installation)
6. [Verification](#verification)
7. [Troubleshooting](#troubleshooting)

---

## Quick Start

### One-Liner Install (Recommended for Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/XDC-Node-Setup/main/install.sh | sudo bash
```

Your node will be running within 5 minutes. Access the dashboard at `http://localhost:7070`

---

## System Requirements

### Minimum Requirements

| Component | Specification |
|-----------|--------------|
| **OS** | Ubuntu 20.04+ LTS (x86_64) |
| **CPU** | 2 cores |
| **RAM** | 4 GB |
| **Storage** | 100 GB HDD |
| **Network** | 10 Mbps |
| **Docker** | 20.10+ |

### Recommended Requirements

| Component | Specification |
|-----------|--------------|
| **OS** | Ubuntu 22.04 LTS (x86_64) |
| **CPU** | 4+ cores |
| **RAM** | 16 GB |
| **Storage** | 500 GB+ NVMe SSD |
| **Network** | 100 Mbps+ |
| **Docker** | Latest stable |

### Client-Specific Requirements

| Client | RAM | Storage | Notes |
|--------|-----|---------|-------|
| XDC Geth | 4GB+ | ~500GB | Standard client |
| XDC Geth PR5 | 4GB+ | ~500GB | Latest features |
| Erigon-XDC | 8GB+ | ~400GB | Dual-sentry architecture |
| Nethermind-XDC | 12GB+ | ~350GB | .NET-based |
| Reth-XDC | 16GB+ | ~300GB | Rust-based, alpha status |

---

## Pre-Installation

### 1. Update System

```bash
sudo apt update && sudo apt upgrade -y
```

### 2. Install Docker

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Verify installation
docker --version
docker compose version
```

### 3. Configure Firewall

```bash
# Install UFW
sudo apt install utf -y

# Default deny incoming
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH
sudo ufw allow 22/tcp

# Allow XDC P2P
sudo ufw allow 30303/tcp
sudo ufw allow 30303/udp

# Allow dashboard (local only recommended)
# sudo ufw allow from 127.0.0.1 to any port 7070

# Enable firewall
sudo ufw enable
```

### 4. Configure Time Sync

```bash
sudo apt install chrony -y
sudo systemctl enable chrony
sudo systemctl start chrony
```

---

## Installation Methods

### Method 1: Automated Install (Recommended)

```bash
# Download and run installer
curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/XDC-Node-Setup/main/setup.sh -o setup.sh
chmod +x setup.sh
sudo ./setup.sh
```

### Method 2: Manual Installation

```bash
# Clone repository
git clone https://github.com/AnilChinchawale/XDC-Node-Setup.git
cd XDC-Node-Setup

# Run setup
sudo ./setup.sh
```

### Method 3: Advanced Installation

```bash
# Run with advanced options
sudo ./setup.sh --advanced
```

This will prompt for:
- Client selection (Geth, Erigon, Nethermind, Reth)
- Network selection (mainnet, testnet, devnet)
- Node type (full, archive, masternode)
- SkyNet integration
- Monitoring options

### Method 4: Docker Compose Only

```bash
cd docker

# Copy environment file
cp mainnet/.env.example mainnet/.env

# Edit configuration
nano mainnet/.env

# Start services
docker compose up -d
```

---

## Client Selection

During installation, you'll be prompted to select a client:

```
Client Selection
=================
1) XDC Stable (v2.6.8) - Official Docker image (recommended)
2) XDC Geth PR5 - Latest geth with XDPoS (builds from source)
3) Erigon-XDC - Multi-client diversity, experimental
4) Nethermind-XDC - .NET-based client with eth/100 protocol (beta)
5) Reth-XDC - Rust-based execution client, fastest sync (alpha)
```

### Client Comparison

| Feature | Geth | Erigon | Nethermind | Reth |
|---------|------|--------|------------|------|
| **Stability** | Production | Experimental | Beta | Alpha |
| **Sync Speed** | Standard | Fast | Very Fast | Fastest |
| **Disk Usage** | ~500GB | ~400GB | ~350GB | ~300GB |
| **RPC Port** | 8545 | 8547 | 8558 | 7073 |
| **P2P Port** | 30303 | 30304 | 30306 | 40303 |

---

## Post-Installation

### 1. Check Node Status

```bash
# Using CLI
xdc status

# Or using Docker
docker logs xdc-node --tail 100 -f
```

### 2. Access Dashboard

Open your browser and navigate to:

```
http://localhost:7070
```

### 3. Configure SkyNet (Optional)

To enable fleet monitoring:

```bash
# Edit SkyNet configuration
nano mainnet/.xdc-node/skynet.conf

# Set your API key
SKYNET_API_KEY=your-api-key-here
SKYNET_NODE_NAME=my-xdc-node

# Restart agent
xdc restart
```

### 4. Download Snapshot (Optional)

For faster initial sync:

```bash
# Download snapshot
xdc snapshot download --network mainnet

# Apply snapshot
xdc snapshot apply
```

---

## Verification

### Check Sync Status

```bash
# Using CLI
xdc sync

# Or using RPC
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
```

### Check Peer Count

```bash
# Using CLI
xdc peers

# Or using RPC
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
```

### Check Block Height

```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

---

## Troubleshooting

### Node Won't Start

```bash
# Check Docker is running
sudo systemctl status docker

# Check port conflicts
sudo netstat -tlnp | grep -E '8545|30303|7070'

# View logs
xdc logs --follow
```

### Node Won't Sync

```bash
# Check peer count
xdc peers

# Restart with fresh peer discovery
xdc stop
rm -rf mainnet/.xdc-node/geth/nodes
xdc start

# Download snapshot
xdc snapshot download
```

### High Resource Usage

```bash
# Reduce memory cache
xdc config set cache 2048
xdc restart

# Check disk space
df -h

# Enable pruning
xdc config set prune_mode full
xdc restart
```

### Dashboard Not Accessible

```bash
# Check if port is open
sudo ufw allow 7070

# Check if dashboard is running
docker ps | grep dashboard

# Restart dashboard
xdc monitor restart
```

---

## Next Steps

- [Configuration Guide](CONFIGURATION.md) - Customize your node settings
- [Troubleshooting Guide](TROUBLESHOOTING.md) - Common issues and solutions
- [API Reference](API.md) - Programmatic node interaction
- [Security Guide](SECURITY.md) - Harden your node installation

---

## Support

- [GitHub Issues](https://github.com/AnilChinchawale/XDC-Node-Setup/issues)
- [XDC Community Discord](https://discord.gg/xdc)
- [XDC Network Docs](https://docs.xdc.community/)
