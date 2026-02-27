# XDC Node Setup - Security Hardening Guide

## Overview

This guide provides comprehensive security hardening recommendations for XDC Node Setup deployments.

## Critical Security Fixes

### 1. Remove Hardcoded Credentials

**Problem:** Default credentials committed to repository

**Solution:**
```bash
# Remove .env from git
git rm --cached docker/mainnet/.env docker/mainnet/.pwd
git commit -m "security: remove hardcoded credentials"

# Add to .gitignore
echo "docker/mainnet/.env" >> .gitignore
echo "docker/mainnet/.pwd" >> .gitignore

# Create template
cp docker/mainnet/.env docker/mainnet/.env.example
# Edit to remove real values
```

### 2. Secure RPC Configuration

**Problem:** RPC exposed to all interfaces with open CORS

**Solution:**
```yaml
# docker-compose.yml
services:
  xdc-node:
    ports:
      - "127.0.0.1:8545:8545"  # Bind to localhost only
    environment:
      - RPC_CORS_DOMAIN=http://localhost:7070  # Specific origin
      - RPC_VHOSTS=localhost
```

### 3. Docker Security Hardening

**Problem:** Privileged containers and docker socket mounts

**Solution:**
```yaml
services:
  xdc-node:
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETGID
      - SETUID
    read_only: true
    tmpfs:
      - /tmp:nosuid,size=100m
```

## Network Security

### Firewall Configuration

```bash
# Default deny incoming
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (change from default 22)
sudo ufw allow 2222/tcp comment 'SSH'

# Allow XDC P2P
sudo ufw allow 30303/tcp comment 'XDC P2P'
sudo ufw allow 30303/udp comment 'XDC P2P UDP'

# RPC is localhost-only, no external access needed
# Dashboard access (if needed externally)
sudo ufw allow from YOUR_IP to any port 7070
```

### SSH Hardening

```bash
# /etc/ssh/sshd_config
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

## Monitoring Security

### Prometheus/Grafana

```yaml
services:
  prometheus:
    ports:
      - "127.0.0.1:9090:9090"  # Localhost only
    
  grafana:
    ports:
      - "127.0.0.1:3000:3000"  # Localhost only
    environment:
      - GF_SECURITY_ADMIN_PASSWORD__FILE=/run/secrets/grafana_password
    secrets:
      - grafana_password

secrets:
  grafana_password:
    file: ./secrets/grafana_password.txt
```

## Secrets Management

### Docker Secrets (Swarm Mode)

```yaml
# docker-compose.yml (swarm)
secrets:
  rpc_password:
    external: true
  
services:
  xdc-node:
    secrets:
      - source: rpc_password
        target: /run/secrets/rpc_password
```

### Environment Variables

```bash
# .env file (never commit!)
RPC_PASSWORD=$(openssl rand -base64 32)
GRAFANA_PASSWORD=$(openssl rand -base64 32)
```

## Audit and Compliance

### Enable Audit Logging

```bash
# Install auditd
sudo apt-get install auditd

# Configure XDC node auditing
sudo auditctl -w /root/xdcchain/ -p rwxa -k xdc-data
sudo auditctl -w /etc/xdc-node/ -p rwxa -k xdc-config
```

### Security Scanning

```bash
# Run security scan
./scripts/security-harden.sh --check

# Docker security scan
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image xinfinorg/xdposchain:v2.6.8
```

## Incident Response

### Compromised Node Response

1. **Isolate the node**
   ```bash
   sudo ufw deny incoming
   sudo ufw allow out on eth0 to any
   ```

2. **Stop containers**
   ```bash
   docker compose down
   ```

3. **Rotate keys**
   - Generate new wallet
   - Update masternode registration
   - Notify network operators

4. **Forensics**
   ```bash
   # Collect logs
   docker logs xdc-node > /tmp/xdc-logs-$(date +%s).txt
   
   # Check for unauthorized access
   grep -i "error\|fail\|unauthorized" /var/log/xdc/*.log
   ```

## Security Checklist

- [ ] Credentials removed from git
- [ ] RPC bound to localhost
- [ ] CORS restricted to specific origins
- [ ] Firewall enabled (UFW)
- [ ] SSH on non-standard port
- [ ] Root login disabled
- [ ] Docker containers non-privileged
- [ ] No docker.sock mounts (unless essential)
- [ ] Secrets management implemented
- [ ] Audit logging enabled
- [ ] Regular security scans scheduled
- [ ] Incident response plan documented

## References

- [OWASP Docker Security](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [XDC Security Best Practices](https://docs.xdc.community/)

---

**Last Updated:** 2026-02-27  
**Version:** 1.0.0
