# XDC CLI Reference

**Complete command-line interface for XDC node management**

---

## Overview

The `xdc` command-line tool provides comprehensive control over your XDC Network node, including deployment, monitoring, troubleshooting, and maintenance operations.

**Installation:** The CLI is automatically installed during `setup.sh`, Ansible playbooks, and Terraform cloud-init deployments. It is available globally as `xdc`.

**Location:** `/usr/local/bin/xdc` (symlinked from install directory)

**Verification:** After deployment, confirm the CLI is installed:

```bash
xdc --version
which xdc
```

If the CLI is missing, you can install it manually:

```bash
bash /path/to/xdc-node-setup/cli/install.sh
```

Or run the smoke test:

```bash
bash tests/test-cli-install.sh
```

---

## Command Structure

```bash
xdc <command> [options] [arguments]
```

**Global Options:**

| Option | Description |
|--------|-------------|
| `--help, -h` | Show help for command |
| `--version, -v` | Show version information |
| `--network <name>` | Specify network (mainnet, testnet, devnet) |
| `--config <path>` | Use custom config file |
| `--verbose` | Enable verbose output |
| `--quiet` | Suppress non-error output |
| `--json` | Output in JSON format |

---

## Core Commands

### `xdc status`

Display current node status and sync progress.

**Usage:**

```bash
xdc status [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--watch, -w` | Continuous monitoring mode (refresh every 5s) |
| `--json` | Output in JSON format |
| `--detailed` | Show extended information |

**Example output:**

```
XDC Node Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Status:        ✅ Syncing
Network:       Mainnet (50)
Current Block: 75,234,567
Highest Block: 75,234,600
Progress:      99.95%
Peers:         23 connected
Uptime:        5d 12h 34m
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Exit codes:**
- `0` — Node healthy and syncing
- `1` — Node offline or unreachable
- `2` — Node syncing but with warnings

---

### `xdc start`

Start the XDC node container.

**Usage:**

```bash
xdc start [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--monitoring` | Start with monitoring stack (Prometheus + Grafana) |
| `--snapshot` | Apply snapshot before starting |
| `--network <name>` | Start specific network (mainnet, testnet, devnet) |
| `--detach, -d` | Run in background (default) |

**Examples:**

```bash
# Start mainnet node
xdc start

# Start with monitoring enabled
xdc start --monitoring

# Start testnet node
xdc start --network testnet

# Start fresh with snapshot
xdc start --snapshot
```

**What it does:**
1. Checks if node is already running
2. Validates configuration files
3. Starts Docker containers via `docker-compose up -d`
4. Waits for RPC to become available
5. Displays initial status

---

### `xdc stop`

Stop the XDC node container gracefully.

**Usage:**

```bash
xdc stop [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--force, -f` | Force stop (immediate shutdown) |
| `--timeout <seconds>` | Graceful shutdown timeout (default: 30s) |

**Examples:**

```bash
# Graceful stop (waits for current operations)
xdc stop

# Force stop immediately
xdc stop --force

# Custom timeout
xdc stop --timeout 60
```

**Shutdown sequence:**
1. Sends SIGTERM to node process
2. Waits for graceful shutdown (up to timeout)
3. If timeout exceeded, sends SIGKILL
4. Removes containers

---

### `xdc restart`

Restart the node with graceful shutdown.

**Usage:**

```bash
xdc restart [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--hard` | Stop and start (instead of restart) |
| `--clear-cache` | Clear node cache before restart |

**Examples:**

```bash
# Standard restart
xdc restart

# Hard restart (stop + start)
xdc restart --hard

# Restart with cache clear
xdc restart --clear-cache
```

---

### `xdc logs`

View node logs with filtering and follow mode.

**Usage:**

```bash
xdc logs [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--follow, -f` | Follow log output (tail -f mode) |
| `--tail <n>` | Show last n lines (default: 100) |
| `--since <time>` | Show logs since timestamp/duration |
| `--level <level>` | Filter by level (info, warn, error, debug) |
| `--grep <pattern>` | Filter logs by pattern |

**Examples:**

```bash
# Show last 100 lines
xdc logs

# Follow logs in real-time
xdc logs --follow

# Show last 500 lines
xdc logs --tail 500

# Show logs from last hour
xdc logs --since 1h

# Show only errors
xdc logs --level error

# Search for specific pattern
xdc logs --grep "peer connected"

# Combined filters
xdc logs --follow --level warn --since 30m
```

**Time formats for `--since`:**
- `10m` — Last 10 minutes
- `1h` — Last hour
- `24h` — Last 24 hours
- `2026-02-14T07:00:00Z` — Specific timestamp

---

### `xdc attach`

Attach to the XDC console for direct RPC interaction.

**Usage:**

```bash
xdc attach [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--exec <command>` | Execute command and exit |
| `--preload <script>` | Load JavaScript file before console |

**Examples:**

```bash
# Attach to interactive console
xdc attach

# Execute single command
xdc attach --exec "eth.blockNumber"

# Load script and attach
xdc attach --preload /path/to/script.js
```

**Console commands:**

```javascript
// Get current block number
eth.blockNumber

// Get peer count
net.peerCount

// Get node info
admin.nodeInfo

// Get accounts
eth.accounts

// Get balance
eth.getBalance("xdc1234...")

// Send transaction
eth.sendTransaction({from: "xdc...", to: "xdc...", value: web3.toWei(1, "ether")})

// Exit console
exit
```

**To exit console:** Press `Ctrl+D` or type `exit`

---

## Monitoring Commands

### `xdc peers`

List and analyze connected peers.

**Usage:**

```bash
xdc peers [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--json` | Output in JSON format |
| `--detailed` | Show full peer information |
| `--count` | Show only peer count |
| `--sort <field>` | Sort by field (latency, block, name) |

**Example output:**

```
Connected Peers (23)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Peer ID              Client       Block      Latency
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
enode://abc...       XDC/v1.4.8   75234567   45ms
enode://def...       XDC/v1.4.7   75234567   120ms
enode://ghi...       XDC/v1.4.8   75234566   78ms
...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

### `xdc health`

Run comprehensive health check with security audit.

**Usage:**

```bash
xdc health [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--full` | Run extended health check (includes security scan) |
| `--notify` | Send notification if issues detected |
| `--fix` | Attempt auto-fix for detected issues |

**Example output:**

```
XDC Node Health Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Node Status:        Running
✅ Sync Status:        Syncing (99.95%)
✅ Peer Count:         23 (healthy)
✅ Disk Space:         287 GB free
⚠️  Memory Usage:      89% (high)
✅ Network:            Reachable
✅ RPC:                Responding
✅ Ports:              Open (30303, 8545)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Security Score: 85/100 (Good)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Recommendations:
  • Consider restarting node (high memory usage)
  • Update to XDC v1.4.9 (security patch available)
```

**Exit codes:**
- `0` — All checks passed
- `1` — Minor issues detected (warnings)
- `2` — Critical issues detected (errors)

---

### `xdc info`

Show detailed node and chain information.

**Usage:**

```bash
xdc info [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--json` | Output in JSON format |
| `--system` | Include system resource info |

**Example output:**

```
XDC Node Information
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Node Details:
  Version:         XDC/v1.4.8-stable
  Node ID:         enode://abc123...
  Network:         Mainnet (50)
  Protocol:        xdc/66

Chain Details:
  Current Block:   75,234,567
  Highest Block:   75,234,600
  Chain ID:        50
  Genesis Hash:    0x7f8a9b...

System Resources:
  CPU Usage:       12.4%
  Memory:          7.2 GB / 16 GB (45%)
  Disk:            213 GB / 500 GB (42%)
  Uptime:          5d 12h 34m

Networking:
  Listening:       0.0.0.0:30303
  Discovery:       Enabled
  NAT:             UPnP
  Max Peers:       50
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

### `xdc sync`

Check detailed sync status and block height.

**Usage:**

```bash
xdc sync [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--watch, -w` | Continuous monitoring (refresh every 10s) |
| `--estimate` | Show estimated time to full sync |

**Example output:**

```
Sync Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Current:       75,234,567
Target:        75,234,600
Behind:        33 blocks
Progress:      99.95%
State:         Syncing
Mode:          Full Sync

Performance:
  Avg Speed:   45 blocks/sec
  ETA:         ~1 minute
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Maintenance Commands

### `xdc backup`

Create encrypted backup of node data.

**Usage:**

```bash
xdc backup create [options] [destination]
xdc backup restore <backup-file> [options]
xdc backup list [options]
```

**Create backup options:**

| Option | Description |
|--------|-------------|
| `--encrypt` | Encrypt backup with password |
| `--compress` | Compress backup (gzip) |
| `--exclude-chaindata` | Exclude blockchain data (keystore only) |

**Examples:**

```bash
# Create full backup
xdc backup create /mnt/backups/

# Create encrypted backup
xdc backup create --encrypt /mnt/backups/

# Backup keystore only
xdc backup create --exclude-chaindata /mnt/backups/

# Restore from backup
xdc backup restore /mnt/backups/xdc-backup-2026-02-14.tar.gz
```

**Backup contents:**
- Node configuration files
- Keystore (encrypted wallet files)
- Optional: Full chaindata (blockchain database)

---

### `xdc snapshot`

Download and apply chain snapshot for fast sync.

**Usage:**

```bash
xdc snapshot download [options]
xdc snapshot apply [options]
xdc snapshot list [options]
xdc snapshot verify <file>
```

**Download options:**

| Option | Description |
|--------|-------------|
| `--network <name>` | Network to download (mainnet, testnet) |
| `--date <YYYY-MM-DD>` | Specific snapshot date |
| `--mirror <url>` | Use custom mirror URL |
| `--resume` | Resume interrupted download |

**Examples:**

```bash
# Download latest mainnet snapshot
xdc snapshot download --network mainnet

# Download specific date
xdc snapshot download --network mainnet --date 2026-02-10

# Resume interrupted download
xdc snapshot download --resume

# List available snapshots
xdc snapshot list

# Verify snapshot integrity
xdc snapshot verify snapshot-mainnet-2026-02-14.tar.gz

# Apply downloaded snapshot
xdc stop
xdc snapshot apply
xdc start
```

**Snapshot process:**
1. Downloads compressed blockchain data
2. Verifies checksum
3. Extracts to chaindata directory
4. Validates database integrity
5. Ready to start node

**Benefits:**
- **Fast sync:** Skip days/weeks of blockchain sync
- **Resume support:** Interrupted downloads can continue
- **Verified:** Checksums ensure data integrity

---

### `xdc security`

Run security audit and apply hardening.

**Usage:**

```bash
xdc security audit [options]
xdc security harden [options]
xdc security scan [options]
```

**Audit options:**

| Option | Description |
|--------|-------------|
| `--report <path>` | Save report to file |
| `--json` | Output in JSON format |

**Examples:**

```bash
# Run security audit
xdc security audit

# Apply security hardening
xdc security harden

# Scan for vulnerabilities
xdc security scan

# Generate report
xdc security audit --report /var/log/xdc-security-audit.txt
```

**Security checks:**
- SSH hardening (key-only auth, disabled root login)
- Firewall configuration (ufw rules)
- Fail2ban status
- File permissions
- Open ports scan
- Docker security
- Log auditing

---

### `xdc monitor`

Open or manage monitoring dashboard.

**Usage:**

```bash
xdc monitor [options]
xdc monitor start [options]
xdc monitor stop
xdc monitor restart
```

**Options:**

| Option | Description |
|--------|-------------|
| `--port <number>` | Dashboard port (default: 8888) |
| `--open` | Open in browser automatically |

**Examples:**

```bash
# Open monitoring dashboard
xdc monitor

# Start monitoring stack
xdc monitor start

# Start on custom port
xdc monitor start --port 9090

# Stop monitoring
xdc monitor stop
```

**Monitoring stack includes:**
- Grafana dashboard (port 3000)
- Prometheus metrics (port 9090)
- Node exporter (system metrics)
- cAdvisor (container metrics)

---

### `xdc update`

Check for and apply version updates.

**Usage:**

```bash
xdc update check [options]
xdc update apply [options]
xdc update rollback
```

**Update options:**

| Option | Description |
|--------|-------------|
| `--version <ver>` | Update to specific version |
| `--auto` | Auto-apply updates without confirmation |
| `--backup` | Create backup before updating |

**Examples:**

```bash
# Check for updates
xdc update check

# Apply latest update
xdc update apply

# Update to specific version
xdc update apply --version v1.4.9

# Update with backup
xdc update apply --backup

# Rollback to previous version
xdc update rollback
```

**Update process:**
1. Checks for new XDC node version
2. Downloads and verifies new binary
3. Creates backup of current version
4. Stops node gracefully
5. Replaces binary
6. Restarts node
7. Validates new version

---

## Configuration Commands

### `xdc config`

View and modify node configuration.

**Usage:**

```bash
xdc config list [options]
xdc config get <key>
xdc config set <key> <value>
xdc config reset
```

**Examples:**

```bash
# List all configuration
xdc config list

# Get specific value
xdc config get rpc_port

# Set value
xdc config set max_peers 100

# Reset to defaults
xdc config reset
```

**Common configuration keys:**

| Key | Default | Description |
|-----|---------|-------------|
| `network_id` | `50` | Network ID (50=mainnet, 51=testnet) |
| `rpc_port` | `8545` | HTTP RPC port |
| `ws_port` | `8546` | WebSocket port |
| `p2p_port` | `30303` | P2P discovery port |
| `max_peers` | `50` | Maximum peer connections |
| `sync_mode` | `full` | Sync mode (full, fast, archive) |
| `cache_size` | `4096` | Cache size in MB |
| `prune_mode` | `full` | State pruning mode |

---

## Advanced Commands

### `xdc debug`

Debug utilities for troubleshooting.

**Usage:**

```bash
xdc debug rpc [options]
xdc debug peers [options]
xdc debug db [options]
```

**Examples:**

```bash
# Test RPC connectivity
xdc debug rpc

# Debug peer connections
xdc debug peers --verbose

# Check database integrity
xdc debug db --check
```

---

### `xdc export`

Export node data (blocks, state, accounts).

**Usage:**

```bash
xdc export blocks <start> <end> <output>
xdc export state <block> <output>
```

**Examples:**

```bash
# Export blocks 1000-2000
xdc export blocks 1000 2000 /tmp/blocks.rlp

# Export state at block 1000
xdc export state 1000 /tmp/state.dump
```

---

### `xdc import`

Import previously exported data.

**Usage:**

```bash
xdc import blocks <file>
xdc import state <file>
```

**Examples:**

```bash
# Import blocks
xdc import blocks /tmp/blocks.rlp

# Import state
xdc import state /tmp/state.dump
```

---

## SkyNet Commands

### `xdc skynet`

Manage SkyNet integration.

**Usage:**

```bash
xdc skynet status
xdc skynet register [options]
xdc skynet unregister
xdc skynet heartbeat
```

**Examples:**

```bash
# Check SkyNet status
xdc skynet status

# Register with SkyNet
xdc skynet register --name "my-node" --location "US-East"

# Manual heartbeat
xdc skynet heartbeat

# Unregister from SkyNet
xdc skynet unregister
```

---

## Utility Commands

### `xdc version`

Show version information.

**Usage:**

```bash
xdc version [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--check` | Check for updates |
| `--json` | Output in JSON format |

**Example output:**

```
XDC CLI Version:    v2.1.0
XDC Node Version:   v1.4.8-stable
Docker:             20.10.23
Docker Compose:     v2.15.1
```

---

### `xdc help`

Show help information for commands.

**Usage:**

```bash
xdc help [command]
```

**Examples:**

```bash
# General help
xdc help

# Command-specific help
xdc help start
xdc help snapshot
```

---

## Environment Variables

The CLI respects these environment variables:

| Variable | Description |
|----------|-------------|
| `XDC_HOME` | Installation directory (default: `/opt/xdc-node`) |
| `XDC_NETWORK` | Default network (mainnet, testnet, devnet) |
| `XDC_RPC_URL` | RPC endpoint URL |
| `XDC_CONFIG` | Custom config file path |
| `XDC_LOG_LEVEL` | Logging level (debug, info, warn, error) |

**Example:**

```bash
export XDC_NETWORK=testnet
export XDC_LOG_LEVEL=debug
xdc start
```

---

## Exit Codes

The CLI uses standard exit codes:

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | General error |
| `2` | Misconfiguration or validation error |
| `3` | Node unreachable or not running |
| `4` | Insufficient permissions |
| `5` | Resource unavailable (disk full, etc.) |

**Usage in scripts:**

```bash
if ! xdc status > /dev/null 2>&1; then
  echo "Node is down, restarting..."
  xdc restart
fi
```

---

## Shell Completion

Enable command auto-completion:

**Bash:**

```bash
xdc completion bash > /etc/bash_completion.d/xdc
source /etc/bash_completion.d/xdc
```

**Zsh:**

```bash
xdc completion zsh > ~/.zsh/completion/_xdc
```

**Fish:**

```bash
xdc completion fish > ~/.config/fish/completions/xdc.fish
```

---

## Examples & Workflows

### Daily monitoring routine

```bash
# Check node status
xdc status

# Check peer count
xdc peers --count

# View recent errors
xdc logs --level error --since 24h

# Run health check
xdc health
```

### After updates

```bash
# Check for updates
xdc update check

# Create backup before updating
xdc backup create --encrypt /mnt/backups/

# Apply update
xdc update apply --backup

# Verify after update
xdc status
xdc health --full
```

### Fresh node setup with snapshot

```bash
# Download snapshot
xdc snapshot download --network mainnet

# Apply snapshot
xdc stop
xdc snapshot apply
xdc start

# Monitor sync
xdc sync --watch
```

### Troubleshooting sync issues

```bash
# Check sync status
xdc sync

# Check peer connectivity
xdc peers --detailed

# View sync-related logs
xdc logs --grep "sync" --tail 200

# Restart to trigger peer discovery
xdc restart
```

---

## Tips & Best Practices

1. **Use `--json` for scripting** — Parse output with `jq` or other tools
2. **Combine `--watch` with `grep`** — Filter live logs: `xdc logs -f | grep ERROR`
3. **Schedule health checks** — Add to cron: `0 */6 * * * xdc health --notify`
4. **Always backup before updates** — Use `xdc update apply --backup`
5. **Monitor disk space** — Check regularly: `xdc info --system`
6. **Use snapshots on initial sync** — Saves days of sync time
7. **Keep logs manageable** — Rotate with: `xdc logs --since 7d > archive.log`

---

## Support

- **GitHub:** [https://github.com/AnilChinchawale/XDC-Node-Setup](https://github.com/AnilChinchawale/XDC-Node-Setup)
- **Issues:** Report bugs via GitHub Issues
- **Documentation:** Full docs at [https://docs.xdc.network/](https://docs.xdc.network/)

---

**XDC CLI — Complete control over your XDC Network node**
