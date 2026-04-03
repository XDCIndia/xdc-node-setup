# XDC SkyOne Agent - Deployment Guide

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Deployment Options](#deployment-options)
4. [Configuration](#configuration)
5. [Monitoring](#monitoring)
6. [Troubleshooting](#troubleshooting)
7. [Advanced Topics](#advanced-topics)

---

## Prerequisites

### System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8+ GB |
| Disk | 100 GB SSD | 500 GB+ NVMe |
| Network | 10 Mbps | 100+ Mbps |

### Software Requirements

- Docker 20.10+ 
- Docker Compose 2.0+
- (Optional) SkyNet API Key from [skynet.xdcindia.com](https://skynet.xdcindia.com)

---

## Quick Start

### 1. One-Line Installer

```bash
curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/quick-start-skyone.sh | bash
```

### 2. Using Docker (Simplest)

```bash
# Monitor existing XDC node
docker run -d \
  --name xdc-skyone \
  -p 7070:7070 \
  -e XDC_RPC_URL=http://your-node:8545 \
  -e SKYNET_API_KEY=your-key \
  anilchinchawale/xdc-skyone:latest
```

Access dashboard at: **http://localhost:7070**

---

## Deployment Options

### Option A: External Node Monitoring

Monitor an existing XDC node without running a node yourself.

**Use Case:** You already have an XDC node running and want to add monitoring.

```yaml
version: "3.8"

services:
  skyone:
    image: anilchinchawale/xdc-skyone:latest
    ports:
      - "7070:7070"
    environment:
      - XDC_RPC_URL=http://existing-node:8545
      - SKYNET_API_KEY=${SKYNET_API_KEY}
      - SKYNET_NODE_NAME=my-monitor
```

**Start:**
```bash
docker-compose -f docker-compose.skyone.yml --profile external up -d
```

### Option B: Full Node + Dashboard

Run a complete XDC node with built-in dashboard.

**Use Case:** New node setup with monitoring included.

```yaml
version: "3.8"

services:
  skyone:
    image: anilchinchawale/xdc-skyone:latest
    ports:
      - "8545:8545"     # RPC
      - "30303:30303"   # P2P
      - "7070:7070"     # Dashboard
    volumes:
      - xdc-data:/data/xdcchain
    environment:
      - NETWORK=mainnet
      - CLIENT=stable
      - SYNC_MODE=snap
      - SKYNET_API_KEY=${SKYNET_API_KEY}

volumes:
  xdc-data:
```

**Start:**
```bash
docker-compose -f docker-compose.skyone.yml --profile full up -d
```

### Option C: Validator Node

Run a validator node with full monitoring.

**Use Case:** Masternode/validator operation.

```yaml
version: "3.8"

services:
  skyone:
    image: anilchinchawale/xdc-skyone:latest
    ports:
      - "30303:30303"   # P2P only (RPC internal)
      - "7070:7070"     # Dashboard
    volumes:
      - validator-data:/data/xdcchain
      - ./keystore:/secrets:ro
    environment:
      - NODE_TYPE=masternode
      - NETWORK=mainnet
      - VALIDATOR_ADDRESS=0x...
      - SKYNET_ROLE=validator
```

---

## Configuration

### Environment Variables Reference

#### Core Settings

| Variable | Default | Options | Description |
|----------|---------|---------|-------------|
| `NODE_TYPE` | `full` | full, archive, rpc, masternode | Type of node |
| `NETWORK` | `mainnet` | mainnet, testnet, devnet, apothem | XDC network |
| `CLIENT` | `stable` | stable, geth-pr5, erigon, nethermind | Client implementation |
| `SYNC_MODE` | `snap` | snap, full, fast | Sync mode |

#### Network Ports

| Variable | Default | Description |
|----------|---------|-------------|
| `RPC_PORT` | `8545` | JSON-RPC HTTP port |
| `WS_PORT` | `8546` | WebSocket port |
| `P2P_PORT` | `30303` | P2P networking port |
| `DASHBOARD_PORT` | `7070` | Dashboard web UI |
| `METRICS_PORT` | `6060` | Prometheus metrics |

#### SkyNet Configuration

| Variable | Required | Description |
|----------|----------|-------------|
| `SKYNET_API_KEY` | Yes* | API key for SkyNet |
| `SKYNET_NODE_NAME` | No | Display name in SkyNet |
| `SKYNET_ROLE` | No | fullnode, validator, rpc |

*Required for SkyNet features. Get key at [skynet.xdcindia.com](https://skynet.xdcindia.com)

### Configuration File

Create `skynet.conf`:

```bash
SKYNET_API_URL=https://skynet.xdcindia.com/api
SKYNET_API_KEY=xdc_your_api_key_here
SKYNET_NODE_NAME=my-xdc-node
SKYNET_ROLE=fullnode
```

Mount in container:
```yaml
volumes:
  - ./skynet.conf:/etc/xdc-node/skynet.conf:ro
```

---

## Monitoring

### Dashboard

Access at `http://localhost:7070`

**Key Metrics:**
- Block height and sync progress
- Peer count and network health
- CPU, memory, disk usage
- Chain consensus status

### Prometheus Metrics

Endpoint: `http://localhost:6060/metrics`

**Available Metrics:**
```
xdc_block_height         - Current block height
xdc_peer_count           - Connected peers
xdc_sync_status          - Sync status (0/1)
xdc_chain_id             - Chain ID
xdc_uptime_seconds       - Node uptime
```

### SkyNet Integration

View your node at: [skynet.xdcindia.com](https://skynet.xdcindia.com)

**Features:**
- Fleet-wide node visibility
- Historical performance data
- Alerts for offline nodes
- Network health overview

---

## Troubleshooting

### Dashboard Not Loading

```bash
# Check container status
docker ps | grep xdc-skyone

# View logs
docker logs xdc-skyone

# Check nginx configuration
docker exec xdc-skyone nginx -t
```

### XDC Node Not Syncing

```bash
# Check sync status
docker exec xdc-skyone curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

# View node logs
docker logs xdc-skyone | grep -i "xdc\|geth"
```

### SkyNet Registration Failed

```bash
# Verify API key
docker exec xdc-skyone cat /etc/xdc-node/skynet.conf

# Test SkyNet connectivity
docker exec xdc-skyone curl -s https://skynet.xdcindia.com/api/health

# Check SkyNet agent logs
docker logs xdc-skyone | grep -i skynet
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Port 7070 already in use | Change `DASHBOARD_PORT` env var |
| Permission denied | Run with `sudo` or add user to docker group |
| Out of disk space | Mount larger volume for `/data/xdcchain` |
| Slow sync | Ensure port 30303 is open in firewall |

---

## Advanced Topics

### Reverse Proxy Setup

**Nginx:**
```nginx
server {
    listen 80;
    server_name xdc-dashboard.yourdomain.com;
    
    location / {
        proxy_pass http://localhost:7070;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
    }
}
```

### SSL/TLS with Let's Encrypt

```yaml
version: "3.8"

services:
  skyone:
    image: anilchinchawale/xdc-skyone:latest
    ports:
      - "7070:7070"
    environment:
      - DASHBOARD_PORT=7070
    
  https-portal:
    image: steveltn/https-portal:1
    ports:
      - "80:80"
      - "443:443"
    environment:
      DOMAINS: 'xdc.yourdomain.com -> http://skyone:7070'
      STAGE: 'production'
```

### Backup Strategy

```bash
# Backup data volume
docker run --rm -v xdc-data:/data -v $(pwd):/backup alpine \
  tar czf /backup/xdc-backup-$(date +%Y%m%d).tar.gz -C /data .

# Backup SkyNet config
cp skynet.conf skynet.conf.backup
```

### Upgrade Process

```bash
# Pull latest image
docker pull anilchinchawale/xdc-skyone:latest

# Stop existing container
docker-compose down

# Start with new image
docker-compose up -d
```

---

## Support

- 📖 [Full Documentation](SKYONE_AGENT_DOCUMENTATION.md)
- 💬 [Discord](https://discord.gg/xdc)
- 🐛 [GitHub Issues](https://github.com/AnilChinchawale/xdc-node-setup/issues)
- 🌐 [SkyNet Platform](https://skynet.xdcindia.com)
