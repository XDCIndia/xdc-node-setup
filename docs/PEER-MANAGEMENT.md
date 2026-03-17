# Peer Management Guide

## Issue #549: static-nodes.json Deprecation

As of Geth 1.17+, `static-nodes.json` generates startup warnings. The preferred methods are:

### 1. Bootnodes (Recommended)
```bash
# In start script or docker-compose
--bootnodes "enode://...@ip:port,enode://...@ip:port"
```

### 2. Admin RPC (Runtime)
```bash
# Add trusted peer (won't be disconnected)
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"admin_addTrustedPeer","params":["enode://..."],"id":1}'

# Add regular peer
curl -X POST http://localhost:8545 \
  -d '{"jsonrpc":"2.0","method":"admin_addPeer","params":["enode://..."],"id":1}'
```

### 3. Static Nodes File (Legacy)
Still works but generates warnings. Use `--bootnodes` flag instead.

## Issue #550: Cross-Client Peer Compatibility

| Source Client | GP5 | Erigon | Nethermind | Reth |
|---------------|-----|--------|------------|------|
| **GP5** | ✅ | ⚠️ Invalid ancestor | ⚠️ Different state roots | ❌ ECIES fail |
| **Erigon** | ✅ (eth/62,63) | ✅ | ✅ | ✅ |
| **Nethermind** | ✅ | ✅ | ✅ | ❌ |
| **Reth** | ❌ | ✅ | ❌ | ✅ |

### Key Rules
1. **GP5 → GP5 ONLY**: GP5 nodes should only peer with GP5 nodes
2. **Erigon is universal**: Can peer with all XDC clients
3. **Reth needs Erigon**: Use Erigon as bridge peer (ECIES incompatible with GP5)

### Generate Client-Specific Peers
```bash
# Generate peers for GP5 only
./scripts/generate-static-nodes.sh gp5

# Generate peers for Erigon
./scripts/generate-static-nodes.sh erigon
```
