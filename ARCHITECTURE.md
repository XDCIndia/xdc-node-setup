# XDC Node Setup - Architecture Overview

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

## Component Flow

1. **CLI (`xdc`)**: User interface for node management
2. **SkyOne Dashboard**: Web UI for monitoring (Next.js + Tailwind)
3. **XDC Node**: Core blockchain client (Geth/Erigon/Nethermind/Reth)
4. **Prometheus**: Metrics collection and storage
5. **SkyNet Agent**: Optional fleet monitoring integration

## Multi-Client Support

### Port Allocation

| Client | RPC Port | P2P Port | Metrics | Notes |
|--------|----------|----------|---------|-------|
| Geth Stable | 8545 | 30303 | 6060 | Official XDC client |
| Geth PR5 | 7070 | 30304 | 6070 | Latest XDPoS features |
| Erigon | 7071 | 30305 | 6071 | Dual-sentry architecture |
| Nethermind | 7072 | 30306 | 6072 | .NET implementation |
| Reth | 8588 | 40303 | 6073 | Rust implementation |

## XDPoS 2.0 Consensus Integration

### Epoch Structure

```
Epoch N (Blocks 0-899):
┌────────────────────┬───────────────────┐
│  Voting Phase      │    Gap Phase      │
│  Blocks 0-449      │   Blocks 450-899  │
│  (Validator votes) │   (No votes)      │
└────────────────────┴───────────────────┘
```

### Key Components

1. **QC Validation** (`scripts/qc-validation.sh`)
2. **Consensus Health Monitor** (`scripts/consensus-health.sh`)
3. **Gap Block Monitor** (`scripts/xdpos/gap-block-monitor.sh`)

## Security Architecture

### Security Score Calculation

| Check | Points |
|-------|--------|
| SSH key-only | 10 |
| Non-standard SSH port | 5 |
| Firewall active | 10 |
| Fail2ban running | 5 |
| Unattended upgrades | 5 |
| OS patches current | 10 |
| Client version current | 15 |
| Monitoring active | 10 |
| Backup configured | 10 |
| Audit logging | 10 |
| Disk encryption | 10 |
| **Total** | **100** |

## Self-Healing Mechanisms

### Watchdog System

- Health checks every 30s
- Auto-restart on failure (max 3/hour)
- 5-minute cooldown between restarts
- SkyNet escalation on persistent issues

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NETWORK_ID` | 50 | Mainnet=50, Testnet=51 |
| `SYNC_MODE` | snap | snap, full, fast |
| `RPC_PORT` | 8545 | JSON-RPC port |
| `P2P_PORT` | 30303 | P2P port |
| `SKYNET_API_URL` | https://net.xdc.network | SkyNet endpoint |

---

*See also: SETUP.md, TROUBLESHOOTING.md, XDPOS2-OPERATOR-GUIDE.md*
