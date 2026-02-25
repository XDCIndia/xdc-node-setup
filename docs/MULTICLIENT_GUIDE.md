# Multi-Client Setup and Testing Guide

## Overview

This guide covers running multiple XDC clients simultaneously for testing, validation, and redundancy.

## Supported Client Combinations

### Recommended Combinations

| Primary | Secondary | Use Case |
|---------|-----------|----------|
| Geth-XDC | Erigon-XDC | Full node + archive queries |
| Geth-XDC | Nethermind-XDC | Production + development |
| Erigon-XDC | Geth-XDC | Archive + validation |

### Port Configuration

| Client | RPC Port | WS Port | P2P Port | Metrics Port |
|--------|----------|---------|----------|--------------|
| Geth-XDC | 8545 | 8546 | 30303 | 6060 |
| Geth-PR5 | 8545 | 8546 | 30303 | 6060 |
| Erigon-XDC | 8547 | 8548 | 30304 | 6061 |
| Nethermind-XDC | 8558 | 8559 | 30306 | 6062 |
| Reth-XDC | 7073 | 7074 | 40303 | 6063 |

## Docker Compose Configuration

### Multi-Client Setup

```yaml
# docker/docker-compose.multiclient.yml
version: '3.8'

services:
  # Primary: Geth-XDC
  xdc-geth:
    image: xinfinorg/xdposchain:v2.6.8
    container_name: xdc-geth
    restart: always
    ports:
      - "30303:30303"
      - "30303:30303/udp"
      - "127.0.0.1:8545:8545"
    volumes:
      - ./data/geth:/work/xdcchain
      - ./mainnet/genesis.json:/work/genesis.json:ro
    networks:
      - xdc-multiclient

  # Secondary: Erigon-XDC
  xdc-erigon:
    image: xinfinorg/erigon-xdc:latest
    container_name: xdc-erigon
    restart: always
    ports:
      - "30304:30303"
      - "30304:30303/udp"
      - "127.0.0.1:8547:8545"
    volumes:
      - ./data/erigon:/data
    networks:
      - xdc-multiclient

  # Tertiary: Nethermind-XDC
  xdc-nethermind:
    image: xinfinorg/nethermind-xdc:latest
    container_name: xdc-nethermind
    restart: always
    ports:
      - "30306:30303"
      - "30306:30303/udp"
      - "127.0.0.1:8558:8545"
    volumes:
      - ./data/nethermind:/data
    networks:
      - xdc-multiclient

  # Shared monitoring
  prometheus:
    image: prom/prometheus:latest
    container_name: xdc-prometheus
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    ports:
      - "127.0.0.1:9090:9090"
    networks:
      - xdc-multiclient

networks:
  xdc-multiclient:
    driver: bridge
```

## Cross-Client Validation

### Block Hash Comparison

```bash
#!/bin/bash
# scripts/cross-client-validate.sh

BLOCK_NUMBER=${1:-"latest"}

# Get block hash from each client
GETH_HASH=$(curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$BLOCK_NUMBER\",false],\"id\":1}" | jq -r '.result.hash')

ERIGON_HASH=$(curl -s -X POST http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$BLOCK_NUMBER\",false],\"id\":1}" | jq -r '.result.hash')

NETHERMIND_HASH=$(curl -s -X POST http://localhost:8558 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$BLOCK_NUMBER\",false],\"id\":1}" | jq -r '.result.hash')

echo "Block: $BLOCK_NUMBER"
echo "Geth:      $GETH_HASH"
echo "Erigon:    $ERIGON_HASH"
echo "Nethermind: $NETHERMIND_HASH"

if [ "$GETH_HASH" = "$ERIGON_HASH" ] && [ "$GETH_HASH" = "$NETHERMIND_HASH" ]; then
  echo "✓ All clients in consensus"
  exit 0
else
  echo "✗ CONSENSUS DIVERGENCE DETECTED!"
  exit 1
fi
```

### Automated Divergence Detection

```typescript
// lib/validation/divergence-detector.ts

interface BlockHash {
  client: string;
  blockNumber: number;
  hash: string;
  timestamp: Date;
}

class DivergenceDetector {
  async checkDivergence(blockNumber: number): Promise<DivergenceReport | null> {
    const hashes: BlockHash[] = await Promise.all([
      this.getBlockHash('geth', blockNumber),
      this.getBlockHash('erigon', blockNumber),
      this.getBlockHash('nethermind', blockNumber),
      this.getBlockHash('reth', blockNumber)
    ]);
    
    const uniqueHashes = new Set(hashes.map(h => h.hash));
    
    if (uniqueHashes.size > 1) {
      const majorityHash = this.getMajorityHash(hashes);
      const divergentClients = hashes.filter(h => h.hash !== majorityHash);
      
      return {
        blockNumber,
        detectedAt: new Date(),
        divergentClients,
        majorityHash,
        severity: 'critical'
      };
    }
    
    return null;
  }
  
  private async getBlockHash(client: string, blockNumber: number): Promise<BlockHash> {
    const rpcUrl = this.getClientRpcUrl(client);
    const response = await fetch(rpcUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'eth_getBlockByNumber',
        params: [`0x${blockNumber.toString(16)}`, false],
        id: 1
      })
    });
    
    const data = await response.json();
    return {
      client,
      blockNumber,
      hash: data.result.hash,
      timestamp: new Date()
    };
  }
  
  private getMajorityHash(hashes: BlockHash[]): string {
    const counts: Record<string, number> = {};
    for (const h of hashes) {
      counts[h.hash] = (counts[h.hash] || 0) + 1;
    }
    return Object.entries(counts).sort((a, b) => b[1] - a[1])[0][0];
  }
}
```

## Integration Testing

### Test Matrix

| Test | Geth | Erigon | Nethermind | Reth |
|------|------|--------|------------|------|
| Sync from genesis | ✅ | ✅ | ✅ | ⚠️ |
| Fast sync | ✅ | N/A | ✅ | ✅ |
| Archive mode | ✅ | ✅ | ✅ | ⚠️ |
| RPC compatibility | ✅ | ✅ | ✅ | ⚠️ |
| WebSocket | ✅ | ✅ | ✅ | ⚠️ |
| P2P peering | ✅ | ✅ | ✅ | ⚠️ |
| XDPoS consensus | ✅ | ✅ | ✅ | ⚠️ |

### Automated Test Suite

```bash
#!/bin/bash
# scripts/test-multiclient.sh

set -e

CLIENTS=("geth" "erigon" "nethermind")
TEST_BLOCK="0x5500000"  # Block to validate

echo "=== Multi-Client Integration Test ==="

# 1. Start all clients
echo "Starting clients..."
docker-compose -f docker/docker-compose.multiclient.yml up -d

# 2. Wait for sync
echo "Waiting for sync..."
sleep 300

# 3. Validate block hashes
echo "Validating block hashes..."
for client in "${CLIENTS[@]}"; do
  HASH=$(curl -s -X POST http://localhost:$(get_rpc_port $client) \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$TEST_BLOCK\",false],\"id\":1}" | jq -r '.result.hash')
  echo "$client: $HASH"
done

# 4. Compare hashes
if [ $(echo "$HASHES" | sort -u | wc -l) -eq 1 ]; then
  echo "✓ All clients agree on block hash"
else
  echo "✗ CONSENSUS FAILURE"
  exit 1
fi

# 5. Test RPC compatibility
echo "Testing RPC compatibility..."
for client in "${CLIENTS[@]}"; do
  test_rpc_methods $client
done

echo "=== All tests passed ==="
```

## Performance Comparison

### Sync Performance

| Client | Sync Time (Mainnet) | Disk Usage | Memory (Peak) |
|--------|---------------------|------------|---------------|
| Geth-XDC | ~48 hours | ~500GB | ~16GB |
| Erigon-XDC | ~24 hours | ~400GB | ~12GB |
| Nethermind-XDC | ~36 hours | ~350GB | ~14GB |
| Reth-XDC | ~30 hours | ~300GB | ~10GB |

### RPC Performance

| Method | Geth | Erigon | Nethermind | Reth |
|--------|------|--------|------------|------|
| eth_blockNumber | 1ms | 1ms | 1ms | 1ms |
| eth_getBalance | 2ms | 1ms | 2ms | 1ms |
| eth_getBlockByNumber | 5ms | 2ms | 3ms | 2ms |
| eth_getTransactionReceipt | 10ms | 3ms | 5ms | 3ms |
| debug_traceTransaction | 100ms | 20ms | 50ms | 30ms |

## Troubleshooting

### Port Conflicts

```bash
# Check port usage
sudo lsof -i :8545  # Geth RPC
sudo lsof -i :8547  # Erigon RPC
sudo lsof -i :8558  # Nethermind RPC
sudo lsof -i :30303 # Geth P2P
sudo lsof -i :30304 # Erigon P2P
```

### Resource Allocation

```yaml
# docker-compose.yml resource limits
services:
  xdc-geth:
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 16G
        reservations:
          cpus: '2'
          memory: 8G
  
  xdc-erigon:
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 12G
        reservations:
          cpus: '2'
          memory: 6G
```

### Storage Management

```bash
# Monitor disk usage per client
du -sh data/geth/*
du -sh data/erigon/*
du -sh data/nethermind/*

# Prune old data
./scripts/prune.sh --client geth --keep-last 100000
```

## Best Practices

1. **Use different ports** for each client to avoid conflicts
2. **Monitor resource usage** - running multiple clients is resource-intensive
3. **Use SSD storage** - multiple clients will saturate HDD
4. **Enable pruning** on all clients to manage disk space
5. **Test on testnet first** before running on mainnet
6. **Use monitoring** to track all clients in one place

## References

- [Geth-XDC Documentation](https://github.com/XinFinOrg/XDPoSChain)
- [Erigon-XDC Documentation](https://github.com/XinFinOrg/erigon)
- [Nethermind Documentation](https://docs.nethermind.io/)
- [Reth Documentation](https://reth.rs/)
