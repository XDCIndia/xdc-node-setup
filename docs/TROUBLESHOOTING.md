# XDC Node Setup - Troubleshooting Guide

## Quick Diagnostics

### Check Node Status

```bash
xdc status
```

Expected output:
```
✓ XDC Node Status
==================
Status: Running
Client: Geth/v2.6.8-stable
Block Height: 89,234,567
Sync Status: 100% (synced)
Peers: 25 connected
Uptime: 3d 12h 45m
```

### Full Health Check

```bash
xdc health --full
```

## Common Issues

### 1. Node Won't Start

#### Symptom
```
✗ XDC Node is not running
```

#### Diagnosis
```bash
# Check Docker is running
sudo systemctl status docker

# Check port conflicts
sudo ss -tlnp | grep -E '8545|30303|7070'

# View logs
xdc logs --follow
```

#### Solutions

**Docker Not Running:**
```bash
sudo systemctl start docker
sudo systemctl enable docker
```

**Port Conflicts:**
```bash
# Find process using port
sudo lsof -i :8545

# Kill process or change port in .env
sed -i 's/RPC_PORT=8545/RPC_PORT=8546/' mainnet/.xdc-node/.env
```

**Corrupted Data:**
```bash
# Reset chain data (WARNING: Requires re-sync)
xdc stop
sudo rm -rf mainnet/xdcchain/XDC/chaindata
xdc start
```

### 2. Node Won't Sync

#### Symptom
```
Sync Status: 0%
Peers: 0 connected
```

#### Diagnosis
```bash
# Check peer count
xdc peers

# Check sync status
xdc sync

# View network logs
xdc logs | grep -i "peer\|sync"
```

#### Solutions

**No Peers:**
```bash
# Add bootnodes manually
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "admin_addPeer",
    "params": ["enode://..."],
    "id": 1
  }'

# Or restart with fresh peer discovery
xdc stop
rm -rf mainnet/.xdc-node/geth/nodes
xdc start
```

**Slow Sync:**
```bash
# Download snapshot for fast sync
xdc snapshot download --network mainnet
xdc snapshot apply
```

**Firewall Blocking:**
```bash
# Allow P2P ports
sudo ufw allow 30303/tcp
sudo ufw allow 30303/udp
```

### 3. High Resource Usage

#### Symptom
```
CPU: 95%
Memory: 14GB/16GB
```

#### Diagnosis
```bash
# Check resource usage
xdc info

# Monitor in real-time
htop
```

#### Solutions

**Reduce Memory Cache:**
```bash
# Edit config
xdc config set cache 2048
xdc restart
```

**Enable Pruning:**
```bash
xdc config set prune_mode full
xdc restart
```

**Check Disk Space:**
```bash
df -h
# If low, clean up logs
xdc logs --clean
```

### 4. Dashboard Not Accessible

#### Symptom
```
http://localhost:7070 - Connection refused
```

#### Diagnosis
```bash
# Check if dashboard is running
docker ps | grep dashboard

# Check logs
docker logs xdc-agent
```

#### Solutions

**Dashboard Not Running:**
```bash
# Start dashboard
xdc monitor start

# Or restart all services
xdc restart
```

**Port Not Open:**
```bash
# Allow dashboard port
sudo ufw allow 7070/tcp
```

**Check Configuration:**
```bash
# Verify dashboard port
grep DASHBOARD_PORT mainnet/.xdc-node/.env
```

### 5. RPC Connection Refused

#### Symptom
```
curl: (7) Failed to connect to localhost port 8545
```

#### Diagnosis
```bash
# Check RPC is enabled
grep ENABLE_RPC mainnet/.xdc-node/.env

# Check RPC binding
sudo ss -tlnp | grep 8545
```

#### Solutions

**RPC Not Enabled:**
```bash
# Enable RPC
echo "ENABLE_RPC=true" >> mainnet/.xdc-node/.env
xdc restart
```

**RPC Bound to Wrong Interface:**
```bash
# Check binding
grep RPC_ADDR mainnet/.xdc-node/.env

# Should be 127.0.0.1 or 0.0.0.0
# Edit if needed
sed -i 's/RPC_ADDR=.*/RPC_ADDR=127.0.0.1/' mainnet/.xdc-node/.env
xdc restart
```

### 6. SkyNet Integration Issues

#### Symptom
```
SkyNet: Disconnected
Last Heartbeat: Never
```

#### Diagnosis
```bash
# Check SkyNet configuration
cat mainnet/.xdc-node/skynet.conf

# Test SkyNet connection
curl -H "Authorization: Bearer YOUR_API_KEY" \
  https://skynet.xdcindia.com/api/v1/nodes/status
```

#### Solutions

**Missing API Key:**
```bash
# Register with SkyNet
cd docker
./skynet-agent.sh --register
```

**Check Agent Logs:**
```bash
docker logs xdc-monitoring
```

**Re-register:**
```bash
# Force re-registration
rm mainnet/.xdc-node/skynet.json
cd docker
./skynet-agent.sh --register
```

### 7. Multi-Client Issues

#### Erigon P2P Issues

**Symptom:** Erigon not connecting to XDC peers

**Solution:**
```bash
# Ensure using correct port
# Erigon uses port 30304 (eth/63) for XDC peers
# Port 30311 (eth/68) is NOT compatible with XDC

# Check peer connections
curl -X POST http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
```

#### Nethermind Sync Issues

**Symptom:** Nethermind stuck at block 0

**Solution:**
```bash
# Check network ID in config
grep NETWORK mainnet/.xdc-node/.env

# For testnet, ensure APOTHEM_FLAG is set
echo "APOTHEM_FLAG=--apothem" >> mainnet/.xdc-node/.env
xdc restart --client nethermind
```

## Error Messages

### "BAD BLOCK" Error

**Cause:** Database corruption or consensus fork

**Solution:**
```bash
# Stop node
xdc stop

# Remove chain data (keep keystore!)
sudo rm -rf mainnet/xdcchain/XDC/chaindata

# Restart (will re-sync)
xdc start
```

### "Insufficient peers"

**Cause:** Network connectivity or firewall issues

**Solution:**
```bash
# Add static peers
xdc peers add <enode-url>

# Check firewall
sudo ufw status

# Restart with peer discovery
xdc stop
rm -rf mainnet/.xdc-node/geth/nodes
xdc start
```

### "Disk full"

**Cause:** Insufficient disk space

**Solution:**
```bash
# Check disk usage
df -h

# Clean up logs
xdc logs --clean

# Prune database
xdc config set prune_mode full
xdc restart
```

## Performance Tuning

### Optimize for Low Memory (< 8GB)

```bash
# Reduce cache
xdc config set cache 1024

# Reduce max peers
xdc config set max_peers 25

# Enable pruning
xdc config set prune_mode full
xdc restart
```

### Optimize for Fast Sync

```bash
# Use snap sync
xdc config set sync_mode snap

# Download snapshot
xdc snapshot download
xdc snapshot apply
```

### Optimize for Masternode

```bash
# Use full sync
xdc config set sync_mode full

# Increase cache
xdc config set cache 8192

# Increase peers
xdc config set max_peers 50

# Enable all APIs
xdc config set rpc_api "admin,eth,net,web3,XDPoS,debug"
```

## Log Analysis

### View Recent Errors

```bash
xdc logs | grep -i "error\|fatal\|panic"
```

### Monitor Specific Component

```bash
# P2P logs
xdc logs | grep -i "peer\|p2p\|dial"

# Sync logs
xdc logs | grep -i "sync\|import\|download"

# Consensus logs
xdc logs | grep -i "consensus\|vote\|qc"
```

### Export Logs

```bash
# Export last 1000 lines
xdc logs --tail 1000 > xdc-logs-$(date +%Y%m%d).txt

# Export all logs
docker logs xdc-node > xdc-all-logs.txt
```

## Getting Help

### Collect Diagnostics

```bash
# Generate diagnostic report
xdc report > diagnostic-report.txt

# Include:
# - Node status
# - Configuration
# - Recent logs
# - System info
```

### Community Resources

- **GitHub Issues:** https://github.com/AnilChinchawale/xdc-node-setup/issues
- **XDC Documentation:** https://docs.xdc.network
- **XDC Community Discord:** https://discord.gg/xdc

### Reporting Issues

When reporting issues, include:

1. **Node Status:** `xdc status`
2. **Configuration:** `xdc config list`
3. **Logs:** `xdc logs --tail 100`
4. **System Info:** `xdc info`
5. **Error Messages:** Full error text

---

**Document Version:** 1.0.0  
**Last Updated:** February 27, 2026
