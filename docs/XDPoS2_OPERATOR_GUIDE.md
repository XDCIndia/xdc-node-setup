# XDPoS 2.0 Operator Guide

## Overview

This guide provides comprehensive instructions for operating XDC Network nodes with XDPoS 2.0 consensus, including security best practices, monitoring setup, and troubleshooting.

## Table of Contents

1. [XDPoS 2.0 Consensus Basics](#xdpos-20-consensus-basics)
2. [Security Best Practices](#security-best-practices)
3. [Monitoring Setup](#monitoring-setup)
4. [Multi-Client Operations](#multi-client-operations)
5. [Troubleshooting](#troubleshooting)
6. [API Reference](#api-reference)

---

## XDPoS 2.0 Consensus Basics

### Key Concepts

#### Epochs and Gap Blocks
- **Epoch Length**: 900 blocks
- **Gap Block**: The first block of each epoch (block numbers divisible by 900)
- **Purpose**: Signals epoch transition and masternode set changes

#### Quorum Certificates (QC)
- **Definition**: Proof that 2/3+ of masternodes have agreed on a block
- **Formation Time**: Should be < 2 seconds under normal conditions
- **Importance**: Critical for consensus finality

#### Vote and Timeout Mechanisms
- **Vote**: Masternodes vote on blocks during their turn
- **Timeout**: Triggered if QC formation takes too long
- **Round**: A consensus round within an epoch

### Consensus Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Epoch Length | 900 blocks | Time between masternode set changes |
| Block Time | 2 seconds | Target time between blocks |
| QC Threshold | 2/3 + 1 | Required signatures for QC |
| Timeout | 10 seconds | Round timeout duration |

---

## Security Best Practices

### RPC Security

#### 1. Bind RPC to Localhost Only

```bash
# In docker/mainnet/.env
RPC_ADDR=127.0.0.1
WS_ADDR=127.0.0.1
```

#### 2. Restrict CORS Origins

```bash
# Instead of wildcards
RPC_CORS_DOMAIN=http://localhost:7070,http://localhost:3000
RPC_VHOSTS=localhost,127.0.0.1
WS_ORIGINS=http://localhost:7070
```

#### 3. Use nginx Reverse Proxy

```nginx
server {
    listen 8545 ssl;
    server_name xdc-node.example.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=rpc:10m rate=10r/s;
    
    location / {
        limit_req zone=rpc burst=20 nodelay;
        proxy_pass http://127.0.0.1:8545;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### Container Security

#### 1. Run as Non-Root User

```yaml
# In docker-compose.yml
services:
  xdc-node:
    user: "1000:1000"
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETGID
      - SETUID
```

#### 2. Resource Limits

```yaml
deploy:
  resources:
    limits:
      cpus: '4'
      memory: 8G
    reservations:
      cpus: '2'
      memory: 4G
```

### Credential Management

#### 1. Never Commit .env Files

```bash
# Add to .gitignore
echo ".env" >> .gitignore
echo "**/.env" >> .gitignore
echo "**/.pwd" >> .gitignore
```

#### 2. Use .env.example

```bash
# Create template
cp .env .env.example
# Replace values with placeholders
sed -i 's/=.*/=YOUR_VALUE_HERE/g' .env.example
```

#### 3. Secure Key Generation

```bash
# Generate secure API key
openssl rand -hex 32

# Generate secure password
openssl rand -base64 32
```

---

## Monitoring Setup

### XDPoS 2.0 Specific Metrics

#### 1. Gap Block Monitoring

```bash
#!/bin/bash
# gap-block-monitor.sh

EPOCH_LENGTH=900
RPC_URL="http://localhost:8545"

get_block_number() {
    curl -s -X POST $RPC_URL \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        | jq -r '.result' | xargs -I {} printf '%d\n' {}
}

is_gap_block() {
    local block=$1
    local epoch_boundary=$(( (block / EPOCH_LENGTH) * EPOCH_LENGTH ))
    [ "$block" -eq "$epoch_boundary" ]
}

monitor() {
    while true; do
        current_block=$(get_block_number)
        
        if is_gap_block "$current_block"; then
            echo "Gap block detected: $current_block"
            # Send alert
            send_alert "Gap block $current_block produced"
        fi
        
        sleep 2
    done
}
```

#### 2. QC Formation Time Monitoring

```typescript
// qc-monitor.ts
async function monitorQCFormation() {
  const startTime = Date.now();
  
  // Wait for QC
  const qc = await waitForQC(blockNumber);
  
  const formationTime = Date.now() - startTime;
  
  if (formationTime > 5000) {
    // Alert if QC takes > 5 seconds
    sendAlert(`Slow QC formation: ${formationTime}ms`);
  }
  
  return formationTime;
}
```

#### 3. Vote Participation Tracking

```bash
# Track masternode votes
#!/bin/bash

TRACKED_MASTERNODES=(
    "0x..."
    "0x..."
)

check_vote_participation() {
    local epoch=$1
    
    for mn in "${TRACKED_MASTERNODES[@]}"; do
        votes=$(get_votes_for_masternode "$mn" "$epoch")
        
        if [ "$votes" -eq 0 ]; then
            send_alert "Masternode $mn missed all votes in epoch $epoch"
        fi
    done
}
```

### Dashboard Setup

#### SkyOne Dashboard

Access at `http://localhost:7070`

Features:
- Real-time block height
- Peer count
- Sync status
- System metrics

#### SkyNet Integration

```bash
# Enable SkyNet reporting
xdc config set skynet_enabled true
xdc config set skynet_api_key "your-api-key"

# Restart to apply
xdc restart
```

---

## Multi-Client Operations

### Supported Clients

| Client | Status | RPC Port | P2P Port | Memory |
|--------|--------|----------|----------|--------|
| XDC Stable | Production | 8545 | 30303 | 4GB+ |
| XDC Geth PR5 | Testing | 8545 | 30303 | 4GB+ |
| Erigon-XDC | Experimental | 8547 | 30304 | 8GB+ |
| Nethermind-XDC | Beta | 8558 | 30306 | 12GB+ |
| Reth-XDC | Alpha | 7073 | 40303 | 16GB+ |

### Switching Clients

```bash
# Stop current node
xdc stop

# Start with different client
xdc start --client erigon

# Check current client
xdc client
```

### Cross-Client Validation

```bash
# Compare block hashes across clients
#!/bin/bash

CLIENTS=(
    "http://localhost:8545"    # geth
    "http://localhost:8547"    # erigon
    "http://localhost:8558"    # nethermind
)

BLOCK_NUMBER=$(curl -s http://localhost:8545 -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    | jq -r '.result')

echo "Checking block $BLOCK_NUMBER across clients..."

for client in "${CLIENTS[@]}"; do
    hash=$(curl -s "$client" -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$BLOCK_NUMBER\",false],\"id\":1}" \
        | jq -r '.result.hash')
    echo "$client: $hash"
done
```

---

## Troubleshooting

### Common Issues

#### 1. Node Won't Sync

**Symptoms**: Block height not increasing, peer count low

**Solutions**:
```bash
# Check peer count
xdc peers

# Restart with fresh peer discovery
xdc stop
rm -rf mainnet/.xdc-node/geth/nodes
xdc start

# Download snapshot
xdc snapshot download --network mainnet
xdc snapshot apply
```

#### 2. High Resource Usage

**Symptoms**: High CPU, memory, or disk usage

**Solutions**:
```bash
# Reduce memory cache
xdc config set cache 2048
xdc restart

# Enable pruning
xdc config set prune_mode full
xdc restart

# Check disk space
df -h
```

#### 3. RPC Connection Refused

**Symptoms**: Cannot connect to RPC endpoint

**Solutions**:
```bash
# Check RPC is enabled
xdc config get rpc_enabled

# Check RPC is listening
netstat -tlnp | grep 8545

# Check firewall
sudo ufw status
sudo ufw allow 8545/tcp
```

### XDPoS 2.0 Specific Issues

#### 1. Gap Block Delays

**Symptoms**: Gap blocks taking longer than expected

**Check**:
```bash
# Monitor gap block timing
#!/bin/bash
EPOCH=900
last_gap_time=$(get_block_timestamp $(( ($(get_block_number) / EPOCH) * EPOCH )))
current_time=$(date +%s)
delay=$((current_time - last_gap_time))

if [ $delay -gt 30 ]; then
    echo "Gap block delay detected: ${delay}s"
fi
```

#### 2. QC Formation Issues

**Symptoms**: Slow or failed QC formation

**Check**:
- Masternode participation rate
- Network latency between masternodes
- Vote propagation delays

#### 3. Epoch Transition Failures

**Symptoms**: Stuck at epoch boundary

**Solutions**:
```bash
# Check masternode set
get_masternodes_by_number latest

# Restart node if stuck
xdc restart
```

---

## API Reference

### XDPoS 2.0 Specific RPC Methods

#### XDPoS_getMasternodesByNumber

```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "XDPoS_getMasternodesByNumber",
    "params": ["latest"],
    "id": 1
  }'
```

Response:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "Number": "0x54F4B00",
    "Round": 1,
    "Masternodes": ["0x...", "0x..."],
    "Standbynodes": ["0x..."],
    "Penalty": []
  }
}
```

#### XDPoS_getV1BlockByNumber

```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "XDPoS_getV1BlockByNumber",
    "params": ["0x54F4B00"],
    "id": 1
  }'
```

#### eth_getBlockByNumber

```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "eth_getBlockByNumber",
    "params": ["latest", false],
    "id": 1
  }'
```

---

## Appendix

### Useful Commands

```bash
# Check node status
xdc status

# View logs
xdc logs --follow

# Check peers
xdc peers

# Check sync status
xdc sync

# Attach to console
xdc attach

# Backup node data
xdc backup create

# Update node
xdc update
```

### Configuration Files

| File | Purpose |
|------|---------|
| `mainnet/.xdc-node/config.toml` | Node configuration |
| `mainnet/.xdc-node/.env` | Environment variables |
| `docker/docker-compose.yml` | Docker services |
| `docker/mainnet/.pwd` | Keystore password |

### Resources

- [XDC Network Documentation](https://docs.xdc.community/)
- [XDPoS 2.0 Technical Paper](https://www.xdc.dev/xdc-foundation/xdpos-2-0-the-next-evolution-in-xdc-network-consensus-4k9b)
- [GitHub Issues](https://github.com/AnilChinchawale/xdc-node-setup/issues)

---

*Last Updated: March 4, 2026*
