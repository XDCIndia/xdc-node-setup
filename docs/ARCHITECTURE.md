# XDC Node Setup - Architecture Overview

## Table of Contents
1. [System Architecture](#system-architecture)
2. [XDPoS 2.0 Consensus Integration](#xdpos-20-consensus-integration)
3. [Multi-Client Support](#multi-client-support)
4. [Security Architecture](#security-architecture)
5. [Deployment Patterns](#deployment-patterns)
6. [Monitoring and Observability](#monitoring-and-observability)

---

## System Architecture

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         XDC Node Setup Architecture                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────┐                     │
│  │   CLI Tool  │    │  SkyOne UI   │    │  SkyNet API │                     │
│  │   (xdc)     │◄──►│  (Port 7070) │◄──►│  (Optional) │                     │
│  └──────┬──────┘    └──────┬───────┘    └─────────────┘                     │
│         │                  │                                                │
│         ▼                  ▼                                                │
│  ┌──────────────────────────────────────────────────────────────┐          │
│  │              Docker Compose Stack                             │          │
│  ├──────────────────────────────────────────────────────────────┤          │
│  │  ┌───────────┐  ┌───────────┐  ┌──────────────┐             │          │
│  │  │ XDC Node  │  │  SkyOne   │  │ Prometheus   │             │          │
│  │  │  (Geth/   │  │ Dashboard │  │  (Metrics)   │             │          │
│  │  │  Erigon)  │  │           │  │              │             │          │
│  │  └─────┬─────┘  └───────────┘  └──────────────┘             │          │
│  │        │                                                    │          │
│  │        ▼                                                    │          │
│  │  ┌───────────┐  ┌───────────┐                              │          │
│  │  │  XDC Chain │  │   Data    │                              │          │
│  │  │   Data    │  │  Volume   │                              │          │
│  │  └───────────┘  └───────────┘                              │          │
│  └──────────────────────────────────────────────────────────────┘          │
│                          │                                                  │
│                          ▼                                                  │
│  ┌──────────────────────────────────────────────────────────────┐          │
│  │              XDPoS 2.0 Consensus Network                      │          │
│  │         (Mainnet / Testnet / Devnet)                          │          │
│  └──────────────────────────────────────────────────────────────┘          │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Component Flow

1. **CLI (`xdc`)**: User interface for node management
2. **SkyOne Dashboard**: Web UI for single-node monitoring (Next.js + Tailwind)
3. **XDC Node**: Core blockchain client (supports multiple implementations)
4. **Prometheus**: Metrics collection and storage
5. **SkyNet Agent**: Optional fleet monitoring integration

---

## XDPoS 2.0 Consensus Integration

### Consensus Architecture

XDPoS 2.0 (Delegated Proof of Stake v2.0) is the consensus mechanism for XDC Network:

```
┌─────────────────────────────────────────────────────────────────┐
│                    XDPoS 2.0 Epoch Structure                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Epoch N (900 blocks)                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Block 0          Block 450         Block 899            │   │
│  │ ┌─────┐          ┌─────┐           ┌─────┐              │   │
│  │ │Start│ ───────► │ Gap │ ────────► │ End │ ───► Epoch   │   │
│  │ │     │          │Block│           │     │      N+1     │   │
│  │ └─────┘          └─────┘           └─────┘              │   │
│  │    │                │                │                   │   │
│  │    ▼                ▼                ▼                   │   │
│  │ Masternode      QC Formation    New Masternode          │   │
│  │ Set Updated     at Gap Block    Set Election            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  Key Parameters:                                                 │
│  - Epoch Length: 900 blocks                                      │
│  - Gap Block: Position 450 (middle of epoch)                     │
│  - QC Requirement: 2/3+ masternode signatures                    │
│  - Timeout: 30 seconds default                                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Consensus Monitoring

The following metrics are tracked for XDPoS 2.0:

| Metric | Description | Importance |
|--------|-------------|------------|
| Epoch Position | Current position within epoch | Critical |
| QC Formation Time | Time to form Quorum Certificate | Critical |
| Vote Participation | % of masternodes voting | High |
| Timeout Count | Number of timeout events | High |
| View Changes | Number of view changes | High |
| Masternode Participation | Individual masternode activity | Critical |

### Implementation Details

```bash
# Epoch calculation
calculate_epoch_info() {
    local block_number=$1
    local epoch_size=900
    local epoch_number=$((block_number / epoch_size))
    local epoch_position=$((block_number % epoch_size))
    local is_gap_block=$((epoch_position == 450 ? 1 : 0))
    local is_epoch_boundary=$((epoch_position == 899 ? 1 : 0))
    
    echo "{\"epoch\":$epoch_number,\"position\":$epoch_position,\"isGap\":$is_gap_block,\"isBoundary\":$is_epoch_boundary}"
}

# XDPoS RPC calls
XDPoS_getMasternodesByNumber("latest")
XDPoS_getVoterStatus(address)
XDPoS_getEpochInfo(epochNumber)
XDPoS_getQCByNumber(blockNumber)
```

---

## Multi-Client Support

### Supported Clients

| Client | Status | RPC Port | P2P Port | Memory | Disk |
|--------|--------|----------|----------|--------|------|
| XDC Stable (v2.6.8) | ✅ Production | 8545 | 30303 | 4GB+ | ~500GB |
| XDC Geth PR5 | ✅ Testing | 8545 | 30303 | 4GB+ | ~500GB |
| Erigon-XDC | ⚠️ Experimental | 8547 | 30304/30311 | 8GB+ | ~400GB |
| Nethermind-XDC | ⚠️ Beta | 8558 | 30306 | 12GB+ | ~350GB |
| Reth-XDC | ⚠️ Alpha | 7073 | 40303 | 16GB+ | ~300GB |

### Client Selection

```bash
# Interactive selection during setup
./setup.sh
# Select client [1-5]:
# 1) XDC Stable (v2.6.8) - Official Docker image (recommended)
# 2) XDC Geth PR5 - Latest geth with XDPoS
# 3) Erigon-XDC - Multi-client diversity
# 4) Nethermind-XDC - .NET-based client
# 5) Reth-XDC - Rust-based client

# Command line selection
./setup.sh --client erigon
```

### Cross-Client Compatibility

When running multiple clients, ensure:
1. Different RPC ports for each client
2. Different P2P ports to avoid conflicts
3. Separate data directories
4. Cross-client block comparison for divergence detection

---

## Security Architecture

### Security Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                    Security Architecture                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Layer 1: Network Security                                       │
│  ├── UFW Firewall (ports 22, 30303, 7070)                       │
│  ├── Fail2ban (brute force protection)                          │
│  └── DDoS protection (rate limiting)                            │
│                                                                  │
│  Layer 2: Application Security                                   │
│  ├── RPC bound to localhost (127.0.0.1)                         │
│  ├── CORS restricted to known origins                           │
│  └── Authentication on all endpoints                            │
│                                                                  │
│  Layer 3: Container Security                                     │
│  ├── Non-root user in containers                                │
│  ├── Read-only root filesystem                                  │
│  └── No docker.sock mounting                                    │
│                                                                  │
│  Layer 4: Data Security                                          │
│  ├── Encrypted backups                                          │
│  ├── Secure key storage                                         │
│  └── Audit logging                                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Security Checklist

- [ ] RPC bound to 127.0.0.1 (not 0.0.0.0)
- [ ] CORS restricted to specific origins
- [ ] Firewall enabled (UFW/iptables)
- [ ] Fail2ban installed and running
- [ ] SSH on non-standard port
- [ ] Root login disabled
- [ ] Automatic security updates enabled
- [ ] Docker running in rootless mode (optional)

---

## Deployment Patterns

### Single Node Deployment

```yaml
# docker-compose.yml (simplified)
services:
  xdc-node:
    image: xinfinorg/xdposchain:v2.6.8
    container_name: xdc-node
    restart: always
    ports:
      - "127.0.0.1:8545:8545"  # RPC (localhost only)
      - "30303:30303"          # P2P
      - "30303:30303/udp"
    volumes:
      - ./xdcchain:/work/xdcchain
    environment:
      - RPC_ADDR=127.0.0.1
      - RPC_CORS_DOMAIN=https://net.xdc.network
```

### Multi-Client Deployment

```yaml
# docker-compose.multiclient.yml
services:
  xdc-geth:
    image: xinfinorg/xdposchain:v2.6.8
    ports:
      - "127.0.0.1:8545:8545"
      - "30303:30303"
    volumes:
      - ./data/geth:/work/xdcchain

  xdc-erigon:
    image: anilchinchawale/erix:latest
    ports:
      - "127.0.0.1:8547:8547"
      - "30304:30304"
    volumes:
      - ./data/erigon:/data

  xdc-nethermind:
    image: anilchinchawale/nmx:latest
    ports:
      - "127.0.0.1:8558:8558"
      - "30306:30306"
    volumes:
      - ./data/nethermind:/data
```

### Kubernetes Deployment

```yaml
# k8s/statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: xdc-node
spec:
  serviceName: xdc-node
  replicas: 3
  podManagementPolicy: Parallel
  template:
    spec:
      containers:
      - name: xdc-node
        image: xinfinorg/xdposchain:v2.6.8
        resources:
          requests:
            memory: "8Gi"
            cpu: "4"
          limits:
            memory: "32Gi"
            cpu: "16"
        volumeMounts:
        - name: xdc-data
          mountPath: /xdcchain
  volumeClaimTemplates:
  - metadata:
      name: xdc-data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: fast-ssd
      resources:
        requests:
          storage: 1Ti
```

---

## Monitoring and Observability

### Metrics Collection

| Category | Metrics | Collection Method |
|----------|---------|-------------------|
| Blockchain | Block height, sync status, peer count | RPC polling |
| Consensus | Epoch position, QC time, votes | XDPoS RPC |
| System | CPU, memory, disk, network | Node exporter |
| Application | RPC latency, error rates | Prometheus |

### Alerting Rules

```yaml
# alerting/rules.yml
groups:
  - name: xdc-node
    rules:
      - alert: NodeDown
        expr: up{job="xdc-node"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "XDC node is down"

      - alert: SyncStall
        expr: increase(xdc_block_height[10m]) == 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Block sync has stalled"

      - alert: LowPeers
        expr: xdc_peer_count < 5
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Low peer count"

      - alert: EpochTransitionDelayed
        expr: xdpos_epoch_transition_time > 30
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Epoch transition is delayed"
```

### Dashboard Views

1. **Overview**: Node health, sync status, key metrics
2. **Consensus**: Epoch information, QC formation, votes
3. **Peers**: Connected peers, geographic distribution
4. **System**: Resource usage, performance trends
5. **Alerts**: Active alerts, historical incidents

---

## Troubleshooting Guide

### Common Issues

#### Node Won't Start
```bash
# Check Docker is running
sudo systemctl status docker

# Check port conflicts
sudo netstat -tlnp | grep -E '8545|30303|7070'

# View logs
xdc logs --follow
```

#### Node Won't Sync
```bash
# Check peer count
xdc peers

# Check sync status
xdc sync

# Add peers from SkyNet
xdc skynet add-peers

# Download snapshot
xdc snapshot download --network mainnet
xdc snapshot apply
```

#### High Resource Usage
```bash
# Reduce memory cache
xdc config set cache 2048
xdc restart

# Enable pruning
xdc config set prune_mode full
xdc restart
```

---

## API Reference

### XDPoS-Specific RPC Methods

| Method | Parameters | Description |
|--------|------------|-------------|
| XDPoS_getMasternodesByNumber | blockNumber | Get active masternodes |
| XDPoS_getVoterStatus | address | Get voter participation status |
| XDPoS_getEpochInfo | epochNumber | Get epoch details |
| XDPoS_getQCByNumber | blockNumber | Get Quorum Certificate |

### Standard Ethereum RPC

| Method | Parameters | Description |
|--------|------------|-------------|
| eth_blockNumber | none | Get current block height |
| eth_getBlockByNumber | number, fullTx | Get block by number |
| eth_syncing | none | Get sync status |
| admin_peers | none | Get connected peers |

---

## References

- [XDC Network Documentation](https://docs.xdc.network)
- [XDPoS 2.0 Consensus](https://www.xdc.dev/xdc-foundation/xdpos-2-0-consensus-algorithm)
- [XDPoSChain GitHub](https://github.com/XinFinOrg/XDPoSChain)
- [Docker Documentation](https://docs.docker.com)
- [Kubernetes Documentation](https://kubernetes.io/docs)
