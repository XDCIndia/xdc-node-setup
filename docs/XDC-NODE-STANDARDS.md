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
7. [XDC-Specific Requirements](#7-xdc-specific-requirements)
8. [Quick Start](#8-quick-start)

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

## 7. XDC-Specific Requirements

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

## 8. Quick Start

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

*Last updated: February 11, 2026*
*Maintained by: [AnilChinchawale](https://github.com/AnilChinchawale)*
