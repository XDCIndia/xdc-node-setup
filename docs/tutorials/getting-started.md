# Getting Started with XDC Node Setup

Welcome! This guide walks you through setting up your first XDC Network node from scratch.

## Prerequisites

| Requirement | Minimum | Recommended |
|------------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8+ GB |
| Disk | 100 GB SSD | 500 GB NVMe |
| OS | Ubuntu 20.04 / macOS 12 | Ubuntu 22.04 / macOS 14 |
| Docker | 20.10+ | 24.0+ |

## Step 1: Install

### Linux (Ubuntu/Debian)

```bash
curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/install.sh | bash
```

### macOS (Apple Silicon)

```bash
# Install Homebrew if needed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install dependencies
brew install docker colima jq

# Start Docker runtime
colima start --cpu 2 --memory 4 --arch aarch64

# Install XDC Node
curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/install.sh | bash
```

## Step 2: Configure

```bash
xdc setup
```

The setup wizard asks:
1. **Network** — mainnet, testnet, or devnet
2. **Client** — geth (default) or erigon
3. **Node name** — a friendly identifier
4. **RPC port** — default 8545

Configuration is saved to `config.toml`.

## Step 3: Start Your Node

```bash
xdc start
```

## Step 4: Verify

```bash
# Check status
xdc status

# Health check
xdc health

# View logs
xdc logs --tail 50
```

## Step 5: Monitor Sync Progress

```bash
xdc status --sync
```

Your node will sync with the network. This takes **2–6 hours** on mainnet depending on your connection and disk speed.

## What's Next?

- [Masternode Setup](./masternode-setup.md) — Run a validator node
- [Erigon Migration](./erigon-migration.md) — Switch to the Erigon client
- [Monitoring](./monitoring.md) — Set up Prometheus + Grafana dashboards

## Quick Reference

```bash
xdc start          # Start the node
xdc stop           # Stop the node
xdc restart        # Restart the node
xdc status         # Show node status
xdc health         # Run health checks
xdc logs           # View logs
xdc reset          # Wipe data and start fresh
xdc update         # Update to latest version
```

## Troubleshooting

If anything goes wrong:

```bash
# Detailed health report
xdc health --json | jq .

# Check Docker containers
docker ps -a --filter "name=xdc"

# Full troubleshooting guide
xdc docs troubleshooting
```

See [Troubleshooting Guide](../TROUBLESHOOTING.md) for common issues and solutions.
