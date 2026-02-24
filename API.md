# XDC Node Setup - API Reference
> Complete API documentation for SkyOne

## Table of Contents

1. [Overview](#overview)
2. [JSON-RPC API](#json-rpc-api)
3. [CLI API](#cli-api)
4. [REST API](#rest-api)
5. [WebSocket API](#websocket-api)
6. [Metrics API](#metrics-api)

---

## Overview

SkyOne provides multiple APIs for interacting with your XDC node:

| API Type | Endpoint | Purpose |
|----------|----------|---------|
| JSON-RPC | `http://localhost:8545` | Standard Ethereum-compatible RPC |
| CLI | `xdc` command | Node management and operations |
| REST | `http://localhost:7070/api` | Dashboard and monitoring |
| WebSocket | `ws://localhost:8546` | Real-time subscriptions |
| Metrics | `http://localhost:6060` | Prometheus metrics |

---

## JSON-RPC API

### Standard Methods

#### eth_blockNumber

Returns the current block number.

**Request:**
```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "eth_blockNumber",
    "params": [],
    "id": 1
  }'
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": "0x54e4d8"
}
```

#### eth_getBalance

Returns the balance of an address.

**Request:**
```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "eth_getBalance",
    "params": ["0x...", "latest"],
    "id": 1
  }'
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": "0xde0b6b3a7640000"
}
```

#### eth_sendRawTransaction

Sends a signed transaction.

**Request:**
```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "eth_sendRawTransaction",
    "params": ["0x..."],
    "id": 1
  }'
```

### XDPoS-Specific Methods

#### XDPoS_getMasternodesByNumber

Returns masternodes for a given block number.

**Request:**
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

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "Number": "0x54e4d8",
    "Round": "0x1a",
    "Masternodes": [
      "0x...",
      "0x..."
    ],
    "Standbynodes": [
      "0x..."
    ],
    "Penalty": []
  }
}
```

#### XDPoS_getEpochNumber

Returns the current epoch number.

**Request:**
```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "XDPoS_getEpochNumber",
    "params": ["latest"],
    "id": 1
  }'
```

### Network Methods

#### net_peerCount

Returns the number of connected peers.

**Request:**
```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "net_peerCount",
    "params": [],
    "id": 1
  }'
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": "0x19"
}
```

#### net_version

Returns the current network ID.

**Request:**
```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "net_version",
    "params": [],
    "id": 1
  }'
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": "50"
}
```

### Admin Methods

#### admin_nodeInfo

Returns information about the node.

**Request:**
```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "admin_nodeInfo",
    "params": [],
    "id": 1
  }'
```

#### admin_addTrustedPeer

Adds a trusted peer.

**Request:**
```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "admin_addTrustedPeer",
    "params": ["enode://..."],
    "id": 1
  }'
```

---

## CLI API

### Core Commands

#### xdc status

Display node status and sync progress.

```bash
xdc status
```

**Output:**
```
Node Status
===========
Client: XDC Geth v2.6.8
Network: mainnet
Sync Status: synced
Block Height: 5,554,392
Peers: 25
Uptime: 3d 12h 45m
```

#### xdc start

Start the XDC node.

```bash
# Start with default client
xdc start

# Start with specific client
xdc start --client erigon

# Start with monitoring
xdc start --monitoring
```

#### xdc stop

Stop the XDC node.

```bash
xdc stop
```

#### xdc restart

Restart the node.

```bash
xdc restart
```

### Monitoring Commands

#### xdc logs

View node logs.

```bash
# View last 100 lines
xdc logs

# Follow logs
xdc logs --follow

# View specific client logs
xdc logs --client erigon
```

#### xdc peers

List connected peers.

```bash
xdc peers
```

#### xdc sync

Check sync status.

```bash
xdc sync
```

### Configuration Commands

#### xdc config

Manage configuration.

```bash
# List all config
xdc config list

# Get value
xdc config get rpc_port

# Set value
xdc config set rpc_port 8545
```

### Maintenance Commands

#### xdc backup

Create encrypted backup.

```bash
xdc backup create
```

#### xdc snapshot

Download/apply snapshot.

```bash
# Download snapshot
xdc snapshot download

# Apply snapshot
xdc snapshot apply
```

#### xdc update

Check for updates.

```bash
xdc update
```

---

## REST API

### Dashboard API

#### GET /api/health

Returns node health status.

**Request:**
```bash
curl http://localhost:7070/api/health
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2026-02-25T10:30:00Z",
  "version": "2.6.8"
}
```

#### GET /api/metrics

Returns node metrics.

**Request:**
```bash
curl http://localhost:7070/api/metrics
```

**Response:**
```json
{
  "blockHeight": 5554392,
  "syncProgress": 100,
  "peerCount": 25,
  "cpuPercent": 45.2,
  "memoryPercent": 62.1,
  "diskPercent": 78.0
}
```

#### GET /api/peers

Returns connected peers.

**Request:**
```bash
curl http://localhost:7070/api/peers
```

**Response:**
```json
{
  "peers": [
    {
      "enode": "enode://...",
      "ip": "203.0.113.1",
      "port": 30303,
      "name": "XDC/v2.6.8"
    }
  ],
  "total": 25
}
```

---

## WebSocket API

### Connection

Connect to WebSocket endpoint:

```javascript
const ws = new WebSocket('ws://localhost:8546');
```

### Subscriptions

#### eth_subscribe (newHeads)

Subscribe to new block headers.

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "eth_subscribe",
  "params": ["newHeads"]
}
```

**Notification:**
```json
{
  "jsonrpc": "2.0",
  "method": "eth_subscription",
  "params": {
    "subscription": "0x...",
    "result": {
      "number": "0x54e4d8",
      "hash": "0x...",
      "parentHash": "0x..."
    }
  }
}
```

#### eth_subscribe (logs)

Subscribe to event logs.

**Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "eth_subscribe",
  "params": ["logs", {
    "address": "0x...",
    "topics": ["0x..."]
  }]
}
```

### Unsubscribe

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "eth_unsubscribe",
  "params": ["0x..."]
}
```

---

## Metrics API

### Prometheus Metrics

Access Prometheus metrics at `http://localhost:6060/debug/metrics/prometheus`

#### Chain Metrics

```
# Current block number
chain_head_block{...} 5554392

# Current epoch
chain_head_epoch{...} 6171
```

#### Network Metrics

```
# Connected peers
p2p_peers{...} 25

# Total inbound traffic
p2p_ingress{...} 1.234e+09

# Total outbound traffic
p2p_egress{...} 5.678e+08
```

#### RPC Metrics

```
# Total RPC calls
rpc_calls{...} 123456

# RPC call duration
rpc_duration{...} 0.012
```

### Querying Metrics

```bash
# Get all metrics
curl http://localhost:6060/debug/metrics/prometheus

# Query specific metric
curl http://localhost:6060/debug/metrics/prometheus | grep chain_head_block
```

---

## Error Codes

### JSON-RPC Errors

| Code | Message | Description |
|------|---------|-------------|
| -32700 | Parse error | Invalid JSON |
| -32600 | Invalid request | JSON-RPC request invalid |
| -32601 | Method not found | Method doesn't exist |
| -32602 | Invalid params | Invalid method parameters |
| -32603 | Internal error | Internal JSON-RPC error |
| -32000 | Server error | Generic server error |

### HTTP Status Codes

| Code | Description |
|------|-------------|
| 200 | Success |
| 400 | Bad request |
| 401 | Unauthorized |
| 403 | Forbidden |
| 404 | Not found |
| 500 | Internal server error |
| 503 | Service unavailable |

---

## Client Libraries

### JavaScript (ethers.js)

```javascript
const { ethers } = require('ethers');

const provider = new ethers.JsonRpcProvider('http://localhost:8545');

// Get block number
const blockNumber = await provider.getBlockNumber();
console.log('Block number:', blockNumber);

// Get balance
const balance = await provider.getBalance('0x...');
console.log('Balance:', ethers.formatEther(balance));
```

### Python (web3.py)

```python
from web3 import Web3

w3 = Web3(Web3.HTTPProvider('http://localhost:8545'))

# Check connection
print(f"Connected: {w3.is_connected()}")

# Get block number
block_number = w3.eth.block_number
print(f"Block number: {block_number}")

# Get balance
balance = w3.eth.get_balance('0x...')
print(f"Balance: {w3.from_wei(balance, 'ether')} XDC")
```

### Go (go-ethereum)

```go
package main

import (
    "context"
    "fmt"
    "log"
    
    "github.com/ethereum/go-ethereum/ethclient"
)

func main() {
    client, err := ethclient.Dial("http://localhost:8545")
    if err != nil {
        log.Fatal(err)
    }
    
    header, err := client.HeaderByNumber(context.Background(), nil)
    if err != nil {
        log.Fatal(err)
    }
    
    fmt.Println("Block number:", header.Number)
}
```

---

## Rate Limiting

### Default Limits

| Endpoint | Limit | Window |
|----------|-------|--------|
| JSON-RPC | 100 req | 1 min |
| REST API | 60 req | 1 min |
| WebSocket | 10 conn | - |

### Configuring Limits

Add to your `.env` file:

```bash
RPC_RATE_LIMIT=100
RPC_RATE_WINDOW=60
```

---

## Authentication

### API Key Authentication

For protected endpoints:

```bash
curl -H "Authorization: Bearer YOUR_API_KEY" \
  http://localhost:7070/api/protected
```

### IP Whitelisting

Configure in `mainnet/.xdc-node/.env`:

```bash
RPC_ALLOW_IPS=127.0.0.1,10.0.0.0/8
```

---

## Related Documentation

- [Setup Guide](SETUP.md) - Installation instructions
- [Configuration Guide](CONFIGURATION.md) - Configuration reference
- [Troubleshooting Guide](TROUBLESHOOTING.md) - Common issues
- [Security Guide](SECURITY.md) - Security hardening
