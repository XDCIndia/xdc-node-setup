# XDC Unified Agent v2 - Quick Reference Card

## 🎯 What's New in Phase 2?

| Feature | What It Does | Benefit |
|---------|-------------|---------|
| **Cross-Node Correlation** | Checks if ALL nodes have same issue | Prevents mass-restart during code bugs |
| **Smart Restart Logic** | Tracks restart effectiveness | Stops ineffective restart loops |
| **Intelligent Peer Mgmt** | Auto-injects healthy peers | Fixes peer isolation issues |
| **Trend Analysis** | Detects sync deceleration | Early warning before stall |
| **Network Height Aware** | Knows real network tip | Accurate sync percentage |
| **Hourly Diagnostics** | Self-assessment reports | Proactive health monitoring |

---

## 🔍 Monitoring Logs

### Look for these Phase 2 log patterns:

```bash
# Correlation Engine
[Phase2-Correlation] Issue bad_block correlation: isolated
[Phase2-Correlation] 🚨 WIDESPREAD ISSUE DETECTED - All nodes affected at block 79000001

# Smart Restart Logic
[Phase2-RestartLogic] ✅ Restart approved (recent: 1/3)
[Phase2-RestartLogic] ❌ Restart limit reached (3 in 6h), escalating instead
[Phase2-RestartLogic] ❌ Last restart ineffective (block: 79000001 → 79000001), escalating

# Peer Management
[Phase2-PeerMgmt] Low peer count (1), fetching healthy peers...
[Phase2-PeerMgmt] ✅ Injected peer: enode://abc123...
[Phase2-PeerMgmt] Injected 3 peers

# Network Height
[Phase2-NetHeight] Network height: 79000100, Local: 79000001

# Diagnostics
[Phase2-Diagnostic] ✅ Hourly diagnostic report sent

# Trend Analysis (in heartbeat)
[Phase2] syncRate=105.2/min trend=stable netHeight=79000100 syncPct=99.9% eta=0.2h
```

---

## 📊 New Metrics in Heartbeat

```json
{
  "syncRate": 105.2,           // blocks/minute (rolling avg)
  "syncTrend": "stable",       // accelerating|stable|decelerating|stalled
  "networkHeight": 79000100,   // real network tip from OpenScan
  "syncPercent": 99.9,         // (localBlock / networkHeight) * 100
  "etaHours": "0.2",          // estimated hours to full sync
  "correlation": "isolated"    // in incident reports
}
```

---

## 🛠️ Troubleshooting

### Agent Not Starting?
```bash
# Check logs
docker logs skynet-agent

# Verify bc package installed
docker exec skynet-agent which bc
```

### State Files Not Updating?
```bash
# Check state files exist
docker exec skynet-agent ls -lh /tmp/*.json

# View block window
docker exec skynet-agent cat /tmp/block-window.json | jq

# View restart history
docker exec skynet-agent cat /tmp/restart-history.json | jq
```

### Peer Injection Not Working?
```bash
# Check peer injection history
docker exec skynet-agent cat /tmp/peer-injection-history

# Check current peers
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'

# Verify client type supports injection
# Geth/XDC: ✅ Yes (admin_addPeer RPC)
# Erigon: ❌ No (logs warning)
# Nethermind: ⚠️ Partial (needs static-nodes.json update)
```

### Network Height Not Fetching?
```bash
# Test OpenScan RPC
curl -X POST https://rpc.openscan.ai/50 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Check cache
docker exec skynet-agent cat /tmp/network-height.json | jq
```

### Restarts Being Blocked?
```bash
# Check restart history
docker exec skynet-agent cat /tmp/restart-history.json | jq

# Count restarts in last 6 hours
docker exec skynet-agent cat /tmp/restart-history.json | \
  jq --argjson cutoff $(date -d '6 hours ago' +%s) \
  '[.restarts[] | select(.timestamp > $cutoff)] | length'

# Clear restart history (emergency only!)
docker exec skynet-agent sh -c 'echo "{\"restarts\":[]}" > /tmp/restart-history.json'
```

### Diagnostic Reports Not Sending?
```bash
# Check diagnostic counter (should increment every heartbeat)
docker exec skynet-agent cat /tmp/diagnostic-counter

# Manually trigger (next heartbeat will send)
docker exec skynet-agent sh -c 'echo "59" > /tmp/diagnostic-counter'
```

---

## 🔧 Configuration Tweaks

### Adjust Restart Limits
Edit `/root/.openclaw/workspace/XDC-Node-Setup/docker/skynet-agent/combined-start.sh`:

```bash
# Line ~1238: Change max restarts per 6h
local recent_restarts=$(echo "$history" | jq --argjson cutoff "$six_hours_ago" \
  '[.restarts[] | select(.timestamp > $cutoff)] | length' 2>/dev/null || echo "0")

# Max 3 restarts per 6 hours (change "3" to desired value)
if [ "$recent_restarts" -ge 3 ]; then
```

### Change Network Height Fetch Interval
```bash
# Line ~1151: Change from every 10th to every Nth heartbeat
if [ $((NETWORK_HEIGHT_COUNTER % 10)) -eq 0 ]; then
# Change "10" to desired interval (e.g., 20 = 20 minutes)
```

### Change Peer Injection Cooldown
```bash
# Line ~220: Change cooldown from 300s to desired value
if [ $time_since -lt 300 ]; then
# Change "300" to desired seconds (e.g., 600 = 10 minutes)
```

### Change Diagnostic Report Interval
```bash
# Line ~1210: Change from every 60th to every Nth heartbeat
if [ $((DIAGNOSTIC_COUNTER % 60)) -eq 0 ] && [ -n "$SKYNET_API_URL" ] && [ -n "$SKYNET_NODE_ID" ] && [ -n "$SKYNET_API_KEY" ]; then
# Change "60" to desired interval (e.g., 30 = 30 minutes)
```

---

## 🧪 Testing Phase 2 Features

### Test Correlation Engine
```bash
# 1. Start multiple nodes on same network
docker-compose up -d xdc-node-1 xdc-node-2 xdc-node-3

# 2. Trigger issue on multiple nodes (e.g., stall at same block)
# 3. Check logs for correlation detection
docker logs skynet-agent-1 | grep "Phase2-Correlation"

# Expected output:
# [Phase2-Correlation] 🚨 WIDESPREAD ISSUE DETECTED - All nodes affected
```

### Test Smart Restart
```bash
# 1. Trigger 3 restarts quickly
docker restart xdc-node  # 1st restart
sleep 5
docker restart xdc-node  # 2nd restart
sleep 5
docker restart xdc-node  # 3rd restart

# 2. Trigger 4th restart attempt
# 3. Check logs for restart block
docker logs skynet-agent | grep "Phase2-RestartLogic"

# Expected output:
# [Phase2-RestartLogic] ❌ Restart limit reached (3 in 6h), escalating instead
```

### Test Peer Injection
```bash
# 1. Manually disconnect node from peers
docker exec xdc-node geth attach --exec "admin.peers.forEach(p => admin.removePeer(p.enode))"

# 2. Wait 5 minutes (5 heartbeats)
# 3. Check logs for peer injection
docker logs skynet-agent | grep "Phase2-PeerMgmt"

# Expected output:
# [Phase2-PeerMgmt] Low peer count (0), fetching healthy peers...
# [Phase2-PeerMgmt] ✅ Injected peer: enode://...
```

### Test Trend Analysis
```bash
# 1. Monitor normal sync
docker logs -f skynet-agent | grep "Phase2.*trend"

# Expected output during normal sync:
# [Phase2] syncRate=105.2/min trend=stable

# 2. Throttle network (simulate slowdown)
tc qdisc add dev eth0 root tbf rate 1mbit burst 32kbit latency 400ms

# 3. Wait 10-15 minutes, check trend
# Expected output:
# [Phase2] syncRate=45.3/min trend=decelerating
```

---

## 📈 Performance Monitoring

### Check Agent Resource Usage
```bash
# Memory usage
docker stats skynet-agent --no-stream

# State file sizes
docker exec skynet-agent du -sh /tmp/*.json

# API call count (estimate from logs)
docker logs skynet-agent | grep "Phase2" | wc -l
```

### Monitor API Health
```bash
# Check SkyNet API response time
time curl -s https://skynet.xdcindia.com/api/v1/fleet/overview > /dev/null

# Check OpenScan RPC response time
time curl -s -X POST https://rpc.openscan.ai/50 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' > /dev/null
```

---

## 🚨 Emergency Commands

### Force Restart Agent (preserve state)
```bash
docker restart skynet-agent
# State files in /tmp/ are preserved
```

### Reset All State (nuclear option)
```bash
docker exec skynet-agent sh -c '
  echo "{\"restarts\":[]}" > /tmp/restart-history.json &&
  echo "{\"blocks\":[]}" > /tmp/block-window.json &&
  echo "{\"peers\":[]}" > /tmp/peer-history.json &&
  echo "{\"height\":0,\"lastUpdate\":0}" > /tmp/network-height.json &&
  echo "0" > /tmp/diagnostic-counter &&
  rm -f /tmp/peer-injection-history /tmp/heal-*-last
'
docker restart skynet-agent
```

### Disable Specific Feature (temporary)
```bash
# Disable correlation engine (allow restarts even if widespread)
docker exec skynet-agent sh -c "sed -i 's/check_fleet_correlation/echo isolated #/' /start.sh"
docker restart skynet-agent

# Re-enable: rebuild container from source
```

---

## 📞 Support

**Report Issues**: GitHub Issues  
**Documentation**: `/root/.openclaw/workspace/XDC-Node-Setup/PHASE2-IMPLEMENTATION-REPORT.md`  
**SkyNet API**: https://skynet.xdcindia.com/api/v1  
**OpenScan RPC**: https://rpc.openscan.ai/{chainId}  

---

**Version**: 2.0  
**Last Updated**: 2026-02-24  
**Maintained by**: OpenClaw AI Agent
