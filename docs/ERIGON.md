# Erigon-XDC Client Guide

Run the XDC Network using the **Erigon** execution client for improved network diversity and resilience.

> **Status**: Erigon-XDC is experimental. It connects to XDC mainnet peers via `eth/63` protocol and syncs blocks. Multi-client diversity is the goal.

---

## Quick Start

The fastest way to run an Erigon-XDC node is using the xdc-node-setup toolkit:

```bash
# Clone the repository
git clone https://github.com/AnilChinchawale/xdc-node-setup.git
cd xdc-node-setup

# Run setup with Erigon client
bash setup.sh --client erigon

# Or if already set up, start with Erigon
xdc start --client erigon
```

The setup script will:
- ✅ Build Erigon-XDC from source (takes ~10-15 minutes)
- ✅ Configure dual P2P sentries (eth/63 + eth/68)
- ✅ Set up RPC on port 8547
- ✅ Deploy SkyOne dashboard for monitoring
- ✅ Register with SkyNet fleet dashboard

**Check status:**

```bash
xdc status        # Node sync progress
xdc peers         # Connected peers
xdc info          # Full node information
```

---

## What is Erigon-XDC?

**Erigon-XDC** is a port of the [Erigon](https://github.com/ledgerwatch/erigon) Ethereum client adapted for the XDC Network. It provides:

### Multi-Client Diversity
Running different client implementations on the XDC Network:
- ✅ **Prevents single points of failure** — A bug in one client won't halt the network
- ✅ **Improves decentralization** — Different codebases = more resilient consensus
- ✅ **Enables innovation** — Test new features without affecting production nodes
- ✅ **Catches consensus issues early** — Client disagreements surface bugs before they spread

### Erigon Advantages
- **Efficient storage** — Flat database structure reduces disk space requirements
- **Fast sync** — Optimized staged sync architecture
- **Low memory** — Better resource utilization vs standard geth
- **Modular design** — Separated P2P, RPC, and execution components

**Repository:** [github.com/AnilChinchawale/erigon-xdc](https://github.com/AnilChinchawale/erigon-xdc)

---

## Architecture

Erigon uses a **multi-sentry architecture** where P2P networking is separated from the core execution engine:

```
┌─────────────────────────────────────────────────────────────┐
│                      Erigon-XDC Node                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐           gRPC :9092        ┌──────────┐ │
│  │   Erigon     │◄──────────────────────────►│ Sentry 1 │ │
│  │   Core       │                             │ eth/63   │ │
│  │  (Execution) │◄─┐                          │ :30304   │ │
│  └──────────────┘  │                          └────┬─────┘ │
│         ▲          │                               │       │
│         │ RPC      │  gRPC :9092                   │ P2P   │
│         │ :8547    │                               ▼       │
│  ┌──────┴──────┐  └───────────────────────►┌──────────┐   │
│  │  HTTP RPC   │                            │ Sentry 2 │   │
│  │   Server    │                            │ eth/68   │   │
│  └─────────────┘                            │ :30311   │   │
│                                             └────┬─────┘   │
└──────────────────────────────────────────────────┼─────────┘
                                                   │
                     ┌─────────────────────────────┼──────────────────┐
                     │ XDC Network                 │                  │
                     ▼                             ▼                  │
          ┌──────────────────┐         ┌──────────────────┐          │
          │  XDC Geth Node   │         │  Ethereum Node   │          │
          │  eth/62, eth/63  │         │  eth/68          │          │
          │  :30303          │         │  :30303          │          │
          └──────────────────┘         └──────────────────┘          │
                     ▲                                                │
                     │                                                │
                     └────────────────────────────────────────────────┘
```

**Key Components:**
- **Core Engine** — Executes blocks, manages state, stores blockchain data
- **Sentry 1 (eth/63)** — XDC-compatible P2P networking on port 30304
- **Sentry 2 (eth/68)** — Standard Ethereum P2P on port 30311 (not XDC-compatible)
- **gRPC** — Internal communication between core and sentries
- **HTTP RPC** — JSON-RPC API for external clients

---

## Peer Connection (CRITICAL)

> ⚠️ **WARNING - P2P Port Compatibility**
> 
> **Port 30304 (eth/63)** is for **XDC peers** — this is the ONLY port compatible with XDC geth nodes.
> 
> **Port 30311 (eth/68)** is NOT compatible with XDC geth nodes — it uses a newer Ethereum protocol that XDC nodes do not support.
> 
> **Always use port 30304** when connecting Erigon to XDC geth nodes or when advertising your enode to other XDC nodes.

### Understanding Dual Sentries

Erigon runs **TWO separate P2P sentries** on different ports with different protocol versions:

| Sentry | Port | Protocol | XDC Compatible | Use For |
|--------|------|----------|----------------|---------|
| **Sentry 1** | **30304** | **eth/63** | ✅ **YES** | **XDC geth nodes** |
| Sentry 2 | 30311 | eth/68 | ❌ NO | Standard Ethereum nodes (NOT XDC) |

**XDC Network Reality:**
- XDC geth nodes only support: `eth/62`, `eth/63`, `eth/100`
- They **DO NOT** support `eth/68`
- You **MUST** connect XDC peers to port **30304** (eth/63 sentry)
- Port 30311 is for future Ethereum compatibility testing only

### Connecting XDC Peers

#### Option 1: Add Erigon Peer to XDC Geth Node

From your **XDC geth node**, add the Erigon node as a trusted peer:

```bash
# Get Erigon's enode (from Erigon server)
ENODE=$(curl -s -X POST http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' \
  | jq -r '.result.enode')

# CRITICAL: Replace [::]  with your public IP
# CRITICAL: Change port 30311 → 30304 for eth/63
PUBLIC_IP=$(curl -s ifconfig.me)
ENODE_63=$(echo $ENODE | sed "s/@\[::\]/@$PUBLIC_IP/" | sed 's/:30311/:30304/')

echo "Erigon enode (eth/63): $ENODE_63"
```

**Then from your XDC geth node:**

```bash
# Use admin_addTrustedPeer to bypass maxpeers limit
curl -X POST http://GETH_RPC:8545 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addTrustedPeer\",\"params\":[\"$ENODE_63\"],\"id\":1}"
```

#### Option 2: Add Geth Peer to Erigon

From your **Erigon node**, add XDC geth nodes:

```bash
# Get geth enode (from geth server)
GETH_ENODE=$(curl -s -X POST http://GETH_IP:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' \
  | jq -r '.result.enode')

# Add to Erigon
curl -X POST http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addPeer\",\"params\":[\"$GETH_ENODE\"],\"id\":1}"
```

### Why admin_addTrustedPeer?

On the **geth side**, use `admin_addTrustedPeer` instead of `admin_addPeer`:
- ✅ Bypasses `maxpeers` limit
- ✅ Ensures connection is maintained
- ✅ Prioritizes trusted nodes over random peers

### Verify Connections

```bash
# Check peer count
curl -s -X POST http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'

# List all peers with details
curl -s -X POST http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"admin_peers","params":[],"id":1}' \
  | jq '.result[] | {name, caps, addr: .network.remoteAddress}'
```

---

## SkyOne Dashboard

The xdc-node-setup automatically deploys the **SkyOne monitoring dashboard** for your Erigon node.

**Access:** `http://YOUR_SERVER_IP:7070`

**Features:**
- 📊 Real-time block height and sync status
- 👥 Live peer count
- 🔄 Sync progress percentage
- 🖥️ System resource usage (CPU, RAM, disk)
- ⚠️ Alert timeline

If you did a manual setup without xdc-node-setup, deploy SkyOne manually:

```bash
cd xdc-node-setup/dashboard

# Build
docker build -t xdc-skyone .

# Run (pointing to Erigon RPC on port 8547)
docker run -d \
  --name xdc-skyone \
  -p 7070:7070 \
  -e RPC_URL=http://host.docker.internal:8547 \
  --restart unless-stopped \
  xdc-skyone
```

> **Note:** On Linux, if `host.docker.internal` doesn't work, use `--network=host` or the Docker bridge IP `172.17.0.1`.

**See also:** [DASHBOARD.md](DASHBOARD.md) for advanced dashboard configuration.

---

## SkyNet Registration

Register your Erigon node on the **XDC SkyNet fleet dashboard** for centralized monitoring across all your nodes.

If you used `xdc start --client erigon`, registration is automatic. For manual setups:

```bash
# Register node
curl -X POST "https://net.xdc.network/api/v1/nodes/register" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_SKYNET_API_KEY" \
  -d '{
    "name": "my-erigon-node",
    "host": "http://YOUR_PUBLIC_IP:8547",
    "role": "fullnode",
    "tags": ["erigon", "multi-client"]
  }'
```

Save the returned `nodeId` and `apiKey`!

### Set Up Heartbeat

Create a heartbeat script that reports node status every minute:

```bash
cat > /root/erigon-heartbeat.sh << 'SCRIPT'
#!/bin/bash
NODE_ID="YOUR_NODE_ID"
API_KEY="YOUR_SKYNET_API_KEY"
RPC="http://127.0.0.1:8547"
API="https://net.xdc.network/api/v1"

# Get block height
BLOCK_HEX=$(curl -s -m 5 -X POST "$RPC" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result // "0x0"')
BLOCK=$((16#${BLOCK_HEX#0x}))

# Get peer count
PEERS_HEX=$(curl -s -m 5 -X POST "$RPC" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' | jq -r '.result // "0x0"')
PEERS=$((16#${PEERS_HEX#0x}))

# Send heartbeat
curl -s -m 10 -X POST "$API/nodes/heartbeat" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d "{\"nodeId\":\"$NODE_ID\",\"blockHeight\":$BLOCK,\"syncing\":true,\"peerCount\":$PEERS,\"clientType\":\"erigon\"}"
SCRIPT

chmod +x /root/erigon-heartbeat.sh
```

**Add to cron:**

```bash
(crontab -l 2>/dev/null; echo "* * * * * /root/erigon-heartbeat.sh >> /var/log/erigon-heartbeat.log 2>&1") | crontab -
```

---

## Manual Setup (Advanced Users)

If you prefer to build and run Erigon manually without Docker:

### Prerequisites

- Linux x86_64 (Ubuntu 22.04+ recommended)
- Go 1.22+ installed
- 500GB+ SSD storage
- 8GB+ RAM
- Ports: 30304 (P2P eth/63), 30311 (P2P eth/68), 8547 (HTTP RPC)

### Build Erigon-XDC

```bash
# Clone repository
git clone https://github.com/AnilChinchawale/erigon-xdc.git
cd erigon-xdc

# Build
make erigon

# Binary will be at: ./build/bin/erigon
```

### Create Start Script

```bash
cat > start-erigon.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

# XDC Mainnet bootnodes
BOOTNODES="enode://e1a69a7d766576e694adc3fc78d801a8a66926cbe8f4fe95b85f3b481444700a5d1b6d440b2715b5bb7cf4824df6a6702740afc8c52b20c72bc8c16f1ccde1f3@149.102.140.32:30303"
BOOTNODES="$BOOTNODES,enode://874589626a2b4fd7c57202533315885815eba51dbc434db88bbbebcec9b22cf2a01eafad2fd61651306fe85321669a30b3f41112eca230137ded24b86e064ba8@5.189.144.192:30303"
BOOTNODES="$BOOTNODES,enode://ccdef92053c8b9622180d02a63edffb3e143e7627737ea812b930eacea6c51f0c93a5da3397f59408c3d3d1a9a381f7e0b07440eae47314685b649a03408cfdd@37.60.243.5:30303"
BOOTNODES="$BOOTNODES,enode://12711126475d7924af98d359e178f71c5d9607de32d2c5b4ab1afff4b86e064ba8@89.117.49.48:30303"
BOOTNODES="$BOOTNODES,enode://81edfecc3df6994679daf67858ae34c0ae91aac944a84b09171532b45ad0f5d0c896eb8c023df04eaa2db743f5fccdf18cf7e2d12120d37a2c142a3be0a348cd@38.102.87.174:30303"
BOOTNODES="$BOOTNODES,enode://053ba696174e7f115e38f0e3963d0035ac20dc18e9a5c5873f9e90fe338d777f726d68d053c987416ec0bd97d4d818c59a8a23bc9ea854069ea2310846e27e7d@162.250.189.221:30303"

# Detect public IP
PUBLIC_IP="${PUBLIC_IP:-$(curl -s ifconfig.me)}"

exec ./build/bin/erigon \
  --chain=xdc \
  --datadir=./datadir \
  --http --http.addr=0.0.0.0 --http.port=8547 \
  --http.api=eth,net,web3,admin \
  --port=30311 \
  --private.api.addr=127.0.0.1:9092 \
  --bootnodes="$BOOTNODES" \
  --nat=extip:$PUBLIC_IP \
  --p2p.protocol=63,62 \
  --discovery.v4 \
  --discovery.xdc \
  --verbosity=3
EOF

chmod +x start-erigon.sh
```

### Start Erigon

```bash
# Using screen (survives SSH disconnects)
screen -dmS erigon ./start-erigon.sh

# Check logs
screen -r erigon    # Press Ctrl+A, then D to detach

# Or with nohup
nohup ./start-erigon.sh > erigon.log 2>&1 &
```

### Verify Sync

```bash
# Block height
curl -s -X POST http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Peer count
curl -s -X POST http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'

# Sync status
curl -s -X POST http://localhost:8547 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
```

---

## Known Issues

### Issue #15: P2P Protocol Mismatch (RESOLVED) ✅

**Status:** RESOLVED via dual-sentry architecture

Erigon uses two separate P2P sentries:
- **Port 30304 (eth/63)** — XDC-compatible, use this for XDC geth peers
- **Port 30311 (eth/68)** — Standard Ethereum protocol (not XDC-compatible)

See [Peer Connection](#peer-connection-critical) section above for details.

---

### Issue #44: Bad Block at 1,884,577

**Status:** Upstream issue — use `xdc-state-root-bypass` branch

Known XDPoS consensus validation issue at block 1,884,577 where state root validation fails.

**Solution:**
```bash
# Use the state root bypass branch
cd erigon-xdc
git checkout xdc-state-root-bypass
make erigon
```

**Alternative:** Reset and resync from snapshot:
```bash
xdc reset --client erigon --confirm
./scripts/snapshot-manager.sh download mainnet-erigon
```

---

### Issue #47: State Root Mismatches During Sync

**Status:** Expected behavior — bypassed in XDPoS chain implementation

Erigon and Geth calculate state differently in some XDPoS consensus edge cases. This results in state root mismatch warnings during sync.

**What happens:**
- State root mismatch is logged as a warning
- Sync continues to the next block (bypass enabled for XDPoS)
- State reconciles at next checkpoint

**Solution:**
Use the `xdc-state-root-bypass` branch which handles these mismatches automatically:
```bash
git clone https://github.com/AnilChinchawale/erigon-xdc.git
cd erigon-xdc
git checkout xdc-state-root-bypass
make erigon
```

**Note:** This is being tracked upstream. The mismatch is a known divergence between Erigon and Geth state calculation for XDPoS consensus.

---

### General Sync Issues

| Issue | Status | Workaround |
|-------|--------|------------|
| eth/68 vs eth/62 mismatch | ✅ RESOLVED | Use port 30304 (eth/63 sentry), not 30311 |
| "too many peers" rejections | Expected | Use `admin_addTrustedPeer` on geth side |
| Slow peer discovery | Known | Manually add peers via `admin_addPeer` RPC |
| State root mismatch | Bypassed | Use `xdc-state-root-bypass` branch |
| XDC bootnodes not responsive | XDC Network | Check [XDC Network status page](https://xdc.network/status) |

**Troubleshooting Resources:**
- Full troubleshooting guide: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Sync issues: [SYNC-GUIDE.md](SYNC-GUIDE.md)

**Reporting Issues:**
- Erigon-XDC: [github.com/AnilChinchawale/erigon-xdc/issues](https://github.com/AnilChinchawale/erigon-xdc/issues)
- Setup Script: [github.com/AnilChinchawale/xdc-node-setup/issues](https://github.com/AnilChinchawale/xdc-node-setup/issues)

---

## Port Reference

| Port | Protocol | Purpose | XDC Compatible | Firewall |
|------|----------|---------|----------------|----------|
| 8547 | HTTP | JSON-RPC API | N/A | Allow (if public RPC) |
| **30304** | TCP/UDP | **P2P eth/63** | ✅ **YES** | **Required** |
| 30311 | TCP/UDP | P2P eth/68 (standard Ethereum) | ❌ **NO** | Optional |
| 9092 | gRPC | Erigon internal API | N/A | Block (internal only) |
| 7070 | HTTP | SkyOne Dashboard | N/A | Allow (monitoring) |

> ⚠️ **WARNING**: Port 30304 (eth/63) is the ONLY port compatible with XDC geth nodes. Port 30311 (eth/68) uses a newer Ethereum protocol that XDC nodes do not support. Always use port 30304 for XDC peer connections.

**Open required ports:**

```bash
sudo ufw allow 30304/tcp
sudo ufw allow 30304/udp
sudo ufw allow 7070/tcp  # Dashboard
```

---

## Further Reading

- [Erigon Documentation](https://github.com/ledgerwatch/erigon#readme)
- [XDC Network Docs](https://docs.xdc.community/)
- [Multi-Client Diversity](https://ethereum.org/en/developers/docs/nodes-and-clients/client-diversity/)
- [Geth PR5 Client Guide](GETH-PR5.md)
- [Dashboard Setup](DASHBOARD.md)

---

**Questions?** Open an issue on [GitHub](https://github.com/AnilChinchawale/xdc-node-setup/issues) or ask in the [XDC Community Forum](https://www.xdc.dev/).
