# XDC Node Setup - Architecture Overview

**Version:** 2.2.0  
**Last Updated:** February 25, 2026

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         XDC Node Setup Architecture                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────┐                 │
│  │   CLI Tool  │    │  SkyOne UI   │    │  SkyNet API │                 │
│  │   (xdc)     │◄──►│  (Port 7070) │◄──►│  (Optional) │                 │
│  └──────┬──────┘    └──────┬───────┘    └─────────────┘                 │
│         │                  │                                             │
│         ▼                  ▼                                             │
│  ┌──────────────────────────────────────────────────┐                   │
│  │              Docker Compose Stack                 │                   │
│  ├──────────────────────────────────────────────────┤                   │
│  │  ┌───────────┐  ┌───────────┐  ┌──────────────┐  │                   │
│  │  │ XDC Node  │  │  SkyOne   │  │ Prometheus   │  │                   │
│  │  │  (Geth/   │  │ Dashboard │  │  (Metrics)   │  │                   │
│  │  │  Erigon)  │  │           │  │              │  │                   │
│  │  └─────┬─────┘  └───────────┘  └──────────────┘  │                   │
│  │        │                                         │                   │
│  │        ▼                                         │                   │
│  │  ┌───────────┐  ┌───────────┐                   │                   │
│  │  │  XDC Chain │  │   Data    │                   │                   │
│  │  │   Data    │  │  Volume   │                   │                   │
│  │  └───────────┘  └───────────┘                   │                   │
│  └──────────────────────────────────────────────────┘                   │
│                          │                                              │
│                          ▼                                              │
│  ┌──────────────────────────────────────────────────┐                   │
│  │              XDC P2P Network                      │                   │
│  │         (Mainnet / Testnet / Devnet)              │                   │
│  └──────────────────────────────────────────────────┘                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Component Overview

### 1. CLI Tool (`xdc`)

The `xdc` command provides a unified interface for node management:

| Command | Purpose |
|---------|---------|
| `xdc start` | Start the node with selected client |
| `xdc stop` | Stop the node gracefully |
| `xdc status` | Display node status and sync progress |
| `xdc logs` | View and follow node logs |
| `xdc backup` | Create encrypted backups |
| `xdc update` | Check and apply updates |

**Implementation:** Bash wrapper around Docker Compose

### 2. XDC Node (Blockchain Client)

Supports multiple client implementations:

| Client | Type | Status | RPC Port | P2P Port |
|--------|------|--------|----------|----------|
| XDC Geth | Official | Production | 8545 | 30303 |
| XDC Geth PR5 | Latest | Testing | 8545 | 30303 |
| Erigon-XDC | High-performance | Experimental | 8547 | 30304 |
| Nethermind-XDC | .NET-based | Beta | 8558 | 30306 |
| Reth-XDC | Rust-based | Alpha | 7073 | 40303 |

### 3. SkyOne Dashboard

Single-node monitoring dashboard:

- **Port:** 7070
- **Technology:** Next.js 14 + Tailwind CSS
- **Features:**
  - Real-time metrics
  - Log viewer
  - Peer monitoring
  - Alert timeline

### 4. Prometheus + Grafana

Metrics collection and visualization:

- **Prometheus Port:** 9090 (internal)
- **Grafana Port:** 3000 (internal)
- **Retention:** 30 days, 10GB cap

### 5. SkyNet Agent

Fleet monitoring integration:

- Auto-registers node with SkyNet
- Sends heartbeats every 30 seconds
- Reports metrics and incidents

---

## Data Flow

### Startup Flow

```
1. User runs: xdc start
2. setup.sh detects OS and environment
3. Docker Compose pulls images
4. XDC node starts syncing
5. SkyOne dashboard starts
6. SkyNet agent registers node (if enabled)
```

### Runtime Flow

```
1. XDC node syncs with network
2. Prometheus scrapes metrics
3. SkyOne displays real-time data
4. SkyNet agent sends heartbeats
5. Alerts triggered if issues detected
```

### Update Flow

```
1. User runs: xdc update
2. Check for new versions
3. Download new images
4. Rolling restart (zero-downtime)
5. Verify health post-update
```

---

## Configuration Management

### Directory Structure

```
XDC-Node-Setup/
├── mainnet/
│   ├── .xdc-node/
│   │   ├── config.toml      # Node configuration
│   │   ├── .env             # Environment variables
│   │   └── skynet.conf      # SkyNet settings
│   └── xdcchain/            # Blockchain data
├── testnet/
│   └── ...
└── devnet/
    └── ...
```

### Configuration Files

| File | Purpose | Format |
|------|---------|--------|
| `config.toml` | XDC node settings | TOML |
| `.env` | Docker environment | Shell |
| `skynet.conf` | Fleet monitoring | Shell |
| `genesis.json` | Network genesis | JSON |

---

## Security Architecture

### Container Security

- **No new privileges:** Containers cannot escalate privileges
- **Capability dropping:** All capabilities dropped, minimal set added
- **Read-only root:** Where possible, containers run with read-only filesystems
- **Tmpfs mounts:** Writable directories are tmpfs with size limits

### Network Security

- **Internal networks:** Monitoring stack on isolated network
- **Localhost binding:** RPC bound to 127.0.0.1 by default
- **Firewall integration:** UFW rules auto-configured

### Secret Management

- **Environment variables:** Secrets passed via env vars
- **Docker secrets:** Support for Docker secrets (Swarm mode)
- **File permissions:** Sensitive files have 600 permissions

---

## Multi-Client Architecture

### Port Allocation

When running multiple clients on the same machine:

| Client | RPC | WS | P2P | Metrics |
|--------|-----|-----|-----|---------|
| Geth | 8545 | 8546 | 30303 | 6060 |
| Erigon | 8547 | 8548 | 30304 | 6061 |
| Nethermind | 8558 | 8559 | 30306 | 6062 |
| Reth | 7073 | 7074 | 40303 | 6063 |

### Client Discovery

- Each client discovers peers via bootnodes
- Cross-client peering supported on compatible protocols
- Erigon uses dual-sentry (eth/63 + eth/68)

---

## Monitoring Architecture

### Metrics Collection

```
XDC Node ──► Prometheus ──► Grafana
    │              │
    └──────────────┘
    SkyOne Dashboard
```

### Alert Pipeline

```
Metric Threshold ──► Alertmanager ──► Notification Channel
    │                      │
    └──────────────────────┘
    SkyNet Incident Creation
```

---

## Deployment Patterns

### Single Node (Default)

```bash
./setup.sh
xdc start
```

### Multi-Client

```bash
# Terminal 1
CLIENT=erigon ./setup.sh
xdc start --client erigon

# Terminal 2
CLIENT=nethermind ./setup.sh
xdc start --client nethermind
```

### Kubernetes

```bash
helm install xdc-node ./k8s/helm-chart \
  --set network=mainnet \
  --set client=erigon
```

---

## Troubleshooting Architecture

### Log Aggregation

- Container logs → Docker logging driver
- JSON format with rotation (50MB × 5 files)
- Accessible via: `xdc logs`

### Health Checks

- **XDC Node:** RPC health endpoint
- **Dashboard:** HTTP health check
- **Prometheus:** Metrics endpoint

### Debug Mode

```bash
# Enable debug logging
DEBUG=1 xdc start

# Attach to node console
xdc attach
```

---

## Future Architecture

### Planned Enhancements

1. **Sidecar Pattern:** Separate consensus client from execution client
2. **Snapshot Sync:** Automated snapshot download
3. **Hot Swapping:** Client switching without full resync
4. **Federation:** Multi-region node coordination

### Scalability Roadmap

| Phase | Feature | Target |
|-------|---------|--------|
| 1 | Snapshot sync | Q1 2026 |
| 2 | Kubernetes operator | Q2 2026 |
| 3 | Multi-client mesh | Q3 2026 |
| 4 | Edge deployment | Q4 2026 |

---

## API Reference

### Internal APIs

| Endpoint | Purpose | Auth |
|----------|---------|------|
| `localhost:8545` | XDC RPC | None (localhost) |
| `localhost:7070/api/health` | Health check | None |
| `localhost:7070/api/metrics` | Prometheus metrics | None |
| `localhost:9090` | Prometheus UI | Basic Auth |
| `localhost:3000` | Grafana | Basic Auth |

### External APIs (SkyNet)

| Endpoint | Purpose | Auth |
|----------|---------|------|
| `skynet.xdcindia.com/api/v1/nodes/register` | Node registration | API Key |
| `skynet.xdcindia.com/api/v1/nodes/heartbeat` | Heartbeat | API Key |

---

*Document version: 2.2.0 - February 25, 2026*
