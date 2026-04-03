# XDC Node Infrastructure - End-to-End Documentation

**Version:** 1.0.0  
**Date:** February 27, 2026  
**Author:** XDC EVM Expert Agent

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Setup Instructions](#setup-instructions)
3. [Configuration Guide](#configuration-guide)
4. [Multi-Client Deployment](#multi-client-deployment)
5. [Monitoring and Alerting](#monitoring-and-alerting)
6. [XDPoS 2.0 Consensus](#xdpos-20-consensus)
7. [Troubleshooting](#troubleshooting)
8. [API Reference](#api-reference)
9. [Security Best Practices](#security-best-practices)

---

## Architecture Overview

### System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         XDC Node Infrastructure                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                      XDC Node Setup (SkyOne)                      │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌──────────────┐  │   │
│  │  │ XDC Node  │  │  SkyOne   │  │ Prometheus│  │  SkyNet      │  │   │
│  │  │  (Geth/   │  │ Dashboard │  │ (Metrics) │  │  Agent       │  │   │
│  │  │  Erigon)  │  │ (Port 7070)│  │           │  │              │  │   │
│  │  └─────┬─────┘  └─────┬─────┘  └─────┬─────┘  └──────┬───────┘  │   │
│  │        │              │              │               │          │   │
│  │        └──────────────┴──────────────┘               │          │   │
│  │                       │                              │          │   │
│  │                       ▼                              ▼          │   │
│  │              ┌─────────────────┐          ┌─────────────────┐   │   │
│  │              │   XDC Chain     │          │   SkyNet API    │   │   │
│  │              │   Data          │          │   (Heartbeat)   │   │   │
│  │              └─────────────────┘          └─────────────────┘   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                    │                                     │
│                                    ▼                                     │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                      XDC SkyNet (Dashboard)                       │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌──────────────┐  │   │
│  │  │  Fleet    │  │  Node     │  │  Masternode│  │   Alerts     │  │   │
│  │  │  Dashboard│  │  Details  │  │  Analytics │  │   Engine     │  │   │
│  │  └───────────┘  └───────────┘  └───────────┘  └──────────────┘  │   │
│  │                                                                  │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌──────────────┐  │   │
│  │  │ PostgreSQL│  │   Redis   │  │  WebSocket │  │   API        │  │   │
│  │  │ (Metadata)│  │  (Cache)  │  │  (Realtime)│  │  (REST)      │  │   │
│  │  └───────────┘  └───────────┘  └───────────┘  └──────────────┘  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Descriptions

| Component | Purpose | Technology |
|-----------|---------|------------|
| XDC Node | Blockchain client | Geth-XDC, Erigon, Nethermind, Reth |
| SkyOne Dashboard | Single-node monitoring | Next.js 14, Prometheus |
| SkyNet Agent | Fleet reporting | Bash, curl |
| SkyNet Dashboard | Fleet management | Next.js 14, PostgreSQL |
| Prometheus | Metrics collection | Prometheus TSDB |

---

## Setup Instructions

### Prerequisites

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Ubuntu 20.04+ | Ubuntu 22.04 LTS |
| Docker | 20.10+ | Latest stable |
| RAM | 4GB | 16GB+ |
| Disk | 100GB HDD | 500GB+ NVMe SSD |
| Network | 10 Mbps | 100 Mbps+ |
| CPU | 2 cores | 4+ cores |

### Quick Start

#### 1. XDC Node Setup (SkyOne)

```bash
# One-liner install
curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/XDC-Node-Setup/main/install.sh | sudo bash

# Or manual installation
git clone https://github.com/AnilChinchawale/XDC-Node-Setup.git
cd XDC-Node-Setup
sudo ./install.sh

# Check status
xdc status
```

#### 2. XDC SkyNet (Dashboard)

```bash
# Clone repository
git clone https://github.com/AnilChinchawale/XDCNetOwn.git
cd XDCNetOwn

# Install dependencies
npm install

# Configure environment
cp dashboard/.env.example dashboard/.env
# Edit dashboard/.env with your settings

# Run database migrations
npm run db:init

# Start development server
npm run dev
```

---

## Configuration Guide

### XDC Node Configuration

#### Mainnet Configuration

File: `mainnet/.xdc-node/config.toml`

```toml
[node]
NetworkId = 50
DataDir = "/xdcchain"
HTTPPort = 8545
WSPort = 8546
Port = 30303
MaxPeers = 50

[eth]
SyncMode = "full"
GCMode = "full"
Cache = 4096

[metrics]
Enabled = true
Port = 6060
```

#### Environment Variables

File: `mainnet/.xdc-node/.env`

```bash
# Network Configuration
NETWORK=mainnet
NODE_NAME=xdc-node

# RPC Configuration (SECURE DEFAULTS)
RPC_PORT=8545
RPC_ADDR=127.0.0.1
RPC_CORS_DOMAIN=http://localhost:3000
RPC_VHOSTS=localhost
WS_PORT=8546
WS_ADDR=127.0.0.1
WS_ORIGINS=http://localhost:3000

# P2P Configuration
P2P_PORT=30303
P2P_NAT=any

# Performance Tuning
CACHE=4096
TRIE_CACHE=1024

# Security
PPROF_ADDR=127.0.0.1

# SkyNet Integration
SKYNET_API_URL=https://skynet.xdcindia.com/api/v1
SKYNET_API_KEY=your_api_key_here
```

### SkyNet Configuration

File: `dashboard/.env`

```bash
# Database
DATABASE_URL=postgresql://user:pass@localhost:5432/skynet

# API Keys (comma-separated)
API_KEYS=xdc-netown-key-2026-prod,another-key

# Redis (optional)
REDIS_URL=redis://localhost:6379

# Next.js
NEXT_PUBLIC_API_URL=http://localhost:3000
NEXT_PUBLIC_REFRESH_INTERVAL=10000
```

---

## Multi-Client Deployment

### Client Comparison

| Feature | XDC Stable | Erigon-XDC | Nethermind-XDC | Reth-XDC |
|---------|------------|------------|----------------|----------|
| Version | v2.6.8 | Latest | Latest | Latest |
| RPC Port | 8545 | 8547 | 8558 | 7073 |
| P2P Port | 30303 | 30304/30311 | 30306 | 40303 |
| Memory | 4GB+ | 8GB+ | 12GB+ | 16GB+ |
| Disk | ~500GB | ~400GB | ~350GB | ~300GB |
| Status | Production | Experimental | Beta | Alpha |

### Running Multiple Clients on Same Machine

```bash
# Client 1: XDC Stable (default ports)
xdc start --client stable --name xdc-stable

# Client 2: Erigon (alternate ports)
xdc start --client erigon --name xdc-erigon \
  --rpc-port 8547 --p2p-port 30304

# Client 3: Nethermind (alternate ports)
xdc start --client nethermind --name xdc-nethermind \
  --rpc-port 8558 --p2p-port 30306
```

### Docker Compose Multi-Client

```yaml
# docker-compose.multiclient.yml
version: '3.8'
services:
  xdc-stable:
    image: xinfinorg/xdposchain:v2.6.8
    ports:
      - "8545:8545"
      - "30303:30303"
    volumes:
      - ./stable-data:/work/xdcchain

  xdc-erigon:
    build: ./docker/erigon
    ports:
      - "8547:8547"
      - "30304:30304"
    volumes:
      - ./erigon-data:/data

  xdc-nethermind:
    build: ./docker/nethermind
    ports:
      - "8558:8558"
      - "30306:30306"
    volumes:
      - ./nethermind-data:/data
```

---

## Monitoring and Alerting

### SkyOne Dashboard

Access at: `http://localhost:7070`

**Features:**
- Real-time block height and sync status
- Peer count and geographic distribution
- System metrics (CPU, memory, disk)
- Alert timeline

### SkyNet Fleet Dashboard

Access at: `https://skynet.xdcindia.com`

**Features:**
- Multi-node fleet overview
- Health scoring per node
- Consensus participation tracking
- Automated incident detection

### Alert Types

| Alert | Severity | Trigger |
|-------|----------|---------|
| Node Down | Critical | No heartbeat for 5 minutes |
| Sync Stall | High | No block progress for 10 minutes |
| Disk Critical | Critical | Disk usage > 90% |
| Peer Drop | High | Peer count < 5 |
| Consensus Fork | Critical | Block hash divergence |

### Prometheus Metrics

```yaml
# Key metrics to monitor
- xdc_block_number
- xdc_peer_count
- xdc_sync_progress
- node_cpu_usage
- node_memory_usage
- node_disk_usage
```

---

## XDPoS 2.0 Consensus

### Consensus Parameters

| Parameter | Value |
|-----------|-------|
| Epoch Length | 900 blocks |
| Gap Blocks | 450 blocks (blocks 450-899) |
| Masternodes | 108 |
| Block Time | 2 seconds |
| Finality | Instant (QC-based) |

### Epoch Structure

```
Epoch N (900 blocks)
├── Blocks 0-449: Normal block production
├── Blocks 450-899: Gap blocks (no production, vote collection)
└── Epoch N+1: New masternode set activated
```

### Consensus Monitoring

**Key Metrics:**
- Vote participation rate
- QC formation time
- Missed blocks per masternode
- Epoch transition time

**API Endpoints:**
```bash
# Get current epoch
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getEpochNumber","params":[],"id":1}'

# Get masternode list
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getMasternodes","params":[],"id":1}'
```

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

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| "bind: address already in use" | Port conflict | Change port or stop conflicting service |
| "no peers available" | Network/firewall issue | Check P2P port, firewall rules |
| "bad block" | Consensus fork | Restart with `--resync` flag |
| "out of memory" | Insufficient RAM | Increase swap or reduce cache |

---

## API Reference

### SkyNet V1 API

#### Authentication

All API endpoints require Bearer token authentication:

```http
Authorization: Bearer YOUR_API_KEY
```

#### Heartbeat

```bash
POST /api/v1/nodes/heartbeat
Content-Type: application/json

{
  "nodeId": "550e8400-e29b-41d4-a716-446655440000",
  "blockHeight": 89234567,
  "syncing": false,
  "syncProgress": 99.8,
  "peerCount": 25,
  "system": {
    "cpuPercent": 45.2,
    "memoryPercent": 62.1,
    "diskPercent": 78.0
  },
  "clientType": "geth",
  "clientVersion": "v2.6.8-stable"
}
```

#### Fleet Status

```bash
GET /api/v1/fleet/status
Authorization: Bearer YOUR_API_KEY
```

Response:
```json
{
  "success": true,
  "data": {
    "healthScore": 92,
    "totalNodes": 12,
    "nodes": [
      {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "name": "xdc-node-01",
        "status": "healthy",
        "blockHeight": 89234567,
        "peerCount": 25
      }
    ]
  }
}
```

### XDC Node RPC

```bash
# Get block number
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Get peer count
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'

# Get syncing status
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
```

---

## Security Best Practices

### 1. RPC Security

```bash
# Bind RPC to localhost only
RPC_ADDR=127.0.0.1

# Restrict CORS domains
RPC_CORS_DOMAIN=http://localhost:3000

# Use nginx reverse proxy for external access
```

### 2. Firewall Configuration

```bash
# Allow P2P port
sudo ufw allow 30303/tcp
sudo ufw allow 30303/udp

# Dashboard port (if needed externally)
sudo ufw allow from YOUR_IP to any port 7070

# Deny all other incoming
sudo ufw default deny incoming
```

### 3. Docker Security

```yaml
# Security hardening in docker-compose.yml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
cap_add:
  - CHOWN
  - SETGID
  - SETUID
```

### 4. API Key Management

```bash
# Generate secure API key
openssl rand -hex 32

# Rotate keys regularly
# Store in environment variables, not in code
```

### 5. Secrets Management

```bash
# Use Docker Secrets (Swarm mode)
echo "my_secret" | docker secret create db_password -

# Or use HashiCorp Vault
vault kv put secret/xdc-node api_key=xxx
```

---

## Appendix

### Useful Commands

```bash
# XDC CLI
xdc status          # Show node status
xdc logs            # View logs
xdc restart         # Restart node
xdc backup create   # Create backup
xdc snapshot download  # Download snapshot

# Docker
docker ps           # List containers
docker logs xdc-node  # View node logs
docker-compose up -d  # Start all services

# System
journalctl -u docker  # Docker logs
htop                # System resources
iotop               # Disk I/O
```

### Links

- [XDC Network](https://xdc.network)
- [XDC Documentation](https://docs.xdc.community)
- [XDC Node Setup](https://github.com/AnilChinchawale/xdc-node-setup)
- [XDC SkyNet](https://github.com/AnilChinchawale/XDCNetOwn)
- [XDC Foundation](https://www.xdc.org)

---

*Documentation generated by XDC EVM Expert Agent*  
*Version 1.0.0 - February 27, 2026*
