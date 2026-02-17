# XDC Client Docker Images for Mac

Docker stable builds for XDC Network clients based on custom forks.

## Images

| Image | Client | Repository | Tag |
|-------|--------|------------|-----|
| `anilchinchawale/gx` | XDC Geth | https://github.com/AnilChinchawale/go-ethereum/tree/feature/xdpos-consensus | stable, latest |
| `anilchinchawale/nmx` | XDC Nethermind | https://github.com/AnilChinchawale/nethermind/tree/build/xdc-net9-stable | stable, latest |
| `anilchinchawale/erix` | XDC Erigon | https://github.com/AnilChinchawale/erigon-xdc/tree/feature/xdc-network | stable, latest |

## Quick Start

### 1. Build All Images

```bash
chmod +x build-all-xdc.sh
./build-all-xdc.sh
```

Or build individually:

```bash
# Geth
docker build -f Dockerfile.gx -t anilchinchawale/gx:stable .

# Nethermind
docker build -f Dockerfile.nmx -t anilchinchawale/nmx:stable .

# Erigon
docker build -f Dockerfile.erix -t anilchinchawale/erix:stable .
```

### 2. Run Individual Client

**Geth (gx):**
```bash
docker run -d \
  --name xdc-geth \
  -p 8545:8545 \
  -p 8546:8546 \
  -p 30303:30303 \
  -v $(pwd)/data/geth:/data/xdcchain \
  anilchinchawale/gx:stable \
  --networkid=51 \
  --http --http.addr=0.0.0.0 \
  --ws --ws.addr=0.0.0.0
```

**Nethermind (nmx):**
```bash
docker run -d \
  --name xdc-nethermind \
  -p 8557:8557 \
  -p 30305:30305 \
  -v $(pwd)/data/nethermind:/data/nethermind \
  anilchinchawale/nmx:stable \
  --config=/config/nethermind.json
```

**Erigon (erix):**
```bash
docker run -d \
  --name xdc-erigon \
  -p 8555:8555 \
  -p 30304:30304 \
  -v $(pwd)/data/erigon:/data/erigon \
  anilchinchawale/erix:stable \
  --chain=xdc-apothem \
  --networkid=51 \
  --http --http.addr=0.0.0.0
```

### 3. Run All Clients (Multi-Client)

```bash
docker-compose -f docker-compose.xdc-mac.yml up -d
```

### 4. Push to Registry

```bash
docker push anilchinchawale/gx:stable
docker push anilchinchawale/nmx:stable
docker push anilchinchawale/erix:stable
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

## Data Directories

```
data/
├── geth/         # Geth chain data
├── nethermind/   # Nethermind chain data
└── erigon/       # Erigon chain data
```

## Health Checks

All images include Docker health checks:
- Geth: Checks HTTP RPC endpoint
- Nethermind: Checks health endpoint
- Erigon: Checks HTTP RPC endpoint

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
# Individual
docker stop xdc-geth && docker rm xdc-geth

# All
docker-compose -f docker-compose.xdc-mac.yml down
```

## Notes

- Images are built for `linux/amd64` platform
- On Mac M1/M2, Docker will use Rosetta 2 or QEMU emulation
- All clients use non-root users for security
- Data is persisted in Docker volumes
