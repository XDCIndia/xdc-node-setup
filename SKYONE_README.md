# XDC SkyOne Agent 🚀

**Unified XDC Node Management Solution**

[![Docker](https://img.shields.io/badge/docker-ready-blue.svg)](https://hub.docker.com/r/anilchinchawale/xdc-skyone)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-3.0.0-orange.svg)]()

## What is SkyOne Agent?

**XDC SkyOne Agent** is an all-in-one container that combines:

- 🖥️ **SkyOne Dashboard** - Beautiful real-time web UI for monitoring
- 📡 **SkyNet Agent** - Automatic node registration and heartbeat monitoring
- ⛓️ **XDC Node** - Optional built-in blockchain node (Geth/Erigon/Nethermind)
- 📊 **Prometheus Metrics** - Export metrics for advanced monitoring

## Quick Start

### Option 1: Monitor External XDC Node (Recommended for Existing Nodes)

```bash
# Download quick start script
curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/quick-start-skyone.sh -o quick-start-skyone.sh
chmod +x quick-start-skyone.sh

# Run interactive setup
./quick-start-skyone.sh external
```

Or manually with Docker:

```bash
docker run -d \
  --name xdc-skyone \
  -p 7070:7070 \
  -e XDC_RPC_URL=http://your-xdc-node:8545 \
  -e SKYNET_API_KEY=your-api-key \
  anilchinchawale/xdc-skyone:latest
```

Access dashboard at: **http://localhost:7070**

### Option 2: Full XDC Node + Dashboard

```bash
./quick-start-skyone.sh full
```

Or with Docker Compose:

```bash
cd docker
docker-compose -f docker-compose.skyone.yml --profile full up -d
```

### Option 3: Docker Compose (All-in-One)

```yaml
version: "3.8"

services:
  xdc-skyone:
    image: anilchinchawale/xdc-skyone:latest
    container_name: xdc-skyone
    restart: unless-stopped
    ports:
      - "8545:8545"     # RPC
      - "30303:30303"   # P2P
      - "7070:7070"     # Dashboard
    volumes:
      - xdc-data:/data/xdcchain
    environment:
      - NETWORK=mainnet
      - CLIENT=stable
      - SKYNET_API_KEY=your-api-key
      - INSTANCE_NAME=MyXDCNode

volumes:
  xdc-data:
```

## Features

### 📊 SkyOne Dashboard

Beautiful real-time monitoring at `http://localhost:7070`:

- **Node Overview** - Block height, peers, sync status
- **Blockchain Metrics** - Sync progress, chain health
- **Network Stats** - Peer map, geographic distribution
- **System Metrics** - CPU, memory, disk usage
- **Alerts** - Sync stall warnings, diagnostics

### 📡 SkyNet Integration

Automatic monitoring and fleet management:

- Auto-registration on startup
- Heartbeat every 30 seconds
- View all nodes at [skynet.xdcindia.com](https://skynet.xdcindia.com)
- Get alerts for offline nodes

### 🔧 XDC Node Support

Multiple client support:

| Client | Type | Performance |
|--------|------|-------------|
| **Geth Stable** | Official | Balanced |
| **Geth PR5** | Latest | Fast sync |
| **Erigon** | Archive | Fastest |
| **Nethermind** | .NET | Efficient |
| **Reth** | Rust | Experimental |

## Configuration

### Environment Variables

```bash
# Core Settings
NODE_TYPE=full                    # full, archive, rpc, masternode
NETWORK=mainnet                   # mainnet, testnet, devnet, apothem
CLIENT=stable                     # stable, geth-pr5, erigon, nethermind
SYNC_MODE=snap                    # snap, full, fast

# Dashboard
DASHBOARD_PORT=7070               # Web UI port
DASHBOARD_REFRESH=10              # Refresh interval (seconds)
XDC_RPC_URL=http://localhost:8545 # XDC node endpoint

# SkyNet
SKYNET_ENABLED=true
SKYNET_API_URL=https://skynet.xdcindia.com/api
SKYNET_API_KEY=your-api-key       # Required for SkyNet
SKYNET_NODE_NAME=my-node          # Display name
SKYNET_ROLE=fullnode              # fullnode, validator, rpc
```

### Volume Mounts

```bash
-v xdc-data:/data/xdcchain        # Blockchain data
-v ./skynet.conf:/etc/xdc-node/skynet.conf:ro  # SkyNet config
-v ./logs:/var/log/xdc            # Log files
```

## Screenshots

### Dashboard Overview
![Dashboard](docs/images/skyone-dashboard.png)

### Node Metrics
![Metrics](docs/images/skyone-metrics.png)

### Peer Map
![Peer Map](docs/images/skyone-peers.png)

## API Endpoints

### Dashboard API

```
GET  /api/health        - Health check
GET  /api/metrics       - Current metrics (JSON)
GET  /api/peers         - Peer information
GET  /api/sync          - Sync status
POST /api/node/restart  - Restart XDC node
POST /api/node/stop     - Stop XDC node
```

### Prometheus Metrics

```
GET  /metrics           - Prometheus format metrics
```

Example:
```bash
curl http://localhost:6060/metrics

# HELP xdc_block_height Current block height
# TYPE xdc_block_height gauge
xdc_block_height 12345678

# HELP xdc_peer_count Number of connected peers
# TYPE xdc_peer_count gauge
xdc_peer_count 25
```

## Building from Source

```bash
git clone https://github.com/AnilChinchawale/xdc-node-setup.git
cd xdc-node-setup

# Build unified image
docker build -t xdc-skyone:latest -f docker/Dockerfile.skyone .

# Run locally
docker run -p 7070:7070 -p 8545:8545 xdc-skyone:latest
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    XDC SkyOne Agent                          │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   SkyOne     │  │  SkyNet      │  │   XDC Node   │      │
│  │  Dashboard   │  │   Agent      │  │  (Optional)  │      │
│  │   :7070      │  │ (Heartbeat)  │  │   :8545      │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

## Documentation

- [Full Documentation](docs/SKYONE_AGENT_DOCUMENTATION.md)
- [Docker Compose Guide](docker/docker-compose.skyone.yml)
- [API Reference](docs/API.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## Support

- 💬 [Discord Community](https://discord.gg/xdc)
- 🐛 [GitHub Issues](https://github.com/AnilChinchawale/xdc-node-setup/issues)
- 📧 [Email Support](mailto:support@xdc.network)
- 🌐 [SkyNet Platform](https://skynet.xdcindia.com)

## License

MIT License - See [LICENSE](LICENSE) file for details.

---

**Maintained by:** Anil Chinchawale  
**Version:** 3.0.0  
**Last Updated:** March 10, 2026
