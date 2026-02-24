# Multi-Client Compatibility Guide

## Overview

This guide covers running multiple XDC clients (Geth, Erigon, Nethermind, Reth) for improved network resilience and validation.

## Supported Clients

| Client | Status | Best For | Notes |
|--------|--------|----------|-------|
| Geth-XDC | Production | General use | Full XDPoS 2.0 support |
| Geth-XDC (PR5) | Beta | Testing new features | Pre-release features |
| Erigon-XDC | Experimental | Fast sync | Archive node optimized |
| Nethermind-XDC | Experimental | Enterprise | High performance |
| Reth-XDC | Alpha | Development | Limited XDPoS support |

## Quick Start

### Geth-XDC (Default)

```bash
# Using Docker
docker-compose up -d xdc-node

# Using setup script
./setup.sh --client=xdc
```

### Erigon-XDC

```bash
# Using Docker
docker-compose -f docker-compose.erigon.yml up -d

# Using setup script
./setup.sh --client=erigon
```

### Nethermind-XDC

```bash
# Using Docker
docker-compose -f docker-compose.nethermind.yml up -d

# Using setup script
./setup.sh --client=nethermind
```

### Reth-XDC

```bash
# Using Docker
docker-compose -f docker-compose.reth.yml up -d

# Using setup script
./setup.sh --client=reth
```

## Client Comparison

### Sync Performance

| Client | Full Sync Time | Archive Sync | Disk Usage |
|--------|---------------|--------------|------------|
| Geth-XDC | ~24 hours | ~7 days | ~800 GB |
| Erigon-XDC | ~12 hours | ~3 days | ~600 GB |
| Nethermind-XDC | ~18 hours | ~5 days | ~700 GB |
| Reth-XDC | ~20 hours | N/A | ~750 GB |

### RPC Compatibility

| Method | Geth | Erigon | Nethermind | Reth |
|--------|------|--------|------------|------|
| eth_syncing | ✅ | ✅ | ✅ | ✅ |
| eth_getBlockByNumber | ✅ | ✅ | ✅ | ✅ |
| XDPoS_getRoundNumber | ✅ | ⚠️ | ⚠️ | ❌ |
| XDPoS_getVoters | ✅ | ⚠️ | ⚠️ | ❌ |
| XDPoS_getQc | ✅ | ⚠️ | ⚠️ | ❌ |
| eth_getLogs | ✅ | ✅ | ✅ | ✅ |
| debug_traceTransaction | ✅ | ✅ | ✅ | ❌ |

### Resource Usage

| Client | Min RAM | Rec. RAM | Min CPU | Rec. CPU |
|--------|---------|----------|---------|----------|
| Geth-XDC | 4 GB | 16 GB | 2 cores | 4 cores |
| Erigon-XDC | 8 GB | 32 GB | 4 cores | 8 cores |
| Nethermind-XDC | 4 GB | 16 GB | 2 cores | 4 cores |
| Reth-XDC | 8 GB | 16 GB | 4 cores | 8 cores |

## Configuration Differences

### Geth-XDC

```yaml
# docker-compose.yml
services:
  xdc-node:
    image: xinfinorg/xdposchain:v2.6.8
    environment:
      - SYNC_MODE=full
      - GC_MODE=full
    volumes:
      - xdcchain:/work/xdcchain
```

### Erigon-XDC

```yaml
# docker-compose.erigon.yml
services:
  erigon:
    image: xinfinorg/erigon-xdc:latest
    environment:
      - CHAIN=XDC
      - PRUNE=hrtc
    volumes:
      - erigon-data:/data
      - erigon-snapshots:/snapshots
```

### Nethermind-XDC

```yaml
# docker-compose.nethermind.yml
services:
  nethermind:
    image: xinfinorg/nethermind-xdc:latest
    environment:
      - NETHERMIND_CONFIG=xdcmainnet
    volumes:
      - nethermind-db:/nethermind/nethermind_db
      - nethermind-keystore:/nethermind/keystore
```

### Reth-XDC

```yaml
# docker-compose.reth.yml
services:
  reth:
    image: xinfinorg/reth-xdc:latest
    environment:
      - CHAIN=xdc
    volumes:
      - reth-data:/root/.local/share/reth
```

## Cross-Client Validation

### Block Hash Comparison

```bash
#!/bin/bash
# compare-clients.sh

BLOCK_NUMBER=$1

GETH_HASH=$(curl -s http://geth:8545 -X POST -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$BLOCK_NUMBER\",false],\"id\":1}" | jq -r '.result.hash')

ERIGON_HASH=$(curl -s http://erigon:8545 -X POST -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$BLOCK_NUMBER\",false],\"id\":1}" | jq -r '.result.hash')

if [ "$GETH_HASH" == "$ERIGON_HASH" ]; then
  echo "✅ Block hashes match: $GETH_HASH"
else
  echo "❌ Block hash mismatch!"
  echo "Geth: $GETH_HASH"
  echo "Erigon: $ERIGON_HASH"
fi
```

### State Root Comparison

```bash
#!/bin/bash
# compare-state-roots.sh

BLOCK_NUMBER=$1

GETH_STATE=$(curl -s http://geth:8545 -X POST -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$BLOCK_NUMBER\",false],\"id\":1}" | jq -r '.result.stateRoot')

ERIGON_STATE=$(curl -s http://erigon:8545 -X POST -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$BLOCK_NUMBER\",false],\"id\":1}" | jq -r '.result.stateRoot')

if [ "$GETH_STATE" == "$ERIGON_STATE" ]; then
  echo "✅ State roots match: $GETH_STATE"
else
  echo "❌ State root mismatch!"
  echo "Geth: $GETH_STATE"
  echo "Erigon: $ERIGON_STATE"
fi
```

## Troubleshooting

### Sync Issues

#### Geth-XDC

**Slow Sync**:
- Check peer count: `xdc status`
- Verify network connectivity
- Consider using snapshot sync

**Stuck Sync**:
- Check for errors in logs: `docker logs xdc-node`
- Verify bootnodes are accessible
- Try restarting with `--syncmode full`

#### Erigon-XDC

**High Memory Usage**:
- Increase swap space
- Reduce batch sizes in config
- Monitor with `htop`

**Snapshot Download Fails**:
- Check disk space (need 1TB+ free)
- Verify network connectivity
- Try manual snapshot download

#### Nethermind-XDC

**Database Corruption**:
- Stop node: `docker stop nethermind`
- Remove database: `rm -rf nethermind-db/*`
- Restart sync

**High CPU Usage**:
- Check pruning settings
- Verify adequate RAM allocated
- Monitor with `docker stats`

#### Reth-XDC

**Limited XDPoS Support**:
- Not all XDPoS RPC methods available
- Use for non-masternode nodes only
- Check documentation for supported methods

## Best Practices

1. **Run Multiple Clients**: For critical infrastructure, run at least 2 different clients
2. **Cross-Validate**: Regularly compare block hashes and state roots
3. **Monitor Divergence**: Set up alerts for client divergence
4. **Test Upgrades**: Test client upgrades on testnet first
5. **Backup Keys**: Keep wallet backups independent of client

## Migration Between Clients

### Geth to Erigon

1. Export keys from Geth
2. Stop Geth node
3. Start Erigon with same keys
4. Verify sync progress

### Erigon to Geth

1. Export keys from Erigon
2. Stop Erigon node
3. Start Geth with same keys
4. Allow full sync (or use snapshot)

## References

- [XDC Network Documentation](https://docs.xdc.network)
- [Geth-XDC GitHub](https://github.com/XinFinOrg/XDPoSChain)
- [Erigon Documentation](https://github.com/ledgerwatch/erigon)
- [Nethermind Documentation](https://docs.nethermind.io)
- [Reth Documentation](https://reth.rs)
