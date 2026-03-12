# XDC EVM Expert Improvement Recommendations

**Date:** March 2, 2026  
**Author:** XDC EVM Expert Agent  
**Scope:** xdc-node-setup and XDCNetOwn repositories

---

## Overview

This document provides detailed improvement recommendations for the XDC node infrastructure, organized by priority and domain. Each recommendation includes implementation approach, code examples, and acceptance criteria.

---

## P0 - Critical Improvements

### 1. XDPoS 2.0 Consensus Monitoring

#### 1.1 Quorum Certificate Validation

**Current State:** No QC validation implemented

**Target State:** Real-time QC monitoring with alerting

**Implementation:**

```typescript
// lib/consensus/qc-monitor.ts
export interface QuorumCertificate {
  blockNumber: number;
  blockHash: string;
  round: number;
  signatures: string[];
  threshold: number;
}

export class QCMonitor {
  async validateQC(blockNumber: number): Promise<{
    valid: boolean;
    signatures: number;
    threshold: number;
    missingValidators: string[];
  }> {
    const block = await this.rpc.call('XDPoS_getV2BlockByNumber', [blockNumber]);
    
    // Verify QC signatures
    const qc = block.quorumCertificate;
    const masternodes = await this.getMasternodesForEpoch(block.epoch);
    
    const validSignatures = await Promise.all(
      qc.signatures.map(sig => this.verifySignature(sig, blockHash, masternodes))
    );
    
    const signatureCount = validSignatures.filter(Boolean).length;
    const threshold = Math.ceil(masternodes.length * 2 / 3);
    
    return {
      valid: signatureCount >= threshold,
      signatures: signatureCount,
      threshold,
      missingValidators: this.getMissingValidators(masternodes, qc.signatures)
    };
  }
}
```

**Acceptance Criteria:**
- [ ] QC validation runs every block
- [ ] Alert when QC threshold not met
- [ ] Track missing validators
- [ ] Historical QC statistics

---

#### 1.2 Gap Block Detection

**Current State:** Basic block height monitoring

**Target State:** Dedicated gap block detection and alerting

**Implementation:**

```typescript
// lib/consensus/gap-monitor.ts
export class GapBlockMonitor {
  private readonly EPOCH_LENGTH = 900;
  
  async detectGapBlocks(epoch: number): Promise<{
    epoch: number;
    gapBlocks: number[];
    expectedBlocks: number;
    actualBlocks: number;
  }> {
    const startBlock = epoch * this.EPOCH_LENGTH;
    const endBlock = startBlock + this.EPOCH_LENGTH - 1;
    
    const gapBlocks: number[] = [];
    
    for (let i = startBlock; i <= endBlock; i++) {
      const block = await this.rpc.getBlockByNumber(i);
      
      // Gap block detection: empty block at epoch boundary
      if (block.transactions.length === 0 && this.isEpochBoundary(i)) {
        gapBlocks.push(i);
      }
    }
    
    return {
      epoch,
      gapBlocks,
      expectedBlocks: this.EPOCH_LENGTH,
      actualBlocks: this.EPOCH_LENGTH - gapBlocks.length
    };
  }
  
  private isEpochBoundary(blockNumber: number): boolean {
    return blockNumber % this.EPOCH_LENGTH === 0;
  }
}
```

---

#### 1.3 Timeout Certificate Monitoring

**Implementation:**

```typescript
// lib/consensus/tc-monitor.ts
export interface TimeoutCertificate {
  round: number;
  timeouts: {
    validator: string;
    signature: string;
  }[];
}

export class TCMonitor {
  async analyzeTimeouts(epoch: number): Promise<{
    totalTimeouts: number;
    byValidator: Map<string, number>;
    consecutiveTimeouts: Map<string, number>;
    potentialIssues: string[];
  }> {
    // Fetch timeout certificates for epoch
    const tcEvents = await this.fetchTCEvents(epoch);
    
    const analysis = {
      totalTimeouts: tcEvents.length,
      byValidator: new Map(),
      consecutiveTimeouts: new Map(),
      potentialIssues: []
    };
    
    // Analyze patterns
    for (const event of tcEvents) {
      const count = analysis.byValidator.get(event.validator) || 0;
      analysis.byValidator.set(event.validator, count + 1);
      
      // Detect consecutive timeouts
      if (await this.isConsecutiveTimeout(event.validator, event.round)) {
        const consecutive = analysis.consecutiveTimeouts.get(event.validator) || 0;
        analysis.consecutiveTimeouts.set(event.validator, consecutive + 1);
      }
    }
    
    // Identify validators with excessive timeouts
    for (const [validator, count] of analysis.byValidator) {
      if (count > this.THRESHOLD) {
        analysis.potentialIssues.push(
          `Validator ${validator} has ${count} timeouts in epoch ${epoch}`
        );
      }
    }
    
    return analysis;
  }
}
```

---

### 2. Security Hardening

#### 2.1 RPC Security Configuration

**Implementation:**

```bash
# scripts/secure-rpc.sh
#!/bin/bash
set -euo pipefail

secure_rpc_configuration() {
  local env_file="${NETWORK}/.xdc-node/.env"
  
  # Backup original
  cp "$env_file" "$env_file.backup"
  
  # Secure RPC configuration
  cat > "$env_file" << 'EOF'
# RPC Security Configuration
RPC_ADDR=127.0.0.1
RPC_PORT=8545
WS_ADDR=127.0.0.1
WS_PORT=8546

# CORS - Restrict to specific origins
RPC_CORS_DOMAIN=http://localhost:7070,https://your-domain.com
RPC_VHOSTS=localhost,127.0.0.1,your-domain.com
WS_ORIGINS=http://localhost:7070,https://your-domain.com

# Disable pprof in production
PPROF_ENABLED=false
PPROF_ADDR=127.0.0.1

# API modules - restrict to necessary only
RPC_API=eth,net,web3,XDPoS
WS_API=eth,net,web3
EOF
  
  echo "✅ RPC secured - bound to localhost only"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  secure_rpc_configuration
fi
```

---

#### 2.2 Secrets Management

**Implementation:**

```typescript
// lib/secrets-manager.ts
import { SecretsManager } from 'aws-sdk';
import { readFileSync } from 'fs';

export class XDCSecretsManager {
  private secrets: Map<string, string> = new Map();
  
  async loadSecrets(): Promise<void> {
    // Priority: Environment > AWS Secrets Manager > File
    
    // 1. Environment variables
    if (process.env.TELEGRAM_BOT_TOKEN) {
      this.secrets.set('telegram_bot_token', process.env.TELEGRAM_BOT_TOKEN);
    }
    
    // 2. AWS Secrets Manager (production)
    if (process.env.AWS_REGION) {
      const client = new SecretsManager({ region: process.env.AWS_REGION });
      const secret = await client.getSecretValue({ 
        SecretId: 'xdc-netown/production' 
      }).promise();
      
      const secrets = JSON.parse(secret.SecretString || '{}');
      Object.entries(secrets).forEach(([key, value]) => {
        this.secrets.set(key, value as string);
      });
    }
    
    // 3. Docker secrets (swarm/kubernetes)
    try {
      const telegramToken = readFileSync(
        '/run/secrets/telegram_bot_token', 
        'utf8'
      ).trim();
      this.secrets.set('telegram_bot_token', telegramToken);
    } catch (e) {
      // Secret not available
    }
  }
  
  get(key: string): string | undefined {
    return this.secrets.get(key);
  }
}
```

---

## P1 - High Priority Improvements

### 3. Multi-Client Performance Monitoring

#### 3.1 Client-Specific Metrics Collection

**Implementation:**

```typescript
// lib/metrics/client-metrics.ts
export interface ClientMetrics {
  clientType: 'geth' | 'erigon' | 'nethermind' | 'reth';
  databaseSize: number;
  memoryUsage: {
    heap: number;
    rss: number;
    external: number;
  };
  cpuUsage: number;
  syncPerformance: {
    blocksPerSecond: number;
    timeToSync: number;
  };
  rpcLatency: {
    eth_blockNumber: number;
    eth_getBlockByNumber: number;
    eth_call: number;
  };
}

export class ClientMetricsCollector {
  async collectMetrics(rpcUrl: string): Promise<ClientMetrics> {
    const clientType = await this.detectClientType(rpcUrl);
    
    const metrics: ClientMetrics = {
      clientType,
      databaseSize: await this.getDatabaseSize(clientType, rpcUrl),
      memoryUsage: await this.getMemoryUsage(clientType, rpcUrl),
      cpuUsage: await this.getCPUUsage(clientType, rpcUrl),
      syncPerformance: await this.getSyncPerformance(rpcUrl),
      rpcLatency: await this.measureRPCLatency(rpcUrl)
    };
    
    return metrics;
  }
  
  private async getDatabaseSize(clientType: string, rpcUrl: string): Promise<number> {
    switch (clientType) {
      case 'geth':
        // Geth: use debug_metrics or estimate from chaindata
        return this.getGethDatabaseSize(rpcUrl);
      case 'erigon':
        // Erigon: use erigon_getInfo
        return this.getErigonDatabaseSize(rpcUrl);
      case 'nethermind':
        // Nethermind: use nethermind_getConfig
        return this.getNethermindDatabaseSize(rpcUrl);
      case 'reth':
        // Reth: use reth_getStatus
        return this.getRethDatabaseSize(rpcUrl);
      default:
        return 0;
    }
  }
}
```

---

#### 3.2 Cross-Client Comparison Dashboard

**Implementation:**

```typescript
// app/api/v1/clients/comparison/route.ts
export async function GET(request: Request) {
  const clients = [
    { name: 'geth', url: process.env.GETH_RPC_URL },
    { name: 'erigon', url: process.env.ERIGON_RPC_URL },
    { name: 'nethermind', url: process.env.NETHERMIND_RPC_URL },
    { name: 'reth', url: process.env.RETH_RPC_URL }
  ].filter(c => c.url);
  
  const comparison = await Promise.all(
    clients.map(async (client) => {
      const blockNumber = await getBlockNumber(client.url!);
      const peerCount = await getPeerCount(client.url!);
      const syncStatus = await getSyncStatus(client.url!);
      const dbSize = await getDatabaseSize(client.url!, client.name);
      
      return {
        client: client.name,
        blockNumber,
        peerCount,
        syncStatus,
        dbSize,
        healthy: peerCount > 0 && !syncStatus.syncing
      };
    })
  );
  
  // Detect divergence
  const blockNumbers = comparison.map(c => c.blockNumber);
  const maxBlock = Math.max(...blockNumbers);
  const minBlock = Math.min(...blockNumbers);
  const divergence = maxBlock - minBlock;
  
  return Response.json({
    comparison,
    divergence,
    consensus: divergence < 10 ? 'healthy' : 'at-risk'
  });
}
```

---

### 4. Automated Sync Stall Recovery

**Implementation:**

```bash
# scripts/sync-recovery.sh
#!/bin/bash
set -euo pipefail

# Configuration
STALL_THRESHOLD=300  # 5 minutes without block progress
RECOVERY_ACTIONS=("add_peers" "restart" "snapshot_sync")

log() {
  echo "[$(date -Iseconds)] $1"
}

detect_sync_stall() {
  local rpc_url="${1:-http://127.0.0.1:8545}"
  local state_file="/tmp/xdc-sync-state.json"
  
  # Get current block
  local current_block
  current_block=$(curl -s -X POST "$rpc_url" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    | jq -r '.result' | xargs -I {} printf "%d\n" {})
  
  # Load previous state
  local last_block=0
  local last_check=0
  if [[ -f "$state_file" ]]; then
    last_block=$(jq -r '.block // 0' "$state_file")
    last_check=$(jq -r '.timestamp // 0' "$state_file")
  fi
  
  local now=$(date +%s)
  
  # Check for stall
  if [[ "$current_block" -le "$last_block" ]]; then
    local stalled_for=$((now - last_check))
    
    if [[ "$stalled_for" -gt "$STALL_THRESHOLD" ]]; then
      log "⚠️ Sync stall detected! Block: $current_block, Stalled for: ${stalled_for}s"
      return 1
    fi
  fi
  
  # Save state
  echo "{\"block\": $current_block, \"timestamp\": $now}" > "$state_file"
  return 0
}

recover_sync() {
  local action="${1:-add_peers}"
  
  case "$action" in
    add_peers)
      log "🔄 Attempting peer injection..."
      /opt/xdc-node/scripts/inject-peers.sh
      ;;
    restart)
      log "🔄 Restarting node..."
      docker restart xdc-node || systemctl restart xdc-node
      ;;
    snapshot_sync)
      log "🔄 Initiating snapshot sync..."
      /opt/xdc-node/scripts/snapshot-download.sh --auto
      ;;
  esac
}

# Main
main() {
  if ! detect_sync_stall "${1:-}"; then
    # Try recovery actions in sequence
    for action in "${RECOVERY_ACTIONS[@]}"; do
      recover_sync "$action"
      sleep 60
      
      # Check if recovered
      if detect_sync_stall "${1:-}"; then
        log "✅ Sync recovered after: $action"
        exit 0
      fi
    done
    
    log "❌ All recovery actions failed"
    # Send alert
    /opt/xdc-node/scripts/send-alert.sh "Sync stall recovery failed"
    exit 1
  fi
}

main "$@"
```

---

### 5. Data Retention and Optimization

**Implementation:**

```sql
-- migrations/20240302000001_add_retention_policy.sql

-- Create partition function for time-series tables
CREATE OR REPLACE FUNCTION create_monthly_partition(
  table_name TEXT,
  year INT,
  month INT
) RETURNS VOID AS $$
DECLARE
  partition_name TEXT;
  start_date DATE;
  end_date DATE;
BEGIN
  partition_name := table_name || '_' || year || '_' || LPAD(month::TEXT, 2, '0');
  start_date := MAKE_DATE(year, month, 1);
  end_date := start_date + INTERVAL '1 month';
  
  EXECUTE format(
    'CREATE TABLE IF NOT EXISTS %I PARTITION OF %I
     FOR VALUES FROM (%L) TO (%L)',
    partition_name, table_name, start_date, end_date
  );
END;
$$ LANGUAGE plpgsql;

-- Partition existing tables
ALTER TABLE node_metrics 
  PARTITION BY RANGE (collected_at);

ALTER TABLE peer_snapshots 
  PARTITION BY RANGE (collected_at);

-- Create retention policy function
CREATE OR REPLACE FUNCTION apply_retention_policy(
  table_name TEXT,
  retention_days INT
) RETURNS VOID AS $$
DECLARE
  cutoff_date DATE;
BEGIN
  cutoff_date := CURRENT_DATE - retention_days;
  
  -- Drop old partitions
  FOR partition IN
    SELECT inhrelid::regclass::text
    FROM pg_inherits
    WHERE inhparent = table_name::regclass
  LOOP
    EXECUTE format(
      'DROP TABLE IF EXISTS %I',
      partition
    );
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Schedule retention job
SELECT cron.schedule(
  'retention-node-metrics',
  '0 2 * * *',
  'SELECT apply_retention_policy(''node_metrics'', 90)'
);
```

---

## P2 - Medium Priority Improvements

### 6. Kubernetes Operator

**Implementation:**

```yaml
# k8s/operator/crd.yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: xdcnodes.xdc.io
spec:
  group: xdc.io
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                client:
                  type: string
                  enum: [geth, erigon, nethermind, reth]
                network:
                  type: string
                  enum: [mainnet, testnet, devnet]
                nodeType:
                  type: string
                  enum: [full, archive, masternode]
                resources:
                  type: object
                  properties:
                    cpu:
                      type: string
                    memory:
                      type: string
                    storage:
                      type: string
                monitoring:
                  type: object
                  properties:
                    enabled:
                      type: boolean
                    skynet:
                      type: boolean
  scope: Namespaced
  names:
    plural: xdcnodes
    singular: xdcnode
    kind: XDCNode
    shortNames:
      - xdc
```

---

### 7. Integration Testing Framework

**Implementation:**

```typescript
// tests/integration/multi-client.test.ts
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { XDCNode } from './fixtures/xdc-node';
import { DivergenceDetector } from '../lib/divergence-detector';

describe('Multi-Client Integration', () => {
  const clients = ['geth', 'erigon', 'nethermind'];
  const nodes: Map<string, XDCNode> = new Map();
  
  beforeAll(async () => {
    // Start all clients
    for (const client of clients) {
      const node = new XDCNode(client);
      await node.start();
      nodes.set(client, node);
    }
    
    // Wait for sync
    await Promise.all(
      Array.from(nodes.values()).map(n => n.waitForSync())
    );
  });
  
  afterAll(async () => {
    // Cleanup
    for (const node of nodes.values()) {
      await node.stop();
    }
  });
  
  it('should maintain consensus across all clients', async () => {
    const detector = new DivergenceDetector({
      clients: clients.map(c => ({
        name: c,
        type: c as any,
        rpcUrl: nodes.get(c)!.rpcUrl,
        enabled: true
      }))
    });
    
    // Check 10 consecutive blocks
    for (let i = 0; i < 10; i++) {
      const latest = await nodes.get('geth')!.getBlockNumber();
      const report = await detector.forceCheck(latest - 6);
      
      expect(report).toBeNull();
      
      // Wait for next block
      await new Promise(r => setTimeout(r, 2000));
    }
  });
  
  it('should handle client restart gracefully', async () => {
    const geth = nodes.get('geth')!;
    
    // Restart geth
    await geth.restart();
    
    // Should re-sync and match others
    await geth.waitForSync();
    
    const detector = new DivergenceDetector();
    const latest = await geth.getBlockNumber();
    const report = await detector.forceCheck(latest - 3);
    
    expect(report).toBeNull();
  });
});
```

---

### 8. Documentation Improvements

#### 8.1 XDPoS 2.0 Operator Guide

```markdown
# XDPoS 2.0 Operator Guide

## Overview

XDPoS 2.0 is the consensus mechanism used by XDC Network. This guide covers operational aspects for node operators.

## Epochs

- **Epoch Length**: 900 blocks (~30 minutes)
- **Epoch Transition**: Occurs at block numbers divisible by 900
- **Gap Blocks**: Empty blocks at epoch boundaries (expected behavior)

## Quorum Certificates (QC)

### What is a QC?

A Quorum Certificate is cryptographic proof that 2/3+ of masternodes have agreed on a block.

### Monitoring QCs

```bash
# Check QC for latest block
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "XDPoS_getV2BlockByNumber",
    "params": ["latest"],
    "id": 1
  }'
```

### Troubleshooting QC Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| QC threshold not met | Insufficient validators | Check network connectivity |
| Missing signatures | Validator offline | Restart validator node |
| QC timeout | Network latency | Check peer connections |

## Timeout Certificates (TC)

TCs are issued when consensus cannot be reached within the timeout period.

### Monitoring Timeouts

```bash
# View timeout statistics
xdc consensus timeouts --epoch 12345
```

## Masternode Operations

### Becoming a Masternode

1. Stake 10,000,000 XDC
2. Run a full node
3. Register as candidate
4. Get elected

### Monitoring Performance

```bash
# Check masternode status
xdc masternode status

# View missed blocks
xdc masternode missed-blocks --last-epoch 10
```
```

---

## Implementation Priority Matrix

| Improvement | Effort | Impact | Priority | Owner |
|-------------|--------|--------|----------|-------|
| QC Monitoring | Medium | High | P0 | Consensus Team |
| Gap Block Detection | Low | High | P0 | Monitoring Team |
| RPC Security | Low | Critical | P0 | Security Team |
| Secrets Management | Medium | Critical | P0 | Security Team |
| Client Metrics | Medium | Medium | P1 | Performance Team |
| Sync Recovery | Medium | High | P1 | Operations Team |
| Data Retention | Low | Medium | P1 | DBA Team |
| K8s Operator | High | Medium | P2 | Platform Team |
| Integration Tests | High | High | P2 | QA Team |

---

## Acceptance Criteria Summary

### P0 Items
- [ ] QC validation alerts when threshold not met
- [ ] Gap block detection with < 1 minute latency
- [ ] RPC bound to 127.0.0.1 by default
- [ ] No secrets in repository
- [ ] All API endpoints authenticated

### P1 Items
- [ ] Client comparison dashboard
- [ ] Automatic sync stall recovery
- [ ] 90-day data retention policy
- [ ] Rate limiting on all endpoints
- [ ] TLS for all services

### P2 Items
- [ ] Kubernetes operator functional
- [ ] Integration tests in CI
- [ ] Complete operator documentation
- [ ] ARM64 native support

---

*Document generated by XDC EVM Expert Agent*
