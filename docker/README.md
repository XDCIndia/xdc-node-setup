# XDC Client Docker Images - OS Agnostic

Cross-platform Docker images for XDC Network clients.

## Supported Platforms

- **Linux** (amd64, arm64)
- **macOS** (Intel/AMD64, Apple Silicon/ARM64)
- **Windows** (WSL2, Docker Desktop)

## Images

| Image | Client | Tag | Description |
|-------|--------|-----|-------------|
| `anilchinchawale/gx` | XDC Geth | `stable`, `latest` | Ethereum Go client with XDPoS |
| `anilchinchawale/nmx` | XDC Nethermind | `stable`, `latest` | .NET client with XDC support |
| `anilchinchawale/erix` | XDC Erigon | `stable`, `latest` | Fast Ethereum client with XDC |

## Source Repositories

- **Geth**: https://github.com/AnilChinchawale/go-ethereum/tree/feature/xdpos-consensus
- **Nethermind**: https://github.com/AnilChinchawale/nethermind/tree/build/xdc-net9-stable
- **Erigon**: https://github.com/AnilChinchawale/erigon-xdc/tree/feature/xdc-network

## Quick Start

### 1. Build All Images

```bash
cd docker
chmod +x build-*.sh
./build-all-xdc.sh
```

### 2. Build Individual Images

```bash
# Geth
./build-gx.sh

# Nethermind
./build-nmx.sh

# Erigon
./build-erix.sh
```

### 3. Run All Clients

```bash
docker-compose -f docker-compose.xdc-clients.yml up -d
```

### 4. Run Individual Client

**Geth:**
```bash
docker run -d \
  --name xdc-geth \
  -p 8545:8545 \
  -p 8546:8546 \
  -p 30303:30303 \
  -v xdc-geth-data:/data/xdcchain \
  anilchinchawale/gx:stable \
  --networkid=51 \
  --http --http.addr=0.0.0.0 \
  --ws --ws.addr=0.0.0.0
```

**Nethermind:**
```bash
docker run -d \
  --name xdc-nethermind \
  -p 8557:8557 \
  -p 30305:30305 \
  -v xdc-nethermind-data:/data/nethermind \
  anilchinchawale/nmx:stable
```

**Erigon:**
```bash
docker run -d \
  --name xdc-erigon \
  -p 8555:8555 \
  -p 30304:30304 \
  -v xdc-erigon-data:/data/erigon \
  anilchinchawale/erix:stable \
  --chain=xdc-apothem \
  --networkid=51 \
  --http --http.addr=0.0.0.0
```

## RPC Endpoints

| Client | HTTP RPC | WebSocket | P2P |
|--------|----------|-----------|-----|
| Geth (gx) | http://localhost:8545 | ws://localhost:8546 | 30303 |
| Nethermind (nmx) | http://localhost:8557 | ws://localhost:8558 | 30305 |
| Erigon (erix) | http://localhost:8555 | ws://localhost:8556 | 30304 |

## Networks

- **Apothem Testnet**: Chain ID 51
- **Mainnet**: Chain ID 50
- **Devnet**: Chain ID 551

## Data Volumes

Docker volumes are used for data persistence:

- `xdc-geth-data` - Geth chain data
- `xdc-nethermind-data` - Nethermind chain data
- `xdc-erigon-data` - Erigon chain data

## Health Checks

All containers include Docker health checks:
- **Geth**: Checks HTTP RPC endpoint
- **Nethermind**: Checks health endpoint
- **Erigon**: Checks HTTP RPC endpoint

## Logs

```bash
# Geth
docker logs -f xdc-geth

# Nethermind
docker logs -f xdc-nethermind

# Erigon
docker logs -f xdc-erigon
```

## Stop & Remove

```bash
# Stop all
docker-compose -f docker-compose.xdc-clients.yml down

# Stop individual
docker stop xdc-geth xdc-nethermind xdc-erigon

# Remove volumes (WARNING: Deletes all chain data!)
docker-compose -f docker-compose.xdc-clients.yml down -v
```

## Push to Registry

```bash
docker push anilchinchawale/gx:stable
docker push anilchinchawale/nmx:stable
docker push anilchinchawale/erix:stable
```

## Architecture Support

All images support:
- `linux/amd64` - x86_64, Intel, AMD
- `linux/arm64` - ARM64, Apple Silicon, AWS Graviton

Docker Buildx is used automatically when available.

## Security

- All containers run as non-root users
- Minimal Alpine Linux base images
- Health checks included
- Signal handling for graceful shutdown

## Troubleshooting

### Build fails on ARM (Apple Silicon)
```bash
# Use buildx for cross-platform builds
docker buildx create --name xdc-builder --usedocker buildx build --platform linux/arm64 -t anilchinchawale/gx:stable .
```

### Port conflicts
```bash
# Check used ports
lsof -i :8545

# Change ports in docker-compose.yml
```

### Permission denied on volumes
```bash
# Fix permissions
sudo chown -R $(id -u):$(id -g) /var/lib/docker/volumes/xdc-geth-data/
```

## License

See individual repository licenses for each client.
