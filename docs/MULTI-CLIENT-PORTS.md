# Multi-Client Port Allocation Guide

## Problem

Running multiple XDC clients (Geth, Erigon, Nethermind, Reth) on the same machine causes P2P port conflicts because all clients default to port 30303.

## Port Allocation Strategy

### Reserved Ports by Client

| Client | P2P Port | RPC HTTP | RPC WS | Metrics |
|--------|----------|----------|--------|---------|
| **XDC Geth Stable** | 30303 | 8545 | 8546 | 6060 |
| **XDC Geth PR5** | 30304 | 8547 | 8548 | 6061 |
| **Erigon XDC** | 30305 | 8549 | 8550 | 6062 |
| **Nethermind XDC** | 30306 | 8551 | 8552 | 6063 |
| **Reth XDC** | 30307 | 8553 | 8554 | 6064 |

### Docker Compose Example

```yaml
version: '3.8'

services:
  xdc-geth-stable:
    image: xinfinorg/xdposchain:v2.6.8
    ports:
      - "30303:30303"  # P2P
      - "8545:8545"    # RPC
      - "8546:8546"    # WS
      - "6060:6060"    # Metrics
    command: --port 30303 --rpc --rpcport 8545
    
  xdc-geth-pr5:
    image: xinfinorg/xdposchain:feature-pr5
    ports:
      - "30304:30303"
      - "8547:8545"
      - "8548:8546"
      - "6061:6060"
    command: --port 30303 --rpc --rpcport 8545
    
  xdc-erigon:
    build: ./docker/erigon
    ports:
      - "30305:30303"
      - "8549:8545"
      - "8550:8546"
      - "6062:6060"
    command: --port 30303 --http.port 8545
    
  xdc-nethermind:
    build: ./docker/nethermind
    ports:
      - "30306:30306"
      - "8551:8545"
      - "8552:8546"
      - "6063:6060"
    command: --Network.DiscoveryPort 30306 --JsonRpc.Port 8545
    
  xdc-reth:
    build: ./docker/reth
    ports:
      - "30307:30303"
      - "8553:8545"
      - "8554:8546"
      - "6064:6060"
    command: --port 30303 --http.port 8545
```

## SkyOne Agent Port Configuration

When running multiple clients, configure SkyOne agents to use the correct ports:

```bash
# SkyOne agent ports by client
export GETH_STABLE_PORT=7070
export GETH_PR5_PORT=7071
export ERIGON_PORT=7072
export NETHERMIND_PORT=7073
export RETH_PORT=7074
```

## Firewall Configuration

If using UFW, allow all client P2P ports:

```bash
sudo ufw allow 30303:30307/tcp comment "XDC Multi-Client P2P"
sudo ufw allow 30303:30307/udp comment "XDC Multi-Client Discovery"
```

## Verification

Check for port conflicts:

```bash
# Check listening ports
sudo netstat -tulpn | grep -E ":(30303|30304|30305|30306|30307|8545|8547|8549|8551|8553)"

# Test peer connectivity
curl -s http://localhost:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
  
curl -s http://localhost:8547 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
```

## Troubleshooting

### Port Already in Use

```bash
# Find process using port
sudo lsof -i :30303

# Kill conflicting process
sudo kill -9 <PID>
```

### Peers Not Connecting

1. Check firewall allows P2P ports
2. Verify NAT/port forwarding configured
3. Check bootnodes configuration
4. Ensure unique node IDs (delete nodekey if needed)

## References

- XDC Network Bootnodes: [XDC Master Node List](https://xdcchain.network/nodes)
- Docker Networking: [Docker Network Documentation](https://docs.docker.com/network/)
