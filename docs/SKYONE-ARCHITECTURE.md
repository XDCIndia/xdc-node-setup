# SkyOne Agent — Architecture & Data Flow

> **Version:** 2.0 (Phase 2 AI Intelligence)
> **Last Updated:** 2026-04-03

---

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          OPERATOR'S SERVER                                  │
│                                                                             │
│  ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐        │
│  │  XDC Node (Geth) │   │ XDC Node (Erigon)│   │ XDC Node (NM)   │        │
│  │  :8545 RPC       │   │  :8546 RPC       │   │  :8547 RPC      │        │
│  │  :30303 P2P      │   │  :30303 P2P      │   │  :30303 P2P     │        │
│  └────────┬─────────┘   └────────┬─────────┘   └────────┬────────┘        │
│           │                      │                       │                  │
│           │  JSON-RPC            │  JSON-RPC             │  JSON-RPC       │
│           ▼                      ▼                       ▼                  │
│  ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐        │
│  │  SkyOne Agent    │   │  SkyOne Agent    │   │  SkyOne Agent    │        │
│  │  (sidecar)       │   │  (sidecar)       │   │  (sidecar)       │        │
│  │  :7070 dashboard │   │  :7071 dashboard │   │  :7072 dashboard │        │
│  └────────┬─────────┘   └────────┬─────────┘   └────────┬────────┘        │
│           │                      │                       │                  │
│           └──────────────────────┼───────────────────────┘                  │
│                                  │                                          │
│                           HTTPS (outbound)                                  │
└──────────────────────────────────┼──────────────────────────────────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │      XDC SkyNet Platform      │
                    │   https://net.xdc.network     │
                    │                                │
                    │  ┌──────────────────────────┐  │
                    │  │    API Gateway            │  │
                    │  │  /api/v1/nodes/*          │  │
                    │  │  /api/v1/peers/*          │  │
                    │  │  /api/v1/incidents/*      │  │
                    │  │  /api/v1/fleet/*          │  │
                    │  │  /api/v1/issues/*         │  │
                    │  └────────────┬─────────────┘  │
                    │               │                 │
                    │  ┌────────────▼─────────────┐  │
                    │  │  Node Registry + State    │  │
                    │  │  Incident Correlation     │  │
                    │  │  Fleet Dashboard          │  │
                    │  │  Alert Engine             │  │
                    │  └──────────────────────────┘  │
                    └──────────────────────────────────┘
```

---

## Agent Lifecycle

```
                    ┌─────────────────────┐
                    │     Agent Starts    │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │  Resolve RPC URL    │ ← Docker socket inspection
                    │  (self-healing)     │   or DNS by container name
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │  Load skynet.conf   │
                    │  + /tmp/skynet-*    │
                    └──────────┬──────────┘
                               │
                  ┌────────────▼────────────┐
                  │ Have SKYNET_NODE_ID +   │
                  │ SKYNET_API_KEY?         │
                  └─────┬───────────┬───────┘
                        │ No        │ Yes
                        ▼           ▼
           ┌────────────────┐  ┌───────────────┐
           │ Auto-Register  │  │  Skip to      │
           │ via /identify  │  │  heartbeat    │
           │ (fingerprint)  │  │  loop         │
           └───────┬────────┘  └───────┬───────┘
                   │ Fail?             │
                   ▼                   │
           ┌────────────────┐          │
           │ Legacy         │          │
           │ /register      │          │
           └───────┬────────┘          │
                   │                   │
                   └─────────┬─────────┘
                             │
                  ┌──────────▼──────────┐
                  │   HEARTBEAT LOOP    │ ← Runs every 30s (configurable)
                  │                     │
                  │  1. Collect metrics  │
                  │  2. Detect & heal   │
                  │  3. Send heartbeat  │
                  │  4. Process cmds    │
                  │  5. Periodic tasks  │
                  └──────────┬──────────┘
                             │
                             │ (loops forever)
                             └──────────────┐
                                            │
                                            ▼
```

---

## Heartbeat Data Flow

```
┌─────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  XDC Node   │     │  SkyOne Agent   │     │  SkyNet API     │
│  (RPC)      │     │  (sidecar)      │     │  (server)       │
└──────┬──────┘     └────────┬────────┘     └────────┬────────┘
       │                     │                        │
       │  eth_blockNumber    │                        │
       │◄────────────────────│                        │
       │────────────────────►│                        │
       │                     │                        │
       │  eth_syncing        │                        │
       │◄────────────────────│                        │
       │────────────────────►│                        │
       │                     │                        │
       │  admin_peers        │                        │
       │◄────────────────────│                        │
       │────────────────────►│                        │
       │                     │                        │
       │  web3_clientVersion │                        │
       │◄────────────────────│                        │
       │────────────────────►│                        │
       │                     │                        │
       │  eth_coinbase       │                        │
       │◄────────────────────│                        │
       │────────────────────►│                        │
       │                     │                        │
       │                     │  POST /v1/nodes/{id}/  │
       │                     │       heartbeat        │
       │                     │───────────────────────►│
       │                     │                        │
       │                     │  {success, commands[]} │
       │                     │◄───────────────────────│
       │                     │                        │
       │  admin_addPeer      │  (if commands include  │
       │  (if peer inject)   │   "add_peers")         │
       │◄────────────────────│                        │
       │                     │                        │
       │  docker restart     │  (if commands include  │
       │  (if restart cmd)   │   "restart")           │
       │◄────────────────────│                        │
       │                     │                        │
```

---

## Phase 2 Periodic Tasks

```
Time ──────────────────────────────────────────────────────────►

HB#   1    2    3    4    5    6    7    8    9    10   11  ...  20  ...  50  ...  120
      │    │    │    │    │    │    │    │    │    │    │       │       │       │
      ├────┼────┼────┼────┼────┼────┼────┼────┼────┼────┼───────┼───────┼───────┤
      │                                                                         │
      ▼  Every heartbeat (30s):                                                 │
      ├─ Collect metrics (block, peers, CPU, disk, etc.)                        │
      ├─ Error detection & auto-heal (10 log patterns)                          │
      ├─ Stall detection (block unchanged?)                                     │
      ├─ Peer drop detection (0 peers?)                                         │
      ├─ Disk pressure check (>90%?)                                            │
      │                                                                         │
      ▼  Every 10 HB (≈5 min):                                                 │
      ├─ Intelligent peer management (inject if <2 peers)                       │
      ├─ RPC re-resolution (detect container IP changes)                        │
      │                                                                         │
      ▼  Every 20 HB (≈10 min):                                                │
      ├─ Network height fetch (OpenScan RPC)                                    │
      ├─ Sync percent + ETA calculation                                         │
      │                                                                         │
      ▼  Every 50 HB (≈25 min):                                                │
      ├─ Config refresh from SkyNet (heartbeat interval, etc.)                  │
      │                                                                         │
      ▼  Every 120 HB (≈1 hour):                                               │
      └─ Self-diagnostic report (uptime, restarts, effectiveness, sync rate)    │
```

---

## Self-Healing Decision Tree

```
                    ┌──────────────────────┐
                    │  Issue Detected      │
                    │  (log pattern match  │
                    │   or stall/crash)    │
                    └──────────┬───────────┘
                               │
                    ┌──────────▼──────────┐
                    │  Check cooldown     │
                    │  for this issue     │
                    │  type               │
                    └─────┬─────────┬─────┘
                     Active│         │Expired
                          │         ▼
                          │  ┌──────────────────┐
                          │  │ Cross-Node        │
                          │  │ Correlation       │
                          │  │ (fleet query)     │
                          │  └──┬────────────┬───┘
                          │     │            │
                          │  Widespread   Isolated
                          │  (>70%)       (<70%)
                          │     │            │
                          │     ▼            ▼
                          │  ┌────────┐  ┌─────────────────┐
                          │  │ESCALATE│  │ Smart Restart    │
                          │  │(code   │  │ Logic Check      │
                          │  │ bug)   │  └──┬──────────┬───┘
                          │  └────────┘     │          │
                          │          Approved│    Denied│
                          │                 ▼          ▼
                          │          ┌──────────┐  ┌──────────┐
                          │          │ RESTART   │  │ ESCALATE │
                          │          │ container │  │ (limit   │
                          │          │ + record  │  │  reached │
                          │          └──────────┘  │  or last  │
                          │                        │  restart  │
                   ┌──────▼──────┐                 │  failed)  │
                   │ SKIP        │                 └──────────┘
                   │ (in cooldown│
                   │  period)    │
                   └─────────────┘
```

---

## RPC Self-Resolution (Docker)

```
┌──────────────────────────────────────────────────────────────┐
│  Agent Container (skyone-mainnet-geth)                       │
│                                                              │
│  RPC_URL = http://:8545  ← empty host after restart         │
│                   │                                          │
│                   ▼                                          │
│  ┌────────────────────────────────┐                          │
│  │ Is host empty?                 │                          │
│  └────┬───────────────────┬───────┘                          │
│   Yes │                   │ No                               │
│       ▼                   ▼                                  │
│  ┌──────────────┐  ┌──────────────────┐                      │
│  │ docker inspect│  │ Test RPC alive   │                      │
│  │ XDC_CONTAINER │  │ (net_version)    │                      │
│  │ → get IP      │  └──┬──────────┬───┘                      │
│  └──────┬───────┘   OK │      Dead│                          │
│         │              │          ▼                           │
│         │              │  ┌────────────────┐                  │
│         ▼              │  │ Re-resolve:    │                  │
│  ┌─────────────────┐   │  │ 1. docker IP   │                  │
│  │ RPC_URL =        │   │  │ 2. DNS name    │                  │
│  │ http://{ip}:8545 │   │  └────────────────┘                  │
│  └─────────────────┘   │                                      │
│                        │  Mounted: /var/run/docker.sock       │
└────────────────────────┼──────────────────────────────────────┘
                         │
                         ▼
                ┌─────────────────┐
                │  XDC Node       │
                │  Container      │
                │  172.25.0.x:8545│
                └─────────────────┘
```

---

## Multi-Client Fleet Topology

```
Server 185.180.220.168 (Mainnet)
├── xdc-mainnet-gp5        (Geth PR5)   :8545 → skyone-mainnet-gp5     :7070
├── xdc-mainnet-erigon     (Erigon)     :8546 → skyone-mainnet-erigon  :7071
├── xdc-mainnet-nm         (Nethermind) :8547 → skyone-mainnet-nm      :7072
└── xdc-mainnet-reth       (Reth)       :8548 → skyone-mainnet-reth    :7073

Server 185.180.220.183 (Apothem)
├── xdc-node-apothem       (Geth)       :8545 → agent-stable
├── xdc-node-gp5-apothem   (Geth PR5)   :8555 → agent-gp5
├── xdc-node-erigon-apo    (Erigon)     :8547 → agent-erigon
├── xdc-node-nm-apothem    (Nethermind) :8557 → agent-nm
└── xdc-node-reth-apothem  (Reth)       :8588 → agent-reth

                    │ All agents report to │
                    ▼                      ▼
        ┌──────────────────────────────────────┐
        │      SkyNet: net.xdc.network         │
        │                                      │
        │  Fleet Overview                      │
        │  ┌────────────────────────────────┐  │
        │  │ Node              Block  Peers │  │
        │  │ geth-v1.17-168    87.6M   12  │  │
        │  │ erigon-v2.60-168  87.6M    8  │  │
        │  │ nm-v1.25-168      87.5M   14  │  │
        │  │ reth-v0.2-168     87.4M    6  │  │
        │  │ geth-v2.6.8-183   72.1M   10  │  │
        │  │ ...                            │  │
        │  └────────────────────────────────┘  │
        └──────────────────────────────────────┘
```

---

## SkyNet API Surface (Agent-Side)

| Method | Endpoint | Direction | Description |
|--------|----------|-----------|-------------|
| `POST` | `/v1/nodes/identify` | Agent → SkyNet | Fingerprint-based registration |
| `POST` | `/v1/nodes/register` | Agent → SkyNet | Legacy registration |
| `POST` | `/v1/nodes/{id}/heartbeat` | Agent → SkyNet | Push metrics |
| `GET`  | `/v1/nodes/{id}/config` | Agent ← SkyNet | Fetch agent config |
| `GET`  | `/v1/peers/healthy` | Agent ← SkyNet | Get healthy peers for injection |
| `POST` | `/v1/nodes/{id}/errors` | Agent → SkyNet | Report errors |
| `POST` | `/v1/nodes/{id}/diagnostic` | Agent → SkyNet | Hourly diagnostic |
| `POST` | `/v1/incidents` | Agent → SkyNet | Report incidents |
| `POST` | `/v1/issues/report` | Agent → SkyNet | Report issues (cooldown) |
| `GET`  | `/v1/fleet/overview` | Agent ← SkyNet | Cross-node correlation |
| `POST` | `/v1/nodes/alerts` | Agent → SkyNet | Critical alerts |

---

## Configuration Flow

```
skynet-template.conf                    Per-client configs
        │                              ┌─ mainnet/.xdc-node/skynet.conf (geth)
        │  cp + customize             ├─ mainnet/.xdc-node/skynet-erigon.conf
        └──────────────────────────►  ├─ mainnet/.xdc-node/skynet-nethermind.conf
                                      ├─ mainnet/.xdc-node/skynet-reth.conf
                                      ├─ testnet/.xdc-node/skynet.conf
                                      └─ devnet/.xdc-node/skynet.conf
                                              │
                                    Docker volume mount
                                              │
                                              ▼
                                      /etc/xdc-node/skynet.conf
                                       (inside agent container)
```

---

## Cron Integration

```
/etc/cron.d/xdc-node
│
├── */5 * * * *   update-agent-ips.sh     ← Refresh container IPs
├── */15 * * * *  node-health-check.sh    ← Quick health check
├── 0 6 * * *     node-health-check.sh    ← Full daily report
├── 17 */6 * * *  version-check.sh        ← Check for updates
└── 0 3 * * *     backup.sh               ← Daily backup
```

---

## Security Model

```
┌──────────────────────────────────────────────────────┐
│  Agent Container                                      │
│                                                       │
│  Permissions:                                         │
│  ├── READ:  /etc/xdc-node/skynet.conf (600)          │
│  ├── READ:  /var/run/docker.sock (for IP resolution)  │
│  ├── READ:  /host/proc (for system metrics)           │
│  ├── READ:  /host/sshd_config (for security audit)    │
│  ├── WRITE: /tmp/skynet-* (state files)               │
│  └── EXEC:  docker restart {container} (self-heal)    │
│                                                       │
│  Network:                                             │
│  ├── Inbound:  None required                          │
│  ├── Outbound: HTTPS to SKYNET_API_URL only           │
│  └── Local:    HTTP to XDC node RPC                   │
│                                                       │
│  Secrets:                                             │
│  ├── SKYNET_API_KEY in skynet.conf (chmod 600)        │
│  └── State in /tmp/skynet-node-id (ephemeral)         │
└──────────────────────────────────────────────────────┘
```

---

## File Map

```
xdc-node-setup/
├── docker/
│   ├── skynet-agent.sh                    # v1 agent (daemon/systemd)
│   ├── skynet-agent-standalone.yml        # Standalone compose for v1
│   ├── docker-compose.skyone.yml          # SkyOne compose (3 profiles)
│   ├── docker-compose.skyone.v2.yml       # Optimized v2 compose
│   ├── docker-compose.apothem-skynet.yml  # Apothem agents compose
│   └── skynet-agent/
│       ├── combined-start.sh              # v2 Phase 2 agent (production)
│       ├── deploy-mainnet-agents.sh       # Fleet deployment script
│       ├── deploy-apo-agents.sh           # Apothem deployment script
│       └── update-agent-ips.sh            # Cron: refresh container IPs
├── scripts/
│   ├── skynet-agent.sh                    # v1.5 agent (with watchdog)
│   ├── skyone-register.sh                 # Multi-client registration
│   ├── skynet-register.sh                 # Bidirectional register/deregister
│   ├── validate-skyone-env.sh             # Pre-flight environment check
│   ├── deploy-skyone-agents.sh            # Agent deployer (host IP fix)
│   ├── macos-heartbeat.sh                 # macOS launchd installer
│   ├── populate-erigon-skynet.sh          # Erigon config helper
│   └── lib/
│       └── common.sh                      # Shared utilities (rpc_call, etc.)
├── configs/
│   └── nginx/skyone-ssl.conf             # SSL reverse proxy for dashboard
├── mainnet/.xdc-node/
│   ├── skynet.conf                        # Geth mainnet config
│   ├── skynet-erigon.conf                 # Erigon mainnet config
│   ├── skynet-nethermind.conf             # Nethermind mainnet config
│   └── skynet-reth.conf                   # Reth mainnet config
├── testnet/.xdc-node/skynet.conf          # Apothem config
├── devnet/.xdc-node/skynet.conf           # Devnet config
├── skynet-template.conf                   # Config template
├── cron/setup-crons.sh                    # Cron installer
└── docs/
    ├── SKYONE-AGENT.md                    # Feature reference (this companion)
    └── SKYONE-ARCHITECTURE.md             # This file
```
