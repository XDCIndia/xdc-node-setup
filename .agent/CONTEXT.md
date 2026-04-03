# Technical Context — XDC Node Setup

Key facts for AI agents working with this repository. Read this before making changes.

## Network Overview

| Network | Chain ID | Block Time | Consensus |
|---------|----------|------------|-----------|
| Mainnet | 50       | ~2s        | XDPoS v2  |
| Apothem | 51       | ~2s        | XDPoS v2  |
| Devnet  | varies   | ~2s        | XDPoS v1/v2 |

## XDPoS Consensus

- **XDPoS v1**: Original delegated proof-of-stake, simpler but less fork-resistant
- **XDPoS v2**: HotStuff-based BFT, 2/3+1 quorum of 108 validators, epoch-based
- **Epoch size**: 900 blocks (mainnet), adjustable on testnet
- **Epoch switch block**: The last block of an epoch runs extra state transitions — all clients must handle this identically
- **Validators**: 108 masternodes; changing requires governance transaction

## Client Port Assignments

### Mainnet

| Client     | RPC    | WS     | P2P   | AuthRPC | Metrics | SkyOne |
|------------|--------|--------|-------|---------|---------|--------|
| geth/XDC   | 8545   | 8549   | 30303 | 8560    | 6060    | 7060   |
| Erigon     | 8547   | 8548   | 30305 | 8551    | 6062    | 7062   |
| Nethermind | 8548   | 8553   | 30304 | 8552    | 6063    | 7063   |
| Reth       | 8588   | —      | 30306 | 8589    | 6064    | 7064   |

### Apothem (Testnet) — Mainnet port + 100/10

| Client     | RPC    | WS     | P2P   |
|------------|--------|--------|-------|
| geth/XDC   | 8645   | 8649   | 30313 |
| Erigon     | 8647   | 8648   | 30315 |
| Nethermind | 8648   | 8653   | 30314 |
| Reth       | 8688   | —      | 30316 |

### SkyOne Dashboard

- **Port 7070** — Geth XDC (mainnet default in some deployments)
- **Port 7071** — Erigon XDC
- **Port 7072** — Nethermind XDC
- **Port 8588/8589** — Reth RPC/WS

## Known Quirks & Gotchas

### Erigon

- Erigon uses a **staged sync** model — stages can stall independently
- **State root mismatches** between geth and Erigon are often due to `Snapshots` stage running slightly behind
- Erigon's RPC port is on 8547, **not** 8545 — easy mistake
- Erigon does not support `admin_addPeer` in the same way as geth; use `--staticpeers` config instead
- OOM crashes during initial sync are common — needs ≥16GB RAM for full node

### Nethermind

- Uses `--JsonRpc.Port` not `--http.port`
- Config is JSON-based (`configs/nethermind-mainnet.json`) not flags
- **Pruning mode** must be configured at genesis — cannot be changed after sync
- Nethermind has its own peer discovery mechanism; fewer XDC bootnodes support it

### Geth/XDC (go-ethereum fork)

- Branch: `feature/xdpos-consensus` in `go-xdc` repo
- Supports `admin_addPeer` and `admin_peers` RPC
- `--unlock` and `--password` flags needed for validator nodes
- `--gcmode archive` required for full state history

### Reth

- Experimental — not production-ready for XDC mainnet
- Does not support XDPoS v1 blocks (mainnet has v1 history)
- RPC on 8588 (non-standard) to avoid conflicts

## Bootnodes

Mainnet bootnodes: `configs/bootnodes-mainnet.json`
Apothem bootnodes: `configs/bootnodes-testnet.json`

Key mainnet bootnodes (enode format):
- Always prefer bootnodes with high uptime (see `scripts/bootnode-optimize.sh`)
- If a node has 0 peers, add 3-5 bootnodes via `admin_addPeer`

## Docker Compose Layout

```
docker/
  mainnet/
    geth/docker-compose.yml
    erigon/docker-compose.yml
    nethermind/docker-compose.yml
  apothem/
    ...
```

Container naming convention: `xdc-{client}[-{network}]`
- `xdc-geth` (mainnet geth)
- `xdc-erigon-apothem` (apothem erigon)

## Data Directories

Runtime data is stored in `/data/{client}/` on the host (mounted into containers).

```
/data/geth/         → geth chaindata
/data/erigon/       → erigon chaindata + mdbx.dat
/data/nethermind/   → nethermind db
/data/reth/         → reth db
```

## Monitoring

- **Prometheus**: port 9090
- **Grafana**: port 3000 (default password: configured in env)
- **Alertmanager**: port 9093
- Metrics exposed by clients on their respective metrics ports

## Common Failure Modes

1. **Block stall** — Most common. Usually caused by bad peer connections or state root issue.
2. **OOM on Erigon** — Happens during initial sync or after state updates on low-RAM nodes.
3. **P2P isolation** — Node has 0 peers; usually NAT/firewall issue or no bootnodes.
4. **Epoch transition crash** — Some clients crash at epoch switch blocks; fix is a patch + restart.
5. **State root mismatch** — Block hash differs between clients; requires investigation.
6. **Disk full** — Chaindata grows ~10-15GB/month; need pruning or larger disk.

## Security Notes

- **NEVER** expose port 8545/8547/8548 to the internet without auth
- **NEVER** run `--unlock` with `--http.addr 0.0.0.0`
- JWT secrets for AuthRPC live in `/data/{client}/jwt.hex`
- All secrets should be in `/root/.secrets/` on the host, not in the repo

## Useful RPC Calls

```bash
# Block height
curl -s http://localhost:8545 -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}' | jq .result

# Peer count
curl -s http://localhost:8545 -d '{"jsonrpc":"2.0","method":"net_peerCount","id":1}' | jq .result

# Syncing status
curl -s http://localhost:8545 -d '{"jsonrpc":"2.0","method":"eth_syncing","id":1}' | jq .result

# Add peer
curl -s http://localhost:8545 -d '{"jsonrpc":"2.0","method":"admin_addPeer","params":["enode://..."],"id":1}' | jq .
```
