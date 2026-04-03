# DevOps Runbook: XDC Bootstrap + GP5 Fast-Sync

> Deploy v2.6.8 (XDC) as bootstrap node, then GP5 (Geth) syncs from it locally.

## Prerequisites

- Server: 4+ cores, 16GB RAM, 500GB+ disk
- OS: Ubuntu 22.04 LTS
- Docker 24+ installed
- SSH access (port 12141)

## Architecture

```
┌──────────────────────────────────────────┐
│  Server: xdc01 (mainnet)                  │
│                                          │
│  ┌────────────────────────────────┐      │
│  │  xdc01-xdc-full-hbss-mainnet   │      │
│  │  (v2.6.8 bootstrap)            │      │
│  │  RPC:8550  P2P:30303           │      │
│  └──────────────┬─────────────────┘      │
│                 │ localhost               │
│  ┌──────────────▼─────────────────┐      │
│  │  xdc01-geth-full-pbss-mainnet   │      │
│  │  (GP5 fast-sync)               │      │
│  │  RPC:8545  P2P:30305           │      │
│  └────────────────────────────────┘      │
│                                          │
│  SkyOne agents auto-deployed for both    │
└──────────────────────────────────────────┘
```

## Naming Convention

Pattern: `{location}-{client}-{sync}-{scheme}-{network}-{server_id}`

| Field | Values |
|-------|--------|
| location | xdc01, xdc02, prod, test |
| client | **xdc** (v2.6.8), **geth** (GP5), erigon, nethermind, reth |
| sync | full, fast, snap |
| scheme | hbss (hash-based), pbss (path-based), archive |
| network | mainnet, apothem |
| server_id | last octet of IP |

## Server Assignment

| Server | IP | SSH | Role | Nodes |
|--------|-----|-----|------|-------|
| xdc01 | 95.217.112.125 | 12141 | **Mainnet** | xdc + geth |
| xdc02 | 135.181.117.109 | 12141 | **Testnet** | xdc + geth |

## Quick Start

### Mainnet (xdc01)

```bash
# 1. SSH into server
ssh -p 12141 root@95.217.112.125

# 2. Clone xdc-node-setup
git clone https://github.com/XDCIndia/xdc-node-setup.git
cd xdc-node-setup

# 3. Run bootstrap setup (auto-deploys v2.6.8 + GP5 + SkyOne)
chmod +x scripts/bootstrap-setup.sh scripts/deploy-skyone.sh
bash scripts/bootstrap-setup.sh --network mainnet

# 4. Check status
docker ps --format 'table {{.Names}}\t{{.Status}}'

# Expected output:
# xdc01-xdc-full-hbss-mainnet-125          Up 5 minutes
# xdc01-geth-full-pbss-mainnet-125         Up 2 minutes
# skyone-xdc01-xdc-full-hbss-mainnet-125   Up 2 minutes
# skyone-xdc01-geth-full-pbss-mainnet-125  Up 1 minute
```

### Testnet (xdc02)

```bash
# 1. SSH into server
ssh -p 12141 root@135.181.117.109

# 2. Clone and run
git clone https://github.com/XDCIndia/xdc-node-setup.git
cd xdc-node-setup
chmod +x scripts/bootstrap-setup.sh scripts/deploy-skyone.sh
bash scripts/bootstrap-setup.sh --network apothem

# Expected containers:
# xdc02-xdc-full-hbss-apothem-109
# xdc02-geth-full-pbss-apothem-109 (may fail — GP5 apothem genesis incompatible)
# skyone-xdc02-xdc-full-hbss-apothem-109
```

## Data Layout

All data stored in `$PWD/data/` (no external flags needed):

```
xdc-node-setup/
├── data/
│   ├── mainnet/
│   │   ├── xdc/          # v2.6.8 chain data (~800GB at full sync)
│   │   └── geth/         # GP5 chain data (~600GB at full sync)
│   │       └── XDC/
│   │           └── static-nodes.json  # Auto-generated with v268 enode
│   └── apothem/
│       ├── xdc/
│       └── geth/
├── scripts/
│   ├── bootstrap-setup.sh
│   ├── deploy-skyone.sh
│   └── lib/naming.sh
└── docs/
    └── DEVOPS_RUNBOOK.md  (this file)
```

## Verification

### Check sync progress

```bash
# v2.6.8 (xdc) block height
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8550 | jq -r '.result' | xargs printf "%d\n"

# GP5 (geth) block height
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545 | jq -r '.result' | xargs printf "%d\n"

# Peer count
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://localhost:8550 | jq -r '.result' | xargs printf "%d\n"
```

### Check SkyNet visibility

```bash
curl -s https://skynet.xdcindia.com/api/v2/nodes | \
  jq '.nodes[] | select(.name | contains("xdc01")) | {name, status, block_height, peer_count}'
```

### Check ethstats

Visit https://stats.xdcindia.com — both nodes should appear with proper names.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| v2.6.8 no peers | Check firewall: `ufw allow 30303/tcp; ufw allow 30303/udp` |
| GP5 no peers | Verify v2.6.8 has peers first; check static-nodes.json exists |
| GP5 apothem fails | GP5 apothem genesis incompatible — use v2.6.8 only for testnet |
| SkyNet not visible | Check SkyOne logs: `docker logs skyone-<name> --tail 20` |
| ethstats not showing | Verify ethstats secret and host in container args |
| Port conflict | `ss -tlnp | grep <port>` — kill conflicting process |
| Out of disk | `df -h` — data grows ~50GB/month per client |

## Sync Time Estimates

| Network | v2.6.8 from genesis | GP5 from genesis |
|---------|--------------------|--------------------|
| Mainnet (~13M blocks) | 5-10 days | 5-10 days (faster with v268 peer) |
| Apothem (~13M blocks) | 3-7 days | N/A (genesis incompatible) |

## Known Limitations

1. **GP5 Apothem**: Genesis hash differs from v2.6.8 network — GP5 cannot sync apothem
2. **ethstats proxy**: Some servers have local proxy at `127.0.0.1:2000`, others use `stats.xdcindia.com:443` directly
3. **v2.6.8 flags**: Uses legacy `--rpc/--rpcaddr` (NOT `--http/--http.addr`)
