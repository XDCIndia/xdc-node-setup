# Erigon Migration Guide

Migrate your XDC node from the default Geth client to **Erigon** — a more efficient implementation with lower disk usage and faster sync.

## Why Erigon?

| Feature | Geth | Erigon |
|---------|------|--------|
| Disk usage | ~500 GB | ~200 GB |
| Sync speed | 4–8 hours | 2–4 hours |
| RAM usage | 8 GB | 4 GB |
| Archive mode | 2+ TB | ~500 GB |
| Client diversity | ✅ | ✅ |

## Prerequisites

- Existing XDC node (Geth) running and synced
- Sufficient disk space for the migration (~200 GB free)
- Docker 24.0+ recommended

## Step 1: Backup Current Configuration

```bash
# Backup config
cp config.toml config.toml.geth-backup

# Note current block height for verification
xdc status --json | jq '.blockHeight'
```

## Step 2: Stop the Geth Node

```bash
xdc stop
```

## Step 3: Switch Client to Erigon

```bash
xdc setup --client erigon
```

Or edit `config.toml` manually:
```toml
[node]
client = "erigon"
```

## Step 4: Start with Erigon

```bash
xdc start
```

Erigon will start syncing from scratch. The old Geth data is preserved in case you need to roll back.

## Step 5: Monitor Sync

```bash
# Watch sync progress
xdc status --sync

# Erigon-specific stages
xdc logs --tail 20 --filter "stage"
```

Erigon syncs in stages:
1. **Headers** — Download block headers
2. **Bodies** — Download block bodies
3. **Senders** — Recover transaction senders
4. **Execution** — Execute all transactions
5. **HashState** — Build state trie
6. **Finish** — Final verification

## Step 6: Verify

```bash
# Confirm client
xdc status --json | jq '.client'
# Should output: "erigon"

# Health check
xdc health
```

## Rolling Back to Geth

If you need to switch back:

```bash
xdc stop
xdc setup --client geth
xdc start
```

Your original Geth data directory is preserved during migration.

## Erigon-Specific Configuration

In `config.toml`:

```toml
[erigon]
# Prune mode: reduce disk usage
prune = "htc"

# Batch size for execution stage
batch-size = "512M"

# Enable archive mode (optional)
# archive = true
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Sync stuck at headers" | Increase peers: `xdc config set maxpeers 50` |
| "Database corruption" | Run `xdc reset --keep-config` and resync |
| "High memory usage" | Reduce batch-size to `256M` |
| "Missing RPC methods" | Some Geth-specific RPCs differ in Erigon; check compatibility |

## macOS ARM64 Notes

Erigon Docker images are available for `linux/arm64`. On macOS:

```bash
# Verify native ARM64 image
docker inspect xdc-erigon --format '{{.Architecture}}'
# Should output: arm64
```

If only `amd64` images are available, Colima will run them under emulation (slower).
