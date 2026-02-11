# XDC Sync Guide

> Complete guide to syncing XDC nodes efficiently

---

## Table of Contents

1. [Sync Modes Explained](#sync-modes-explained)
2. [Expected Sync Times](#expected-sync-times)
3. [Snapshot Download](#snapshot-download)
4. [Troubleshooting Slow Sync](#troubleshooting-slow-sync)
5. [Disk Space Planning](#disk-space-planning)

---

## Sync Modes Explained

XDC nodes support three synchronization modes:

### Full Sync (Default)

```bash
XDC --syncmode full
```

**Description**: Downloads all blocks and verifies all transactions from genesis.

| Aspect | Details |
|--------|---------|
| **Speed** | Moderate (days to weeks) |
| **Disk Usage** | ~500GB |
| **State Access** | Current state only |
| **Best For** | Standard nodes, validators |

**Pros**:
- Complete verification of chain history
- Can serve current state queries
- Suitable for most use cases

**Cons**:
- Cannot query historical state
- Moderate disk requirements

### Snap Sync

```bash
XDC --syncmode snap
```

**Description**: Downloads recent state snapshot, then syncs remaining blocks.

| Aspect | Details |
|--------|---------|
| **Speed** | Fast (hours) |
| **Disk Usage** | ~300GB |
| **State Access** | Current state only |
| **Best For** | RPC nodes, quick setup |

**Pros**:
- Fastest sync method
- Lowest disk usage
- Good for testing/development

**Cons**:
- Cannot verify full history
- No historical state queries

### Archive Sync

```bash
XDC --syncmode full --gcmode archive
```

**Description**: Keeps ALL historical state for every block.

| Aspect | Details |
|--------|---------|
| **Speed** | Slowest (weeks) |
| **Disk Usage** | 1-2TB+ |
| **State Access** | Full history |
| **Best For** | Explorers, indexers, analytics |

**Pros**:
- Can query state at any historical block
- Required for `debug_*` and `trace_*` methods
- Essential for block explorers

**Cons**:
- Massive disk requirements
- Slowest sync time
- Highest hardware costs

### Mode Comparison

| Feature | Snap | Full | Archive |
|---------|------|------|---------|
| Sync Time | Hours | Days | Weeks |
| Disk Space | 300GB | 500GB | 1-2TB+ |
| eth_call (latest) | ✅ | ✅ | ✅ |
| eth_call (historical) | ❌ | ❌ | ✅ |
| debug_traceTransaction | ❌ | ❌ | ✅ |
| Validator Compatible | ⚠️ | ✅ | ✅ |
| RPC Production | ✅ | ✅ | ✅ |
| Explorer/Indexer | ❌ | ❌ | ✅ |

---

## Expected Sync Times

Sync times vary based on hardware and network conditions:

### From Genesis (No Snapshot)

| Sync Mode | Hardware Class | Estimated Time |
|-----------|----------------|----------------|
| Snap | Budget (4-core, 16GB) | 6-12 hours |
| Snap | Mid (8-core, 32GB) | 2-4 hours |
| Snap | High (16-core, 64GB) | 1-2 hours |
| Full | Budget | 7-14 days |
| Full | Mid | 3-7 days |
| Full | High | 1-3 days |
| Archive | Budget | 4-8 weeks |
| Archive | Mid | 2-4 weeks |
| Archive | High | 1-2 weeks |

### From Snapshot

| Sync Mode | Hardware | Estimated Time |
|-----------|----------|----------------|
| Full (from snapshot) | Any | 30-60 minutes |
| Archive (from snapshot) | Any | 1-2 hours |

### Factors Affecting Sync Speed

1. **Disk I/O**: NVMe SSD is 10x faster than HDD
2. **CPU**: More cores = faster state processing
3. **RAM**: More RAM = better caching
4. **Network**: Bandwidth affects block download
5. **Peers**: More quality peers = faster data

---

## Snapshot Download

Skip weeks of syncing by downloading a chain snapshot.

### Quick Start

```bash
# List available snapshots
./scripts/snapshot-manager.sh list

# Download mainnet full node snapshot
./scripts/snapshot-manager.sh download mainnet-full

# Download testnet snapshot
./scripts/snapshot-manager.sh download testnet-full
```

### Manual Download

If automated script fails:

```bash
# Create data directory
mkdir -p /root/xdcchain

# Download snapshot (mainnet full)
wget -c https://download.xinfin.network/xdcchain-mainnet-full-latest.tar.gz

# Verify checksum
wget https://download.xinfin.network/xdcchain-mainnet-full-latest.tar.gz.sha256
sha256sum -c xdcchain-mainnet-full-latest.tar.gz.sha256

# Extract (takes 30-60 minutes)
tar -xzf xdcchain-mainnet-full-latest.tar.gz -C /root/xdcchain
```

### Verify Snapshot Integrity

```bash
# Run verification
./scripts/snapshot-manager.sh verify /root/xdcchain

# Start node and check first block
XDC --datadir /root/xdcchain console --exec "eth.getBlock(1)"
```

### Available Snapshots

| Network | Type | Size | URL |
|---------|------|------|-----|
| Mainnet | Full | ~250GB | `https://download.xinfin.network/xdcchain-mainnet-full-latest.tar.gz` |
| Mainnet | Archive | ~500GB | `https://download.xinfin.network/xdcchain-mainnet-archive-latest.tar.gz` |
| Testnet | Full | ~50GB | `https://download.xinfin.network/xdcchain-testnet-full-latest.tar.gz` |

---

## Troubleshooting Slow Sync

### Check Current Status

```bash
# Get sync status with ETA
./scripts/sync-optimizer.sh status

# Watch sync progress
./scripts/sync-optimizer.sh watch
```

### Common Issues and Solutions

#### 1. Low Peer Count

**Symptoms**: < 10 peers, slow block download

**Solution**:
```bash
# Optimize bootnodes
./scripts/bootnode-optimize.sh

# Check firewall
sudo ufw status
sudo ufw allow 30303/tcp
sudo ufw allow 30303/udp

# Check NAT
./scripts/bootnode-optimize.sh --nat-check
```

#### 2. Disk I/O Bottleneck

**Symptoms**: High disk wait, slow state processing

**Diagnosis**:
```bash
# Check I/O wait
iostat -x 1 5

# Check disk speed
dd if=/dev/zero of=/root/xdcchain/test bs=1G count=1 oflag=dsync
rm /root/xdcchain/test
```

**Solution**:
- Use NVMe SSD (not SATA SSD or HDD)
- Ensure no other I/O-heavy processes
- Consider RAID 0 for performance

#### 3. Memory Pressure

**Symptoms**: OOM kills, swap usage

**Diagnosis**:
```bash
# Check memory
free -h

# Check for swap usage
swapon --show
```

**Solution**:
- Increase RAM (32GB minimum recommended)
- Add swap (temporary):
  ```bash
  sudo fallocate -l 16G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  ```
- Reduce cache size in XDC flags: `--cache 2048`

#### 4. Network Issues

**Symptoms**: Peers connecting/disconnecting, block download stalls

**Solution**:
```bash
# Check network
ping -c 5 8.8.8.8

# Check DNS
nslookup erpc.xinfin.network

# Check port connectivity
nc -zv 54.169.180.136 30303
```

#### 5. Stuck at Specific Block

**Symptoms**: Block height not increasing for hours

**Solution**:
```bash
# Stop node
sudo systemctl stop xdc-node

# Clear peers database
rm -rf /root/xdcchain/XDC/nodes

# Restart with fresh peers
sudo systemctl start xdc-node
```

### Sync Speed Optimization Checklist

- [ ] NVMe SSD with 500GB+ free space
- [ ] 32GB+ RAM
- [ ] 8+ CPU cores
- [ ] 1Gbps+ network
- [ ] Port 30303 open (TCP and UDP)
- [ ] Quality peers (run bootnode-optimize.sh)
- [ ] Latest XDC client version
- [ ] No other resource-intensive processes

---

## Disk Space Planning

### Current Chain Sizes (as of February 2026)

| Data Type | Mainnet | Testnet |
|-----------|---------|---------|
| Full Node | ~500 GB | ~80 GB |
| Archive Node | ~1.5 TB | ~200 GB |
| Ancient Data | ~300 GB | ~50 GB |
| State Trie | ~200 GB | ~30 GB |

### Growth Projections

XDC chain grows at approximately:
- **~2-3 GB/week** for full nodes
- **~10-15 GB/week** for archive nodes

### Recommended Disk Allocation

| Node Type | Minimum | Recommended | 1-Year Comfortable |
|-----------|---------|-------------|-------------------|
| Full Node | 500 GB | 1 TB | 1.5 TB |
| Archive Node | 1.5 TB | 2 TB | 3 TB |
| Validator | 500 GB | 1 TB | 1.5 TB |

### Monitoring Disk Usage

```bash
# Check current usage
df -h /root/xdcchain

# Check chaindata size
du -sh /root/xdcchain/XDC/chaindata

# Set up alerts
./scripts/node-health-check.sh --full

# Disk usage alert threshold (default 85%)
echo "DISK_ALERT_THRESHOLD=85" >> /etc/xdc-node/config
```

### Pruning Options

When running low on disk space:

```bash
# Analyze pruning potential
./scripts/sync-optimizer.sh prune

# Option 1: Re-sync from snapshot (recommended)
./scripts/snapshot-manager.sh download mainnet-full

# Option 2: Manual cleanup (advanced)
# Stop node first!
rm -rf /root/xdcchain/XDC/lightchaindata
rm -rf /root/xdcchain/XDC/nodes
```

### Disk Performance Requirements

| Disk Type | Random Read | Random Write | Suitable? |
|-----------|-------------|--------------|-----------|
| HDD (7200 RPM) | ~100 IOPS | ~100 IOPS | ❌ No |
| SATA SSD | ~50K IOPS | ~50K IOPS | ⚠️ Marginal |
| NVMe SSD | ~500K IOPS | ~400K IOPS | ✅ Yes |
| NVMe RAID 0 | ~1M IOPS | ~800K IOPS | ✅ Excellent |

---

## Quick Reference Commands

```bash
# Check sync status
./scripts/sync-optimizer.sh status

# Watch sync with auto-refresh
./scripts/sync-optimizer.sh watch

# Recommend sync mode based on hardware
./scripts/sync-optimizer.sh recommend

# Download snapshot
./scripts/snapshot-manager.sh download mainnet-full

# Optimize peers
./scripts/bootnode-optimize.sh

# Check disk usage
df -h /root/xdcchain

# Check peer count
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://localhost:8545 | jq -r '.result' | xargs printf "%d\n"
```

---

*Last updated: February 11, 2026*
