# XDC Geth PR5 Client Guide

Run the XDC Network using the **Geth PR5** client — the latest go-ethereum with XDPoS consensus integration.

> **Status**: Geth PR5 is a development build testing the latest go-ethereum features with XDC's XDPoS consensus. It's suitable for testing, development, and adventurous node operators.

---

## Quick Start

The fastest way to run a Geth PR5 node is using the xdc-node-setup toolkit:

```bash
# Clone the repository
git clone https://github.com/AnilChinchawale/xdc-node-setup.git
cd xdc-node-setup

# Run setup with Geth PR5 client
bash setup.sh --client geth-pr5

# Or if already set up, start with Geth PR5
xdc start --client geth-pr5
```

The setup script will:
- ✅ Build Geth PR5 from source (takes ~10-15 minutes)
- ✅ Configure XDPoS consensus
- ✅ Set up RPC on port 8545 (same as stable)
- ✅ Deploy SkyOne dashboard for monitoring
- ✅ Register with SkyNet fleet dashboard

**Check status:**

```bash
xdc status        # Node sync progress
xdc peers         # Connected peers
xdc info          # Full node information
xdc client        # Check current client version
```

---

## What is Geth PR5?

**Geth PR5** is a fork of [go-ethereum](https://github.com/ethereum/go-ethereum) with XDC's **XDPoS (XinFin Delegated Proof of Stake)** consensus mechanism integrated.

### Key Information

- **Base:** Latest go-ethereum codebase
- **Consensus:** XDPoS (XinFin Delegated Proof of Stake)
- **Repository:** [github.com/AnilChinchawale/go-ethereum](https://github.com/AnilChinchawale/go-ethereum)
- **Branch:** `feature/xdpos-consensus`
- **PR:** #5 on the go-ethereum repository
- **Build Requirements:** Go 1.22+

### Why Geth PR5?

**Latest upstream geth features + XDC consensus:**
- ✅ **Modern EVM** — Latest Ethereum EVM opcodes and precompiles
- ✅ **Better performance** — Optimizations from upstream geth development
- ✅ **State schemes** — Support for both `hash` and `path` state storage
- ✅ **Snap sync** — Fast sync protocol (when XDC beacon chain available)
- ✅ **Modern metrics** — Improved Prometheus metrics and tracing
- ✅ **Code quality** — Benefits from Ethereum Foundation's ongoing development

**vs Stable XDC:**
- Stable XDC is based on an older geth fork
- Geth PR5 tracks latest upstream while maintaining XDPoS consensus
- Testing ground for future XDC mainnet upgrades

---

## Architecture

Geth PR5 uses the same architecture as stable XDC geth:

```
┌──────────────────────────────────────────────────────────┐
│                    Geth PR5 Node                         │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ┌─────────────────────────────────────────┐            │
│  │         XDPoS Consensus Engine          │            │
│  │  (Delegated Proof of Stake)             │            │
│  └───────────────┬─────────────────────────┘            │
│                  │                                       │
│  ┌───────────────▼─────────────────────────┐            │
│  │         Execution Layer (EVM)           │            │
│  │  • Transaction processing               │            │
│  │  • Smart contract execution             │            │
│  │  • State management                     │            │
│  └───────────────┬─────────────────────────┘            │
│                  │                                       │
│  ┌───────────────▼─────────────────────────┐            │
│  │         Storage Layer                   │            │
│  │  • LevelDB (state + chain data)         │            │
│  │  • Hash scheme (default)                │            │
│  │  • Path scheme (optional)               │            │
│  └───────────────┬─────────────────────────┘            │
│                  │                                       │
│  ┌───────────────▼─────────────────────────┐            │
│  │         P2P Network Layer               │            │
│  │  • eth/62, eth/63, eth/100              │            │
│  │  • Port: 30303                          │            │
│  │  • Discovery via DHT + bootnodes        │            │
│  └─────────────────────────────────────────┘            │
│                  │                                       │
│  ┌───────────────▼─────────────────────────┐            │
│  │         RPC API Server                  │            │
│  │  • HTTP: 8545                           │            │
│  │  • WS: 8546                             │            │
│  │  • APIs: eth, net, web3, admin, XDPoS   │            │
│  └─────────────────────────────────────────┘            │
│                                                          │
└──────────────────────────────────────────────────────────┘
                   │
                   │ P2P eth/62, eth/63, eth/100
                   │
        ┌──────────┴───────────┐
        │  XDC Network Peers   │
        │  (mainnet/testnet)   │
        └──────────────────────┘
```

### Component Details

**XDPoS Consensus:**
- Validator set managed via smart contracts
- Block time: ~2 seconds
- Epoch length: 900 blocks
- Rewards distributed automatically

**Execution Layer:**
- Latest Ethereum EVM with all London, Berlin, Shanghai opcodes
- Gas calculation improvements
- Enhanced precompile support

**Storage:**
- Default: Hash-based state scheme (compatible with stable)
- Optional: Path-based state scheme (experimental, more efficient)

**P2P Layer:**
- Fully compatible with existing XDC mainnet peers
- Same protocols as stable: `eth/62`, `eth/63`, `eth/100`
- Same port: **30303**

---

## Differences from Stable XDC

| Feature | Stable XDC | Geth PR5 | Notes |
|---------|------------|----------|-------|
| **Base Geth Version** | v1.10.x (older) | v1.13.x+ (latest) | PR5 tracks upstream |
| **EVM** | London-era | Shanghai+ | Newer opcodes & precompiles |
| **State Scheme** | Hash only | Hash or Path | Path scheme is experimental |
| **Snap Sync** | ❌ No | ✅ Yes (future) | Requires beacon chain support |
| **Metrics** | Basic | Enhanced | Better Prometheus integration |
| **Tracing** | Limited | Full support | Geth debug APIs improved |
| **Memory Usage** | Higher | Optimized | Upstream improvements |
| **Build Time** | ~5-10 min | ~10-15 min | More code to compile |
| **RPC Port** | 8545 | 8545 | Same |
| **P2P Port** | 30303 | 30303 | Same |
| **P2P Protocols** | eth/62,63,100 | eth/62,63,100 | Same |
| **Compatibility** | ✅ Production | ⚠️ Testing/Dev | PR5 is newer, less battle-tested |

### Performance Improvements

Geth PR5 benefits from upstream optimizations:
- 🚀 Faster block processing
- 💾 Lower memory footprint
- 🔄 Better cache management
- 📊 Enhanced metrics granularity

### Breaking Changes

⚠️ **State Scheme:** If you switch from hash → path scheme, you cannot downgrade without resyncing!

---

## Configuration

Geth PR5 uses the same `config.toml` format as stable XDC:

**Location:** `mainnet/.xdc-node/config.toml` (or `testnet/.xdc-node/config.toml`)

### Example config.toml

```toml
[Node]
DataDir = "/xdcchain"
HTTPPort = 8545
WSPort = 8546
Port = 30303

[Node.HTTP]
Enabled = true
Addr = "0.0.0.0"
Port = 8545
API = ["eth", "net", "web3", "admin", "XDPoS"]
CORSDomain = ["*"]
VHosts = ["*"]

[Node.WS]
Enabled = true
Addr = "0.0.0.0"
Port = 8546
API = ["eth", "net", "web3"]

[Eth]
NetworkId = 50                    # 50 = mainnet, 51 = testnet
SyncMode = "full"                 # full, fast, or snap
GCMode = "full"                   # full or archive
DatabaseCache = 4096              # MB, reduce if low on RAM
TrieCleanCache = 1024
TrieDirtyCache = 512
SnapshotCache = 512
StateScheme = "hash"              # hash (default) or path (experimental)

[Eth.TxPool]
Locals = []
NoLocals = false
Journal = "/xdcchain/transactions.rlp"
Rejournal = 3600000000000         # 1h in nanoseconds
PriceLimit = 1
PriceBump = 10
AccountSlots = 16
GlobalSlots = 5120
AccountQueue = 64
GlobalQueue = 1024

[Eth.GPO]
Blocks = 20
Percentile = 60
MaxPrice = 500000000000           # 500 gwei

[Node.P2P]
MaxPeers = 50
NoDiscovery = false
StaticNodes = []
TrustedNodes = []
ListenAddr = ":30303"
EnableMsgEvents = false

[Metrics]
Enabled = true
HTTP = "0.0.0.0"
Port = 6060
```

### State Scheme Options

**Hash Scheme (Default):**
```toml
[Eth]
StateScheme = "hash"
```
- ✅ Compatible with stable XDC
- ✅ Battle-tested
- ❌ Higher disk usage

**Path Scheme (Experimental):**
```toml
[Eth]
StateScheme = "path"
```
- ✅ Lower disk usage (~30% reduction)
- ✅ Faster state access
- ⚠️ Experimental, cannot downgrade without resync
- ⚠️ Not compatible with stable XDC snapshots

### Sync Modes

```toml
[Eth]
SyncMode = "full"  # Options: full, fast, snap
```

| Mode | Speed | Disk Usage | Validation | Availability |
|------|-------|------------|------------|--------------|
| **full** | Slowest | Lowest | Full | ✅ Available |
| **fast** | Medium | Medium | Headers + recent state | ✅ Available |
| **snap** | Fastest | Lowest | Snapshot-based | ⏳ Future (needs beacon) |

**Recommendation:** Use `full` for production, `fast` for development.

---

## SkyOne Dashboard

The xdc-node-setup automatically deploys the **SkyOne monitoring dashboard** for your Geth PR5 node.

**Access:** `http://YOUR_SERVER_IP:7070`

**Features:**
- 📊 Real-time block height and sync status
- 👥 Live peer count and network graph
- 🔄 Sync progress percentage
- 🖥️ System resource usage (CPU, RAM, disk)
- ⚠️ Alert timeline
- 🏷️ Client type badge (shows "Geth PR5")

**Dashboard automatically detects:**
- Client version from RPC
- Network (mainnet/testnet)
- Sync mode

**See also:** [DASHBOARD.md](DASHBOARD.md) for advanced dashboard configuration.

---

## SkyNet Registration

Register your Geth PR5 node on the **XDC SkyNet fleet dashboard** for centralized monitoring across all your nodes.

If you used `xdc start --client geth-pr5`, registration is automatic. The node will be tagged with `client:geth-pr5`.

**Manual registration:**

```bash
curl -X POST "https://skynet.xdcindia.com/api/v1/nodes/register" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_SKYNET_API_KEY" \
  -d '{
    "name": "my-geth-pr5-node",
    "host": "http://YOUR_PUBLIC_IP:8545",
    "role": "fullnode",
    "tags": ["geth-pr5", "latest", "testing"]
  }'
```

The SkyNet dashboard will display your node with a `Geth PR5` badge and track it separately from stable nodes for comparison.

---

## Manual Setup (Build from Source)

If you prefer to build and run Geth PR5 manually without Docker:

### Prerequisites

- Linux x86_64 (Ubuntu 22.04+ recommended)
- **Go 1.22+** installed ([installation guide](https://go.dev/doc/install))
- 500GB+ SSD storage
- 8GB+ RAM
- Ports: 30303 (P2P), 8545 (HTTP RPC), 8546 (WebSocket)

### Install Go 1.22+

```bash
# Download and install Go 1.22
wget https://go.dev/dl/go1.22.0.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.22.0.linux-amd64.tar.gz

# Add to PATH
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

# Verify
go version  # Should show go1.22.0 or later
```

### Build Geth PR5

```bash
# Clone the feature branch
git clone -b feature/xdpos-consensus https://github.com/AnilChinchawale/go-ethereum.git
cd go-ethereum

# Build geth
make geth

# Binary will be at: ./build/bin/geth
# Optionally install system-wide:
sudo cp ./build/bin/geth /usr/local/bin/geth-pr5
```

**Build time:** ~10-15 minutes depending on CPU

### Create Data Directory

```bash
mkdir -p ~/xdc-geth-pr5
cd ~/xdc-geth-pr5
```

### Download Genesis and Config

```bash
# Genesis file (mainnet)
wget https://raw.githubusercontent.com/XinFinOrg/XinFin-Node/master/genesis/mainnet.json -O genesis.json

# Initialize
geth-pr5 --datadir ./data init genesis.json
```

### Create Start Script

```bash
cat > start.sh << 'EOF'
#!/bin/bash
set -e

DATADIR="./data"
BOOTNODES="enode://e1a69a7d766576e694adc3fc78d801a8a66926cbe8f4fe95b85f3b481444700a5d1b6d440b2715b5bb7cf4824df6a6702740afc8c52b20c72bc8c16f1ccde1f3@149.102.140.32:30303,enode://874589626a2b4fd7c57202533315885815eba51dbc434db88bbbebcec9b22cf2a01eafad2fd61651306fe85321669a30b3f41112eca230137ded24b86e064ba8@5.189.144.192:30303"

geth-pr5 \
  --datadir "$DATADIR" \
  --networkid 50 \
  --syncmode full \
  --gcmode full \
  --http \
  --http.addr 0.0.0.0 \
  --http.port 8545 \
  --http.api eth,net,web3,admin,XDPoS \
  --http.corsdomain "*" \
  --http.vhosts "*" \
  --ws \
  --ws.addr 0.0.0.0 \
  --ws.port 8546 \
  --ws.api eth,net,web3 \
  --port 30303 \
  --bootnodes "$BOOTNODES" \
  --nat extip:$(curl -s ifconfig.me) \
  --maxpeers 50 \
  --cache 4096 \
  --verbosity 3
EOF

chmod +x start.sh
```

### Start Node

```bash
# Using screen
screen -dmS geth-pr5 ./start.sh

# View logs
screen -r geth-pr5  # Press Ctrl+A, then D to detach

# Or with nohup
nohup ./start.sh > geth.log 2>&1 &
tail -f geth.log
```

### Verify Sync

```bash
# Block number
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Peer count
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'

# Sync status
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

# Client version
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}'
```

---

## Known Issues

| Issue | Status | Workaround |
|-------|--------|------------|
| Path state scheme migration | No downgrade | Use hash scheme for production |
| Snap sync without beacon | Not available | Use full or fast sync modes |
| Higher build time | Expected | Pre-built Docker images available via xdc-node-setup |
| Mainnet compatibility | Testing | Report any consensus issues on GitHub |

**Reporting Issues:**
- Geth PR5 code: [github.com/AnilChinchawale/go-ethereum/issues](https://github.com/AnilChinchawale/go-ethereum/issues)
- Setup script: [github.com/AnilChinchawale/xdc-node-setup/issues](https://github.com/AnilChinchawale/xdc-node-setup/issues)

---

## Client Comparison

| Feature | Stable XDC | Geth PR5 | Erigon-XDC |
|---------|------------|----------|------------|
| **Maturity** | ✅ Production | ⚠️ Testing | ⚠️ Experimental |
| **Base** | Geth v1.10.x | Geth v1.13+ | Erigon v2.x |
| **EVM** | London | Shanghai+ | Shanghai+ |
| **Build Time** | ❌ None (Docker) | ~10-15 min | ~10-15 min |
| **P2P Port** | 30303 | 30303 | 30304 (eth/63) + 30311 (eth/68) |
| **RPC Port** | 8545 | 8545 | 8547 |
| **P2P Protocols** | eth/62,63,100 | eth/62,63,100 | eth/62,63 |
| **Sync Modes** | full, fast | full, fast, snap* | full |
| **State Schemes** | hash | hash, path | hash |
| **Memory** | Medium | Low-Medium | Low |
| **Disk Usage** | Medium | Medium (hash) / Low (path) | Low |
| **Metrics** | Basic | Enhanced | Advanced |
| **Best For** | Production nodes | Testing latest features | Multi-client diversity |

_*snap sync requires beacon chain support (future)_

### When to Use Each Client

**Use Stable XDC when:**
- ✅ Running production validator or masternodes
- ✅ Maximum stability is required
- ✅ No time for source builds

**Use Geth PR5 when:**
- ✅ Testing latest geth features before mainnet
- ✅ Contributing to XDC protocol development
- ✅ Running development/testnet nodes
- ✅ Want upstream geth improvements

**Use Erigon-XDC when:**
- ✅ Contributing to multi-client diversity
- ✅ Low disk space requirements
- ✅ Running archive nodes efficiently
- ✅ Experimental mindset

---

## Migrating from Stable to Geth PR5

**Option 1: Fresh Sync (Recommended)**

```bash
# Stop stable node
xdc stop

# Backup data (optional)
xdc backup create

# Start with Geth PR5 (fresh sync)
xdc start --client geth-pr5
```

**Option 2: Reuse Data (Risky)**

Only if both use `hash` state scheme:

```bash
# Stop stable
xdc stop

# Copy data
cp -r mainnet/xdcchain mainnet/xdcchain.backup

# Start Geth PR5
xdc start --client geth-pr5

# Monitor for issues
xdc logs --follow

# If problems occur, rollback:
# xdc stop
# rm -rf mainnet/xdcchain
# mv mainnet/xdcchain.backup mainnet/xdcchain
# xdc start --client stable
```

⚠️ **Warning:** Cross-client data migration is not officially supported. Fresh sync is safer.

---

## Further Reading

- [Go-Ethereum Documentation](https://geth.ethereum.org/docs)
- [XDPoS Consensus Overview](https://docs.xdc.community/learn/xdpos-consensus/)
- [State Schemes Explained](https://blog.ethereum.org/2023/09/12/geth-v1-13-0)
- [Erigon-XDC Client Guide](ERIGON.md)
- [Dashboard Setup](DASHBOARD.md)

---

**Questions?** Open an issue on [GitHub](https://github.com/AnilChinchawale/xdc-node-setup/issues) or ask in the [XDC Community Forum](https://www.xdc.dev/).
