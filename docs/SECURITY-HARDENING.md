# XDC Node Setup - Security Hardening Guide

## Overview

This guide provides comprehensive security hardening recommendations for XDC Node Setup deployments. Following these practices will help protect your node from common attacks and ensure safe operation.

## Critical Security Issues (Fix Immediately)

### 1. Remove Hardcoded Credentials

**Problem:** Default passwords and API keys are committed to the repository.

**Fix:**
```bash
# Remove .env from git
git rm --cached docker/mainnet/.env
git rm --cached docker/mainnet/.pwd

# Add to .gitignore
echo ".env" >> .gitignore
echo "*.pwd" >> .gitignore

# Generate secure passwords
openssl rand -base64 32  # For Grafana admin
openssl rand -hex 16     # For API keys
```

### 2. Restrict RPC Access

**Problem:** RPC endpoints are exposed to all interfaces with wildcard CORS.

**Fix:**
```bash
# Edit docker/mainnet/.env
RPC_ADDR=127.0.0.1          # Bind to localhost only
WS_ADDR=127.0.0.1
RPC_CORS_DOMAIN="http://localhost:7070"
RPC_VHOSTS="localhost,127.0.0.1"
```

### 3. Secure Docker Configuration

**Problem:** Docker socket mounts and privileged containers create escape risks.

**Fix:**
```yaml
# Remove from docker-compose.yml
# - /var/run/docker.sock:/var/run/docker.sock

# Replace privileged: true with specific capabilities
cap_add:
  - SYS_PTRACE
  - DAC_READ_SEARCH
cap_drop:
  - ALL
security_opt:
  - no-new-privileges:true
```

## Network Security

### Firewall Configuration

```bash
# Allow only necessary ports
sudo ufw default deny incoming
sudo ufw default allow outgoing

# XDC P2P
sudo ufw allow 30303/tcp comment 'XDC P2P'
sudo ufw allow 30303/udp comment 'XDC P2P Discovery'

# Dashboard (if external access needed)
sudo ufw allow from YOUR_IP to any port 7070 comment 'SkyOne Dashboard'

# SSH (restrict to your IP)
sudo ufw allow from YOUR_IP to any port 22 comment 'SSH Admin'

# Enable firewall
sudo ufw enable
```

### SSH Hardening

```bash
# /etc/ssh/sshd_config
Port 2222                          # Non-default port
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

## Authentication & Access Control

### Dashboard Authentication

```bash
# Enable dashboard auth in .env
DASHBOARD_AUTH_ENABLED=true
DASHBOARD_USER=admin
DASHBOARD_PASS=$(openssl rand -base64 16)
```

### API Key Management

```bash
# Generate secure API keys
export SKYNET_API_KEY=$(openssl rand -hex 32)

# Store in secure location (not in git)
echo "SKYNET_API_KEY=$SKYNET_API_KEY" > /etc/xdc-node/skynet.conf
chmod 600 /etc/xdc-node/skynet.conf
```

## Monitoring & Alerting

### Security Monitoring

```bash
# Install fail2ban
sudo apt install fail2ban

# Configure for XDC
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = 2222
filter = sshd
logpath = /var/log/auth.log
EOF

sudo systemctl restart fail2ban
```

### Audit Logging

```bash
# Enable audit logging
cat > /etc/audit/rules.d/xdc.rules <<EOF
-w /etc/xdc-node/ -p wa -k xdc-config-changes
-w /var/lib/xdc-node/ -p wa -k xdc-data-access
-w /usr/local/bin/xdc -p x -k xdc-commands
EOF

sudo augenrules --load
```

## Backup & Recovery

### Secure Backups

```bash
# Encrypt backups
xdc backup create --encrypt --passphrase "$(cat /etc/xdc-node/backup-passphrase)"

# Store offsite
rsync -avz --delete /var/backups/xdc/ user@backup-server:/backups/xdc/
```

### Disaster Recovery

```bash
# Document recovery procedures
cat > /etc/xdc-node/recovery.md <<'EOF'
# XDC Node Recovery Procedures

## Critical Files to Backup
- /etc/xdc-node/skynet.conf
- /var/lib/xdc-node/.state/
- /var/lib/xdc-node/xdcchain/keystore/

## Recovery Steps
1. Restore configuration files
2. Download latest snapshot
3. Start node with xdc start
4. Verify sync status: xdc sync
EOF
```

## Compliance Checklist

- [ ] No secrets in git repository
- [ ] RPC bound to localhost only
- [ ] Firewall enabled with minimal ports
- [ ] SSH key authentication only
- [ ] fail2ban installed and configured
- [ ] Automatic security updates enabled
- [ ] Audit logging enabled
- [ ] Encrypted backups configured
- [ ] Incident response plan documented

## Security Contacts

Report security vulnerabilities to:
- GitHub Security Advisory: https://github.com/AnilChinchawale/xdc-node-setup/security
- Email: security@xdc.network

---

*Last updated: 2026-02-25*
