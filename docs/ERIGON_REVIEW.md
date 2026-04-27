# Erigon Client Integration Review

## Executive Summary

The XDC-Node-Setup repository has **partial erigon client support** with the basic infrastructure in place, but **critical gaps exist** that prevent end-to-end functionality for new installations.

## What's Implemented ✅

### 1. Client Selection Infrastructure
- `setup.sh` includes erigon as option 3 in the client selection prompt
- `cli/xdc` supports `--client erigon` flag for starting with erigon
- Client detection logic in status commands recognizes erigon via version string

### 2. Docker Configuration
- `docker/docker-compose.erigon.yml` - Compose override file for erigon
- `docker/erigon/Dockerfile` - Multi-stage build from golang:1.22-alpine
- `docker/docker-compose.erigon-apothem.yml` - Compose override file for erigon

### 3. Key Erigon-Specific Settings in docker-compose.erigon-apothem.yml:
```yaml
ports:
  - "${P2P_PORT:-30304}:30304"      # eth/63 (XDC compatible)
  - "${P2P_PORT_68:-30311}:30311"   # eth/68 (NOT XDC compatible)
  - "127.0.0.1:${RPC_PORT:-8547}:8547"  # HTTP-RPC
```

### 4. Start Script Configuration (start-erigon.sh)
- Uses `--chain=xdc` for XDC network
- Sets `--p2p.protocol=63,62` for XDC compatibility
- Enables `--discovery.xdc` for XDC-specific discovery
- Private API on port 9092

## Critical Issues Found 🔴

### Issue 1: Client Selection Not Used During Setup (CRITICAL)
**Location:** `setup.sh`, function `start_services()` (line ~1436)

**Problem:** The `start_services()` function does NOT use the `CLIENT` variable to select the appropriate docker compose file. It always runs:
```bash
docker compose up -d --remove-orphans
```

Instead of:
```bash
case "$CLIENT" in
    erigon) docker compose -f docker-compose.yml -f docker-compose.erigon-apothem.yml up -d ;;
    geth-pr5) docker compose -f docker-compose.yml -f docker-compose.geth-pr5.yml up -d ;;
    *) docker compose up -d ;;
esac
```

**Impact:** Even if user selects erigon during setup, the node starts with the default stable client.

### Issue 2: Path References in docker-compose.erigon-apothem.yml
**Problem:** The compose file references paths like:
```yaml
- ./mainnet/genesis.json:/genesis.json:ro
- ./mainnet/bootnodes.list:/bootnodes.list:ro
```

But these paths are relative and may not resolve correctly depending on the working directory.

### Issue 3: Missing Erigon-Specific Configuration in setup_docker_compose()
**Location:** `setup.sh`, function `setup_docker_compose()` (line ~1032)

**Problem:** This function always generates the default docker-compose.yml regardless of CLIENT setting. It doesn't generate or prepare the erigon-specific configuration.

### Issue 4: Port Configuration Inconsistency
**Problem:** The default P2P ports conflict between clients:
- Stable/geth-pr5: Port 30303 (single port)
- Erigon: Port 30304 (eth/63) + 30311 (eth/68)

The setup.sh uses P2P_PORT=30303 by default, which doesn't match erigon's default of 30304.

### Issue 5: Private API Port Mismatch
**Problem:** The start-erigon.sh sets `--private.api.addr=0.0.0.0:9092` but documentation mentions port 9091.

## Port Requirements Summary

| Port | Protocol | Purpose | XDC Compatible |
|------|----------|---------|----------------|
| 8547 | HTTP | RPC API | N/A |
| 8561 | HTTP | Auth RPC | N/A |
| 9091 | TCP | Private API | N/A |
| 30304 | TCP/UDP | P2P eth/63 | ✅ Yes |
| 30311 | TCP/UDP | P2P eth/68 | ❌ No |

## Connecting Erigon to Geth Nodes

When running erigon alongside geth nodes, you MUST:

1. **Use port 30304** for peer connections (eth/63 protocol)
2. **Add erigon as trusted peer** on geth nodes using `admin_addTrustedPeer`

Example:
```bash
# On geth node, add erigon as trusted peer
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "admin_addTrustedPeer",
    "params": ["enode://<erigon_node_id>@<erigon_ip>:30304"],
    "id": 1
  }'
```

**Note:** Port 30311 (eth/68) is NOT compatible with XDC geth nodes. Do not use it for peer connections.

## Recommendations

### Immediate Fixes Required:

1. **Fix start_services()** to use CLIENT variable for compose file selection
2. **Add erigon-specific setup** in setup_docker_compose() when CLIENT=erigon
3. **Document port differences** in README and setup prompts
4. **Add firewall rules** for both 30304 and 30311 in setup_security()

### Documentation Updates Needed:

1. Erigon-specific installation instructions
2. Port configuration table
3. Multi-client network setup guide
4. Troubleshooting section for erigon-specific issues

## Testing Checklist

Before marking erigon support as complete:

- [ ] Fresh install with `CLIENT=erigon` completes successfully
- [ ] Erigon container starts and syncs blocks
- [ ] RPC endpoint responds on port 8547
- [ ] P2P connections work on port 30304
- [ ] Cannot connect to port 30311 (expected - incompatible)
- [ ] Can connect to existing geth nodes using admin_addTrustedPeer on port 30304
- [ ] Switching clients via `xdc start --client erigon` works
- [ ] Status command correctly identifies erigon client

## Known Limitations

1. **Experimental Status**: Erigon-XDC is marked as experimental in the client selection
2. **Build Time**: Building from source takes 10-15 minutes
3. **Memory Requirements**: Erigon requires more RAM (8GB+ recommended vs 4GB for geth)
4. **Protocol Compatibility**: eth/68 port (30311) cannot peer with XDC geth nodes
5. **Snapshot Compatibility**: May not be compatible with geth snapshots
