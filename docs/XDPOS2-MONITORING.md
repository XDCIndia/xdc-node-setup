# XDPoS 2.0 Consensus Monitoring Guide

## Overview

This guide covers monitoring XDPoS 2.0 consensus for XDC Network masternodes and validators.

## XDPoS 2.0 Consensus Basics

### Epoch Structure
- **Epoch Size**: 900 blocks
- **Epoch Change**: Every multiple of 900 (900, 1800, 2700...)
- **Masternode Count**: 108 active masternodes per epoch

### Consensus Flow
1. **Block Proposal**: A masternode proposes a block for the current round
2. **Vote Collection**: Other masternodes vote on the proposed block
3. **QC Formation**: When 2/3+ votes are collected, a Quorum Certificate (QC) is formed
4. **Block Commit**: The block is committed with the QC
5. **Timeout**: If QC is not formed within timeout, round increases

### Key Blocks in Epoch
- **Block 900×n - 450**: Vote collection for next epoch begins
- **Block 900×n - 50**: QC formation deadline
- **Block 900×n**: Epoch transition (new masternode set takes effect)

## Monitoring Metrics

### 1. Epoch Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| Current Epoch | Current epoch number | - |
| Blocks Until Epoch | Blocks remaining until next epoch | < 10 blocks |
| Vote Collection Status | Whether vote collection is active | - |
| QC Formation Time | Time to form QC | > 1 second |

### 2. Consensus Health Metrics

| Metric | Description | Good | Warning | Critical |
|--------|-------------|------|---------|----------|
| Vote Participation | % of masternodes voting | > 95% | 90-95% | < 90% |
| QC Formation Time | Average time to form QC | < 500ms | 500ms-1s | > 1s |
| Round Changes | Round changes per epoch | 0 | 1-2 | > 2 |
| Timeout Certificates | TCs per epoch | 0 | 1 | > 1 |

### 3. Masternode Metrics

| Metric | Description | Target |
|--------|-------------|--------|
| Blocks Produced | Blocks proposed per epoch | 8-9 |
| Blocks Missed | Missed proposal opportunities | 0 |
| Vote Latency | Time to cast vote | < 100ms |
| Penalty Status | Current penalty status | Active |

## Monitoring Setup

### Using Prometheus

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'xdpos-consensus'
    static_configs:
      - targets: ['localhost:6060']
    metrics_path: /debug/metrics/prometheus
```

### Key Prometheus Queries

```promql
# Current block height
XDPoS_currentBlock

# Epoch number
floor(XDPoS_currentBlock / 900)

# Blocks until next epoch
(900 - (XDPoS_currentBlock % 900))

# Vote participation rate
XDPoS_votes_received / XDPoS_votes_expected

# QC formation time
XDPoS_qc_formation_time_seconds
```

### Grafana Dashboard

Import the XDPoS Consensus dashboard (ID: xxxx) for visual monitoring.

## Alerting Rules

### Critical Alerts

```yaml
# alerts.yml
groups:
  - name: xdpos-critical
    rules:
      - alert: LowVoteParticipation
        expr: xdpos_vote_participation < 0.9
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Vote participation below 90%"
          
      - alert: EpochTransitionImminent
        expr: (900 - (xdpos_current_block % 900)) < 10
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Epoch transition in {{ $value }} blocks"
```

## Troubleshooting

### Low Vote Participation

**Symptoms**: Vote participation drops below 90%

**Possible Causes**:
- Network connectivity issues
- Masternode software outdated
- Consensus bug

**Resolution**:
1. Check network connectivity between masternodes
2. Verify all masternodes running latest version
3. Check for error logs in XDC client

### QC Formation Timeout

**Symptoms**: QC formation time > 1 second

**Possible Causes**:
- High network latency
- Slow masternode response
- Network partition

**Resolution**:
1. Check network latency between masternodes
2. Monitor individual masternode response times
3. Investigate network partitions

### Epoch Transition Issues

**Symptoms**: Delays or failures at epoch boundary

**Possible Causes**:
- Masternode set change conflicts
- Vote collection incomplete
- QC not formed before deadline

**Resolution**:
1. Monitor vote collection starting at block 900×n-450
2. Ensure QC formation by block 900×n-50
3. Check masternode set synchronization

## API Reference

### XDPoS RPC Methods

```bash
# Get current round number
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getRoundNumber","params":[],"id":1}'

# Get voters for a block
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getVoters","params":["0x..."],"id":1}'

# Get QC for a block
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"XDPoS_getQc","params":["0x..."],"id":1}'
```

## Best Practices

1. **Monitor Continuously**: Set up 24/7 monitoring for all consensus metrics
2. **Alert Proactively**: Configure alerts before issues become critical
3. **Track Trends**: Monitor metrics over time to identify degradation
4. **Test Failover**: Regularly test backup masternode configurations
5. **Stay Updated**: Keep masternode software updated to latest version

## References

- [XDPoS 2.0 Whitepaper](https://docs.xdc.network)
- [XDC Network Documentation](https://docs.xdc.network)
- [XDC EVM Expert Validation Report](../XDC_VALIDATION_REPORT.md)
