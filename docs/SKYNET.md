# SkyNet Integration Guide

**Centralized fleet monitoring and management for XDC Network nodes**

---

## Overview

**XDC SkyNet** is a centralized monitoring platform that aggregates metrics, alerts, and health data from all your XDC nodes into a single dashboard. It provides fleet-wide visibility, automated alerting, and historical analytics.

**Key Benefits:**
- 🌐 **Single pane of glass** — Monitor all nodes from one dashboard
- 📊 **Historical analytics** — Track performance trends over time
- 🔔 **Unified alerting** — Get notified across all your nodes
- 📍 **Geographic distribution** — See where your nodes are deployed
- 🔗 **Network insights** — Understand peer connectivity patterns
- 💓 **Heartbeat monitoring** — Real-time connection status
- 📈 **Fleet statistics** — Aggregate metrics across your infrastructure

**SkyNet Platform:** [https://net.xdc.network](https://net.xdc.network) (managed by XDC Network)

---

## Architecture

### How It Works

```
┌─────────────────┐
│   XDC Node      │
│   (Your Server) │
└────────┬────────┘
         │
         │ Heartbeat every 60s
         │ (node metrics + health)
         │
         ▼
┌─────────────────┐      ┌──────────────────┐
│ SkyNet Agent    │─────▶│  SkyNet API      │
│ (skynet-agent.sh)│      │  net.xdc.network │
└─────────────────┘      └────────┬─────────┘
         │                         │
         │ Writes status           │ Stores metrics
         │ to /tmp/                │ in database
         ▼                         ▼
┌─────────────────┐      ┌──────────────────┐
│ Dashboard API   │      │ SkyNet Dashboard │
│ /api/heartbeat  │      │ (Public Web UI)  │
└─────────────────┘      └──────────────────┘
```

**Components:**

1. **skynet-agent.sh** — Bash script that runs as daemon, collects metrics and sends heartbeat
2. **SkyNet API** — Cloud endpoint (`https://net.xdc.network/api/v1`) that receives and stores data
3. **Local API endpoint** — Dashboard reads heartbeat status from `/tmp/skynet-heartbeat.json`
4. **SkyNet Dashboard** — Web UI to view all registered nodes

---

## Installation & Setup

### Automatic Setup (Recommended)

SkyNet integration is automatically configured during node installation:

```bash
cd XDC-Node-Setup
sudo ./setup.sh
```

**What happens:**
1. Generates unique node ID (stored in `/etc/xdc-node/skynet.conf`)
2. Creates SkyNet agent service (`skynet-agent.sh`)
3. Registers node with SkyNet API
4. Starts heartbeat daemon (runs every 60 seconds)
5. Configures dashboard to show heartbeat status

**Configuration file:** `/etc/xdc-node/skynet.conf`

```conf
SKYNET_ENABLED=true
SKYNET_URL=https://net.xdc.network/api/v1
NODE_ID=node_1a2b3c4d5e6f
NODE_NAME=xdc-mainnet-01
NODE_LOCATION=US-East-1
```

### Manual Setup

If you need to manually configure SkyNet:

**1. Create configuration file:**

```bash
sudo mkdir -p /etc/xdc-node
sudo tee /etc/xdc-node/skynet.conf <<EOF
SKYNET_ENABLED=true
SKYNET_URL=https://net.xdc.network/api/v1
NODE_ID=node_$(openssl rand -hex 8)
NODE_NAME=$(hostname)-xdc
NODE_LOCATION=Unknown
EOF
```

**2. Install SkyNet agent script:**

```bash
sudo cp scripts/skynet-agent.sh /usr/local/bin/skynet-agent
sudo chmod +x /usr/local/bin/skynet-agent
```

**3. Create systemd service:**

```bash
sudo tee /etc/systemd/system/skynet-agent.service <<EOF
[Unit]
Description=XDC SkyNet Agent
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/usr/local/bin/skynet-agent
Restart=always
RestartSec=60
User=root

[Install]
WantedBy=multi-user.target
EOF
```

**4. Enable and start service:**

```bash
sudo systemctl daemon-reload
sudo systemctl enable skynet-agent
sudo systemctl start skynet-agent
```

**5. Verify it's running:**

```bash
sudo systemctl status skynet-agent
```

---

## Configuration

### Configuration File: `/etc/xdc-node/skynet.conf`

**Full reference:**

```conf
# Enable/disable SkyNet integration
SKYNET_ENABLED=true

# SkyNet API endpoint
SKYNET_URL=https://net.xdc.network/api/v1

# Unique node identifier (auto-generated)
NODE_ID=node_1a2b3c4d5e6f

# Human-readable node name (appears in dashboard)
NODE_NAME=xdc-mainnet-01

# Geographic location (optional, for map view)
NODE_LOCATION=US-East-1

# Heartbeat interval in seconds (default: 60)
HEARTBEAT_INTERVAL=60

# RPC endpoint to query node metrics
RPC_URL=http://localhost:8545

# API timeout in seconds
API_TIMEOUT=10

# Retry attempts on failure
MAX_RETRIES=3
```

### Environment Variables

Override config via environment variables:

```bash
export SKYNET_ENABLED=true
export SKYNET_URL=https://net.xdc.network/api/v1
export NODE_ID=node_abc123
export NODE_NAME=my-custom-name
```

---

## Heartbeat Mechanism

### What Gets Sent

Every 60 seconds, the SkyNet agent sends a JSON payload to the SkyNet API:

```json
{
  "nodeId": "node_1a2b3c4d5e6f",
  "nodeName": "xdc-mainnet-01",
  "location": "US-East-1",
  "timestamp": "2026-02-14T07:20:00Z",
  "metrics": {
    "blockNumber": 75234567,
    "peerCount": 23,
    "networkId": 50,
    "syncStatus": "syncing",
    "syncProgress": 99.95,
    "clientVersion": "XDC/v1.4.8-stable"
  },
  "system": {
    "cpuUsage": 12.4,
    "memoryUsage": 45.6,
    "diskUsage": 67.8,
    "uptime": 432000
  },
  "health": {
    "status": "healthy",
    "errors": [],
    "warnings": ["High memory usage"]
  }
}
```

### Heartbeat Status File

After each heartbeat attempt, the agent writes status to `/tmp/skynet-heartbeat.json`:

```json
{
  "lastHeartbeat": "2026-02-14T07:20:00Z",
  "status": "success",
  "skynetUrl": "https://net.xdc.network/api/v1",
  "nodeId": "node_1a2b3c4d5e6f",
  "nodeName": "xdc-mainnet-01",
  "error": ""
}
```

**Status values:**
- `success` — Heartbeat sent successfully
- `failed` — Heartbeat failed (contains error message)
- `pending` — Heartbeat in progress

**This file is read by:**
- Dashboard API endpoint (`/api/heartbeat`)
- Sidebar component (for visual indicator)
- Monitoring scripts

---

## Auto-Restart Watchdog

### Overview

The SkyNet agent includes a **built-in watchdog** that automatically detects and recovers from node failures. It runs health checks on every heartbeat (every 60 seconds) and can auto-restart unhealthy nodes.

**Watchdog Features:**
- 🔄 **Auto-restart** — Automatically restarts failed/stuck nodes
- 🛡️ **Rate limiting** — Max 3 restarts per hour with 5-minute cooldown
- 📊 **Health checks** — Container status, RPC response, sync progress, peer count
- 📝 **Detailed logging** — All actions logged to `/var/log/xdc-watchdog.log`
- 🎯 **Smart detection** — Only restarts on critical issues

### Health Checks

The watchdog performs these checks on every heartbeat:

| Check | Description | Action on Failure |
|-------|-------------|-------------------|
| **Container Status** | Is the Docker container running? | Auto-restart |
| **RPC Responsiveness** | Does `eth_blockNumber` respond? | Auto-restart |
| **Sync Progress** | Is block height increasing? | Auto-restart (if stalled >10 min) |
| **Peer Count** | Are peers connected? | Warn + auto-inject peers |

### Restart Logic

**When watchdog triggers a restart:**
1. Detects critical issue (e.g., RPC down, container stopped)
2. Checks cooldown period (5 minutes since last restart)
3. Checks restart limit (max 3 per hour)
4. Logs restart action with reason
5. Restarts Docker container (or systemd service)
6. Increments restart counter

**Restart counter resets:**
- After 1 hour of node stability (no issues detected)
- On system reboot (watchdog state is in `/tmp`)

**Example watchdog log:**
```
[2026-02-15 18:30:15] ⚠️ Warning: No peers connected
[2026-02-15 18:31:20] 🔄 AUTO-RESTART triggered: Container xdc-node is exited, RPC not responding
[2026-02-15 18:31:20] Restarting Docker container: xdc-node
[2026-02-15 18:31:25] ✅ Container restarted successfully
[2026-02-15 18:31:25] Restart count: 1/3 in current window
[2026-02-15 18:32:30] ✅ Node healthy (block: 75234801, peers: 28)
```

### Manual Watchdog Check

You can manually trigger a watchdog health check:

```bash
# Run watchdog check
./scripts/skynet-agent.sh --watchdog

# View watchdog logs
tail -f /var/log/xdc-watchdog.log

# View last 50 lines
tail -50 /var/log/xdc-watchdog.log
```

### Watchdog State

Watchdog tracks state in `/tmp/xdc-watchdog-state.json`:

```json
{
  "lastBlock": 75234801,
  "lastCheckTime": 1708022430,
  "restartCount": 1,
  "lastRestartTime": 1708022080,
  "firstRestartTime": 1708022080
}
```

**State fields:**
- `lastBlock` — Last known block height (to detect stalls)
- `lastCheckTime` — Unix timestamp of last health check
- `restartCount` — Number of restarts in current 1-hour window
- `lastRestartTime` — Unix timestamp of last restart
- `firstRestartTime` — Unix timestamp of first restart in current window

### Disable Watchdog

To disable the watchdog (not recommended):

**Option 1: Skip watchdog in agent code**
```bash
# Edit skynet-agent.sh and comment out the watchdog call
sudo nano /root/xdc-node-setup/scripts/skynet-agent.sh

# Find this line in push_heartbeat():
if ! check_node_health "$block_height" "$peer_count" "$is_syncing"; then
# Comment it out:
# if ! check_node_health "$block_height" "$peer_count" "$is_syncing"; then
```

**Option 2: Stop the agent entirely**
```bash
# Stop systemd service (if installed)
sudo systemctl stop xdc-skynet-agent
sudo systemctl disable xdc-skynet-agent

# Remove cron job
crontab -e
# Delete the skynet-agent line
```

⚠️ **Warning:** Disabling the watchdog means you lose auto-restart protection. Your node may stay down for hours if it crashes while you're away.

### Troubleshooting Watchdog

**Problem: Watchdog restarting node too often**

Check logs to see why:
```bash
tail -100 /var/log/xdc-watchdog.log
```

Common causes:
- **RPC not bound to 127.0.0.1** — Check `RPC_ADDR` in `.env`
- **Slow disk causing sync stalls** — Upgrade to SSD
- **Network issues causing peer loss** — Check firewall, open port 30303
- **Corrupted blockchain data** — May need to resync

**Problem: Watchdog not restarting failed node**

Possible reasons:
1. **Restart limit reached** (3/hour) — Wait for 1-hour window to reset
2. **In cooldown period** (5 min) — Check `lastRestartTime` in state file
3. **Issue not critical enough** — Watchdog only restarts on RPC failure/container stopped/sync stall

Check state:
```bash
cat /tmp/xdc-watchdog-state.json
```

**Problem: Want to reset restart counter manually**

Delete the state file:
```bash
sudo rm /tmp/xdc-watchdog-state.json
```

Counter will reset on next heartbeat.

---

## Dashboard Integration

### Heartbeat Indicator

The XDC SkyOne Dashboard shows real-time heartbeat status in the sidebar:

**Visual states:**

| State | Indicator | Meaning |
|-------|-----------|---------|
| **Connected** | 🟢 Pulsing green dot | Heartbeat within last 2 minutes |
| **Pending** | 🟡 Yellow dot | Heartbeat 2-5 minutes ago |
| **Offline** | 🔴 Red dot | Heartbeat >5 minutes ago |
| **Error** | 🔴 Red dot + error | Heartbeat failed with error |
| **Disabled** | ⚫ Grey | SkyNet not configured |

**Location in UI:**
- Sidebar (bottom section, below navigation links)
- Collapsed sidebar shows just the colored dot
- Expanded sidebar shows "Last heartbeat: Xs ago"

### SkyNet Status Card

Main dashboard page includes a dedicated SkyNet status card:

**Displays:**
- Connection status with color indicator
- Last heartbeat timestamp (human-readable)
- Node ID (truncated, e.g., `node_1a2b...`)
- Link to full SkyNet dashboard
- Error messages when heartbeat fails

**Example:**

```
┌────────────────────────────────────┐
│ SkyNet Status                      │
├────────────────────────────────────┤
│ Status: 🟢 Connected               │
│ Last heartbeat: 23 seconds ago     │
│ Node ID: node_1a2b...              │
│                                    │
│ [View on SkyNet Dashboard →]       │
└────────────────────────────────────┘
```

### API Endpoint

**Endpoint:** `GET /api/heartbeat`

**Response when enabled and connected:**

```json
{
  "enabled": true,
  "status": "connected",
  "lastHeartbeat": "2026-02-14T07:18:30Z",
  "timeSinceLastHeartbeat": 90,
  "skynetUrl": "https://net.xdc.network/api/v1",
  "nodeId": "node_1a2b3c4d5e6f",
  "nodeName": "xdc-mainnet-01",
  "error": null
}
```

**Response when disabled:**

```json
{
  "enabled": false,
  "status": "disabled",
  "message": "SkyNet integration is not configured"
}
```

**Response when offline:**

```json
{
  "enabled": true,
  "status": "offline",
  "lastHeartbeat": "2026-02-14T06:50:00Z",
  "timeSinceLastHeartbeat": 1830,
  "error": "No heartbeat received in last 30 minutes"
}
```

---

## SkyNet Dashboard (Web UI)

### Accessing the Dashboard

**URL:** [https://net.xdc.network](https://net.xdc.network)

**Authentication:**
- Register with email and password
- Or use OAuth (Google, GitHub)

**After login:**
1. You'll see a list of all your registered nodes
2. Click on a node to view detailed metrics
3. Configure alerts and notifications

### Dashboard Features

#### 1. Fleet Overview

**Main dashboard shows:**
- Total nodes online/offline
- Aggregate block height (min/max/avg)
- Total peer connections across fleet
- Geographic distribution map
- Recent alerts timeline

#### 2. Node Cards

**Each node displays:**
- 🟢/🟡/🔴 Status indicator (pulsing for online)
- Node name and location
- Current block height
- Peer count
- Last heartbeat timestamp (e.g., "2 minutes ago")
- Quick action buttons (view details, restart, configure)

**Card layout:**

```
┌─────────────────────────────────────────┐
│ 🟢 xdc-mainnet-01                       │
│    US-East-1                            │
├─────────────────────────────────────────┤
│ Block: 75,234,567                       │
│ Peers: 23                               │
│ Last heartbeat: 2 minutes ago           │
│                                         │
│ [View Details] [Logs] [Restart]         │
└─────────────────────────────────────────┘
```

#### 3. Node Details Page

**Detailed view shows:**
- Real-time metrics chart (block height over time)
- Sync status and progress bar
- Peer list with geographic map
- System resource graphs (CPU, memory, disk)
- Recent logs and errors
- Configuration settings
- Version and update status

#### 4. Alerts & Notifications

**Configurable alerts:**
- Node goes offline (no heartbeat for X minutes)
- Sync stalled (no block progress for X minutes)
- Low peer count (fewer than X peers)
- High resource usage (CPU/memory/disk over X%)
- Version update available

**Notification channels:**
- Email (configurable frequency)
- Webhook (POST to custom URL)
- Telegram bot (coming soon)
- Slack integration (coming soon)

#### 5. Historical Analytics

**View trends over time:**
- Block height progression
- Peer count fluctuations
- Resource usage patterns
- Downtime incidents
- Sync speed (blocks/sec)

**Time ranges:**
- Last hour / 24 hours / 7 days / 30 days / custom

---

## CLI Commands

### Check SkyNet Status

```bash
xdc skynet status
```

**Example output:**

```
SkyNet Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Enabled:         Yes
Status:          Connected
Node ID:         node_1a2b3c4d5e6f
Node Name:       xdc-mainnet-01
Last Heartbeat:  23 seconds ago
SkyNet URL:      https://net.xdc.network/api/v1
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Register with SkyNet

```bash
xdc skynet register --name "my-node" --location "US-East"
```

### Manual Heartbeat

```bash
xdc skynet heartbeat
```

### Disable SkyNet

```bash
xdc skynet disable
```

**Or edit config:**

```bash
sudo sed -i 's/SKYNET_ENABLED=true/SKYNET_ENABLED=false/' /etc/xdc-node/skynet.conf
sudo systemctl restart skynet-agent
```

---

## Troubleshooting

### Heartbeat not showing in dashboard

**1. Check SkyNet agent is running:**

```bash
sudo systemctl status skynet-agent
```

**If not running:**

```bash
sudo systemctl start skynet-agent
```

**2. Check heartbeat status file:**

```bash
cat /tmp/skynet-heartbeat.json
```

**Should show recent timestamp and `status: "success"`**

**3. Test heartbeat API:**

```bash
curl http://localhost:7070/api/heartbeat
```

**Should return JSON with `enabled: true`**

**4. Check SkyNet config:**

```bash
cat /etc/xdc-node/skynet.conf
```

**Verify `SKYNET_ENABLED=true`**

---

### Heartbeat status shows "error"

**1. Check agent logs:**

```bash
sudo journalctl -u skynet-agent -n 50
```

**Look for error messages like:**
- `Connection refused` — SkyNet API unreachable
- `Timeout` — Network issue or slow API
- `Unauthorized` — Invalid node ID
- `RPC error` — Can't query local XDC node

**2. Test API connectivity:**

```bash
curl -X POST https://net.xdc.network/api/v1/heartbeat \
  -H "Content-Type: application/json" \
  -d '{"nodeId":"test","nodeName":"test","timestamp":"2026-02-14T07:00:00Z"}'
```

**Should return 200 OK**

**3. Test RPC connectivity:**

```bash
curl http://localhost:8545 \
  -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

**Should return current block number**

---

### Dashboard shows "SkyNet: Not configured"

**1. Verify config file exists:**

```bash
ls -la /etc/xdc-node/skynet.conf
```

**If missing, create it:**

```bash
sudo mkdir -p /etc/xdc-node
sudo tee /etc/xdc-node/skynet.conf <<EOF
SKYNET_ENABLED=true
SKYNET_URL=https://net.xdc.network/api/v1
NODE_ID=node_$(openssl rand -hex 8)
NODE_NAME=$(hostname)-xdc
EOF
```

**2. Mount config in Docker:**

Verify `docker-compose.yml` includes:

```yaml
volumes:
  - /etc/xdc-node/skynet.conf:/etc/xdc-node/skynet.conf:ro
```

**3. Restart dashboard:**

```bash
docker compose restart xdc-agent
```

---

### Node not appearing in SkyNet dashboard

**1. Check node is registered:**

```bash
curl -X GET "https://net.xdc.network/api/v1/nodes/node_1a2b3c4d5e6f"
```

**Should return node details**

**2. Re-register if needed:**

```bash
xdc skynet register --force
```

**3. Verify heartbeat is being sent:**

```bash
sudo journalctl -u skynet-agent -f
```

**Look for successful POST requests**

---

### High heartbeat latency

**Symptoms:**
- Dashboard shows "Last heartbeat: 5+ minutes ago" despite agent running
- SkyNet dashboard shows stale data

**Causes:**
- Network connectivity issues
- SkyNet API slow or overloaded
- Agent stuck or frozen

**Solutions:**

**1. Restart agent:**

```bash
sudo systemctl restart skynet-agent
```

**2. Reduce heartbeat interval (lighter load):**

```bash
# Edit config
sudo nano /etc/xdc-node/skynet.conf

# Change:
HEARTBEAT_INTERVAL=120  # 2 minutes instead of 60 seconds

# Restart
sudo systemctl restart skynet-agent
```

**3. Use alternative endpoint (if available):**

```bash
SKYNET_URL=https://skynet-backup.xdc.network/api/v1
```

---

## Security Considerations

### Data Privacy

**What data is sent to SkyNet:**
- ✅ Block height, peer count, sync status (public blockchain data)
- ✅ Node version, network ID (public info)
- ✅ System resource usage (CPU, memory, disk percentages)
- ✅ Node ID (random identifier, not linked to identity)
- ❌ **NOT sent:** Private keys, keystore, wallet addresses, transaction history

**All sensitive data stays on your server.**

### Authentication

**Node registration:**
- Each node has unique ID (generated randomly)
- No password or API key required for basic registration
- Future: Optional API key for enhanced features

**Dashboard access:**
- Requires account creation (email + password or OAuth)
- Can only view nodes you registered

### Network Security

**Firewall rules:**
- SkyNet uses outbound HTTPS (port 443)
- No inbound connections required
- Agent initiates all communication

**Disable if needed:**

```bash
# Temporary disable
sudo systemctl stop skynet-agent

# Permanent disable
sudo systemctl disable skynet-agent
xdc config set skynet_enabled false
```

---

## Advanced Usage

### Custom Metrics

Extend the agent to send custom metrics:

**Edit `skynet-agent.sh`:**

```bash
# Add custom metric collection
CUSTOM_METRIC=$(your-command-here)

# Include in JSON payload
curl -X POST "$SKYNET_URL/heartbeat" \
  -H "Content-Type: application/json" \
  -d "{
    \"nodeId\": \"$NODE_ID\",
    \"customMetric\": $CUSTOM_METRIC,
    ...
  }"
```

### Webhook Notifications

Configure SkyNet to POST alerts to your webhook:

**1. Create webhook endpoint (example with Express.js):**

```javascript
app.post('/skynet-webhook', (req, res) => {
  const alert = req.body
  console.log(`Alert: ${alert.type} - ${alert.message}`)
  // Send to Slack, email, etc.
  res.sendStatus(200)
})
```

**2. Configure in SkyNet dashboard:**
- Go to Settings → Notifications
- Add webhook URL: `https://your-server.com/skynet-webhook`
- Select alert types to forward

### Multi-Node Monitoring

Monitor multiple nodes from single dashboard:

**1. Install on each node with unique names:**

```bash
# Node 1
NODE_NAME=xdc-us-east-1 ./setup.sh

# Node 2
NODE_NAME=xdc-eu-west-1 ./setup.sh

# Node 3
NODE_NAME=xdc-asia-1 ./setup.sh
```

**2. All nodes appear in your SkyNet dashboard**

**3. Set up aggregate alerts:**
- Alert if ANY node goes offline
- Alert if AVERAGE peer count drops below threshold
- Alert if TOTAL nodes < expected count

---

## API Reference

### SkyNet API Endpoints

**Base URL:** `https://net.xdc.network/api/v1`

#### POST /heartbeat

Submit node heartbeat.

**Request:**

```json
{
  "nodeId": "node_abc123",
  "nodeName": "my-node",
  "location": "US-East",
  "timestamp": "2026-02-14T07:20:00Z",
  "metrics": { ... },
  "system": { ... },
  "health": { ... }
}
```

**Response:**

```json
{
  "status": "success",
  "message": "Heartbeat received",
  "nextHeartbeat": "2026-02-14T07:21:00Z"
}
```

#### GET /nodes/{nodeId}

Get node details.

**Response:**

```json
{
  "nodeId": "node_abc123",
  "nodeName": "my-node",
  "location": "US-East",
  "status": "online",
  "lastHeartbeat": "2026-02-14T07:20:00Z",
  "metrics": { ... }
}
```

#### GET /nodes

List all your nodes.

**Response:**

```json
{
  "nodes": [
    { "nodeId": "node_abc123", "nodeName": "node-1", "status": "online" },
    { "nodeId": "node_def456", "nodeName": "node-2", "status": "offline" }
  ],
  "total": 2
}
```

---

## FAQ

**Q: Is SkyNet required to run an XDC node?**  
A: No, it's completely optional. Your node will work fine without it. SkyNet just provides monitoring and alerting.

**Q: Does SkyNet cost money?**  
A: Basic monitoring is free. Premium features (advanced analytics, extended history) may require a subscription in the future.

**Q: Can I self-host SkyNet?**  
A: Not yet, but it's on the roadmap. Currently, you must use the hosted version at `net.xdc.network`.

**Q: What data retention does SkyNet have?**  
A: Free tier: 7 days. Premium: 90 days. Enterprise: Unlimited.

**Q: Can I export my data from SkyNet?**  
A: Yes, via API or CSV download from dashboard.

**Q: How secure is SkyNet?**  
A: All communication uses HTTPS. No private keys or sensitive data is transmitted. See Security section above.

**Q: What if SkyNet is down?**  
A: Your node continues running normally. Heartbeat status will show "offline" in local dashboard, but node operation is unaffected.

**Q: Can I use SkyNet with testnets?**  
A: Yes! Just set `NODE_NAME=testnet-node` to distinguish from mainnet nodes.

---

## Support

- **SkyNet Dashboard:** [https://net.xdc.network](https://net.xdc.network)
- **Documentation:** [https://docs.xdc.network/skynet](https://docs.xdc.network/skynet)
- **GitHub Issues:** [https://github.com/AnilChinchawale/XDC-Node-Setup/issues](https://github.com/AnilChinchawale/XDC-Node-Setup/issues)
- **Discord:** [XDC Network Discord](https://discord.gg/xdc)

---

**SkyNet — Unified monitoring for the XDC Network ecosystem**
