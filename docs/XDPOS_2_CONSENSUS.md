# XDPoS 2.0 Consensus Guide

## Overview

XDC Network uses XDPoS 2.0 (XinFin Delegated Proof of Stake version 2.0), a BFT-based consensus mechanism that enables fast finality and high throughput.

## Core Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| **Epoch Length** | 900 blocks | Duration of each consensus epoch (~30 minutes at 2s/block) |
| **Gap Blocks** | 450 blocks | Blocks before epoch end where voting stops |
| **Masternode Set** | Up to 108 | Maximum number of validator masternodes |
| **QC Threshold** | 67% (2/3+1) | Validators needed for Quorum Certificate |
| **Block Time** | 2 seconds | Target time between blocks |
| **Finality** | 1 epoch | Blocks finalized after epoch completion |

## Epoch Structure

Each epoch consists of 900 blocks:

```
Epoch N: Blocks 0-899
├─ Voting Period: Blocks 0-449 (validators vote on blocks)
├─ Gap Period: Blocks 450-899 (no voting, prepare for transition)
└─ Epoch Transition: Block 900 → Epoch N+1 begins

Example:
- Epoch 13717: Blocks 12,345,300 - 12,346,199
  - Voting active: 12,345,300 - 12,345,749
  - Gap blocks: 12,345,750 - 12,346,199
- Epoch 13718: Blocks 12,346,200 - 12,347,099
```

## Gap Blocks Explained

**Why gap blocks exist:**
- Prevents vote aggregation conflicts during epoch transitions
- Gives validators time to prepare for new epoch
- Ensures clean masternode set transitions
- Reduces consensus race conditions

**During gap period (last 450 blocks):**
- ❌ No consensus voting occurs
- ✅ Block production continues normally
- ✅ Transactions processed normally
- ✅ Masternode set prepared for next epoch

## Quorum Certificates (QC)

A Quorum Certificate is formed when 2/3+1 validators sign the same block.

**QC Formation:**
1. Block proposer creates block
2. Validators receive and verify block
3. Validators broadcast vote messages
4. When 67%+ votes received → QC formed
5. Block is finalized

**Monitoring QC Health:**
```bash
# Check recent QCs
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getLatestQCs","params":[],"id":1}'

# Validate consensus parameters
./scripts/validate-consensus.sh
```

## Vote Participation

Masternodes must participate in voting to earn rewards and avoid penalties.

**Vote Lifecycle:**
1. Masternode receives new block
2. Validates block (state transition, signatures)
3. Broadcasts vote message to network
4. Vote included in next QC

**Penalties for non-participation:**
- Missed votes → reduced rewards
- Persistent missed votes → temporary removal from validator set
- Re-inclusion after penalty period expires

## Masternode Requirements

**Hardware:**
- CPU: 4+ cores
- RAM: 16GB+ recommended
- Disk: 500GB+ SSD (full node), 2TB+ (archive)
- Network: 100Mbps+ with low latency

**Staking:**
- Minimum stake: 10,000,000 XDC
- Locked during validation period
- Penalties deducted from stake for misbehavior

**Uptime:**
- 95%+ uptime recommended for consistent rewards
- Monitor with `scripts/node-health-check.sh`

## Monitoring Best Practices

### 1. Epoch Tracking
```bash
# Get current epoch
current_block=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | jq -r '.result')

epoch=$((16#${current_block#0x} / 900))
epoch_position=$((16#${current_block#0x} % 900))

echo "Current epoch: $epoch"
echo "Position in epoch: $epoch_position/900"
```

### 2. Gap Block Detection
```bash
blocks_until_gap=$((450 - (16#${current_block#0x} % 900)))
if [[ $blocks_until_gap -le 0 ]]; then
    echo "Currently in gap period"
else
    echo "Gap period in $blocks_until_gap blocks"
fi
```

### 3. Vote Participation Check
```bash
# Check if your masternode is voting
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getMasternodesByNumber","params":["latest"],"id":1}'
```

## Troubleshooting

### Issue: Node Not Voting

**Symptoms:**
- Masternode shows in list but no votes recorded
- Rewards lower than expected

**Diagnosis:**
```bash
# Check if in masternode set
./scripts/validate-consensus.sh

# Check network connectivity
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
```

**Solutions:**
1. Verify stake amount ≥ 10M XDC
2. Check firewall allows P2P port (30303)
3. Ensure node fully synced
4. Verify enode URL registered correctly

### Issue: Missed Blocks During Gap Period

**This is normal behavior!** Gap blocks (last 450 of each epoch) do not participate in voting. This is intentional.

### Issue: QC Formation Failures

**Symptoms:**
- High timeout certificate count
- Slow finality

**Diagnosis:**
```bash
# Check network latency
ping -c 10 <peer-ip>

# Check system resources
top
df -h
```

**Solutions:**
1. Improve network connectivity
2. Increase hardware resources
3. Optimize database (vacuum, reindex)
4. Check for disk I/O bottlenecks

## Tools

- `scripts/validate-consensus.sh` - Validate XDPoS 2.0 parameters
- `scripts/node-health-check.sh` - Monitor node health
- `scripts/snapshot-download.sh` - Fast sync with snapshots

## References

- [XDPoS 2.0 Whitepaper](https://www.xdc.dev/xdc-foundation/xdpos-2-0-a-leap-in-blockchain-consensus-4k8b)
- [XDPoSChain GitHub](https://github.com/XinFinOrg/XDPoSChain)
- [XDC Network Documentation](https://docs.xdc.network/)
