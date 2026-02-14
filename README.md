# XDC Node Setup

<div align="center">

![XDC Node Setup](https://img.shields.io/badge/XDC-Node%20Setup-blue?style=for-the-badge&logo=docker)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)](LICENSE)
[![Version](https://img.shields.io/badge/Version-1.0.0-blue?style=for-the-badge)](VERSION)
[![XDC Network](https://img.shields.io/badge/XDC-Network-brightgreen?style=for-the-badge)](https://xdc.network/)

**Production-ready XDC Network node deployment in minutes**

[Quick Start](#quick-start) • [CLI Reference](#cli-reference) • [Documentation](#documentation) • [Changelog](CHANGELOG.md)

</div>

---

## 🚀 Quick Start

### One-Liner Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/XDC-Node-Setup/main/install.sh | sudo bash
```

### Manual Installation

```bash
# 1. Clone the repository
git clone https://github.com/AnilChinchawale/XDC-Node-Setup.git
cd XDC-Node-Setup

# 2. Run the installer
sudo ./install.sh

# 3. Check node status
xdc status
```

Your node will be running and syncing within 5 minutes. Access the SkyOne dashboard at `http://localhost:7070`

---

## 📋 Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Multi-Client Support](#multi-client-support)
- [Cloud Deployment](#cloud-deployment)
- [CLI Reference](#cli-reference)
- [SkyOne Dashboard](#skyone-dashboard)
- [SkyNet Integration](#skynet-integration)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Architecture](#architecture)
- [Contributing](#contributing)
- [License](#license)

---

## ✨ Features

| Feature | Description | Status |
|---------|-------------|--------|
| 🚀 **One-Command Deployment** | Get a node running in under 5 minutes | ✅ |
| 🔒 **Security Hardened** | SSH hardening, firewall, fail2ban, audit logging | ✅ |
| 📊 **SkyOne Dashboard** | Built-in monitoring dashboard on port 7070 | ✅ |
| 🔧 **Multi-Client Support** | Geth stable, Geth PR5, Erigon | ✅ |
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

## 🔧 Multi-Client Support

XDC Node Setup supports **three different clients** for improved network diversity and resilience:

### Client Comparison

| Feature | XDC Stable | XDC Geth PR5 | Erigon-XDC |
|---------|------------|--------------|------------|
| **Version** | v2.6.8 | Latest | Latest |
| **Type** | Official Docker | Source build | Source build |
| **Build Time** | Instant | ~10-15 min | ~10-15 min |
| **RPC Port** | 8545 | 8545 | **8547** |
| **P2P Port** | 30303 | 30303 | 30304 + 30311 |
| **Sync Speed** | Standard | Standard | Fast |
| **Disk Usage** | ~500GB | ~500GB | ~400GB |
| **Memory** | 4GB+ | 4GB+ | 8GB+ |
| **Status** | Production | Testing | Experimental |

### Selecting a Client

During setup, choose your preferred client:

```bash
Client Selection
=================
1) XDC Stable (v2.6.8) - Official Docker image (recommended)
2) XDC Geth PR5 - Latest geth with XDPoS (builds from source)
3) Erigon-XDC - Multi-client diversity, experimental

Select client [1-3] (default: 1):
```

### Switching Clients

```bash
# Start with specific client
xdc start --client stable
xdc start --client geth-pr5
xdc start --client erigon

# Check current client
xdc client
```

### Why Multi-Client Matters

- ✅ **Network Resilience**: Prevents single-client bugs from affecting the entire network
- ✅ **Performance Options**: Choose the best client for your use case
- ✅ **Future-Proof**: Easy migration as clients evolve
- ✅ **Diversity**: Contributes to XDC network health

---

## ☁️ Cloud Deployment

XDC Node Setup provides ready-to-use deployment templates for popular cloud platforms:

### AWS AMI (Packer)

Build a custom AMI with XDC node pre-installed:

```bash
cd deploy/aws
packer build packer.json
```

**Features:**
- Ubuntu 22.04 LTS base
- Docker and Docker Compose pre-installed
- XDC node auto-configuration
- CloudWatch agent for monitoring

**Deploy:**
```bash
# Launch instance from your new AMI
aws ec2 run-instances \
  --image-id ami-xxxxxxxx \
  --instance-type t3.xlarge \
  --key-name your-key \
  --security-group-ids sg-xxxxxxxxx
```

### DigitalOcean 1-Click

Deploy with DigitalOcean Marketplace:

```bash
# Build the snapshot
cd deploy/digitalocean
packer build marketplace.yaml

# Or deploy via DO API
curl -X POST https://api.digitalocean.com/v2/droplets \
  -H "Authorization: Bearer $DO_TOKEN" \
  -d '{"name":"xdc-node","region":"nyc3","size":"s-4vcpu-8gb","image":"ubuntu-22-04-x64"}'
```

**Features:**
- One-click deployment from DO Marketplace
- SkyOne dashboard pre-configured
- Automatic firewall setup
- First-boot configuration script

### Akash Network (Decentralized Cloud)

Deploy on the decentralized Akash cloud:

```bash
# Install Akash CLI first, then:
akash tx deployment create deploy/akash/deploy.yaml --from your-key
```

**Features:**
- Decentralized hosting
- Pay with AKT tokens
- Global provider network
- Competitive pricing

### Docker Hub

Pull the official image:

```bash
docker pull xinfinorg/xdposchain:v2.6.8
```

Or build your own:

```bash
cd deploy/docker
docker build -t xdc-node:latest .
```

See [deploy/docker/README.md](deploy/docker/README.md) for automated build setup instructions.

### Cloud Deployment Comparison

| Platform | Deployment Time | Cost/Month | Best For |
|----------|-----------------|------------|----------|
| **AWS** | ~5 min | $140 | Enterprise, scaling |
| **DigitalOcean** | ~3 min | $48 | Simple setup, dev/test |
| **Akash** | ~10 min | $20-40 | Decentralized, cost-saving |
| **Self-hosted** | ~15 min | Hardware | Full control |

### Quick Links

- [AWS Packer Template](deploy/aws/packer.json)
- [DigitalOcean Marketplace](deploy/digitalocean/marketplace.yaml)
- [Akash SDL Manifest](deploy/akash/deploy.yaml)
- [Docker Hub Setup](deploy/docker/README.md)

---

## 🖥️ CLI Reference

The `xdc` command provides full control over your node:

### Core Commands

| Command | Description | Example |
|---------|-------------|---------|
| `xdc status` | Display node status and sync progress | `xdc status --watch` |
| `xdc start` | Start the XDC node | `xdc start --client erigon` |
| `xdc stop` | Stop the XDC node | `xdc stop` |
| `xdc restart` | Restart the node | `xdc restart` |
| `xdc logs` | View node logs | `xdc logs --follow` |
| `xdc info` | Show detailed node info | `xdc info` |

### Monitoring Commands

| Command | Description | Example |
|---------|-------------|---------|
| `xdc monitor` | Open SkyOne dashboard | `xdc monitor` |
| `xdc health` | Run health check | `xdc health --full` |
| `xdc peers` | List connected peers | `xdc peers` |
| `xdc sync` | Check sync status | `xdc sync` |

### Maintenance Commands

| Command | Description | Example |
|---------|-------------|---------|
| `xdc backup` | Create encrypted backup | `xdc backup create` |
| `xdc snapshot` | Download/apply snapshot | `xdc snapshot download` |
| `xdc update` | Check for updates | `xdc update` |
| `xdc security` | Run security audit | `xdc security --apply` |
| `xdc attach` | Attach to XDC console | `xdc attach` |

### Configuration Commands

| Command | Description | Example |
|---------|-------------|---------|
| `xdc config list` | View all config | `xdc config list` |
| `xdc config get` | Get config value | `xdc config get rpc_enabled` |
| `xdc config set` | Set config value | `xdc config set max_peers 100` |

### Help

```bash
xdc --help           # Show all commands
xdc <command> --help # Show command-specific help
```

---

## 📊 SkyOne Dashboard

SkyOne is the built-in single-node monitoring dashboard that comes with every XDC Node Setup installation.

### Features

- **Real-time Metrics**: Block height, sync status, peer count
- **System Monitoring**: CPU, memory, disk usage
- **Network Statistics**: Latency, throughput, connection health
- **Alert Timeline**: Historical alerts and notifications
- **Security Score**: System hardening recommendations

### Access

```
Local:      http://localhost:7070
Network:    http://<your-server-ip>:7070
```

### Dashboard Pages

| Page | Description |
|------|-------------|
| **Overview** | High-level node health and key metrics |
| **Peers** | Connected peers with geographic distribution |
| **Blocks** | Recent blocks and chain statistics |
| **Alerts** | System alerts and notifications |
| **Settings** | Dashboard configuration |

---

## 📡 SkyNet Integration

XDC Node Setup automatically integrates with **XDC SkyNet** for fleet-wide monitoring.

### What is SkyNet?

SkyNet is the fleet monitoring platform for XDC Network operators. It provides:
- Centralized dashboard for all your nodes
- Unified alerting across your fleet
- Historical metrics and analytics
- Network-wide statistics

### How It Works

1. During setup, the installer creates a unique node identifier
2. Node metrics are automatically reported to SkyNet every 15 minutes
3. Access your fleet at: [https://net.xdc.network](https://net.xdc.network)

### Configuration

```bash
# View SkyNet config
xdc config get skynet_enabled

# Disable SkyNet (if needed)
xdc config set skynet_enabled false
xdc restart
```

---

## ⚙️ Configuration

Configuration files are stored in `{network}/.xdc-node/config.toml`

### Directory Structure

```
XDC-Node-Setup/
├── mainnet/
│   ├── .xdc-node/
│   │   └── config.toml
│   └── xdcchain/
├── testnet/
│   └── ...
└── devnet/
    └── ...
```

### Key Configuration Options

```toml
[node]
NetworkId = 50           # 50 = mainnet, 51 = testnet
DataDir = "/xdcchain"
HTTPPort = 8545
WSPort = 8546
Port = 30303
MaxPeers = 50

[eth]
SyncMode = "full"        # full, fast, or archive
GCMode = "full"
Cache = 4096            # Memory cache in MB

[metrics]
Enabled = true
Port = 6060
```

### Editing Configuration

```bash
# View current config
xdc config list

# Edit config file
nano mainnet/.xdc-node/config.toml

# Apply changes
xdc restart
```

---

## 🔍 Troubleshooting

### Node Won't Start

```bash
# Check Docker is running
sudo systemctl status docker

# Check port conflicts
sudo netstat -tlnp | grep -E '8545|30303|7070'

# View detailed logs
xdc logs --follow

# Check system resources
xdc info
```

### Node Won't Sync

```bash
# Check peer count
xdc peers

# Check sync status
xdc sync

# If no peers, restart with fresh peer discovery
xdc stop
rm -rf mainnet/.xdc-node/geth/nodes
xdc start

# Download snapshot for fast sync
xdc snapshot download --network mainnet
xdc snapshot apply
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
# Check if port 7070 is open
sudo ufw allow 7070

# Check if dashboard is running
docker ps | grep dashboard

# Restart dashboard
xdc monitor restart
```

### RPC Connection Refused

```bash
# Check RPC is enabled
xdc config get rpc_enabled

# Check RPC is listening
netstat -tlnp | grep 8545

# Allow RPC port (if needed)
sudo ufw allow 8545
```

### Getting Help

- [Full Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- [GitHub Issues](https://github.com/AnilChinchawale/XDC-Node-Setup/issues)
- [XDC Community Discord](https://discord.gg/xdc)
- [XDC Network Docs](https://docs.xdc.community/)

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         XDC Node Setup Architecture                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────┐                 │
│  │   CLI Tool  │    │  SkyOne UI   │    │  SkyNet API │                 │
│  │   (xdc)     │◄──►│  (Port 7070) │◄──►│  (Optional) │                 │
│  └──────┬──────┘    └──────┬───────┘    └─────────────┘                 │
│         │                  │                                             │
│         ▼                  ▼                                             │
│  ┌──────────────────────────────────────────────────┐                   │
│  │              Docker Compose Stack                 │                   │
│  ├──────────────────────────────────────────────────┤                   │
│  │  ┌───────────┐  ┌───────────┐  ┌──────────────┐  │                   │
│  │  │ XDC Node  │  │  SkyOne   │  │ Prometheus   │  │                   │
│  │  │  (Geth/   │  │ Dashboard │  │  (Metrics)   │  │                   │
│  │  │  Erigon)  │  │           │  │              │  │                   │
│  │  └─────┬─────┘  └───────────┘  └──────────────┘  │                   │
│  │        │                                         │                   │
│  │        ▼                                         │                   │
│  │  ┌───────────┐  ┌───────────┐                   │                   │
│  │  │  XDC Chain │  │   Data    │                   │                   │
│  │  │   Data    │  │  Volume   │                   │                   │
│  │  └───────────┘  └───────────┘                   │                   │
│  └──────────────────────────────────────────────────┘                   │
│                          │                                              │
│                          ▼                                              │
│  ┌──────────────────────────────────────────────────┐                   │
│  │              XDC P2P Network                      │                   │
│  │         (Mainnet / Testnet / Devnet)              │                   │
│  └──────────────────────────────────────────────────┘                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Flow

1. **CLI (`xdc`)**: User interface for node management
2. **SkyOne Dashboard**: Web UI for monitoring (Next.js + Tailwind)
3. **XDC Node**: Core blockchain client (Geth/Erigon)
4. **Prometheus**: Metrics collection and storage
5. **SkyNet Agent**: Optional fleet monitoring integration

---

## 🤝 Contributing

We welcome contributions from the community!

### Getting Started

1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b feature/my-feature`
3. **Commit** your changes: `git commit -am 'Add new feature'`
4. **Push** to the branch: `git push origin feature/my-feature`
5. **Submit** a Pull Request

### Development Guidelines

- All scripts must pass `shellcheck` linting
- Include error handling (`set -euo pipefail`)
- Add tests for new features
- Update documentation
- Follow conventional commits

### Code of Conduct

This project adheres to a [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

---

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- [XDC Foundation](https://www.xdc.org/) for the XDC Network
- [Go Ethereum](https://geth.ethereum.org/) for the underlying client
- [Erigon](https://github.com/ledgerwatch/erigon) for the high-performance client
- All contributors and community members

---

<div align="center">

**[Documentation](docs/)** • **[Issues](https://github.com/AnilChinchawale/XDC-Node-Setup/issues)** • **[Discussions](https://github.com/AnilChinchawale/XDC-Node-Setup/discussions)** • **[XDC Network](https://xdc.network/)**

Built with ❤️ for the XDC Network community

</div>
