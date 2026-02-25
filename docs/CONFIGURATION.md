# XDC Node Setup - Configuration Guide

## Overview

This guide covers all configuration options for XDC Node Setup, including environment variables, config files, and runtime parameters.

## Configuration Hierarchy

Configuration values are resolved in this order (highest priority first):

1. **Environment Variables**
2. **CLI Arguments**
3. **Config Files** (.env, config.toml)
4. **Docker Compose Defaults**
5. **Script Defaults**

## Environment Variables

### Core Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `NETWORK` | mainnet | Network: mainnet, testnet, apothem, devnet |
| `NODE_TYPE` | full | Node type: full, archive, masternode |
| `CLIENT` | xdc | Client: xdc, geth-pr5, erigon, nethermind, reth |
| `DATA_DIR` | /root/xdcchain | Chain data directory |

### RPC Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `RPC_PORT` | 8545 | HTTP RPC port |
| `WS_PORT` | 8546 | WebSocket port |
| `RPC_ADDR` | 127.0.0.1 | RPC bind address (security: use 127.0.0.1) |
| `WS_ADDR` | 127.0.0.1 | WebSocket bind address |
| `RPC_API` | admin,eth,net,web3,XDPoS | Enabled RPC APIs |
| `WS_API` | eth,net,web3,XDPoS | Enabled WebSocket APIs |
| `RPC_CORS_DOMAIN` | localhost | CORS allowed origins |
| `RPC_VHOSTS` | localhost | Virtual hosts whitelist |
| `WS_ORIGINS` | localhost | WebSocket origins whitelist |

### P2P Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `P2P_PORT` | 30303 | P2P TCP/UDP port |
| `MAX_PEERS` | 50 | Maximum peer connections |
| `BOOTNODES` | (network default) | Comma-separated bootnode enodes |

### Sync Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SYNC_MODE` | full | Sync mode: full, snap, fast |
| `GC_MODE` | full | Garbage collection: full, archive |
| `PRUNE_MODE` | full | Pruning mode: full, archive |

### Resource Limits

| Variable | Default | Description |
|----------|---------|-------------|
| `MEMORY_LIMIT` | 8G | Docker memory limit |
| `CPU_LIMIT` | 4 | Docker CPU limit |
| `CACHE_SIZE` | 4096 | XDC cache size in MB |

### Monitoring

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_MONITORING` | false | Enable Prometheus/Grafana |
| `DASHBOARD_PORT` | 7070 | SkyOne dashboard port |
| `PROMETHEUS_PORT` | 9090 | Prometheus port |
| `GRAFANA_PORT` | 3000 | Grafana port |

### SkyNet Integration

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_SKYNET` | false | Enable SkyNet fleet monitoring |
| `SKYNET_API_KEY` | (generated) | SkyNet API key |
| `SKYNET_NODE_ID` | (generated) | Unique node identifier |
| `SKYNET_NODE_NAME` | (hostname) | Node display name |
| `SKYNET_URL` | https://net.xdc.network | SkyNet API endpoint |

### Security

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_SECURITY` | true | Enable security hardening |
| `ENABLE_FIREWALL` | true | Enable UFW firewall |
| `ENABLE_FAIL2BAN` | true | Enable fail2ban |
| `ENABLE_AUTOMATIC_UPDATES` | true | Enable automatic updates |

## Config Files

### Main Config: config.toml

```toml
# /mainnet/.xdc-node/config.toml

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

# XDPoS 2.0 consensus
[xdpos]
Epoch = 900
Gap = 450
```

### Environment Config: .env

```bash
# /mainnet/.xdc-node/.env

# Network
NETWORK=mainnet
INSTANCE_NAME=my-xdc-node

# RPC (Security: Keep bind to localhost)
RPC_PORT=8545
RPC_ADDR=127.0.0.1
RPC_CORS_DOMAIN=localhost

# P2P
P2P_PORT=30303
MAX_PEERS=50

# Sync
SYNC_MODE=full
GC_MODE=full

# Resources
CACHE_SIZE=4096
```

### SkyNet Config: skynet.conf

```bash
# /mainnet/.xdc-node/skynet.conf

SKYNET_ENABLED=true
SKYNET_URL=https://net.xdc.network
SKYNET_API_KEY=your-api-key
SKYNET_NODE_ID=uuid-generated-during-setup
SKYNET_NODE_NAME=my-xdc-node
HEARTBEAT_INTERVAL=60
```

## Client-Specific Configuration

### Erigon Configuration

```bash
# Erigon uses different ports
RPC_PORT=8547
P2P_PORT=30304
P2P_PORT_68=30311

# Erigon needs more memory
ERIGON_MEMORY=12G
ERIGON_CPUS=4
```

### Nethermind Configuration

```bash
# Nethermind ports
RPC_PORT=8558
P2P_PORT=30306

# Nethermind memory
NETHERMIND_MEMORY=12G
```

### Reth Configuration

```bash
# Reth ports
RPC_PORT=7073
P2P_PORT=40303

# Reth needs more memory
RETH_MEMORY=16G
```

## Network Configuration

### Mainnet (NetworkId: 50)

```toml
[network]
NetworkId = 50
Bootnodes = [
  "enode://...",
  "enode://..."
]
```

### Testnet/Apothem (NetworkId: 51)

```toml
[network]
NetworkId = 51
Bootnodes = [
  "enode://...",
  "enode://..."
]
```

## Security Configuration

### Secure RPC Setup

```bash
# 1. Bind to localhost only
RPC_ADDR=127.0.0.1
WS_ADDR=127.0.0.1

# 2. Restrict CORS
RPC_CORS_DOMAIN=localhost
WS_ORIGINS=localhost

# 3. Use nginx reverse proxy for external access
# See: configs/nginx-rpc.conf
```

### Firewall Rules

```bash
# Required ports
sudo ufw allow 30303/tcp  # P2P
sudo ufw allow 30303/udp  # P2P
sudo ufw allow from 127.0.0.1 to any port 8545  # RPC (local only)
sudo ufw allow from 127.0.0.1 to any port 7070  # Dashboard (local only)
```

## Advanced Configuration

### Custom Genesis

```bash
# For private networks
GENESIS_FILE=/path/to/genesis.json
NETWORK=local
```

### Extra Flags

```bash
# Pass additional flags to XDC
XDC_EXTRA_FLAGS="--verbosity 5 --metrics"
```

### Log Configuration

```bash
# Log level
LOG_LEVEL=2  # 0=silent, 1=error, 2=warn, 3=info, 4=debug, 5=detail

# Log file
LOG_FILE=/var/log/xdc/xdc.log
```

## Configuration Validation

### Test Configuration

```bash
# Validate config without starting
xdc config validate

# Check config values
xdc config get rpc_port
xdc config get sync_mode

# List all config
xdc config list
```

### Debug Configuration

```bash
# Show effective configuration
xdc config dump

# Show configuration sources
xdc config sources
```

## Troubleshooting Configuration

### Common Issues

**Issue: RPC not accessible externally**
```bash
# Solution: Check bind address
RPC_ADDR=0.0.0.0  # Allow external (not recommended without auth)
# Or use nginx reverse proxy
```

**Issue: Sync too slow**
```bash
# Solution: Increase cache
CACHE_SIZE=8192

# Or use snap sync
SYNC_MODE=snap
```

**Issue: Out of memory**
```bash
# Solution: Reduce cache
CACHE_SIZE=2048

# Or reduce memory limit
MEMORY_LIMIT=4G
```

## Configuration Examples

### Production Masternode

```bash
# .env
NETWORK=mainnet
NODE_TYPE=masternode
CLIENT=xdc
SYNC_MODE=full
CACHE_SIZE=8192
MEMORY_LIMIT=16G
CPU_LIMIT=8

# Security
RPC_ADDR=127.0.0.1
ENABLE_SECURITY=true
ENABLE_FIREWALL=true

# Monitoring
ENABLE_MONITORING=true
ENABLE_SKYNET=true
```

### Development Node

```bash
# .env
NETWORK=devnet
NODE_TYPE=full
CLIENT=geth-pr5
SYNC_MODE=snap
CACHE_SIZE=2048
MEMORY_LIMIT=4G

# Local development
RPC_ADDR=0.0.0.0
RPC_CORS_DOMAIN=*
ENABLE_MONITORING=false
```

### Archive Node

```bash
# .env
NETWORK=mainnet
NODE_TYPE=archive
CLIENT=erigon
SYNC_MODE=full
GC_MODE=archive
CACHE_SIZE=16384
MEMORY_LIMIT=32G
```

## References

- [Docker Compose Config](docker/docker-compose.yml)
- [Setup Script](setup.sh)
- [Security Guide](docs/SECURITY.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
