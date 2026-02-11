# XDC Node Infrastructure Compliance Matrix

> This document maps each standard from [XDC-NODE-STANDARDS.md](XDC-NODE-STANDARDS.md) to its implementation in this repository.

## Document Info

| Property | Value |
|----------|-------|
| Version | 2.0.0 |
| Last Updated | 2026-02-11 |
| Standards Version | 1.0 |
| Overall Compliance | ✅ Fully Compliant |

---

## Section 1: Server Security

| Standard | Section | Script/Config | Status | Notes |
|----------|---------|---------------|--------|-------|
| SSH key-only auth | 1.1 | `scripts/security-harden.sh` | ✅ Implemented | `PasswordAuthentication no` |
| Non-standard SSH port | 1.1 | `scripts/security-harden.sh` | ✅ Implemented | Port 12141 |
| MaxAuthTries limit | 1.1 | `scripts/security-harden.sh` | ✅ Implemented | MaxAuthTries 3 |
| AllowUsers restriction | 1.1 | `scripts/security-harden.sh` | ✅ Implemented | AllowUsers root |
| Strong SSH ciphers | 1.1 | `scripts/security-harden.sh` | ✅ Implemented | AES-256-GCM, ChaCha20 |
| UFW deny incoming | 1.2 | `scripts/security-harden.sh` | ✅ Implemented | Default deny |
| UFW allow SSH | 1.2 | `scripts/security-harden.sh` | ✅ Implemented | Port 12141/tcp |
| UFW allow P2P | 1.2 | `scripts/security-harden.sh` | ✅ Implemented | 30303/tcp+udp |
| No public RPC | 1.2 | `scripts/security-harden.sh` | ✅ Implemented | RPC localhost only |
| Fail2ban enabled | 1.3 | `scripts/security-harden.sh` | ✅ Implemented | SSH jail active |
| Fail2ban SSH port | 1.3 | `scripts/security-harden.sh` | ✅ Implemented | Port 12141 |
| Fail2ban maxretry | 1.3 | `scripts/security-harden.sh` | ✅ Implemented | maxretry 3 |
| Fail2ban bantime | 1.3 | `scripts/security-harden.sh` | ✅ Implemented | bantime 3600 |
| LUKS detection | 1.5 | `scripts/security-harden.sh` | ✅ Implemented | Checks lsblk for crypto_LUKS |
| LUKS setup guidance | 1.5 | `scripts/security-harden.sh` | ✅ Implemented | Prints setup instructions |
| Sysctl network hardening | 1.x | `scripts/security-harden.sh` | ✅ Implemented | RP filter, SYN cookies, etc. |
| Sysctl kernel hardening | 1.x | `scripts/security-harden.sh` | ✅ Implemented | Memory, file handles, etc. |

---

## Section 2: Audit & Compliance

| Standard | Section | Script/Config | Status | Notes |
|----------|---------|---------------|--------|-------|
| Auditd installed | 2.2 | `scripts/security-harden.sh` | ✅ Implemented | Auto-install if missing |
| Admin commands audit | 2.2 | `scripts/security-harden.sh` | ✅ Implemented | `-k admin_commands` |
| Chaindata access audit | 2.2 | `scripts/security-harden.sh` | ✅ Implemented | `-k chaindata_access` |
| Auth log audit | 2.2 | `scripts/security-harden.sh` | ✅ Implemented | `-k auth_log` |
| Docker access audit | 2.2 | `scripts/security-harden.sh` | ✅ Implemented | Docker socket monitored |
| User changes audit | 2.2 | `scripts/security-harden.sh` | ✅ Implemented | passwd, shadow, group |
| Privilege escalation audit | 2.2 | `scripts/security-harden.sh` | ✅ Implemented | setuid, setgid |
| Unattended upgrades | 2.x | `scripts/security-harden.sh` | ✅ Implemented | Security updates auto |
| Log retention policy | 2.3 | `cron/setup-crons.sh` | ✅ Implemented | Logrotate configured |

---

## Section 3: Smart Engineering

| Standard | Section | Script/Config | Status | Notes |
|----------|---------|---------------|--------|-------|
| Client diversity support | 3.1 | `configs/versions.json` | ✅ Implemented | XDPoSChain + Erigon-XDC |
| Multi-client versioning | 3.1 | `scripts/version-check.sh` | ✅ Implemented | Checks both repos |
| Health checks | 3.3 | `scripts/node-health-check.sh` | ✅ Implemented | RPC + system metrics |
| Auto-restart capability | 3.3 | `docker-compose.yml` | ✅ Implemented | restart: unless-stopped |
| Watchdog functionality | 3.3 | `cron/setup-crons.sh` | ✅ Implemented | 15-min health checks |

---

## Section 4: Single-Pane Monitoring

| Standard | Section | Script/Config | Status | Notes |
|----------|---------|---------------|--------|-------|
| Block height monitoring | 4.1 | `scripts/node-health-check.sh` | ✅ Implemented | eth_blockNumber |
| Mainnet comparison | 4.1 | `scripts/node-health-check.sh` | ✅ Implemented | erpc.xinfin.network |
| Peer count monitoring | 4.1 | `scripts/node-health-check.sh` | ✅ Implemented | net_peerCount |
| Sync status check | 4.1 | `scripts/node-health-check.sh` | ✅ Implemented | eth_syncing |
| Client version check | 4.1 | `scripts/node-health-check.sh` | ✅ Implemented | web3_clientVersion |
| CPU usage monitoring | 4.1 | `scripts/node-health-check.sh` | ✅ Implemented | /proc/loadavg |
| RAM usage monitoring | 4.1 | `scripts/node-health-check.sh` | ✅ Implemented | free command |
| Disk usage monitoring | 4.1 | `scripts/node-health-check.sh` | ✅ Implemented | df command |
| Security score display | 4.1 | `scripts/node-health-check.sh` | ✅ Implemented | 0-100 scale |
| Prometheus metrics | 4.2 | `docker-compose.yml` | ✅ Implemented | Node + container metrics |
| Grafana dashboards | 4.2 | `monitoring/grafana/dashboards/` | ✅ Implemented | Pre-provisioned |
| Datasource config | 4.2 | `monitoring/grafana/datasources.yml` | ✅ Implemented | Auto-configured |

---

## Section 4: Alert Rules

| Standard | Section | Script/Config | Status | Notes |
|----------|---------|---------------|--------|-------|
| Node offline > 5 min | 4.3 | `monitoring/alerts.yml` | ✅ Implemented | Critical severity |
| Block height behind > 100 | 4.3 | `monitoring/alerts.yml` | ✅ Implemented | Warning severity |
| Peer count = 0 | 4.3 | `monitoring/alerts.yml` | ✅ Implemented | Critical severity |
| Disk > 85% warning | 4.3 | `monitoring/alerts.yml` | ✅ Implemented | Warning severity |
| Disk > 95% critical | 4.3 | `monitoring/alerts.yml` | ✅ Implemented | Critical severity |
| CPU > 90% | 4.3 | `monitoring/alerts.yml` | ✅ Implemented | Warning severity |
| Memory > 90% | 4.3 | `monitoring/alerts.yml` | ✅ Implemented | Warning severity |
| New version available | 4.3 | `monitoring/alerts.yml` | ✅ Implemented | Info severity |
| Security score < 70 | 4.3 | `monitoring/alerts.yml` | ✅ Implemented | Warning severity |
| Telegram notifications | 4.3 | `configs/alertmanager.yml` | ✅ Implemented | Critical immediate |
| Batched warnings | 4.3 | `configs/alertmanager.yml` | ✅ Implemented | 30-min batching |

---

## Section 5: Version Management & Auto-Update

| Standard | Section | Script/Config | Status | Notes |
|----------|---------|---------------|--------|-------|
| versions.json config | 5.1 | `configs/versions.json` | ✅ Implemented | Schema v1 |
| GitHub API queries | 5.2 | `scripts/version-check.sh` | ✅ Implemented | releases/latest |
| ETag caching | 5.2 | `scripts/version-check.sh` | ✅ Implemented | /tmp cache |
| Semver comparison | 5.2 | `scripts/version-check.sh` | ✅ Implemented | sort -V |
| Auto-update option | 5.3 | `scripts/version-check.sh` | ✅ Implemented | autoUpdate flag |
| Test-first deployment | 5.3 | `scripts/version-check.sh` | ✅ Implemented | Rolling restart |
| Telegram notifications | 5.3 | `scripts/version-check.sh` | ✅ Implemented | On new version |
| Version timestamp | 5.3 | `scripts/version-check.sh` | ✅ Implemented | lastChecked field |
| XDPoSChain support | 5.4 | `configs/versions.json` | ✅ Implemented | XinFinOrg/XDPoSChain |
| Erigon-XDC support | 5.4 | `configs/versions.json` | ✅ Implemented | AnilChinchawale/erigon-xdc |
| 6-hour check interval | 5.5 | `cron/setup-crons.sh` | ✅ Implemented | */6 hours |

---

## Section 6: Security Scorecard

| Standard | Section | Script/Config | Status | Notes |
|----------|---------|---------------|--------|-------|
| SSH key-only (10 pts) | 6.1 | `scripts/security-harden.sh` | ✅ Implemented | Checks sshd_config |
| SSH port (5 pts) | 6.1 | `scripts/security-harden.sh` | ✅ Implemented | Port != 22 |
| Firewall (10 pts) | 6.1 | `scripts/security-harden.sh` | ✅ Implemented | UFW active |
| Fail2ban (5 pts) | 6.1 | `scripts/security-harden.sh` | ✅ Implemented | Service active |
| Unattended (5 pts) | 6.1 | `scripts/security-harden.sh` | ✅ Implemented | Package installed |
| OS patches (10 pts) | 6.1 | `scripts/security-harden.sh` | ✅ Implemented | No upgradable |
| Client version (15 pts) | 6.1 | `scripts/node-health-check.sh` | ✅ Implemented | Version check |
| Monitoring (10 pts) | 6.1 | `scripts/node-health-check.sh` | ✅ Implemented | Docker check |
| Backup (10 pts) | 6.1 | `scripts/node-health-check.sh` | ✅ Implemented | Cron check |
| Audit logging (10 pts) | 6.1 | `scripts/node-health-check.sh` | ✅ Implemented | Auditd check |
| Disk encryption (10 pts) | 6.1 | `scripts/security-harden.sh` | ✅ Implemented | LUKS check |
| JSON output | 6.2 | `scripts/security-harden.sh` | ✅ Implemented | security-score.json |
| Human-readable output | 6.2 | `scripts/security-harden.sh` | ✅ Implemented | Console + file |

---

## Section 7: XDC-Specific Requirements

| Standard | Section | Script/Config | Status | Notes |
|----------|---------|---------------|--------|-------|
| P2P port 30303 | 7.2 | `docker-compose.yml` | ✅ Implemented | TCP + UDP |
| RPC port 8545 | 7.2 | `docker-compose.yml` | ✅ Implemented | Internal only |
| WebSocket 8546 | 7.2 | `docker-compose.yml` | ✅ Implemented | Internal only |
| Data directory | 7.3 | `docker-compose.yml` | ✅ Implemented | /root/xdcchain |
| Keystore backup | 7.3 | `scripts/backup.sh` | ✅ Implemented | Encrypted |
| Genesis config | 7.3 | `setup.sh` | ✅ Implemented | Downloaded |
| Node types (full/archive/rpc) | 7.4 | `setup.sh` | ✅ Implemented | Interactive selection |

---

## Section 8: Quick Start

| Standard | Section | Script/Config | Status | Notes |
|----------|---------|---------------|--------|-------|
| One-line setup | 8.1 | `setup.sh` | ✅ Implemented | curl pipe bash |
| Interactive mode | 8.1 | `setup.sh` | ✅ Implemented | Node type selection |
| Non-interactive mode | 8.1 | `setup.sh` | ✅ Implemented | --non-interactive |
| Health check command | 8.2 | `scripts/node-health-check.sh` | ✅ Implemented | --full --notify |
| Security check | 8.3 | `scripts/node-health-check.sh` | ✅ Implemented | --security-only |

---

## Backup System

| Standard | Section | Script/Config | Status | Notes |
|----------|---------|---------------|--------|-------|
| Chain data backup | - | `scripts/backup.sh` | ✅ Implemented | Incremental rsync |
| Keystore backup | - | `scripts/backup.sh` | ✅ Implemented | Encrypted |
| Config backup | - | `scripts/backup.sh` | ✅ Implemented | Tar archive |
| Genesis backup | - | `scripts/backup.sh` | ✅ Implemented | Copied |
| GPG encryption | - | `scripts/backup.sh` | ✅ Implemented | Optional |
| S3 upload | - | `scripts/backup.sh` | ✅ Implemented | Optional |
| FTP upload | - | `scripts/backup.sh` | ✅ Implemented | Optional |
| 7 daily retention | - | `scripts/backup.sh` | ✅ Implemented | Configurable |
| 4 weekly retention | - | `scripts/backup.sh` | ✅ Implemented | Configurable |
| 12 monthly retention | - | `scripts/backup.sh` | ✅ Implemented | Configurable |
| Integrity verification | - | `scripts/backup.sh` | ✅ Implemented | tar test / gpg check |
| Config file support | - | `scripts/backup.sh` | ✅ Implemented | /root/.xdc-backup.conf |

---

## Cron Jobs

| Standard | Section | Script/Config | Status | Notes |
|----------|---------|---------------|--------|-------|
| Health check 15 min | - | `cron/setup-crons.sh` | ✅ Implemented | */15 * * * * |
| Version check 6 hrs | - | `cron/setup-crons.sh` | ✅ Implemented | 17 */6 * * * |
| Full report daily 6 AM | - | `cron/setup-crons.sh` | ✅ Implemented | 0 6 * * * |
| Backup daily 3 AM | - | `cron/setup-crons.sh` | ✅ Implemented | 0 3 * * * |
| Weekly backup Sun 2 AM | - | `cron/setup-crons.sh` | ✅ Implemented | 0 2 * * 0 |
| Log rotation | - | `cron/setup-crons.sh` | ✅ Implemented | Weekly |

---

## Summary

| Category | Total Items | Implemented | Percentage |
|----------|-------------|-------------|------------|
| Server Security | 17 | 17 | 100% |
| Audit & Compliance | 9 | 9 | 100% |
| Smart Engineering | 5 | 5 | 100% |
| Monitoring | 12 | 12 | 100% |
| Alert Rules | 11 | 11 | 100% |
| Version Management | 11 | 11 | 100% |
| Security Scorecard | 13 | 13 | 100% |
| XDC-Specific | 7 | 7 | 100% |
| Quick Start | 5 | 5 | 100% |
| Backup System | 12 | 12 | 100% |
| Cron Jobs | 6 | 6 | 100% |
| **TOTAL** | **108** | **108** | **100%** |

---

## Verification Commands

### Check Security Score

```bash
/opt/xdc-node/scripts/node-health-check.sh --security-only
cat /opt/xdc-node/reports/security-score.json
```

### Check Compliance

```bash
/opt/xdc-node/scripts/implement-standards.sh
cat /opt/xdc-node/reports/compliance-*.json | jq .
```

### Verify Services

```bash
# Check Docker containers
docker compose -f /opt/xdc-node/docker/docker-compose.yml ps

# Check cron jobs
cat /etc/cron.d/xdc-node

# Check firewall
ufw status verbose

# Check fail2ban
fail2ban-client status sshd

# Check auditd
auditctl -l
```

---

*This compliance matrix is automatically verified by `implement-standards.sh`*
