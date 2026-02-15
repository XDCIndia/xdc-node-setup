# XDC Erigon Docker Setup

Production-ready Docker setup for XDC Network on Erigon client.

## Features

- ✅ **Official Erigon base** — Based on erigontech/erigon Dockerfile
- ✅ **Cross-platform** — AMD64 (v1/v2) and ARM64 support
- ✅ **Multi-stage build** — Optimized image size (~200MB vs ~2GB)
- ✅ **Non-root user** — Security best practices
- ✅ **Go 1.24** — Production standard (aligned with upstream Erigon)
- ✅ **Dual P2P sentries** — eth/63 (port 30304) + eth/68 (port 30311)
- ✅ **Health checks** — Auto-restart on failure
- ✅ **Logging** — Structured logs with rotation

## Quick Start

### 1. Build the Image

```bash
# Standard build (AMD64)
docker build -t xdc-erigon .

# With Silkworm (x86_64 only, experimental)
docker build --build-arg BUILD_SILKWORM=true -t xdc-erigon .

# For ARM64 (Raspberry Pi, Mac M1/M2)
docker build --platform linux/arm64 -t xdc-erigon .
```

### 2. Run with Docker Compose (Recommended)

```bash
# Create data directory
mkdir -p ./data

# Start node
docker-compose up -d

# View logs
docker-compose logs -f

# Stop node
docker-compose down
```

### 3. Run with Docker CLI

```bash
docker run -d \
  --name xdc-node-erigon \
  --restart unless-stopped \
  -p 8545:8545 \
  -p 30303:30303 \
  -p 30304:30304 \
  -v $(pwd)/data:/work/xdcchain \
  xdc-erigon \
  --chain=xdc \
  --datadir=/work/xdcchain \
  --http \
  --http.addr=0.0.0.0 \
  --http.api=eth,net,web3
```

## Configuration

### Environment Variables

Edit `docker-compose.yml` or pass via `-e`:

- `XDC_DATA_DIR` — Data directory path (default: `./data`)
- `UID` / `GID` — User/group IDs (default: `1000:1000`)

### Command-Line Flags

All Erigon flags are supported. Key XDC-specific flags:

```bash
--chain=xdc                    # XDC mainnet chainspec
--http.api=eth,net,web3,erigon # RPC API modules
--maxpeers=100                 # Max peer connections
--db.size.limit=8TB            # Database size limit
--private.api.addr=0.0.0.0:9090 # gRPC diagnostics
```

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8545 | TCP | HTTP RPC API |
| 8551 | TCP | Engine API (authrpc) |
| 30303 | TCP/UDP | P2P discovery |
| 30304 | TCP/UDP | Sentry (eth/63, XDC mainnet) |
| 30311 | TCP/UDP | Sentry (eth/68, modern clients) |
| 9090 | TCP | gRPC diagnostics |
| 6060 | TCP | Metrics (pprof) |

## Data Directory

Erigon stores data in `/work/xdcchain`:

```
data/
├── chaindata/      # Blockchain state
├── snapshots/      # Historical snapshots
├── txpool/         # Transaction pool
└── nodes/          # P2P node database
```

**Volume mount:** `-v /path/to/data:/work/xdcchain`

## Health Check

```bash
# Check if RPC is responding
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Expected: {"jsonrpc":"2.0","id":1,"result":"0x..."}
```

## Monitoring

### Docker logs
```bash
docker logs -f xdc-node-erigon
```

### Metrics endpoint
```bash
curl http://localhost:6060/debug/metrics/prometheus
```

### gRPC diagnostics
```bash
# Requires grpcurl
grpcurl -plaintext localhost:9090 list
```

## Troubleshooting

### Container exits immediately
```bash
# Check logs
docker logs xdc-node-erigon

# Common causes:
# - Corrupted data directory → delete and resync
# - Port conflicts → check with `netstat -tulpn`
# - Permission issues → chown data directory to UID 1000
```

### Sync stuck
```bash
# Check peer count
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'

# If zero peers, check firewall
sudo ufw allow 30303
sudo ufw allow 30304
```

### High CPU/memory
```bash
# Limit resources in docker-compose.yml
deploy:
  resources:
    limits:
      cpus: '4'
      memory: 16G
```

## Building from Source

If you need to modify the Erigon code:

```bash
# 1. Clone XDC erigon fork
git clone --branch feature/xdc-network https://github.com/AnilChinchawale/erigon-xdc.git
cd erigon-xdc

# 2. Make your changes
# ...

# 3. Build Docker image from current directory
docker build -t xdc-erigon -f /path/to/xdc-node-setup/docker/erigon/Dockerfile .
```

## Architecture

**Multi-stage build:**
```
Stage 1 (builder):
  - golang:1.22-bookworm base
  - Clone XDC erigon fork
  - Build erigon binary
  - Build Silkworm library (optional, AMD64 only)

Stage 2 (runtime):
  - debian:12-slim base
  - Copy erigon binary
  - Setup non-root user
  - Install runtime dependencies only
  - Final image: ~200MB
```

## Performance Tips

1. **Use SSD/NVMe** — Database is I/O intensive
2. **Allocate 16GB+ RAM** — Required for full sync
3. **Fast CPU** — Multi-core preferred (4+ cores)
4. **Stable network** — 100+ Mbps recommended
5. **Keep ports open** — 30303, 30304 for peer discovery

## Differences from Official Erigon

1. **XDC chainspec** — Supports XDPoS consensus
2. **eth/63 sentry** — Required for XDC mainnet peers
3. **Go 1.22** — Downgraded from 1.25 for stability
4. **No ForkID in handshake** — XDC-specific P2P protocol

## Support

- **Issues:** https://github.com/AnilChinchawale/xdc-node-setup/issues
- **XDC Network:** https://xdc.network
- **Erigon Docs:** https://erigon.tech

## License

Same as Erigon (LGPL-3.0)
