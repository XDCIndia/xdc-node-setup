# Security Best Practices for XDC Nodes

This document outlines comprehensive security best practices for running XDC Network nodes in production environments.

---

## Table of Contents

1. [Server Hardening Checklist](#1-server-hardening-checklist)
2. [Network Security](#2-network-security)
3. [Key Management](#3-key-management)
4. [Incident Response Plan](#4-incident-response-plan)
5. [Compliance](#5-compliance)

---

## 1. Server Hardening Checklist

### Pre-Deployment

- [ ] **Operating System**
  - [ ] Use Ubuntu 20.04 LTS, 22.04 LTS, or 24.04 LTS
  - [ ] Apply all security patches
  - [ ] Remove unnecessary packages and services
  - [ ] Configure automatic security updates

- [ ] **SSH Configuration**
  - [ ] Change default SSH port (22 → 12141 recommended)
  - [ ] Disable password authentication
  - [ ] Use SSH key pairs only (RSA 4096-bit or Ed25519)
  - [ ] Set `MaxAuthTries 3`
  - [ ] Set `ClientAliveInterval 300`
  - [ ] Use strong cryptographic algorithms
  - [ ] Restrict `AllowUsers` to specific accounts

- [ ] **Firewall (UFW)**
  - [ ] Default deny all incoming
  - [ ] Allow SSH on custom port
  - [ ] Allow XDC P2P (30303/tcp, 30303/udp)
  - [ ] Never expose RPC ports (8545, 8546, 8989) publicly
  - [ ] Enable rate limiting on SSH

- [ ] **Intrusion Detection**
  - [ ] Install and configure fail2ban
  - [ ] Enable auditd for system call monitoring
  - [ ] Configure log aggregation
  - [ ] Set up real-time alerting

### Post-Deployment

- [ ] **Docker Security**
  - [ ] Use official XDC images only
  - [ ] Never run containers as root
  - [ ] Enable Docker Content Trust
  - [ ] Regularly scan images for vulnerabilities
  - [ ] Use read-only filesystems where possible

- [ ] **Monitoring & Alerting**
  - [ ] Configure Prometheus + Grafana
  - [ ] Set up Telegram/Slack alerts
  - [ ] Monitor for unusual activity
  - [ ] Track security-related metrics

- [ ] **Backup Strategy**
  - [ ] Automated daily backups
  - [ ] Encrypted backup storage
  - [ ] Off-site backup replication
  - [ ] Regular backup restoration tests

---

## 2. Network Security

### Port Configuration

| Port | Protocol | Direction | Purpose | Public |
|------|----------|-----------|---------|--------|
| 12141 | TCP | Inbound | SSH | ✅ No (restrict by IP) |
| 30303 | TCP/UDP | Inbound/Outbound | XDC P2P | ✅ Yes |
| 8545 | TCP | Inbound | HTTP RPC | ❌ No (localhost only) |
| 8546 | TCP | Inbound | WebSocket RPC | ❌ No (localhost only) |
| 9090 | TCP | Inbound | Prometheus | ❌ No (localhost only) |
| 3000 | TCP | Inbound | Grafana | ❌ No (tunnel/localhost) |

### DDoS Protection

```bash
# Rate limiting with iptables (in addition to UFW)
iptables -A INPUT -p tcp --dport 30303 -m limit --limit 25/minute --limit-burst 100 -j ACCEPT
iptables -A INPUT -p tcp --dport 30303 -j DROP

# Connection tracking
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
```

### VPN & Private Networking

For production deployments:
- Use private networks between nodes
- Implement VPN for administrative access
- Consider using WireGuard for node-to-node communication

```bash
# WireGuard example configuration
[Interface]
PrivateKey = <server-private-key>
Address = 10.0.0.1/24
ListenPort = 51820

[Peer]
PublicKey = <client-public-key>
AllowedIPs = 10.0.0.2/32
```

---

## 3. Key Management

### Keystore Security

```bash
# Secure keystore directory
chmod 700 /root/xdcchain/keystore
chown -R xdc:xdc /root/xdcchain/keystore

# Encrypt keystore backups
gpg --symmetric --cipher-algo AES256 --compress-algo 1 --s2k-cipher-algo AES256 --s2k-digest-algo SHA512 --s2k-mode 3 --s2k-count 65536 keystore-backup.tar.gz
```

### Hardware Security Modules (HSM)

For production validator nodes:
- Use HSM for key storage (YubiHSM, AWS CloudHSM)
- Never store private keys on disk
- Implement multi-sig for critical operations

### Key Rotation Schedule

| Key Type | Rotation Frequency |
|----------|-------------------|
| SSH keys | Every 90 days |
| API keys | Every 30 days |
| Signing keys | Every 180 days |
| Backup encryption keys | Every 365 days |

---

## 4. Incident Response Plan

### Severity Levels

| Level | Description | Response Time |
|-------|-------------|---------------|
| P0 - Critical | Node compromise, funds at risk | Immediate |
| P1 - High | Node offline, sync issues | 15 minutes |
| P2 - Medium | Performance degradation | 1 hour |
| P3 - Low | Non-critical alerts | 4 hours |

### Incident Response Playbook

#### P0 - Critical Security Incident

1. **Immediate Actions (0-5 minutes)**
   ```bash
   # Isolate the node
   ufw --force reset
   ufw default deny incoming
   ufw default deny outgoing
   systemctl stop xdc-node
   docker stop xdc-node
   ```

2. **Assessment (5-15 minutes)**
   - Review audit logs: `ausearch -ts recent -k admin-commands`
   - Check network connections: `ss -tunap`
   - Analyze process tree: `ps auxf`

3. **Containment (15-30 minutes)**
   - Rotate all credentials
   - Revoke API keys
   - Alert stakeholders via Telegram

4. **Recovery (30+ minutes)**
   - Deploy from known-good backup
   - Apply all security patches
   - Re-enable services incrementally

#### P1 - Node Offline

```bash
# Check service status
systemctl status xdc-node
docker ps | grep xdc-node

# Check logs
journalctl -u xdc -f
docker logs xdc --tail 100

# Restart if needed
docker compose -f /opt/xdc-node/docker/docker-compose.yml restart
```

### Emergency Contacts

- **Security Team**: security@xdc.community
- **On-call Engineer**: Telegram @xdc-oncall
- **Escalation**: +1-XXX-XXX-XXXX

---

## 5. Compliance

### SOC 2 Type II Requirements

| Control | Implementation |
|---------|---------------|
| CC6.1 | Logical access controls, MFA |
| CC6.2 | Encryption at rest (LUKS) and in transit (TLS) |
| CC6.3 | Role-based access control (RBAC) |
| CC6.6 | Intrusion detection (fail2ban, auditd) |
| CC7.1 | Vulnerability scanning |
| CC7.2 | Patch management (unattended-upgrades) |
| A1.2 | Availability monitoring (Prometheus) |

### CIS Benchmarks

Run CIS hardening script:
```bash
curl -sSL https://raw.githubusercontent.com/AnilChinchawale/XDC-Node-Setup/main/scripts/security-harden.sh | bash
```

Key CIS controls implemented:
- 1.1.1 Disable unused filesystems
- 3.1 Network parameters (sysctl hardening)
- 4.2.1 Configure rsyslog
- 5.1 Configure cron
- 5.2 SSH configuration
- 5.3 PAM configuration
- 5.4 User accounts and environment

### Audit Trail

Maintain comprehensive audit logs:
- All administrative commands
- Configuration changes
- Access to sensitive data
- Network connections
- Authentication events

Retention: 1 year minimum, encrypted storage.

---

## References

- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [CIS Ubuntu Benchmarks](https://www.cisecurity.org/benchmark/ubuntu_linux)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [XDC Network Security Guidelines](https://docs.xdc.community/security)
