# XDC Multi-Client Troubleshooting Guide

This guide covers common issues when running multiple XDC clients (GP5, Erigon, Nethermind, Reth) simultaneously.

## Table of Contents

1. [Genesis Issues](#genesis-issues)
2. [Sync Issues](#sync-issues)
3. [Port Conflicts](#port-conflicts)
4. [SkyNet Registration](#skynet-registration)
5. [Client-Specific Issues](#client-specific-issues)
6. [Known Limitations](#known-limitations)

---

## Genesis Issues

### Genesis Mismatch Error

**Symptoms:**
```
GENESIS MISMATCH DETECTED!
Genesis file chainId (51) does not match expected (50)
```

**Solution:**
1. Verify you're using the correct genesis file for your network
2. Set the correct `NETWORK` environment variable:
   ```bash
   export NETWORK=mainnet  # chainId 50
   # OR
   export NETWORK=apothem  # chainId 51
   ```
3. Re-initialize genesis:
   ```bash
   ./scripts/init-genesis.sh --network mainnet --force
   ```

### Chain ID Mismatch After Network Switch

**Symptoms:**
Node fails to start after switching from apothem to mainnet (or vice versa).

**Solution:**
Enable auto-wipe and restart:
```bash
export GENESIS_GUARD_AUTO_WIPE=true
docker-compose -f docker-compose.multi-client.yml restart xdc-gp5
```

Or manually wipe chaindata:
```bash
rm -rf ./data/gp5/XDC/chaindata
rm -rf ./data/gp5/XDC/nodes
./scripts/init-genesis.sh --network mainnet --client gp5
```

---

## Sync Issues

### Node Stuck at Block 0

**Symptoms:**
- Node stays at block 0 for extended time
- No peers connecting

**Diagnosis:**
```bash
# Check peer count
curl -X POST http://localhost:7070 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
```

**Solutions:**
1. Check firewall allows P2P ports:
   ```bash
   sudo ufw allow 30303/tcp
   sudo ufw allow 30303/udp
   sudo ufw allow 30304/tcp  # Erigon
   sudo ufw allow 30304/udp
   ```

2. Verify bootnodes are configured:
   ```bash
   cat docker/mainnet/bootnodes.list
   ```

3. Add static peers:
   ```bash
   # GP5
   curl -X POST http://localhost:7070 \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"admin_addPeer","params":["enode://..."],"id":1}'
   ```

### Sync Progress Stopped

**Symptoms:**
- Block number not increasing
- Node was syncing but stopped

**Diagnosis:**
```bash
# Check sync status
curl -X POST http://localhost:7070 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
```

**Solutions:**
1. Restart the client:
   ```bash
   docker-compose -f docker-compose.multi-client.yml restart xdc-gp5
   ```

2. Check disk space:
   ```bash
   df -h ./data/
   ```

3. Increase max peers:
   ```bash
   export MAX_PEERS=100
   docker-compose -f docker-compose.multi-client.yml up -d
   ```

---

## Port Conflicts

### Multi-Client Port Allocation

| Client | RPC | WS | P2P | Metrics |
|--------|-----|-----|-----|---------|
| GP5 | 7070 | 7071 | 30303 | 6070 |
| Erigon | 7072 | 7073 | 30304 | 6071 |
| Nethermind | 7074 | 7075 | 30306 | 6072 |
| Reth | 8588 | 8589 | 40303 | 6073 |

### Port Already in Use

**Symptoms:**
```
Error starting userland proxy: listen tcp 0.0.0.0:7070: bind: address already in use
```

**Solution:**
1. Find the process:
   ```bash
   sudo lsof -i :7070
   ```

2. Stop conflicting service or change port:
   ```bash
   # In .env file
   GP5_RPC_PORT=7080
   ```

---

## SkyNet Registration

### Registration Failed

**Symptoms:**
```
SkyOne: Node not responding at http://localhost:7070
```

**Solutions:**
1. Wait for node to fully start (30-60 seconds)
2. Check RPC is enabled and accessible
3. Verify SKYNET_ENABLED is true:
   ```bash
   export SKYNET_ENABLED=true
   ```

### Check Registration Status

```bash
./scripts/skyone-register.sh status
```

Expected output:
```
[SkyOne] gp5: block=12345678 peers=25 status=synced
[SkyOne] erigon: block=12345670 peers=18 status=syncing
[SkyOne] nethermind: block=12345650 peers=12 status=syncing
[SkyOne] reth: not responding
```

---

## Client-Specific Issues

### GP5 (Geth PR5)

**Issue:** `XDPoS consensus not found`
- Ensure using correct image: `xinfinorg/xdposchain:pr5-latest`

**Issue:** `Store reward db not enabled`
- Add `--store-reward` flag if using legacy RPC style

### Erigon

**Issue:** `Sentry handshake failed`
- This is normal during initial sync, wait for peers

**Issue:** Very slow initial sync
- Erigon uses staged sync, initial stages take longer
- Expected: 2-3 days for full sync

### Nethermind

**Issue:** `ChainSpec not found`
- Ensure genesis is copied to `/xdcchain/chainspec/xdc.json`

**Issue:** `Discovery failed`
- Check P2P port 30306 is open

### Reth

**Issue:** `Chain not supported`
- Reth XDC support is experimental
- Ensure using XDC-specific Reth build

---

## Known Limitations

### 1. Cross-Client Peer Discovery
- Clients may not discover each other directly
- Use common bootnodes for all clients

### 2. State Root Divergence
- During active development, state roots may diverge between clients
- This is expected and being actively fixed

### 3. XDPoS 2.0 Consensus
- Only GP5 fully supports XDPoS 2.0
- Erigon/Nethermind may lag on consensus upgrades

### 4. Snapshot Sync
- Only GP5 supports snapshot sync
- Erigon/Nethermind use full sync only

### 5. Memory Requirements

| Client | Minimum RAM | Recommended |
|--------|-------------|-------------|
| GP5 | 4 GB | 8 GB |
| Erigon | 8 GB | 16 GB |
| Nethermind | 8 GB | 16 GB |
| Reth | 8 GB | 16 GB |
| **All 4** | 24 GB | 64 GB |

### 6. Disk Requirements

| Network | GP5 | Erigon | Nethermind |
|---------|-----|--------|------------|
| Mainnet | ~200 GB | ~150 GB | ~250 GB |
| Apothem | ~50 GB | ~40 GB | ~60 GB |

---

## Getting Help

1. **GitHub Issues:** https://github.com/AnilChinchawale/xdc-node-setup/issues
2. **XDC Discord:** https://discord.gg/xdc
3. **SkyNet Dashboard:** https://net.xdc.network

When reporting issues, include:
- Client name and version
- Network (mainnet/apothem)
- Docker compose logs: `docker-compose logs xdc-<client>`
- Block number and peer count
