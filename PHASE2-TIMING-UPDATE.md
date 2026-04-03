# Phase 2 Timing Update — 30s Heartbeat Interval

**Date**: 2026-02-24 09:30 GMT+5:30  
**Status**: ✅ Complete  
**Script Size**: 1,510 lines

---

## 🔄 Critical Timing Changes

### Heartbeat Interval: 60s → 30s

**Default**: 30 seconds (configurable via env var or SkyNet API)

```bash
# Environment variable (optional)
HEARTBEAT_INTERVAL=30

# Or fetched from SkyNet API on startup
GET /api/v1/nodes/{id}/config
{
  "data": {
    "heartbeatInterval": 30
  }
}
```

---

## ⏱️ Updated Timings

| Feature | Old Frequency | New Frequency | Real Time |
|---------|--------------|---------------|-----------|
| **Heartbeat** | Every 60s | Every 30s | 30 seconds |
| **Block window** | 30 samples = 30 min | 30 samples = 15 min | 15 minutes |
| **Stall detection** | 5 HB = 5 min | 10 HB = 5 min | 5 minutes |
| **Peer check** | Every 5 HB = 5 min | Every 10 HB = 5 min | 5 minutes |
| **Network height** | Every 10 HB = 10 min | Every 20 HB = 10 min | 10 minutes |
| **Config refresh** | N/A | Every 50 HB = 25 min | 25 minutes |
| **Diagnostic report** | Every 60 HB = 1 hour | Every 120 HB = 1 hour | 1 hour |

---

## 🆕 New Feature: Config Refresh

Agent now fetches its configuration from SkyNet API:

### On Startup
```bash
fetch_agent_config "$SKYNET_NODE_ID" "$SKYNET_API_KEY" "$SKYNET_API_URL"
# Sets HEARTBEAT_INTERVAL from API response
```

### Every 50 Heartbeats (~25 minutes)
```bash
if [ $((CONFIG_REFRESH_COUNTER % 50)) -eq 0 ]; then
  fetch_agent_config "$SKYNET_NODE_ID" "$SKYNET_API_KEY" "$SKYNET_API_URL"
fi
```

### Fallback Logic
1. Try to fetch from SkyNet API
2. If API unavailable → use `HEARTBEAT_INTERVAL` env var
3. If env var not set → default to 30s

---

## 📐 Architecture Confirmation

### Each XDC Node Has Exactly ONE Agent Sidecar

```
┌─────────────────────────────────────┐
│  XDC Node Container                 │
│  - Geth/Erigon/Nethermind          │
│  - RPC port 8545                   │
│  - P2P port 30303                  │
└──────────────┬──────────────────────┘
               │ monitors via RPC
               ▼
┌─────────────────────────────────────┐
│  XDC Agent Sidecar Container        │
│  - Sends heartbeats every 30s      │
│  - Auto-heals (restart, peers)     │
│  - Reports incidents (dedup)       │
│  - Fetches fleet data for corr.    │
│  - Calculates sync % (OpenScan)    │
│  - Tracks trends (15-min window)   │
│  - Generates hourly diagnostics    │
│  - State persisted in /tmp/        │
└─────────────────────────────────────┘
```

---

## 🔧 Implementation Changes

### 1. Configurable Heartbeat Interval
```bash
# At script start
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-30}"

# Fetch from SkyNet API
fetch_agent_config() {
  local response=$(curl -s -m 5 "${api_url}/v1/nodes/${node_id}/config" \
    -H "Authorization: Bearer ${api_key}" 2>/dev/null)
  
  local remote_interval=$(echo "$response" | jq -r '.data.heartbeatInterval')
  if [ -n "$remote_interval" ] && [ "$remote_interval" -gt 0 ]; then
    HEARTBEAT_INTERVAL=$remote_interval
    echo "[Phase2-Config] ✅ Using custom interval: ${HEARTBEAT_INTERVAL}s"
  fi
}

# Use in sleep
sleep $HEARTBEAT_INTERVAL
```

### 2. Updated Sync Rate Calculation
```bash
calculate_sync_rate() {
  local heartbeat_interval="${1:-30}"
  # ... existing logic ...
  
  # Calculate blocks per minute accounting for interval
  local time_window_seconds=$(( (block_count - 1) * heartbeat_interval ))
  local time_window_minutes=$(echo "scale=4; $time_window_seconds / 60" | bc)
  local rate=$(echo "scale=2; $block_diff / $time_window_minutes" | bc)
}
```

### 3. Adjusted Counter Thresholds
```bash
# Stall detection: 5 → 10 heartbeats (still 5 min)
if [ $STALL_COUNT -ge 10 ] && [ "$CAN_RESTART" = true ]; then

# Peer management: every 5 → every 10 heartbeats (still 5 min)
if [ $((PEER_MGMT_COUNTER % 10)) -eq 0 ]; then

# Network height: every 10 → every 20 heartbeats (still 10 min)
if [ $((NETWORK_HEIGHT_COUNTER % 20)) -eq 0 ]; then

# Diagnostic: every 60 → every 120 heartbeats (still 1 hour)
if [ $((DIAGNOSTIC_COUNTER % 120)) -eq 0 ]; then

# Config refresh: NEW - every 50 heartbeats (~25 min)
if [ $((CONFIG_REFRESH_COUNTER % 50)) -eq 0 ]; then
```

---

## 📊 Impact on Metrics

### API Calls Per Hour

| Endpoint | Old (60s) | New (30s) | Notes |
|----------|-----------|-----------|-------|
| Heartbeat | 60 | 120 | 2x frequency |
| Fleet overview | ~60 | ~120 | On incident only |
| Network height | 6 | 6 | Same (every 10 min) |
| Healthy peers | 12 | 12 | Same (every 5 min) |
| Config fetch | 0 | ~2.4 | NEW (every 25 min) |
| Diagnostic | 1 | 1 | Same (hourly) |

**Total**: ~139-199 calls/hour (was ~79-139)

### Data Windows

| Window | Old Size | New Size | Coverage |
|--------|----------|----------|----------|
| Block history | 30 @ 60s | 30 @ 30s | 30 min → 15 min |
| Peer history | 30 @ 60s | 30 @ 30s | 30 min → 15 min |
| Restart history | Last 20 | Last 20 | Unchanged |

---

## 🚀 Deployment

### Environment Variable Method
```bash
docker run -d \
  --name skynet-agent \
  -e HEARTBEAT_INTERVAL=30 \
  -e SKYNET_API_URL=https://skynet.xdcindia.com/api/v1 \
  xdc-skynet-agent:v2.0
```

### SkyNet API Method (Recommended)
```bash
# Agent fetches config on startup automatically
docker run -d \
  --name skynet-agent \
  -e SKYNET_API_URL=https://skynet.xdcindia.com/api/v1 \
  xdc-skynet-agent:v2.0

# Backend can control interval per node
PUT /api/v1/nodes/{id}/config
{
  "heartbeatInterval": 30
}
```

### Docker Compose
```yaml
services:
  skynet-agent:
    image: xdc-skynet-agent:v2.0
    environment:
      HEARTBEAT_INTERVAL: 30  # Optional, fetches from API by default
      SKYNET_API_URL: https://skynet.xdcindia.com/api/v1
```

---

## 🔍 Verification

### Check Active Interval
```bash
# View startup logs
docker logs skynet-agent | grep "Phase2-Config"

# Expected output:
# [Phase2-Config] Fetching agent config from SkyNet...
# [Phase2-Config] ✅ Using custom interval from SkyNet: 30s
# [Phase2-Config] Using heartbeat interval: 30s
# [Phase2-Config] Block window: 30 samples = 15.0 minutes
```

### Monitor Heartbeat Frequency
```bash
# Watch heartbeat logs
docker logs -f skynet-agent | grep "Heartbeat OK"

# Should see one line every 30 seconds
# [SkyNet] ✅ Heartbeat OK
# ... (30 seconds later) ...
# [SkyNet] ✅ Heartbeat OK
```

### Verify Config Refresh
```bash
# Watch for config refresh every ~25 minutes
docker logs -f skynet-agent | grep "Phase2-Config"

# Expected every 50 heartbeats:
# [Phase2-Config] Fetching agent config from SkyNet...
# [Phase2-Config] ✅ Using custom interval from SkyNet: 30s
```

---

## 📝 SkyNet Backend API Requirements

### New Endpoint: GET /api/v1/nodes/{id}/config

**Request**:
```http
GET /api/v1/nodes/{nodeId}/config
Authorization: Bearer {apiKey}
```

**Response**:
```json
{
  "success": true,
  "data": {
    "heartbeatInterval": 30,
    "features": {
      "correlationEngine": true,
      "smartRestart": true,
      "peerManagement": true
    }
  }
}
```

**Fallback**: If endpoint returns 404 or error, agent uses default 30s

---

## 🎯 Benefits of 30s Interval

### 1. **Faster Problem Detection**
- Issues detected in 2.5 minutes instead of 5 minutes (at half the window)
- More granular sync rate tracking

### 2. **Better Trend Analysis**
- 15-minute window captures recent behavior
- More data points for trend calculation
- Faster detection of deceleration

### 3. **Improved Responsiveness**
- Stall detected in 5 minutes (10 heartbeats)
- Peer injection triggered sooner
- More up-to-date fleet status

### 4. **Backward Compatible**
- API ignores extra heartbeats if processing is rate-limited
- Fingerprint dedup prevents duplicate incidents
- Dashboard shows real-time status

---

## ⚠️ Considerations

### 1. **API Load**
- Heartbeat frequency doubled (60/hour → 120/hour)
- Consider rate limiting on backend (e.g., process max 1 heartbeat/min per node)
- Use caching for fleet overview queries

### 2. **Agent Resource Usage**
- Minimal CPU impact (heartbeat is lightweight)
- Memory unchanged (same window sizes)
- Slightly more network traffic

### 3. **Database Write Load**
- 2x heartbeat writes per node
- Consider batch writes or async processing
- Use heartbeat consolidation (update instead of insert)

---

## ✅ Checklist: Timing Update Complete

- [x] Heartbeat interval configurable (env + API)
- [x] Config fetch on startup
- [x] Config refresh every 50 HB (~25 min)
- [x] Stall detection adjusted (10 HB = 5 min)
- [x] Peer check adjusted (10 HB = 5 min)
- [x] Network height adjusted (20 HB = 10 min)
- [x] Diagnostic adjusted (120 HB = 1 hour)
- [x] Sync rate calculation updated (accounts for interval)
- [x] Block window = 15 min (30 samples @ 30s)
- [x] Sleep uses $HEARTBEAT_INTERVAL
- [x] Documentation updated
- [x] Script header updated

---

## 📚 Related Documentation

- **Full Report**: `PHASE2-IMPLEMENTATION-REPORT.md`
- **Quick Reference**: `docker/skynet-agent/PHASE2-QUICK-REFERENCE.md`
- **Executive Summary**: `PHASE2-EXECUTIVE-SUMMARY.md`
- **This Update**: `PHASE2-TIMING-UPDATE.md` (you are here)

---

**Built by**: OpenClaw AI Agent  
**Date**: 2026-02-24 09:30 GMT+5:30  
**Version**: 2.0 (timing update)  
**Status**: Ready for deployment 🚀
