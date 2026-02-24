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

## 🔧 Multi-Client Support

XDC Node Setup supports **five different clients** for improved network diversity and resilience:

### Client Comparison

| Feature | XDC Stable | XDC Geth PR5 | Erigon-XDC | Nethermind-XDC | Reth-XDC |
|---------|------------|--------------|------------|----------------|----------|
| **Version** | v2.6.8 | Latest | Latest | Latest | Latest |
| **Type** | Official Docker | Source build | Source build | .NET build | Rust build |
| **Build Time** | Instant | ~10-15 min | ~10-15 min | ~10-15 min | ~20-30 min |
| **RPC Port** | 8545 | 8545 | **8547** | **8558** | **7073** |
| **Auth RPC Port** | N/A | N/A | **8561** | N/A | N/A |
| **Private API** | N/A | N/A | **9091** | N/A | N/A |
| **P2P Port** | 30303 | 30303 | **30304** + 30311 | **30306** | **40303** |
| **P2P Protocol** | eth/63 | eth/63 | eth/63 + eth/68 | eth/100 | eth/100 |
| **XDC Peer Compatible** | ✅ Yes | ✅ Yes | ✅ Port 30304 only | ✅ Yes | ✅ Yes |
| **Sync Speed** | Standard | Standard | Fast | Very Fast | Very Fast |
| **Disk Usage** | ~500GB | ~500GB | ~400GB | ~350GB | ~300GB |
| **Memory** | 4GB+ | 4GB+ | **8GB+** | **12GB+** | **16GB+** |
| **Status** | Production | Testing | **Experimental** | **Beta** | **Alpha** |

### Selecting a Client

During setup, choose your preferred client:

```bash
# Run setup with specific client selection
bash setup.sh --client erigon

# Or run interactive setup
bash setup.sh
```

Interactive client selection:

```bash
Client Selection
=================
1) XDC Stable (v2.6.8) - Official Docker image (recommended)
2) XDC Geth PR5 - Latest geth with XDPoS (builds from source)
3) Erigon-XDC - Multi-client diversity, experimental
4) Nethermind-XDC - .NET-based client with eth/100 protocol (beta)
5) Reth-XDC - Rust-based execution client, fastest sync (alpha)

Select client [1-5] (default: 1):
```

### Erigon Client

The **Erigon-XDC** client provides multi-client diversity with a dual-sentry architecture:

- **eth/63 sentry** on port **30304** — connects to XDC Network peers
- **eth/68 sentry** on port **30311** — standard Ethereum P2P (NOT compatible with XDC)
- **RPC** on port **8547** — JSON-RPC API endpoint

> ⚠️ **WARNING - P2P Port Compatibility**
> 
> **Port 30304 (eth/63)** is for **XDC peers** — this is the ONLY port compatible with XDC geth nodes.

### Nethermind Client

The **Nethermind-XDC** client is a .NET-based implementation with eth/100 protocol support:

- **eth/100 protocol** — Full compatibility with XDC Network
- **RPC** on port **8558** — JSON-RPC API endpoint
- **P2P** on port **30306** — Connects to all XDC peers
- **Fast sync** — Optimized sync speed and reduced disk usage

### Reth Client

The **Reth-XDC** client is a Rust-based execution client offering cutting-edge performance:

- **Rust implementation** — Memory-safe, high-performance execution engine
- **RPC** on port **7073** — JSON-RPC API endpoint
- **P2P** on port **40303** — XDC Network peer connectivity
- **Discovery** on port **40304** — UDP peer discovery
- **Fastest sync** — Optimized database design for rapid initial sync
- **Requires debug.tip** — Manual sync tip hash required (no CL available)

> ⚠️ **ALPHA STATUS**
> 
> Reth-XDC is in **early alpha**. Requires more memory (16GB+) and needs `--debug.tip` hash for syncing.
> 
> **Port 30311 (eth/68)** is NOT compatible with XDC geth nodes — it uses a newer Ethereum protocol.
> 
> **Always use port 30304** when connecting Erigon to XDC geth nodes.

> **Note:** Erigon builds from source which takes approximately **10-15 minutes** during initial setup.

For complete Erigon setup instructions, see [**docs/ERIGON.md**](docs/ERIGON.md).

### Switching Clients

```bash
# Start with specific client
xdc start --client stable
xdc start --client geth-pr5
xdc start --client erigon
xdc start --client nethermind
xdc start --client reth

# Check current client
xdc client
```

### Why Multi-Client Matters

- ✅ **Network Resilience**: Prevents single-client bugs from affecting the entire network
- ✅ **Performance Options**: Choose the best client for your use case
- ✅ **Future-Proof**: Easy migration as clients evolve
- ✅ **Diversity**: Contributes to XDC network health

---

## 🔷 Erigon-XDC Client Guide

Erigon-XDC is an experimental high-performance client for the XDC Network. This section covers erigon-specific setup and configuration.

### Installation with Erigon

#### Option 1: Interactive Setup
```bash
./setup.sh
# Select option 3: Erigon-XDC when prompted for client
```

#### Option 2: Command Line
```bash
# Start with erigon client
xdc start --client erigon

# Or set environment variable
CLIENT=erigon ./setup.sh
```

### Erigon-Specific Configuration

Erigon uses different default ports than the standard geth clients:

| Port | Protocol | Purpose | XDC Compatible | Notes |
|------|----------|---------|----------------|-------|
| **8547** | HTTP | RPC API | N/A | Default erigon RPC port (vs 8545 for geth) |
| **8561** | HTTP | Auth RPC | N/A | Authentication-required RPC |
| **9091** | TCP | Private API | N/A | Internal erigon API |
| **30304** | TCP/UDP | P2P eth/63 | ✅ Yes | **Primary peer port - XDC compatible** |
| **30311** | TCP/UDP | P2P eth/68 | ❌ No | New protocol - NOT compatible with XDC geth nodes |

**Important:** Erigon runs TWO P2P sentries simultaneously:
- **Port 30304** uses eth/63 protocol (backward compatible with XDC geth nodes)
- **Port 30311** uses eth/68 protocol (newer, but NOT compatible with XDC network)

### Environment Variables

Add to your `.env` file or export before starting:

```bash
# Erigon-specific ports
RPC_PORT=8547                    # Erigon RPC (different from geth's 8545)
P2P_PORT=30304                   # eth/63 compatible port
P2P_PORT_68=30311                # eth/68 port (not XDC compatible)
INSTANCE_NAME=Erigon_XDC_Node

# Optional: Resource limits
ERIGON_MEMORY=12G                # Erigon needs more RAM than geth
ERIGON_CPUS=4
```

### Connecting Erigon to Existing Geth Nodes

When running erigon in a mixed environment with geth nodes, you must use **port 30304** (eth/63) for peer connections:

#### Step 1: Get Erigon's Enode ID
```bash
# From the erigon node
curl -X POST http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}'
```

#### Step 2: Add Erigon as Trusted Peer on Geth
```bash
# On the geth node (port 8545), add erigon using port 30304
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "admin_addTrustedPeer",
    "params": ["enode://<erigon_node_id>@<erigon_ip>:30304"],
    "id": 1
  }'
```

⚠️ **Critical:** Always use port 30304 for peer connections. Port 30311 (eth/68) is NOT compatible with XDC geth nodes.

### Firewall Configuration for Erigon

Erigon requires additional firewall rules:

```bash
# Allow eth/63 P2P port (XDC compatible)
sudo ufw allow 30304/tcp comment 'Erigon P2P eth/63'
sudo ufw allow 30304/udp comment 'Erigon P2P eth/63'

# Allow eth/68 P2P port (optional, not XDC compatible)
sudo ufw allow 30311/tcp comment 'Erigon P2P eth/68'
sudo ufw allow 30311/udp comment 'Erigon P2P eth/68'

# RPC port (binds to localhost by default, external access not recommended)
# sudo ufw allow 8547/tcp comment 'Erigon RPC (local only recommended)'
```

### Docker Compose Override

The erigon configuration uses a docker-compose override file:

```bash
# Manual start with erigon
cd docker
docker compose -f docker-compose.yml -f docker-compose.erigon.yml up -d

# Or use the CLI
xdc start --client erigon
```

### Switching to/from Erigon

```bash
# Switch to erigon
xdc stop
xdc start --client erigon

# Switch back to stable
xdc stop
xdc start --client stable

# Check current client
xdc client
```

### Known Limitations

| Limitation | Description | Workaround |
|------------|-------------|------------|
| **Build Time** | Erigon builds from source (10-15 min) | Pre-build image or use CI/CD |
| **Memory Requirements** | Requires 8GB+ RAM | Ensure adequate system resources |
| **eth/68 Incompatibility** | Port 30311 not XDC compatible | Always use port 30304 for peers |
| **RPC Port Difference** | Uses 8547 vs geth's 8545 | Update scripts/tools to use correct port |
| **Experimental Status** | Not production-ready | Test thoroughly before mainnet use |
| **Snapshot Compatibility** | Erigon snapshots differ from geth | Sync from genesis or use erigon-specific snapshots |

### Troubleshooting Erigon

#### Check Erigon Status
```bash
# Verify erigon is running
xdc status

# Check erigon logs
xdc logs --client erigon

# Check erigon-specific logs
docker logs xdc-node-erigon
```

#### Port Conflicts
```bash
# Check if ports are in use
sudo ss -tlnp | grep -E '30304|30311|8547'

# Find and stop conflicting services
sudo lsof -i :30304
```

#### Peer Connection Issues
```bash
# Check peer count
curl -X POST http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'

# Manually add trusted peer (use port 30304!)
curl -X POST http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "admin_addTrustedPeer",
    "params": ["enode://...:30304"],
    "id": 1
  }'
```

#### Build Issues
```bash
# Clean and rebuild
cd docker/erigon
docker build --no-cache -t erigon-xdc:latest .

# Check build logs
docker build -t erigon-xdc:latest . 2>&1 | tee build.log
```

### Architecture Notes

Erigon's dual-sentry design:
```
┌─────────────────────────────────────────┐
│         Erigon-XDC Node                │
├─────────────────────────────────────────┤
│                                         │
│  ┌──────────────┐    ┌──────────────┐  │
│  │ Sentry 1     │    │ Sentry 2     │  │
│  │ Port 30304   │    │ Port 30311   │  │
│  │ eth/63       │    │ eth/68       │  │
│  │ XDC compat   │    │ NOT compat   │  │
│  └──────┬───────┘    └──────┬───────┘  │
│         │                   │          │
│         └─────────┬─────────┘          │
│                   │                    │
│            ┌──────┴──────┐             │
│            │   Erigon    │             │
│            │   Core      │             │
│            └──────┬──────┘             │
│                   │                    │
│              RPC:8547                  │
│              Auth:8561                 │
│              Private:9091              │
│                                         │
└─────────────────────────────────────────┘
```

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
