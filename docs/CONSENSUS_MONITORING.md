# Consensus Monitoring Guide

## Overview

This guide explains how to monitor XDPoS 2.0 consensus health using SkyNet and node-level metrics.

## Key Metrics

### 1. Quorum Certificate (QC) Metrics

| Metric | Description | Target | Alert Threshold |
|--------|-------------|--------|-----------------|
| qc_formation_rate | % of blocks with valid QC | > 95% | < 90% |
| qc_signature_count | Average signatures per QC | > 73 | < 70 |
| qc_formation_time | Time to form QC (ms) | < 1000ms | > 2000ms |

### 2. Vote Metrics

| Metric | Description | Target | Alert Threshold |
|--------|-------------|--------|-----------------|
| vote_participation | % of masternodes voting | > 90% | < 85% |
| vote_latency | Average vote latency (ms) | < 500ms | > 1000ms |
| missed_votes | Votes missed per epoch | < 5% | > 10% |

### 3. Epoch Metrics

| Metric | Description | Target | Alert Threshold |
|--------|-------------|--------|-----------------|
| epoch_transition_time | Time for epoch handover | < 30s | > 60s |
| epoch_block_count | Blocks per epoch | 900 | ≠ 900 |
| gap_block_processing | Gap block handling time | < 5s | > 10s |

### 4. Timeout Metrics

| Metric | Description | Target | Alert Threshold |
|--------|-------------|--------|-----------------|
| timeout_rate | % of rounds with timeout | < 5% | > 10% |
| timeout_recovery | Time to recover from timeout | < 10s | > 30s |

## Monitoring Implementation

### Node-Level Monitoring

```bash
#!/bin/bash
# consensus-monitor.sh

RPC_URL="http://localhost:8545"

# Get current block
BLOCK_NUMBER=$(curl -s -X POST "$RPC_URL" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result')

# Calculate epoch
EPOCH=$(( $(printf "%d" "$BLOCK_NUMBER") / 900 ))

echo "Current Block: $BLOCK_NUMBER"
echo "Current Epoch: $EPOCH"

# Get peer count
PEERS=$(curl -s -X POST "$RPC_URL" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' | jq -r '.result')

echo "Connected Peers: $(( $(printf "%d" "$PEERS") ))"
```

### SkyNet Integration

```typescript
// SkyNet consensus monitoring service
class ConsensusMonitor {
  async collectMetrics(): Promise<ConsensusMetrics> {
    const block = await this.getLatestBlock();
    const epoch = Math.floor(block.number / 900);
    
    return {
      blockNumber: block.number,
      epoch: epoch,
      timestamp: block.timestamp,
      qcFormation: await this.checkQCFormation(block),
      voteParticipation: await this.calculateVoteParticipation(epoch),
      timeoutRate: await this.calculateTimeoutRate(epoch),
    };
  }
  
  async reportToSkyNet(metrics: ConsensusMetrics): Promise<void> {
    await fetch('https://skynet.xdc.network/api/metrics', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(metrics),
    });
  }
}
```

## Alerting Configuration

### Critical Alerts

```yaml
# alerts/critical.yml
alerts:
  - name: qc_formation_failure
    condition: qc_formation_rate < 0.90
    severity: critical
    channels: [pagerduty, slack]
    
  - name: epoch_transition_stuck
    condition: epoch_transition_time > 60s
    severity: critical
    channels: [pagerduty, slack]
    
  - name: consensus_partition
    condition: vote_participation < 0.67
    severity: critical
    channels: [pagerduty, sms]
```

### Warning Alerts

```yaml
# alerts/warning.yml
alerts:
  - name: low_vote_participation
    condition: vote_participation < 0.85
    severity: warning
    channels: [slack, email]
    
  - name: high_timeout_rate
    condition: timeout_rate > 0.10
    severity: warning
    channels: [slack]
```

## Dashboard Setup

### Grafana Dashboard

```json
{
  "dashboard": {
    "title": "XDPoS 2.0 Consensus",
    "panels": [
      {
        "title": "QC Formation Rate",
        "type": "stat",
        "targets": [
          {
            "expr": "qc_formation_rate"
          }
        ]
      },
      {
        "title": "Vote Participation",
        "type": "graph",
        "targets": [
          {
            "expr": "vote_participation"
          }
        ]
      },
      {
        "title": "Epoch Progress",
        "type": "gauge",
        "targets": [
          {
            "expr": "(block_number % 900) / 900"
          }
        ]
      }
    ]
  }
}
```

## Troubleshooting

### Low QC Formation Rate

**Symptoms**: QC formation rate drops below 90%

**Investigation**:
1. Check network connectivity
2. Verify masternode participation
3. Review timeout events
4. Check for clock skew

**Resolution**:
```bash
# Check peer connections
xdc status

# Review logs for errors
xdc logs | grep -i "qc\|vote\|timeout"

# Restart if necessary
xdc restart
```

### Epoch Transition Issues

**Symptoms**: Node stuck at epoch boundary

**Investigation**:
1. Check gap block processing
2. Verify masternode list
3. Review epoch transition logs

**Resolution**:
```bash
# Check current epoch
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Force resync if stuck
xdc stop
rm -rf $DATA_DIR/xdc/chaindata
xdc start --syncmode full
```

### High Timeout Rate

**Symptoms**: Excessive timeout certificates

**Investigation**:
1. Measure network latency
2. Check peer count
3. Review block propagation time

**Resolution**:
```bash
# Optimize peer connections
xdc config set --maxpeers 50

# Check network latency
ping bootnode.xdc.network

# Monitor block propagation
xdc logs | grep "imported blocks"
```

## Best Practices

1. **Monitor Continuously**: Set up 24/7 monitoring with alerting
2. **Track Trends**: Look for gradual degradation, not just failures
3. **Test Alerts**: Regularly verify alerting pipeline
4. **Document Baselines**: Establish normal operating ranges
5. **Review Regularly**: Weekly review of consensus metrics

## Tools

- **SkyNet**: Centralized monitoring dashboard
- **Prometheus**: Metrics collection
- **Grafana**: Visualization
- **PagerDuty**: Critical alerting
- **Slack**: Team notifications

---

*Document Version: 1.0*  
*Last Updated: March 2, 2026*
