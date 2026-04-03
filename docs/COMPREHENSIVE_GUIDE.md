# XDC Node Setup - Comprehensive Documentation

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Quick Start](#quick-start)
3. [Client Support](#client-support)
4. [OS Compatibility](#os-compatibility)
5. [Configuration Management](#configuration-management)
6. [Self-Healing](#self-healing)
7. [Self-Reporting](#self-reporting)
8. [Update Management](#update-management)
9. [Security Hardening](#security-hardening)
10. [Troubleshooting](#troubleshooting)
11. [API Reference](#api-reference)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        XDC Node Setup (SkyOne)                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐              │
│  │   XDC Node   │◄──►│  XDC Agent   │◄──►│   SkyNet     │              │
│  │   (Docker)   │    │  (Dashboard) │    │  (Cloud)     │              │
│  └──────────────┘    └──────────────┘    └──────────────┘              │
│         │                   │                                           │
│         ▼                   ▼                                           │
│  ┌──────────────┐    ┌──────────────┐                                  │
│  │  Prometheus  │    │   Grafana    │                                  │
│  │  (Metrics)   │    │ (Dashboards) │                                  │
│  └──────────────┘    └──────────────┘                                  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Components

| Component | Purpose | Port |
|-----------|---------|------|
| XDC Node | Blockchain client | 8545 (RPC), 30303 (P2P) |
| XDC Agent | Dashboard + SkyNet agent | 7070 |
| Prometheus | Metrics collection | 9090 (internal) |
| Grafana | Visualization | 3000 (internal) |

---

## Quick Start

### One-Line Install

```bash
curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/install.sh | sudo bash
```

### Manual Installation

```bash
# 1. Clone repository
git clone https://github.com/AnilChinchawale/xdc-node-setup.git
cd xdc-node-setup

# 2. Run installer
sudo ./install.sh

# 3. Start node
xdc start

# 4. Check status
xdc status
```

### Access Dashboard

```
http://localhost:7070
```

---

## Client Support

### Supported Clients

| Client | Version | Status | RPC Port | P2P Port | Disk Usage |
|--------|---------|--------|----------|----------|------------|
| **Geth-XDC** | v2.6.8 | Production | 8545 | 30303 | ~500GB |
| **Geth-PR5** | Latest | Testing | 8545 | 30303 | ~500GB |
| **Erigon-XDC** | Latest | Experimental | 8547 | 30304 | ~400GB |
| **Nethermind-XDC** | Latest | Beta | 8558 | 30306 | ~350GB |
| **Reth-XDC** | Latest | Alpha | 7073 | 40303 | ~300GB |

### Client Selection

```bash
# Start with specific client
xdc start --client stable      # XDC Stable (v2.6.8)
xdc start --client geth-pr5    # XDC Geth PR5
xdc start --client erigon      # Erigon-XDC
xdc start --client nethermind  # Nethermind-XDC
xdc start --client reth        # Reth-XDC
```

### Multi-Client Setup

```bash
# Run multiple clients on same machine (different ports)
docker-compose -f docker/docker-compose.multiclient.yml up -d
```

---

## OS Compatibility

### Supported Platforms

| OS | Architecture | Status | Notes |
|----|--------------|--------|-------|
| Ubuntu 22.04+ | x86_64 | ✅ Fully Supported | Primary platform |
| Ubuntu 20.04+ | x86_64 | ✅ Supported | |
| Debian 11+ | x86_64 | ✅ Supported | |
| CentOS/RHEL 8+ | x86_64 | ⚠️ Experimental | |
| macOS 13+ | x86_64 | ✅ Supported | Rosetta for some clients |
| macOS 13+ | ARM64 | ⚠️ Limited | Nethermind native, others via Rosetta |
| Windows | x86_64 | ⚠️ WSL2 Only | No native support |

### Platform Detection

```bash
# Check your platform
xdc doctor --platform
```

---

## Configuration Management

### Network Configuration

```bash
# Mainnet (default)
xdc start --network mainnet

# Apothem Testnet
xdc start --network apothem

# Devnet
xdc start --network devnet
```

### RPC Configuration

```bash
# Environment variables
export RPC_PORT=8545
export RPC_BIND=127.0.0.1  # Secure: localhost only
export WS_PORT=8546
export P2P_PORT=30303

# Start with custom ports
xdc start
```

### Configuration Files

| File | Purpose | Location |
|------|---------|----------|
| `.env` | Environment variables | `~/.xdc-node/.env` |
| `config.toml` | Client configuration | `~/.xdc-node/config.toml` |
| `skynet.conf` | SkyNet agent config | `~/.xdc-node/skynet.conf` |
| `self-heal.conf` | Self-healing config | `~/.xdc-node/self-heal.conf` |

### Sample Configuration

```toml
# ~/.xdc-node/config.toml
[Node]
DataDir = "/work/xdcchain"
IPCPath = "XDC.ipc"
HTTPHost = "127.0.0.1"  # Secure: localhost only
HTTPPort = 8545
HTTPVirtualHosts = ["localhost"]
HTTPCors = ["http://localhost:7070"]  # Restrict CORS
WSHost = "127.0.0.1"
WSPort = 8546

[Node.P2P]
ListenAddr = ":30303"
MaxPeers = 50

[XDPoS]
Enable = true
Epoch = 900
Gap = 450
```

---

## Self-Healing

### Overview

Self-healing automatically recovers from common node issues:
- Sync stalls
- Peer drops
- Memory pressure
- Container crashes

### Configuration

```yaml
# ~/.xdc-node/self-heal.conf
self_healing:
  enabled: true
  max_auto_restarts_per_hour: 3
  
  sync_stall:
    detection_threshold_minutes: 10
    auto_restart: true
    auto_snapshot_sync: true
    escalation_after_minutes: 30
    
  peer_drop:
    critical_threshold: 5
    auto_restart: true
    
  consensus_fork:
    auto_action: false  # Never auto-restart on fork
    preserve_logs: true
    immediate_alert: true
```

### Recovery Actions

| Issue | Severity | Automatic Action | Escalation |
|-------|----------|------------------|------------|
| Sync stall < 30 min | warning | Increase peer discovery | Alert only |
| Sync stall > 30 min | high | Restart with snapshot sync | Create issue |
| Peer count = 0 | critical | Restart P2P, check firewall | Page operator |
| Bad block detected | critical | Stop node, alert operator | Do not auto-restart |
| Consensus fork | critical | Stop node, preserve state | Immediate alert |

---

## Self-Reporting

### SkyNet Integration

```bash
# Enable SkyNet reporting
export SKYNET_ENABLED=true
export SKYNET_URL=https://skynet.xdcindia.com
export SKYNET_API_KEY=your-api-key

xdc start
```

### Heartbeat Configuration

```yaml
# ~/.xdc-node/skynet.conf
skynet:
  enabled: true
  url: https://skynet.xdcindia.com
  api_key: ${SKYNET_API_KEY}
  heartbeat_interval_seconds: 30
  
  metrics:
    send_system_metrics: true
    send_consensus_metrics: true
    send_peer_metrics: true
    
  alerts:
    sync_stall_threshold_minutes: 10
    peer_drop_threshold: 5
    disk_warning_percent: 80
    disk_critical_percent: 90
```

### Reported Metrics

- Block height and sync progress
- Peer count and geographic distribution
- System resources (CPU, memory, disk)
- Client version and type
- Consensus participation (masternodes)

---

## Update Management

### Automatic Updates

```bash
# Check for updates
xdc update --check

# Update to latest version
xdc update

# Update with automatic restart
xdc update --auto-restart
```

### Version Pinning

```bash
# Pin to specific version
export XDC_VERSION=2.6.8
xdc start

# Pin in config
# ~/.xdc-node/.env
XDC_VERSION=2.6.8
```

### Rolling Updates (Masternodes)

```bash
# Perform rolling update across fleet
xdc fleet update --rolling --batch-size 1 --wait-time 300
```

### Rollback

```bash
# Rollback to previous version
xdc rollback

# Rollback to specific version
xdc rollback --version 2.6.7
```

---

## Security Hardening

### Default Security Features

- ✅ SSH key authentication only
- ✅ UFW firewall with restrictive rules
- ✅ fail2ban intrusion prevention
- ✅ Docker security hardening
- ✅ Automatic security updates

### Security Checklist

```bash
# Run security audit
xdc security audit

# Apply hardening
xdc security harden
```

### RPC Security

```bash
# Secure RPC configuration (default)
export RPC_BIND=127.0.0.1
export RPC_CORS=http://localhost:7070
xdc start

# With reverse proxy (for external access)
export RPC_BIND=127.0.0.1
xdc start
# Configure nginx reverse proxy separately
```

### Docker Security

```yaml
# docker-compose.yml security options
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

## Troubleshooting

### Common Issues

#### Node Not Syncing

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

#### Port Conflicts

```bash
# Check port usage
sudo lsof -i :8545
sudo lsof -i :30303

# Change ports
export RPC_PORT=8546
export P2P_PORT=30304
xdc start
```

#### Disk Space Issues

```bash
# Check disk usage
xdc doctor --disk

# Prune old data
xdc prune --mode=full

# Compact database
xdc compact
```

### Diagnostic Commands

```bash
# Full diagnostic
xdc doctor

# Check specific areas
xdc doctor --network
xdc doctor --disk
xdc doctor --sync
xdc doctor --peers
xdc doctor --consensus
```

---

## API Reference

### CLI Commands

| Command | Description | Example |
|---------|-------------|---------|
| `xdc start` | Start node | `xdc start --client stable` |
| `xdc stop` | Stop node | `xdc stop` |
| `xdc restart` | Restart node | `xdc restart` |
| `xdc status` | Check status | `xdc status` |
| `xdc logs` | View logs | `xdc logs --follow` |
| `xdc update` | Update node | `xdc update` |
| `xdc backup` | Backup data | `xdc backup` |
| `xdc restore` | Restore from backup | `xdc restore <file>` |
| `xdc doctor` | Run diagnostics | `xdc doctor` |

### RPC API

```bash
# Get block number
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Get peer count
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'

# Get sync status
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
```

### Dashboard API

```bash
# Health check
curl http://localhost:7070/api/health

# Metrics
curl http://localhost:7070/api/metrics

# Peers
curl http://localhost:7070/api/peers
```

---

## XDPoS 2.0 Consensus

### Epoch Structure

- **Epoch Length**: 900 blocks
- **Gap Blocks**: 450 blocks before epoch end (blocks 450-899)
- **Masternodes**: 108

### Consensus Flow

```
1. Block Proposal (Leader)
2. Vote Collection (Masternodes)
3. QC Formation (2/3 + 1 votes)
4. Block Finalization
5. Next Round
```

### Gap Block Handling

During gap blocks (every 900th block):
- No block production
- Vote collection continues
- Epoch transition preparation

---

## Support

- **Documentation**: https://docs.xdc.network
- **Discord**: https://discord.gg/xdc
- **GitHub Issues**: https://github.com/AnilChinchawale/xdc-node-setup/issues

---

## License

MIT License - see LICENSE file for details.
