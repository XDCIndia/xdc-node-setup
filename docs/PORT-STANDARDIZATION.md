# XDC Multi-Client Port Configuration Guide

## Issue #502: Standardize Port Configuration and Document P2P Compatibility

This document provides standardized port allocation and P2P protocol compatibility information for running multiple XDC clients simultaneously.

## Port Standardization

### Standard Port Allocation Matrix

| Client | RPC Port | WebSocket Port | P2P Port | Protocol Version |
|--------|----------|----------------|----------|------------------|
| XDC Geth | 8545 | 8546 | 30303 | eth/63 |
| Erigon | 8547 | 8548 | 30304 | eth/63 |
| Nethermind | 8558 | 8559 | 30306 | eth/100 |
| Reth | 7073 | 7074 | 40303 | eth/100 |

### Port Allocation Rationale

1. **RPC Ports (8545, 8547, 8558, 7073)**: Each client gets a unique RPC port to prevent conflicts
2. **WebSocket Ports (8546, 8548, 8559, 7074)**: Separate from RPC for clean separation
3. **P2P Ports (30303, 30304, 30306, 40303)**: Unique P2P ports allow all clients to participate in network

## P2P Protocol Compatibility

### ⚠️ CRITICAL: Erigon Port 30311 (eth/68) is NOT Compatible

**DO NOT use port 30311 for Erigon when connecting to XDC Network.**

Port 30311 uses the `eth/68` protocol which is **not compatible** with XDC Network. XDC uses:
- `eth/63` for XDC Geth and Erigon
- `eth/100` for XDC-specific protocol (Nethermind, Reth)

### Protocol Compatibility Matrix

| Port | Protocol | XDC Compatible | Notes |
|------|----------|----------------|-------|
| 30303 | eth/63 | ✅ Yes | XDC Geth default |
| 30304 | eth/63 | ✅ Yes | Erigon eth/63 compatible |
| 30306 | eth/100 | ✅ Yes | Nethermind XDC protocol |
| 40303 | eth/100 | ✅ Yes | Reth XDC protocol |
| 30311 | eth/68 | ❌ **NO** | Erigon eth/68 - **INCOMPATIBLE** |

## Docker Compose Examples

### Multi-Client Setup (All Clients)

```yaml
version: '3.8'

services:
  # XDC Geth (Primary)
  xdc-geth:
    image: xinfinorg/xdposchain:v2.6.8
    container_name: xdc-geth
    restart: unless-stopped
    ports:
      - "8545:8545"    # RPC
      - "8546:8546"    # WebSocket
      - "0.0.0.0:30303:30303"     # P2P TCP (eth/63)
      - "0.0.0.0:30303:30303/udp" # P2P UDP
    volumes:
      - xdc-geth-data:/work/xdcchain
    # ... additional configuration

  # Erigon (Archive Node)
  xdc-erigon:
    image: xinfinorg/xdc-erigon:latest
    container_name: xdc-erigon
    restart: unless-stopped
    ports:
      - "8547:8547"    # RPC
      - "8548:8548"    # WebSocket
      - "0.0.0.0:30304:30304"     # P2P TCP (eth/63 - XDC compatible)
      - "0.0.0.0:30304:30304/udp" # P2P UDP
    # WARNING: Do NOT use port 30311 - it's eth/68 and NOT compatible with XDC!
    volumes:
      - xdc-erigon-data:/erigon-data
    # ... additional configuration

  # Nethermind
  xdc-nethermind:
    image: nethermind/nethermind:latest
    container_name: xdc-nethermind
    restart: unless-stopped
    ports:
      - "8558:8558"    # RPC
      - "8559:8559"    # WebSocket
      - "0.0.0.0:30306:30306"     # P2P TCP (eth/100)
      - "0.0.0.0:30306:30306/udp" # P2P UDP
    volumes:
      - xdc-nethermind-data:/nethermind-data
    # ... additional configuration

  # Reth
  xdc-reth:
    image: xinfinorg/xdc-reth:latest
    container_name: xdc-reth
    restart: unless-stopped
    ports:
      - "7073:7073"    # RPC
      - "7074:7074"    # WebSocket
      - "0.0.0.0:40303:40303"     # P2P TCP (eth/100)
      - "0.0.0.0:40303:40303/udp" # P2P UDP
    volumes:
      - xdc-reth-data:/reth-data
    # ... additional configuration

volumes:
  xdc-geth-data:
  xdc-erigon-data:
  xdc-nethermind-data:
  xdc-reth-data:
```

### Single Client Examples

#### XDC Geth

```yaml
services:
  xdc-geth:
    image: xinfinorg/xdposchain:v2.6.8
    ports:
      - "8545:8545"    # RPC
      - "8546:8546"    # WebSocket
      - "0.0.0.0:30303:30303"
      - "0.0.0.0:30303:30303/udp"
```

#### Erigon (Correct Configuration)

```yaml
services:
  xdc-erigon:
    image: xinfinorg/xdc-erigon:latest
    ports:
      - "8547:8547"    # RPC
      - "8548:8548"    # WebSocket
      - "0.0.0.0:30304:30304"     # eth/63 - XDC compatible
      - "0.0.0.0:30304:30304/udp"
    # IMPORTANT: Do NOT expose port 30311
```

## Port Validation Tool

Use the provided validation script to check your configuration:

```bash
# Show port allocation matrix
./scripts/validate-ports.sh matrix

# Show protocol compatibility
./scripts/validate-ports.sh protocols

# Validate docker-compose file
./scripts/validate-ports.sh validate docker-compose.yml

# Generate configuration for a specific client
./scripts/validate-ports.sh generate erigon

# Validate P2P port for client
./scripts/validate-ports.sh validate-p2p erigon 30304

# Check system port availability
./scripts/validate-ports.sh check
```

## Troubleshooting

### Cannot Connect to Peers

1. **Check P2P Protocol Version**
   ```bash
   # For Geth/Erigon, verify eth/63
   curl -X POST http://localhost:8545 \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}'
   ```

2. **Verify Port Bindings**
   ```bash
   # Check if P2P ports are listening
   sudo ss -tulnp | grep -E "30303|30304|30306|40303"
   ```

3. **Check Firewall Rules**
   ```bash
   # Allow P2P ports through firewall
   sudo ufw allow 30303/tcp
   sudo ufw allow 30303/udp
   sudo ufw allow 30304/tcp
   sudo ufw allow 30304/udp
   ```

### Erigon Peering Issues

If Erigon cannot peer with XDC Network:

1. **Verify NOT using port 30311**
   ```bash
   # Check docker-compose for incorrect port
   grep -n "30311" docker-compose.yml
   ```

2. **Check protocol version**
   ```bash
   # Should show eth/63, not eth/68
   curl -s http://localhost:8547 \
     -X POST -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' | jq '.result.protocols.eth'
   ```

3. **Review Erigon configuration**
   - Ensure `--chain xdc` or `--chain xdc-testnet` is set
   - Verify bootnodes are correctly configured

### Port Conflicts

If you see "port already in use" errors:

```bash
# Find process using the port
sudo lsof -i :30303
# or
sudo ss -tulnp | grep 30303

# Kill the process or use different ports
```

## Environment Variables

Standardize client configuration using environment variables:

```bash
# XDC Geth
GETH_RPC_PORT=8545
GETH_WS_PORT=8546
GETH_P2P_PORT=30303

# Erigon
ERIGON_RPC_PORT=8547
ERIGON_WS_PORT=8548
ERIGON_P2P_PORT=30304

# Nethermind
NETHERMIND_RPC_PORT=8558
NETHERMIND_WS_PORT=8559
NETHERMIND_P2P_PORT=30306

# Reth
RETH_RPC_PORT=7073
RETH_WS_PORT=7074
RETH_P2P_PORT=40303
```

## References

- [Issue #502](https://github.com/AnilChinchawale/xdc-node-setup/issues/502) - Original issue
- [Ethereum Protocols](https://github.com/ethereum/devp2p/blob/master/caps/eth.md) - eth protocol specifications
- [XDC Documentation](https://docs.xdc.network) - Official XDC documentation
