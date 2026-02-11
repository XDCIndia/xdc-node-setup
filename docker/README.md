# XDC Node Docker Setup - Production Deployment Guide

This repository contains a production-grade Docker Compose setup for running XDC (XinFin Digital Contract) blockchain nodes with comprehensive monitoring.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Security Hardening](#security-hardening)
- [Monitoring Access](#monitoring-access)
- [Backup Procedures](#backup-procedures)
- [Troubleshooting](#troubleshooting)

---

## Overview

This setup provides:

- **XDC Node** - The core blockchain client (xinfinorg/xdposchain:v2.6.8)
- **Prometheus** - Metrics collection and alerting
- **Grafana** - Visualization dashboards
- **Node Exporter** - System-level metrics
- **cAdvisor** - Container metrics
- **Alertmanager** - Alert routing (optional)
- **Dashboard** - Custom web UI for node monitoring (optional)

### Key Features

- ✅ Official Docker entrypoint flow (entry.sh → start.sh)
- ✅ Automatic XDC binary symlink creation
- ✅ Graceful shutdown handling (SIGTERM/SIGINT)
- ✅ Log rotation with size limits
- ✅ Comprehensive error handling (`set -euo pipefail`)
- ✅ Security hardening (no-new-privileges, cap_drop, read-only mounts)
- ✅ Resource limits (CPU/memory)
- ✅ Health checks for all services

---

## Prerequisites

### System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 4 cores | 8+ cores |
| RAM | 16 GB | 32+ GB |
| Storage (SSD) | 500 GB | 1+ TB |
| Network | 100 Mbps | 1 Gbps |

### Software Requirements

- Docker Engine 20.10+ or Docker Desktop 4.0+
- Docker Compose 2.0+
- Git (for cloning)

### Network Requirements

- **Port 30303/tcp** - P2P communication (must be publicly accessible)
- **Port 30303/udp** - P2P discovery (must be publicly accessible)
- **Port 8545/tcp** - RPC API (restrict to localhost/internal)
- **Port 8546/tcp** - WebSocket (restrict to localhost/internal)
- **Port 3000/tcp** - Grafana dashboard (restrict via firewall)
- **Port 3001/tcp** - Node dashboard (restrict via firewall)

---

## Quick Start

### 1. Clone and Navigate

```bash
cd /root/.openclaw/workspace/XDC-Node-Setup/docker
```

### 2. Configure Environment

#### For Mainnet:

```bash
cd mainnet

# Edit the environment configuration
nano .env

# IMPORTANT: Change the default password in .pwd
# Generate a strong password:
openssl rand -base64 32 > .pwd
```

#### For Testnet (Apothem):

```bash
cd testnet

# Edit the environment configuration
nano .env

# Change the default password
openssl rand -base64 32 > .pwd
```

### 3. Update Docker Compose for Your Network

Edit `docker-compose.yml` and update the volume mounts:

**For Mainnet:**
```yaml
volumes:
  - ./mainnet/xdcchain:/work/xdcchain
  - ./mainnet/genesis.json:/work/genesis.json:ro
  - ./mainnet/start-node.sh:/work/start.sh:ro
  - ./mainnet/bootnodes.list:/work/bootnodes.list:ro
  - ./mainnet/.pwd:/work/.pwd:ro
  - ./mainnet/.env:/work/.env:ro
```

**For Testnet:**
```yaml
volumes:
  - ./testnet/xdcchain:/work/xdcchain
  - ./testnet/genesis.json:/work/genesis.json:ro
  - ./testnet/start-node.sh:/work/start.sh:ro
  - ./testnet/bootnodes.list:/work/bootnodes.list:ro
  - ./testnet/.pwd:/work/.pwd:ro
  - ./testnet/.env:/work/.env:ro
```

### 4. Start the Node

```bash
# Start core services only (node + monitoring)
docker compose up -d

# Or start with all optional services
docker compose --profile alertmanager --profile dashboard up -d
```

### 5. Verify Node Status

```bash
# Check container status
docker compose ps

# View node logs
docker compose logs -f xdc-node

# Check if node is syncing
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
```

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NETWORK` | mainnet | Network type (mainnet/testnet) |
| `INSTANCE_NAME` | xdc-mainnet-node | Node name for stats server |
| `SYNC_MODE` | full | Sync mode (full/fast) |
| `GC_MODE` | archive | Garbage collection (archive/full) |
| `LOG_LEVEL` | 2 | Verbosity (0-5) |
| `ENABLE_RPC` | true | Enable RPC API |
| `RPC_ADDR` | 0.0.0.0 | RPC bind address |
| `RPC_PORT` | 8545 | RPC port |
| `RPC_API` | eth,net,web3,XDPoS | Enabled RPC APIs |
| `WS_PORT` | 8546 | WebSocket port |
| `METRICS` | true | Enable Prometheus metrics |
| `METRICS_PORT` | 6060 | Metrics endpoint port |

### Sync Modes

- **full** (recommended): Downloads and validates all blocks from genesis. Most secure but slower initial sync.
- **fast**: Downloads block headers and validates only recent blocks. Faster sync but less secure.

### GC Modes

- **archive** (recommended for masternodes): Keeps all historical state. Required for running a masternode.
- **full**: Prunes old state. Uses less disk space but cannot serve historical data.

---

## Security Hardening

### 1. Password Security

**⚠️ CRITICAL: Change the default password in `.pwd` before starting!**

```bash
# Generate a strong password
openssl rand -base64 32 > mainnet/.pwd

# Or use a password manager
```

### 2. Grafana Security

Edit `.env` and change default credentials:

```bash
GRAFANA_ADMIN_USER=your-secure-username
GRAFANA_ADMIN_PASSWORD=your-strong-password-here
GRAFANA_SECRET_KEY=$(openssl rand -hex 32)
```

### 3. Firewall Configuration

**Restrict external access to sensitive ports:**

```bash
# Allow P2P (required for node operation)
ufw allow 30303/tcp
ufw allow 30303/udp

# Restrict RPC to localhost only (already bound to 127.0.0.1 in compose)
# ufw deny 8545/tcp

# Restrict Grafana to specific IPs (example)
ufw allow from YOUR_IP to any port 3000

# Or use SSH tunneling instead of exposing Grafana
tunnel on 3000:localhost:3000 user@your-node-server
```

### 4. RPC Security

The RPC port (8545) is **not exposed externally** by default. Access it via:

- **SSH Tunnel**: `ssh -L 8545:localhost:8545 user@node-server`
- **Local access**: Run scripts/tools directly on the node server

### 5. Docker Security

The compose file includes security options:

```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
cap_add:
  - CHOWN
  - SETGID
  - SETUID
```

### 6. File Permissions

Ensure sensitive files have correct permissions:

```bash
chmod 600 mainnet/.pwd
chmod 600 mainnet/.env
chmod 644 mainnet/genesis.json
chmod 644 mainnet/bootnodes.list
chmod 755 mainnet/start-node.sh
```

---

## Monitoring Access

### Grafana Dashboard

Access Grafana at `http://your-node-ip:3000`

- **Default URL**: http://localhost:3000 (or your server IP)
- **Default login**: admin / changeme (change in .env!)

### Prometheus

Access Prometheus at `http://localhost:9090` (localhost only for security)

### Node Metrics

The node exposes metrics at:
- Prometheus metrics: `http://localhost:6060/debug/metrics/prometheus`
- pprof profiling: `http://localhost:6060/debug/pprof/`

### Custom Dashboard

If enabled, the custom dashboard is available at `http://your-node-ip:3001`

---

## Backup Procedures

### Critical Data to Backup

1. **Wallet/Keystore**: `./mainnet/xdcchain/keystore/`
2. **Password File**: `./mainnet/.pwd`
3. **Configuration**: `./mainnet/.env`
4. **Node Data**: `./mainnet/xdcchain/XDC/` (large, optional if wallet backed up)

### Automated Backup Script

```bash
#!/bin/bash
# backup-xdc.sh - Run daily via cron

BACKUP_DIR="/backups/xdc-node"
DATE=$(date +%Y%m%d-%H%M%S)
NODE_DIR="/root/.openclaw/workspace/XDC-Node-Setup/docker/mainnet"

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# Backup wallet and critical files
tar czf "${BACKUP_DIR}/xdc-wallet-${DATE}.tar.gz" \
    -C "${NODE_DIR}" \
    xdcchain/keystore/ \
    .pwd \
    .env

# Optional: Backup full chain data (very large)
# tar czf "${BACKUP_DIR}/xdc-chain-${DATE}.tar.gz" \
#     -C "${NODE_DIR}" \
#     xdcchain/

# Keep only last 7 backups
find "${BACKUP_DIR}" -name "xdc-wallet-*.tar.gz" -mtime +7 -delete

echo "Backup completed: ${BACKUP_DIR}/xdc-wallet-${DATE}.tar.gz"
```

### Restore from Backup

```bash
# Stop the node
docker compose down

# Restore wallet and config
tar xzf /backups/xdc-node/xdc-wallet-DATE.tar.gz -C ./mainnet/

# Start the node
docker compose up -d
```

---

## Troubleshooting

### Node Won't Start

```bash
# Check logs
docker compose logs xdc-node

# Verify configuration
docker compose config

# Check disk space
df -h

# Check file permissions
ls -la mainnet/
```

### Slow Sync

- Ensure port 30303 is open to the internet
- Check bootnodes are reachable: `telnet bootnode-ip 30303`
- Monitor peer count: `curl -X POST http://localhost:8545 -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'`

### High Memory Usage

- Reduce `LOG_LEVEL` in .env
- Adjust resource limits in docker-compose.yml
- Consider using `GC_MODE=full` instead of `archive`

### "XDC: command not found"

This error occurs if the entrypoint flow is bypassed. Ensure:
1. `entrypoint: ["/work/entry.sh"]` is set in docker-compose.yml
2. `NETWORK` environment variable is set
3. The start-node.sh has the safety fallback symlink creation

### Graceful Shutdown Issues

The script handles SIGTERM/SIGINT for graceful shutdown. If the node doesn't stop:

```bash
# Force stop
docker compose kill xdc-node

# Check for zombie processes
docker compose ps
```

---

## Support

- **XDC Documentation**: https://docs.xdc.network
- **XDC Stats (Mainnet)**: https://stats.xinfin.network
- **XDC Stats (Testnet)**: https://stats.apothem.network
- **GitHub Issues**: Report issues in this repository

---

## License

This setup is provided as-is for the XDC community. Ensure compliance with XDC Network terms of service.
