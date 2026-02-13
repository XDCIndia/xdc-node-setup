# Troubleshooting Guide for XDC Node Setup

This guide helps you diagnose and resolve common issues with XDC Node Setup.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Docker Issues](#docker-issues)
- [Sync Issues](#sync-issues)
- [Network Issues](#network-issues)
- [Performance Issues](#performance-issues)
- [Security Issues](#security-issues)
- [API/RPC Issues](#apirpc-issues)
- [Backup/Restore Issues](#backuprestore-issues)
- [Getting Help](#getting-help)

---

## Installation Issues

### "Permission denied" when running setup.sh

**Cause:** Script doesn't have execute permissions or user lacks privileges.

**Solution:**
```bash
chmod +x setup.sh
sudo ./setup.sh
```

### "Command not found: docker"

**Cause:** Docker is not installed or not in PATH.

**Solution:**
```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

### "Unsupported OS" error

**Cause:** Operating system not officially supported.

**Solution:**
- Supported: Ubuntu 20.04/22.04/24.04, Debian 11/12, macOS 12+
- For other systems, use Docker deployment method

---

## Docker Issues

### Container fails to start

**Check logs:**
```bash
docker logs xdc-node
```

**Common causes:**
1. Port already in use
   ```bash
   sudo lsof -i :8545  # Check what's using the port
   sudo systemctl stop <service>
   ```

2. Volume permissions
   ```bash
   sudo chown -R $(id -u):$(id -g) ./xdcchain
   ```

3. Out of disk space
   ```bash
   df -h
   docker system prune -a  # Clean up unused images
   ```

### "No such file or directory" for genesis.json

**Solution:**
```bash
# Ensure proper file structure
mkdir -p mainnet
cp configs/genesis.json mainnet/
```

---

## Sync Issues

### Node stuck at block 0

**Diagnosis:**
```bash
# Check peer count
curl -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://localhost:8545

# Expected: 0x5 (at least 5 peers)
```

**Solutions:**
1. Check firewall rules
2. Verify bootstrap nodes in bootnodes.list
3. Restart with clean sync:
   ```bash
   docker-compose down
   rm -rf xdcchain/XDC
   docker-compose up -d
   ```

### Sync is very slow

**Causes:**
- Insufficient hardware resources
- Slow disk I/O
- Network latency

**Solutions:**
1. Check resources:
   ```bash
   # Monitor during sync
   iostat -x 5  # Check disk I/O
   top          # Check CPU/memory
   ```

2. Use SSD/NVMe storage
3. Increase cache:
   ```yaml
   # docker-compose.yml
   environment:
     - --cache=4096
   ```

### "Ancient block chain prune" warning

**Cause:** Normal operation for ancient data pruning.

**Solution:** No action needed unless disk is full.

---

## Network Issues

### Cannot connect to RPC endpoint

**Check:**
```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

**Common fixes:**
1. Check if container is running:
   ```bash
   docker ps | grep xdc-node
   ```

2. Verify port binding:
   ```bash
   docker port xdc-node
   ```

3. Check firewall:
   ```bash
   sudo ufw status
   sudo ufw allow 8545/tcp
   ```

### Peers disconnect frequently

**Causes:**
- Clock drift
- NAT issues
- Unstable network

**Solutions:**
1. Sync system clock:
   ```bash
   sudo apt-get install ntp
   sudo systemctl enable ntp
   ```

2. Configure port forwarding for 30303/tcp and 30303/udp
3. Use static IP or DDNS

---

## Performance Issues

### High CPU usage

**Diagnosis:**
```bash
# Identify process
ps aux | grep -E "XDC|xdc"

# Check sync status
./scripts/node-health-check.sh --full
```

**Solutions:**
1. Limit CPU usage:
   ```yaml
   # docker-compose.yml
   deploy:
     resources:
       limits:
         cpus: '4.0'
   ```

2. Reduce peer count:
   ```bash
   # In start-node.sh
   --maxpeers 25
   ```

### High memory usage

**Solutions:**
1. Reduce cache size
2. Limit concurrent connections
3. Add swap space (emergency only):
   ```bash
   sudo fallocate -l 8G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

### Disk space issues

**Check:**
```bash
du -sh xdcchain/* | sort -h
```

**Solutions:**
1. Enable pruning (if not archive node)
2. Move data to larger disk
3. Set up automated cleanup:
   ```bash
   ./scripts/cleanup-logs.sh
   ```

---

## Security Issues

### SSH brute force attacks

**Symptoms:**
- Many failed login attempts in `/var/log/auth.log`

**Solution:**
```bash
# Run security hardening
sudo ./scripts/security-harden.sh

# Check fail2ban status
sudo fail2ban-client status sshd
```

### Unauthorized RPC access

**Symptoms:**
- Unknown transactions
- Unexpected API calls

**Solution:**
1. Enable authentication
2. Bind to localhost only:
   ```yaml
   ports:
     - "127.0.0.1:8545:8545"
   ```
3. Use firewall to restrict access

### Certificate errors

**Solution:**
```bash
# Regenerate certificates
sudo ./scripts/regenerate-certs.sh
```

---

## API/RPC Issues

### "Method not found" error

**Cause:** API namespace not enabled

**Solution:**
```bash
# Enable required APIs
# In start-node.sh, add to --rpcapi:
--rpcapi eth,net,web3,admin,debug
```

### CORS errors from browser

**Solution:**
```bash
# Add allowed origins
--rpccorsdomain "http://localhost:3000,https://myapp.com"
```

### Rate limiting issues

**Symptoms:**
- 429 Too Many Requests errors

**Solution:**
1. Implement client-side rate limiting
2. Increase limits (if self-hosted):
   ```yaml
   # In docker-compose.yml
   --rpcrps 1000
   ```

---

## Backup/Restore Issues

### Backup fails with "permission denied"

**Solution:**
```bash
# Fix permissions
sudo chown -R $(whoami) /opt/xdc-node/backups

# Run backup with sudo
sudo ./scripts/backup.sh create
```

### Restore fails with "corrupted data"

**Causes:**
- Incomplete backup
- Version mismatch
- Wrong network

**Solution:**
1. Verify backup integrity:
   ```bash
   ./scripts/backup.sh verify <backup-file>
   ```

2. Check version compatibility
3. Ensure correct network type

### Encrypted backup won't decrypt

**Solutions:**
1. Verify you have the correct key
2. Check if key rotation occurred
3. Use backup key rotation script:
   ```bash
   ./scripts/rotate-backup-keys.sh list
   ```

---

## Getting Help

### Collect diagnostic information

```bash
# Run diagnostic script
./scripts/diagnostics.sh

# Or manually collect:
- OS version: lsb_release -a
- Docker version: docker version
- Node logs: docker logs xdc-node
- System resources: free -h, df -h
- Network: netstat -tlnp, iptables -L
```

### Community Support

- **Discord:** https://discord.gg/xdc
- **GitHub Issues:** https://github.com/XinFinOrg/XDC-Node-Setup/issues
- **Documentation:** https://docs.xdc.network

### Emergency Contacts

For security issues: security@xdc.dev

### Debug Mode

Enable debug logging:
```bash
export DEBUG=1
export LOG_LEVEL=DEBUG
./setup.sh
```

---

## Quick Reference

### Common Commands

```bash
# Check node status
curl http://localhost:8545 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'

# View logs
docker logs -f xdc-node --tail 100

# Restart node
docker-compose restart xdc-node

# Health check
./scripts/node-health-check.sh --full

# Update node
./scripts/version-check.sh --update
```

### Important File Locations

| File/Directory | Purpose |
|---------------|---------|
| `/opt/xdc-node/` | Installation directory |
| `/opt/xdc-node/mainnet/xdcchain/` | Blockchain data |
| `/opt/xdc-node/logs/` | Log files |
| `/opt/xdc-node/backups/` | Backup storage |
| `/opt/xdc-node/configs/` | Configuration files |
| `/var/log/xdc-node/` | System logs |

### Default Ports

| Port | Service | Protocol |
|------|---------|----------|
| 8545 | RPC | HTTP |
| 8546 | WebSocket | WS |
| 30303 | P2P | TCP/UDP |
| 12141 | SSH (hardened) | TCP |
| 9090 | Prometheus | HTTP |
| 3000 | Grafana | HTTP |