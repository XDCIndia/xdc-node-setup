# XDC Node Setup - Configuration Guide
> Comprehensive configuration reference for SkyOne

## Table of Contents

1. [Configuration Files](#configuration-files)
2. [Environment Variables](#environment-variables)
3. [Network Configuration](#network-configuration)
4. [RPC Configuration](#rpc-configuration)
5. [Client-Specific Settings](#client-specific-settings)
6. [Advanced Configuration](#advanced-configuration)

---

## Configuration Files

### Main Configuration Files

```
XDC-Node-Setup/
├── mainnet/.xdc-node/
│   ├── config.toml          # Node configuration
│   ├── .env                 # Environment variables
│   └── skynet.conf          # SkyNet integration
├── docker/
│   └── docker-compose.yml   # Container orchestration
└── cli/
    └── xdc                  # CLI configuration
```

### Configuration Locations by Network

| Network | Configuration Path |
|---------|-------------------|
| Mainnet | `mainnet/.xdc-node/` |
| Testnet | `testnet/.xdc-node/` |
| Devnet | `devnet/.xdc-node/` |
| Apothem | `apothem/.xdc-node/` |

---

## Environment Variables

### Core Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `NETWORK` | mainnet | Network to connect to (mainnet, testnet, devnet, apothem) |
| `INSTANCE_NAME` | xdc-node | Name for this node instance |
| `SYNC_MODE` | full | Sync mode (full, fast, snap) |
| `GC_MODE` | full | Garbage collection mode (full, archive) |

### RPC Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_RPC` | true | Enable JSON-RPC API |
| `RPC_ADDR` | 127.0.0.1 | RPC bind address (127.0.0.1 for local only) |
| `RPC_PORT` | 8545 | RPC port |
| `RPC_API` | eth,net,web3,XDPoS | Enabled RPC APIs |
| `RPC_CORS_DOMAIN` | * | CORS allowed origins |
| `RPC_VHOSTS` | * | Virtual hosts allowed |

### WebSocket Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `WS_ADDR` | 127.0.0.1 | WebSocket bind address |
| `WS_PORT` | 8546 | WebSocket port |
| `WS_API` | eth,net,web3,XDPoS | Enabled WebSocket APIs |
| `WS_ORIGINS` | * | Allowed WebSocket origins |

### P2P Network Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | 30303 | P2P listening port |
| `P2P_PORT` | 30303 | Alias for PORT |
| `NAT` | any | NAT traversal method |
| `MAX_PEERS` | 50 | Maximum peer connections |

### Logging Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_LEVEL` | 2 | Log verbosity (0=silent, 5=detail) |
| `MAX_LOG_SIZE` | 1073741824 | Max log file size in bytes (1GB) |

### Metrics Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `METRICS` | true | Enable metrics collection |
| `METRICS_ADDR` | 127.0.0.1 | Metrics bind address |
| `METRICS_PORT` | 6060 | Metrics port |
| `PPROF` | false | Enable pprof profiling |
| `PPROF_ADDR` | 127.0.0.1 | pprof bind address |
| `PPROF_PORT` | 6060 | pprof port |

### Dashboard Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `DASHBOARD_PORT` | 7070 | Dashboard port |
| `DASHBOARD_AUTH_ENABLED` | false | Enable dashboard auth |
| `DASHBOARD_USER` | admin | Dashboard username |
| `DASHBOARD_PASS` | xdc-skyone | Dashboard password |

### Grafana Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_GRAFANA` | false | Enable Grafana |
| `GRAFANA_ADMIN_USER` | admin | Grafana admin username |
| `GRAFANA_ADMIN_PASSWORD` | changeme | Grafana admin password |
| `GRAFANA_SECRET_KEY` | xdc-grafana-secret | Grafana secret key |

### SkyNet Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_SKYNET` | false | Enable SkyNet integration |
| `SKYNET_API_KEY` | - | SkyNet API key |
| `SKYNET_NODE_ID` | - | Unique node identifier |
| `SKYNET_NODE_NAME` | - | Node display name |

---

## Network Configuration

### Mainnet Configuration

```bash
# mainnet/.xdc-node/.env
NETWORK=mainnet
INSTANCE_NAME=xdc-mainnet-node
SYNC_MODE=full
GC_MODE=full

# RPC Configuration
ENABLE_RPC=true
RPC_ADDR=127.0.0.1
RPC_PORT=8545
RPC_API=admin,eth,net,web3,XDPoS
RPC_CORS_DOMAIN=http://localhost:7070

# P2P Configuration
PORT=30303
MAX_PEERS=50
```

### Testnet (Apothem) Configuration

```bash
# testnet/.xdc-node/.env
NETWORK=testnet
INSTANCE_NAME=xdc-testnet-node
SYNC_MODE=fast
GC_MODE=full

# RPC Configuration
ENABLE_RPC=true
RPC_ADDR=127.0.0.1
RPC_PORT=8545

# P2P Configuration
PORT=30304
MAX_PEERS=25
```

---

## RPC Configuration

### Secure RPC Setup

```bash
# Bind to localhost only (recommended)
RPC_ADDR=127.0.0.1

# Restrict CORS to specific origins
RPC_CORS_DOMAIN=http://localhost:7070,https://net.xdc.network

# Enable only necessary APIs
RPC_API=eth,net,web3,XDPoS

# Disable admin API in production
# RPC_API=eth,net,web3
```

### Public RPC Setup (Not Recommended)

⚠️ **Warning**: Only use this if you understand the security implications

```bash
# Bind to all interfaces
RPC_ADDR=0.0.0.0

# Enable authentication
RPC_API=eth,net,web3

# Restrict CORS
RPC_CORS_DOMAIN=https://yourdomain.com
```

---

## Client-Specific Settings

### XDC Geth (Default)

```bash
# Standard configuration
CLIENT=xdc
RPC_PORT=8545
P2P_PORT=30303
```

### Erigon-XDC

```bash
# Erigon-specific ports
CLIENT=erigon
RPC_PORT=8547
P2P_PORT=30304
P2P_PORT_68=30311

# Resource limits
ERIGON_MEMORY=12G
ERIGON_CPUS=4
```

**Important**: Erigon uses port 30304 (eth/63) for XDC compatibility, NOT port 30311 (eth/68).

### Nethermind-XDC

```bash
# Nethermind-specific ports
CLIENT=nethermind
RPC_PORT=8558
P2P_PORT=30306
```

### Reth-XDC

```bash
# Reth-specific ports
CLIENT=reth
RPC_PORT=7073
P2P_PORT=40303

# Requires debug.tip for sync
RETH_DEBUG_TIP=0x...
```

---

## Advanced Configuration

### Custom Bootnodes

```bash
# Edit bootnodes.list
cat > mainnet/.xdc-node/bootnodes.list << 'EOF'
enode://bootnode1@ip1:30303
enode://bootnode2@ip2:30303
EOF
```

### Pruning Configuration

```bash
# Enable pruning to reduce disk usage
GC_MODE=full
SYNC_MODE=full

# For archive node (keeps all history)
GC_MODE=archive
```

### Masternode Configuration

```bash
# Required for masternode operation
NODE_TYPE=masternode
GC_MODE=archive
SYNC_MODE=full

# Coinbase address
COINBASE=0x...

# Unlock account
UNLOCK=0x...
PASSWORD_FILE=/work/.pwd
```

### Prometheus Metrics

```bash
# Enable Prometheus
ENABLE_PROMETHEUS=true
METRICS=true
METRICS_ADDR=0.0.0.0
METRICS_PORT=6060

# Start with monitoring profile
docker compose --profile monitoring up -d
```

---

## Configuration Management

### Using CLI

```bash
# View all config
xdc config list

# Get specific value
xdc config get rpc_port

# Set value
xdc config set rpc_port 8545

# Apply changes
xdc restart
```

### Using Environment Files

```bash
# Edit environment file
nano mainnet/.xdc-node/.env

# Restart to apply
xdc restart
```

### Using Docker Compose Overrides

```yaml
# docker-compose.override.yml
services:
  xdc-node:
    environment:
      - RPC_PORT=8545
      - MAX_PEERS=100
    deploy:
      resources:
        limits:
          memory: 16G
```

---

## Security Best Practices

### 1. RPC Security

```bash
# Always bind to localhost in production
RPC_ADDR=127.0.0.1

# Use reverse proxy for external access
# nginx/apache with SSL termination
```

### 2. Firewall Configuration

```bash
# Allow only necessary ports
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 30303/tcp   # XDC P2P
sudo ufw allow 30303/udp   # XDC P2P
# Do NOT expose RPC port externally
```

### 3. File Permissions

```bash
# Secure configuration files
chmod 600 mainnet/.xdc-node/.env
chmod 600 mainnet/.xdc-node/.pwd
chown -R $USER:$USER mainnet/.xdc-node/
```

---

## Configuration Validation

### Test RPC Configuration

```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

### Test P2P Connectivity

```bash
# Check peer count
xdc peers

# Or via RPC
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
```

### Validate Configuration

```bash
# Run configuration check
xdc config validate

# Check for common issues
xdc health --full
```

---

## Environment-Specific Configurations

### Development

```bash
LOG_LEVEL=4
ENABLE_RPC=true
RPC_ADDR=0.0.0.0
METRICS=true
PPROF=true
```

### Staging

```bash
LOG_LEVEL=3
ENABLE_RPC=true
RPC_ADDR=127.0.0.1
METRICS=true
PPROF=false
ENABLE_SKYNET=true
```

### Production

```bash
LOG_LEVEL=2
ENABLE_RPC=true
RPC_ADDR=127.0.0.1
RPC_CORS_DOMAIN=https://net.xdc.network
METRICS=true
PPROF=false
ENABLE_SKYNET=true
ENABLE_SECURITY=true
```

---

## Troubleshooting Configuration

### Reset to Defaults

```bash
# Backup current config
cp mainnet/.xdc-node/.env mainnet/.xdc-node/.env.backup

# Reset to defaults
xdc config reset

# Or manually copy example
cp docker/mainnet/.env.example mainnet/.xdc-node/.env
```

### Debug Configuration

```bash
# View effective configuration
xdc config list --verbose

# Check environment variables
env | grep -E 'RPC|P2P|NETWORK'

# View container environment
docker exec xdc-node env
```

---

## Related Documentation

- [Setup Guide](SETUP.md) - Installation instructions
- [Troubleshooting Guide](TROUBLESHOOTING.md) - Common issues
- [API Reference](API.md) - Programmatic interaction
- [Security Guide](SECURITY.md) - Security hardening
