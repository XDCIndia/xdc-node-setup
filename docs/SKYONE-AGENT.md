# SkyOne XDC Agent — Complete Feature Reference

> **Version:** 2.0 (Phase 2 AI Intelligence)
> **Last Updated:** 2026-04-03
> **Source Files:** `docker/skynet-agent.sh`, `scripts/skynet-agent.sh`, `docker/skynet-agent/combined-start.sh`

---

## Table of Contents

1. [Overview](#overview)
2. [Agent Variants](#agent-variants)
3. [Configuration](#configuration)
4. [Auto-Registration](#auto-registration)
5. [Heartbeat Mechanism](#heartbeat-mechanism)
6. [Metrics Collection](#metrics-collection)
7. [Client Type Auto-Detection](#client-type-auto-detection)
8. [Genesis Hash Verification](#genesis-hash-verification)
9. [Network Height Calculation](#network-height-calculation)
10. [Peer Management](#peer-management)
11. [Watchdog & Self-Healing](#watchdog--self-healing)
12. [Phase 2 AI Intelligence](#phase-2-ai-intelligence)
13. [Security Scanning](#security-scanning)
14. [Storage Detection](#storage-detection)
15. [Remote Commands](#remote-commands)
16. [Deployment](#deployment)
17. [Environment Variables](#environment-variables)
18. [Heartbeat Payload Schema](#heartbeat-payload-schema)
19. [Troubleshooting](#troubleshooting)

---

## Overview

The SkyOne XDC Agent is a sidecar monitoring agent that runs alongside XDC Network nodes. It collects metrics, sends heartbeats to the SkyNet platform, auto-heals stalled/crashed nodes, and provides fleet-wide observability.

There are **three main agent implementations** that share the same architecture but target different deployment scenarios:

| File | Purpose | Runtime |
|------|---------|---------|
| `docker/skynet-agent.sh` | Docker/native daemon (v1) | Bash + systemd |
| `scripts/skynet-agent.sh` | Enhanced watchdog variant (v1.5) | Bash + systemd |
| `docker/skynet-agent/combined-start.sh` | Phase 2 unified container agent | Docker sidecar (background loop) |

---

## Agent Variants

### v1: `docker/skynet-agent.sh`
- Original implementation
- Supports `--daemon`, `--register`, `--install`, `--status`, `--add-peers`
- Installs as systemd service (`xdc-skynet-agent.service`)
- Config: `/etc/xdc-node/skynet.conf`
- State: `${XDC_STATE_DIR}/skynet.json`
- Features: heartbeat, registration, security scanning, peer injection, remote commands, genesis verification, state scheme detection

### v1.5: `scripts/skynet-agent.sh`
- Enhanced version with built-in watchdog
- Everything in v1 plus:
  - Auto-restart unhealthy nodes (container stopped, RPC down, sync stalled)
  - Max 3 restarts/hour with 5-minute cooldown
  - Stall duration tracking (hours stuck on same block)
  - Watchdog state persistence (`/tmp/xdc-watchdog-state.json`)
  - Watchdog log (`/var/log/xdc-watchdog.log`)
  - `--watchdog` mode for standalone health checks

### v2: `docker/skynet-agent/combined-start.sh` (Phase 2)
- Production container agent deployed as Docker sidecar
- Everything in v1.5 plus:
  - **Self-resolving RPC** — auto-detects container IP via Docker socket
  - **Fingerprint-based identity** (Issue #71) — `coinbase@IP:clientType:network`
  - **Smart node naming** — `{client}-v{version}-{type}-{ip}-{network}`
  - **Cross-node correlation engine** — detects widespread vs isolated issues
  - **Intelligent peer management** — cooldown-aware injection every 5 min
  - **Block progress tracking** — rolling 30-sample window (15 min)
  - **Sync trend analysis** — accelerating/stable/decelerating/stalled
  - **Network height awareness** — fetches from OpenScan RPCs
  - **ETA estimation** — calculates sync completion time
  - **Smart restart logic** — effectiveness tracking, 3/6h limit
  - **10-pattern error classification** from container logs
  - **Self-diagnostic reports** — hourly summary to SkyNet
  - **Config refresh from SkyNet** — every ~25 min
  - **Issue reporting with cooldown** — prevents duplicate alerts

---

## Configuration

### Config File: `skynet.conf`

```bash
# Required
SKYNET_API_URL=https://skynet.xdcindia.com/api/v1
SKYNET_API_KEY=                    # Auto-populated on registration
SKYNET_NODE_ID=                    # Auto-populated on first boot

# Identity
SKYNET_NODE_NAME=                  # Display name (auto-generated if empty)
SKYNET_ROLE=fullnode               # fullnode | masternode | archive | monitor

# Notifications (optional)
SKYNET_EMAIL=
SKYNET_TELEGRAM=

# Advanced
HEARTBEAT_INTERVAL=30              # Seconds between heartbeats (default: 30)
XDC_RPC_URL=http://127.0.0.1:8545
```

### Config Locations

| Network | Path |
|---------|------|
| Mainnet (geth) | `mainnet/.xdc-node/skynet.conf` |
| Mainnet (erigon) | `mainnet/.xdc-node/skynet-erigon.conf` |
| Mainnet (nethermind) | `mainnet/.xdc-node/skynet-nethermind.conf` |
| Mainnet (reth) | `mainnet/.xdc-node/skynet-reth.conf` |
| Apothem | `testnet/.xdc-node/skynet.conf` |
| Devnet | `devnet/.xdc-node/skynet.conf` |
| Template | `skynet-template.conf` |

### Config Validation

Run `scripts/validate-skyone-env.sh` before starting the agent:
```bash
source scripts/validate-skyone-env.sh
validate_skyone_env
```

Checks:
- `XDC_RPC_URL` set and reachable
- `SKYNET_API_URL` set and reachable
- `SKYNET_API_KEY` present (warns if missing)
- `SKYNET_NODE_ID` present (auto-registers if missing)
- Auto-generates `NODE_NAME` if not provided

---

## Auto-Registration

### Fingerprint-Based Identity (Phase 2, Issue #71)

The v2 agent uses a fingerprint to identify nodes:

```
fingerprint = {coinbase}@{public_ip}:{client_type}:{network}
```

**Endpoint:** `POST /api/v1/nodes/identify`

**Payload:**
```json
{
  "fingerprint": "0xabc123@1.2.3.4:geth:mainnet",
  "ip": "1.2.3.4",
  "clientType": "geth",
  "clientVersion": "XDC/v1.17.0",
  "name": "geth-v1.17.0-fullnode-1.2.3.4-mainnet",
  "network": "mainnet",
  "role": "fullnode",
  "coinbase": "0xabc123"
}
```

**Response** (new or recovered):
```json
{
  "success": true,
  "data": {
    "nodeId": "uuid-here",
    "apiKey": "key-here",
    "isNew": true
  }
}
```

### Legacy Registration (v1 fallback)

**Endpoint:** `POST /api/v1/nodes/register`

**Payload includes:** name, host, role, rpcUrl, location (city, country, lat, lng), tags, version, clientType, nodeType, ipv4, ipv6, OS info, coinbase.

### Smart Node Naming

Auto-generated format: `{client}-v{version}-{type}-{ip}-{network}`

Examples:
- `geth-v1.17.0-fullnode-185.180.220.183-mainnet`
- `erigon-v2.60.0-fullnode-185.180.220.183-apothem`
- `nethermind-v1.25.0-fullnode-10.0.0.5-mainnet`

---

## Heartbeat Mechanism

### Interval
- Default: **30 seconds** (configurable via `HEARTBEAT_INTERVAL` env or SkyNet API)
- Config refresh from SkyNet: every ~25 minutes

### Endpoints
- v1: `POST /api/nodes/heartbeat` or `POST /api/v1/nodes/heartbeat`
- v2: `POST /api/v1/nodes/{nodeId}/heartbeat`

### Auto-Registration on Heartbeat
If `NODE_ID` is empty when a heartbeat fires, the agent auto-registers first, then sends the heartbeat.

### Heartbeat Status File
Written to `/tmp/skynet-heartbeat.json` for dashboard consumption:
```json
{
  "lastHeartbeat": "2026-04-03T05:30:00Z",
  "status": "success",
  "skynetUrl": "https://skynet.xdcindia.com/api/v1",
  "nodeId": "uuid",
  "nodeName": "xdc-mainnet-geth",
  "error": ""
}
```

---

## Metrics Collection

Every heartbeat collects and reports:

### Blockchain Metrics
| Metric | RPC Method | Description |
|--------|-----------|-------------|
| `blockHeight` | `eth_blockNumber` | Current block number (decimal) |
| `syncing` | `eth_syncing` | Boolean sync status |
| `syncProgress` | `eth_syncing` | Percentage if syncing |
| `peerCount` | `admin_peers` | Number of connected peers |
| `peers[]` | `admin_peers` | Full peer list (enode, name, remoteAddress, direction) |
| `txPool.pending` | `txpool_status` | Pending transaction count |
| `txPool.queued` | `txpool_status` | Queued transaction count |
| `gasPrice` | `eth_gasPrice` | Current gas price (hex) |
| `coinbase` | `eth_coinbase` | Coinbase address |
| `clientVersion` | `admin_nodeInfo` | Full client version string |
| `enode` | `admin_nodeInfo` | Public enode URL (IP-replaced) |

### System Metrics
| Metric | Source | Description |
|--------|--------|-------------|
| `cpuPercent` | `/proc/stat` | CPU usage percentage |
| `memoryPercent` | `free` | Memory usage percentage |
| `diskPercent` | `df` | Root disk usage percentage |
| `diskUsedGb` | `df -BG` | Used disk in GB |
| `diskTotalGb` | `df -BG` | Total disk in GB |
| `rpcLatencyMs` | Timed `eth_blockNumber` | RPC round-trip latency |

### OS Metrics
| Metric | Source |
|--------|--------|
| `os.type` | `uname -s` |
| `os.release` | `/etc/os-release PRETTY_NAME` |
| `os.arch` | `uname -m` |
| `os.kernel` | `uname -r` |
| `ipv4` | `ifconfig.me` / `api.ipify.org` |
| `ipv6` | `ifconfig6.me` / `api6.ipify.org` |

### Phase 2 Metrics (v2 only)
| Metric | Description |
|--------|-------------|
| `syncRate` | Blocks per minute (rolling 15-min window) |
| `syncTrend` | accelerating / stable / decelerating / stalled / initializing |
| `networkHeight` | Latest block from OpenScan public RPC |
| `syncPercent` | Local block / network height × 100 |
| `etaHours` | Estimated hours to sync completion |
| `stalled` | Boolean: is node sync-stalled? |
| `storageType` | NVMe / SSD / HDD (from `/sys/block`) |
| `dockerImage` | Docker image name of the XDC node container |
| `fingerprint` | `coinbase@ip` identity hash |

---

## Client Type Auto-Detection

Detected from `web3_clientVersion` or `admin_nodeInfo.name` string:

| Pattern Match | Client Type |
|--------------|-------------|
| `XDC` / `XDPoS` | `XDC` (geth stable) |
| `Geth` / `go-ethereum` | `geth` |
| `Erigon` | `erigon` |
| `Nethermind` | `nethermind` |
| `reth` | `reth` |

### Version-Aware Detection (v2)
```
XDC v2.6.8+ → "xdc" (stable)
XDC v1.x / Geth → "geth" (PR5/fork)
```

---

## Genesis Hash Verification

Verifies network identity by comparing genesis block hash:

| Network | Genesis Hash |
|---------|-------------|
| Mainnet | `0x4a9d748bd78a8d0385b67788c2435dcdb914f98a96250b68863a1f8b7642d6b1` |
| Apothem | `0xbdea512b4f12ff1135ec92c00dc047ffb93890c2ea1aa0eefe9b013d80640075` |

### Mismatch Detection
If `NETWORK` env var doesn't match the genesis hash network, the agent:
1. Logs a `⚠️ GENESIS MISMATCH` warning
2. Sets `genesis.mismatch: true` in heartbeat
3. Reports the configured vs actual network

---

## Network Height Calculation

### Source
- Mainnet (chain ID 50): `https://rpc.openscan.ai/50`
- Apothem (chain ID 51): `https://rpc.openscan.ai/51`

### Caching
- Updated every 20 heartbeats (≈10 minutes)
- Cached in `/tmp/network-height.json`
- Falls back to cached value on fetch failure

### Derived Metrics
- **Sync Percent** = `localBlock / networkHeight × 100`
- **ETA Hours** = `(networkHeight - localBlock) / (syncRate × 60)`

---

## Peer Management

### Auto-Injection on Zero Peers
Both v1 and v2 agents detect zero peers and auto-inject from SkyNet:

```
GET /api/v1/peers/healthy?network={network}&limit=20
```

Peers are added via `admin_addPeer` RPC. Supported clients:
- ✅ Geth/XDC — `admin_addPeer`
- ✅ Nethermind — `admin_addPeer`
- ⚠️ Erigon — logged but not injectable (no `admin_addPeer` support)

### Phase 2 Intelligent Peer Management
- Runs every 10 heartbeats (≈5 minutes)
- Only injects if peer count < 2
- **Cooldown**: 5-minute minimum between injections
- Tracks injection history in `/tmp/peer-injection-history`
- Limits to 3 peers per injection cycle

### Peer Drop Detection (v2)
- Tracks consecutive zero-peer heartbeats
- Reports `peer_drop` issue to SkyNet after 10 minutes of zero peers
- 60-minute cooldown between reports

---

## Watchdog & Self-Healing

### v1.5 Watchdog (`scripts/skynet-agent.sh`)
| Check | Trigger | Action |
|-------|---------|--------|
| Container status | Not running | Docker restart |
| RPC responding | No response | Docker restart |
| Sync progress | Same block for 10 min | Docker restart |
| Peer count | Zero peers | Peer injection |
| Stall pre-heal | 2-5 min stall | Peer injection first |

**Limits:**
- Max 3 restarts per hour
- 5-minute cooldown between restarts
- Alerts SkyNet when restart limit reached

### v2 Smart Restart Logic
| Feature | Description |
|---------|-------------|
| Rate limiting | Max 3 restarts per 6 hours |
| Effectiveness tracking | Checks if previous restart helped (block progressed) |
| Escalation | If restart ineffective or limit reached → escalate to SkyNet |
| Restart history | Persisted in `/tmp/restart-history.json` (last 20 entries) |

### v2 Error Classification (10 Patterns)
| Pattern ID | Regex | Severity | Action |
|-----------|-------|----------|--------|
| `missing_trie_node` | `missing trie node` | critical | rollback 1000 blocks |
| `breach_of_protocol` | `BreachOfProtocol` | warning | none (monitor) |
| `bad_block` | `BAD BLOCK` | critical | rollback 100 blocks |
| `uint256_overflow` | `uint256 overflow\|panic.*overflow` | critical | restart |
| `state_root_mismatch` | `state root mismatch\|invalid merkle root` | critical | rollback 500 blocks |
| `protocol_mismatch` | `unsupported eth protocol\|rlp: expected input` | warning | peer refresh |
| `disk_corruption` | `corrupted\|checksum mismatch` | critical | escalate |
| `memory_oom` | `out of memory\|cannot allocate` | critical | restart |
| `genesis_mismatch` | `genesis block mismatch` | critical | escalate |
| `fork_choice` | `forked block\|side chain` | warning | none (monitor) |

### Cross-Node Correlation (v2)
Before restarting, v2 queries fleet overview:
- If >70% of fleet nodes stalled at the same block → **widespread** (likely code bug) → escalate, don't restart
- Otherwise → **isolated** → proceed with restart

---

## Phase 2 AI Intelligence

### Periodic Task Schedule (v2 at 30s heartbeat)

| Task | Frequency | Counter | Description |
|------|-----------|---------|-------------|
| Heartbeat + metrics | Every HB | — | Core monitoring loop |
| Error detection & heal | Every HB | — | Log pattern matching |
| Peer management | 10 HB (5 min) | `PEER_MGMT_COUNTER` | Inject if <2 peers |
| Network height | 20 HB (10 min) | `NETWORK_HEIGHT_COUNTER` | Fetch from OpenScan |
| Config refresh | 50 HB (25 min) | `CONFIG_REFRESH_COUNTER` | `GET /v1/nodes/{id}/config` |
| Self-diagnostic | 120 HB (1 hour) | `DIAGNOSTIC_COUNTER` | Summary to `/v1/nodes/{id}/diagnostic` |
| RPC re-resolution | 10 HB or 3 fails | `RPC_RESOLVE_COUNTER` | Detect container IP changes |

### Self-Diagnostic Report
Sent hourly to SkyNet with:
- Agent uptime
- Restarts in window
- Average sync rate
- Peer history (last 10 entries)
- Restart effectiveness percentage
- Recommendation text

### Issue Reporting
Reports issues to `POST /v1/issues/report` with per-type cooldowns:
- `sync_stall` — 60-minute cooldown
- `peer_drop` — 60-minute cooldown
- `disk_critical` — 60-minute cooldown

---

## Security Scanning

Both v1 and v2 compute a security score (0-100):

| Check | Penalty | Description |
|-------|---------|-------------|
| SSH on port 22 | -10 | Default SSH port |
| Root login enabled | -10 | `PermitRootLogin` not `no` |
| No firewall (UFW) | -15 | UFW not active |
| No fail2ban | -10 | fail2ban not running |
| No auto-updates | -5 | unattended-upgrades not installed |
| RPC exposed 0.0.0.0 | -15 | Ports 8545/8989/30303 on all interfaces |
| Docker as root | -5 | Docker running with root |

v2 adds:
| Check | Penalty |
|-------|---------|
| Running as root user | -10 |
| SSH password auth enabled | -15 |
| No firewall/iptables | -10 |

---

## Storage Detection

### Storage Type
Detected from `/sys/block/{device}/queue/rotational`:
- `0` → **SSD**
- `1` → **HDD**
- Device name contains `nvme` → **NVMe**

### State Scheme Detection (v1)
Detects PBSS vs HBSS from Docker container args:
- `--state.scheme path` → `path` (PBSS)
- `--state.scheme hash` → `hash` (HBSS)
- Also checks container logs for `scheme=path|hash`

---

## Remote Commands

The heartbeat response can include commands:

| Command | Action |
|---------|--------|
| `restart` | Docker restart of XDC container or `systemctl restart xdc-node` |
| `update` | Runs `version-check.sh --auto-update` |
| `add_peers` | Triggers peer injection from SkyNet |

---

## Deployment

### Systemd Service (v1/v1.5)
```bash
./scripts/skynet-agent.sh --install
# Creates /etc/systemd/system/xdc-skynet-agent.service
# Enables and starts the daemon
```

### Docker Sidecar (v2)
```bash
docker run -d --name skyone-mainnet-geth \
  --restart unless-stopped \
  -v /path/to/skynet.conf:/etc/xdc-node/skynet.conf:ro \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e RPC_URL=http://172.17.0.2:8545 \
  -e CLIENT_TYPE=geth \
  -e XDC_CONTAINER_NAME=xdc-node \
  anilchinchawale/xdc-skyone:latest
```

### Docker Compose Profiles
```bash
# External monitoring (no XDC node)
docker compose -f docker/docker-compose.skyone.yml --profile external up -d

# Full stack (node + dashboard + agent)
docker compose -f docker/docker-compose.skyone.yml --profile full up -d

# Validator
docker compose -f docker/docker-compose.skyone.yml --profile validator up -d

# With Prometheus + Grafana
docker compose -f docker/docker-compose.skyone.v2.yml --profile monitoring up -d
```

### Multi-Client Fleet Deployment
```bash
# Mainnet agents (gp5, erigon, nm, reth)
bash docker/skynet-agent/deploy-mainnet-agents.sh

# Apothem agents
bash docker/skynet-agent/deploy-apo-agents.sh

# Refresh IPs after container restarts (runs via cron every 5 min)
bash docker/skynet-agent/update-agent-ips.sh
```

### macOS
```bash
bash scripts/macos-heartbeat.sh
# Installs as launchd agent: com.xdc.skynet.heartbeat
# Interval: 60 seconds
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SKYNET_API_URL` | `https://skynet.xdcindia.com/api` | SkyNet API base URL |
| `SKYNET_API_KEY` | (empty) | Auth key (auto-populated) |
| `SKYNET_NODE_ID` | (empty) | Node UUID (auto-populated) |
| `SKYNET_NODE_NAME` | hostname | Display name |
| `SKYNET_ROLE` | `fullnode` | Node role |
| `RPC_URL` / `XDC_RPC_URL` | `http://127.0.0.1:8545` | XDC node RPC endpoint |
| `XDC_CONTAINER_NAME` | `xdc-node` | Docker container to monitor |
| `XDC_RPC_PORT` | (from RPC_URL) | Override internal RPC port |
| `HEARTBEAT_INTERVAL` | `30` | Seconds between heartbeats |
| `NETWORK` | `mainnet` | Network name |
| `CLIENT_TYPE` | (auto-detected) | Client type override |
| `NODE_NAME` | hostname | Legacy name variable |
| `NODE_ROLE` | `fullnode` | Legacy role variable |
| `SKYNET_MASTER_KEY` | `xdc-netown-key-2026-prod` | Master key for auto-registration |
| `DOCKER_IMAGE` | (auto-detected) | Docker image override |

---

## Heartbeat Payload Schema

### v2 Full Payload

```json
{
  "blockHeight": 87654321,
  "peerCount": 12,
  "isSyncing": false,
  "clientType": "geth",
  "version": "XDC/v1.17.0-stable/linux-amd64/go1.21.0",
  "network": "mainnet",
  "chainId": 50,
  "coinbase": "0x...",
  "fingerprint": "0x...@1.2.3.4",
  "stalled": false,
  "lastRestart": "",
  "syncRate": 120.5,
  "syncTrend": "stable",
  "networkHeight": 87654500,
  "syncPercent": 99.99,
  "etaHours": "0.1",
  "os": {
    "type": "Linux",
    "release": "Ubuntu 22.04.3 LTS",
    "arch": "x86_64",
    "kernel": "5.15.0-91-generic",
    "ipv4": "1.2.3.4"
  },
  "system": {
    "cpuPercent": 15.2,
    "memoryPercent": 62.3,
    "diskPercent": 45,
    "diskUsedGb": 180,
    "diskTotalGb": 400
  },
  "security": {
    "score": 85,
    "issues": ["SSH password authentication enabled"]
  },
  "storageType": "NVMe",
  "dockerImage": "anilchinchawale/xdc-node:latest"
}
```

### v1 Additional Fields
```json
{
  "nodeId": "uuid",
  "peers": [{"enode":"...", "name":"...", "remoteAddress":"...", "direction":"inbound"}],
  "txPool": {"pending": 5, "queued": 0},
  "gasPrice": "0x3b9aca00",
  "rpcLatencyMs": 12,
  "enode": "enode://pubkey@1.2.3.4:30303",
  "stateScheme": "hash",
  "startupParams": "--syncmode snap --cache 4096",
  "genesis": {
    "hash": "0x4a9d748b...",
    "network": "mainnet",
    "mismatch": false
  },
  "stallHours": 0,
  "stalledAtBlock": 0
}
```

---

## Troubleshooting

### Agent not sending heartbeats
1. Check config: `cat /etc/xdc-node/skynet.conf`
2. Validate env: `bash scripts/validate-skyone-env.sh`
3. Test RPC: `curl -s -X POST http://127.0.0.1:8545 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'`
4. Check heartbeat status: `cat /tmp/skynet-heartbeat.json`

### Agent can't reach RPC (Docker bridge)
- Use container IP, not `localhost` or `host.docker.internal`
- The v2 agent auto-resolves via Docker socket mount
- Ensure `/var/run/docker.sock` is mounted

### Repeated restarts
- Check watchdog log: `tail -f /var/log/xdc-watchdog.log`
- Check restart history: `cat /tmp/restart-history.json`
- v2 caps at 3 restarts per 6 hours

### Node not registering
- Ensure `SKYNET_API_URL` is reachable
- Check if `SKYNET_NODE_ID` already populated in config
- Delete `/tmp/skynet-node-id` to force re-registration
