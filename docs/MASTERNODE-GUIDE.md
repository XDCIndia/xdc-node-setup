# XDC Masternode Guide

> Complete guide for running an XDC Network masternode

---

## Table of Contents

1. [Overview](#overview)
2. [Requirements](#requirements)
3. [Setup Process](#setup-process)
4. [Monitoring Rewards](#monitoring-rewards)
5. [Troubleshooting](#troubleshooting)
6. [Slashing Prevention](#slashing-prevention)
7. [ROI Calculator](#roi-calculator)

---

## Overview

XDC Network uses **XDPoS (XinFin Delegated Proof of Stake)** consensus with 108 masternodes validating transactions. Running a masternode requires:

- **10,000,000 XDC** staked
- **KYC verification** at master.xinfin.network
- **Reliable infrastructure** (99.9%+ uptime)

### Rewards

Masternodes earn rewards for validating blocks:
- **~5-8% APY** on staked XDC
- Rewards distributed every epoch (~30 minutes)
- Higher rewards for consistent uptime

---

## Requirements

### Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **CPU** | 8 cores | 16+ cores |
| **RAM** | 32 GB | 64 GB |
| **Storage** | 1 TB NVMe SSD | 2 TB NVMe SSD |
| **Network** | 1 Gbps | 10 Gbps |
| **IP** | Static IP | Static IP + DDoS protection |

### Software Requirements

- **OS**: Ubuntu 20.04/22.04/24.04 LTS
- **Docker**: 20.10+
- **XDC Client**: Latest version (v2.6.0+)

### Financial Requirements

- **10,000,000 XDC** for staking
- Additional XDC for gas fees (~100 XDC)
- KYC verification completed

---

## Setup Process

### Step 1: System Preparation

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y curl git jq bc netcat

# Clone XDC Node Setup
git clone https://github.com/AnilChinchawale/XDC-Node-Setup.git
cd XDC-Node-Setup
```

### Step 2: Run Masternode Setup Wizard

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Run the masternode setup wizard
sudo ./scripts/masternode-setup.sh
```

The wizard will:
1. Check system requirements
2. Verify your XDC balance (10M+ required)
3. Generate or import keystore
4. Configure coinbase address
5. Set up static peers
6. Guide you through registration

### Step 3: Generate Keystore

If you don't have a keystore:

```bash
# The wizard will generate one, or manually:
XDC account new --datadir /root/xdcchain
```

**⚠️ IMPORTANT**: Back up your keystore file immediately!

Location: `/root/xdcchain/keystore/UTC--<timestamp>--<address>`

### Step 4: Complete KYC

1. Visit [master.xinfin.network](https://master.xinfin.network)
2. Connect your wallet containing 10M+ XDC
3. Complete identity verification
4. Submit required documents
5. Wait for approval (24-72 hours)

### Step 5: Register as Masternode Candidate

**Option A: Via Web Wallet (Recommended)**

1. Visit [wallet.xdc.network](https://wallet.xdc.network)
2. Connect wallet with 10M+ XDC
3. Navigate to "Become a Candidate"
4. Enter your node address (coinbase)
5. Submit 10M XDC stake

**Option B: Via CLI**

```bash
# Attach to node
XDC attach http://localhost:8545

# Unlock account
personal.unlockAccount("0xYOUR_ADDRESS", "YOUR_PASSWORD")

# Send stake to registration contract
eth.sendTransaction({
  from: "0xYOUR_ADDRESS",
  to: "0x0000000000000000000000000000000000000088",
  value: web3.toWei(10000000, "ether"),
  gas: 200000
})
```

### Step 6: Start Your Node

```bash
# Enable and start the validator service
sudo systemctl enable xdc-validator
sudo systemctl start xdc-validator

# Check status
sudo systemctl status xdc-validator
```

### Step 7: Verify Masternode Status

```bash
# Check if your node is in the masternode list
./scripts/xdc-monitor.sh --masternode-status

# Or via RPC
curl -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getMasternodes","params":[],"id":1}' \
  http://localhost:8545 | jq '.result'
```

---

## Monitoring Rewards

### Using XDC Monitor

```bash
# Full masternode monitoring
./scripts/xdc-monitor.sh --masternode-status

# Continuous monitoring
./scripts/xdc-monitor.sh --continuous
```

### Check Rewards via Explorer

1. Visit [explorer.xinfin.network](https://explorer.xinfin.network)
2. Search for your masternode address
3. View "Rewards" tab

### Reward Calculation

Rewards are distributed per epoch (900 blocks, ~30 minutes):

```
Epoch Reward = Block Reward × Blocks Validated
Daily Reward = Epoch Reward × 48 epochs
Monthly Reward = Daily Reward × 30 days
Annual Yield = (Annual Rewards / 10,000,000 XDC) × 100%
```

### Track via CLI

```bash
# Check balance changes
watch -n 60 'curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"0xYOUR_ADDRESS\", \"latest\"],\"id\":1}" \
  http://localhost:8545 | jq -r ".result" | xargs printf "%d\n"'
```

---

## Troubleshooting

### Common Issues

#### Node Not Syncing

```bash
# Check sync status
./scripts/sync-optimizer.sh status

# Optimize peers
./scripts/bootnode-optimize.sh

# Download snapshot if far behind
./scripts/snapshot-manager.sh download mainnet-full
```

#### Low Peer Count

```bash
# Run peer optimizer
./scripts/bootnode-optimize.sh

# Check NAT configuration
./scripts/bootnode-optimize.sh --nat-check
```

#### Missed Blocks

If you're missing blocks (not validating when scheduled):

1. **Check node sync status** - Must be fully synced
2. **Verify uptime** - 99.9%+ required
3. **Check system resources** - CPU/RAM not maxed
4. **Review logs** for errors:

```bash
xdc logs -f | grep -i error
```

#### Node Offline Alert

```bash
# Quick restart
sudo systemctl restart xdc-validator

# Check what went wrong
journalctl -u xdc-validator --since "1 hour ago"
```

### Log Analysis

```bash
# View recent logs
journalctl -u xdc-validator -n 100

# Follow logs in real-time
journalctl -u xdc-validator -f

# Search for errors
journalctl -u xdc-validator | grep -i "error\|fail"
```

---

## Slashing Prevention

XDC uses a reputation-based slashing mechanism. To avoid penalties:

### 1. Maintain High Uptime

- **Target**: 99.9%+ uptime
- **Max downtime**: ~8.7 hours/year
- Use monitoring with instant alerts

```bash
# Set up monitoring
./scripts/xdc-monitor.sh --continuous

# Configure Telegram alerts
sudo nano /etc/xdc-node/notify.conf
```

### 2. Keep Node Synced

- Always within 10 blocks of network head
- Monitor sync status continuously
- Have snapshot ready for quick recovery

### 3. Prevent Double Signing

- **NEVER** run two nodes with the same keystore
- Properly stop old node before migrating
- Use unique keystore per validator

### 4. Keep Software Updated

```bash
# Check for updates weekly
./scripts/version-check.sh

# Update when available
xdc update --apply
```

### 5. Hardware Redundancy

- UPS for power protection
- RAID for disk redundancy
- Multiple network connections

### Slashing Events to Monitor

| Event | Cause | Prevention |
|-------|-------|------------|
| Downtime | Node offline | High availability setup |
| Double Sign | Same key on 2 nodes | Single keystore rule |
| Invalid Block | Software bug | Keep client updated |
| Malicious Vote | Compromised key | Secure keystore |

---

## ROI Calculator

### Expected Returns

Based on 10,000,000 XDC stake at various APY rates:

| APY | Daily | Monthly | Yearly |
|-----|-------|---------|--------|
| 5% | 1,370 XDC | 41,667 XDC | 500,000 XDC |
| 6% | 1,644 XDC | 50,000 XDC | 600,000 XDC |
| 7% | 1,918 XDC | 58,333 XDC | 700,000 XDC |
| 8% | 2,192 XDC | 66,667 XDC | 800,000 XDC |

### Cost Considerations

Monthly infrastructure costs (estimates):

| Provider | Configuration | Monthly Cost |
|----------|---------------|--------------|
| Hetzner AX102 | 32-core, 64GB, 2TB NVMe | ~$100-150 |
| AWS c5.2xlarge | 8-core, 16GB | ~$250-300 |
| DigitalOcean | 16-core, 32GB | ~$320 |
| Self-hosted | Enterprise hardware | Varies |

### Net ROI Calculation

```
Annual Rewards: 600,000 XDC (at 6% APY)
Infrastructure Cost: $1,800/year (~$150/mo)
Net Return (if XDC = $0.05): $30,000 - $1,800 = $28,200/year
Net ROI: 28,200 / (10,000,000 × $0.05) = 5.64%
```

### Break-Even Analysis

At current infrastructure costs (~$150/mo = $1,800/year):

| XDC Price | Annual Rewards Value | Break-even APY |
|-----------|---------------------|----------------|
| $0.01 | $6,000 | 30% |
| $0.05 | $30,000 | 6% |
| $0.10 | $60,000 | 3% |

---

## Quick Reference

### Important Addresses

- **Masternode Registration Contract**: `0x0000000000000000000000000000000000000088`
- **Chain ID (Mainnet)**: 50
- **Chain ID (Testnet)**: 51

### Important URLs

- **Masternode Portal**: [master.xinfin.network](https://master.xinfin.network)
- **Web Wallet**: [wallet.xdc.network](https://wallet.xdc.network)
- **Explorer**: [explorer.xinfin.network](https://explorer.xinfin.network)
- **Documentation**: [docs.xdc.community](https://docs.xdc.community)

### CLI Quick Commands

```bash
# Check masternode status
xdc masternode status

# View rewards
./scripts/xdc-monitor.sh --rewards

# Check sync
xdc sync status

# View logs
xdc logs -f

# Restart node
sudo xdc restart --graceful
```

---

## Support

- **XDC Discord**: [discord.gg/xdc](https://discord.gg/xdc)
- **XDC Telegram**: [t.me/xinfin](https://t.me/xinfin)
- **GitHub Issues**: [XDC-Node-Setup Issues](https://github.com/AnilChinchawale/XDC-Node-Setup/issues)

---

*Last updated: February 11, 2026*
