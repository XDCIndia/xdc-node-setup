# XDC Erigon Documentation Index

Complete documentation for XDC Network on Erigon client.

---

## 📚 **Documentation Overview**

| Document | Size | Purpose |
|----------|------|---------|
| [README.md](./README.md) | 5.3 KB | Quick start guide + features |
| [UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md) | 7.7 KB | Go 1.22 → 1.24 upgrade process |
| [erigon-upgrade-advisory.md](./erigon-upgrade-advisory.md) | 9.1 KB | Executive upgrade advisory |
| [erigon-performance-report.md](./erigon-performance-report.md) | 7.3 KB | Multi-server performance analysis |
| [docker-compose.yml](./docker-compose.yml) | 1.8 KB | Production deployment config |

**Total Documentation:** 31.2 KB across 5 files

---

## 🚀 **Quick Start (I'm New)**

1. **Read first:** [README.md](./README.md)
   - What is XDC Erigon
   - Features and benefits
   - Quick start commands
   - Port configurations
   - Basic troubleshooting

2. **Build your first node:**
   ```bash
   cd docker/erigon
   docker build -t xdc-erigon .
   docker-compose up -d
   ```

3. **Verify it's working:**
   ```bash
   curl -X POST http://localhost:8545 \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
   ```

---

## 🔧 **Maintenance (I'm Operating Nodes)**

### Monitoring

**Check sync status:**
```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' | jq .
```

**Monitor resources:**
```bash
docker stats xdc-node-erigon
```

**View logs:**
```bash
docker logs -f xdc-node-erigon
```

### Performance Analysis

Read: [erigon-performance-report.md](./erigon-performance-report.md)
- Current status of all nodes
- Sync speed estimates
- Resource usage recommendations
- Troubleshooting common issues

---

## 📈 **Upgrading (Go 1.22 → 1.24)**

### If you have Go 1.22 nodes:

1. **Read upgrade advisory first:**  
   [erigon-upgrade-advisory.md](./erigon-upgrade-advisory.md)
   - Executive summary
   - Risk assessment (Very Low)
   - Deployment strategy
   - Testing checklist

2. **Follow detailed guide:**  
   [UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md)
   - Step-by-step upgrade process
   - Dependency version matrix
   - Rollback plan
   - Monitoring commands

3. **Test on non-production first:**
   ```bash
   git pull origin main
   cd docker/erigon
   docker build -t xdc-erigon:go124 .
   # Run e2e tests
   cd ../../tests/e2e
   ./test-erigon-docker.sh
   ```

---

## 📊 **Performance Reports**

### Current Node Status

Read: [erigon-performance-report.md](./erigon-performance-report.md)

**Quick Summary:**
- ✅ **1 erigon node syncing** (GCX: 8 peers, 334K blocks)
- ❌ **2 erigon nodes down** (168 server: 0 peers)
- ❌ **1 macOS node offline** (24h no heartbeat)

**Key Findings:**
- GCX performing well (8 peers, progressing sync)
- 168 nodes need restart (containers stopped)
- Erigon sync time estimate: 3-5 days on SSD

---

## 🏗️ **Architecture & Design**

### Multi-Stage Docker Build

```
Stage 1 (builder):
  - golang:1.24-bookworm base
  - Clone XDC erigon fork
  - Build erigon binary
  - Cross-compilation support

Stage 2 (runtime):
  - debian:12-slim base (~200MB final)
  - Copy binary only
  - Non-root user (erigon:1000)
  - Security hardened
```

### Port Layout

| Port | Protocol | Purpose |
|------|----------|---------|
| 8545 | TCP | HTTP RPC API |
| 8551 | TCP | Engine API (authrpc) |
| 30303 | TCP/UDP | P2P discovery |
| 30304 | TCP/UDP | Sentry (eth/63, XDC mainnet) |
| 30311 | TCP/UDP | Sentry (eth/68, modern clients) |
| 9090 | TCP | gRPC diagnostics |
| 6060 | TCP | Metrics (pprof) |

### XDC-Specific Modifications

1. **Clone XDC fork:** `github.com/AnilChinchawale/erigon-xdc`
2. **Go 1.24.0:** Production standard
3. **Dual P2P sentries:** eth/63 (port 30304) + eth/68 (port 30311)
4. **Data directory:** `/work/xdcchain`
5. **State root bypass:** XDC chainspec differences handled

---

## 🧪 **Testing**

### E2E Test Suite

Located at: `../../tests/e2e/test-erigon-docker.sh`

**Tests:**
1. ✅ Docker image builds successfully
2. ✅ Container starts without errors
3. ✅ RPC responds to eth_blockNumber
4. ✅ admin_nodeInfo available
5. ✅ Sync status working
6. ⏳ Peer count (optional, requires time)
7. ✅ No critical errors in logs
8. ✅ Data directory created
9. ✅ Health check passes

**Run tests:**
```bash
cd tests/e2e
./test-erigon-docker.sh
```

---

## 🐛 **Troubleshooting**

### Common Issues

#### 1. Container exits immediately
```bash
docker logs xdc-node-erigon
# Common causes:
# - Corrupted data → delete and resync
# - Port conflicts → check with netstat
# - Permissions → chown to UID 1000
```

#### 2. Zero peers (no P2P connectivity)
```bash
# Check firewall
sudo ufw allow 30303
sudo ufw allow 30304

# Check enode
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' \
  | jq .result.enode
```

#### 3. Sync stalled
```bash
# Check peer count
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'

# If zero peers, auto-inject from SkyNet
# (requires SkyNet agent integration)
```

#### 4. High CPU/memory
```bash
# Limit resources in docker-compose.yml
deploy:
  resources:
    limits:
      cpus: '4'
      memory: 16G
```

**Full troubleshooting:** See [README.md](./README.md#troubleshooting)

---

## 🔒 **Security**

### Best Practices

1. **Non-root user:** Container runs as `erigon:erigon` (UID 1000)
2. **Minimal base:** Debian slim (~200MB vs 2GB+)
3. **Read-only filesystem:** (Optional, can enable in compose)
4. **No password auth:** Use SSH keys for server access
5. **Firewall:** Only expose necessary ports
6. **Health checks:** Auto-restart on failure

### Security Scanning

```bash
# Scan dependencies
go install golang.org/x/vuln/cmd/govulncheck@latest
govulncheck ./...

# Scan Docker image
docker scan xdc-erigon
```

---

## 🚨 **Incident Response**

### Node Down

1. **Check container:**
   ```bash
   docker ps -a | grep erigon
   docker logs xdc-node-erigon --tail 100
   ```

2. **Check system:**
   ```bash
   df -h  # Disk space
   free -h  # Memory
   top  # CPU usage
   ```

3. **Restart if safe:**
   ```bash
   docker restart xdc-node-erigon
   ```

4. **If data corrupted:**
   ```bash
   docker stop xdc-node-erigon
   rm -rf /path/to/data/chaindata
   docker start xdc-node-erigon  # Will resync
   ```

### Zero Peers

1. **Check firewall:**
   ```bash
   sudo ufw status
   sudo iptables -L -n | grep 30303
   ```

2. **Auto-inject peers:**
   ```bash
   # Via SkyNet agent (recommended)
   bash /path/to/skynet-agent.sh --add-peers
   
   # Manual (from SkyNet API)
   curl https://net.xdc.network/api/v1/peers/healthy?limit=20
   ```

3. **Verify connectivity:**
   ```bash
   nc -zv [peer-ip] 30303
   ```

---

## 📖 **Further Reading**

### External Resources

- **Upstream Erigon:** https://github.com/erigontech/erigon
- **Erigon Docs:** https://erigon.tech
- **XDC Network:** https://xdc.network
- **XDC Docs:** https://docs.xdc.network
- **SkyNet Platform:** https://net.xdc.network

### Internal Resources

- **xdc-node-setup:** https://github.com/AnilChinchawale/xdc-node-setup
- **erigon-xdc fork:** https://github.com/AnilChinchawale/erigon-xdc
- **SkyNet Dashboard:** https://net.xdc.network

---

## 🤝 **Contributing**

### Reporting Issues

1. Check existing issues first
2. Include version info: `docker inspect xdc-erigon | jq '.[0].Config.Labels'`
3. Attach logs: `docker logs xdc-node-erigon > erigon.log`
4. Describe steps to reproduce

**GitHub Issues:** https://github.com/AnilChinchawale/xdc-node-setup/issues

### Updating Documentation

1. Edit files in `docker/erigon/`
2. Run spell check: `aspell check *.md`
3. Commit with descriptive message
4. Update this index if adding new docs

---

## 📝 **Version History**

| Date | Version | Changes |
|------|---------|---------|
| 2026-02-15 | v1.2 | Go 1.24 upgrade, comprehensive docs |
| 2026-02-14 | v1.1 | macOS fixes, E2E tests |
| 2026-02-13 | v1.0 | Initial production release |

**Current Version:** v1.2 (Go 1.24.0 production)

---

## 📞 **Support**

### Getting Help

1. **Documentation:** Start here (this index)
2. **GitHub Issues:** https://github.com/AnilChinchawale/xdc-node-setup/issues
3. **Telegram:** @AnilChinchawale
4. **Discord:** https://discord.com/invite/clawd (OpenClaw community)

### Emergency Contact

For critical production issues:
- Telegram: @AnilChinchawale
- Email: anil24593@gmail.com

---

## 🎯 **Quick Reference Card**

**Build:**
```bash
docker build -t xdc-erigon .
```

**Run:**
```bash
docker-compose up -d
```

**Status:**
```bash
curl -s -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' | jq .
```

**Logs:**
```bash
docker logs -f xdc-node-erigon
```

**Stop:**
```bash
docker-compose down
```

---

**Documentation Version:** 1.2  
**Last Updated:** 2026-02-15  
**Maintained By:** Anil Chinchawale
