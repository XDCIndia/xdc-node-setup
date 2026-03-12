# Multi-Client XDC Node Deployment Guide

**Version:** 1.0  
**Date:** February 27, 2026  
**Applies to:** xdc-node-setup (SkyOne) v1.0+

---

## Table of Contents

1. [Introduction](#introduction)
2. [Supported Clients](#supported-clients)
3. [Client Comparison](#client-comparison)
4. [Port Configuration](#port-configuration)
5. [Single Machine Multi-Client Setup](#single-machine-multi-client-setup)
6. [Cross-Client Communication](#cross-client-communication)
7. [Monitoring Multi-Client Deployments](#monitoring-multi-client-deployments)
8. [Troubleshooting](#troubleshooting)

---

## Introduction

This guide covers deploying multiple XDC clients on a single machine or across a fleet. Multi-client diversity improves network resilience and allows operators to choose the best client for their specific use case.

---

## Supported Clients

### 1. XDC Geth (Stable)
- **Version:** v2.6.8
- **Status:** Production
- **Type:** Official Docker image
- **Best for:** General use, stability

### 2. XDC Geth PR5
- **Version:** Latest development
- **Status:** Testing
- **Type:** Source build
- **Best for:** Latest features, testing

### 3. Erigon-XDC
- **Version:** Latest
- **Status:** Experimental
- **Type:** Source build
- **Best for:** Archive nodes, fast sync

### 4. Nethermind-XDC
- **Version:** Latest
- **Status:** Beta
- **Type:** .NET build
- **Best for:** Low resource usage, fast sync

### 5. Reth-XDC
- **Version:** Latest
- **Status:** Alpha
- **Type:** Rust build
- **Best for:** Maximum performance, lowest disk usage

---

## Client Comparison

| Feature | Geth | Geth PR5 | Erigon | Nethermind | Reth |
|---------|------|----------|--------|------------|------|
| **RPC Port** | 8545 | 8545 | 8547 | 8558 | 7073 |
| **P2P Port** | 30303 | 30303 | 30304, 30311 | 30306 | 40303 |
| **Memory** | 4GB+ | 4GB+ | 8GB+ | 12GB+ | 16GB+ |
| **Disk** | ~500GB | ~500GB | ~400GB | ~350GB | ~300GB |
| **Sync Speed** | Standard | Standard | Fast | Very Fast | Very Fast |
| **Status** | Production | Testing | Experimental | Beta | Alpha |

---

## Port Configuration

### Default Ports by Client

```yaml
# Geth (Stable & PR5)
geth:
  rpc: 8545
  ws: 8546
  p2p: 30303
  auth_rpc: 8551

# Erigon
erigon:
  rpc: 8547
  auth_rpc: 8561
  private_api: 9091
  p2p_eth63: 30304  # XDC compatible
  p2p_eth68: 30311  # NOT XDC compatible

# Nethermind
nethermind:
  rpc: 8558
  p2p: 30306

# Reth
reth:
  rpc: 7073
  p2p: 40303
  discovery: 40304
```

### Port Allocation for Multi-Client Setup

When running multiple clients on the same machine, use this port allocation:

```yaml
# Client 1: Geth (Primary)
geth_primary:
  rpc: 8545
  ws: 8546
  p2p: 30303
  metrics: 6060

# Client 2: Erigon (Secondary)
erigon_secondary:
  rpc: 8547
  auth_rpc: 8561
  private_api: 9091
  p2p_eth63: 30304
  p2p_eth68: 30311
  metrics: 6061

# Client 3: Nethermind (Tertiary)
nethermind_tertiary:
  rpc: 8558
  p2p: 30306
  metrics: 6062

# Client 4: Reth (Quaternary)
reth_quaternary:
  rpc: 7073
  p2p: 40303
  discovery: 40304
  metrics: 6063
```

---

## Single Machine Multi-Client Setup

### Prerequisites

- 32GB+ RAM (64GB recommended)
- 2TB+ NVMe SSD
- 8+ CPU cores
- Docker and Docker Compose

### Directory Structure

```
xdc-multi-client/
├── docker-compose.yml          # Main compose file
├── .env                        # Environment variables
├── geth/
│   ├── docker-compose.yml
│   └── data/
├── erigon/
│   ├── docker-compose.yml
│   └── data/
├── nethermind/
│   ├── docker-compose.yml
│   └── data/
├── reth/
│   ├── docker-compose.yml
│   └── data/
└── monitoring/
    ├── prometheus.yml
    └── grafana/
```

### Docker Compose Configuration

```yaml
# docker-compose.yml
version: '3.8'

services:
  # Geth Primary Node
  geth-node:
    image: xinfinorg/xdposchain:v2.6.8
    container_name: xdc-geth
    restart: unless-stopped
    ports:
      - "8545:8545"     # RPC
      - "8546:8546"     # WS
      - "30303:30303"   # P2P TCP
      - "30303:30303/udp" # P2P UDP
      - "6060:6060"     # Metrics
    volumes:
      - ./geth/data:/xdcchain
      - ./geth/config:/config
    environment:
      - NETWORK=mainnet
      - RPC_PORT=8545
      - WS_PORT=8546
      - PORT=30303
    networks:
      - xdc-network

  # Erigon Secondary Node
  erigon-node:
    build:
      context: ./erigon
      dockerfile: Dockerfile
    container_name: xdc-erigon
    restart: unless-stopped
    ports:
      - "8547:8547"     # RPC
      - "8561:8561"     # Auth RPC
      - "9091:9091"     # Private API
      - "30304:30304"   # P2P eth/63 (XDC compatible)
      - "30304:30304/udp"
      - "30311:30311"   # P2P eth/68 (NOT XDC compatible)
      - "30311:30311/udp"
      - "6061:6060"     # Metrics
    volumes:
      - ./erigon/data:/erigon-data
    environment:
      - NETWORK=mainnet
      - RPC_PORT=8547
      - P2P_PORT=30304
      - P2P_PORT_68=30311
    networks:
      - xdc-network

  # Nethermind Tertiary Node
  nethermind-node:
    build:
      context: ./nethermind
      dockerfile: Dockerfile
    container_name: xdc-nethermind
    restart: unless-stopped
    ports:
      - "8558:8558"     # RPC
      - "30306:30306"   # P2P
      - "30306:30306/udp"
      - "6062:6060"     # Metrics
    volumes:
      - ./nethermind/data:/nethermind-data
    environment:
      - NETWORK=mainnet
      - RPC_PORT=8558
      - P2P_PORT=30306
    networks:
      - xdc-network

  # Reth Quaternary Node
  reth-node:
    build:
      context: ./reth
      dockerfile: Dockerfile
    container_name: xdc-reth
    restart: unless-stopped
    ports:
      - "7073:7073"     # RPC
      - "40303:40303"   # P2P
      - "40303:40303/udp"
      - "40304:40304/udp" # Discovery
      - "6063:6060"     # Metrics
    volumes:
      - ./reth/data:/reth-data
    environment:
      - NETWORK=mainnet
      - RPC_PORT=7073
      - P2P_PORT=40303
    networks:
      - xdc-network

  # Shared Monitoring
  prometheus:
    image: prom/prometheus:latest
    container_name: xdc-prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    networks:
      - xdc-network

  grafana:
    image: grafana/grafana:latest
    container_name: xdc-grafana
    ports:
      - "3000:3000"
    volumes:
      - ./monitoring/grafana:/etc/grafana/provisioning
      - grafana-data:/var/lib/grafana
    networks:
      - xdc-network

networks:
  xdc-network:
    driver: bridge

volumes:
  prometheus-data:
  grafana-data:
```

### Prometheus Configuration

```yaml
# monitoring/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'geth-node'
    static_configs:
      - targets: ['geth-node:6060']
    metrics_path: /debug/metrics/prometheus

  - job_name: 'erigon-node'
    static_configs:
      - targets: ['erigon-node:6060']
    metrics_path: /debug/metrics/prometheus

  - job_name: 'nethermind-node'
    static_configs:
      - targets: ['nethermind-node:6060']
    metrics_path: /metrics

  - job_name: 'reth-node'
    static_configs:
      - targets: ['reth-node:6060']
    metrics_path: /metrics
```

### Environment Variables

```bash
# .env
# Geth Configuration
GETH_NETWORK=mainnet
GETH_RPC_PORT=8545
GETH_WS_PORT=8546
GETH_P2P_PORT=30303

# Erigon Configuration
ERIGON_NETWORK=mainnet
ERIGON_RPC_PORT=8547
ERIGON_P2P_PORT=30304
ERIGON_P2P_PORT_68=30311

# Nethermind Configuration
NETHERMIND_NETWORK=mainnet
NETHERMIND_RPC_PORT=8558
NETHERMIND_P2P_PORT=30306

# Reth Configuration
RETH_NETWORK=mainnet
RETH_RPC_PORT=7073
RETH_P2P_PORT=40303
```

### Starting Multi-Client Setup

```bash
# 1. Create directory structure
mkdir -p xdc-multi-client/{geth,erigon,nethermind,reth,monitoring}/{data,config}

# 2. Copy configuration files
cp docker-compose.yml xdc-multi-client/
cp .env xdc-multi-client/
cp prometheus.yml xdc-multi-client/monitoring/

# 3. Start all clients
cd xdc-multi-client
docker-compose up -d

# 4. Verify all clients are running
docker-compose ps

# 5. Check logs
docker-compose logs -f geth-node
docker-compose logs -f erigon-node
docker-compose logs -f nethermind-node
docker-compose logs -f reth-node
```

---

## Cross-Client Communication

### Adding Peers Between Clients

To ensure cross-client connectivity, add each client as a peer to the others:

```bash
#!/bin/bash
# add-cross-client-peers.sh

# Get enode IDs
GETH_ENODE=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' | \
  jq -r '.result.enode')

ERIGON_ENODE=$(curl -s -X POST http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' | \
  jq -r '.result.enode')

NETHERMIND_ENODE=$(curl -s -X POST http://localhost:8558 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' | \
  jq -r '.result.enode')

RETH_ENODE=$(curl -s -X POST http://localhost:7073 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' | \
  jq -r '.result.enode')

echo "Geth Enode: $GETH_ENODE"
echo "Erigon Enode: $ERIGON_ENODE"
echo "Nethermind Enode: $NETHERMIND_ENODE"
echo "Reth Enode: $RETH_ENODE"

# Add peers (example: add Erigon to Geth)
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addTrustedPeer\",\"params\":[\"$ERIGON_ENODE\"],\"id\":1}"

# Add Geth to Erigon (use port 30304 for XDC compatibility!)
ERIGON_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' xdc-erigon)
GETH_ENODE_MODIFIED=$(echo $GETH_ENODE | sed "s/@[^:]*:/@${ERIGON_IP}:/")
curl -X POST http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addTrustedPeer\",\"params\":[\"$GETH_ENODE_MODIFIED\"],\"id\":1}"
```

### Important: Erigon P2P Port Compatibility

**⚠️ CRITICAL:** Erigon uses TWO P2P ports:

- **Port 30304 (eth/63)**: Compatible with XDC geth nodes
- **Port 30311 (eth/68)**: NOT compatible with XDC geth nodes

**Always use port 30304** when connecting Erigon to other XDC clients.

---

## Monitoring Multi-Client Deployments

### SkyNet Integration

Each client should report to SkyNet with client-specific metadata:

```typescript
interface ClientMetadata {
  clientType: 'geth' | 'erigon' | 'nethermind' | 'reth';
  clientVersion: string;
  rpcPort: number;
  p2pPort: number;
  syncMode: 'full' | 'fast' | 'snap' | 'archive';
  chainDataSize: number;
  databaseSize: number;
}
```

### Cross-Client Block Verification

```bash
#!/bin/bash
# verify-cross-client-consensus.sh

RPC_ENDPOINTS=(
  "http://localhost:8545"   # Geth
  "http://localhost:8547"   # Erigon
  "http://localhost:8558"   # Nethermind
  "http://localhost:7073"   # Reth
)

CLIENT_NAMES=(
  "Geth"
  "Erigon"
  "Nethermind"
  "Reth"
)

echo "Cross-Client Block Verification"
echo "================================"

# Get latest block from each client
for i in "${!RPC_ENDPOINTS[@]}"; do
  endpoint="${RPC_ENDPOINTS[$i]}"
  name="${CLIENT_NAMES[$i]}"
  
  result=$(curl -s -X POST "$endpoint" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}')
  
  block_number=$(echo "$result" | jq -r '.result.number' | xargs printf '%d')
  block_hash=$(echo "$result" | jq -r '.result.hash')
  
  echo "$name: Block $block_number, Hash $block_hash"
done

# Compare hashes (simplified - would need more robust comparison)
echo ""
echo "Checking for divergences..."
```

---

## Troubleshooting

### Port Conflicts

**Symptom:** `bind: address already in use`

**Resolution:**
```bash
# Find processes using ports
sudo lsof -i :8545
sudo lsof -i :8547
sudo lsof -i :8558
sudo lsof -i :7073

# Stop conflicting services
sudo systemctl stop xdc-node  # If running native service

# Or use different ports in docker-compose.yml
```

### Memory Issues

**Symptom:** OOM kills, container restarts

**Resolution:**
```bash
# Check memory usage
docker stats

# Adjust memory limits in docker-compose.yml
services:
  geth-node:
    deploy:
      resources:
        limits:
          memory: 8G
        reservations:
          memory: 4G
```

### Disk Space

**Symptom:** `no space left on device`

**Resolution:**
```bash
# Check disk usage
df -h
du -sh */data

# Prune old data (WARNING: Requires resync)
docker-compose stop
docker-compose rm
rm -rf */data/*
docker-compose up -d
```

### Sync Issues

**Symptom:** Clients stuck at different block heights

**Resolution:**
```bash
# Check sync status for each client
curl -X POST http://localhost:8545 -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

# Check peer count
curl -X POST http://localhost:8545 -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'

# Restart specific client
docker-compose restart geth-node
```

---

## References

- [XDC Node Setup README](./README.md)
- [Erigon Client Guide](./docs/ERIGON.md)
- [XDPoS 2.0 Monitoring Guide](./docs/XDPoS2_MONITORING.md)
- [SkyNet Dashboard Documentation](../XDCNetOwn/README.md)

---

*Document Version: 1.0*  
*Last Updated: February 27, 2026*
