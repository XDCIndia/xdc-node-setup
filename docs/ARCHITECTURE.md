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

### Supported Clients

| Client | Type | Status | RPC Port | P2P Port |
|--------|------|--------|----------|----------|
| XDC Geth | Official | Production | 8545 | 30303 |
| XDC Geth PR5 | Latest | Testing | 8545 | 30303 |
| Erigon-XDC | Experimental | Experimental | 8547 | 30304/30311 |
| Nethermind-XDC | .NET | Beta | 8558 | 30306 |
| Reth-XDC | Rust | Alpha | 7073 | 40303 |

### Client Selection

```bash
# Interactive selection
./setup.sh

# Command line selection
xdc start --client erigon

# Environment variable
CLIENT=erigon ./setup.sh
```

## XDPoS 2.0 Consensus Integration

### Epoch Configuration

```
Epoch Length: 900 blocks
Gap Blocks: 450 blocks before epoch end
Masternode Count: 108
Standby Count: Variable
```

### Consensus Events

1. **Block Production**: Masternodes produce blocks in round-robin
2. **Voting**: Masternodes vote for blocks to form QC
3. **QC Formation**: 2/3+ votes required for quorum
4. **Epoch Transition**: New masternode set every 900 blocks
5. **Timeout**: Timeout certificates if QC not formed

## Data Flow

### Startup Flow

```
1. setup.sh → Detect OS, install dependencies
2. Docker Compose → Pull images, create volumes
3. XDC Node → Initialize genesis, start sync
4. SkyOne Agent → Start dashboard, register with SkyNet
5. Prometheus → Start metrics collection
```

### Runtime Flow

```
1. XDC Node → Sync blocks, process transactions
2. Prometheus → Scrape metrics every 15s
3. SkyOne → Display metrics, check health
4. SkyNet Agent → Send heartbeat every 60s
5. Alertmanager → Send alerts on issues
```

## Security Architecture

### Network Security

- RPC bound to localhost by default (127.0.0.1)
- P2P port (30303) exposed for network participation
- Dashboard port (7070) for local access
- Internal Docker network for service communication

### Container Security

```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
cap_add:
  - CHOWN
  - SETGID
  - SETUID
```

### Data Security

- Keystore password in Docker secret (production)
- Volume mounts for persistent data
- Log rotation to prevent disk exhaustion
- Backup encryption for node data

## Monitoring Architecture

### Metrics Collection

```
XDC Node → Prometheus → Grafana → Alerts
    ↓
SkyOne Dashboard (real-time)
    ↓
SkyNet API (fleet aggregation)
```

### Health Checks

| Component | Check | Interval |
|-----------|-------|----------|
| XDC Node | RPC eth_blockNumber | 30s |
| SkyOne | HTTP /api/health | 30s |
| Prometheus | Target scraping | 15s |

## Scaling Considerations

### Vertical Scaling

- Increase CPU/memory limits in docker-compose.yml
- Use NVMe SSD for chain data
- Increase Prometheus retention

### Horizontal Scaling

- One node per host (recommended)
- Kubernetes StatefulSet for orchestration
- Shared nothing architecture

## Integration Points

### SkyNet Integration

```
SkyOne Agent → HTTPS → SkyNet API
    ↓
Node Registration (POST /api/v1/nodes/register)
Heartbeat (POST /api/v1/nodes/heartbeat)
Issues (POST /api/v1/issues/report)
```

### External RPC

```
Users → nginx → XDC Node RPC
    ↓
Authentication (API keys)
Rate Limiting
TLS Termination
```

## Configuration Hierarchy

1. **Environment Variables** (highest priority)
2. **Config Files** (.env, config.toml)
3. **CLI Arguments**
4. **Docker Compose defaults**
5. **Script defaults** (lowest priority)

## Troubleshooting Architecture

### Log Aggregation

```
XDC Node → /var/log/xdc/ → Docker logs → Log rotation
    ↓
SkyOne → Log viewer in dashboard
```

### Debug Endpoints

| Endpoint | Purpose |
|----------|---------|
| /debug/pprof | Go profiling (localhost only) |
| /metrics | Prometheus metrics |
| /api/health | Health check |

## Deployment Patterns

### Single Node

```bash
./setup.sh
xdc start
```

### With Monitoring

```bash
./setup.sh --monitoring
xdc start --monitoring
```

### With SkyNet

```bash
./setup.sh --skynet
xdc start
```

## Future Architecture

### Planned Enhancements

1. **Kubernetes Operator**: Native K8s deployment
2. **Snapshot Sync**: Automated fast sync
3. **Self-Healing**: Automatic recovery
4. **Multi-Client Consensus Testing**: Cross-client validation

## References

- [Docker Compose Configuration](docker/docker-compose.yml)
- [Setup Script](setup.sh)
- [CLI Reference](README.md#cli-reference)
- [XDPoS 2.0 Spec](https://docs.xdc.network/consensus)
