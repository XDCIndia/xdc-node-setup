# Multi-Client Port Allocation Guide

## 🚨 Issue #356 - Port Management & Isolation

**Priority:** P0 (Critical)  
**Status:** DOCUMENTED  
**Date:** 2026-02-28

### Problem

Running multiple XDC clients on the same machine can cause port conflicts, leading to:
- Node startup failures
- P2P connection issues
- RPC service unavailability
- Docker container crashes

---

## ✅ Standard Port Allocation

### XDC Client Port Matrix

| Client | RPC | WebSocket | P2P Primary | P2P Secondary | Auth RPC | Metrics |
|--------|-----|-----------|-------------|---------------|----------|---------|
| **Geth XDC** | 8545 | 8546 | 30303 | - | 8551 | 6060 |
| **Erigon XDC** | 8547 | 8548 | 30304 | 30311 (sentry) | 8561 | 6061 |
| **Nethermind XDC** | 8558 | 8559 | 30306 | - | - | 6070 |
| **Reth XDC** | 7073 | 7074 | 40303 | - | 8552 | 6071 |

### SkyOne Agent Ports

| Agent | Port | Description |
|-------|------|-------------|
| Geth XDC Agent | 7070 | HTTP API |
| Erigon XDC Agent | 7071 | HTTP API |
| Nethermind XDC Agent | 7072 | HTTP API |
| Reth XDC Agent | 8588 (RPC), 8589 (WS) | HTTP API |

---

## 🔧 Configuration Examples

### Docker Compose - Multi-Client Setup

```yaml
# docker-compose.multi-client.yml
version: '3.8'

services:
  xdc-geth:
    image: xinfinorg/xdposchain:v2.6.8
    container_name: xdc-node-geth-pr5
    environment:
      - HTTP_ADDR=127.0.0.1
      - HTTP_PORT=8545
      - WS_PORT=8546
      - P2P_PORT=30303
    ports:
      - "127.0.0.1:8545:8545"  # RPC (localhost only)
      - "8546:8546"  # WebSocket
      - "30303:30303"  # P2P TCP
      - "30303:30303/udp"  # P2P UDP
      - "6060:6060"  # Metrics
    volumes:
      - geth-data:/work/xdcchain

  xdc-erigon:
    image: anilchinchawale/erix:latest
    container_name: xdc-erigon-mainnet
    environment:
      - HTTP_ADDR=127.0.0.1
      - HTTP_PORT=8547
      - P2P_PORT=30304
      - P2P_PORT_68=30311
    ports:
      - "127.0.0.1:8547:8547"  # RPC (localhost only)
      - "8548:8548"  # WebSocket
      - "30304:30304"  # P2P TCP
      - "30304:30304/udp"  # P2P UDP
      - "30311:30311"  # Sentry P2P
      - "30311:30311/udp"  # Sentry Discovery
      - "6061:6061"  # Metrics
    volumes:
      - erigon-data:/data

  xdc-nethermind:
    image: anilchinchawale/nmx:latest
    container_name: xdc-nethermind-mainnet
    environment:
      - RPC_PORT=8558
      - P2P_PORT=30306
    ports:
      - "127.0.0.1:8558:8558"  # RPC (localhost only)
      - "8559:8559"  # WebSocket
      - "30306:30306"  # P2P TCP
      - "30306:30306/udp"  # P2P UDP
      - "6070:6070"  # Metrics
    volumes:
      - nethermind-data:/nethermind/data

  xdc-reth:
    image: xdc-reth:latest
    container_name: xdc-reth-mainnet
    environment:
      - RPC_PORT=7073
      - P2P_PORT=40303
    ports:
      - "127.0.0.1:7073:7073"  # RPC (localhost only)
      - "7074:7074"  # WebSocket
      - "40303:40303"  # P2P TCP
      - "6071:6071"  # Metrics
    volumes:
      - reth-data:/work/xdcchain

volumes:
  geth-data:
  erigon-data:
  nethermind-data:
  reth-data:
```

---

## 🐳 Environment Variables

### Geth XDC

```bash
# docker-compose.yml or .env
HTTP_ADDR=127.0.0.1
HTTP_PORT=8545
WS_ADDR=127.0.0.1
WS_PORT=8546
P2P_PORT=30303
METRICS_PORT=6060
AUTH_RPC_PORT=8551
```

### Erigon XDC

```bash
HTTP_ADDR=127.0.0.1
HTTP_PORT=8547
WS_PORT=8548
P2P_PORT=30304
P2P_PORT_68=30311  # Sentry port
METRICS_PORT=6061
AUTH_RPC_PORT=8561
```

### Nethermind XDC

```bash
RPC_PORT=8558
WS_PORT=8559
P2P_PORT=30306
METRICS_PORT=6070
```

### Reth XDC

```bash
RPC_PORT=7073
WS_PORT=7074
P2P_PORT=40303
DISCOVERY_PORT=40304
METRICS_PORT=6071
AUTH_RPC_PORT=8552
```

---

## 🔍 Port Conflict Detection

### Check Port Usage

```bash
# Check if a specific port is in use
lsof -i :8545
netstat -tlnp | grep :8545

# Check all XDC-related ports
for port in 8545 8547 8558 7073 30303 30304 30306 40303; do
  echo -n "Port $port: "
  lsof -i :$port >/dev/null 2>&1 && echo "IN USE" || echo "FREE"
done
```

### Automated Port Checker Script

```bash
#!/bin/bash
# scripts/check-ports.sh

declare -A PORTS=(
    ["Geth RPC"]=8545
    ["Geth P2P"]=30303
    ["Erigon RPC"]=8547
    ["Erigon P2P"]=30304
    ["Erigon Sentry"]=30311
    ["Nethermind RPC"]=8558
    ["Nethermind P2P"]=30306
    ["Reth RPC"]=7073
    ["Reth P2P"]=40303
)

echo "=== XDC Multi-Client Port Status ==="
echo ""

conflicts=0
for service in "${!PORTS[@]}"; do
    port=${PORTS[$service]}
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        process=$(lsof -Pi :$port -sTCP:LISTEN 2>/dev/null | tail -1 | awk '{print $1}')
        echo "✗ CONFLICT: $service (port $port) is IN USE by $process"
        ((conflicts++))
    else
        echo "✓ OK: $service (port $port) is FREE"
    fi
done

echo ""
if [[ $conflicts -gt 0 ]]; then
    echo "ERROR: Found $conflicts port conflict(s)"
    echo "Please configure alternative ports in docker-compose.yml or .env"
    exit 1
else
    echo "SUCCESS: No port conflicts detected"
    exit 0
fi
```

---

## 🔥 Firewall Configuration

### Required UFW Rules

```bash
# Geth XDC
sudo ufw allow 30303/tcp comment 'XDC Geth P2P'
sudo ufw allow 30303/udp comment 'XDC Geth Discovery'

# Erigon XDC
sudo ufw allow 30304/tcp comment 'XDC Erigon P2P'
sudo ufw allow 30304/udp comment 'XDC Erigon Discovery'
sudo ufw allow 30311/tcp comment 'XDC Erigon Sentry P2P'
sudo ufw allow 30311/udp comment 'XDC Erigon Sentry Discovery'

# Nethermind XDC
sudo ufw allow 30306/tcp comment 'XDC Nethermind P2P'
sudo ufw allow 30306/udp comment 'XDC Nethermind Discovery'

# Reth XDC
sudo ufw allow 40303/tcp comment 'XDC Reth P2P'

# SSH (custom port)
sudo ufw allow 12141/tcp comment 'SSH'

# RPC ports (DO NOT OPEN - localhost only)
# 8545, 8547, 8558, 7073 should NOT be accessible from internet
```

### Verify Firewall Status

```bash
sudo ufw status numbered | grep -E "8545|8547|8558|7073|30303|30304|30306|40303"
```

---

## ⚠️ Common Port Conflicts

### Scenario 1: Default RPC Port 8545 Conflict

**Problem:** Both Geth XDC and another client try to use 8545

**Solution:**
```yaml
# Keep Geth on default 8545
xdc-geth:
  ports:
    - "127.0.0.1:8545:8545"

# Move other client to alternate port
xdc-erigon:
  environment:
    - HTTP_PORT=8547
  ports:
    - "127.0.0.1:8547:8547"
```

### Scenario 2: P2P Port 30303 Conflict

**Problem:** Multiple clients try to use 30303 for P2P

**Solution:** Each client should use its designated P2P port:
- Geth: 30303
- Erigon: 30304
- Nethermind: 30306
- Reth: 40303

### Scenario 3: Docker Host Network Mode

**Problem:** Using `network_mode: host` causes all conflicts

**Solution:** Use bridge network and explicit port mappings:
```yaml
services:
  xdc-geth:
    network_mode: bridge  # NOT host
    ports:
      - "8545:8545"
      - "30303:30303"
```

---

## 🧪 Testing Multi-Client Setup

### Test RPC Connectivity

```bash
# Test each client RPC
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}'

curl -X POST http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}'

curl -X POST http://localhost:8558 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}'

curl -X POST http://localhost:7073 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}'
```

### Test P2P Connectivity

```bash
# Check peer count for each client
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","id":1}'
```

---

## 📊 Port Usage Monitoring

### Watch for Port Conflicts

```bash
# Monitor port usage every 5 seconds
watch -n 5 'netstat -tlnp | grep -E "8545|8547|8558|7073|30303|30304|30306|40303"'
```

### Prometheus Metrics

All clients expose Prometheus metrics on their designated metrics ports:
- Geth: http://localhost:6060/debug/metrics/prometheus
- Erigon: http://localhost:6061/debug/metrics/prometheus
- Nethermind: http://localhost:6070/metrics
- Reth: http://localhost:6071/metrics

---

## 🚨 Emergency: Forcefully Release Port

```bash
# Find process using port 8545
PID=$(lsof -ti:8545)

# Kill the process (use with caution!)
kill -9 $PID

# Or gracefully stop Docker container
docker stop xdc-node-geth-pr5
```

---

## ✅ Port Allocation Checklist

- [ ] Each client uses unique RPC port
- [ ] Each client uses unique P2P port
- [ ] Firewall allows P2P ports
- [ ] Firewall blocks RPC ports from internet
- [ ] Docker port mappings are correct
- [ ] No conflicts detected with `check-ports.sh`
- [ ] All clients can sync and connect to peers
- [ ] Metrics accessible on designated ports

---

## 📚 References

- [XDC Node Setup - Security Guide](./SECURITY-RPC.md)
- [Docker Port Mapping](https://docs.docker.com/config/containers/container-networking/)
- [UFW Firewall Configuration](https://help.ubuntu.com/community/UFW)
