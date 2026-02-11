# XDC Node Operations Runbook

A comprehensive guide for on-call engineers managing XDC Network nodes.

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Node Not Syncing](#node-not-syncing)
3. [Node Crashed](#node-crashed)
4. [Disk Full](#disk-full)
5. [No Peers](#no-peers)
6. [Fork Detected](#fork-detected)
7. [Version Mismatch](#version-mismatch)
8. [Memory Leak](#memory-leak)
9. [DDoS on RPC](#ddos-on-rpc)
10. [Key Compromise](#key-compromise)
11. [Backup Restoration](#backup-restoration)

---

## Quick Reference

### Essential Commands

```bash
# Check node status
systemctl status xdc-node

# View logs
journalctl -u xdc -f
journalctl -u xdc --since "1 hour ago"

# Check sync status
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://localhost:8545 | jq

# Check block number
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545 | jq

# Check peer count
curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://localhost:8545 | jq

# Run health check
./scripts/node-health-check.sh --full

# Restart node gracefully
systemctl restart xdc-node
```

### Important File Locations

| File | Location |
|------|----------|
| Node data | `/xdc-data/` or `/root/XDC-Node/` |
| Logs | `/var/log/xdc/` |
| Config | `/etc/xdc-node/` |
| Systemd service | `/etc/systemd/system/xdc-node.service` |
| Backup | `/backup/xdc-node/` |

---

## Node Not Syncing

### Symptoms
- `eth_syncing` returns `false` but block number is far behind
- Block number stuck at same value for extended period
- Health check shows "sync lag" alert

### Diagnosis

```bash
# 1. Check current block vs network
LOCAL_BLOCK=$(curl -s -X POST localhost:8545 -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result')
echo "Local block: $((16#${LOCAL_BLOCK:2}))"

# 2. Compare with public RPC
PUBLIC_BLOCK=$(curl -s -X POST https://rpc.xdc.org -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result')
echo "Public block: $((16#${PUBLIC_BLOCK:2}))"

# 3. Check peer count
PEERS=$(curl -s -X POST localhost:8545 -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' | jq -r '.result')
echo "Peers: $((16#${PEERS:2}))"

# 4. Check for errors in logs
journalctl -u xdc --since "1 hour ago" | grep -i "error\|failed\|timeout"

# 5. Check disk I/O
iostat -x 1 5

# 6. Check network connectivity
ping -c 5 rpc.xdc.org
```

### Resolution

**If peer count is 0:**
→ See [No Peers](#no-peers)

**If I/O wait is high (>50%):**
```bash
# Check for disk bottleneck
df -h
iotop -o

# If disk is full, see [Disk Full](#disk-full)
# If disk is slow, consider NVMe upgrade
```

**If logs show database corruption:**
```bash
# Stop node
systemctl stop xdc-node

# Backup current data
mv /xdc-data /xdc-data.corrupt.$(date +%Y%m%d)

# Restore from backup or resync
./scripts/backup.sh restore /backup/xdc-node/latest.tar.gz

# Or fast sync from scratch
rm -rf /xdc-data
systemctl start xdc-node
```

**If no obvious issue:**
```bash
# Restart the node
systemctl restart xdc-node

# Wait 10 minutes and recheck
sleep 600
./scripts/node-health-check.sh
```

### Prevention
- Monitor sync lag with alerts
- Regular backup schedule
- Sufficient disk I/O capacity

### Escalation
- If issue persists >2 hours, escalate to senior engineer
- If data corruption suspected, consult with team before data deletion

---

## Node Crashed

### Symptoms
- `systemctl status xdc-node` shows "failed" or "dead"
- Alert: "XDC node not responding"
- No response on RPC port

### Diagnosis

```bash
# 1. Check service status
systemctl status xdc-node

# 2. Check recent logs
journalctl -u xdc -n 500 --no-pager

# 3. Look for OOM kill
dmesg | grep -i "out of memory\|oom\|killed"

# 4. Check disk space
df -h /xdc-data

# 5. Check system resources
free -h
uptime
```

### Resolution

**If OOM killed:**
```bash
# Increase memory limit
systemctl edit xdc-node
# Add:
# [Service]
# MemoryMax=24G

# Restart
systemctl daemon-reload
systemctl start xdc-node
```

**If disk full:**
→ See [Disk Full](#disk-full)

**If segfault/crash:**
```bash
# Check for core dumps
ls -la /var/crash/

# Restart the node
systemctl start xdc-node

# If crashes repeatedly, collect logs and escalate
journalctl -u xdc > /tmp/crash-logs-$(date +%Y%m%d).txt
```

**If config error:**
```bash
# Validate config
cat /etc/systemd/system/xdc-node.service

# Fix config issues
systemctl edit xdc-node

# Restart
systemctl daemon-reload
systemctl start xdc-node
```

### Prevention
- Set appropriate resource limits
- Monitor memory and disk usage
- Keep XDC client updated

### Escalation
- If crash is reproducible, open issue with logs
- If validator, check for missed blocks and notify stakeholders

---

## Disk Full

### Symptoms
- Alert: "Disk usage > 85%"
- Node stops syncing or crashes
- Write operations fail

### Diagnosis

```bash
# 1. Check disk usage
df -h

# 2. Find largest directories
du -sh /xdc-data/* | sort -h | tail -20

# 3. Check for log accumulation
du -sh /var/log/*

# 4. Check for old backups
du -sh /backup/xdc-node/*
```

### Resolution

**Emergency cleanup (>95%):**
```bash
# 1. Stop node if critical
systemctl stop xdc-node

# 2. Clear old logs
journalctl --vacuum-size=500M
rm -f /var/log/*.gz
rm -f /var/log/*.1

# 3. Remove old backups (keep last 3)
cd /backup/xdc-node
ls -t | tail -n +4 | xargs rm -f

# 4. Clear docker if applicable
docker system prune -f

# 5. Restart node
systemctl start xdc-node
```

**If ancient/prunable data:**
```bash
# For XDPoSChain, check pruning options
# Note: Full node requires all data

# Option 1: Extend disk
# AWS: Modify EBS volume
# Hetzner: Add volume

# Option 2: Resync with pruning (if not archive node)
rm -rf /xdc-data
# Configure with gcmode=light
systemctl start xdc-node
```

### Prevention
- Set disk alerts at 70%, 85%, 95%
- Automated log rotation
- Regular cleanup cronjob
- Plan storage growth

### Escalation
- If production impact, notify stakeholders
- If data at risk, prioritize backup before cleanup

---

## No Peers

### Symptoms
- `net_peerCount` returns 0
- Node syncing stops
- Alert: "No peers connected"

### Diagnosis

```bash
# 1. Check peer count
curl -s -X POST localhost:8545 -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'

# 2. Check firewall
ufw status
iptables -L -n

# 3. Check if P2P port is open
ss -tlnp | grep 30303
netstat -an | grep 30303

# 4. Test external connectivity
nc -zv 8.8.8.8 443

# 5. Check bootnodes in config
grep -i bootnode /etc/systemd/system/xdc-node.service
```

### Resolution

**If firewall blocking:**
```bash
# Open P2P port
ufw allow 30303/tcp
ufw allow 30303/udp
ufw reload
```

**If cloud security group:**
```bash
# AWS: Check security group inbound rules
# Hetzner: Check firewall rules
# Ensure 30303 TCP/UDP is allowed from 0.0.0.0/0
```

**If network issue:**
```bash
# Restart networking
systemctl restart networking

# Check DNS
cat /etc/resolv.conf
nslookup rpc.xdc.org
```

**If bootnode issue:**
```bash
# Add static nodes
cat > /xdc-data/static-nodes.json << 'EOF'
[
  "enode://...",
  "enode://..."
]
EOF

# Restart node
systemctl restart xdc-node
```

### Prevention
- Monitor peer count
- Test network changes before applying
- Maintain bootnode list

### Escalation
- If network-wide issue, check XDC community channels
- If hosting provider issue, contact support

---

## Fork Detected

### Symptoms
- Block hash mismatch with network
- Multiple chains detected
- Transactions not confirming

### Diagnosis

```bash
# 1. Get local block hash at specific height
HEIGHT=1000000
curl -s -X POST localhost:8545 -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$(printf '0x%x' $HEIGHT)\",false],\"id\":1}" \
  | jq -r '.result.hash'

# 2. Compare with public RPC
curl -s -X POST https://rpc.xdc.org -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$(printf '0x%x' $HEIGHT)\",false],\"id\":1}" \
  | jq -r '.result.hash'

# 3. Check client version
curl -s -X POST localhost:8545 -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}'
```

### Resolution

**If on wrong fork:**
```bash
# 1. Stop node
systemctl stop xdc-node

# 2. Backup current data (for investigation)
tar -czvf /backup/fork-data-$(date +%Y%m%d).tar.gz /xdc-data

# 3. Clear chain data
rm -rf /xdc-data/XDC/chaindata
rm -rf /xdc-data/XDC/lightchaindata

# 4. Ensure correct version
./scripts/version-check.sh

# 5. Restart and resync
systemctl start xdc-node
```

**If client outdated:**
```bash
# Update to latest version
./scripts/version-check.sh --update

# Restart
systemctl restart xdc-node
```

### Prevention
- Version monitoring alerts
- Automated update checks
- Follow network announcements

### Escalation
- If fork is network-wide, coordinate with XDC community
- Document fork height and circumstances

---

## Version Mismatch

### Symptoms
- Alert: "New XDC client version available"
- Peers rejecting connection
- Protocol mismatch errors

### Diagnosis

```bash
# 1. Check current version
curl -s -X POST localhost:8545 -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}'

# 2. Check latest version
./scripts/version-check.sh --check-only

# 3. Check peer protocol versions
journalctl -u xdc | grep -i "protocol"
```

### Resolution

```bash
# 1. Review changelog for breaking changes
# https://github.com/XinFinOrg/XDPoSChain/releases

# 2. Plan maintenance window (if major update)

# 3. Update using rolling deployment
ansible-playbook playbooks/update-client.yml --limit validator-01

# 4. Verify after update
./scripts/node-health-check.sh --full
```

### Prevention
- Automated version checking (cron)
- Subscribe to release notifications
- Test updates in staging first

### Escalation
- If breaking change, coordinate team-wide update
- If urgent security fix, expedite deployment

---

## Memory Leak

### Symptoms
- Memory usage growing continuously
- OOM kills increasing
- Performance degradation over time

### Diagnosis

```bash
# 1. Check memory usage
free -h
ps aux --sort=-%mem | head -10

# 2. Monitor over time
watch -n 5 'free -h; echo "---"; ps aux --sort=-%mem | head -5'

# 3. Check node memory specifically
systemctl show xdc | grep Memory

# 4. Check for known issues
# Review XDC GitHub issues
```

### Resolution

**Immediate mitigation:**
```bash
# Restart node (temporary fix)
systemctl restart xdc-node

# Schedule regular restarts if needed
echo "0 4 * * * systemctl restart xdc-node" | crontab -
```

**Long-term fix:**
```bash
# 1. Update to latest version (may have fixes)
./scripts/version-check.sh --update

# 2. Adjust cache settings
# Edit service to reduce cache
systemctl edit xdc-node
# [Service]
# Environment="CACHE_SIZE=2048"

# 3. Set memory limits
systemctl edit xdc-node
# [Service]
# MemoryMax=12G
# MemoryHigh=10G
```

### Prevention
- Memory monitoring and alerts
- Regular updates
- Right-size cache for hardware

### Escalation
- Report to XDC team with memory dumps
- Document conditions for reproduction

---

## DDoS on RPC

### Symptoms
- Extremely high request rate
- RPC unresponsive
- CPU/bandwidth maxed out

### Diagnosis

```bash
# 1. Check request rate
# If using nginx
tail -f /var/log/nginx/access.log | pv -l -i10 >/dev/null

# 2. Check connections
ss -s
netstat -an | grep 8545 | wc -l

# 3. Identify attackers
netstat -an | grep 8545 | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head

# 4. Check bandwidth
iftop -i eth0
```

### Resolution

**Immediate mitigation:**
```bash
# 1. Block top offenders
TOP_IPS=$(netstat -an | grep 8545 | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -5 | awk '{print $2}')
for ip in $TOP_IPS; do
  ufw deny from $ip
done

# 2. Enable rate limiting (if nginx)
# In nginx.conf:
# limit_req_zone $binary_remote_addr zone=rpc:10m rate=10r/s;
# limit_req zone=rpc burst=20;

# 3. Restart services
systemctl restart nginx xdc-node
```

**If attack continues:**
```bash
# Enable Cloudflare/WAF
# Move RPC behind authentication
# Implement request signing
```

### Prevention
- Rate limiting on RPC
- Authentication for heavy users
- Use CDN/WAF for public endpoints
- Separate public and internal RPC

### Escalation
- If sustained attack, engage security team
- Consider taking RPC offline temporarily
- Notify users of degraded service

---

## Key Compromise

### Symptoms
- Unauthorized transactions
- Unexpected validator behavior
- Alert from monitoring or user

### Diagnosis

```bash
# 1. Immediately check for unauthorized activity
# Review recent transactions from your addresses

# 2. Check for unauthorized access
last
who
history

# 3. Review auth logs
cat /var/log/auth.log | grep -i "accepted\|failed"

# 4. Check for malware
rkhunter --check
chkrootkit
```

### Resolution

**CRITICAL - Act immediately:**

```bash
# 1. ISOLATE THE SYSTEM
# Disconnect from network if possible (but preserve evidence)

# 2. Revoke/rotate all keys
# For validators: unstake if possible
# Generate new keys on a clean system

# 3. Preserve evidence
tar -czvf /tmp/incident-$(date +%Y%m%d).tar.gz \
  /var/log/ \
  ~/.bash_history \
  /etc/ssh/

# 4. Notify stakeholders
# - Security team
# - Management
# - Users (if their funds affected)
# - Law enforcement (if significant)

# 5. Rebuild from scratch
# Do NOT reuse the compromised system
# Deploy new infrastructure
# Restore data from known-good backup
```

### Prevention
- HSM for validator keys
- Regular security audits
- Principle of least privilege
- MFA everywhere

### Escalation
- **ALWAYS ESCALATE KEY COMPROMISE**
- Security team + management + legal
- Follow incident response plan

---

## Backup Restoration

### Symptoms
- Need to restore from backup after data loss
- Corruption requiring clean start
- Disaster recovery scenario

### Diagnosis

```bash
# 1. List available backups
ls -la /backup/xdc-node/
aws s3 ls s3://bucket/xdc-backups/

# 2. Verify backup integrity
tar -tzf /backup/xdc-node/latest.tar.gz | head

# 3. Check backup timestamp
stat /backup/xdc-node/latest.tar.gz
```

### Resolution

```bash
# 1. Stop the node
systemctl stop xdc-node

# 2. Backup current (possibly corrupt) data
mv /xdc-data /xdc-data.old.$(date +%Y%m%d)

# 3. Create fresh directory
mkdir -p /xdc-data

# 4. Restore from backup
# Local backup:
tar -xzvf /backup/xdc-node/latest.tar.gz -C /

# S3 backup:
aws s3 cp s3://bucket/xdc-backups/latest.tar.gz /tmp/
tar -xzvf /tmp/latest.tar.gz -C /

# Encrypted backup:
gpg --decrypt /backup/xdc-node/latest.tar.gz.gpg | tar -xzv -C /

# 5. Fix permissions
chown -R root:root /xdc-data

# 6. Start node
systemctl start xdc-node

# 7. Monitor sync progress
./scripts/node-health-check.sh --watch

# 8. Verify restoration
# Check block height is increasing
# Check peer connectivity
```

### Prevention
- Regular backup testing (quarterly restore drill)
- Multiple backup locations (3-2-1 rule)
- Backup monitoring and alerts

### Escalation
- If backup is corrupt, escalate immediately
- If no recent backup, consider sync from scratch

---

## Appendix: Contact Information

### Internal Contacts

| Role | Contact | When to Contact |
|------|---------|-----------------|
| On-Call Primary | [PagerDuty] | All incidents |
| On-Call Secondary | [PagerDuty] | No response from primary |
| Team Lead | [Slack] | SEV1/SEV2 |
| CTO | [Phone] | SEV1 only |

### External Resources

| Resource | Link |
|----------|------|
| XDC GitHub | https://github.com/XinFinOrg/XDPoSChain |
| XDC Discord | https://discord.gg/xdc |
| XDC Documentation | https://docs.xdc.community |

---

*Last Updated: 2024*
*Author: XDC Node Setup Team*
