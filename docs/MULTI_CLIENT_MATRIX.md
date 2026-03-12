# Multi-Client Compatibility Matrix

## Overview

This document provides a comprehensive compatibility matrix for XDC Network clients.

## Client Comparison

| Feature | Geth-XDC Stable | Geth-XDC PR5 | Erigon-XDC | Nethermind-XDC | Reth-XDC |
|---------|-----------------|--------------|------------|----------------|----------|
| **Version** | v2.6.8 | Latest | Latest | Latest | Latest |
| **Status** | Production | Testing | Experimental | Beta | Alpha |
| **Sync Speed** | Standard | Standard | Fast | Very Fast | Very Fast |
| **Disk Usage** | ~500GB | ~500GB | ~400GB | ~350GB | ~300GB |
| **Memory** | 4GB+ | 4GB+ | 8GB+ | 12GB+ | 16GB+ |

## Port Configuration

| Client | RPC Port | P2P Port | Auth RPC | Private API |
|--------|----------|----------|----------|-------------|
| Geth-XDC | 8545 | 30303 | N/A | N/A |
| Geth-XDC PR5 | 8545 | 30303 | N/A | N/A |
| Erigon-XDC | 8547 | 30304*, 30311 | 8561 | 9091 |
| Nethermind-XDC | 8558 | 30306 | N/A | N/A |
| Reth-XDC | 7073 | 40303 | N/A | N/A |

*Port 30304 is XDC compatible. Port 30311 (eth/68) is NOT compatible with XDC.

## Protocol Compatibility

### P2P Protocol Support

| Client | eth/63 | eth/68 | eth/100 | XDC Compatible |
|--------|--------|--------|---------|----------------|
| Geth-XDC | ✅ | ❌ | ❌ | ✅ |
| Geth-XDC PR5 | ✅ | ❌ | ❌ | ✅ |
| Erigon-XDC | ✅ (30304) | ✅ (30311) | ❌ | ⚠️* |
| Nethermind-XDC | ❌ | ❌ | ✅ | ✅ |
| Reth-XDC | ❌ | ❌ | ✅ | ⚠️ |

*Erigon: Only port 30304 is XDC compatible

### RPC Compatibility

| Method | Geth-XDC | Erigon | Nethermind | Reth |
|--------|----------|--------|------------|------|
| eth_blockNumber | ✅ | ✅ | ✅ | ✅ |
| eth_getBalance | ✅ | ✅ | ✅ | ✅ |
| eth_sendTransaction | ✅ | ✅ | ✅ | ✅ |
| eth_call | ✅ | ✅ | ✅ | ✅ |
| debug_traceTransaction | ✅ | ✅ | ⚠️ | ⚠️ |
| txpool_content | ✅ | ❌ | ✅ | ⚠️ |
| admin_nodeInfo | ✅ | ✅ | ✅ | ⚠️ |

## XDPoS 2.0 Support

| Feature | Geth-XDC | Erigon | Nethermind | Reth |
|---------|----------|--------|------------|------|
| QC Validation | ✅ | ⚠️ | ⚠️ | ❌ |
| Vote Processing | ✅ | ⚠️ | ⚠️ | ❌ |
| Epoch Transition | ✅ | ⚠️ | ⚠️ | ❌ |
| Gap Block Handling | ✅ | ⚠️ | ⚠️ | ❌ |
| Timeout Certificates | ✅ | ⚠️ | ⚠️ | ❌ |

Legend:
- ✅ Full support
- ⚠️ Partial/Experimental support
- ❌ Not supported

## Known Issues

### Reth-XDC (Alpha)

1. **P2P Connection Issues**: ECIES handshake problems
2. **Debug Tip Required**: Needs manual `--debug.tip` configuration
3. **Memory Usage**: Higher than other clients
4. **Sync Stability**: Occasional stalls

**Workarounds**:
```bash
# Manual debug tip configuration
reth node --debug.tip 0x...

# Monitor peer count
curl -X POST http://localhost:7073 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
```

### Erigon-XDC (Experimental)

1. **Port Confusion**: Must use 30304 for XDC peers
2. **Build Time**: 10-15 minutes from source
3. **Memory Requirements**: 8GB+ recommended
4. **Snapshot Compatibility**: Different format from Geth

**Configuration**:
```yaml
# Use correct P2P port for XDC
P2P_PORT=30304  # NOT 30311
```

### Nethermind-XDC (Beta)

1. **Protocol Differences**: Uses eth/100
2. **Limited Documentation**: Fewer examples available
3. **.NET Dependencies**: Requires .NET runtime

## Client Selection Guide

### For Production Nodes

**Recommended**: Geth-XDC Stable (v2.6.8)
- Battle-tested
- Full XDPoS 2.0 support
- Best documentation
- Largest peer network

### For Development

**Recommended**: Geth-XDC PR5
- Latest features
- Active development
- Good for testing

### For Resource-Constrained Environments

**Recommended**: Nethermind-XDC
- Lowest disk usage (~350GB)
- Fast sync
- Lower memory than Reth

### For Experimentation

**Options**: Erigon-XDC, Reth-XDC
- Cutting-edge features
- Performance improvements
- Help identify bugs

## Migration Guide

### From Geth to Erigon

1. Stop Geth node
2. Backup chaindata
3. Install Erigon
4. Import snapshot or sync from genesis
5. Update firewall rules for port 30304

```bash
# Switch command
xdc stop
xdc start --client erigon
```

### From Geth to Nethermind

1. Stop Geth node
2. Install Nethermind
3. Sync from network (snapshots incompatible)
4. Update RPC port references (8545 → 8558)

### From Any to Reth

⚠️ **Not recommended for production**

1. Requires manual debug.tip configuration
2. Limited XDPoS 2.0 support
3. P2P connection issues

## Testing Multi-Client Setup

```bash
# Start multiple clients
xdc start --client stable --name geth-node
xdc start --client erigon --name erigon-node
xdc start --client nethermind --name nethermind-node

# Verify peer connections
xdc status --all

# Check for divergence
curl http://localhost:7070/api/divergence-check
```

## Monitoring Multi-Client Setup

Key metrics to track:
- Block height consistency across clients
- Peer count per client
- Memory usage per client
- Sync status
- Error rates

## Troubleshooting

### Clients Not Peering

1. Check P2P ports are open
2. Verify protocol compatibility
3. Check firewall rules
4. Review client logs

### Block Divergence

1. Compare block hashes
2. Check state roots
3. Review transaction execution
4. Alert on divergence

### Performance Issues

1. Monitor resource usage
2. Check disk I/O
3. Review network latency
4. Adjust client settings

---

*Document Version: 1.0*  
*Last Updated: March 2, 2026*
