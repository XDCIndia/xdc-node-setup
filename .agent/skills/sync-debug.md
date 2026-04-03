# Skill: Sync Debugging

How to diagnose and fix sync issues per XDC client.

## Quick Triage

First, determine the type of stall:

```bash
# Is the block advancing?
watch -n 5 'curl -s http://localhost:8545 \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"id\":1}" \
  | jq -r .result | xargs printf "%d\n" 2>/dev/null || echo "RPC down"'

# Is the node syncing or at head?
curl -s http://localhost:8545 \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","id":1}' | jq .result
# false = at head; object = syncing (shows currentBlock, highestBlock)

# How many peers?
curl -s http://localhost:8545 \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","id":1}' | jq -r '.result | tonumber'
```

## Geth/XDC Sync Debugging

### Common Errors in Logs

```
# State root mismatch
"Bad block: state root mismatch"
→ Add block to bad block list: --badBlockHash=<hash>
→ Delete chaindata/bad-blocks/ and restart

# Peer ban
"Dropping connection to peer"
→ Usually temporary; add bootnodes

# Disk space
"level db: write: no space left"
→ Clean up: docker system prune -f
→ Add disk or enable pruning

# Database corruption
"corrupted db"
→ Requires full resync from snapshot
```

### Geth Diagnostic Commands

```bash
# Check sync progress
curl -s http://localhost:8545 \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","id":1}' | jq .

# List peers
curl -s http://localhost:8545 \
  -d '{"jsonrpc":"2.0","method":"admin_peers","id":1}' | jq '.[].network.remoteAddress'

# Add bootnode
curl -s http://localhost:8545 \
  -d '{"jsonrpc":"2.0","method":"admin_addPeer","params":["enode://..."],"id":1}' | jq .

# Check node info
curl -s http://localhost:8545 \
  -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","id":1}' | jq .enode

# pprof heap (if --pprof enabled)
curl -s http://localhost:6060/debug/pprof/heap > heap.pprof
go tool pprof heap.pprof
```

### Geth Restart Sequence for Stuck Sync

```bash
docker stop xdc-geth
sleep 5
# Clear bad blocks if state root issue
docker run --rm -v /data/geth:/data alpine sh -c "rm -rf /data/geth/bad-blocks"
docker start xdc-geth
# Watch logs
docker logs -f xdc-geth 2>&1 | grep -v "^$"
```

## Erigon Sync Debugging

### Erigon Staged Sync

Erigon syncs in stages. Stalls happen at a specific stage:

```
Stages (in order):
  Headers → BlockHashes → Bodies → Senders → Execution → 
  Translation → HashState → IntermediateHashes → 
  AccountHistoryIndex → StorageHistoryIndex → LogIndex → 
  CallTraces → TxLookup → TxPool → Finish
```

To check which stage is stuck:

```bash
docker logs xdc-erigon 2>&1 | grep -i "stage\|stuck\|progress" | tail -20
```

### Common Erigon Errors

```
# Execution stage stuck
"[STAGED_SYNC] Execution stage"
→ Usually resource contention; check CPU/RAM

# State root mismatch (different from geth)
"wrong state root"
→ Erigon sometimes diverges at epoch blocks
→ Use --state.root.bypass.list flag (see state-root.md)

# mdbx database lock
"cannot open database"
→ Another process holds the lock
→ Kill all erigon processes, remove /data/erigon/mdbx.lck

# Download timeout
"download timeout"
→ P2P issues; add more peers
```

### Erigon Diagnostic Commands

```bash
# Erigon RPC is on 8547 (not 8545!)
PORT=8547

# Block number
curl -s http://localhost:${PORT} \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}' | jq -r '.result | tonumber'

# Syncing status (shows current stage)
curl -s http://localhost:${PORT} \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","id":1}' | jq .

# Check mdbx.dat size (chaindata growth)
du -sh /data/erigon/chaindata/mdbx.dat
```

### Erigon Restart for Stall

```bash
docker stop xdc-erigon
sleep 10  # Erigon needs longer to flush mdbx
docker start xdc-erigon
docker logs -f xdc-erigon 2>&1 | grep -E "(stage|error|warn)" | head -20
```

## Nethermind Sync Debugging

### Common Nethermind Errors

```
# Peer discovery
"No peers found"
→ Check --Discovery.Bootnodes in config

# State sync
"Trie node missing"
→ Usually heals itself; if persists, needs resync

# JSON config error
"Invalid configuration"
→ Validate configs/nethermind-mainnet.json with jq
```

### Nethermind Diagnostic Commands

```bash
PORT=8548

# Health endpoint
curl -s http://localhost:${PORT}/health | jq .

# Sync progress
curl -s http://localhost:${PORT} \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","id":1}' | jq .

# Validate config
jq . configs/nethermind-mainnet.json
```

## General Sync Recovery Steps

1. **Check peers first** — If 0 peers, no amount of restarts will help. Fix P2P first.
2. **Check disk** — If > 95% full, sync will fail. Free space or add disk.
3. **Check RAM** — Erigon needs ≥16GB. Geth needs ≥8GB.
4. **Restart the container** — Often fixes transient stalls.
5. **Add bootnodes** — If persistent peer issue. See peer-management.md.
6. **Check for known bad blocks** — See state-root.md if state root mismatch.
7. **Resync from snapshot** — Last resort. Takes hours but is clean.

## Resync from Snapshot

```bash
# Stop client
docker stop xdc-geth

# Backup current data (optional, if disk allows)
mv /data/geth /data/geth-backup-$(date +%Y%m%d)

# Download latest snapshot (see configs/snapshots.json)
mkdir -p /data/geth
cd /data/geth
wget -c "$(jq -r '.geth.mainnet.url' configs/snapshots.json)"
tar -xzf *.tar.gz

# Start client
docker start xdc-geth
```
