# XDC-Node-Setup

<p align="center">
  <img src="https://www.xdc.dev/images/logos/site-logo.png" alt="XDC Network" width="200"/>
</p>

<p align="center">
  <strong>Enterprise-grade XDC Network node deployment toolkit</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/Version-2.0.0-green.svg" alt="Version: 2.0.0">
  <img src="https://img.shields.io/badge/Ubuntu-20.04%2F22.04%2F24.04-orange.svg" alt="Ubuntu: 20.04/22.04/24.04">
  <img src="https://img.shields.io/badge/XDC-v2.6.0-blue.svg" alt="XDC: v2.6.0">
  <img src="https://img.shields.io/badge/Standards-Compliant-brightgreen.svg" alt="Standards: Compliant">
</p>

---

## Overview

**XDC-Node-Setup** is a comprehensive toolkit for deploying, securing, and managing XDC Network nodes according to industry-grade infrastructure standards. It provides automated security hardening, continuous monitoring, version management, and compliance reporting.

### Key Features

- 🔒 **Security Hardening** — SSH hardening, firewall, fail2ban, audit logging, disk encryption guidance
- 📊 **Monitoring Stack** — Prometheus + Grafana with pre-configured dashboards and alerts
- 📦 **Version Management** — Automated version checking with optional auto-update
- 🏥 **Health Monitoring** — Continuous health checks with Telegram notifications
- 💾 **Backup & Recovery** — Incremental backups with GPG encryption and retention policies
- 📋 **Compliance Reporting** — Security scorecard and compliance matrix
- 🚀 **One-Line Setup** — Deploy a production-ready XDC node in minutes

---

## 📋 Implementation Status

| Standard | Status | Script/Config |
|----------|--------|---------------|
| SSH Hardening | ✅ Implemented | `security-harden.sh` |
| Firewall (UFW) | ✅ Implemented | `security-harden.sh` |
| Fail2ban | ✅ Implemented | `security-harden.sh` |
| Audit Logging | ✅ Implemented | `security-harden.sh` |
| Sysctl Hardening | ✅ Implemented | `security-harden.sh` |
| Unattended Upgrades | ✅ Implemented | `security-harden.sh` |
| LUKS Guidance | ✅ Implemented | `security-harden.sh` |
| RPC Health Checks | ✅ Implemented | `node-health-check.sh` |
| Block Height Comparison | ✅ Implemented | `node-health-check.sh` |
| Security Score | ✅ Implemented | `node-health-check.sh` |
| Version Checking | ✅ Implemented | `version-check.sh` |
| ETag Caching | ✅ Implemented | `version-check.sh` |
| Auto-Update | ✅ Implemented | `version-check.sh` |
| Incremental Backups | ✅ Implemented | `backup.sh` |
| GPG Encryption | ✅ Implemented | `backup.sh` |
| S3/FTP Upload | ✅ Implemented | `backup.sh` |
| Prometheus Monitoring | ✅ Implemented | `docker-compose.yml` |
| Grafana Dashboards | ✅ Implemented | `docker-compose.yml` |
| Alert Rules | ✅ Implemented | `alerts.yml` |
| Alertmanager | ✅ Implemented | `alertmanager.yml` |
| Cron Jobs | ✅ Implemented | `setup-crons.sh` |

---

## 🚀 Quick Start

### One-Line Installer

```bash
curl -sSL https://raw.githubusercontent.com/AnilChinchawale/XDC-Node-Setup/main/setup.sh | sudo bash
```

### Manual Installation

```bash
git clone https://github.com/AnilChinchawale/XDC-Node-Setup.git
cd XDC-Node-Setup
sudo ./setup.sh
```

### Non-Interactive Mode

```bash
sudo NODE_TYPE=full NETWORK=mainnet ./setup.sh --non-interactive
```

### Implement All Standards

```bash
sudo ./scripts/implement-standards.sh
```

### Configure Notifications

Set up alerts via the XDC Gateway platform (recommended) or direct Telegram:

```bash
# Copy the notification config template
sudo mkdir -p /etc/xdc-node
sudo cp configs/notify.conf.template /etc/xdc-node/notify.conf

# Edit the config with your settings
sudo nano /etc/xdc-node/notify.conf
```

**Option 1: XDC Gateway Platform (Recommended)**
```bash
NOTIFY_CHANNELS="platform"
NOTIFY_PLATFORM_API_KEY="your-api-key-from-cloud.xdcrpc.com"
```

**Option 2: Direct Telegram**
```bash
NOTIFY_CHANNELS="telegram"
NOTIFY_TELEGRAM_BOT_TOKEN="your-bot-token"
NOTIFY_TELEGRAM_CHAT_ID="your-chat-id"
```

**Option 3: Email Notifications**
```bash
NOTIFY_CHANNELS="email"
NOTIFY_EMAIL_ENABLED="true"
NOTIFY_EMAIL_TO="admin@example.com"
NOTIFY_EMAIL_SMTP_HOST="smtp.gmail.com"
NOTIFY_EMAIL_SMTP_USER="your-email@gmail.com"
NOTIFY_EMAIL_SMTP_PASS="your-app-password"
```

Test your notifications:
```bash
./scripts/notify-test.sh
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        XDC Node Infrastructure                               │
└─────────────────────────────────────────────────────────────────────────────┘

                              ┌─────────────────┐
                              │   Internet      │
                              │   (P2P Network) │
                              └────────┬────────┘
                                       │
                              ┌────────▼────────┐
                              │    Firewall     │
                              │    (UFW)        │
                              │  ┌───────────┐  │
                              │  │Port 12141 │──┼──► SSH
                              │  │Port 30303 │──┼──► XDC P2P
                              │  └───────────┘  │
                              └────────┬────────┘
                                       │
┌──────────────────────────────────────┼──────────────────────────────────────┐
│  Docker Network                      │                                       │
│  ┌───────────────────────────────────▼───────────────────────────────────┐  │
│  │                           xdc-network                                  │  │
│  │  ┌─────────────────┐                                                  │  │
│  │  │    XDC Node     │◄──────────────────────────────────────────────┐  │  │
│  │  │  (Port 8545/46) │                                               │  │  │
│  │  │                 │                                               │  │  │
│  │  │ ┌─────────────┐ │         ┌─────────────────────────────────┐  │  │  │
│  │  │ │ Chain Data  │ │         │      xdc-monitoring (internal)  │  │  │  │
│  │  │ │  /xdcchain  │ │         │  ┌───────────┐  ┌───────────┐   │  │  │  │
│  │  │ └─────────────┘ │         │  │Prometheus │  │  Grafana  │   │  │  │  │
│  │  └─────────────────┘         │  │  :9090    │  │   :3000   │   │  │  │  │
│  │                              │  └─────┬─────┘  └─────┬─────┘   │  │  │  │
│  │                              │        │              │         │  │  │  │
│  │                              │  ┌─────▼─────┐  ┌─────▼─────┐   │  │  │  │
│  │                              │  │  Node     │  │ cAdvisor  │   │  │  │  │
│  │                              │  │ Exporter  │  │  :8080    │   │  │  │  │
│  │                              │  │  :9100    │  │           │   │  │  │  │
│  │                              │  └───────────┘  └───────────┘   │  │  │  │
│  │                              └─────────────────────────────────┘  │  │  │
│  └───────────────────────────────────────────────────────────────────┘  │  │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  Scheduled Tasks (Cron)                                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │Health Check │  │Version Check│  │   Backup    │  │Security Scan│         │
│  │  (15 min)   │  │   (6 hrs)   │  │  (Daily 3AM)│  │ (Daily 6AM) │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
│         │                │                │                │                 │
│         └────────────────┴────────────────┴────────────────┘                 │
│                                   │                                          │
│                          ┌────────▼────────┐                                 │
│                          │    Telegram     │                                 │
│                          │   Notifications │                                 │
│                          └─────────────────┘                                 │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 📁 Directory Structure

```
XDC-Node-Setup/
├── configs/                    # Configuration templates
│   ├── versions.json           # Version mapping & auto-update config
│   ├── alertmanager.yml        # Alertmanager configuration
│   ├── mainnet.env             # Mainnet environment
│   ├── testnet.env             # Testnet environment
│   ├── firewall.rules          # UFW rules reference
│   ├── fail2ban.conf           # Fail2ban config
│   └── sshd_config.template    # Hardened SSH config
├── docker/                     # Docker deployment
│   ├── docker-compose.yml      # Full stack compose
│   └── Dockerfile              # XDC node build
├── docs/                       # Documentation
│   ├── XDC-NODE-STANDARDS.md   # Infrastructure standards
│   ├── COMPLIANCE.md           # Compliance matrix
│   ├── SECURITY.md             # Security guide
│   ├── MONITORING.md           # Monitoring guide
│   ├── ARCHITECTURE.md         # Architecture docs
│   └── TROUBLESHOOTING.md      # Troubleshooting guide
├── monitoring/                 # Prometheus & Grafana
│   ├── prometheus.yml          # Prometheus config
│   ├── alerts.yml              # Alert rules
│   └── grafana/                # Grafana provisioning
│       ├── dashboards/         # Dashboard JSON
│       └── datasources.yml     # Datasource config
├── scripts/                    # Utility scripts
│   ├── security-harden.sh      # Security hardening
│   ├── node-health-check.sh    # Health monitoring
│   ├── version-check.sh        # Version management
│   ├── backup.sh               # Backup system
│   └── implement-standards.sh  # Master implementation
├── systemd/                    # Systemd services
│   └── xdc-node.service        # Node service
├── cron/                       # Scheduled tasks
│   └── setup-crons.sh          # Cron installation
├── setup.sh                    # Main installer
├── LICENSE                     # MIT License
└── README.md                   # This file
```

---

## 🔒 Security Scorecard

Each deployment is scored on a 100-point scale:

| Check | Points | Description |
|-------|--------|-------------|
| SSH key-only auth | 10 | `PasswordAuthentication no` |
| Non-standard SSH port | 5 | Port 12141 instead of 22 |
| Firewall active (UFW) | 10 | `ufw status: active` |
| Fail2ban running | 5 | `systemctl is-active fail2ban` |
| Unattended upgrades | 5 | Auto security updates |
| OS patches current | 10 | No pending updates |
| Client version current | 15 | Latest XDC client |
| Monitoring active | 10 | Prometheus + Grafana running |
| Backup configured | 10 | Backup cron + recent backup |
| Audit logging | 10 | Auditd running |
| Disk encryption (LUKS) | 10 | Encrypted volumes |
| **Total** | **100** | |

### Score Interpretation

| Score | Rating | Status |
|-------|--------|--------|
| 90-100 | 🟢 Excellent | Production ready |
| 70-89 | 🟡 Good | Minor improvements needed |
| 50-69 | 🟠 Fair | Significant gaps |
| <50 | 🔴 Poor | Not suitable for production |

---

## 📊 Monitoring & Alerts

### Alert Conditions

| Condition | Severity | Description |
|-----------|----------|-------------|
| Node offline > 5 min | 🔴 Critical | Node not responding |
| Block height behind > 100 | 🟡 Warning | Sync falling behind |
| Peer count = 0 | 🟡 Warning | Network isolation |
| Disk usage > 85% | 🟡 Warning | Storage running low |
| Disk usage > 95% | 🔴 Critical | Immediate action needed |
| CPU > 90% | 🟡 Warning | High resource usage |
| Memory > 90% | 🟡 Warning | Memory pressure |
| New version available | ℹ️ Info | Update available |
| Security score < 70 | 🟡 Warning | Security review needed |

### Grafana Dashboards

- **XDC Node Overview**: Block height, peers, sync status
- **System Metrics**: CPU, RAM, disk, network
- **Container Metrics**: Docker resource usage
- **Alerts History**: Alert timeline and status

---

## 📜 Scripts Reference

### `setup.sh`

Main installer script with interactive and non-interactive modes.

```bash
# Interactive
sudo ./setup.sh

# Non-interactive
sudo NODE_TYPE=full NETWORK=mainnet ./setup.sh --non-interactive
```

### `scripts/security-harden.sh`

Applies all security hardening measures.

```bash
sudo ./scripts/security-harden.sh
```

### `scripts/node-health-check.sh`

Monitors node health and generates reports.

```bash
# Quick check
./scripts/node-health-check.sh

# Full check with notification
./scripts/node-health-check.sh --full --notify

# Security score only
./scripts/node-health-check.sh --security-only
```

### `scripts/version-check.sh`

Checks for and optionally applies updates.

```bash
./scripts/version-check.sh
```

### `scripts/backup.sh`

Creates encrypted backups.

```bash
./scripts/backup.sh
```

### `scripts/implement-standards.sh`

Implements all standards and generates compliance report.

```bash
sudo ./scripts/implement-standards.sh
```

---

## ⚙️ Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `NODE_TYPE` | full, archive, or rpc | full |
| `NETWORK` | mainnet or testnet | mainnet |
| `TELEGRAM_BOT_TOKEN` | Telegram notifications | - |
| `TELEGRAM_CHAT_ID` | Telegram chat ID | - |
| `GRAFANA_ADMIN_PASSWORD` | Grafana password | admin |

### versions.json

```json
{
  "clients": {
    "XDPoSChain": {
      "repo": "XinFinOrg/XDPoSChain",
      "current": "v2.6.0",
      "autoUpdate": false
    }
  }
}
```

### Backup Configuration

Create `/root/.xdc-backup.conf`:

```bash
BACKUP_DIR=/backup/xdc-node
RETENTION_DAILY=7
RETENTION_WEEKLY=4
RETENTION_MONTHLY=12
# GPG_RECIPIENT=your-key-id
# S3_BUCKET=your-bucket
```

---

## 🔧 Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **OS** | Ubuntu 20.04 | Ubuntu 22.04/24.04 |
| **CPU** | 4 cores | 8+ cores |
| **RAM** | 16GB | 32GB+ |
| **Disk** | 500GB SSD | 1TB NVMe SSD |
| **Network** | 100 Mbps | 1 Gbps |

---

## 🤝 Contributing

Contributions are welcome! Please read our contributing guidelines:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit changes: `git commit -am 'Add my feature'`
4. Push to branch: `git push origin feature/my-feature`
5. Submit a Pull Request

### Development Guidelines

- All scripts must have `set -euo pipefail`
- Use shellcheck for linting
- Add logging for all operations
- Include error handling
- Update documentation

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🆘 Support

- **XDC Network Docs**: https://docs.xdc.community/
- **XDPoSChain GitHub**: https://github.com/XinFinOrg/XDPoSChain
- **Issues**: https://github.com/AnilChinchawale/XDC-Node-Setup/issues

---

## 📚 Additional Documentation

- [XDC Node Standards](docs/XDC-NODE-STANDARDS.md) - Complete infrastructure standards
- [Compliance Matrix](docs/COMPLIANCE.md) - Standards to implementation mapping
- [Security Guide](docs/SECURITY.md) - Security best practices
- [Monitoring Guide](docs/MONITORING.md) - Monitoring setup
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues

---

<p align="center">
  Built with ❤️ for the XDC Network community
</p>
