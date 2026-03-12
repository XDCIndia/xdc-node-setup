# XDC Node Infrastructure - Architecture Overview

**Version:** 1.0  
**Date:** March 4, 2026  
**Author:** XDC EVM Expert Agent

---

## Table of Contents

1. [System Overview](#system-overview)
2. [SkyOne (Node Setup) Architecture](#skyone-node-setup-architecture)
3. [SkyNet (Dashboard) Architecture](#skynet-dashboard-architecture)
4. [Multi-Client Support](#multi-client-support)
5. [XDPoS 2.0 Consensus Integration](#xdpos-20-consensus-integration)
6. [Security Architecture](#security-architecture)
7. [Data Flow](#data-flow)
8. [Deployment Patterns](#deployment-patterns)

---

## System Overview

The XDC Node Infrastructure consists of two complementary systems:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     XDC Node Infrastructure                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────────────┐          ┌──────────────────────┐            │
│  │     SkyOne           │          │      SkyNet          │            │
│  │   (Node Setup)       │◄────────►│    (Dashboard)       │            │
│  │                      │  Heartbeat│                      │            │
│  │  • Node Deployment   │          │  • Fleet Monitoring  │            │
│  │  • Client Management │          │  • Alerting          │            │
│  │  • Self-Healing      │          │  • Analytics         │            │
│  │  • Local Dashboard   │          │  • Multi-Client View │            │
│  └──────────────────────┘          └──────────────────────┘            │
│           │                                   │                        │
│           └──────────┬────────────────────────┘                        │
│                      ▼                                                  │
│           ┌──────────────────────┐                                     │
│           │   XDC Network        │                                     │
│           │   (Mainnet/Testnet)  │                                     │
│           └──────────────────────┘                                     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. CLI Tool (`xdc`)
- **Purpose**: User interface for node management
- **Language**: Bash
- **Location**: `/usr/local/bin/xdc`
- **Key Features**:
  - One-command node deployment
  - Status monitoring
  - Log management
  - Security hardening

### 2. XDC Node
- **Purpose**: Core blockchain client
- **Supported Clients**:
  - Geth-XDC (stable/PR5)
  - Erigon-XDC
  - Nethermind-XDC
  - Reth-XDC
- **Ports**:
  - RPC: 8545 (Geth), 8547 (Erigon), 8556 (Nethermind), 7073 (Reth)
  - P2P: 30303 (Geth), 30304 (Erigon), 30306 (Nethermind), 40303 (Reth)

### 3. SkyOne Dashboard
- **Purpose**: Single-node monitoring interface
- **Technology**: Next.js 14 + TypeScript + Tailwind CSS
- **Port**: 7070
- **Features**:
  - Real-time metrics
  - Log viewer
  - Peer map
  - Alert timeline

### 4. SkyNet Agent
- **Purpose**: Fleet monitoring integration
- **Location**: `docker/skynet-agent.sh`
- **Frequency**: Every 30 seconds
- **Data**: Heartbeat + metrics push

## Data Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  XDC Node   │────►│  SkyOne UI  │────►│   User      │
│  (Geth)     │     │  (Port 7070)│     │  (Browser)  │
└──────┬──────┘     └─────────────┘     └─────────────┘
       │
       │ HTTP RPC
       ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ SkyNet Agent│────►│ XDC SkyNet  │────►│  Fleet      │
│ (Heartbeat) │     │  (API)      │     │ Dashboard   │
└─────────────┘     └─────────────┘     └─────────────┘
```

## Configuration Files

| File | Purpose | Location |
|------|---------|----------|
| `config.toml` | Node configuration | `mainnet/.xdc-node/config.toml` |
| `.env` | Environment variables | `mainnet/.xdc-node/.env` |
| `node.env` | Node metadata | `mainnet/.xdc-node/node.env` |
| `skynet.conf` | SkyNet integration | `mainnet/.xdc-node/skynet.conf` |
| `client.conf` | Client type | `mainnet/.xdc-node/client.conf` |

## Security Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Security Layers                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Layer 1: Host                                               │
│  ├── SSH hardening (port, root login)                        │
│  ├── UFW firewall                                            │
│  └── Fail2ban intrusion detection                            │
│                                                              │
│  Layer 2: Docker                                             │
│  ├── No new privileges                                       │
│  ├── Capability dropping                                     │
│  └── Read-only root filesystem                               │
│                                                              │
│  Layer 3: Application                                        │
│  ├── RPC bound to localhost                                  │
│  ├── JWT authentication (planned)                            │
│  └── TLS encryption (planned)                                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Multi-Client Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Multi-Client Setup                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  Geth-XDC    │  │ Erigon-XDC   │  │ Nethermind   │          │
│  │  Port 8545   │  │ Port 8547    │  │ Port 8556    │          │
│  │  P2P 30303   │  │ P2P 30304    │  │ P2P 30306    │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                 │                 │                   │
│         └─────────────────┼─────────────────┘                   │
│                           │                                     │
│                    ┌──────┴──────┐                              │
│                    │   XDC       │                              │
│                    │   Network   │                              │
│                    └─────────────┘                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Deployment Modes

### 1. Simple Mode (Default)
```bash
./setup.sh
# Minimal prompts, sensible defaults
```

### 2. Advanced Mode
```bash
./setup.sh --advanced
# Full configuration options
```

### 3. Automated Mode
```bash
NODE_TYPE=full NETWORK=mainnet ./setup.sh
# Environment variable driven
```

## Scaling Considerations

### Single Node
- Default setup
- Suitable for most users
- Local monitoring only

### Multi-Client
- Run multiple clients simultaneously
- Increased resource requirements
- Cross-client validation

### Fleet Deployment
- SkyNet integration
- Centralized monitoring
- Automated alerts

## Monitoring Stack

```
┌─────────────────────────────────────────────────────────────┐
│                    Monitoring Architecture                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Prometheus  │  │   Grafana    │  │   SkyOne     │      │
│  │  (Metrics)   │  │ (Dashboard)  │  │  (Built-in)  │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
│         │                 │                 │               │
│         └─────────────────┼─────────────────┘               │
│                           │                                 │
│                    ┌──────┴──────┐                          │
│                    │  XDC Node   │                          │
│                    │  (Geth)     │                          │
│                    └─────────────┘                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Backup and Recovery

### Automated Backups
- Location: `mainnet/.xdc-node/backups/`
- Frequency: Daily (configurable)
- Retention: 7 days

### Manual Backup
```bash
xdc backup create
```

### Recovery
```bash
xdc backup restore <backup-file>
```

## Troubleshooting Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Troubleshooting Flow                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Issue Detected                                              │
│       │                                                      │
│       ▼                                                      │
│  ┌──────────────┐                                           │
│  │  xdc health  │                                           │
│  └──────┬───────┘                                           │
│         │                                                    │
│    ┌────┴────┬────────┬────────┐                            │
│    ▼         ▼        ▼        ▼                            │
│ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐                        │
│ │Logs  │ │Peers │ │Sync  │ │System│                        │
│ │Check │ │Check │ │Check │ │Check │                        │
│ └──┬───┘ └──┬───┘ └──┬───┘ └──┬───┘                        │
│    └─────────┴────────┴────────┘                            │
│                   │                                          │
│                   ▼                                          │
│            ┌──────────┐                                     │
│            │  Report  │                                     │
│            │  Issue   │                                     │
│            └──────────┘                                     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

**Document Version:** 1.0.0  
**Last Updated:** February 27, 2026  
**Maintainer:** XDC EVM Expert Agent
