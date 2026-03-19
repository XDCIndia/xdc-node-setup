# XDC Node Setup

<div align="center">

![XDC Node Setup](https://img.shields.io/badge/XDC-Node%20Setup-blue?style=for-the-badge&logo=docker)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)](LICENSE)
[![Version](https://img.shields.io/badge/Version-2.0.0-blue?style=for-the-badge)](VERSION)
[![XDC Network](https://img.shields.io/badge/XDC-Network-brightgreen?style=for-the-badge)](https://xdc.network/)

**Production-ready XDC Network node deployment in minutes**

[Quick Start](#quick-start) • [Features](#features) • [Setup Guide](#setup-guide) • [CLI Reference](#cli-reference) • [Documentation](#documentation) • [Troubleshooting](#troubleshooting)

</div>

---

## 📋 Table of Contents

- [Quick Start](#quick-start)
- [Features](#features)
- [Requirements](#requirements)
- [Setup Guide](#setup-guide)
  - [Mainnet Setup](#mainnet-setup)
  - [Apothem Testnet Setup](#apothem-testnet-setup)
  - [Multi-Client Setup](#multi-client-setup)
- [Network Configuration](#network-configuration)
- [CLI Reference](#cli-reference)
- [SkyOne Dashboard](#skyone-dashboard)
- [SkyNet Integration](#skynet-integration)
- [Multi-Client Support](#multi-client-support)
- [Cloud Deployment](#cloud-deployment)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)

---

## 🚀 Quick Start

### One-Liner Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/install.sh | sudo bash
```

### Manual Installation

```bash
# 1. Clone the repository
git clone https://github.com/AnilChinchawale/xdc-node-setup.git
cd xdc-node-setup

# 2. Run the installer
sudo ./install.sh

# 3. Start your node
xdc start

# 4. Check status
xdc status
```

Your node will be running and syncing within 5 minutes.

---

## ✨ Features

| Feature | Description | Status |
|---------|-------------|--------|
| 🚀 **One-Command Deployment** | Get a node running in under 5 minutes | ✅ |
| 🔒 **Security Hardened** | SSH hardening, firewall, fail2ban, audit logging | ✅ |
| 📊 **SkyOne Dashboard** | Built-in monitoring dashboard on port 7070 | ✅ |
| 🔧 **Multi-Client Support** | Geth stable, Geth PR5, Erigon, Nethermind, Reth | ✅ |
| 🌐 **Multi-Network** | Mainnet, Testnet (Apothem), Devnet | ✅ |
| 📡 **SkyNet Integration** | Auto-registers with XDC SkyNet for fleet monitoring | ✅ |
| 💾 **Fast Sync** | Snapshot download with resume support | ✅ |
| 🔄 **Auto-Updates** | Automatic version checks and updates | ✅ |
| 🛠️ **Powerful CLI** | Single `xdc` command for all operations | ✅ |
| 📱 **Mobile Ready** | Responsive dashboard for mobile monitoring | ✅ |

---

## 💻 Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **OS** | Linux x86_64 (Ubuntu 20.04+) | Ubuntu 22.04 LTS |
| **Docker** | 20.10+ | Latest stable |
| **RAM** | 4GB | 16GB+ |
| **Disk** | 100GB HDD | 500GB+ NVMe SSD |
| **Network** | 10 Mbps | 100 Mbps+ |
| **CPU** | 2 cores | 4+ cores |

### Supported Platforms

- ✅ Linux x86_64 (primary)
- ✅ Linux ARM64
- ✅ macOS (with Rosetta emulation)
- ⚠️ Windows (via WSL2)

---

## 📖 Setup Guide

### Mainnet Setup

```bash
# Quick start with defaults (XDC Stable client)
xdc start

# With specific client
xdc start --client stable

# With custom ports
xdc start --rpc-port 8545 --p2p-port 30303
```

### Apothem Testnet Setup

```bash
# Navigate to Apothem directory
cd docker/apothem

# Run setup script (validates genesis, bootnodes, ports)
./setup.sh

# Or manually with docker-compose
docker-compose -f docker-compose.apothem-geth.yml up -d
```

**Apothem Testnet Details:**
- **Network ID:** 51
- **RPC:** http://localhost:8545
- **WebSocket:** ws://localhost:8546
- **Chain ID:** 51
- **Genesis:** Matches official XDPoSChain testnet

### Multi-Client Setup

Run all 4 XDC clients simultaneously using XDCSync infrastructure:

```bash
# 1. Initialize genesis for all clients
./scripts/init-genesis.sh --network mainnet

# 2. Start all clients with docker-compose
docker-compose -f docker-compose.multi-client.yml up -d

# 3. Check status of all clients
./scripts/skyone-register.sh status

# 4. View logs
docker-compose -f docker-compose.multi-client.yml logs -f
```

**Multi-Client Port Allocation:**

| Client | RPC HTTP | RPC WS | P2P | Metrics |
|--------|----------|--------|-----|---------|
| GP5 (Geth PR5) | 7070 | 7071 | 30303 | 6070 |
| Erigon | 7072 | 7073 | 30304 | 6071 |
| Nethermind | 7074 | 7075 | 30306 | 6072 |
| Reth | 8588 | 8589 | 40303 | 6073 |

**SkyOne Auto-Registration:**
All clients automatically register with SkyNet when `SKYNET_ENABLED=true`.

```bash
# Enable SkyNet monitoring
export SKYNET_ENABLED=true
export SKYNET_API_KEY=your-api-key  # Optional
docker-compose -f docker-compose.multi-client.yml up -d
```

**Genesis Guard:**
The start scripts include Genesis Guard to validate chainId on startup:
- Prevents network mismatch (mainnet vs apothem)
- Auto-wipes chaindata on network switch (when `GENESIS_GUARD_AUTO_WIPE=true`)

See [docs/TROUBLESHOOTING-MULTI-CLIENT.md](docs/TROUBLESHOOTING-MULTI-CLIENT.md) for common issues.

### Single Client Setup

```bash
# Start with different clients
xdc start --client stable      # XDC Stable (v2.6.8)
xdc start --client geth-pr5    # XDC Geth PR5 (latest)
xdc start --client erigon      # Erigon-XDC (experimental)
xdc start --client nethermind  # Nethermind-XDC (beta)
xdc start --client reth        # Reth-XDC (alpha)

# Check which client is running
xdc client
```

---

## 🌐 Network Configuration

### Port Requirements

| Port | Protocol | Service | Required |
|------|----------|---------|----------|
| 8545 | TCP | HTTP RPC | Optional* |
| 8546 | TCP | WebSocket | Optional* |
| 30303 | TCP/UDP | P2P | **Yes** |
| 7070 | TCP | SkyOne Dashboard | Optional |

\* Required for external API access. Bind to localhost only for security.

### RPC Configuration

By default, RPC is bound to `0.0.0.0` (all interfaces). For production:

```bash
# Bind to localhost only (secure)
export RPC_BIND=127.0.0.1
xdc start

# Or use nginx reverse proxy with SSL
# See docs/SSL_SETUP.md
```

---

## 🖥️ CLI Reference

### Core Commands

```bash
# Start node
xdc start [--client <name>] [--network <mainnet|apothem>]

# Stop node
xdc stop

# Restart node
xdc restart

# Check status
xdc status

# View logs
xdc logs [--follow] [--client <name>]

# Update to latest version
xdc update

# Check version
xdc version
```

### Advanced Commands

```bash
# Backup node data
xdc backup

# Restore from backup
xdc restore <backup-file>

# Reset node (dangerous - wipes data)
xdc reset

# Enter node shell
xdc shell

# Run diagnostic checks
xdc doctor
```

---

## 📊 SkyOne Dashboard

Access the built-in monitoring dashboard:

```
http://localhost:7070
```

Features:
- Real-time sync status
- Peer count and network health
- Block height and chain data
- System resource usage
- Log viewer

---

## 🔗 SkyNet Integration

Automatically register your node with XDC SkyNet for fleet monitoring:

```bash
# Enable SkyNet (enabled by default)
export SKYNET_ENABLED=true
export SKYNET_URL=https://net.xdc.network
xdc start
```

---

## 🔧 Multi-Client Support

| Client | Version | Status | RPC Port | P2P Port |
|--------|---------|--------|----------|----------|
| **XDC Stable** | v2.6.8 | Production | 8545 | 30303 |
| **XDC Geth PR5** | Latest | Testing | 8545 | 30303 |
| **Erigon-XDC** | Latest | Experimental | 8547 | 30304 |
| **Nethermind-XDC** | Latest | Beta | 8558 | 30306 |
| **Reth-XDC** | Latest | Alpha | 7073 | 40303 |

See [docs/CLIENTS.md](docs/CLIENTS.md) for detailed client comparison.

---

## ☁️ Cloud Deployment

Ready-to-use templates for:

- **AWS** - Packer AMI builder
- **DigitalOcean** - 1-Click Marketplace
- **Akash** - Decentralized cloud
- **Docker Hub** - Official images

See [deploy/](deploy/) directory for templates.

---

## 🔧 Troubleshooting

### Node Not Syncing

```bash
# Check logs
xdc logs --follow

# Check peer count
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'

# Restart with verbose logging
xdc restart --verbose
```

### Port Conflicts

```bash
# Check port usage
sudo lsof -i :8545
sudo lsof -i :30303

# Kill conflicting process or change ports
xdc stop
export RPC_PORT=8546
export P2P_PORT=30304
xdc start
```

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for more.

---

## 🔒 Security

### Default Security Features

- ✅ SSH key authentication only
- ✅ UFW firewall with restrictive rules
- ✅ fail2ban intrusion prevention
- ✅ Docker security hardening
- ✅ Automatic security updates

### Production Hardening

```bash
# Run security hardening script
sudo ./scripts/security-harden.sh

# Enable CIS benchmarks
sudo ./scripts/cis-benchmark.sh
```

See [docs/SECURITY.md](docs/SECURITY.md) for detailed security guide.

---

## 🤝 Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file.

---

<div align="center">

**Built for the XDC Network Community** ❤️

[Website](https://xdc.network) • [Documentation](https://docs.xdc.network) • [Discord](https://discord.gg/xdc)

</div>
