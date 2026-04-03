# XDC Node Setup - Configuration Guide

**Version:** 1.0  
**Date:** March 4, 2026

This guide covers all configuration options for XDC Node Setup (SkyOne).

## Configuration Files

### 1. `.env` - Environment Variables

Location: `mainnet/.xdc-node/.env` (or `testnet/.xdc-node/.env`)

```bash
# Node Identity
INSTANCE_NAME=XDC_Node
CONTACT_DETAILS=admin@example.com

# Network Configuration
NETWORK=mainnet
NETWORK_ID=50

# Sync Configuration
SYNC_MODE=full
GC_MODE=full

# RPC Configuration
ENABLE_RPC=true
ENABLE_WS=true
RPC_ADDR=127.0.0.1
RPC_PORT=8545
RPC_API=admin,eth,net,web3,XDPoS
RPC_CORS_DOMAIN=http://localhost:7070
RPC_VHOSTS=localhost,127.0.0.1

# WebSocket Configuration
WS_ADDR=127.0.0.1
WS_PORT=8546
WS_API=admin,eth,net,web3,XDPoS
WS_ORIGINS=localhost,127.0.0.1

# P2P Configuration
P2P_PORT=30303

# Dashboard Configuration
DASHBOARD_PORT=7070

# Erigon-Specific Ports (Multi-Client Mode)
ERIGON_RPC_PORT=8547
ERIGON_AUTHRPC_PORT=8561
ERIGON_P2P_PORT=30304
ERIGON_P2P_PORT_68=30311
ERIGON_DASHBOARD_PORT=7071

# Nethermind-Specific Ports (Multi-Client Mode)
NETHERMIND_RPC_PORT=8556
NETHERMIND_P2P_PORT=30306
NETHERMIND_DASHBOARD_PORT=7072

# Private Key (for masternodes)
PRIVATE_KEY=0000000000000000000000000000000000000000000000000000000000000000

# Logging
LOG_LEVEL=2
```

### 2. `config.toml` - Node Configuration

Location: `mainnet/.xdc-node/config.toml`

```toml
[node]
NetworkId = 50
DataDir = "/work/xdcchain"
HTTPPort = 8545
WSPort = 8546
Port = 30303
MaxPeers = 50

[eth]
SyncMode = "snap"
GCMode = "full"
Cache = 4096

[eth.txpool]
PriceLimit = 1
PriceBump = 10
AccountSlots = 16
GlobalSlots = 4096
AccountQueue = 64
GlobalQueue = 1024

[rpc]
HTTPHost = "127.0.0.1"
HTTPVirtualHosts = ["localhost"]
HTTPCors = ["localhost"]
WSHost = "127.0.0.1"
WSOrigins = ["localhost"]

[metrics]
Enabled = true
Port = 6060

[rpc]
Enabled = true
API = ["admin", "eth", "net", "web3", "XDPoS"]
CorsDomain = ["*"]
Vhosts = ["*"]
```

### 3. `skynet.conf` - SkyNet Integration

Location: `mainnet/.xdc-node/skynet.conf`

```bash
# SkyNet API Configuration
SKYNET_API_URL=https://skynet.xdcindia.com/api/v1
SKYNET_API_KEY=your-api-key-here

# Node Identity
SKYNET_NODE_ID=550e8400-e29b-41d4-a716-446655440000
SKYNET_NODE_NAME=xdc-node-01
SKYNET_ROLE=fullnode

# Heartbeat Configuration
HEARTBEAT_INTERVAL=30
```

## Client-Specific Configuration

### Geth-XDC (Stable)

```yaml
# docker-compose.yml
services:
  xdc-node:
    image: xinfinorg/xdposchain:v2.6.8
    ports:
      - "127.0.0.1:8545:8545"  # RPC
      - "127.0.0.1:8546:8546"  # WebSocket
      - "30303:30303"          # P2P
      - "30303:30303/udp"      # P2P UDP
```

### Erigon-XDC

```yaml
# docker-compose.erigon.yml
services:
  xdc-erigon:
    image: anilchinchawale/erix:latest
    ports:
      - "127.0.0.1:8547:8547"  # RPC (different from Geth)
      - "127.0.0.1:8561:8561"  # Auth RPC
      - "30304:30304"          # P2P (eth/63 - XDC compatible)
      - "30311:30311"          # P2P (eth/68 - NOT XDC compatible)
```

**Important:** Erigon uses port 30304 for XDC-compatible peers (eth/63) and port 30311 for standard Ethereum peers (eth/68). Only use port 30304 for XDC Network connections.

### Nethermind-XDC

```yaml
# docker-compose.nethermind.yml
services:
  xdc-node:
    image: anilchinchawale/nmx:latest
    ports:
      - "127.0.0.1:8556:8545"  # RPC
      - "30306:30303"          # P2P
```

### Reth-XDC

```yaml
# docker-compose.reth.yml
services:
  xdc-reth:
    image: anilchinchawale/reth-xdc:latest
    ports:
      - "127.0.0.1:7073:8545"  # RPC
      - "40303:30303"          # P2P
```

## Network Configuration

### Mainnet (Chain ID: 50)

```bash
NETWORK=mainnet
NETWORK_ID=50
BOOTNODES=enode://9a977b1ac4320fa2c862dcaf536aaaea3a8f8f7cd14e3bcde32e5a1c0152bd17bd18bfdc3c2ca8c4a0f3da153c62935fea1dc040cc1e66d2c07d6b4c91e2ed42@bootnode.xinfin.network:30303
```

### Testnet/Apothem (Chain ID: 51)

```bash
NETWORK=apothem
NETWORK_ID=51
APOTHEM_FLAG=--apothem
BOOTNODES=enode://91e59fa1b034ae35e9f4e8a99cc6621f09d74e76a6220abb6c93b29ed41a9e1fc4e5b70e2c5fc43f883cffbdcd6f4f6cbc1d23af077f28c2aecc22403355d4b1@bootnodes.apothem.network:30312
```

### Devnet (Chain ID: 551)

```bash
NETWORK=devnet
NETWORK_ID=551
```

## Sync Modes

### Full Sync

```bash
SYNC_MODE=full
```

- Downloads and verifies all blocks
- Highest security
- Slowest sync
- Required for masternodes

### Snap Sync

```bash
SYNC_MODE=snap
```

- Downloads recent state snapshots
- Faster initial sync
- Lower resource usage
- Not suitable for masternodes

## Security Configuration

### SSH Hardening

```bash
# /etc/ssh/sshd_config
Port 2222                          # Non-default port
PermitRootLogin no                 # Disable root login
PasswordAuthentication no          # Use keys only
MaxAuthTries 3
```

### Firewall (UFW)

```bash
# Default deny
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (custom port)
sudo ufw allow 2222/tcp

# Allow XDC P2P
sudo ufw allow 30303/tcp
sudo ufw allow 30303/udp

# Allow monitoring (if enabled)
sudo ufw allow 9090/tcp  # Prometheus
sudo ufw allow 3000/tcp  # Grafana

# Enable firewall
sudo ufw enable
```

### Docker Security

```yaml
# docker-compose.yml
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

## Monitoring Configuration

### Prometheus

```yaml
# docker/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'xdc-node'
    static_configs:
      - targets: ['xdc-node:6060']
    metrics_path: /debug/metrics/prometheus
```

### Grafana

```yaml
# docker-compose.monitoring.yml
services:
  grafana:
    image: grafana/grafana:latest
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=secure-password
      - GF_USERS_ALLOW_SIGN_UP=false
```

### Nginx Reverse Proxy

### Custom Data Directory

```bash
# .env
DATA_DIR=/mnt/xdc-data/xdcchain
```

### Memory Limits

```bash
# .env
CACHE_SIZE=8192  # 8GB cache
```

### Peer Configuration

```bash
# .env
MAX_PEERS=50
```

### Bootnodes

Create `mainnet/bootnodes.list`:

```
enode://9a977b1ac4320fa2c862dcaf536aaaea3a8f8f7cd14e3bcde32e5a1c0152bd17bd18bfdc3c2ca8c4a0f3da153c62935fea1dc040cc1e66d2c07d6b4c91e2ed42@bootnode.xinfin.network:30303
```

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `NODE_TYPE` | `full` | Node type: full, archive, masternode |
| `NETWORK` | `mainnet` | Network: mainnet, testnet, devnet |
| `CLIENT` | `stable` | Client: stable, geth-pr5, erigon, nethermind, reth |
| `SYNC_MODE` | `full` | Sync mode: full, snap |
| `RPC_PORT` | `8545` | RPC port |
| `P2P_PORT` | `30303` | P2P port |
| `DATA_DIR` | `mainnet/xdcchain` | Data directory |
| `ENABLE_MONITORING` | `false` | Enable Prometheus/Grafana |
| `ENABLE_SKYNET` | `false` | Enable SkyNet integration |
| `ENABLE_SECURITY` | `true` | Enable security hardening |

## Troubleshooting Configuration

### Reset Configuration

```bash
# Stop node
xdc stop

# Remove configuration
rm -rf mainnet/.xdc-node/

# Re-run setup
./setup.sh
```

### View Current Configuration

```bash
# View all config
xdc config list

# View specific value
xdc config get rpc_port

# Set value
xdc config set rpc_port 8546
```

### Validate Configuration

```bash
# Check for errors
xdc health --full
```

---

**Document Version:** 1.0.0  
**Last Updated:** February 27, 2026
