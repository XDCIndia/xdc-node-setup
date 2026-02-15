# Troubleshooting Guide for XDC Node Setup

This guide helps you diagnose and resolve common issues with XDC Node Setup.

## Table of Contents

- [Quick Fixes](#quick-fixes)
- [Sync Issues (Bad Blocks / State Root Mismatches)](#sync-issues-bad-blocks--state-root-mismatches)
  - [Issue #30: GCX Bad Block at 166,500](#issue-30-gcx-bad-block-at-166500)
  - [Issue #44: Erigon Bad Block at 1,884,577](#issue-44-erigon-bad-block-at-1884577)
  - [Issue #47: Erigon State Root Mismatches](#issue-47-erigon-state-root-mismatches)
- [Erigon P2P Protocol Issues](#erigon-p2p-protocol-issues)
  - [Issue #15: Protocol Mismatch eth/68 vs eth/62,63](#issue-15-protocol-mismatch-eth68-vs-eth6263)
- [Peer Connection Issues](#peer-connection-issues)
- [Sync Stalls](#sync-stalls)
- [Port Conflicts](#port-conflicts)
- [Docker Issues on macOS](#docker-issues-on-macos)
- [Installation Issues](#installation-issues)
- [Docker Issues](#docker-issues)
- [Network Issues](#network-issues)
- [Performance Issues](#performance-issues)
- [Security Issues](#security-issues)
- [API/RPC Issues](#apirpc-issues)
- [Backup/Restore Issues](#backuprestore-issues)
- [Getting Help](#getting-help)

---

## Quick Fixes

### Reset Node and Resync

If your node is stuck on a bad block or experiencing state root mismatches, the fastest fix is to reset and resync:

```bash
# Using the xdc CLI (recommended)
xdc reset --confirm

# Or manually:
xdc stop
rm -rf mainnet/xdcchain/XDC
xdc start

# For Erigon nodes:
xdc stop --client erigon
rm -rf mainnet/erigon-datadir
xdc start --client erigon
```

### Check Node Status

```bash
# Quick status overview
xdc status

# Detailed health check
xdc health --full

# Watch sync progress
xdc status --watch
```

---

## Sync Issues (Bad Blocks / State Root Mismatches)

### Overview

Bad blocks and state root mismatches are among the most common sync issues on XDC Network. These typically occur due to:

1. **Consensus differences** between client implementations
2. **Snap sync limitations** — State snapshots may have inconsistencies
3. **XDPoS consensus edge cases** at specific block heights
4. **Client version incompatibilities**

### General Solutions

#### Option 1: Clear Data and Resync (Fastest)

```bash
# Stop the node
xdc stop

# Remove chaindata (keep config!)
rm -rf mainnet/xdcchain/XDC

# Restart
xdc start
```

#### Option 2: Use Full Sync Instead of Snap Sync

Edit your start script or docker-compose.yml:

```bash
# For Geth
XDC --syncmode full

# For Erigon (uses staged sync by default)
erigon --chain=xdc --prune=hrtc
```

#### Option 3: Download Fresh Snapshot

```bash
# Download and apply latest snapshot
./scripts/snapshot-manager.sh download mainnet-full

# This wipes existing data and applies fresh snapshot
```

---

### Issue #30: GCX Bad Block at 166,500

**Symptoms:**
```
ERROR[mm-dd|hh:mm:ss] Failed to import block              number=166,500  hash=0x... err="invalid merkle root"
```

**Cause:** Known issue with geth snap sync on XDC where the state root at block 166,500 doesn't match the expected value. This is due to differences in how XDPoS consensus state is calculated during snap sync.

**Solution:**

1. **Reset and resync with full sync:**
```bash
xdc reset --confirm
# Then edit docker-compose.yml or start-node.sh to use --syncmode full
```

2. **Or use snapshot download:**
```bash
./scripts/snapshot-manager.sh download mainnet-full
```

**Prevention:**
- Use `--syncmode full` for validators or production nodes
- Use snapshot downloads for faster initialization
- Keep client updated to latest version

**Status:** Documented workaround. This is an upstream consensus issue being tracked.

---

### Issue #44: Erigon Bad Block at 1,884,577

**Symptoms:**
```
ERROR[mm-dd|hh:mm:ss] Bad block at height 1,884,577      err="invalid state root"
WARN [mm-dd|hh:mm:ss] Staged sync failed                 err="state root mismatch"
```

**Cause:** Known XDPoS consensus validation issue at block 1,884,577 in the Erigon-XDC implementation. The state transition at this block contains edge cases that differ between Erigon and Geth implementations.

**Solution:**

1. **Use the xdc-state-root-bypass branch:**
```bash
# Rebuild Erigon with the bypass branch
cd erigon-xdc
git checkout xdc-state-root-bypass
make erigon

# Restart node
xdc restart --client erigon
```

2. **Or reset and resync from snapshot:**
```bash
xdc reset --client erigon --confirm
./scripts/snapshot-manager.sh download mainnet-erigon
```

**Prevention:**
- Use the `xdc-state-root-bypass` branch for Erigon nodes
- Monitor [erigon-xdc repository](https://github.com/AnilChinchawale/erigon-xdc) for updates

**Status:** Upstream erigon-xdc issue. The state root bypass branch handles this.

---

### Issue #47: Erigon State Root Mismatches During Sync

**Symptoms:**
```
WARN [mm-dd|hh:mm:ss] State root mismatch                expected=0x... got=0x...
WARN [mm-dd|hh:mm:ss] Continuing with bypass...          
```

**Cause:** Erigon and Geth calculate state differently in some XDPoS consensus edge cases. This results in state root mismatch warnings during sync.

**What happens:**
- State root mismatch is logged as a warning
- Sync continues to the next block (bypass enabled for XDPoS)
- State reconciles at next checkpoint

**Solution:**

1. **Use the state root bypass branch (RECOMMENDED):**
```bash
git clone https://github.com/AnilChinchawale/erigon-xdc.git
cd erigon-xdc
git checkout xdc-state-root-bypass
make erigon
```

2. **Monitor sync progress:**
```bash
# State root mismatches are logged but sync continues
xdc logs --follow | grep -i "state root"

# Check if blocks are still importing
xdc status
```

3. **If sync stalls completely, reset:**
```bash
xdc reset --client erigon --confirm
```

**Explanation:**

State root mismatches in Erigon-XDC are **bypassed by design** for XDPoS chains. The node will:
- Log the mismatch as a warning
- Continue syncing to the next block
- Attempt to reconcile state at the next checkpoint

This is being tracked upstream and will be resolved when XDPoS consensus state calculation is fully standardized.

**Status:** Expected behavior. Use `xdc-state-root-bypass` branch.

---

## Erigon P2P Protocol Issues

### Issue #15: Protocol Mismatch eth/68 vs eth/62,63

**Symptoms:**
```
WARN [mm-dd|hh:mm:ss] Peer rejected                     err="protocol mismatch: peer only supports [eth/62 eth/63], we require [eth/68]"
WARN [mm-dd|hh:mm:ss] Failed to add peer                err="incompatible P2P protocol"
```

**Cause:** XDC geth nodes only support `eth/62`, `eth/63`, and `eth/100` (XDPoS) protocols. They do not support `eth/68` which is used by standard Ethereum nodes.

**Solution (RESOLVED):**

Erigon-XDC now uses a **dual-sentry architecture** to handle this:

| Sentry | Port | Protocol | Purpose |
|--------|------|----------|---------|
| Sentry 1 | **30304** | **eth/63** | XDC-compatible (connect to XDC geth nodes) |
| Sentry 2 | 30311 | eth/68 | Standard Ethereum (future compatibility) |

**To connect Erigon to XDC peers:**

```bash
# 1. Get your Erigon enode (use port 30304!)
curl -s -X POST http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' \
  | jq -r '.result.enode' \
  | sed 's/\[::\]/YOUR_PUBLIC_IP/' \
  | sed 's/:30311/:30304/'

# 2. Add Erigon as trusted peer from your XDC geth node:
curl -X POST http://GETH_RPC:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "method":"admin_addTrustedPeer",
    "params":["enode://...YOUR_ENODE...:30304"],
    "id":1
  }'
```

**Verification:**
```bash
# Check peer connections
xdc peers

# Verify eth/63 sentry is connected to XDC peers
curl -s -X POST http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"admin_peers","params":[],"id":1}' \
  | jq '.result[] | {name, caps, addr: .network.remoteAddress}'
```

**Status:** RESOLVED. Dual-sentry architecture handles this automatically.

---

## Peer Connection Issues

### Low Peer Count (< 5 peers)

**Diagnosis:**
```bash
# Check peer count
xdc peers

# Or via RPC
curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
```

**Solutions:**

1. **Inject peers manually:**
```bash
xdc addpeers
```

2. **Optimize bootnodes:**
```bash
./scripts/bootnode-optimize.sh
```

3. **Add specific peers:**
```bash
# From XDC geth node, add Erigon as trusted peer
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "method":"admin_addTrustedPeer",
    "params":["enode://..."],
    "id":1
  }'
```

4. **Check firewall:**
```bash
sudo ufw status
sudo ufw allow 30303/tcp
sudo ufw allow 30303/udp
sudo ufw allow 30304/tcp  # For Erigon eth/63
sudo ufw allow 30304/udp
```

### Peers Keep Disconnecting

**Causes & Solutions:**

1. **Clock drift:**
```bash
# Sync system clock
sudo apt-get install -y ntp
sudo systemctl enable ntp
sudo systemctl restart ntp
```

2. **NAT issues:**
```bash
# Check NAT configuration
./scripts/bootnode-optimize.sh --nat-check
```

3. **Protocol mismatch** (Erigon only):
- Ensure XDC peers connect to port 30304 (eth/63), not 30311 (eth/68)
- See [Issue #15](#issue-15-protocol-mismatch-eth68-vs-eth6263)

---

## Sync Stalls

### Node Stuck at Specific Block

**Symptoms:** Block height not increasing for > 1 hour

**Diagnosis:**
```bash
# Check if peers are responsive
xdc peers

# Check for errors
xdc logs --follow | grep -i error
```

**Solutions:**

1. **Clear peers database:**
```bash
xdc stop
rm -rf mainnet/xdcchain/XDC/nodes
xdc start
```

2. **Reset and resync:**
```bash
xdc reset --confirm
```

3. **Check for bad block:**
```bash
# If stuck at specific block (e.g., 166,500)
# See Issue #30 for known bad blocks
```

### Sync Very Slow

**Optimization checklist:**

- [ ] NVMe SSD (not SATA SSD or HDD)
- [ ] 32GB+ RAM
- [ ] 8+ CPU cores
- [ ] 1Gbps+ network
- [ ] Port 30303 open (TCP/UDP)
- [ ] Quality peers (run `xdc addpeers`)

**Apply optimizations:**
```bash
# Increase cache (requires restart)
# Edit docker-compose.yml or start-node.sh:
XDC --cache=4096

# Use snapshot
./scripts/snapshot-manager.sh download mainnet-full
```

---

## Port Conflicts

### Port Already in Use

**Symptoms:**
```
Error: listen tcp :8545: bind: address already in use
```

**Solutions:**

1. **Find and kill conflicting process:**
```bash
sudo lsof -i :8545
sudo kill -9 <PID>
```

2. **Use different port:**
```bash
# Edit docker-compose.yml or start-node.sh
# Change port mapping:
ports:
  - "8546:8545"  # Map host 8546 to container 8545
```

3. **Check xdc status auto-detects:**
```bash
# xdc CLI automatically detects port conflicts and offers alternatives
xdc start
```

### Required Ports

| Port | Service | Protocol | Required |
|------|---------|----------|----------|
| 8545 | Geth RPC | HTTP | Yes |
| 8547 | Erigon RPC | HTTP | For Erigon |
| 8546 | WebSocket | WS | Optional |
| 30303 | Geth P2P | TCP/UDP | Yes |
| 30304 | Erigon eth/63 | TCP/UDP | For Erigon |
| 30311 | Erigon eth/68 | TCP/UDP | Optional |

---

## Docker Issues on macOS

### Shared Volume Performance

**Issue:** Very slow I/O on macOS Docker

**Solution:**
```bash
# Use named volumes instead of bind mounts
# In docker-compose.yml:
volumes:
  xdc-data:  # Named volume, not ./mainnet/xdcchain

# Or use virtiofs (Docker Desktop 4.6+)
# Settings -> General -> Use Virtualization framework
# Settings -> Features -> Use VirtioFS
```

### Memory Limits

**Issue:** Docker out of memory

**Solution:**
```bash
# Increase Docker Desktop memory to 8GB+
# Settings -> Resources -> Memory
```

### Port Binding Issues

**Issue:** Cannot bind to privileged ports

**Solution:**
```bash
# Use higher port numbers on host
ports:
  - "18545:8545"  # Instead of 8545:8545
```

---

## Installation Issues

### "Permission denied" when running setup.sh

**Cause:** Script doesn't have execute permissions or user lacks privileges.

**Solution:**
```bash
chmod +x setup.sh
sudo ./setup.sh
```

### "Command not found: docker"

**Cause:** Docker is not installed or not in PATH.

**Solution:**
```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

### "Unsupported OS" error

**Cause:** Operating system not officially supported.

**Solution:**
- Supported: Ubuntu 20.04/22.04/24.04, Debian 11/12, macOS 12+
- For other systems, use Docker deployment method

---

## Docker Issues

### Container fails to start

**Check logs:**
```bash
xdc logs
```

**Common causes:**

1. Port already in use (see [Port Conflicts](#port-conflicts))

2. Volume permissions:
   ```bash
   sudo chown -R $(id -u):$(id -g) ./xdcchain
   ```

3. Out of disk space:
   ```bash
   df -h
   docker system prune -a  # Clean up unused images
   ```

### "No such file or directory" for genesis.json

**Solution:**
```bash
# Ensure proper file structure
mkdir -p mainnet
cp configs/genesis.json mainnet/
```

---

## Network Issues

### Cannot connect to RPC endpoint

**Check:**
```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

**Common fixes:**

1. Check if container is running:
   ```bash
   docker ps | grep xdc-node
   ```

2. Verify port binding:
   ```bash
   docker port xdc-node
   ```

3. Check firewall:
   ```bash
   sudo ufw status
   sudo ufw allow 8545/tcp
   ```

---

## Performance Issues

### High CPU usage

**Diagnosis:**
```bash
# Identify process
ps aux | grep -E "XDC|xdc"

# Check sync status
./scripts/node-health-check.sh --full
```

**Solutions:**

1. Limit CPU usage:
   ```yaml
   # docker-compose.yml
   deploy:
     resources:
       limits:
         cpus: '4.0'
   ```

2. Reduce peer count:
   ```bash
   # In start-node.sh
   --maxpeers 25
   ```

### High memory usage

**Solutions:**

1. Reduce cache size
2. Limit concurrent connections
3. Add swap space (emergency only):
   ```bash
   sudo fallocate -l 8G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

### Disk space issues

**Check:**
```bash
du -sh xdcchain/* | sort -h
```

**Solutions:**

1. Enable pruning (if not archive node)
2. Move data to larger disk
3. Set up automated cleanup:
   ```bash
   ./scripts/cleanup-logs.sh
   ```

---

## Security Issues

### SSH brute force attacks

**Symptoms:**
- Many failed login attempts in `/var/log/auth.log`

**Solution:**
```bash
# Run security hardening
sudo ./scripts/security-harden.sh

# Check fail2ban status
sudo fail2ban-client status sshd
```

### Unauthorized RPC access

**Symptoms:**
- Unknown transactions
- Unexpected API calls

**Solution:**

1. Enable authentication
2. Bind to localhost only:
   ```yaml
   ports:
     - "127.0.0.1:8545:8545"
   ```
3. Use firewall to restrict access

---

## API/RPC Issues

### "Method not found" error

**Cause:** API namespace not enabled

**Solution:**
```bash
# Enable required APIs
# In start-node.sh, add to --rpcapi:
--rpcapi eth,net,web3,admin,debug
```

### CORS errors from browser

**Solution:**
```bash
# Add allowed origins
--rpccorsdomain "http://localhost:3000,https://myapp.com"
```

---

## Backup/Restore Issues

### Backup fails with "permission denied"

**Solution:**
```bash
# Fix permissions
sudo chown -R $(whoami) /opt/xdc-node/backups

# Run backup with sudo
sudo ./scripts/backup.sh create
```

### Restore fails with "corrupted data"

**Causes:**
- Incomplete backup
- Version mismatch
- Wrong network

**Solution:**

1. Verify backup integrity:
   ```bash
   ./scripts/backup.sh verify <backup-file>
   ```

2. Check version compatibility
3. Ensure correct network type

---

## Getting Help

### Collect diagnostic information

```bash
# Run diagnostic script
./scripts/diagnostics.sh

# Or manually collect:
- OS version: lsb_release -a
- Docker version: docker version
- Node logs: xdc logs
- System resources: free -h, df -h
- Network: netstat -tlnp, iptables -L
```

### Community Support

- **Discord:** https://discord.gg/xdc
- **GitHub Issues:** https://github.com/AnilChinchawale/xdc-node-setup/issues
- **Documentation:** https://docs.xdc.network

### Related Issues

- **Issue #30:** [GCX bad block at 166,500](https://github.com/AnilChinchawale/xdc-node-setup/issues/30) — State root mismatch during snap sync
- **Issue #44:** [Erigon bad block at 1,884,577](https://github.com/AnilChinchawale/xdc-node-setup/issues/44) — XDPoS consensus validation
- **Issue #47:** [Erigon state root mismatches](https://github.com/AnilChinchawale/xdc-node-setup/issues/47) — Expected with current implementation
- **Issue #15:** [Erigon P2P protocol mismatch](https://github.com/AnilChinchawale/xdc-node-setup/issues/15) — Resolved with dual-sentry

---

## Quick Reference

### Common Commands

```bash
# Check node status
xdc status

# View logs
xdc logs --follow

# Restart node
xdc restart

# Health check
xdc health --full

# Reset and resync
xdc reset --confirm

# Update node
xdc update
```

### Important File Locations

| File/Directory | Purpose |
|---------------|---------|
| `/opt/xdc-node/` | Installation directory |
| `mainnet/xdcchain/` | Blockchain data (Geth) |
| `mainnet/erigon-datadir/` | Blockchain data (Erigon) |
| `mainnet/.xdc-node/` | Node state and config |
| `logs/` | Log files |

---

*Last updated: February 15, 2026*
