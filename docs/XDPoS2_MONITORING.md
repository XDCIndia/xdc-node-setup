# XDPoS 2.0 Consensus Monitoring Guide

**Version:** 1.0  
**Date:** February 27, 2026  
**Applies to:** xdc-node-setup (SkyOne) v1.0+, XDCNetOwn (SkyNet)

---

## Table of Contents

1. [Introduction](#introduction)
2. [XDPoS 2.0 Overview](#xdpos-20-overview)
3. [Epoch Structure](#epoch-structure)
4. [Gap Blocks](#gap-blocks)
5. [Vote Collection](#vote-collection)
6. [Monitoring Implementation](#monitoring-implementation)
7. [Alert Configuration](#alert-configuration)
8. [Troubleshooting](#troubleshooting)

---

## Introduction

This guide covers XDPoS 2.0 consensus monitoring for XDC Network nodes. XDPoS 2.0 is a Byzantine Fault Tolerant (BFT) consensus mechanism that ensures network security and finality through a rotating masternode set.

---

## XDPoS 2.0 Overview

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Masternode** | Validator node that produces blocks and votes |
| **Epoch** | Time period (900 blocks) with fixed masternode set |
| **Gap Block** | Non-production block period for vote collection |
| **Quorum Certificate (QC)** | Proof that 2/3+ masternodes voted for a block |
| **Timeout Certificate (TC)** | Proof that 2/3+ masternodes timed out |

### Consensus Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     XDPoS 2.0 Consensus Flow                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Epoch Start (Block 0)                                          │
│       │                                                          │
│       ▼                                                          │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐        │
│  │   Block 1   │────▶│   Block 2   │────▶│   Block N   │        │
│  │  (Round 1)  │     │  (Round 2)  │     │  (Round N)  │        │
│  └──────┬──────┘     └──────┬──────┘     └──────┬──────┘        │
│         │                   │                   │               │
│         └───────────────────┴───────────────────┘               │
│                         │                                       │
│                         ▼                                       │
│                  Vote Collection                                │
│                         │                                       │
│                         ▼                                       │
│              Quorum Certificate (QC)                            │
│                         │                                       │
│                         ▼                                       │
│  Gap Blocks (450-899) ──┴──▶ Epoch Transition                   │
│                                                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## Epoch Structure

### Epoch Parameters

```yaml
epoch_length: 900          # Blocks per epoch
gap_start: 450            # First gap block
gap_end: 899              # Last gap block
production_blocks: 450    # Blocks with production
masternode_count: 108     # Maximum masternodes
```

### Epoch Phases

| Phase | Block Range | Activity |
|-------|-------------|----------|
| **Production** | 0-449 | Normal block production |
| **Gap** | 450-899 | Vote collection, no production |
| **Transition** | 899-900 | Masternode set update |

### Monitoring Epoch Boundaries

```bash
#!/bin/bash
# epoch-monitor.sh

RPC_ENDPOINT="http://localhost:8545"
EPOCH_LENGTH=900

# Get current block number
current_block=$(curl -s -X POST $RPC_ENDPOINT \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | \
  jq -r '.result' | xargs printf '%d')

# Calculate epoch position
current_epoch=$((current_block / EPOCH_LENGTH))
epoch_position=$((current_block % EPOCH_LENGTH))
blocks_to_gap=$((450 - epoch_position))
blocks_to_epoch_end=$((900 - epoch_position))

echo "Current Block: $current_block"
echo "Current Epoch: $current_epoch"
echo "Epoch Position: $epoch_position"
echo "Blocks to Gap: $blocks_to_gap"
echo "Blocks to Epoch End: $blocks_to_epoch_end"

# Alert if approaching gap
if [ $blocks_to_gap -le 10 ] && [ $blocks_to_gap -gt 0 ]; then
  echo "WARNING: Approaching gap blocks in $blocks_to_gap blocks"
fi

# Alert if in gap
if [ $epoch_position -ge 450 ]; then
  echo "INFO: Currently in gap block period"
fi
```

---

## Gap Blocks

### What are Gap Blocks?

Gap blocks are a unique feature of XDPoS 2.0 where block production pauses for 450 blocks at the end of each epoch. During this time:

- **No new blocks** are produced
- **Vote collection** continues for previously produced blocks
- **Masternodes prepare** for the next epoch
- **QC formation** completes for final blocks

### Gap Block Monitoring

```bash
#!/bin/bash
# gap-block-monitor.sh

EPOCH_LENGTH=900
GAP_START=450
RPC_ENDPOINT="http://localhost:8545"

get_block_number() {
  curl -s -X POST $RPC_ENDPOINT \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | \
    jq -r '.result' | xargs printf '%d'
}

is_gap_block() {
  local block=$1
  local position=$((block % EPOCH_LENGTH))
  [ $position -ge $GAP_START ]
}

# Main monitoring loop
while true; do
  current_block=$(get_block_number)
  
  if is_gap_block $current_block; then
    echo "$(date): GAP BLOCK ACTIVE - Block $current_block"
    
    # Monitor vote collection during gap
    # This would integrate with XDCNetOwn metrics
  else
    blocks_to_gap=$((GAP_START - (current_block % EPOCH_LENGTH)))
    if [ $blocks_to_gap -le 50 ]; then
      echo "$(date): Approaching gap blocks ($blocks_to_gap blocks remaining)"
    fi
  fi
  
  sleep 10
done
```

### Prometheus Metrics for Gap Blocks

```yaml
# gap_metrics.yml
gap_block_active:
  type: gauge
  help: "1 if currently in gap block period, 0 otherwise"
  
gap_blocks_remaining:
  type: gauge
  help: "Number of blocks until gap period starts"
  
votes_collected_during_gap:
  type: counter
  help: "Total votes collected during gap period"
  
gap_period_duration_seconds:
  type: histogram
  help: "Duration of gap period in seconds"
  buckets: [2700, 3600, 4500, 5400, 7200]  # 45min to 2 hours
```

---

## Vote Collection

### Vote Mechanics

In XDPoS 2.0, masternodes submit votes for blocks to achieve consensus:

1. **Block Proposal**: Masternode proposes a block
2. **Vote Broadcast**: Other masternodes broadcast votes
3. **QC Formation**: When 2/3+ votes received, QC is formed
4. **Block Finality**: Block is considered final with QC

### Vote Monitoring Script

```bash
#!/bin/bash
# vote-monitor.sh

MASTERNODE_ADDRESS="${MASTERNODE_ADDRESS}"
RPC_ENDPOINT="http://localhost:8545"

# Get masternode info for current epoch
get_masternode_info() {
  local epoch=$1
  curl -s -X POST $RPC_ENDPOINT \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"XDPoS_getMasternodes\",\"params\":[\"$epoch\"],\"id\":1}"
}

# Check if node is in masternode set
check_masternode_status() {
  local epoch=$(curl -s -X POST $RPC_ENDPOINT \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"XDPoS_getEpochNumber","params":[],"id":1}' | \
    jq -r '.result')
  
  local mn_list=$(get_masternode_info $epoch)
  
  if echo "$mn_list" | grep -q "$MASTERNODE_ADDRESS"; then
    echo "Masternode Status: ACTIVE in epoch $epoch"
    return 0
  else
    echo "Masternode Status: NOT IN SET for epoch $epoch"
    return 1
  fi
}

# Monitor vote participation
monitor_votes() {
  while true; do
    if check_masternode_status; then
      # Get vote statistics
      # This would require additional RPC methods or event parsing
      echo "$(date): Monitoring vote participation..."
    fi
    sleep 30
  done
}

monitor_votes
```

### Vote Metrics

```yaml
# vote_metrics.yml
vote_submissions_total:
  type: counter
  labels: [masternode_address, epoch]
  help: "Total votes submitted by this masternode"

vote_submissions_missed:
  type: counter
  labels: [masternode_address, epoch]
  help: "Missed vote opportunities"

vote_participation_rate:
  type: gauge
  labels: [masternode_address]
  help: "Vote participation rate (0-1)"

qc_formed_total:
  type: counter
  help: "Total quorum certificates formed"

tc_formed_total:
  type: counter
  help: "Total timeout certificates formed"
```

---

## Monitoring Implementation

### SkyOne Integration

Add to `docker/monitoring/prometheus-rules.yml`:

```yaml
groups:
  - name: xdpos_consensus
    rules:
      - alert: XDPoSGapBlockActive
        expr: gap_block_active == 1
        for: 0m
        labels:
          severity: info
        annotations:
          summary: "Gap block period is active"
          description: "Currently in gap block period (blocks 450-899)"
      
      - alert: XDPoSEpochTransitionSoon
        expr: gap_blocks_remaining <= 10
        for: 0m
        labels:
          severity: warning
        annotations:
          summary: "Epoch transition approaching"
          description: "Gap blocks start in {{ $value }} blocks"
      
      - alert: XDPoSLowVoteParticipation
        expr: rate(vote_submissions_missed[1h]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low vote participation detected"
          description: "Masternode has missed >10% of votes in the last hour"
      
      - alert: XDPoSMasternodeNotInSet
        expr: masternode_in_current_set == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Masternode not in current set"
          description: "This node is not in the current masternode set"
```

### SkyNet Integration

Add to SkyNet heartbeat payload:

```typescript
interface XDPoSMetrics {
  epoch: number;
  epochPosition: number;
  inGapPeriod: boolean;
  masternodeInSet: boolean;
  votesSubmittedThisEpoch: number;
  votesMissedThisEpoch: number;
  lastQCTime: string;
  lastTCTime: string;
}
```

---

## Alert Configuration

### Critical Alerts

| Alert | Condition | Action |
|-------|-----------|--------|
| **Consensus Fork** | Block hash divergence between clients | Immediate investigation |
| **Masternode Removal** | Node no longer in masternode set | Check stake, penalties |
| **QC Timeout** | No QC formed for >5 minutes | Check network connectivity |

### Warning Alerts

| Alert | Condition | Action |
|-------|-----------|--------|
| **Low Vote Rate** | <90% vote participation | Monitor, check node health |
| **Epoch Transition** | Within 10 blocks of gap | Prepare for reduced activity |
| **Gap Block Extended** | Gap period >2 hours | Check network consensus |

### Info Alerts

| Alert | Condition | Action |
|-------|-----------|--------|
| **Gap Block Start** | Entering gap period | Normal notification |
| **New Epoch** | Epoch transition complete | Log for tracking |

---

## Troubleshooting

### Common Issues

#### Issue: Node Not in Masternode Set

**Symptoms:**
- `masternode_in_current_set == 0`
- No block production
- No votes being submitted

**Diagnosis:**
```bash
# Check if node is registered as masternode
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getMasternodes","params":["latest"],"id":1}'

# Check stake amount
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getCandidateStatus","params":["0x..."],"id":1}'
```

**Resolution:**
1. Verify sufficient stake (10M XDC minimum)
2. Check for penalties or slashing
3. Ensure node is properly registered

#### Issue: Low Vote Participation

**Symptoms:**
- `vote_participation_rate < 0.9`
- Frequent missed votes

**Diagnosis:**
```bash
# Check peer connectivity
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'

# Check sync status
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
```

**Resolution:**
1. Ensure adequate peer connections (>10)
2. Verify node is fully synced
3. Check network latency to other masternodes

#### Issue: Extended Gap Period

**Symptoms:**
- Gap period lasts >2 hours
- No new epoch transition

**Diagnosis:**
```bash
# Check current block and epoch
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Check network health
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
```

**Resolution:**
1. Check if network has consensus
2. Verify sufficient masternodes online (>2/3)
3. Contact other masternode operators

---

## References

- [XDPoS 2.0 Technical Specification](https://docs.xdc.community)
- [XDC Network Consensus Documentation](https://xinfin.org)
- [SkyOne Node Setup Documentation](./README.md)
- [SkyNet Dashboard Documentation](../XDCNetOwn/README.md)

---

*Document Version: 1.0*  
*Last Updated: February 27, 2026*
