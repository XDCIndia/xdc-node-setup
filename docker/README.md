# XDC Client Docker Images - OS Agnostic

Cross-platform Docker images for XDC Network clients.

## Reference Implementations

These Dockerfiles are adapted from official client implementations:

| Client | Official Image | Our Image | Source Repository |
|--------|----------------|-----------|-------------------|
| **Geth** | `ethereum/client-go` | `anilchinchawale/gx` | https://github.com/AnilChinchawale/go-ethereum/tree/feature/xdpos-consensus |
| **Nethermind** | `nethermind/nethermind` | `anilchinchawale/nmx` | https://github.com/AnilChinchawale/nethermind/tree/build/xdc-unified |
| **Erigon** | `erigontech/erigon` | `anilchinchawale/erix` | https://github.com/AnilChinchawale/erigon-xdc/tree/feature/xdc-network |

## Adaptations from Official Images

### Geth (`Dockerfile.gx`)
**Based on:** `ethereum/client-go` official Dockerfile

**Key adaptations:**
- Uses `golang:1.23-alpine` (matching XDC fork requirements)
- Clones from XDC fork repository instead of upstream
- Binary name changed from `geth` to `XDC`
- Added `jq` for better health check parsing
- Maintains official best practices: static linking, layer caching, minimal runtime

**Official practices kept:**
- Multi-stage build (builder + runtime)
- `go mod download` for dependency caching
- `go run build/ci.go install -static` for building
- Alpine Linux runtime base
- Metadata labels (commit, version, buildnum)
- Non-root user execution

### Nethermind (`Dockerfile.nmx`)
**Based on:** `nethermind/nethermind` official Dockerfile

**Key adaptations:**
- Uses .NET 9 SDK (matching XDC fork branch)
- Alpine-based images for smaller size
- Clones from XDC fork repository
- Maintains locked-mode restore

**Official practices kept:**
- Multi-stage build with SDK + ASP.NET runtime
- `dotnet restore --locked-mode`
- `dotnet publish --no-self-contained`
- Architecture detection (`x64` vs `arm64`)
- Volume declarations for keystore, logs, nethermind_db
- Non-root user with specific UID
- Proper layer caching

### Erigon (`Dockerfile.erix`)
**Based on:** `erigontech/erigon` official Dockerfile

**Key adaptations:**
- Uses `golang:1.22-alpine` (matching XDC fork)
- Clones from XDC fork repository
- Simplified build without Silkworm support
- Alpine runtime instead of Debian (smaller image)

**Official practices kept:**
- Uses `tonistiigi/xx` for cross-compilation
- `xx-go` for architecture-specific builds
- `STOPSIGNAL SIGINT` for graceful shutdown
- Specific UID/GID (1000) for user
- `VOLUME` declaration for data directory
- Comprehensive OCI labels
- Multi-architecture support (AMD64v1, AMD64v2, ARM64)
- Build flags for optimization

## Supported Platforms

- **Linux** (amd64, arm64)
- **macOS** (Intel/AMD64, Apple Silicon/ARM64)
- **Windows** (WSL2, Docker Desktop)

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

| Client | HTTP RPC | WebSocket |
|--------|----------|-----------|
| Geth (gx) | http://localhost:8545 | ws://localhost:8546 |
| Nethermind (nmx) | http://localhost:8557 | ws://localhost:8558 |
| Erigon (erix) | http://localhost:8555 | ws://localhost:8556 |

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

## Security Features

All images implement security best practices from official images:
- Non-root users (UID 1000)
- Minimal base images (Alpine Linux)
- Static binary compilation where applicable
- Proper signal handling (SIGINT for graceful shutdown)
- Volume declarations for sensitive data
- No unnecessary packages

## Build Arguments

Each Dockerfile accepts build arguments for flexibility:

| Argument | Description | Default |
|----------|-------------|---------|
| `GIT_BRANCH` | Git branch to clone | `feature/xdpos-consensus` (gx), `build/xdc-unified` (nmx), `feature/xdc-network` (erix) |
| `GIT_REPO` | Git repository URL | XDC fork URLs |
| `TARGETARCH` | Target architecture | Auto-detected |
| `UID_ERIGON` / `GID_ERIGON` | User/Group IDs | 1000 |

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

## Troubleshooting

### Build fails on ARM (Apple Silicon)
```bash
# Use buildx for cross-platform builds
docker buildx create --name xdc-builder --use
docker buildx build --platform linux/arm64 -t anilchinchawale/gx:stable -f Dockerfile.gx .
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

See individual repository licenses for each client:
- Geth: GPL-3.0
- Nethermind: LGPL-3.0
- Erigon: LGPL-3.0

## References

- Official Geth Docker: https://hub.docker.com/r/ethereum/client-go
- Official Nethermind Docker: https://hub.docker.com/r/nethermind/nethermind
- Official Erigon Docker: https://hub.docker.com/r/erigontech/erigon
