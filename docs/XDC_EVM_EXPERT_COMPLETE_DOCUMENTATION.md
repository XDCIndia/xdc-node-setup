# XDC Node Ecosystem - Complete E2E Documentation

**Version**: 2.0.0  
**Date**: March 4, 2026  
**Repositories**:
- [xdc-node-setup (SkyOne)](https://github.com/AnilChinchawale/xdc-node-setup) - Node deployment & management
- [XDCNetOwn (SkyNet)](https://github.com/AnilChinchawale/XDCNetOwn) - Centralized monitoring dashboard

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Quick Start Guide](#2-quick-start-guide)
3. [XDPoS 2.0 Consensus Monitoring](#3-xdpos-20-consensus-monitoring)
4. [Multi-Client Deployment](#4-multi-client-deployment)
5. [Security Best Practices](#5-security-best-practices)
6. [API Reference](#6-api-reference)
7. [Troubleshooting](#7-troubleshooting)
8. [Performance Tuning](#8-performance-tuning)

---

## 1. Architecture Overview

### 1.1 System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           XDC Node Ecosystem                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        XDC Network (Mainnet)                         │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐   │   │
│  │  │ Masternode│  │ Masternode│  │ Masternode│  │  Full   │  │  Full   │   │   │
│  │  │   (MN1) │  │   (MN2) │  │   (MN3) │  │  Node   │  │  Node   │   │   │
│  │  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘   │   │
│  │       └─────────────┴─────────────┴─────────────┴─────────────┘      │   │
│  │                              P2P Network                              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    ▲                                        │
│                                    │                                        │
│  ┌─────────────────────────────────┼─────────────────────────────────────┐ │
│  │         SkyOne (Node Setup)      │                                    │ │
│  │  ┌───────────────────────────────┼─────────────────────────────────┐ │ │
│  │  │      Docker Compose Stack     │                                 │ │ │
│  │  │  ┌─────────────┐  ┌───────────┴──────────┐  ┌───────────────┐  │ │ │
│  │  │  │  XDC Node   │  │   SkyOne Dashboard   │  │  SkyNet Agent │  │ │ │
│  │  │  │  (Geth/     │  │     (Port 7070)      │  │  (Heartbeat)  │  │ │ │
│  │  │  │  Erigon/    │  │                      │  │               │  │ │ │
│  │  │  │  Nethermind/│  │  ┌──────────────┐    │  │               │  │ │ │
│  │  │  │  Reth)      │  │  │ Prometheus   │    │  │               │  │ │ │
│  │  │  └──────┬──────┘  │  │ Grafana      │    │  └───────┬───────┘  │ │ │
│  │  │         │         │  └──────────────┘    │          │          │ │ │
│  │  │         │         └──────────────────────┘          │          │ │ │
│  │  └─────────┼───────────────────────────────────────────┼──────────┘ │ │
│  │            │                                           │            │ │
│  │            ▼                                           ▼            │ │
│  │  ┌─────────────────────────────────────────────────────────────┐   │ │
│  │  │                    Data Volumes                              │   │ │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │   │ │
│  │  │  │  XDC Chain   │  │   Metrics    │  │   Config/Logs    │  │   │ │
│  │  │  │   Data       │  │    DB        │  │                  │  │   │ │
│  │  │  └──────────────┘  └──────────────┘  └──────────────────┘  │   │ │
│  │  └─────────────────────────────────────────────────────────────┘   │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                    │                                      │
│                                    │ HTTP/TLS                              │
│                                    ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │                      SkyNet (Dashboard)                              │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │ │
│  │  │   Next.js    │  │  PostgreSQL  │  │   Alert Manager          │  │ │
│  │  │  Dashboard   │  │   Database   │  │  (Telegram/Email/Slack)  │  │ │
│  │  └──────────────┘  └──────────────┘  └──────────────────────────┘  │ │
│  │                                                                     │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │ │
│  │  │  Divergence  │  │  Masternode  │  │    ML Anomaly Detector   │  │ │
│  │  │  Detector    │  │   Monitor    │  │                          │  │ │
│  │  └──────────────┘  └──────────────┘  └──────────────────────────┘  │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Component Interactions

| Component | Protocol | Port | Purpose |
|-----------|----------|------|---------|
| XDC Node (Geth) | HTTP RPC | 8545 | Blockchain queries |
| XDC Node (Geth) | WebSocket | 8546 | Real-time events |
| XDC Node (Geth) | P2P | 30303 | Peer discovery |
| Erigon | HTTP RPC | 8547 | Alternative client |
| Erigon | P2P | 30304/30311 | Dual-sentry P2P |
| Nethermind | HTTP RPC | 8558 | .NET client |
| Nethermind | P2P | 30306 | P2P networking |
| Reth | HTTP RPC | 7073 | Rust client |
| Reth | P2P | 40303 | P2P networking |
| SkyOne Dashboard | HTTP | 7070 | Node monitoring |
| Prometheus | HTTP | 9090 | Metrics collection |
| Grafana | HTTP | 3000 | Visualization |

### 1.3 Data Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   XDC Node  │────▶│  SkyOne     │────▶│  SkyNet     │────▶│  Dashboard  │
│  (Metrics)  │     │  Agent      │     │  API        │     │  (UI)       │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                           │                   │
                           ▼                   ▼
                    ┌─────────────┐     ┌─────────────┐
                    │  Local      │     │ PostgreSQL  │
                    │  Logs       │     │  Database   │
                    └─────────────┘     └─────────────┘
```

---

## 2. Quick Start Guide

### 2.1 One-Line Installation

```bash
# Install XDC node with default settings (Geth stable, mainnet)
curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/setup.sh | sudo bash

# Install with specific options
sudo bash -c 'curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/setup.sh | bash -s -- --advanced --email admin@example.com --telegram @admin'
```

### 2.2 Post-Installation

```bash
# Check node status
xdc status

# View logs
xdc logs --follow

# Check sync progress
xdc sync

# Access dashboard
open http://localhost:7070
```

### 2.3 Multi-Client Setup

```bash
# Start with Erigon client
xdc start --client erigon

# Start with Nethermind
xdc start --client nethermind

# Start all clients simultaneously
xdc start --client all
```

---

## 3. XDPoS 2.0 Consensus Monitoring

### 3.1 Consensus Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Block Time | 2 seconds | Target time between blocks |
| Epoch Length | 900 blocks | ~30 minutes per epoch |
| Gap Period | 450 blocks | Last half of epoch for voting |
| Quorum | 2/3 + 1 | Required votes for QC (50 of 72) |
| Masternode Count | 72 | Active validators |

### 3.2 Epoch Structure

```
Epoch N (900 blocks)
├─ Blocks 0-449: Normal block production
├─ Blocks 450-899: Gap period (voting only)
│  └─ Vote collection for next epoch masternodes
└─ Block 900: Epoch transition

   0        449    450        899    900
   |─────────|──────|──────────|──────|
   │Production│      │   Gap    │      │
   │  Period  │      │  Period  │      │
   └──────────┘      └──────────┘      │
                                       ▼
                               Epoch N+1 Begins
```

### 3.3 Monitoring Commands

```bash
# Get current epoch info
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "XDPoS_getMasternodesByNumber",
    "params": ["latest"],
    "id": 1
  }'

# Get consensus status
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "XDPoS_getV1ConsensusStatus",
    "params": [],
    "id": 1
  }'

# Check if in gap period
EPOCH=$(( $(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | jq -r '.result' | xargs printf '%d\n' 16) / 900 ))
BLOCK_IN_EPOCH=$(( $(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | jq -r '.result' | xargs printf '%d\n' 16) % 900 ))

if [ $BLOCK_IN_EPOCH -ge 450 ]; then
  echo "Currently in gap period (block $BLOCK_IN_EPOCH of epoch $EPOCH)"
else
  echo "Currently in production period (block $BLOCK_IN_EPOCH of epoch $EPOCH)"
fi
```

### 3.4 Consensus Health Metrics

| Metric | Target | Warning | Critical |
|--------|--------|---------|----------|
| QC Formation Time | < 1s | > 2s | > 5s |
| Vote Participation | > 95% | < 90% | < 80% |
| Timeout Rate | < 1% | > 5% | > 10% |
| Block Time | 2s | > 3s | > 5s |

---

## 4. Multi-Client Deployment

### 4.1 Client Comparison

| Feature | Geth-XDC | Erigon-XDC | Nethermind-XDC | Reth-XDC |
|---------|----------|------------|----------------|----------|
| **Status** | Production | Experimental | Beta | Alpha |
| **RPC Port** | 8545 | 8547 | 8558 | 7073 |
| **P2P Port** | 30303 | 30304/30311 | 30306 | 40303 |
| **Memory** | 4GB+ | 8GB+ | 12GB+ | 16GB+ |
| **Disk** | ~500GB | ~400GB | ~350GB | ~300GB |
| **Sync Speed** | Standard | Fast | Very Fast | Very Fast |

### 4.2 Running Multiple Clients

```bash
# Start all clients on same machine
xdc start --client all

# Check all client statuses
xdc status --all

# View logs for specific client
xdc logs --client erigon
xdc logs --client nethermind

# Stop all clients
xdc stop --all
```

### 4.3 Port Configuration

```yaml
# docker/docker-compose.multiclient.yml
services:
  xdc-geth:
    ports:
      - "8545:8545"    # RPC
      - "30303:30303"  # P2P
  
  xdc-erigon:
    ports:
      - "8547:8547"    # RPC
      - "30304:30304"  # P2P (eth/63 - XDC compatible)
      - "30311:30311"  # P2P (eth/68 - not XDC compatible)
  
  xdc-nethermind:
    ports:
      - "8558:8558"    # RPC
      - "30306:30306"  # P2P
  
  xdc-reth:
    ports:
      - "7073:7073"    # RPC
      - "40303:40303"  # P2P
```

---

## 5. Security Best Practices

### 5.1 RPC Security

```bash
# Bind RPC to localhost only (default in v2.2.0+)
RPC_ADDR=127.0.0.1

# Restrict CORS to specific origins
RPC_CORS_DOMAIN=http://localhost:7070,https://skynet.xdcindia.com

# Disable RPC if not needed
ENABLE_RPC=false
```

### 5.2 Firewall Configuration

```bash
# UFW rules for XDC node
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH (change from default 22)
sudo ufw allow 2222/tcp comment 'SSH custom port'

# XDC P2P
sudo ufw allow 30303/tcp comment 'XDC P2P'
sudo ufw allow 30303/udp comment 'XDC P2P UDP'

# Additional clients (if running multi-client)
sudo ufw allow 30304/tcp comment 'Erigon P2P'
sudo ufw allow 30306/tcp comment 'Nethermind P2P'
sudo ufw allow 40303/tcp comment 'Reth P2P'

# Enable firewall
sudo ufw enable
```

### 5.3 Container Security

```yaml
# Security hardening in docker-compose.yml
services:
  xdc-node:
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETGID
      - SETUID
    read_only: true
    tmpfs:
      - /tmp:nosuid,size=100m
```

---

## 6. API Reference

### 6.1 SkyOne Node API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Node health status |
| `/api/metrics` | GET | Prometheus metrics |
| `/api/peers` | GET | Connected peers |

### 6.2 SkyNet Fleet API

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/api/v1/nodes/register` | POST | Bearer | Register new node |
| `/api/v1/nodes/heartbeat` | POST | Bearer | Send metrics |
| `/api/v1/fleet/status` | GET | Bearer | Fleet overview |
| `/api/v1/masternodes` | GET | Bearer | Masternode list |
| `/api/v1/consensus/status` | GET | Bearer | Consensus metrics |

### 6.3 XDPoS RPC Methods

```bash
# Get masternodes for epoch
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "XDPoS_getMasternodesByNumber",
    "params": ["latest"],
    "id": 1
  }'

# Get consensus status
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "XDPoS_getV1ConsensusStatus",
    "params": [],
    "id": 1
  }'

# Get reward for block
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "XDPoS_getRewardByHash",
    "params": ["0x..."],
    "id": 1
  }'
```

---

## 7. Troubleshooting

### 7.1 Common Issues

#### Node Won't Start

```bash
# Check Docker is running
sudo systemctl status docker

# Check port conflicts
sudo ss -tlnp | grep -E '8545|30303|7070'

# View logs
docker logs xdc-node

# Reset and restart
xdc stop
rm -rf mainnet/.xdc-node/geth/nodes
xdc start
```

#### Sync Stalled

```bash
# Check peer count
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'

# Add bootstrap peers
xdc peers add --enode "enode://..."

# Download snapshot for fast sync
xdc snapshot download --network mainnet
xdc snapshot apply
```

#### High Memory Usage

```bash
# Reduce cache size
xdc config set cache 2048
xdc restart

# Enable pruning
xdc config set prune_mode full
xdc restart

# Monitor memory
xdc health --full
```

### 7.2 Debug Commands

```bash
# Attach to XDC console
xdc attach

# Get node info
xdc info

# Check system resources
xdc health

# Security audit
xdc security
```

---

## 8. Performance Tuning

### 8.1 Client-Specific Tuning

#### Geth-XDC

```toml
# configs/config.toml
[Eth]
Cache = 4096          # 4GB cache
GCMode = "full"       # Garbage collection mode

[Node]
HTTPPort = 8545
WSPort = 8546
Port = 30303
MaxPeers = 50
```

#### Erigon-XDC

```bash
# Environment variables
ERIGON_MEMORY=12G     # Allocate 12GB RAM
ERIGON_CPUS=4         # Limit to 4 cores
```

#### Nethermind-XDC

```json
// nethermind.json
{
  "Init": {
    "MemoryHint": 12000000000
  },
  "Network": {
    "MaxActivePeers": 50
  }
}
```

### 8.2 System Optimization

```bash
# Increase file descriptors
ulimit -n 65535

# Kernel tuning
sudo sysctl -w net.core.rmem_max=134217728
sudo sysctl -w net.core.wmem_max=134217728
sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728"
sudo sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728"

# SSD optimization
sudo blockdev --setra 16384 /dev/nvme0n1
```

---

## Appendix A: XDPoS 2.0 Consensus Specification

### A.1 Consensus States

```
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│  IDLE   │───▶│ PROPOSE │───▶│  VOTE   │───▶│ COMMIT  │
└─────────┘    └─────────┘    └─────────┘    └─────────┘
     ▲                                            │
     └────────────────────────────────────────────┘
                    (Next Round)
```

### A.2 Message Types

| Type | Purpose | Size |
|------|---------|------|
| `Propose` | Block proposal | ~2KB |
| `Vote` | Vote for block | ~100B |
| `Timeout` | Round timeout | ~50B |
| `Sync` | Block sync | Variable |

### A.3 Security Properties

- **Safety**: No two conflicting blocks can be committed
- **Liveness**: Network continues to make progress despite faults
- **Accountability**: Misbehaving validators can be identified

---

## Appendix B: Client-Specific Notes

### B.1 Erigon-XDC

**Dual-Sentry Architecture:**
- Port 30304 (eth/63): Compatible with XDC geth nodes
- Port 30311 (eth/68): Ethereum P2P (NOT XDC compatible)

**Important:** Always use port 30304 when connecting to XDC peers.

### B.2 Nethermind-XDC

**eth/100 Protocol:**
Full compatibility with XDC Network using custom protocol.

**Fast Sync:**
Optimized for rapid initial synchronization.

### B.3 Reth-XDC

**Alpha Status:**
- Requires `--debug.tip` for sync
- Higher memory requirements (16GB+)
- Fastest sync speed once configured

---

## Appendix C: Monitoring Checklist

### Daily Checks

- [ ] Node is synced (block height matches network)
- [ ] Peer count > 10
- [ ] No critical alerts in dashboard
- [ ] Disk usage < 80%

### Weekly Checks

- [ ] Review consensus participation rate
- [ ] Check QC formation times
- [ ] Verify backup integrity
- [ ] Review security logs

### Monthly Checks

- [ ] Update to latest client version
- [ ] Review and rotate credentials
- [ ] Analyze performance trends
- [ ] Test disaster recovery

---

**Document Version**: 2.0.0  
**Last Updated**: March 4, 2026  
**Maintained by**: XDC EVM Expert Agent
