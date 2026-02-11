# Troubleshooting Guide

Common issues and solutions for XDC Network nodes.

---

## Table of Contents

1. [Node Not Syncing](#1-node-not-syncing)
2. [No Peers](#2-no-peers)
3. [High Disk Usage](#3-high-disk-usage)
4. [Memory Issues](#4-memory-issues)
5. [Port Conflicts](#5-port-conflicts)
6. [Docker Issues](#6-docker-issues)
7. [RPC Connection Issues](#7-rpc-connection-issues)

---

## 1. Node Not Syncing

### Symptoms
- Block height stays at 0 or doesn't increase
- Sync status shows "syncing" for extended period
- `eth_syncing` returns `true` indefinitely

### Diagnostics

```bash
# Check sync status
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' | jq

# Check current block
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq

# Check peer count
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' | jq

# View node logs
docker logs xdc-node --tail 100 -f
```

### Solutions

**1. Check Network Connectivity**
```bash
# Test P2P port connectivity
nc -zv localhost 30303

# Check firewall rules
ufw status verbose

# Verify bootnodes are reachable
telnet 5.189.144.192 30303
```

**2. Reset Sync (Last Resort)**
```bash
# Stop node
docker compose -f /opt/xdc-node/docker/docker-compose.yml stop xdc-node

# Backup chain data
cp -r /root/xdcchain/XDC/chaindata /root/xdcchain/XDC/chaindata.backup.$(date +%Y%m%d)

# Remove chain data (WARNING: Full resync required!)
rm -rf /root/xdcchain/XDC/chaindata/*

# Restart node
docker compose -f /opt/xdc-node/docker/docker-compose.yml start xdc-node
```

**3. Increase Peer Count**
```bash
# Edit config to increase max peers
sed -i 's/MAX_PEERS=.*/MAX_PEERS=50/' /opt/xdc-node/configs/node.env

# Restart node
docker compose -f /opt/xdc-node/docker/docker-compose.yml restart xdc-node
```

---

## 2. No Peers

### Symptoms
- Peer count is 0 or very low (<3)
- Node appears isolated
- Sync progress stalls

### Diagnostics

```bash
# Check peer count
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' | jq

# Check network interfaces
ip addr show

# Check if P2P port is listening
ss -tlnp | grep 30303

# Check firewall status
ufw status
iptables -L -n | grep 30303
```

### Solutions

**1. Verify Firewall Rules**
```bash
# Allow XDC P2P ports
ufw allow 30303/tcp comment "XDC P2P"
ufw allow 30303/udp comment "XDC P2P Discovery"
ufw reload
```

**2. Check Port Forwarding (if behind NAT)**
```bash
# Verify NAT configuration
docker exec xdc-node XDC --nat extip:$(curl -s ifconfig.me)
```

**3. Add Static Peers**
```bash
# Edit docker-compose.yml to add static nodes:
# --bootnodes "enode://..."
```

**4. Check for IP Blacklisting**
```bash
# Check if your IP is rate-limited
iptables -L -n | grep DROP

# Check fail2ban status
fail2ban-client status
```

---

## 3. High Disk Usage

### Symptoms
- Disk usage >85%
- Node performance degradation
- Potential crashes

### Diagnostics

```bash
# Check disk usage
df -h

# Check XDC data size
du -sh /root/xdcchain/XDC/*

# Find large files
find /root/xdcchain -type f -size +1G -exec ls -lh {} \;

# Check log sizes
du -sh /var/log/*
docker system df
```

### Solutions

**1. Prune Old Data (Full Nodes)**
```bash
# Prune ancient chain segments (requires node stop)
docker compose -f /opt/xdc-node/docker/docker-compose.yml stop xdc-node

# Run prune (if using geth-based client)
# Note: XDC doesn't support standard pruning, consider:
# - Switching to snap sync mode for resync
# - Using lighter client
```

**2. Enable Log Rotation**
```bash
# Docker log rotation should already be configured
# Verify in docker-compose.yml:
grep -A5 logging /opt/xdc-node/docker/docker-compose.yml
```

**3. Clean Docker Resources**
```bash
# Remove unused containers
docker container prune -f

# Remove unused images
docker image prune -af

# Remove unused volumes (WARNING: Check first!)
docker volume prune -f
```

**4. Move Data to Larger Disk**
```bash
# Mount new disk
mount /dev/sdb1 /mnt/xdc-data

# Sync data
rsync -avP /root/xdcchain/ /mnt/xdc-data/

# Update mount
umount /mnt/xdc-data
mount /dev/sdb1 /root/xdcchain
```

---

## 4. Memory Issues

### Symptoms
- OOM (Out of Memory) kills
- High swap usage
- Slow performance

### Diagnostics

```bash
# Check memory usage
free -h

# Check swap usage
swapon -s

# Check memory by process
ps aux --sort=-%mem | head -20

# Check OOM kills
dmesg | grep -i "out of memory"

# Check container memory limits
docker stats --no-stream
```

### Solutions

**1. Increase Swap (Temporary)**
```bash
# Create swap file
fallocate -l 8G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Make permanent
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

**2. Reduce Cache Size**
```bash
# Edit node config
sed -i 's/CACHE_SIZE=.*/CACHE_SIZE=2048/' /opt/xdc-node/configs/node.env

# Restart node
docker compose -f /opt/xdc-node/docker/docker-compose.yml restart xdc-node
```

**3. Add More RAM**
Recommended RAM by node type:
- Full Node: 32GB
- Archive Node: 64GB
- RPC Node: 32GB

**4. Optimize System**
```bash
# Reduce vm.swappiness
echo 'vm.swappiness = 10' >> /etc/sysctl.conf
sysctl -p

# Clear caches (temporary)
echo 1 > /proc/sys/vm/drop_caches
```

---

## 5. Port Conflicts

### Symptoms
- "bind: address already in use" errors
- Services fail to start
- Connection refused errors

### Diagnostics

```bash
# Check listening ports
ss -tlnp

# Find process using port
lsof -i :30303
lsof -i :8545
lsof -i :8546

# Check Docker port mappings
docker ps --format "table {{.Names}}\t{{.Ports}}"
```

### Solutions

**1. Change Conflicting Port**
```bash
# Edit docker-compose.yml to use different ports
# Example: Change RPC port from 8545 to 18545
sed -i 's/8545:8545/18545:8545/' /opt/xdc-node/docker/docker-compose.yml

# Update firewall
ufw allow 18545/tcp
```

**2. Kill Conflicting Process**
```bash
# Find and kill process
kill -9 $(lsof -t -i:8545)
```

**3. Check for Multiple Node Instances**
```bash
# List all XDC processes
ps aux | grep -i xdc

# Stop duplicate containers
docker ps | grep xdc
docker stop <container_id>
```

---

## 6. Docker Issues

### Symptoms
- Containers won't start
- Image pull failures
- Network connectivity issues

### Diagnostics

```bash
# Check Docker status
systemctl status docker

# Check Docker logs
journalctl -u docker -f

# Check disk space for Docker
docker system df

# Verify Docker network
docker network ls
docker network inspect xdc-network
```

### Solutions

**1. Restart Docker**
```bash
systemctl restart docker
```

**2. Reset Docker Network**
```bash
# Remove and recreate network
docker network rm xdc-network
docker compose -f /opt/xdc-node/docker/docker-compose.yml up -d
```

**3. Clean Docker**
```bash
# Remove all stopped containers
docker container prune -f

# Remove unused networks
docker network prune -f

# Restart with clean state
docker compose -f /opt/xdc-node/docker/docker-compose.yml down
docker compose -f /opt/xdc-node/docker/docker-compose.yml up -d
```

**4. Fix Permission Issues**
```bash
# Fix Docker socket permissions
chmod 666 /var/run/docker.sock

# Or add user to docker group
usermod -aG docker $USER
```

---

## 7. RPC Connection Issues

### Symptoms
- Cannot connect to RPC endpoint
- Connection refused errors
- Timeouts

### Diagnostics

```bash
# Test RPC endpoint
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}'

# Check if port is listening locally
ss -tlnp | grep 8545

# Check from remote (should fail if properly secured)
curl -X POST http://<server-ip>:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}'
```

### Solutions

**1. Verify RPC is Enabled**
```bash
# Check node is started with RPC flags
docker logs xdc-node | grep -i "rpc"
```

**2. Use SSH Tunnel for Remote Access**
```bash
# Create secure tunnel
ssh -L 8545:localhost:8545 root@your-server -p 12141

# Then use localhost:8545 locally
```

**3. Configure RPC CORS (if needed)**
```bash
# Edit docker-compose.yml to add:
# --rpccorsdomain "https://your-domain.com"
```

**4. Check Firewall**
```bash
# Ensure RPC is NOT exposed publicly
ufw status | grep 8545

# Should show no rules, or only local access
```

---

## Quick Reference Commands

```bash
# Restart all services
docker compose -f /opt/xdc-node/docker/docker-compose.yml restart

# View all logs
docker compose -f /opt/xdc-node/docker/docker-compose.yml logs -f

# Check node status
curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' | jq

# Health check
/opt/xdc-node/scripts/node-health-check.sh

# Run security hardening
/opt/xdc-node/scripts/security-harden.sh
```

---

## Getting Help

If issues persist:

1. Check logs: `/var/log/xdc-*.log`
2. Run health check: `/opt/xdc-node/scripts/node-health-check.sh --full`
3. Review [XDC Documentation](https://docs.xdc.community/)
4. Open an issue: https://github.com/AnilChinchawale/XDC-Node-Setup/issues
