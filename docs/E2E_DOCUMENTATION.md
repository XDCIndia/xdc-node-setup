# XDC Node Setup - End-to-End Documentation

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Setup Instructions](#setup-instructions)
3. [Configuration Guide](#configuration-guide)
4. [Multi-Client Deployment](#multi-client-deployment)
5. [XDPoS 2.0 Operations](#xdpos-20-operations)
6. [Monitoring and Alerting](#monitoring-and-alerting)
7. [Troubleshooting](#troubleshooting)
8. [API Reference](#api-reference)
9. [Security Best Practices](#security-best-practices)

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

### Prerequisites

- Docker 20.10+ and Docker Compose 2.0+
- 4+ CPU cores
- 16GB+ RAM (32GB recommended for multi-client)
- 500GB+ SSD storage
- Linux/macOS/Windows (WSL2)

### Quick Start

```bash
# Clone the repository
git clone https://github.com/AnilChinchawale/xdc-node-setup.git
cd xdc-node-setup

# Copy environment template
cp .env.example .env

# Edit configuration
nano .env

# Start the node
docker-compose up -d
```

### One-Command Setup

```bash
# Interactive setup wizard
./setup.sh

# Or automated setup
./setup.sh --network mainnet --client geth --sync-mode snap
```

---

## Configuration Guide

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NETWORK_ID` | 50 | Mainnet=50, Testnet=51 |
| `SYNC_MODE` | snap | snap, full, fast |
| `RPC_PORT` | 8545 | JSON-RPC port |
| `P2P_PORT` | 30303 | P2P port |
| `SKYNET_API_URL` | https://net.xdc.network | SkyNet endpoint |
| `DATA_DIR` | ./data | Chain data directory |

### Network Configuration

#### Mainnet (Network ID: 50)
```bash
NETWORK_ID=50
RPC_PORT=8545
P2P_PORT=30303
BOOTNODES="enode://..."
```

#### Testnet (Network ID: 51)
```bash
NETWORK_ID=51
RPC_PORT=8545
P2P_PORT=30303
BOOTNODES="enode://..."
```

### Security Configuration

```bash
# Bind RPC to localhost only (recommended for production)
RPC_ADDR=127.0.0.1
WS_ADDR=127.0.0.1

# Restrict CORS origins
RPC_CORS_DOMAIN=http://localhost:7070
RPC_VHOSTS=localhost,127.0.0.1

# Disable pprof in production
PPROF_ENABLED=false
```

---

## Multi-Client Deployment

### Port Allocation

| Client | RPC Port | P2P Port | Metrics | Notes |
|--------|----------|----------|---------|-------|
| Geth Stable | 8545 | 30303 | 6060 | Official XDC client |
| Geth PR5 | 7070 | 30304 | 6070 | Latest XDPoS features |
| Erigon | 7071 | 30305 | 6071 | Dual-sentry architecture |
| Nethermind | 7072 | 30306 | 6072 | .NET implementation |
| Reth | 8588 | 40303 | 6073 | Rust implementation |

### Running Multiple Clients

```bash
# Start all clients
docker-compose -f docker-compose.multiclient.yml up -d

# Start specific clients
docker-compose -f docker-compose.multiclient.yml up -d xdc-geth-stable xdc-erigon

# Check client status
./scripts/multi-client-status.sh
```

### Client Comparison

| Client | Memory | Disk | Sync Speed | Best For |
|--------|--------|------|------------|----------|
| Geth-XDC | 4GB+ | 500GB | Medium | Production stability |
| Erigon | 8GB+ | 400GB | Fast | Archive nodes |
| Nethermind | 12GB+ | 350GB | Fast | Enterprise |
| Reth | 16GB+ | 300GB | Very Fast | Development |

---

## XDPoS 2.0 Operations

### Epoch Structure

```
Epoch N (Blocks 0-899):
┌────────────────────┬───────────────────┐
│  Voting Phase      │    Gap Phase      │
│  Blocks 0-449      │   Blocks 450-899  │
│  (Validator votes) │   (No votes)      │
└────────────────────┴───────────────────┘
```

### Quorum Certificate Validation

```bash
# Check QC for latest block
./scripts/qc-validation.sh

# Monitor QC continuously
./scripts/qc-validation.sh --continuous
```

### Gap Block Monitoring

```bash
# Check gap blocks
./scripts/xdpos/gap-block-monitor.sh

# Monitor continuously
./scripts/xdpos/gap-block-monitor.sh --continuous
```

### Consensus Health Check

```bash
# Run consensus health check
./scripts/consensus-health.sh

# Check masternode status
./scripts/masternode-status.sh
```

---

## Monitoring and Alerting

### Prometheus Metrics

| Metric | Description |
|--------|-------------|
| `xdc_block_number` | Current block height |
| `xdc_peer_count` | Number of connected peers |
| `xdc_sync_status` | Sync status (0=syncing, 1=synced) |
| `xdc_consensus_vote_participation` | Vote participation rate |
| `xdc_consensus_qc_healthy` | QC formation health |

### Grafana Dashboards

Access Grafana at `http://localhost:3000`

- **Node Overview**: Basic node metrics
- **Consensus Health**: XDPoS 2.0 specific metrics
- **Multi-Client Comparison**: Side-by-side client metrics

### SkyNet Integration

```bash
# Register node with SkyNet
./scripts/skynet-agent.sh --register

# Start SkyNet agent daemon
./scripts/skynet-agent.sh --daemon

# Install as systemd service
./scripts/skynet-agent.sh --install
```

---

## Troubleshooting

### Sync Issues

#### Symptom: Node not syncing
```bash
# Check peer connectivity
./scripts/fix-peer-connectivity.sh

# Check sync status
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

# Restart node
docker-compose restart xdc-node
```

#### Symptom: Slow sync
```bash
# Download snapshot for fast sync
./scripts/snapshot-download.sh

# Verify snapshot integrity
./scripts/snapshot-verify.sh /path/to/snapshot.tar.gz
```

### Consensus Issues

#### Symptom: Missing votes
```bash
# Check masternode status
./scripts/consensus-health.sh

# Check if in masternode set
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getMasternodesByNumber","params":["latest"],"id":1}'
```

#### Symptom: High timeout rate
```bash
# Check timeout certificates
./scripts/consensus-monitor.sh --check-timeouts

# View logs
docker logs xdc-node | grep -i timeout
```

### Network Issues

#### Symptom: No peers
```bash
# Add bootstrap peers
./scripts/inject-peers.sh

# Check network connectivity
./scripts/network-diagnostic.sh
```

---

## API Reference

### JSON-RPC Endpoints

#### Standard Ethereum Methods

```bash
# Get block number
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Get block by number
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}'

# Get peer count
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
```

#### XDPoS 2.0 Methods

```bash
# Get masternodes
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getMasternodesByNumber","params":["latest"],"id":1}'

# Get V2 block info
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getV2BlockByNumber","params":["latest"],"id":1}'

# Get round info
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getRoundInfo","params":["latest"],"id":1}'
```

---

## Security Best Practices

### Production Checklist

- [ ] RPC bound to localhost only
- [ ] CORS origins restricted
- [ ] Firewall enabled (UFW)
- [ ] Fail2ban installed
- [ ] SSH key-only authentication
- [ ] Non-standard SSH port
- [ ] Unattended upgrades enabled
- [ ] Regular security updates
- [ ] Backup configured
- [ ] Monitoring active

### Security Score

| Check | Points |
|-------|--------|
| SSH key-only | 10 |
| Non-standard SSH port | 5 |
| Firewall active | 10 |
| Fail2ban running | 5 |
| Unattended upgrades | 5 |
| OS patches current | 10 |
| Client version current | 15 |
| Monitoring active | 10 |
| Backup configured | 10 |
| Audit logging | 10 |
| Disk encryption | 10 |
| **Total** | **100** |

Run security audit:
```bash
./scripts/cis-benchmark.sh
```

---

*Documentation Version: 1.0*  
*Last Updated: March 2026*
