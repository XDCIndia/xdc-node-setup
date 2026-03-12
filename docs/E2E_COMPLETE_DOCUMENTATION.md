# XDC Node Setup - End-to-End Documentation

**Version:** 2.2.0  
**Last Updated:** March 4, 2026  
**Repository:** https://github.com/AnilChinchawale/xdc-node-setup

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Setup Instructions](#setup-instructions)
3. [Configuration Guide](#configuration-guide)
4. [Client Support](#client-support)
5. [Security Hardening](#security-hardening)
6. [Monitoring & Alerting](#monitoring--alerting)
7. [Troubleshooting](#troubleshooting)
8. [API Reference](#api-reference)
9. [XDPoS 2.0 Consensus](#xdpos-20-consensus)
10. [Multi-Client Deployment](#multi-client-deployment)

---

## Architecture Overview

### System Architecture

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
3. **XDC Node**: Core blockchain client (Geth/Erigon/Nethermind/Reth)
4. **Prometheus**: Metrics collection and storage
5. **SkyNet Agent**: Optional fleet monitoring integration

---

## Setup Instructions

### Quick Start (One-Liner)

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

### Requirements

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

## Configuration Guide

### Directory Structure

```
XDC-Node-Setup/
├── mainnet/
│   ├── .xdc-node/
│   │   ├── config.toml
│   │   ├── node.env
│   │   └── skynet.conf
│   └── xdcchain/
├── testnet/
│   └── ...
├── docker/
│   ├── docker-compose.yml
│   └── mainnet/
│       ├── genesis.json
│       ├── start-node.sh
│       └── bootnodes.list
└── configs/
    └── config.toml.template
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NODE_TYPE` | full | Node type: full, archive, rpc, masternode |
| `NETWORK` | mainnet | Network: mainnet, testnet, devnet, apothem |
| `CLIENT` | stable | Client: stable, geth-pr5, erigon, nethermind, reth |
| `SYNC_MODE` | full | Sync mode: full, snap |
| `RPC_PORT` | 9545 | RPC port |
| `P2P_PORT` | 30303 | P2P port |
| `DATA_DIR` | ./mainnet/xdcchain | Data directory |
| `ENABLE_MONITORING` | false | Enable Prometheus/Grafana |
| `ENABLE_SKYNET` | false | Enable SkyNet fleet monitoring |
| `ENABLE_SECURITY` | true | Enable security hardening |

### Client-Specific Ports

#### Erigon-XDC
| Port | Protocol | Purpose | XDC Compatible |
|------|----------|---------|----------------|
| 8547 | HTTP | RPC API | N/A |
| 8561 | HTTP | Auth RPC | N/A |
| 9091 | TCP | Private API | N/A |
| 30304 | TCP/UDP | P2P eth/63 | ✅ Yes |
| 30311 | TCP/UDP | P2P eth/68 | ❌ No |

#### Nethermind-XDC
| Port | Protocol | Purpose |
|------|----------|---------|
| 8558 | HTTP | RPC API |
| 30306 | TCP/UDP | P2P |

#### Reth-XDC
| Port | Protocol | Purpose |
|------|----------|---------|
| 7073 | HTTP | RPC API |
| 40303 | TCP/UDP | P2P |
| 40304 | UDP | Discovery |

---

## Client Support

### Client Comparison

| Feature | XDC Stable | XDC Geth PR5 | Erigon-XDC | Nethermind-XDC | Reth-XDC |
|---------|------------|--------------|------------|----------------|----------|
| **Version** | v2.6.8 | Latest | Latest | Latest | Latest |
| **Type** | Official Docker | Source build | Source build | .NET build | Rust build |
| **Build Time** | Instant | ~10-15 min | ~10-15 min | ~10-15 min | ~20-30 min |
| **RPC Port** | 8545 | 8545 | 8547 | 8558 | 7073 |
| **P2P Port** | 30303 | 30303 | 30304/30311 | 30306 | 40303 |
| **Sync Speed** | Standard | Standard | Fast | Very Fast | Very Fast |
| **Disk Usage** | ~500GB | ~500GB | ~400GB | ~350GB | ~300GB |
| **Memory** | 4GB+ | 4GB+ | 8GB+ | 12GB+ | 16GB+ |
| **Status** | Production | Testing | Experimental | Beta | Alpha |

### Selecting a Client

```bash
# Run setup with specific client selection
bash setup.sh --client erigon

# Or start with specific client
xdc start --client erigon
xdc start --client nethermind
xdc start --client reth
```

---

## Security Hardening

### Default Security Features

- SSH hardening
- UFW firewall configuration
- fail2ban intrusion prevention
- Audit logging
- Docker security options (`no-new-privileges`, `cap_drop: ALL`)

### Security Best Practices

1. **RPC Binding**
   ```bash
   # Bind to localhost only (default)
   RPC_ADDR=127.0.0.1
   
   # Use nginx reverse proxy for external access
   ```

2. **CORS Configuration**
   ```bash
   # Restrict to specific origins
   RPC_CORS_DOMAIN=https://your-domain.com
   RPC_VHOSTS=your-domain.com
   ```

3. **Firewall Rules**
   ```bash
   # Allow SSH
   sudo ufw allow 22/tcp
   
   # Allow P2P
   sudo ufw allow 30303/tcp
   sudo ufw allow 30303/udp
   
   # RPC is bound to localhost - no external access needed
   ```

### Security Audit Results

| Issue | Severity | Status |
|-------|----------|--------|
| RPC CORS Wildcard | P0 | Fixed |
| RPC Bound to 0.0.0.0 | P0 | Fixed |
| Hardcoded Credentials | P0 | Fixed |
| pprof Exposed | P0 | Fixed |
| Docker Socket Mount | P1 | Fixed |
| Privileged Containers | P1 | Fixed |

---

## Monitoring & Alerting

### SkyOne Dashboard

Access the built-in dashboard at `http://localhost:7070`

**Features:**
- Real-time metrics (block height, sync status, peer count)
- System monitoring (CPU, memory, disk usage)
- Network statistics (latency, throughput)
- Alert timeline
- Security score

### Prometheus & Grafana

Enable monitoring during setup:
```bash
ENABLE_MONITORING=true ./setup.sh
```

**Access:**
- Prometheus: `http://localhost:9090`
- Grafana: `http://localhost:3000` (default: admin/admin)

### SkyNet Integration

Nodes automatically report to SkyNet for fleet monitoring:

```bash
# Enable SkyNet
xdc config set skynet_enabled true
xdc restart
```

**Fleet Dashboard:** https://net.xdc.network

---

## Troubleshooting

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

---

## API Reference

### CLI Commands

| Command | Description | Example |
|---------|-------------|---------|
| `xdc status` | Display node status | `xdc status --watch` |
| `xdc start` | Start the XDC node | `xdc start --client erigon` |
| `xdc stop` | Stop the XDC node | `xdc stop` |
| `xdc restart` | Restart the node | `xdc restart` |
| `xdc logs` | View node logs | `xdc logs --follow` |
| `xdc info` | Show detailed node info | `xdc info` |
| `xdc monitor` | Open SkyOne dashboard | `xdc monitor` |
| `xdc health` | Run health check | `xdc health --full` |
| `xdc peers` | List connected peers | `xdc peers` |
| `xdc sync` | Check sync status | `xdc sync` |
| `xdc backup` | Create encrypted backup | `xdc backup create` |
| `xdc snapshot` | Download/apply snapshot | `xdc snapshot download` |
| `xdc update` | Check for updates | `xdc update` |

### JSON-RPC API

The XDC node exposes standard Ethereum JSON-RPC endpoints:

```bash
# Get block number
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Get syncing status
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

# Get peer count
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
```

### XDPoS-Specific Methods

```bash
# Get masternodes
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getMasternodes","params":[],"id":1}'

# Get epoch number
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getEpochNumber","params":[],"id":1}'
```

---

## XDPoS 2.0 Consensus

### Overview

XDPoS 2.0 is the consensus mechanism used by XDC Network, featuring:

- **Delegated Proof of Stake (DPoS)**: 108 masternodes
- **Epoch-based consensus**: 900 blocks per epoch
- **Quorum Certificates (QC)**: For block finality
- **Timeout Certificates (TC)**: For liveness
- **Gap blocks**: Every 900th block (no transactions)

### Consensus Parameters

| Parameter | Value |
|-----------|-------|
| Epoch Length | 900 blocks |
| Masternode Count | 108 |
| Block Time | 2 seconds |
| Quorum | 2/3 + 1 of masternodes |

### Monitoring XDPoS 2.0

The node setup includes monitoring for:

- **Epoch transitions**: Alert when epoch changes
- **QC formation**: Track quorum certificate formation time
- **Vote participation**: Monitor masternode voting
- **Timeout events**: Track timeout certificates
- **Gap blocks**: Handle special gap block logic

### XDPoS 2.0 API

```bash
# Get current epoch
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getEpochNumber","params":["latest"],"id":1}'

# Get masternode list
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getMasternodes","params":["latest"],"id":1}'
```

---

## Multi-Client Deployment

### Running Multiple Clients

```bash
# Start all clients simultaneously
xdc start --client all

# Or start individually on different ports
CLIENT=stable RPC_PORT=8545 P2P_PORT=30303 xdc start
CLIENT=erigon RPC_PORT=8547 P2P_PORT=30304 xdc start
CLIENT=nethermind RPC_PORT=8558 P2P_PORT=30306 xdc start
```

### Port Allocation Strategy

| Client | RPC Port | P2P Port | Dashboard |
|--------|----------|----------|-----------|
| XDC Stable | 8545 | 30303 | 7070 |
| Erigon | 8547 | 30304 | 7071 |
| Nethermind | 8558 | 30306 | 7072 |
| Reth | 7073 | 40303 | 7073 |

### Cross-Client Peer Connections

```bash
# Add Erigon as trusted peer to Geth (use port 30304!)
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "admin_addTrustedPeer",
    "params": ["enode://<erigon_node_id>@<erigon_ip>:30304"],
    "id": 1
  }'
```

### Kubernetes Deployment

```bash
# Deploy with Helm
helm install xdc-node ./helm/xdc-node \
  --set client=erigon \
  --set network=mainnet \
  --set persistence.size=500Gi
```

---

## Additional Resources

- [Full Documentation](docs/)
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- [Security Guide](docs/SECURITY.md)
- [XDPoS 2.0 Guide](docs/XDPOS2-CONSENSUS.md)
- [Multi-Client Guide](docs/MULTI-CLIENT-GUIDE.md)
- [API Reference](docs/API_REFERENCE.md)

---

**License:** MIT  
**Maintainer:** @anilchinchawale
