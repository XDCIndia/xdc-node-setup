# XDC SkyOne Agent - Unified Container Documentation

## Overview

**XDC SkyOne Agent** is a unified, single-container solution that combines:
- 🖥️ **SkyOne Dashboard** - Real-time web UI for XDC node monitoring
- 📡 **SkyNet Agent** - Automatic node registration and heartbeat monitoring
- 🔧 **XDC Node Management** - Built-in node control and diagnostics
- 📊 **Metrics Collection** - Prometheus-compatible metrics export

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    XDC SkyOne Agent Container                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   SkyOne     │  │  SkyNet      │  │   XDC Node   │      │
│  │  Dashboard   │  │   Agent      │  │   (Optional) │      │
│  │   (Port 7070)│  │ (Heartbeat)  │  │              │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
│         │                  │                  │              │
│         └──────────────────┼──────────────────┘              │
│                            ▼                                │
│                   ┌────────────────┐                        │
│                   │  Unified API   │                        │
│                   │   (Internal)   │                        │
│                   └────────────────┘                        │
│                            │                                │
│         ┌──────────────────┼──────────────────┐              │
│         ▼                  ▼                  ▼              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  SkyNet API  │  │  XDC P2P     │  │  Prometheus  │      │
│  │  (Optional)  │  │   Network    │  │  (Optional)  │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Option 1: Standalone Dashboard (Monitoring External Node)

```bash
docker run -d \
  --name xdc-skyone \
  -p 7070:7070 \
  -e XDC_RPC_URL=http://your-xdc-node:8545 \
  -e SKYNET_API_KEY=your-api-key \
  anilchinchawale/xdc-skyone:latest
```

### Option 2: Full Node + Dashboard + SkyNet

```bash
docker run -d \
  --name xdc-skyone \
  -p 8545:8545 \
  -p 30303:30303 \
  -p 7070:7070 \
  -p 6060:6060 \
  -v xdc-data:/data \
  -e NODE_TYPE=full \
  -e NETWORK=mainnet \
  -e SKYNET_API_KEY=your-api-key \
  anilchinchawale/xdc-skyone:latest
```

### Option 3: Docker Compose (Recommended)

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
      - "6060:6060"     # Metrics
    volumes:
      - xdc-data:/data
      - ./skynet.conf:/etc/xdc-node/skynet.conf:ro
    environment:
      - NODE_TYPE=full
      - NETWORK=mainnet
      - CLIENT=stable
      - SYNC_MODE=snap
      - INSTANCE_NAME=MyXDCNode
      # SkyNet Configuration
      - SKYNET_API_URL=https://net.xdc.network/api
      - SKYNET_API_KEY=${SKYNET_API_KEY}
      - SKYNET_NODE_NAME=my-xdc-node
      - SKYNET_ROLE=fullnode
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:7070/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - xdc-network

volumes:
  xdc-data:
    driver: local

networks:
  xdc-network:
    driver: bridge
```

## Environment Variables

### Core Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `NODE_TYPE` | `full` | Node type: full, archive, rpc, masternode |
| `NETWORK` | `mainnet` | Network: mainnet, testnet, devnet, apothem |
| `CLIENT` | `stable` | Client: stable, geth-pr5, erigon, nethermind |
| `SYNC_MODE` | `snap` | Sync mode: snap, full, fast |
| `INSTANCE_NAME` | `XDC-Node` | Node display name |

### Dashboard Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `DASHBOARD_PORT` | `7070` | Dashboard web UI port |
| `DASHBOARD_REFRESH` | `10` | Metrics refresh interval (seconds) |
| `XDC_RPC_URL` | `http://localhost:8545` | XDC node RPC endpoint |

### SkyNet Agent Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SKYNET_ENABLED` | `true` | Enable SkyNet agent |
| `SKYNET_API_URL` | `https://net.xdc.network/api` | SkyNet API endpoint |
| `SKYNET_API_KEY` | - | Your SkyNet API key (required) |
| `SKYNET_NODE_ID` | - | Persistent node ID (auto-generated) |
| `SKYNET_NODE_NAME` | `hostname` | Node name in SkyNet |
| `SKYNET_ROLE` | `fullnode` | Node role: fullnode, validator, rpc |
| `HEARTBEAT_INTERVAL` | `30` | Heartbeat interval (seconds) |

### Network Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `RPC_PORT` | `8545` | JSON-RPC HTTP port |
| `WS_PORT` | `8546` | WebSocket port |
| `P2P_PORT` | `30303` | P2P networking port |
| `METRICS_PORT` | `6060` | Prometheus metrics port |

### Security Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `RPC_CORS` | `localhost` | Allowed CORS origins |
| `RPC_VHOSTS` | `localhost,127.0.0.1` | Allowed virtual hosts |
| `ENABLE_AUTH` | `false` | Enable RPC authentication |

## Features

### SkyOne Dashboard

Real-time web interface accessible at `http://localhost:7070`:

- **📊 Node Overview**
  - Block height and sync status
  - Peer count and network health
  - Client version and uptime

- **⛓️ Blockchain Metrics**
  - Current/highest block
  - Sync percentage with progress bar
  - Chain ID and consensus status

- **🌐 Network Stats**
  - Peer map visualization
  - Inbound/outbound peer distribution
  - Geographic peer distribution

- **💾 System Metrics**
  - CPU and memory usage
  - Disk space and I/O
  - Network bandwidth

- **⚠️ Alerts & Diagnostics**
  - Sync stall warnings
  - Peer connectivity issues
  - Auto-healing suggestions

- **🔗 SkyNet Integration**
  - Registration status
  - Last heartbeat timestamp
  - Fleet-wide node visibility

### SkyNet Agent

Automatic monitoring and registration:

1. **Auto-Registration**
   - Detects node configuration on startup
   - Registers with SkyNet API
   - Persists node ID for continuity

2. **Heartbeat Monitoring**
   - Sends metrics every 30 seconds
   - Includes block height, peers, sync status
   - Automatic retry on failure

3. **Fleet Management**
   - View all nodes in SkyNet dashboard
   - Compare performance across nodes
   - Get alerts for offline nodes

## API Endpoints

### Dashboard API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Health check |
| `/api/metrics` | GET | Current metrics JSON |
| `/api/peers` | GET | Peer information |
| `/api/sync` | GET | Sync status |
| `/api/node/restart` | POST | Restart XDC node |
| `/api/node/stop` | POST | Stop XDC node |

### Prometheus Metrics

Available at `:6060/metrics`:

```
# HELP xdc_block_height Current block height
# TYPE xdc_block_height gauge
xdc_block_height 12345678

# HELP xdc_peer_count Number of connected peers
# TYPE xdc_peer_count gauge
xdc_peer_count 25

# HELP xdc_sync_status Sync status (1=syncing, 0=synced)
# TYPE xdc_sync_status gauge
xdc_sync_status 0
```

## Building from Source

```bash
# Clone repository
git clone https://github.com/AnilChinchawale/xdc-node-setup.git
cd xdc-node-setup

# Build the unified image
docker build -t xdc-skyone:latest -f docker/Dockerfile.skyone .

# Run locally
docker run -p 7070:7070 -p 8545:8545 xdc-skyone:latest
```

## Troubleshooting

### Dashboard Not Loading

```bash
# Check container logs
docker logs xdc-skyone

# Verify dashboard is running
docker exec xdc-skyone curl -s http://localhost:7070/api/health
```

### SkyNet Registration Failing

```bash
# Check SkyNet config
docker exec xdc-skyone cat /etc/xdc-node/skynet.conf

# Test SkyNet connectivity
docker exec xdc-skyone curl -s https://net.xdc.network/api/health
```

### XDC Node Not Syncing

```bash
# Check XDC node logs
docker logs xdc-skyone | grep -i "xdc\|geth\|erigon"

# Verify RPC endpoint
docker exec xdc-skyone curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
```

## Security Best Practices

1. **Change Default Passwords**
   - Set strong `SKYNET_API_KEY`
   - Use environment variables, not hardcoded values

2. **Restrict RPC Access**
   - Set `RPC_CORS` to your domain only
   - Use `RPC_VHOSTS` to whitelist hosts

3. **Enable Authentication**
   - Set `ENABLE_AUTH=true` for production
   - Use JWT tokens for API access

4. **Firewall Rules**
   ```bash
   # Allow only necessary ports
   ufw allow 7070/tcp    # Dashboard
   ufw allow 30303/tcp   # P2P
   ufw allow 30303/udp   # P2P
   ufw deny 8545/tcp     # RPC (internal only)
   ```

## Migration from Separate Components

### From Standalone Dashboard

```bash
# Old way
docker run -p 7070:7070 xdc-dashboard:latest

# New way (monitoring external node)
docker run -p 7070:7070 \
  -e XDC_RPC_URL=http://existing-node:8545 \
  xdc-skyone:latest
```

### From Standalone SkyNet Agent

```bash
# Old way
./scripts/skynet-agent.sh --daemon

# New way (built-in)
docker run -p 7070:7070 \
  -e SKYNET_API_KEY=your-key \
  xdc-skyone:latest
```

## License

MIT License - See LICENSE file for details.

## Support

- 📖 Documentation: https://docs.xdc.network
- 💬 Discord: https://discord.gg/xdc
- 🐛 Issues: https://github.com/AnilChinchawale/xdc-node-setup/issues
- 🌐 SkyNet: https://net.xdc.network

---

**Version:** 3.0.0  
**Last Updated:** March 10, 2026  
**Maintainer:** Anil Chinchawale
