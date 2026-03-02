# Multi-Client Port Allocation Guide

## Overview

Running multiple XDC clients on the same machine requires careful port allocation to avoid conflicts. This guide provides the standard port allocation strategy for running Geth, Erigon, Nethermind, and Reth simultaneously.

## Standard Port Allocation

| Client | P2P Port | RPC HTTP | RPC WS | Metrics | Engine API |
|--------|----------|----------|--------|---------|------------|
| **Geth (Stable)** | 30303 | 8545 | 8546 | 6060 | 8551 |
| **Geth (PR5)** | 30304 | 7070 | 7071 | 6070 | 8552 |
| **Erigon** | 30305 | 7071 | 7072 | 6071 | 8553 |
| **Nethermind** | 30306 | 7072 | 7073 | 6072 | 8554 |
| **Reth** | 40303 | 8588 | 8589 | 6073 | 8555 |

## Docker Compose Configuration

### Multi-Client Setup

Create `docker-compose.multiclient.yml`:

```yaml
version: '3.8'

services:
  # Geth Stable
  xdc-geth-stable:
    image: xinfinorg/xdposchain:v2.6.8
    container_name: xdc-geth-stable
    ports:
      - "30303:30303"      # P2P
      - "30303:30303/udp"  # P2P UDP
      - "8545:8545"        # RPC HTTP
      - "8546:8546"        # RPC WS
      - "6060:6060"        # Metrics
    volumes:
      - ./data/geth-stable:/xdcchain
    command: |
      --networkid 50
      --datadir /xdcchain
      --http --http.addr 0.0.0.0 --http.port 8545
      --ws --ws.addr 0.0.0.0 --ws.port 8546
      --port 30303
    restart: unless-stopped

  # Geth PR5
  xdc-geth-pr5:
    image: xinfinorg/xdposchain:pr5-latest
    container_name: xdc-geth-pr5
    ports:
      - "30304:30304"      # P2P
      - "30304:30304/udp"  # P2P UDP
      - "7070:7070"        # RPC HTTP
      - "7071:7071"        # RPC WS
    volumes:
      - ./data/geth-pr5:/xdcchain
    command: |
      --networkid 50
      --datadir /xdcchain
      --http --http.addr 0.0.0.0 --http.port 7070
      --ws --ws.addr 0.0.0.0 --ws.port 7071
      --port 30304
    restart: unless-stopped

  # Erigon
  xdc-erigon:
    image: anilchinchawale/erix:latest
    container_name: xdc-erigon
    ports:
      - "30305:30305"      # P2P
      - "30305:30305/udp"  # P2P UDP
      - "7071:7071"        # RPC HTTP
      - "7072:7072"        # RPC WS
    volumes:
      - ./data/erigon:/xdcchain
    command: |
      --chain=xdc
      --datadir=/xdcchain
      --http --http.addr=0.0.0.0 --http.port=7071
      --ws --ws.addr=0.0.0.0
      --port=30305
    restart: unless-stopped

  # Nethermind
  xdc-nethermind:
    image: anilchinchawale/nmx:latest
    container_name: xdc-nethermind
    ports:
      - "30306:30306"      # P2P
      - "30306:30306/udp"  # P2P UDP
      - "7072:7072"        # RPC HTTP
      - "7073:7073"        # RPC WS
    volumes:
      - ./data/nethermind:/xdcchain
    environment:
      - NETHERMIND_CONFIG=xdc
      - NETHERMIND_JSONRPCCONFIG_PORT=7072
      - NETHERMIND_NETWORK_DISCOVERYPORT=30306
      - NETHERMIND_NETWORK_P2PPORT=30306
    restart: unless-stopped

  # Reth (Experimental)
  xdc-reth:
    image: xdc/reth:latest
    container_name: xdc-reth
    ports:
      - "40303:40303"      # P2P
      - "40303:40303/udp"  # P2P UDP
      - "8588:8588"        # RPC HTTP
      - "8589:8589"        # RPC WS
    volumes:
      - ./data/reth:/xdcchain
    command: |
      node
      --chain xdc
      --datadir /xdcchain
      --http --http.addr 0.0.0.0 --http.port 8588
      --ws --ws.addr 0.0.0.0 --ws.port 8589
      --port 40303
    restart: unless-stopped
```

## Usage

### Start All Clients

```bash
docker-compose -f docker-compose.multiclient.yml up -d
```

### Start Specific Clients

```bash
# Geth + Erigon only
docker-compose -f docker-compose.multiclient.yml up -d xdc-geth-stable xdc-erigon

# All except Reth
docker-compose -f docker-compose.multiclient.yml up -d xdc-geth-stable xdc-geth-pr5 xdc-erigon xdc-nethermind
```

### Check Status

```bash
docker-compose -f docker-compose.multiclient.yml ps
```

## Port Conflict Detection

### Check for Port Conflicts

```bash
#!/bin/bash
# scripts/check-port-conflicts.sh

PORTS=(30303 30304 30305 30306 40303 8545 7070 7071 7072 8588 8589)

echo "Checking for port conflicts..."
for port in "${PORTS[@]}"; do
    if lsof -i :$port -sTCP:LISTEN >/dev/null 2>&1; then
        process=$(lsof -i :$port -sTCP:LISTEN | tail -1 | awk '{print $1}')
        echo "⚠️  Port $port is already in use by: $process"
    else
        echo "✅ Port $port is available"
    fi
done
```

## Firewall Configuration

### UFW (Ubuntu)

```bash
# Allow multi-client P2P ports
sudo ufw allow 30303:30306/tcp comment 'XDC P2P Geth/Erigon/Nethermind'
sudo ufw allow 30303:30306/udp comment 'XDC P2P Geth/Erigon/Nethermind'
sudo ufw allow 40303/tcp comment 'XDC P2P Reth'
sudo ufw allow 40303/udp comment 'XDC P2P Reth'

# Allow RPC (localhost only recommended)
# sudo ufw allow from 127.0.0.1 to any port 8545:8589 proto tcp
```

## Best Practices

1. **Resource Allocation**
   - Each client needs 4-8GB RAM
   - 500GB-1TB disk space per client
   - Consider using separate disks for optimal I/O

2. **Monitoring**
   - Use different metrics ports (6060, 6070, 6071, 6072, 6073)
   - Integrate with Prometheus for unified monitoring
   - Set up SkyNet agents for each client

3. **High Availability**
   - Use load balancer for RPC endpoints
   - Configure health checks per client
   - Stagger restarts during upgrades

4. **Security**
   - Never expose RPC ports to public internet
   - Use nginx/traefik reverse proxy with authentication
   - Enable firewall rules for P2P ports only

## Troubleshooting

### Port Already in Use

```bash
# Find process using port
lsof -i :30303

# Kill process (if safe)
kill -9 $(lsof -t -i:30303)

# Or change port in docker-compose
```

### Clients Not Peering

```bash
# Check P2P connectivity
docker exec xdc-geth-stable geth attach /xdcchain/geth.ipc --exec 'admin.peers.length'

# Check if ports are open externally
nc -zv YOUR_PUBLIC_IP 30303
```

### High Resource Usage

```bash
# Monitor resource usage per container
docker stats xdc-geth-stable xdc-erigon xdc-nethermind

# Adjust sync mode if needed (--syncmode=snap)
```

## References

- [XDC Network Documentation](https://docs.xdc.network/)
- [Multi-Client Architecture](../docs/ARCHITECTURE.md)
- [SkyOne Agent Setup](../docs/SKYNET-INTEGRATION.md)

---

*Last Updated: 2026-03-02*
*Maintainer: XDC Node Setup Team*
