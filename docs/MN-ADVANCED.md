# XDC Advanced Masternode Guide

> Complete guide for advanced masternode operations including reward tracking, clustering, and stake management

**Author:** anilcinchawale \<anil24593@gmail.com\>  
**Version:** 2.1.0  
**Last Updated:** February 11, 2026

---

## Table of Contents

1. [Reward Tracking Guide](#reward-tracking-guide)
2. [Cluster Setup](#cluster-setup)
3. [Auto-Compound Setup](#auto-compound-setup)
4. [Tax Reporting Guide](#tax-reporting-guide)
5. [ROI Optimization Strategies](#roi-optimization-strategies)

---

## Reward Tracking Guide

### Overview

The XDC Masternode Rewards System tracks historical rewards, calculates APY, and provides detailed analytics on your masternode performance.

### Features

- **Daily/Weekly/Monthly summaries** of XDC earned
- **APY calculation** based on actual rewards vs expected
- **Missed block detection** and reporting
- **Slashing event tracking**
- **Export capabilities** (CSV, JSON)
- **SQLite database** for historical data

### Quick Start

```bash
# Show current reward summary
xdc rewards

# Show reward history for last 30 days
xdc rewards history --days 30

# Calculate APY
xdc rewards apy

# Show missed blocks report
xdc rewards missed

# Export to CSV
xdc rewards export csv
```

### Database Schema

Rewards are stored in `/var/lib/xdc-node/rewards.db` with the following tables:

| Table | Description |
|-------|-------------|
| `rewards` | Individual reward events |
| `missed_blocks` | Missed block records |
| `slashing_events` | Slashing/penalty events |
| `apy_history` | Historical APY calculations |
| `delegations` | Stake delegation records |

### Alert Configuration

Add to your notification config to receive reward alerts:

```bash
# Notify when rewards are below expected
xdc notify --send "Reward below expected threshold" --level warning

# Notify on slashing events
xdc notify --send "Masternode slashing detected" --level critical
```

---

## Cluster Setup

### Overview

Masternode clustering provides high availability (HA) for your XDC masternode by allowing automatic failover between multiple nodes.

### Architecture

```
┌─────────────────┐         ┌─────────────────┐
│  Primary Node   │◄────────│  Backup Node 1  │
│  (Active)       │   Sync  │  (Standby)      │
│                 │         │                 │
│  - Signs blocks │         │  - Synced       │
│  - Rewards      │         │  - Ready        │
└────────┬────────┘         └─────────────────┘
         │
         │                  ┌─────────────────┐
         │                  │  Backup Node 2  │
         └─────────────────►│  (Standby)      │
             Heartbeat      │                 │
                            │  - Synced       │
                            │  - Ready        │
                            └─────────────────┘
```

### Requirements

- Minimum 2 nodes (1 primary + 1 backup)
- All nodes must have identical hardware specs
- SSH key-based authentication between nodes
- Shared keystore for masternode keys

### Step-by-Step Setup

#### 1. Initialize Cluster

On your primary node:

```bash
# Initialize cluster with custom ID
xdc cluster init --cluster-id xdc-mn-prod-001

# Or use auto-generated ID
xdc cluster init
```

This creates:
- `/etc/xdc-node/cluster.conf` - Cluster configuration
- `/var/lib/xdc-node/cluster/` - Cluster state files
- `/etc/xdc-node/cluster-keys/` - Shared keystore directory

#### 2. Add Backup Nodes

```bash
# Add a backup node
xdc cluster add-node 192.168.1.100 --user xdc

# Add with specific SSH key
xdc cluster add-node 192.168.1.101 --user xdc --ssh-key /path/to/key
```

#### 3. Configure SSH Keys

Ensure passwordless SSH works between all nodes:

```bash
# Generate key if not exists
ssh-keygen -t ed25519 -f ~/.ssh/xdc_cluster

# Copy to backup nodes
ssh-copy-id -i ~/.ssh/xdc_cluster.pub xdc@192.168.1.100
ssh-copy-id -i ~/.ssh/xdc_cluster.pub xdc@192.168.1.101

# Update cluster config
xdc cluster config set SSH_KEY_PATH /home/xdc/.ssh/xdc_cluster
```

#### 4. Sync Keystore

```bash
# Sync masternode keys to all nodes
xdc cluster sync-keys
```

This distributes:
- Masternode signing keys
- Node certificates
- Configuration files

#### 5. Promote Primary

```bash
# Set current node as primary
xdc cluster promote $(hostname -I | awk '{print $1}')
```

### Cluster Commands

```bash
# Check cluster status
xdc cluster status

# Check health of all nodes
xdc cluster health

# Manual failover to specific node
xdc cluster failover --node 192.168.1.100

# Remove a node
xdc cluster remove-node 192.168.1.100

# View configuration
xdc cluster config
```

### Health Check & Auto-Failover

The cluster includes automatic health monitoring:

```bash
# Check health (runs automatically via cron)
xdc cluster health

# View health check logs
tail -f /var/log/xdc-node/cluster-health.log
```

**Failover Logic:**
- Primary sends heartbeat every 30 seconds
- Backup promotes itself if 3 consecutive heartbeats missed
- Automatic key activation on new primary
- Notification sent on failover

### Cluster Security

1. **Encrypted Key Transfer**: Keys are transferred using AES-256-GCM encryption
2. **SSH Hardening**: Use dedicated SSH keys with restricted permissions
3. **Network Isolation**: Cluster communication should be on private network
4. **Access Control**: Limit cluster management to specific users

---

## Auto-Compound Setup

### Overview

Auto-compounding automatically restakes your rewards, increasing your total stake and compounding returns over time.

### How It Works

1. Rewards accumulate in your masternode address
2. When rewards exceed the threshold, they are automatically restaked
3. Increased stake = increased rewards in next epoch

### Enabling Auto-Compound

```bash
# Enable with default threshold (1000 XDC)
xdc stake compound --enable

# Enable with custom threshold
xdc stake compound --enable --threshold 5000

# Check status
xdc stake compound-status

# Trigger manually
xdc stake compound-now
```

### Threshold Recommendations

| Stake Size | Recommended Threshold | Compounding Frequency |
|------------|----------------------|----------------------|
| 10M XDC | 500 XDC | Daily |
| 20M XDC | 1000 XDC | Daily |
| 50M XDC | 2500 XDC | Every 2-3 days |
| 100M+ XDC | 5000 XDC | Weekly |

**Note:** Consider gas fees when setting threshold. XDC has very low fees (~0.000021 XDC per transaction).

### Compounding Schedule

Auto-compound runs via cron every hour:

```bash
# Check if cron job exists
crontab -l | grep compound

# Expected output:
# 0 * * * * /opt/xdc-node/scripts/stake-manager.sh --compound-now > /dev/null 2>&1
```

### Disabling Auto-Compound

```bash
xdc stake compound --disable
```

---

## Tax Reporting Guide

### Overview

The tax reporting feature generates CSV exports suitable for tax filing, including reward history with USD valuations.

### Generating Tax Reports

```bash
# Generate report for current year
xdc stake tax-report

# Generate for specific year
xdc stake tax-report --year 2025

# Save to specific file
xdc stake tax-report --year 2025 --output xdc-taxes-2025.csv
```

### Report Format

The generated CSV includes:

| Column | Description |
|--------|-------------|
| Date | Timestamp of reward |
| Block | Block number |
| Amount (XDC) | Raw XDC amount |
| Amount (USD) | USD value at time of receipt |
| Type | Reward type (block, epoch, etc.) |
| Cost Basis | 0 for rewards (income) |
| Gain/Loss | USD value (same as Amount USD) |

### Tax Treatment Notes

**General Guidelines (consult a tax professional):**

1. **Staking Rewards**: Treated as ordinary income at fair market value when received
2. **Cost Basis**: FMV at time of receipt becomes your cost basis
3. **Capital Gains**: Selling rewards later triggers capital gains/losses
4. **Record Keeping**: Keep records for at least 7 years

### Example Tax Calculation

```
Received: 100 XDC when price was $0.03
Income: $3.00 (report as ordinary income)
Cost Basis: $0.03 per XDC

Later sold 100 XDC when price was $0.05
Proceeds: $5.00
Cost Basis: $3.00
Capital Gain: $2.00 (long-term or short-term depending on holding period)
```

### Cost Basis Tracking

```bash
# View your cost basis
xdc stake cost-basis
```

This shows:
- Initial stake amount
- Total rewards received
- Average cost basis per XDC

---

## ROI Optimization Strategies

### Understanding XDC Masternode ROI

**Base Parameters:**
- Minimum Stake: 10,000,000 XDC
- Expected APY: ~5.5%
- Block Time: 2 seconds
- Epoch Length: 900 blocks (~30 minutes)

### Optimization Strategies

#### 1. Maximize Uptime

```bash
# Monitor uptime
xdc status --watch

# Setup alerting for downtime
xdc notify --test
```

**Impact**: 99.9% vs 95% uptime = ~5% difference in rewards

#### 2. Optimize Network Connectivity

```bash
# Check peer connections
xdc network peers

# Optimize bootnodes
xdc peers optimize
```

**Target**: 25+ peers for optimal block propagation

#### 3. Use Clustering for HA

See [Cluster Setup](#cluster-setup) section.

**Benefit**: Eliminates single point of failure, maximizes uptime

#### 4. Auto-Compound Rewards

See [Auto-Compound Setup](#auto-compound-setup) section.

**Benefit**: Compound interest effect, higher long-term returns

#### 5. Monitor and Avoid Penalties

```bash
# Check penalty status
xdc consensus penalties

# Monitor missed blocks
xdc rewards missed
```

**Penalty Risks:**
- Missed blocks: Temporary reward reduction
- Slashing: Permanent stake reduction

#### 6. Optimal Withdrawal Timing

```bash
# Get withdrawal recommendations
xdc stake withdraw-plan
```

Factors to consider:
- **Epoch boundaries**: Withdraw at epoch start to minimize missed blocks
- **Gas fees**: XDC fees are minimal, but batch withdrawals save transactions
- **Tax year**: Consider timing for tax optimization

### ROI Calculator

Estimate your returns:

```bash
# Estimate 90-day rewards
xdc stake estimate-rewards --days 90
```

**Formula:**
```
Annual Rewards = Stake × APY
Monthly Rewards = Annual Rewards / 12
Daily Rewards = Annual Rewards / 365
```

### Performance Monitoring

Track your masternode performance over time:

```bash
# Compare actual vs expected rewards
xdc rewards compare

# View APY history
xdc rewards apy --days 90
```

### Advanced: Multi-Masternode Strategy

For operators with 20M+ XDC:

1. **Split stake** between multiple masternodes
2. **Geographic distribution** of nodes
3. **Client diversity** (if multiple clients available)

**Benefits:**
- Risk distribution
- Network decentralization
- Potential for higher total rewards

---

## Troubleshooting

### Common Issues

#### Rewards Not Tracking

```bash
# Initialize database
xdc rewards --init-db

# Check database exists
ls -la /var/lib/xdc-node/rewards.db
```

#### Cluster Failover Not Working

```bash
# Check SSH connectivity
xdc cluster health

# Verify heartbeat cron
crontab -l | grep cluster

# Check logs
tail -f /var/log/xdc-node/cluster.log
```

#### Auto-Compound Not Triggering

```bash
# Check compound status
xdc stake compound-status

# Verify cron job
crontab -l | grep compound

# Check database permissions
ls -la /var/lib/xdc-node/rewards.db
```

### Getting Help

- GitHub Issues: https://github.com/AnilChinchawale/XDC-Node-Setup/issues
- Documentation: https://docs.xdcnode.io
- Community Discord: https://discord.gg/xdc

---

## Appendix

### File Locations

| File/Directory | Purpose |
|----------------|---------|
| `/var/lib/xdc-node/rewards.db` | Rewards database |
| `/etc/xdc-node/cluster.conf` | Cluster configuration |
| `/var/log/xdc-node/` | Log files |
| `/opt/xdc-node/scripts/` | Management scripts |

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `XDC_RPC_URL` | RPC endpoint | http://localhost:8545 |
| `XDC_NETWORK` | Network (mainnet/testnet) | mainnet |
| `MASTERNODE_ADDRESS` | Your masternode address | - |
| `REWARD_DB` | Database path | /var/lib/xdc-node/rewards.db |

---

*Maintained by Anil Chinchawale for the XDC Community*
