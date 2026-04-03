# XDPoS 2.0 Operator Guide

## Overview

XDPoS 2.0 is the consensus mechanism powering XDC Network. This guide covers essential operational knowledge for masternode operators.

## Table of Contents

1. [Consensus Overview](#consensus-overview)
2. [Epoch Structure](#epoch-structure)
3. [Quorum Certificates (QC)](#quorum-certificates-qc)
4. [Timeout Certificates (TC)](#timeout-certificates-tc)
5. [Masternode Operations](#masternode-operations)
6. [Monitoring & Troubleshooting](#monitoring--troubleshooting)

---

## Consensus Overview

### What is XDPoS 2.0?

XDPoS 2.0 is a Byzantine Fault Tolerant (BFT) consensus protocol with the following characteristics:

- **Validator Set**: 108 masternodes
- **Block Time**: ~2 seconds target
- **Finality**: 1-2 epochs (~30-60 minutes)
- **Rewards**: Distributed to masternode operators and delegators
- **Slashing**: Penalties for downtime and misbehavior

### Key Differences from XDPoS 1.0

| Feature | XDPoS 1.0 | XDPoS 2.0 |
|---------|-----------|-----------|
| Finality | Probabilistic | Deterministic (QC-based) |
| Fork Recovery | Manual | Automatic |
| Timeout Handling | None | Timeout Certificates (TC) |
| Block Validation | PoA-style | BFT-style with 2/3+ quorum |

---

## Epoch Structure

### Epoch Basics

- **Epoch Length**: 900 blocks (~30 minutes at 2s/block)
- **Epoch Number**: `block_number / 900`
- **Gap Blocks**: Blocks 450-899 in each epoch (no validator voting)

### Epoch Phases

```
Epoch N (Blocks 0-899):
┌────────────────────┬───────────────────┐
│  Voting Phase      │    Gap Phase      │
│  Blocks 0-449      │   Blocks 450-899  │
│  (Validator votes) │   (No votes)      │
└────────────────────┴───────────────────┘
```

**Voting Phase (Blocks 0-449):**
- Validators propose and vote on blocks
- QCs are formed with 2/3+ validator votes
- Active consensus participation

**Gap Phase (Blocks 450-899):**
- Block production continues
- No voting (votes are collected for next epoch)
- Checkpoint for validator set changes

### Epoch Transition

At block 900 (start of next epoch):

1. **Validator Set Update**: New masternode set activated
2. **Reward Distribution**: Rewards for previous epoch distributed
3. **Vote Reset**: Vote counters reset for new epoch

---

## Quorum Certificates (QC)

### What is a QC?

A Quorum Certificate is cryptographic proof that 2/3+ of validators (73 out of 108) have voted for a block.

### QC Structure

```json
{
  "blockHash": "0x...",
  "blockNumber": 12345,
  "round": 1,
  "signatures": [
    "0xsig1...",
    "0xsig2...",
    ...  // 73+ signatures
  ],
  "validators": [
    "0xaddr1...",
    "0xaddr2...",
    ...  // 73+ validator addresses
  ]
}
```

### QC Formation Process

1. **Block Proposal**: Block proposer creates new block
2. **Vote Collection**: Validators vote on the block
3. **Signature Aggregation**: Votes are aggregated into QC
4. **QC Broadcast**: QC is broadcast to network
5. **Block Finalization**: Block with QC is considered finalized

### Monitoring QC Formation

Check QC formation rate:

```bash
# Check if QC exists in block extraData
curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}' \
  | jq '.result.extraData' | wc -c

# If length > 260 bytes, QC is present
```

---

## Timeout Certificates (TC)

### What is a TC?

When QC formation fails (e.g., network partition, insufficient votes), validators send timeout votes. A TC is formed when 2/3+ validators vote to timeout the current round.

### TC vs QC

| | Quorum Certificate (QC) | Timeout Certificate (TC) |
|---|---|---|
| **Indicates** | Consensus achieved | Consensus timeout |
| **Action** | Block finalized | Move to next round |
| **Threshold** | 2/3+ votes | 2/3+ timeout votes |
| **Frequency** | Every block (normal operation) | Rare (network issues) |

### When TCs Occur

- Network partitions
- Validator downtime
- Slow block propagation
- Byzantine behavior

### Monitoring TCs

```bash
# Check for TC in extraData (length > QC length)
# High TC rate indicates network issues
```

**Alert Thresholds:**
- TC rate > 5%: Warning
- TC rate > 10%: Critical - investigate immediately

---

## Masternode Operations

### Running a Masternode

#### Prerequisites

- **Stake**: 10,000,000 XDC minimum
- **Hardware**: 4+ CPU cores, 16GB+ RAM, 500GB+ SSD
- **Network**: Stable connection, public IP, port 30303 open
- **Uptime**: 99%+ required

#### Registration

1. **Stake XDC**: Lock 10M XDC in masternode contract
2. **Configure Node**: Set coinbase address and signing key
3. **Wait for Epoch**: Registration active at next epoch boundary

```bash
# Example coinbase configuration
--coinbase 0xYourMasternodeAddress \
--unlock 0xYourMasternodeAddress \
--password /path/to/password.txt
```

#### Monitoring Masternode Status

```bash
# Check if you're in the current masternode set
curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"XDPoS_getMasternodesByNumber","params":["latest"],"id":1}' \
  | jq '.result[] | select(. == "0xYourAddress")'
```

### Validator Performance Metrics

#### Vote Participation Rate

```
Vote Participation = (Votes Cast / Expected Votes) * 100%
```

**Targets:**
- Excellent: 99%+
- Good: 95-99%
- Fair: 90-95%
- Poor: <90% (risk of penalties)

#### Block Production Rate

```
Block Production = (Blocks Produced / Blocks Assigned) * 100%
```

**Targets:**
- Excellent: 99%+
- Good: 95-99%
- Fair: 90-95%
- Poor: <90%

### Slashing & Penalties

#### Slashing Conditions

1. **Double Signing**: Signing two conflicting blocks at same height
2. **Extended Downtime**: >10% missed votes in epoch
3. **Byzantine Behavior**: Malicious voting patterns

#### Penalty Tiers

| Severity | Condition | Penalty |
|----------|-----------|---------|
| **Warning** | Missed votes 5-10% | Reduced rewards |
| **Minor** | Missed votes 10-20% | 50% reward reduction |
| **Major** | Missed votes >20% | Temporary removal from set |
| **Critical** | Double signing | Stake slashing (partial) |

---

## Monitoring & Troubleshooting

### Essential Metrics

Monitor these metrics via SkyNet dashboard or CLI:

1. **Block Height**: Current sync status
2. **Peer Count**: Network connectivity (target: 10-50 peers)
3. **Vote Participation**: Your vote % in current epoch
4. **Block Production**: Blocks produced vs expected
5. **Rewards**: Accumulated rewards per epoch
6. **QC Formation Time**: Average time to form QC

### Common Issues

#### Issue 1: Missing Votes

**Symptoms:**
- Vote participation rate dropping
- Not seeing your votes in blocks

**Diagnosis:**
```bash
# Check if node is synced
curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

# Check peer count
curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
```

**Solutions:**
1. Ensure node is fully synced
2. Check network connectivity
3. Verify signing key is loaded and unlocked
4. Restart node if necessary

#### Issue 2: Not Producing Blocks

**Symptoms:**
- Block production rate 0%
- Rewards not accumulating

**Diagnosis:**
```bash
# Verify you're in the masternode set
curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"XDPoS_getMasternodesByNumber","params":["latest"],"id":1}'
```

**Solutions:**
1. Check registration status
2. Verify stake is still locked
3. Ensure coinbase address matches registered address
4. Check for slashing events

#### Issue 3: High TC Rate

**Symptoms:**
- Timeout certificates appearing frequently
- Block finality delays

**Diagnosis:**
```bash
# Check logs for timeout messages
docker logs xdc-node | grep -i timeout

# Check network latency to other validators
```

**Solutions:**
1. Improve network connectivity
2. Reduce load on node (check CPU/memory)
3. Check for network partitions
4. Verify clock synchronization (NTP)

#### Issue 4: Epoch Transition Failures

**Symptoms:**
- Node stuck at epoch boundary (block 900, 1800, etc.)
- Consensus errors in logs

**Solutions:**
1. Wait for next epoch (automatic recovery)
2. Check validator set changes
3. Verify QC for epoch boundary block exists
4. Restart node if stuck for >30 minutes

### Health Check Checklist

Daily checks:

- [ ] Node is synced (check block height vs network)
- [ ] Peer count is healthy (10-50 peers)
- [ ] Vote participation > 95%
- [ ] Block production on target
- [ ] No errors in logs
- [ ] Disk space > 20% free

Weekly checks:

- [ ] Rewards accumulating correctly
- [ ] No slashing events
- [ ] Average QC formation time < 5 seconds
- [ ] TC rate < 1%
- [ ] Backup node data

### Emergency Procedures

#### Procedure: Node Compromised

1. **Immediately disconnect** node from network
2. **Rotate signing keys** on backup node
3. **Investigate** attack vector
4. **Report** to XDC core team
5. **Restore** from clean backup
6. **Re-register** with new keys

#### Procedure: Extended Downtime

1. **Alert delegates** (if applicable)
2. **Monitor slashing** threshold (20% missed votes)
3. **Restore service** ASAP
4. **Document** root cause
5. **Implement** preventive measures

---

## Additional Resources

- **XDC Network Explorer**: https://xdc.network/
- **Masternode Monitoring**: https://skynet.xdcindia.com/
- **Technical Documentation**: https://docs.xdc.network/
- **Community Support**: https://discord.gg/xdc

---

**Version**: 1.0  
**Last Updated**: March 2026  
**Maintainer**: XDC DevOps Team
