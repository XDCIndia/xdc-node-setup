# XDC Node Setup (XNS)

<div align="center">

![XDC Node Setup](https://img.shields.io/badge/XDC-Node%20Setup-blue?style=for-the-badge&logo=docker)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)](LICENSE)
[![Version](https://img.shields.io/badge/Version-2.1.0-blue?style=for-the-badge)](VERSION)
[![XDC Network](https://img.shields.io/badge/XDC-Network-brightgreen?style=for-the-badge)](https://xdc.network/)

**Run an XDC Network node with one command — no technical knowledge needed**

[🚀 Quick Start (Non-Technical)](#-quick-start-for-everyone) • [💻 Technical Setup](#-technical-setup) • [CLI Reference](#cli-reference) • [Troubleshooting](#troubleshooting)

</div>

---

## 🚀 Quick Start for Everyone

### What is an XDC Node?

An **XDC node** is a computer program that helps run the XDC Network — a fast, low-cost blockchain used for global trade and finance. Think of it like running a server that helps keep the network secure and running smoothly.

**You don't need to be a programmer.** If you can copy and paste a single command, you can run a node.

### One Command to Start

**Step 1:** Open your terminal (on Linux or macOS)

**Step 2:** Copy and paste this one line:

```bash
curl -fsSL https://install.xdc.network | bash
```

That's it. The installer will:
- ✅ Check your computer meets the requirements
- ✅ Install Docker (if not already installed)
- ✅ Download a recent snapshot (fast sync, not days)
- ✅ Start your node with safe defaults
- ✅ **Verify your node is actually working** before saying "done"

**What you'll see:**
```
🚀 XNS Installer v2.1.0
Checking requirements... ✓
Installing Docker... ✓
Downloading snapshot... ████████░░ 80%
Starting node... ✓
Waiting for peers... 3 peers connected ✓
Node is syncing! Current block: 45,231,000

✅ Setup complete! Your node is running.
   Check status anytime: xns status
   View logs: xns logs
   Stop node: xns down
```

### Check Your Node

```bash
xns status
```

Shows: sync percentage, peers, disk usage, and whether everything is healthy.

### Common Commands

| Command | What it does |
|---------|-------------|
| `xns status` | See if your node is healthy |
| `xns logs` | View recent logs |
| `xns logs -f` | Follow logs live |
| `xns down` | Stop the node |
| `xns up` | Start the node |
| `xns restart` | Restart the node |

### Need Help?

- 💬 [Discord](https://discord.gg/xdc) — ask questions, get help
- 📖 [Full Documentation](docs/README.md) — for advanced users
- 🛠️ [Troubleshooting](#troubleshooting) — common fixes

---

## 💻 Technical Setup

### For Developers & DevOps

```bash
# Clone and install
git clone https://github.com/XDCIndia/xdc-node-setup.git
cd xdc-node-setup

# Build XNS CLI
cd xns && go build -o xns ./cmd/xdccli

# One-command node setup
./xns node init --network apothem --client gp5 --name mynode --up

# Fleet deployment
./xns fleet deploy --config ~/.xns/fleet.yaml
```

See [docs/ADVANCED.md](docs/ADVANCED.md) for full technical documentation.

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

### One-Command Node Setup (XNS CLI v2.1)

```bash
# Single command: init spec + render compose + start container
xns init --network apothem --client gp5 --name mynode
xns up --network apothem --client gp5

# With snapshot restore (fastest path to sync)
xns snapshot --network apothem --client gp5
xns up --network apothem --client gp5
```

### What happens:
1. `init` — Creates docker-compose with XNS-standard ports
2. `up` — Starts container with correct bootnodes
3. `wait` — Blocks until `net.peerCount > 0` and blocks are progressing
4. `health` — Verifies node is actually syncing, not just "running"

### Fleet Setup (multi-server)

```bash
# Deploy to entire fleet from config
xns fleet deploy --config ~/.xns/fleet.yaml

# Rolling update with abort conditions
xns fleet rolling-update --fleet apothem \
  --abort-on validators-not-legit,epoch-stuck,state-root-mismatch
```

### Legacy One-Liner Install

```bash
curl -fsSL https://raw.githubusercontent.com/XDCIndia/xdc-node-setup/feat/xns-2.0-roadmap/install.sh | bash
```

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
| 🔍 **Real Healthcheck** | Verifies peers + sync + block progression | ✅ |
| 🔄 **Auto-Updates** | Automatic version checks and updates | ✅ |
| 🛠️ **Unified CLI** | Single `xns` command for all operations | ✅ |
| 📱 **Mobile Ready** | Responsive dashboard for mobile monitoring | ✅ |
| 🛡️ **Non-Interactive** | No prompts by default — safe for CI/CD | ✅ |
| 📦 **Pinned Images** | Reproducible builds — no `:latest` tags | ✅ |
| ↩️ **Atomic Rollback** | Failed installs clean up after themselves | ✅ |

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
# Quick start with defaults (GP5 client)
xns init --network mainnet --client gp5
xns up --network mainnet --client gp5

# With specific client
xns init --network mainnet --client v268
xns up --network mainnet --client v268

# With custom ports
xns init --network mainnet --client gp5
# Edit ~/.xns/compose-mainnet-gp5.yml to change ports
xns up --network mainnet --client gp5
```

### Apothem Testnet Setup

```bash
# One command
xns init --network apothem --client gp5
xns up --network apothem --client gp5

# With snapshot for fast sync
xns snapshot --network apothem --client gp5
xns up --network apothem --client gp5
```

**Apothem Testnet Details:**
- **Network ID:** 51
- **RPC:** http://localhost:9645
- **WebSocket:** ws://localhost:9646
- **Chain ID:** 51
- **Genesis:** Matches official XDPoSChain testnet

### Multi-Client Setup

Run all 4 XDC clients simultaneously:

```bash
# 1. Initialize each client
xns init --network mainnet --client gp5 --name gp5-node
xns init --network mainnet --client erigon --name erigon-node
xns init --network mainnet --client nethermind --name nm-node
xns init --network mainnet --client reth --name reth-node

# 2. Start all clients
xns up --network mainnet --client gp5
xns up --network mainnet --client erigon
xns up --network mainnet --client nethermind
xns up --network mainnet --client reth

# 3. Check status of all clients
xns status --network mainnet --client gp5
xns status --network mainnet --client erigon
```

**Multi-Client Port Allocation:**

| Client | RPC HTTP | RPC WS | P2P | Metrics |
|--------|----------|--------|-----|---------|
| GP5 (Geth PR5) | 8545 | 8546 | 30303 | 6070 |
| Erigon | 8547 | 8548 | 30304 | 6071 |
| Nethermind | 8548 | 8553 | 30304 | 6072 |
| Reth | 8588 | — | 30306 | 6073 |

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
# Edit ~/.xns/config.yaml to set bind_address: 127.0.0.1
xns restart
```

---

## 🖥️ CLI Reference

### Core Commands

```bash
# Initialize node configuration
xns init --network mainnet --client gp5 --name mynode

# Start node (waits until healthy)
xns up [--network mainnet] [--client gp5]

# Stop node
xns down [--network mainnet] [--client gp5]

# Restart node
xns restart [--network mainnet] [--client gp5]

# Check status
xns status [--network mainnet] [--client gp5]

# View logs
xns logs [--network mainnet] [--client gp5] [-f|--follow]

# Run healthcheck
xns health [--network mainnet] [--client gp5]

# Wait until node is ready
xns wait [--network mainnet] [--client gp5] [--timeout 300]

# Download snapshot
xns snapshot --network mainnet --client gp5

# Show config
xns config

# Show version
xns version

# Show help
xns help
```

### Global Options

| Option | Description | Default |
|--------|-------------|---------|
| `--network` | Network to use | `mainnet` |
| `--client` | Client to use | `gp5` |
| `--name` | Container name | `xns-node` |
| `--timeout` | Timeout for wait command | `300` |

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
export SKYNET_URL=https://skynet.xdcindia.com
xns up
```

---

## 🔧 Multi-Client Support

| Client | Version | Status | RPC Port | P2P Port |
|--------|---------|--------|----------|----------|
| **GP5 (Geth PR5)** | v2.1.0 | Production | 8545 | 30303 |
| **XDC Stable** | v2.6.8 | Production | 8545 | 30303 |
| **Erigon-XDC** | v1.0.0 | Experimental | 8547 | 30304 |
| **Nethermind-XDC** | v1.0.0 | Beta | 8558 | 30306 |
| **Reth-XDC** | v0.1.0 | Alpha | 8588 | 30306 |

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
xns logs -f

# Check peer count
xns status

# Check health
xns health

# Restart with fresh config
xns down
xns up
```

### Port Conflicts

```bash
# Check port usage
sudo lsof -i :8545
sudo lsof -i :30303

# Kill conflicting process or change ports
xns down
# Edit ~/.xns/compose-mainnet-gp5.yml to change ports
xns up
```

### No Peers Connected

```bash
# Check bootnodes are configured
xns config | grep bootnodes

# Manually add a peer (if needed)
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"admin_addPeer","params":["enode://..."],"id":1}'
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
- ✅ Non-interactive install (no prompts to accidentally skip)
- ✅ Checksum verification for downloads
- ✅ Atomic rollback on failure

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
