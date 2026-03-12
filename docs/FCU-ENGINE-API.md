# FCU (Fork Choice Updated) - Engine API Documentation

## Overview

FCU = `engine_forkchoiceUpdatedV1` — a JSON-RPC method in the **Engine API** introduced with Ethereum's The Merge.

**Purpose**: Tells the execution client (Reth, Erigon, Geth) which block is the canonical head of the chain. Without FCU, the client doesn't know which blocks to sync toward.

> **XDC-specific**: Since XDC uses XDPoS (not PoS), there is no beacon node to send FCU. A custom **FCU feeder script** bridges this gap by querying a synced peer and forwarding the head to Reth's Engine API.

## How It Works

```json
{
  "jsonrpc": "2.0",
  "method": "engine_forkchoiceUpdatedV1",
  "params": [{
    "headBlockHash": "0x...",      // Current tip to sync to
    "safeBlockHash": "0x...",      // Safe block (usually same as head)
    "finalizedBlockHash": "0x..."  // Finalized block (MUST be genesis for XDC)
  }],
  "id": 1
}
```

### Critical: `finalizedBlockHash` MUST be Genesis

Using the latest block hash as `finalizedBlockHash` causes the pipeline to **unwind on every FCU** because the finalized target changes each time. Always use the network's genesis hash.

## XDC Network Deployments

### Network Configuration

| Parameter | Apothem (Testnet) | Mainnet |
|-----------|-------------------|---------|
| Chain ID | 51 | 50 |
| Genesis Hash | `0xbdea512b...640075` | `0x4a9d748b...42d6b1` |
| Reth RPC Port | 8588 | 8588 |
| Reth AuthRPC Port | 8552 | 8551 |
| Reth P2P Port | 30309 | 30309 |
| Source Peer | GP5 at `:8545` or Erigon at `:8547` | Stable XDC at `:8549` or GP5 at `:8545` |
| JWT Secret Path | `/root/reth-apothem-data/jwt.hex` | `/root/reth-mainnet-data/jwt.hex` |
| FCU Interval | 30 seconds | 30 seconds |
| Docker Image | `anilchinchawale/rethx:apothem-backfill` | `anilchinchawale/rethx:latest` |

### Full Genesis Hashes

```
# Apothem (Chain ID 51)
0xbdea512b4f12ff1135ec92c00dc047ffb93890c2ea1aa0eefe9b013d80640075

# Mainnet (Chain ID 50)
0x4a9d748bd78a8d0385b67788c2435dcdb914f98a96250b68863a1f8b7642d6b1
```

### Server Deployments

| Server | IP | SSH Port | Network | Reth Status |
|--------|-----|----------|---------|-------------|
| APO | 185.180.220.183 | 52316 | Apothem | Syncing via FCU feeder |
| TEST | 95.217.56.168 | 12141 | Mainnet | Connected via xdc-net Docker |
| PROD | 65.21.27.213 | 12141 | Mainnet | Pending (ECIES blocked) |

## Why Reth Needs FCU

| Without FCU | With FCU |
|-------------|----------|
| Pipeline finishes stages, stops | Pipeline knows target, continues |
| Block number stays frozen | Syncs to network tip |
| "Waiting for payload..." | "Downloading headers..." |
| Must manually restart | Automatic continuous sync |

### The Sync Flow

```
[Synced Peer (GP5/Erigon)] → eth_getBlockByNumber("latest")
        ↓
[FCU Feeder Script] → Generates JWT, sends engine_forkchoiceUpdatedV1
        ↓
[Reth Engine API] → Validates FCU, sets new sync target
        ↓
[Reth Pipeline] → 13 stages: Headers → Bodies → Execution → Finish
        ↓
[Pipeline Complete] → Waits for next FCU (30s interval)
```

## How Other Blockchains Handle FCU

### Ethereum Mainnet (PoS — The Native Way)

```
[Beacon Node] ← P2P attestation gossip (every 12s slot)
      ↓
[Fork Choice (LMD-GHOST)] ← Determines canonical chain
      ↓
[engine_forkchoiceUpdatedV1] → Sent to Reth via authenticated HTTP
      ↓
[Reth] ← Updates sync target, runs pipeline
```

- **No external feeder needed** — beacon node (Lighthouse/Prysm/Lodestar) handles it
- FCU sent every slot (12 seconds)
- `finalizedBlockHash` advances naturally via PoS finality (~13 min)

### Layer 2 Chains (Optimism/Base using op-reth)

```
[L1 Ethereum] ← Batch data posted by Sequencer
      ↓
[op-node] ← Derives L2 blocks from L1 data + sequencer feed
      ↓
[engine_forkchoiceUpdatedV1] → Tells op-reth the new L2 head
      ↓
[op-reth] ← Syncs to derived head
```

- **`op-node` acts as beacon equivalent** — no manual feeder
- FCU frequency depends on L1 block time + sequencer speed
- `finalizedBlockHash` tied to L1 finality

### XDC Network (XDPoS — Custom FCU Feeder)

```
[XDPoS Consensus] ← Happens in P2P layer (V1: PoA, V2: BFT)
      ↓
[No beacon node exists] ← Gap in architecture
      ↓
[FCU Feeder Script] ← Bridges the gap
      ↓
[Reth Engine API] ← Receives synthetic FCU
```

- **Manual feeder required** — XDPoS has no Engine API integration
- Feeder queries any synced peer (Erigon, GP5, Stable XDC)
- `finalizedBlockHash` = genesis hash (XDPoS finality not mapped to Engine API)
- If feeder stops, Reth pipeline stops after current cycle

## FCU Feeder Script

### Complete Implementation (`fcu-feeder.py`)

```python
#!/usr/bin/env python3
"""
XDC Reth FCU Feeder - Bridges XDPoS consensus to Reth's Engine API.

Usage:
  # Apothem
  NETWORK=apothem python3 fcu-feeder.py

  # Mainnet
  NETWORK=mainnet python3 fcu-feeder.py
"""
import base64, hashlib, hmac, json, os, time, urllib.request

# Network configs
NETWORKS = {
    "apothem": {
        "genesis": "0xbdea512b4f12ff1135ec92c00dc047ffb93890c2ea1aa0eefe9b013d80640075",
        "source": "http://127.0.0.1:8545",      # GP5 RPC
        "target": "http://127.0.0.1:8552",       # Reth authrpc
        "jwt_file": "/root/reth-apothem-data/jwt.hex",
    },
    "mainnet": {
        "genesis": "0x4a9d748bd78a8d0385b67788c2435dcdb914f98a96250b68863a1f8b7642d6b1",
        "source": "http://127.0.0.1:8549",       # Stable XDC RPC
        "target": "http://127.0.0.1:8551",       # Reth authrpc
        "jwt_file": "/root/reth-mainnet-data/jwt.hex",
    }
}

def create_jwt(secret_hex):
    """Generate HS256 JWT token for Engine API authentication."""
    secret = bytes.fromhex(secret_hex.strip().lstrip("0x"))
    def b64url(data):
        return base64.urlsafe_b64encode(data).rstrip(b"=")
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload = b64url(json.dumps({"iat": int(time.time())}).encode())
    message = header + b"." + payload
    signature = b64url(hmac.new(secret, message, hashlib.sha256).digest())
    return (message + b"." + signature).decode()

def rpc_call(url, method, params, jwt_token=None):
    """Send JSON-RPC request with optional JWT auth."""
    data = json.dumps({"jsonrpc": "2.0", "method": method, "params": params, "id": 1}).encode()
    headers = {"Content-Type": "application/json"}
    if jwt_token:
        headers["Authorization"] = f"Bearer {jwt_token}"
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": {"message": str(e)}}

def main():
    network = os.environ.get("NETWORK", "apothem")
    config = NETWORKS.get(network)
    if not config:
        print(f"Unknown network: {network}. Use: apothem or mainnet")
        return

    with open(config["jwt_file"]) as f:
        jwt_secret = f.read().strip()

    print(f"FCU Feeder [{network}]")
    print(f"  Source: {config['source']}")
    print(f"  Target: {config['target']}")
    print(f"  Genesis: {config['genesis'][:20]}...")

    last_hash = None
    errors = 0

    while True:
        try:
            # 1. Get latest block from synced peer
            result = rpc_call(config["source"], "eth_getBlockByNumber", ["latest", False])
            block = result.get("result")
            if not block:
                print(f"[WARN] No block from source: {result.get('error', {}).get('message', '?')}")
                errors += 1
                time.sleep(5)
                continue

            block_hash = block["hash"]
            block_num = int(block["number"], 16)

            # Skip if same block (no new blocks)
            if block_hash == last_hash:
                time.sleep(30)
                continue

            # 2. Generate fresh JWT token
            jwt_token = create_jwt(jwt_secret)

            # 3. Send FCU to Reth
            fcu_state = {
                "headBlockHash": block_hash,
                "safeBlockHash": block_hash,
                "finalizedBlockHash": config["genesis"]  # ALWAYS genesis!
            }
            result = rpc_call(config["target"], "engine_forkchoiceUpdatedV1",
                            [fcu_state, None], jwt_token)

            # 4. Parse response
            if "result" in result:
                status = result["result"].get("payloadStatus", {}).get("status", "?")
            else:
                status = f"ERR: {result.get('error', {}).get('message', '?')}"

            ts = time.strftime("%H:%M:%S")
            print(f"[{ts}] Block {block_num:,} ({block_hash[:16]}...) → {status}")
            last_hash = block_hash
            errors = 0

        except KeyboardInterrupt:
            print("\nStopped.")
            break
        except Exception as e:
            errors += 1
            print(f"[ERROR] {e}")

        # Back off on repeated errors
        sleep_time = min(30 * (2 ** min(errors, 4)), 480) if errors > 3 else 30
        time.sleep(sleep_time)

if __name__ == "__main__":
    main()
```

### Running the Feeder

```bash
# Apothem (default)
nohup python3 fcu-feeder.py > /tmp/fcu-feeder.log 2>&1 &

# Mainnet
NETWORK=mainnet nohup python3 fcu-feeder.py > /tmp/fcu-feeder-mainnet.log 2>&1 &

# Check status
ps aux | grep fcu-feeder
tail -f /tmp/fcu-feeder.log
```

### Systemd Service (Recommended for Production)

```ini
# /etc/systemd/system/fcu-feeder@.service
[Unit]
Description=XDC Reth FCU Feeder (%i)
After=docker.service
Requires=docker.service

[Service]
Type=simple
Environment=NETWORK=%i
ExecStart=/usr/bin/python3 /opt/xdc-node-setup/scripts/fcu-feeder.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
# Enable for both networks
systemctl enable --now fcu-feeder@apothem
systemctl enable --now fcu-feeder@mainnet
```

## Troubleshooting

### Reth Stuck / Pipeline Not Advancing

**Symptom**: `eth_blockNumber` returns the same value for minutes

**Diagnosis**:
```bash
# Check if feeder is running
ps aux | grep fcu-feeder

# Check feeder logs
tail -20 /tmp/fcu-feeder.log

# Check Reth logs for pipeline status
docker logs --tail=20 xdc-apothem-reth 2>&1 | grep -i "pipeline\|stage"
```

**Fix — Send Manual FCU**:
```bash
# 1. Get latest block hash from a synced peer
BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest",false],"id":1}' \
  http://127.0.0.1:8545 | jq -r '.result.hash')

# 2. Generate JWT and send FCU (use Python one-liner)
python3 -c "
import base64,hashlib,hmac,json,time,urllib.request
secret = bytes.fromhex(open('/root/reth-apothem-data/jwt.hex').read().strip())
b64 = lambda d: base64.urlsafe_b64encode(d).rstrip(b'=')
h = b64(json.dumps({'alg':'HS256','typ':'JWT'}).encode())
p = b64(json.dumps({'iat':int(time.time())}).encode())
t = (h+b'.'+p+b'.'+b64(hmac.new(secret,h+b'.'+p,hashlib.sha256).digest())).decode()
fcu = {'jsonrpc':'2.0','method':'engine_forkchoiceUpdatedV1','params':[{
  'headBlockHash':'$BLOCK',
  'safeBlockHash':'$BLOCK',
  'finalizedBlockHash':'0xbdea512b4f12ff1135ec92c00dc047ffb93890c2ea1aa0eefe9b013d80640075'
}],'id':1}
r = urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8552',
  json.dumps(fcu).encode(),{'Content-Type':'application/json','Authorization':f'Bearer {t}'}),timeout=10)
print(json.loads(r.read()))
"
```

**Expected response**: `{"payloadStatus": {"status": "SYNCING"}}`

### Pipeline Unwinding Repeatedly

**Symptom**: Logs show "Unwinding" after every FCU

**Cause**: `finalizedBlockHash` set to latest block instead of genesis

**Fix**: Always use genesis hash as `finalizedBlockHash`:
- Apothem: `0xbdea512b4f12ff1135ec92c00dc047ffb93890c2ea1aa0eefe9b013d80640075`
- Mainnet: `0x4a9d748bd78a8d0385b67788c2435dcdb914f98a96250b68863a1f8b7642d6b1`

### JWT Authentication Failure

**Symptom**: `401 Unauthorized` or `Invalid JWT`

**Causes**:
1. Wrong JWT secret file path
2. Clock skew > 60 seconds between feeder and Reth
3. Secret file has extra whitespace or `0x` prefix

**Fix**:
```bash
# Verify JWT secret
cat /root/reth-apothem-data/jwt.hex | xxd | head -1

# Check time sync
date && docker exec xdc-apothem-reth date
```

### Source Peer Not Responding

**Symptom**: Feeder logs "No block from source"

**Fix**: Switch to a different synced peer:
```bash
# Check which peers are responding
for port in 8545 8547 8549 8557; do
  echo -n "Port $port: "
  curl -s -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://127.0.0.1:$port 2>/dev/null | jq -r '.result // "OFFLINE"'
done
```

## Architecture: Why XDC Needs a Feeder

```
┌─────────────────────────────────────────────────────┐
│                   Ethereum PoS                       │
│                                                      │
│  [Beacon Node] ──FCU──> [Reth]                       │
│       ↑                                              │
│  Consensus built-in                                  │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│                   XDC Network                        │
│                                                      │
│  [XDPoS V1/V2] ──P2P──> [Geth/Erigon/NM]           │
│       ↑                       │                      │
│  Consensus in P2P layer       │ synced blocks        │
│                               ↓                      │
│                    [FCU Feeder] ──FCU──> [Reth]      │
│                                                      │
│  Feeder bridges XDPoS consensus to Engine API        │
└─────────────────────────────────────────────────────┘
```

The fundamental gap: Reth was designed for PoS Ethereum where a beacon node drives sync via Engine API. XDC's XDPoS consensus lives in the P2P/network layer of clients like Geth and Erigon. The FCU feeder translates between these two worlds.

## Reth Pipeline Stages (Reference)

When FCU triggers a sync, Reth runs 13 pipeline stages:

| Stage | Name | Description |
|-------|------|-------------|
| 1/13 | Headers | Download block headers from peers |
| 2/13 | Bodies | Download block bodies |
| 3/13 | SenderRecovery | Recover transaction senders via ECDSA |
| 4/13 | Execution | Execute all transactions |
| 5/13 | AccountHashing | Hash account state |
| 6/13 | StorageHashing | Hash storage state |
| 7/13 | MerkleUnwind | Compute state root |
| 8/13 | AccountHistory | Index account history |
| 9/13 | StorageHistory | Index storage history |
| 10/13 | LogIndex | Index transaction logs |
| 11/13 | TxLookup | Index transaction hashes |
| 12/13 | Prune | Remove old data per config |
| 13/13 | Finish | Finalize checkpoint |

After stage 13, RPC (`eth_blockNumber`) updates to the new checkpoint.

---

*Documented: March 9, 2026*
*Updated: March 9, 2026 — Added mainnet config, full feeder script, troubleshooting*
*For: XDC Multi-Client Implementation*
