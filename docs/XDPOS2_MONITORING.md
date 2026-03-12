# XDPoS 2.0 Consensus Monitoring Guide

## Overview

This guide covers XDPoS 2.0 consensus monitoring for XDC Network nodes, including QC validation, vote tracking, and epoch boundary monitoring.

## XDPoS 2.0 Fundamentals

### Epoch Structure

- **Epoch Length:** 900 blocks
- **Masternodes:** 108 active validators
- **Quorum:** 73 signatures (2/3 majority)
- **Gap Blocks:** Empty blocks at epoch transitions

### Key Concepts

| Term | Description |
|------|-------------|
| Epoch | 900-block period with fixed masternode set |
| Round | Block number within epoch (0-899) |
| QC | Quorum Certificate - proof of consensus |
| Gap Block | Empty block at epoch boundary |

## Consensus Health Monitoring

### 1. QC Validation

```typescript
import { validateQC, isEpochBoundary } from '@/lib/consensus';

// Check QC at checkpoint block
async function checkConsensus(blockNum: number) {
  if (isEpochBoundary(blockNum)) {
    const validation = await validateQC(blockNum);
    
    if (!validation.valid) {
      console.error(`QC validation failed: ${validation.error}`);
      // Alert operators
    }
  }
}
```

### 2. Vote Tracking

```typescript
import { getVotes, countVotes } from '@/lib/consensus';

// Monitor vote participation
async function monitorVotes(blockNum: number) {
  const votes = await getVotes(blockNum);
  const voteCount = votes.length;
  
  if (voteCount < 73) {
    console.warn(`Insufficient votes: ${voteCount}/73`);
  }
  
  // Track vote latency
  for (const vote of votes) {
    const latency = await getVoteLatency(blockNum, vote.masternode);
    if (latency > 2000) {
      console.warn(`High vote latency from ${vote.masternode}: ${latency}ms`);
    }
  }
}
```

### 3. Masternode Set Tracking

```typescript
import { getMasternodes, isMasternode } from '@/lib/consensus';

// Monitor masternode participation
async function trackMasternodes() {
  const mnSet = await getMasternodes();
  
  console.log(`Epoch: ${mnSet.epoch}`);
  console.log(`Active: ${mnSet.masternodes.length}`);
  console.log(`Standby: ${mnSet.standbynodes.length}`);
  console.log(`Penalized: ${mnSet.penalized.length}`);
  
  // Check if specific address is masternode
  const isMn = await isMasternode('0x...');
}
```

## Gap Block Detection

Gap blocks occur at epoch boundaries when the network transitions between masternode sets.

```typescript
import { isGapBlock, detectGapBlocks } from '@/lib/consensus';

// Detect gap blocks in range
async function findGapBlocks() {
  const currentBlock = await getBlockNumber();
  const startBlock = currentBlock - 100;
  
  const gapBlocks = await detectGapBlocks(startBlock, currentBlock);
  
  if (gapBlocks.length > 0) {
    console.log(`Found ${gapBlocks.length} gap blocks:`, gapBlocks);
  }
}
```

## Consensus Health Score

The consensus health score combines multiple metrics:

```typescript
import { getConsensusHealth, checkConsensusHealth } from '@/lib/consensus';

// Get comprehensive health metrics
async function healthCheck() {
  const health = await getConsensusHealth();
  
  console.log(`
    Block: ${health.blockNumber}
    Epoch: ${health.epoch}
    Masternodes: ${health.masternodeCount}
    Votes: ${health.voteCount}
    Health Score: ${health.healthScore}
    Is Epoch Boundary: ${health.isEpochBoundary}
  `);
  
  if (health.qcData) {
    console.log(`QC Signatures: ${health.qcData.signatures.length}`);
  }
}
```

## Edge Cases and Race Conditions

### 1. Epoch Boundary Race Conditions

At epoch transitions, vote/timeout race conditions can occur:

```typescript
// Monitor QC formation time at epoch boundary
async function monitorEpochTransition(epoch: number) {
  const startBlock = epoch * 900;
  
  // Wait for QC formation
  const startTime = Date.now();
  let qcData = null;
  
  while (Date.now() - startTime < 30000) { // 30 second timeout
    qcData = await getQCData(startBlock);
    if (qcData && qcData.signatures.length >= 73) {
      break;
    }
    await new Promise(r => setTimeout(r, 1000));
  }
  
  const formationTime = Date.now() - startTime;
  
  if (!qcData || qcData.signatures.length < 73) {
    console.error(`QC formation failed after ${formationTime}ms`);
  } else {
    console.log(`QC formed in ${formationTime}ms with ${qcData.signatures.length} signatures`);
  }
}
```

### 2. Vote Timeout Handling

```typescript
// Handle vote timeouts
async function handleVoteTimeout(blockNum: number) {
  const votes = await getVotes(blockNum);
  const mnSet = await getMasternodes();
  
  // Find masternodes that didn't vote
  const votingMns = new Set(votes.map(v => v.masternode.toLowerCase()));
  const nonVotingMns = mnSet.masternodes.filter(
    mn => !votingMns.has(mn.toLowerCase())
  );
  
  if (nonVotingMns.length > 0) {
    console.warn(`Non-voting masternodes: ${nonVotingMns.join(', ')}`);
  }
}
```

## Monitoring Dashboard Integration

### Prometheus Metrics

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'xdc-consensus'
    static_configs:
      - targets: ['localhost:9090']
    metrics_path: /debug/metrics/prometheus
```

### Grafana Alerts

```yaml
# alerts/consensus.yml
groups:
  - name: consensus
    rules:
      - alert: InsufficientMasternodes
        expr: xdc_masternode_count < 73
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Insufficient masternodes"
          
      - alert: QCValidationFailed
        expr: xdc_qc_valid == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "QC validation failed at epoch boundary"
```

## Troubleshooting

### Low Vote Count

**Symptoms:** QC validation fails, insufficient signatures

**Causes:**
- Network partition
- Masternode offline
- Clock skew

**Solutions:**
```bash
# Check network connectivity
xdc peers

# Check system time
ntpq -p

# Restart node if needed
xdc restart
```

### Gap Block Issues

**Symptoms:** Transactions not processing at epoch boundaries

**Expected:** Gap blocks are normal at epoch transitions

**Investigation:**
```typescript
// Check if gap block is expected
const isExpected = isEpochBoundary(blockNum + 1);
```

## API Reference

### Consensus Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/consensus/health` | GET | Current consensus health |
| `/api/v1/consensus/qc/:block` | GET | QC data for block |
| `/api/v1/consensus/votes/:block` | GET | Votes for block |
| `/api/v1/consensus/masternodes` | GET | Current masternode set |

### Response Format

```json
{
  "blockNumber": 89234567,
  "epoch": 99149,
  "round": 567,
  "masternodeCount": 108,
  "voteCount": 108,
  "qcValid": true,
  "healthScore": 100,
  "isEpochBoundary": false
}
```

## References

- [XDPoS 2.0 Technical Paper](https://docs.xdc.community/)
- [XDC Consensus Documentation](https://github.com/XinFinOrg/XDPoSChain)

---

**Last Updated:** 2026-02-27  
**Version:** 1.0.0
