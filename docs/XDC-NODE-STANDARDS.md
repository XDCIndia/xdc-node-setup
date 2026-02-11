# XDC Node Infrastructure Standards

> Industry-grade standards for deploying, securing, monitoring, and maintaining XDC Network nodes.

**Repository:** [github.com/AnilChinchawale/XDC-Node-Setup](https://github.com/AnilChinchawale/XDC-Node-Setup)

---

## Table of Contents

1. [Server Security](#1-server-security)
2. [Audit & Compliance](#2-audit--compliance)
3. [Smart Engineering](#3-smart-engineering)
4. [Single-Pane Monitoring](#4-single-pane-monitoring)
5. [Version Management & Auto-Update](#5-version-management--auto-update)
6. [Security Scorecard](#6-security-scorecard)
7. [Notification System](#7-notification-system)
8. [XDC-Specific Requirements](#8-xdc-specific-requirements)
9. [Quick Start](#9-quick-start)

---

## 1. Server Security

> **Implementing script:** [`scripts/security-harden.sh`](../scripts/security-harden.sh)

### SSH Hardening
```bash
# /etc/ssh/sshd_config
PermitRootLogin prohibit-password   # Key-only auth
PasswordAuthentication no            # Disable password login
Port 12141                          # Non-standard port
MaxAuthTries 3
AllowUsers root                     # Explicit allowlist
ClientAliveInterval 300
ClientAliveCountMax 2
```

### Firewall (UFW)
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 12141/tcp    # SSH (custom port)
ufw allow 30303/tcp    # XDC P2P
ufw allow 30303/udp    # XDC P2P discovery
ufw enable
```

> ⚠️ **Never expose RPC ports (8545, 8546, 8989) to the internet.** Use a reverse proxy (Nginx) with rate limiting and API key authentication if external access is needed.

### Fail2ban
```ini
# /etc/fail2ban/jail.local
[sshd]
enabled = true
port = 12141
maxretry = 3
bantime = 3600
findtime = 600
```

> **Config template:** [`configs/fail2ban.conf`](../configs/fail2ban.conf)

### Disk Encryption
- **LUKS** for data-at-rest encryption on chain data volumes
- Encrypt `/root/xdcchain` partitions
- Store keys in hardware security module (HSM) for production
- Minimum: encrypt keystore directory

### Secrets Management
- **Never store private keys or secrets in plaintext** on disk in production
- Use HashiCorp Vault, AWS Secrets Manager, or SOPS-encrypted configs
- Rotate credentials every 90 days
- Separate secrets per environment (test/staging/prod)

### Sysctl Hardening
```bash
# Network hardening
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.tcp_syncookies = 1

# Kernel hardening
kernel.randomize_va_space = 2
fs.suid_dumpable = 0
kernel.core_uses_pid = 1
```

> **Config template:** [`configs/sshd_config.template`](../configs/sshd_config.template)

---

## 2. Audit & Compliance

### SOC 2 Type II
The gold standard for blockchain infrastructure providers (Alchemy, Infura, QuickNode all maintain it):
- **Security**: Access controls, encryption, network security
- **Availability**: Uptime SLAs, redundancy, disaster recovery
- **Processing Integrity**: Accurate block processing, consensus verification
- **Confidentiality**: Data classification, encryption at rest/transit
- **Privacy**: No PII in logs, data retention policies

### Audit Logging
```bash
# Install and configure auditd
apt install auditd audispd-plugins

# Log all admin commands
auditctl -a always,exit -F arch=b64 -S execve -F uid=0 -k admin-commands

# Log file access to chain data
auditctl -w /root/xdcchain -p rwxa -k chaindata-access

# Log keystore access
auditctl -w /root/xdcchain/keystore -p rwxa -k keystore-access

# Log SSH events
auditctl -w /var/log/auth.log -p wa -k auth-log
```

### Change Management
- All node configs tracked in Git (this repository)
- Infrastructure-as-Code via setup scripts
- Version-controlled updates via `configs/versions.json`
- Rollback procedures: stop node → restore backup → restart

### Log Retention

| Log Type | Retention | Storage |
|----------|-----------|---------|
| Audit logs | 1 year | Encrypted offsite |
| Node logs | 90 days | Compressed local + remote |
| System logs | 30 days | Local + remote syslog |
| Security events | 2 years | Immutable storage |

---

## 3. Smart Engineering

### Client Diversity
Running multiple client implementations prevents single-point-of-failure bugs:

| Client | Type | Repository | Purpose |
|--------|------|-----------|---------|
| **XDPoSChain** (geth-xdc) | Go | [XinFinOrg/XDPoSChain](https://github.com/XinFinOrg/XDPoSChain) | Primary consensus client |
| **erigon-xdc** | Go | [AnilChinchawale/erigon-xdc](https://github.com/AnilChinchawale/erigon-xdc) | Alternative client for diversity |

> **XDC Network goal:** No single client should run >66% of nodes to prevent consensus bugs from causing chain halts.

### Geographic Distribution
Recommended minimum for production node infrastructure:
- **3+ regions** (e.g., EU, US, Asia)
- **2+ providers** per region (Hetzner, OVH, AWS, DigitalOcean)
- Round-robin DNS or global load balancer for RPC endpoints

### High Availability Architecture
```
                    ┌─────────────┐
                    │  DNS / LB   │
                    └──────┬──────┘
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │ Region 1 │ │ Region 2 │ │ Region 3 │
        │ (EU)     │ │ (US)     │ │ (Asia)   │
        ├──────────┤ ├──────────┤ ├──────────┤
        │ geth-xdc │ │ geth-xdc │ │ geth-xdc │
        │ erigon   │ │ erigon   │ │ erigon   │
        │ monitor  │ │ monitor  │ │ monitor  │
        └──────────┘ └──────────┘ └──────────┘
```

### Circuit Breakers & Failover
- Health checks every 15 minutes (`scripts/node-health-check.sh`)
- Automatic restart via systemd (`systemd/xdc-node.service`)
- Watchdog script for process monitoring
- Telegram alerts on node failure
- Automatic failover to healthy nodes via load balancer

### Backup Strategy

> **Implementing script:** [`scripts/backup.sh`](../scripts/backup.sh)

- **Daily backups** at 3:00 AM (incremental)
- **Weekly full backups** on Sunday at 2:00 AM
- **Retention**: 7 daily, 4 weekly, 12 monthly
- **Encryption**: GPG-encrypted archives
- **Targets**: keystore, configs, genesis.json, node database
- **Offsite**: Optional S3 or FTP upload

---

## 4. Single-Pane Monitoring

### Monitoring Stack

Deployed via [`docker/docker-compose.yml`](../docker/docker-compose.yml):

| Component | Port | Purpose |
|-----------|------|---------|
| **Grafana** | 3000 | Dashboards & visualization |
| **Prometheus** | 9090 | Metrics collection & alerting |
| **Node Exporter** | 9100 | System metrics (CPU, RAM, disk, network) |
| **cAdvisor** | 8080 | Container metrics |

### Grafana Dashboard

Pre-configured dashboard ([`monitoring/grafana/dashboards/xdc-node.json`](../monitoring/grafana/dashboards/xdc-node.json)):

- **Block Height** — current height vs mainnet head
- **Sync Progress** — percentage and ETA
- **Peer Count** — P2P connectivity health
- **CPU Usage** — per-core and average
- **Memory Usage** — used/available/cached
- **Disk Usage** — space and I/O throughput
- **Network I/O** — bandwidth in/out
- **Client Version** — current vs latest release
- **Uptime** — continuous uptime tracking

### Health Check Script

> **Implementing script:** [`scripts/node-health-check.sh`](../scripts/node-health-check.sh)

Checks performed:
```bash
# RPC health
eth_blockNumber      # Current block height
net_peerCount        # Connected peers
eth_syncing          # Sync status
web3_clientVersion   # Client version string

# System health (via SSH for remote nodes)
df -h                # Disk usage
top -bn1             # CPU usage
free -m              # Memory usage
uptime -p            # System uptime
```

### Alerting Rules

> **Config:** [`monitoring/alerts.yml`](../monitoring/alerts.yml)

| Condition | Severity | Action |
|-----------|----------|--------|
| Node offline > 5 min | 🔴 Critical | Telegram alert + auto-restart |
| Block height behind > 100 blocks | 🟡 Warning | Telegram alert |
| Peer count = 0 | 🟡 Warning | Telegram alert |
| Disk usage > 85% | 🟡 Warning | Telegram alert |
| Disk usage > 95% | 🔴 Critical | Telegram alert + prune old data |
| CPU usage > 90% sustained | 🟡 Warning | Telegram alert |
| Memory usage > 90% | 🟡 Warning | Telegram alert |
| New client version available | 🔵 Info | Telegram notification |
| Security score < 70 | 🟡 Warning | Review required |

### Telegram Notifications
Set up alerts via environment variables:
```bash
export TELEGRAM_BOT_TOKEN="your-bot-token"
export TELEGRAM_CHAT_ID="your-chat-id"
```

Create a bot via [@BotFather](https://t.me/BotFather) and get your chat ID from [@userinfobot](https://t.me/userinfobot).

---

## 5. Version Management & Auto-Update

> **Implementing script:** [`scripts/version-check.sh`](../scripts/version-check.sh)
> **Config:** [`configs/versions.json`](../configs/versions.json)

### Version Mapping
```json
{
  "schemaVersion": 1,
  "checkIntervalHours": 6,
  "clients": {
    "XDPoSChain": {
      "repo": "XinFinOrg/XDPoSChain",
      "current": "v2.6.0",
      "latest": "v2.6.0",
      "autoUpdate": false
    },
    "erigon-xdc": {
      "repo": "AnilChinchawale/erigon-xdc",
      "current": "0.1.0-alpha",
      "latest": "0.1.0-alpha",
      "autoUpdate": false
    }
  }
}
```

### How It Works
1. **Version check script** runs every 6 hours via cron
2. Queries GitHub Releases API for each client repository
3. Uses ETag caching to avoid GitHub API rate limits
4. Compares `current` vs `latest` semantic version
5. If new version detected:
   - `autoUpdate: true` → Pull, build, deploy to test node first, then production (rolling restart)
   - `autoUpdate: false` → Telegram notification with changelog link
6. Updates `configs/versions.json` with latest version and timestamp

### Update Strategy
```
New Release Detected
        │
        ▼
   ┌─────────┐     autoUpdate: true
   │  Notify  │────────────────────►  Deploy to TEST node
   │  Admin   │                           │
   └─────────┘                       Run health checks
        │                                │
   autoUpdate: false              Checks pass?
        │                          Yes ──┤── No → Alert & rollback
        ▼                                ▼
   Manual review              Deploy to PRODUCTION
   & approval                  (rolling restart)
                                        │
                                        ▼
                               Verify & report
```

### Cron Schedule
```bash
# Version check every 6 hours
0 */6 * * * /opt/xdc-node/scripts/version-check.sh --notify

# Full health report daily at 6 AM
0 6 * * * /opt/xdc-node/scripts/node-health-check.sh --full --notify

# Health check every 15 minutes
*/15 * * * * /opt/xdc-node/scripts/node-health-check.sh --notify

# Backup daily at 3 AM
0 3 * * * /opt/xdc-node/scripts/backup.sh

# Weekly full backup Sunday 2 AM
0 2 * * 0 /opt/xdc-node/scripts/backup.sh --full
```

> **Auto-install:** [`cron/setup-crons.sh`](../cron/setup-crons.sh)

---

## 6. Security Scorecard

Each server is scored on a 100-point scale:

| # | Check | Points | How to Verify |
|---|-------|--------|---------------|
| 1 | SSH key-only auth | 10 | `sshd_config: PasswordAuthentication no` |
| 2 | Non-standard SSH port | 5 | `sshd_config: Port != 22` |
| 3 | Firewall active (UFW) | 10 | `ufw status` shows `active` |
| 4 | Fail2ban running | 5 | `systemctl is-active fail2ban` |
| 5 | Unattended upgrades | 5 | `dpkg -l unattended-upgrades` installed |
| 6 | OS patches current | 10 | `apt list --upgradable` count = 0 |
| 7 | Client version current | 15 | `current == latest` in versions.json |
| 8 | Monitoring active | 10 | Prometheus/node_exporter running |
| 9 | Backup configured | 10 | Backup cron exists + recent backup file |
| 10 | Audit logging (auditd) | 10 | `systemctl is-active auditd` |
| 11 | Disk encryption (LUKS) | 10 | `lsblk -f` shows LUKS volumes |
| | **Total** | **100** | |

### Score Interpretation

| Score | Rating | Action Required |
|-------|--------|-----------------|
| 90–100 | 🟢 **Excellent** | Production ready |
| 70–89 | 🟡 **Good** | Minor improvements needed |
| 50–69 | 🟠 **Fair** | Significant gaps — prioritize fixes |
| < 50 | 🔴 **Poor** | Not suitable for production use |

### Run Security Audit
```bash
./scripts/security-harden.sh --audit-only
# or
./scripts/node-health-check.sh --security-only
```

---

## 7. Notification System

### Overview

XDC Node Setup provides a multi-channel notification system for alerts, reports, and version updates. Instead of requiring users to configure their own Telegram bots, notifications are sent through the **XDC Gateway platform** — one API key and you're done.

### Architecture

```
┌──────────────────┐
│  Node Health      │
│  Version Check    │──── Alert Event ────┐
│  Backup Script    │                     │
│  Security Audit   │                     ▼
└──────────────────┘              ┌───────────────┐
                                  │  Notify Engine │
                                  │  (lib/notify)  │
                                  └───────┬───────┘
                          ┌───────────────┼───────────────┐
                          ▼               ▼               ▼
                   ┌────────────┐  ┌────────────┐  ┌────────────┐
                   │  Platform  │  │  Telegram   │  │   Email    │
                   │  API       │  │  (direct)   │  │  (SMTP)    │
                   └─────┬──────┘  └─────┬──────┘  └─────┬──────┘
                         │               │               │
                         ▼               ▼               ▼
                   ┌────────────┐  ┌────────────┐  ┌────────────┐
                   │ Gateway    │  │ Telegram    │  │ User       │
                   │ Bot → TG   │  │ Bot API     │  │ Inbox      │
                   │ + Email    │  │             │  │            │
                   └────────────┘  └────────────┘  └────────────┘
```

### Notification Channels

| Channel | Setup Complexity | Features | Recommended |
|---------|-----------------|----------|-------------|
| **Platform API** | 🟢 Easy — just API key | TG + Email via Gateway bot | ✅ Yes |
| **Direct Telegram** | 🟡 Medium — create bot | TG only, user manages bot | Fallback |
| **Direct Email** | 🟡 Medium — SMTP config | Email only | Optional add-on |

#### Channel 1: Platform API (Recommended)

Users register their node on the XDC Gateway dashboard and get an API key. All notifications route through the platform's Telegram bot and email service — zero bot setup required.

```
POST https://cloud.xdcrpc.com/api/v1/notifications/send
Authorization: Bearer <api-key>
Content-Type: application/json

{
  "type": "alert",
  "level": "critical",
  "title": "🔴 Node Down: 65.21.27.213",
  "message": "XDC node on 65.21.27.213 has been unreachable for 5 minutes. Last block: 99,222,839. Auto-restart attempted.",
  "channels": ["telegram", "email"],
  "metadata": {
    "nodeHost": "65.21.27.213",
    "alertType": "node_offline",
    "lastBlock": 99222839,
    "downtime": "5m"
  }
}
```

**Response:**
```json
{
  "success": true,
  "delivered": {
    "telegram": true,
    "email": true
  },
  "notificationId": "ntf_abc123"
}
```

#### Channel 2: Direct Telegram (Fallback)

For users who prefer their own bot:
1. Create bot via [@BotFather](https://t.me/BotFather)
2. Get chat ID from [@userinfobot](https://t.me/userinfobot)
3. Set `NOTIFY_TELEGRAM_BOT_TOKEN` and `NOTIFY_TELEGRAM_CHAT_ID`

#### Channel 3: Direct Email (SMTP)

For users who want direct email delivery:
```bash
NOTIFY_EMAIL_TO="admin@example.com"
NOTIFY_EMAIL_SMTP_HOST="smtp.gmail.com"
NOTIFY_EMAIL_SMTP_PORT=587
NOTIFY_EMAIL_SMTP_USER="alerts@example.com"
NOTIFY_EMAIL_SMTP_PASS="app-password"
```

### Alert Levels & Routing

| Level | Examples | Delivery | Quiet Hours |
|-------|----------|----------|-------------|
| 🔴 **Critical** | Node offline, disk >95%, backup failed, auto-update failed | **Instant** — all channels | ✅ Delivered always |
| 🟡 **Warning** | Peers = 0, disk >85%, block behind >100, security score <70 | **Hourly digest** | ❌ Held until morning |
| 🔵 **Info** | New version available, backup success, health report | **Daily report** | ❌ Held until morning |

### Smart Delivery Features

#### Deduplication
Same alert won't fire again within a configurable interval (default: 5 minutes for critical, 1 hour for warnings):

```
Alert state tracked in: /var/lib/xdc-node/alert-state.json

{
  "node_offline:65.21.27.213": {
    "lastFired": "2026-02-11T04:30:00Z",
    "count": 3,
    "level": "critical"
  },
  "block_behind:95.217.56.168": {
    "lastFired": "2026-02-11T03:00:00Z",
    "count": 1,
    "level": "warning"
  }
}
```

#### Quiet Hours
- **Default**: 23:00 — 07:00 (configurable)
- Only 🔴 **critical** alerts delivered during quiet hours
- 🟡 Warnings and 🔵 info batched into a **morning digest** sent at quiet hours end

#### Hourly Digest
Non-critical alerts batched into a summary instead of individual messages:

```
📊 XDC Node Digest (05:00 — 06:00)

⚠️ 2 Warnings:
  • Peer count = 0 on gcx-snap (175.110.113.12)
  • Block height 150 behind on test-erigon (95.217.56.168)

ℹ️ 1 Info:
  • Backup completed successfully on prod (65.21.27.213)

🔗 Full report: /var/lib/xdc-node/reports/2026-02-11.json
```

#### Rate Limiting
- Max **10 notifications per hour** per channel
- Prevents alert storms during cascading failures
- If limit hit, sends a single "rate limit reached, check logs" message

#### Retry Logic
- Failed sends retry **3 times** with exponential backoff (5s, 15s, 45s)
- All attempts logged to `/var/log/xdc-node/notifications.log`

### Email Templates

All emails use responsive HTML with XDC dark theme branding (primary: `#1F4CED`):

| Template | Trigger | Content |
|----------|---------|---------|
| **Alert** | Critical/warning event | Red/yellow header, event details, affected node, recommended action |
| **Daily Report** | Scheduled (6 AM) | All nodes summary table, security scores, version status, 24h timeline |
| **Digest** | Hourly (non-critical batch) | Grouped alerts/warnings/info with counts |
| **Version Update** | New release detected | Release version, changelog link, update instructions |

#### Example: Alert Email

```
┌─────────────────────────────────────────────┐
│  🔴 CRITICAL: Node Offline                  │  ← Red header
├─────────────────────────────────────────────┤
│                                             │
│  Server: 65.21.27.213 (production)          │
│  Client: XDPoSChain v2.6.0                  │
│  Last Block: 99,222,839                     │
│  Down Since: 2026-02-11 04:30:00 UTC        │
│  Duration: 5 minutes                        │
│                                             │
│  Action Taken:                              │
│  ✅ Auto-restart attempted                   │
│  ⏳ Waiting for node to sync                │
│                                             │
│  Recommended:                               │
│  • Check server SSH access                  │
│  • Review system logs                       │
│  • Verify disk space                        │
│                                             │
│  [View Dashboard] [SSH to Server]           │
│                                             │
├─────────────────────────────────────────────┤
│  XDC Node Setup • Unsubscribe              │
└─────────────────────────────────────────────┘
```

### Configuration

All notification settings in `/etc/xdc-node/notify.conf`:

```bash
# ============================================
# XDC Node Notification Configuration
# ============================================

# --- Channels (comma-separated) ---
# Options: platform, telegram, email
NOTIFY_CHANNELS="platform"

# --- Platform API (Recommended) ---
# Get your API key from https://cloud.xdcrpc.com/dashboard
NOTIFY_PLATFORM_URL="https://cloud.xdcrpc.com/api/v1/notifications"
NOTIFY_PLATFORM_API_KEY=""

# --- Direct Telegram (Fallback) ---
# Create bot: https://t.me/BotFather
# Get chat ID: https://t.me/userinfobot
NOTIFY_TELEGRAM_BOT_TOKEN=""
NOTIFY_TELEGRAM_CHAT_ID=""

# --- Email (Optional) ---
NOTIFY_EMAIL_TO=""
NOTIFY_EMAIL_FROM="alerts@xdc.network"
NOTIFY_EMAIL_SMTP_HOST="smtp.gmail.com"
NOTIFY_EMAIL_SMTP_PORT=587
NOTIFY_EMAIL_SMTP_USER=""
NOTIFY_EMAIL_SMTP_PASS=""

# --- Delivery Rules ---
NOTIFY_ALERT_INTERVAL=300        # Dedup: min seconds between same critical alert
NOTIFY_WARNING_INTERVAL=3600     # Dedup: min seconds between same warning
NOTIFY_RATE_LIMIT=10             # Max notifications per hour per channel

# --- Digest ---
NOTIFY_DIGEST_ENABLED=true       # Batch non-critical into digest
NOTIFY_DIGEST_INTERVAL=3600      # Digest frequency (seconds)

# --- Quiet Hours ---
NOTIFY_QUIET_ENABLED=true
NOTIFY_QUIET_START="23:00"       # Only critical alerts after this
NOTIFY_QUIET_END="07:00"         # Morning digest sent at this time

# --- Report ---
NOTIFY_DAILY_REPORT=true         # Send daily health summary
NOTIFY_DAILY_REPORT_TIME="06:00" # When to send daily report
```

### Notification Flow

```
Event Occurs (node down, new version, etc.)
        │
        ▼
   Is it Critical?
   ┌─── Yes ──────────────────────────► Send Immediately
   │                                    (all channels, ignore quiet hours)
   │
   No ── Is Digest Enabled?
         ┌─── Yes ─────► Add to digest buffer
         │                     │
         │               Digest interval reached?
         │               ┌─── Yes ──► Send digest summary
         │               │
         │               No ──► Wait
         │
         No ─── Is Quiet Hours?
                ┌─── Yes ──► Queue for morning
                │
                No ──► Send now
                       │
                       ▼
                  Rate limit OK?
                  ┌─── Yes ──► Deliver to channels
                  │
                  No ──► Log + skip
```

### Platform API Endpoints

The XDC Gateway platform provides these notification endpoints:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/notifications/send` | POST | Send notification |
| `/api/v1/notifications/preferences` | GET/PUT | Get/update user notification preferences |
| `/api/v1/notifications/history` | GET | View past notifications |
| `/api/v1/notifications/test` | POST | Test notification delivery |
| `/api/v1/notifications/unsubscribe` | POST | Unsubscribe from channel |

### Implementation Files

| File | Purpose |
|------|---------|
| `scripts/lib/notify.sh` | Shared notification library (source in scripts) |
| `configs/notify.conf.template` | Configuration template with all options |
| `templates/email/alert.html` | Critical/warning alert email |
| `templates/email/report.html` | Daily health report email |
| `templates/email/digest.html` | Hourly digest email |
| `templates/email/version-update.html` | New version notification |
| `scripts/notify-test.sh` | Test all configured channels |

---

## 8. XDC-Specific Requirements

### XDPoS Consensus
- **Consensus**: XDPoS (Delegated Proof of Stake with XDC modifications)
- **Masternode requirements**: 10,000,000 XDC stake for validator nodes
- **Block time**: ~2 seconds
- **Epoch length**: 900 blocks (~30 minutes)
- **Protocol versions**: eth/62, eth/63, eth/100 (NOT eth/66+)
- **Chain ID**: 50 (Mainnet), 51 (Apothem Testnet)

### Network Configuration

| Network | Chain ID | Bootnodes | Genesis |
|---------|----------|-----------|---------|
| **Mainnet** | 50 | [See mainnet.env](../configs/mainnet.env) | Built into client |
| **Apothem Testnet** | 51 | [See testnet.env](../configs/testnet.env) | Built into client |

### Network Ports

| Port | Protocol | Purpose | Expose? |
|------|----------|---------|---------|
| 30303 | TCP/UDP | P2P networking & discovery | ✅ Public |
| 8545 | TCP | HTTP JSON-RPC | ❌ Internal only |
| 8546 | TCP | WebSocket JSON-RPC | ❌ Internal only |
| 8989 | TCP | Production RPC (custom) | ❌ Internal only |

### Data Directory Structure
```
/root/xdcchain/
├── XDC/
│   ├── chaindata/        # Block + state data (~500GB+ for full node)
│   ├── lightchaindata/   # Light client data
│   └── nodes/            # Peer database
├── keystore/             # Account keys (BACKUP THIS!)
└── genesis.json          # Network genesis config
```

### Recommended Hardware

| Role | CPU | RAM | Disk | Network |
|------|-----|-----|------|---------|
| **Full Node** | 8+ cores | 32 GB | 1 TB NVMe SSD | 1 Gbps |
| **Archive Node** | 16+ cores | 64 GB | 4 TB+ NVMe SSD | 1 Gbps |
| **RPC Node** | 8+ cores | 32 GB | 1 TB NVMe SSD | 10 Gbps |
| **Masternode** | 16+ cores | 32 GB | 1 TB NVMe SSD | 1 Gbps (static IP) |

### XDC Node Command Reference
```bash
# Start node (mainnet)
XDC --datadir /root/xdcchain --networkid 50 \
    --port 30303 --rpc --rpcaddr 127.0.0.1 --rpcport 8545 \
    --rpccorsdomain "*" --rpcapi "eth,net,web3,txpool" \
    --ws --wsaddr 127.0.0.1 --wsport 8546 \
    --syncmode "full" --gcmode "archive"

# Check sync status
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","id":1}' \
  http://127.0.0.1:8545

# Get block number
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}' \
  http://127.0.0.1:8545

# Get peer count
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","id":1}' \
  http://127.0.0.1:8545

# Get client version
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"web3_clientVersion","id":1}' \
  http://127.0.0.1:8545
```

---

## 9. Quick Start

### One-Line Install
```bash
curl -sSL https://raw.githubusercontent.com/AnilChinchawale/XDC-Node-Setup/main/setup.sh | bash
```

### Manual Setup
```bash
# Clone the repository
git clone https://github.com/AnilChinchawale/XDC-Node-Setup.git
cd XDC-Node-Setup

# Run setup
chmod +x setup.sh
./setup.sh

# Harden security
./scripts/security-harden.sh

# Start monitoring
cd docker && docker compose up -d

# Install cron jobs
./cron/setup-crons.sh

# Run first health check
./scripts/node-health-check.sh --full --notify
```

### Docker Deployment
```bash
cd docker
docker compose up -d
```

This starts:
- XDC node (geth-xdc)
- Prometheus (metrics collection)
- Grafana (dashboards on port 3000)
- Node Exporter (system metrics)
- cAdvisor (container metrics)

### Verify Node
```bash
# Check block height
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}' \
  http://127.0.0.1:8545 | jq -r '.result' | xargs printf "%d\n"

# Check peers
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","id":1}' \
  http://127.0.0.1:8545 | jq -r '.result' | xargs printf "%d\n"
```

---

## File Reference

| File | Purpose |
|------|---------|
| `setup.sh` | One-line node installer |
| `scripts/security-harden.sh` | Server security hardening |
| `scripts/node-health-check.sh` | Node monitoring & alerts |
| `scripts/version-check.sh` | Auto-update from GitHub releases |
| `scripts/backup.sh` | Encrypted backup system |
| `configs/versions.json` | Version mapping & tracking |
| `configs/mainnet.env` | Mainnet environment config |
| `configs/testnet.env` | Testnet (Apothem) config |
| `configs/fail2ban.conf` | Fail2ban configuration |
| `configs/sshd_config.template` | Hardened SSH config |
| `configs/firewall.rules` | UFW firewall rules |
| `docker/docker-compose.yml` | Full monitoring stack |
| `monitoring/alerts.yml` | Prometheus alert rules |
| `monitoring/grafana/dashboards/` | Pre-built Grafana dashboards |
| `systemd/xdc-node.service` | Systemd service file |
| `cron/setup-crons.sh` | Cron job installer |

---

## References

- [XDC Network Documentation](https://docs.xdc.community/)
- [XDPoSChain GitHub](https://github.com/XinFinOrg/XDPoSChain)
- [Erigon-XDC GitHub](https://github.com/AnilChinchawale/erigon-xdc)
- [CIS Benchmarks for Ubuntu](https://www.cisecurity.org/benchmark/ubuntu_linux)
- [SOC 2 Compliance Guide](https://www.aicpa.org/soc2)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)

---

## 9. Notification System

> **Implementing script:** [`scripts/lib/notify.sh`](../scripts/lib/notify.sh)
> **Config template:** [`configs/notify.conf.template`](../configs/notify.conf.template)

The XDC Node toolkit includes a comprehensive notification system supporting multiple channels with intelligent features like deduplication, quiet hours, and digest mode.

### Notification Channels

| Channel | Description | Configuration |
|---------|-------------|---------------|
| **Platform API** | XDC Gateway platform (recommended) | `NOTIFY_PLATFORM_API_KEY` |
| **Telegram** | Direct Telegram bot | `NOTIFY_TELEGRAM_BOT_TOKEN`, `NOTIFY_TELEGRAM_CHAT_ID` |
| **Email** | SMTP or platform-based | `NOTIFY_EMAIL_*` settings |

### Platform API (Recommended)

The XDC Gateway platform provides unified notifications without managing your own bot:

1. Register your node at [cloud.xdcrpc.com](https://cloud.xdcrpc.com)
2. Get your API key from the dashboard
3. Set `NOTIFY_PLATFORM_API_KEY` in `/etc/xdc-node/notify.conf`

```bash
NOTIFY_CHANNELS="platform"
NOTIFY_PLATFORM_URL="https://cloud.xdcrpc.com/api/v1/notifications"
NOTIFY_PLATFORM_API_KEY="your-api-key-here"
```

### Direct Telegram Setup

For users who prefer their own Telegram bot:

1. Create a bot via [@BotFather](https://t.me/BotFather)
2. Get your chat ID from [@userinfobot](https://t.me/userinfobot)
3. Configure:

```bash
NOTIFY_CHANNELS="telegram"
NOTIFY_TELEGRAM_BOT_TOKEN="123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
NOTIFY_TELEGRAM_CHAT_ID="123456789"
```

### Email Configuration

Email notifications support two modes:

**Via Platform API:**
```bash
NOTIFY_CHANNELS="platform"
NOTIFY_PLATFORM_API_KEY="your-key"
# Platform handles email delivery
```

**Direct SMTP:**
```bash
NOTIFY_CHANNELS="email"
NOTIFY_EMAIL_ENABLED="true"
NOTIFY_EMAIL_TO="admin@example.com"
NOTIFY_EMAIL_FROM="alerts@xdc.network"
NOTIFY_EMAIL_SMTP_HOST="smtp.gmail.com"
NOTIFY_EMAIL_SMTP_PORT="587"
NOTIFY_EMAIL_SMTP_USER="your-email@gmail.com"
NOTIFY_EMAIL_SMTP_PASS="your-app-password"
```

### Alert Levels

| Level | Description | When Used |
|-------|-------------|-----------|
| **Critical** | Immediate attention required | Node offline, disk >95%, container down |
| **Warning** | Should be addressed soon | Low peers, disk >85%, block behind |
| **Info** | Informational | New version available, backup success |

### Quiet Hours

Configure quiet hours to batch non-critical alerts:

```bash
NOTIFY_QUIET_START="23:00"  # Start of quiet period
NOTIFY_QUIET_END="07:00"    # End of quiet period
NOTIFY_DIGEST_ENABLED="true"
NOTIFY_DIGEST_INTERVAL="3600"  # Digest every hour
```

During quiet hours:
- **Critical alerts** are sent immediately
- **Warning/Info alerts** are batched into a digest
- Digest is sent when quiet hours end

### Alert Deduplication

Prevents alert spam by tracking last alert time per type:

```bash
NOTIFY_ALERT_INTERVAL="300"  # 5 minutes between same alert type
```

State is tracked in `/var/lib/xdc-node/alert-state.json`.

### Rate Limiting

Protects against notification flooding:

```bash
NOTIFY_RATE_LIMIT_PER_HOUR="10"  # Max notifications per hour per channel
```

### Configuration File

Create `/etc/xdc-node/notify.conf`:

```bash
# Notification channels (comma-separated)
NOTIFY_CHANNELS="platform"

# Platform API
NOTIFY_PLATFORM_URL="https://cloud.xdcrpc.com/api/v1/notifications"
NOTIFY_PLATFORM_API_KEY=""

# Direct Telegram (fallback)
NOTIFY_TELEGRAM_BOT_TOKEN=""
NOTIFY_TELEGRAM_CHAT_ID=""

# Email
NOTIFY_EMAIL_ENABLED="false"
NOTIFY_EMAIL_TO=""

# Intervals
NOTIFY_ALERT_INTERVAL="300"
NOTIFY_REPORT_INTERVAL="86400"
NOTIFY_DIGEST_ENABLED="true"
NOTIFY_DIGEST_INTERVAL="3600"

# Quiet hours
NOTIFY_QUIET_START="23:00"
NOTIFY_QUIET_END="07:00"

# Rate limiting
NOTIFY_RATE_LIMIT_PER_HOUR="10"
```

### Testing Notifications

Test your configuration:

```bash
/opt/xdc-node/scripts/notify-test.sh
```

This tests all configured channels and reports which are working.

### Notification Functions

For script developers, the notification library provides:

```bash
# Source the library
source /opt/xdc-node/scripts/lib/notify.sh

# Critical alert (always sends immediately)
notify_alert "critical" "Node Offline" "XDC node is not responding"

# Standard notification (respects deduplication & quiet hours)
notify "warning" "Low Peers" "Only 2 peers connected" "low_peers"

# Periodic report (respects report interval)
notify_report "daily_health" "Health Report" "$report_content"
```

---

## 10. Masternode Operations

> **Implementing script:** [`scripts/masternode-setup.sh`](../scripts/masternode-setup.sh)
> **Guide:** [`docs/MASTERNODE-GUIDE.md`](./MASTERNODE-GUIDE.md)

### Masternode Requirements

| Requirement | Value | Notes |
|-------------|-------|-------|
| **XDC Stake** | 10,000,000 XDC | Locked during masternode operation |
| **KYC** | Required | Complete at master.xinfin.network |
| **Hardware** | 16+ cores, 32GB+ RAM, 1TB NVMe | See hardware requirements |
| **Uptime** | 99.9%+ | Missed blocks affect reputation |

### Masternode Setup Wizard

The setup wizard automates the entire masternode configuration:

```bash
./scripts/masternode-setup.sh
```

Steps performed:
1. System requirements verification
2. XDC balance check (10M+ required)
3. Keystore generation or import
4. Coinbase address configuration
5. Static peer optimization
6. Registration guidance
7. Validator service setup
8. Monitoring configuration

### Epoch and Round Tracking

XDC uses XDPoS consensus with epochs:

- **Epoch Length**: 900 blocks (~30 minutes)
- **Block Time**: ~2 seconds
- **Masternode Count**: 108 validators

Monitor epochs with:

```bash
./scripts/xdc-monitor.sh --epoch
```

### Reward Monitoring

```bash
# Check masternode rewards and status
./scripts/xdc-monitor.sh --rewards

# Continuous monitoring
./scripts/xdc-monitor.sh --continuous
```

### Slashing Prevention

Avoid penalties by:
- Maintaining 99.9%+ uptime
- Keeping software updated
- Never running duplicate validators
- Monitoring for missed blocks

---

## 11. Sync Optimization

> **Implementing script:** [`scripts/sync-optimizer.sh`](../scripts/sync-optimizer.sh)
> **Guide:** [`docs/SYNC-GUIDE.md`](./SYNC-GUIDE.md)

### Sync Mode Selection

| Mode | Disk Space | Sync Time | Use Case |
|------|------------|-----------|----------|
| **Snap** | ~300GB | Hours | Quick setup, RPC nodes |
| **Full** | ~500GB | Days | Validators, production RPC |
| **Archive** | 1-2TB+ | Weeks | Explorers, historical queries |

Auto-recommend based on your hardware:

```bash
./scripts/sync-optimizer.sh recommend
```

### Sync Progress Monitoring

```bash
# Check sync status with ETA
./scripts/sync-optimizer.sh status

# Auto-refresh every 30 seconds
./scripts/sync-optimizer.sh watch
```

### Snapshot Management

Skip initial sync by downloading verified snapshots:

```bash
# List available snapshots
./scripts/snapshot-manager.sh list

# Download and install
./scripts/snapshot-manager.sh download mainnet-full

# Create snapshot from running node
./scripts/snapshot-manager.sh create /backup/snapshots
```

### Chaindata Pruning

When disk space is limited:

```bash
./scripts/sync-optimizer.sh prune
```

### Multi-Client Comparison

If running multiple clients:

```bash
./scripts/sync-optimizer.sh compare
```

---

## 12. Network Intelligence

> **Implementing script:** [`scripts/network-intel.sh`](../scripts/network-intel.sh)

### Peer Geographic Distribution

Map your connected peers by location:

```bash
./scripts/network-intel.sh peers
```

Identifies geographic concentration risks (>66% in one country).

### Upgrade Readiness

Check if your node is ready for upgrades:

```bash
./scripts/network-intel.sh upgrade
```

Verifies:
- Current vs latest client version
- Hard fork block configuration
- Chain ID correctness
- Sync status
- Peer connectivity

### Client Diversity Analysis

Monitor network client distribution:

```bash
./scripts/network-intel.sh diversity
```

Warns if >66% of peers run the same client (centralization risk).

### Network Health Monitoring

```bash
./scripts/network-intel.sh health
```

Reports:
- Average block time (last 100 blocks)
- Block production rate
- Transaction pool status
- Comparison with public RPCs

### Fork Detection

Detect if your node is on a wrong fork:

```bash
./scripts/xdc-monitor.sh --fork
```

Compares local block hashes with multiple public RPCs:
- erpc.xinfin.network
- rpc.xinfin.network
- rpc.xdc.org

### Bootnode Optimization

Improve peer connectivity:

```bash
# Optimize mainnet peers
./scripts/bootnode-optimize.sh

# Optimize testnet peers
./scripts/bootnode-optimize.sh --testnet

# Check for NAT issues
./scripts/bootnode-optimize.sh --nat-check
```

### RPC Security

Harden your RPC endpoint:

```bash
# List available security profiles
./scripts/rpc-security.sh profiles

# Generate Nginx config for public RPC
./scripts/rpc-security.sh generate public

# Audit keystore security
./scripts/rpc-security.sh audit
```

---

*Last updated: February 11, 2026*
*Maintained by: [AnilChinchawale](https://github.com/AnilChinchawale)*
