# Fullnode Deployment Guide

## Issue #516: xinfinorg/xdposchain:v2.6.8 requires PRIVATE_KEY env or custom entrypoint for fullnode operation

### Problem

When running `xinfinorg/xdposchain:v2.6.8` as a fullnode (without masternode key), the container exits with:
```
NETWORK env Must be set, mainnet/testnet/devnet/local
```
or when NETWORK is set:
```
PRIVATE_KEY environment variable has not been set.
```

The image entrypoint script requires `PRIVATE_KEY` for masternode operation. Running as fullnode requires bypassing the entrypoint or using a custom entrypoint.

### Solutions

#### Solution 1: Use the New Fullnode Entrypoint (Recommended)

We provide a new entrypoint script that automatically detects fullnode vs masternode mode:

```yaml
services:
  xdc-fullnode:
    image: xinfinorg/xdposchain:v2.6.8
    container_name: xdc-fullnode
    volumes:
      - xdc-data:/work/xdcchain
      - ./docker/xdc-fullnode-entrypoint.sh:/entrypoint-fullnode.sh:ro
    entrypoint: ["/entrypoint-fullnode.sh"]
    environment:
      - NETWORK=mainnet  # or apothem/devnet
      - RPC_ENABLED=true
      - RPC_ADDR=0.0.0.0
      - P2P_PORT=30303
```

#### Solution 2: Direct Binary Entrypoint (Quick Fix)

Use the `--entrypoint` flag to bypass the wrapper script:

```yaml
# For Apothem Testnet
services:
  xdc-apothem:
    image: xinfinorg/xdposchain:v2.6.8
    entrypoint: ["/usr/bin/XDC-testnet"]
    command:
      - --datadir=/work/xdcchain
      - --networkid=51
      - --apothem
      - --port=30303
      - --rpc
      - --rpcaddr=0.0.0.0
      - --rpcport=8545

# For Mainnet
services:
  xdc-mainnet:
    image: xinfinorg/xdposchain:v2.6.8
    entrypoint: ["/usr/bin/XDC"]
    command:
      - --datadir=/work/xdcchain
      - --networkid=50
      - --port=30303
      - --rpc
      - --rpcaddr=0.0.0.0
      - --rpcport=8545
```

#### Solution 3: Shell Command Entrypoint

Use a shell command to dynamically select the binary:

```yaml
services:
  xdc-node:
    image: xinfinorg/xdposchain:v2.6.8
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        BIN=$(which XDC-testnet 2>/dev/null || which XDC 2>/dev/null || echo "/usr/bin/XDC")
        exec $BIN \
          --datadir /work/xdcchain \
          --networkid 51 \
          --apothem \
          --port 30303 \
          --rpc --rpcaddr 0.0.0.0
```

### Environment Variables

When using the fullnode entrypoint, the following environment variables are supported:

| Variable | Default | Description |
|----------|---------|-------------|
| `NETWORK` | (required) | Network to connect to: `mainnet`, `testnet`/`apothem`, or `devnet` |
| `DATA_DIR` | `/work/xdcchain` | Data directory path |
| `RPC_ENABLED` | `true` | Enable RPC server |
| `RPC_ADDR` | `127.0.0.1` | RPC listen address (use `0.0.0.0` for Docker) |
| `RPC_PORT` | `8545` | RPC listen port |
| `RPC_VHOSTS` | `localhost` | Allowed RPC virtual hosts |
| `RPC_ALLOW_ORIGINS` | `localhost` | Allowed CORS origins |
| `RPC_API` | `eth,net,web3,XDPoS` | Enabled RPC APIs |
| `WS_ENABLED` | `false` | Enable WebSocket server |
| `WS_ADDR` | `127.0.0.1` | WebSocket listen address |
| `WS_PORT` | `8546` | WebSocket listen port |
| `P2P_PORT` | `30303` | P2P network port |
| `BOOTNODES` | (empty) | Comma-separated list of bootnodes |
| `SYNC_MODE` | `full` | Sync mode: `full`, `fast`, or `snap` |
| `GAS_PRICE` | `1` | Minimum gas price |
| `XDC_EXTRA_ARGS` | (empty) | Additional arguments passed to XDC binary |

### Network IDs

| Network | Network ID | Notes |
|---------|------------|-------|
| Mainnet | 50 | Production XDC Network |
| Apothem (Testnet) | 51 | XDC Testnet |
| Devnet | 551 | Development network |

### Binary Locations

Inside the `xinfinorg/xdposchain` container:

| Binary | Path | Network |
|--------|------|---------|
| XDC | `/usr/bin/XDC` | Mainnet |
| XDC-testnet | `/usr/bin/XDC-testnet` | Testnet/Apothem |

### Docker Compose Examples

#### Basic Fullnode (Mainnet)

```yaml
version: '3.8'

services:
  xdc-mainnet:
    image: xinfinorg/xdposchain:v2.6.8
    container_name: xdc-mainnet
    restart: unless-stopped
    ports:
      - "8545:8545"
      - "30303:30303"
      - "30303:30303/udp"
    volumes:
      - xdc-data:/work/xdcchain
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        exec /usr/bin/XDC \
          --datadir /work/xdcchain \
          --networkid 50 \
          --port 30303 \
          --rpc --rpcaddr 0.0.0.0 --rpcport 8545 \
          --rpccorsdomain "*" --rpcvhosts "*" \
          --rpcapi eth,net,web3,XDPoS \
          --syncmode full
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8545 -X POST -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' | grep -q result || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

volumes:
  xdc-data:
```

#### Fullnode with Custom Entrypoint

```yaml
version: '3.8'

services:
  xdc-fullnode:
    image: xinfinorg/xdposchain:v2.6.8
    container_name: xdc-fullnode
    restart: unless-stopped
    ports:
      - "8545:8545"
      - "30303:30303"
    volumes:
      - xdc-data:/work/xdcchain
      - ./docker/xdc-fullnode-entrypoint.sh:/entrypoint.sh:ro
    entrypoint: ["/entrypoint.sh"]
    environment:
      - NETWORK=mainnet
      - RPC_ENABLED=true
      - RPC_ADDR=0.0.0.0
      - P2P_PORT=30303
      - SYNC_MODE=full

volumes:
  xdc-data:
```

### Migration Guide

If you're currently using the masternode entrypoint and want to switch to fullnode mode:

1. **Backup your data directory** before making changes
2. Remove the `PRIVATE_KEY` environment variable
3. Update the `entrypoint` in your docker-compose.yml
4. Ensure `NETWORK` is set correctly
5. Restart the container

### Troubleshooting

#### Container exits immediately

Check logs: `docker logs xdc-container-name`

Common causes:
- Missing `NETWORK` environment variable
- Data directory permissions issues
- Port conflicts

#### Cannot connect to peers

- Verify bootnodes are correctly configured
- Check firewall rules for P2P port (default: 30303)
- Ensure NAT traversal is working: add `--nat extip:YOUR_PUBLIC_IP`

#### RPC not accessible

- Set `RPC_ADDR=0.0.0.0` (not `127.0.0.1`) for Docker
- Check port mapping in docker-compose.yml
- Verify RPC is enabled with `--rpc`

### Related Issues

- #516 - Original issue: Fullnode entrypoint requirements
- #517 - NM start.sh CLI arguments
- #514 - GP5 protocol compatibility
