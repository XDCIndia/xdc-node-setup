# FCU (Fork Choice Updated) - Engine API Documentation

## Overview

FCU = `engine_forkchoiceUpdatedV1` - A JSON-RPC method in the **Engine API** (introduced with Ethereum's The Merge).

**Purpose**: Tells the execution client (Reth, Erigon, Geth) which block is the canonical head of the chain. Without FCU, the client doesn't know which blocks to sync toward.

## How It Works

```json
{
  "jsonrpc": "2.0",
  "method": "engine_forkchoiceUpdatedV1",
  "params": [{
    "headBlockHash": "0x...",      // Current tip to sync to
    "safeBlockHash": "0x...",      // Safe block (usually same as head)
    "finalizedBlockHash": "0x..."  // Finalized block (genesis for XDC)
  }],
  "id": 1
}
```

## Why Reth Needs FCU

| Without FCU              | With FCU                 |
| ------------------------ | ------------------------ |
| Pipeline finishes stages | Pipeline knows target    |
| Block stays at 8M        | Syncs to 10M             |
| "Waiting for payload..." | "Downloading headers..." |

## The Flow

```
[Synced Peer] → "Latest block is 10,060,262"
      ↓
[FCU Feeder] → Sends engine_forkchoiceUpdatedV1 to Reth every 30s
      ↓
[Reth] → "OK, my new target is 10,060,262"
      ↓
[Reth Pipeline] → Downloads headers/bodies → Executes → Finishes
```

## How Different Blockchains Handle FCU

### Ethereum Mainnet (The "Proper" Way)

**Architecture**:
- **Consensus Layer**: Lighthouse, Prysm, Lodestar (beacon nodes)
- **Execution Layer**: Reth, Geth, Nethermind, Erigon

**FCU Flow**:
```
[Beacon Node] ← P2P attestation gossip
      ↓
[Fork Choice] ← Determines canonical chain (LMD-GHOST)
      ↓
[engine_forkchoiceUpdatedV1] → Sent to execution client
      ↓
[Reth] ← Updates sync target
```

**Key Points**:
- Beacon nodes run consensus (PoS)
- FCU sent every slot (12 seconds)
- No external feeder needed

### Layer 2 Chains (Optimism, Arbitrum, Base)

**Architecture**:
- **Sequencer** → Orders transactions, creates blocks
- **op-node** → Derives blocks from L1 + sequencer feed
- **op-reth** (Reth fork) → Executes blocks

**FCU Flow**:
```
[Sequencer] → Creates new blocks
      ↓
[op-node] → Derives from L1 + sequencer
      ↓
[engine_forkchoiceUpdatedV1] → Tells op-reth new head
      ↓
[op-reth] ← Syncs to sequencer head
```

**Key Points**:
- `op-node` acts as "beacon node" equivalent
- Sends FCU based on L1 data
- No manual feeder needed

### XDC Network (Custom Solution)

**Problem**: XDPoS v1/v2 doesn't have a beacon node

**Solution**: Custom FCU feeder script

```python
# Query synced peer for latest block
# Generate JWT token from secret  
# Send engine_forkchoiceUpdatedV1 to Reth authrpc
# Repeat every 30 seconds
```

**Why this works**:
- XDPoS consensus happens in network layer
- Use existing synced nodes as "consensus source"
- Feeder bridges the gap

## Implementation

### JWT Authentication
```python
import base64, hashlib, hmac, json, time

def generate_jwt(secret_hex):
    secret = bytes.fromhex(secret_hex)
    header = base64.urlsafe_b64encode(
        json.dumps({"alg": "HS256", "typ": "JWT"}).encode()
    ).rstrip(b"=")
    payload = base64.urlsafe_b64encode(
        json.dumps({"iat": int(time.time())}).encode()
    ).rstrip(b"=")
    msg = header + b"." + payload
    sig = base64.urlsafe_b64encode(
        hmac.new(secret, msg, hashlib.sha256).digest()
    ).rstrip(b"=")
    return (msg + b"." + sig).decode()
```

### FCU Request
```bash
curl -X POST http://localhost:8551 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -d '{
    "jsonrpc": "2.0",
    "method": "engine_forkchoiceUpdatedV1",
    "params": [{
      "headBlockHash": "0x...",
      "safeBlockHash": "0x...",
      "finalizedBlockHash": "0x..."
    }],
    "id": 1
  }'
```

### Response Codes
| Status   | Meaning                          |
| -------- | -------------------------------- |
| SYNCING  | Reth accepted, will sync         |
| VALID    | Block already validated          |
| INVALID  | Block rejected (bad hash/state)  |

## XDC-Specific FCU Feeder Script

See: `/root/fcu-feeder.py` on APO server

Key parameters:
- **Source**: Erigon/GP5 at `http://127.0.0.1:8547`
- **Target**: Reth authrpc at `http://127.0.0.1:8551`
- **JWT Secret**: `/root/reth-apothem-data/jwt.hex`
- **Interval**: 30 seconds
- **Finalized Block**: Apothem genesis hash

---

*Documented: March 9, 2026*  
*For: XDC Multi-Client Implementation*
