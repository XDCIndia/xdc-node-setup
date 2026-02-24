# XDC Node Setup - XDPoS 2.0 Consensus Guide

## Overview

This guide explains XDPoS 2.0 (XinFin Delegated Proof of Stake) consensus mechanism and how to monitor it effectively using XDC Node Setup.

## XDPoS 2.0 Fundamentals

### Epoch System

```
Epoch Length: 900 blocks (~30 minutes)
Masternodes: 108 validators per epoch
Block Time: ~2 seconds
```

**Epoch Lifecycle:**
1. **Epoch Start** - New masternode set selected
2. **Block Production** - Masternodes take turns proposing blocks
3. **Voting** - Other masternodes vote on proposed blocks
4. **QC Formation** - Quorum Certificate requires 2/3 + 1 votes
5. **Epoch End** - Rewards distributed, next epoch begins

### Key Concepts

#### Masternodes
- **Active**: Currently producing blocks and voting
- **Standby**: Candidates waiting to join active set
- **Penalty**: Masternodes removed for misbehavior

#### Quorum Certificate (QC)
- Requires signatures from 73+ masternodes (2/3 + 1 of 108)
- Proves block has been agreed upon by consensus
- Stored in block header

#### Gap Blocks
- Occur when consensus fails to reach QC
- Network continues with empty blocks
- Indicate potential issues with masternodes

## Monitoring XDPoS 2.0

### Epoch Tracking

```bash
# Get current epoch number
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "XDPoS_getEpochNumber",
    "params": ["latest"],
    "id": 1
  }'

# Response
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": 99150  # Current epoch
}
```

### Masternode Monitoring

```bash
# Get current masternode set
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "XDPoS_getMasternodesByNumber",
    "params": ["latest"],
    "id": 1
  }'

# Response
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": [
    "0x9475074f...",
    "0xad22b60e...",
    # ... 108 masternodes
  ]
}
```

### Vote Analysis

```bash
# Get block with vote information
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "XDPoS_getV1ByNumber",
    "params": ["0x550F5E0"],
    "id": 1
  }'

# Response includes:
# - Round number
# - QC (Quorum Certificate)
# - Signatures from voting masternodes
```

## Consensus Health Indicators

### Healthy Network Signs

| Metric | Healthy Range | Warning | Critical |
|--------|--------------|---------|----------|
| Block Time | 2-3s | 3-5s | >5s |
| Gap Blocks | 0-1 per epoch | 2-5 | >5 |
| QC Formation | <5s | 5-10s | >10s |
| Vote Participation | >95% | 85-95% | <85% |
| Epoch Duration | 25-35 min | 35-45 min | >45 min |

### Alert Thresholds

```yaml
# skynet-agent.conf
# XDPoS 2.0 specific alerts
XDPOS_ALERT_GAP_BLOCKS=3
XDPOS_ALERT_EPOCH_DELAY=10m
XDPOS_ALERT_QC_TIMEOUT=15s
XDPOS_ALERT_VOTE_PARTICIPATION=85
```

## Troubleshooting Consensus Issues

### Symptom: High Gap Block Frequency

**Possible Causes:**
1. Masternode network issues
2. Clock skew between masternodes
3. Insufficient peer connections

**Diagnostic Steps:**
```bash
# Check peer count
xdc peers

# Check system time
ntpq -p

# Review logs for vote failures
xdc logs | grep -i "vote\|qc\|timeout"
```

### Symptom: Slow Block Production

**Possible Causes:**
1. High network latency between masternodes
2. Resource exhaustion (CPU/memory)
3. Database performance issues

**Diagnostic Steps:**
```bash
# Check system resources
xdc info

# Monitor database performance
curl http://localhost:6060/debug/metrics  # pprof endpoint

# Check for database corruption
xdc health --full
```

### Symptom: Epoch Transition Delays

**Possible Causes:**
1. Masternode set calculation issues
2. Smart contract delays
3. Network partition

**Diagnostic Steps:**
```bash
# Check epoch smart contract
# Contract: 0x0000000000000000000000000000000000000088

# Verify masternode candidates
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "eth_call",
    "params": [{
      "to": "0x0000000000000000000000000000000000000088",
      "data": "0x"  # getCandidates method
    }, "latest"],
    "id": 1
  }'
```

## Multi-Client Consensus Considerations

### Client Compatibility

| Client | XDPoS 2.0 Support | Notes |
|--------|------------------|-------|
| Geth-XDC | ✅ Full | Reference implementation |
| Erigon-XDC | ✅ Full | Experimental support |
| Nethermind-XDC | ✅ Full | Beta support |
| Reth-XDC | ⚠️ Partial | Alpha, limited testing |

### Cross-Client Verification

```bash
# Compare block hashes across clients
# Geth
curl -X POST http://localhost:8545 \
  -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}'

# Erigon
curl -X POST http://localhost:8547 \
  -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}'

# Compare hash field in responses
```

## Best Practices

### For Masternode Operators

1. **Maintain High Availability**
   - 99.9%+ uptime required
   - Redundant network connections
   - UPS/power backup

2. **Monitor Vote Participation**
   - Target >95% participation
   - Investigate missed votes immediately

3. **Stay Synchronized**
   - Use NTP for accurate time
   - Monitor block height vs network

4. **Keep Software Updated**
   - Apply consensus-critical updates immediately
   - Test updates on testnet first

### For Full Node Operators

1. **Track Consensus Health**
   - Monitor gap block frequency
   - Watch epoch transition times

2. **Maintain Peer Connections**
   - Minimum 10 peers
   - Include diverse client types

3. **Report Anomalies**
   - Use SkyNet to report consensus issues
   - Participate in network monitoring

## Resources

- [XDPoS 2.0 Technical Paper](https://docs.xdc.network/consensus)
- [XDC Network Explorer](https://explorer.xinfin.network)
- [Masternode Requirements](https://docs.xdc.network/masternode)

---

*Last updated: 2026-02-25*
