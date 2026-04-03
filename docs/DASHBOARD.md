# XDC SkyOne Dashboard

**Production-ready Next.js dashboard for XDC node monitoring and management**

---

## Overview

The XDC SkyOne Dashboard is a modern, real-time web interface for monitoring and managing your XDC Network node. Built with Next.js 15, TypeScript, and Tailwind CSS, it provides comprehensive insights into node health, network status, peer connections, and system resources.

**Features:**
- 🎨 **Beautiful UI** — Modern, responsive design with dark/light themes
- 📊 **Real-time metrics** — Live block height, sync status, and peer count
- 🔔 **Smart alerts** — Proactive monitoring with actionable notifications
- 🌐 **Network insights** — Peer analysis, geographic distribution, and connection quality
- 💓 **Heartbeat monitoring** — SkyNet integration with visual connection status
- 📈 **System stats** — CPU, memory, disk, and container metrics
- 🚨 **Diagnostics** — Displays logs and errors even when node is offline
- 🔄 **Auto-refresh** — Configurable polling intervals (10-60 seconds)

**Access:** `http://localhost:7070` (or `http://<server-ip>:7070`)

---

## Installation

### Via Docker (Recommended)

The dashboard is included in the Docker Compose stack:

```bash
cd /root/workspace/xdc-node-setup/docker
RPC_URL=http://xdc-node:8545 docker compose up -d xdc-agent
```

**What happens:**
1. Builds Next.js dashboard from `dashboard/` directory
2. Exposes dashboard on port 7070
3. Connects to XDC node RPC at `http://xdc-node:8545`
4. Reads SkyNet config from `/etc/xdc-node/skynet.conf`

### Standalone (Development)

For local development:

```bash
cd dashboard
npm install
RPC_URL=http://localhost:8545 npm run dev
```

**Development server:** `http://localhost:3000`

---

## Configuration

### Environment Variables

Set in `docker-compose.yml` or `.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `RPC_URL` | `http://xdc-node:8545` | XDC node RPC endpoint |
| `PORT` | `7070` | Dashboard HTTP port |
| `REFRESH_INTERVAL` | `30000` | Data refresh interval (ms) |
| `NODE_ENV` | `production` | Node.js environment |

**Example:**

```yaml
services:
  xdc-agent:
    environment:
      - RPC_URL=http://xdc-node:8545
      - PORT=7070
      - REFRESH_INTERVAL=15000
```

### SkyNet Configuration

SkyNet integration reads from `/etc/xdc-node/skynet.conf`:

```conf
SKYNET_ENABLED=true
SKYNET_URL=https://skynet.xdcindia.com/api/v1
NODE_ID=node_abc123def456
NODE_NAME=my-xdc-node
```

**Mount this file in Docker:**

```yaml
volumes:
  - /etc/xdc-node/skynet.conf:/etc/xdc-node/skynet.conf:ro
```

---

## Dashboard Features

### 1. Main Overview Page (`/`)

**URL:** `http://localhost:7070`

**Displays:**
- **Node Status Card** — Current block height, sync progress, network ID
- **System Stats Grid** — CPU, memory, disk usage in real-time
- **SkyNet Status Card** — Heartbeat connection indicator and last seen time
- **Recent Alerts Timeline** — Latest warnings and errors with timestamps

**Visual Indicators:**
- 🟢 **Green** — Node healthy, syncing normally
- 🟡 **Yellow** — Node degraded, minor issues detected
- 🔴 **Red** — Node offline or critical error
- ⚫ **Grey** — Service disabled or not configured

### 2. Peers Page (`/peers`)

**URL:** `http://localhost:7070/peers`

**Displays:**
- **Peer list table** — All connected peers with IPs and Node IDs
- **Geographic distribution** — Peer locations on world map (if available)
- **Connection stats** — Inbound vs outbound peers, protocol versions
- **Peer health scores** — Based on latency and block propagation

**Actions:**
- View peer details (client version, network info)
- Filter by connection type (inbound/outbound)
- Sort by block height or latency

### 3. Alerts Page (`/alerts`)

**URL:** `http://localhost:7070/alerts`

**Alert Types:**
- 🔴 **Critical** — Node offline, sync stalled >10 min, no peers
- 🟡 **Warning** — Low peer count (<5), high sync lag (>100 blocks)
- 🔵 **Info** — Sync started, new peers connected, updates available

**Features:**
- Timeline view with relative timestamps
- Alert history (last 24 hours)
- Acknowledgement and dismissal
- Export alerts to JSON/CSV

### 4. Network Page (`/network`)

**URL:** `http://localhost:7070/network`

**Displays:**
- **Chain statistics** — Total transactions, network hashrate, validator count
- **Block explorer link** — Quick access to block details on XDCScan
- **Network health metrics** — Block time, finality, fork detection
- **Consensus info** — Current epoch, validator set, missed blocks

### 5. Sidebar Navigation

**Always visible (collapsible):**
- Dashboard (home icon)
- Peers list
- Alerts timeline
- Network stats
- **SkyNet Heartbeat Indicator** — Pulsing dot with connection status

**Collapsed mode:**
- Shows only icons
- Heartbeat indicator remains visible as colored dot
- Expands on hover

---

## API Endpoints

The dashboard exposes several API routes for external tools:

### `GET /api/metrics`

Returns comprehensive node metrics including diagnostics.

**Response when node is healthy:**

```json
{
  "status": "healthy",
  "nodeStatus": "syncing",
  "currentBlock": 75234567,
  "highestBlock": 75234600,
  "syncProgress": 99.95,
  "peerCount": 23,
  "networkId": 50,
  "clientVersion": "XDC/v1.4.8-stable",
  "timestamp": "2026-02-14T07:20:00Z"
}
```

**Response when node is unhealthy:**

```json
{
  "status": "error",
  "nodeStatus": "offline",
  "diagnostics": {
    "containerStatus": "running",
    "lastKnownBlock": 75234500,
    "errors": ["RPC connection refused", "Timeout after 5000ms"],
    "recentLogs": [
      "2026-02-14 07:15:23 ERROR Failed to connect to peer",
      "2026-02-14 07:16:45 WARN Sync stalled at block 75234500"
    ],
    "systemStats": {
      "cpu": 12.4,
      "memory": 45.6,
      "disk": 67.8
    }
  },
  "timestamp": "2026-02-14T07:20:00Z"
}
```

**Usage:**

```bash
curl http://localhost:7070/api/metrics
```

### `GET /api/health`

Simple health check endpoint.

**Response:**

```json
{
  "status": "healthy",
  "uptime": 86400,
  "timestamp": "2026-02-14T07:20:00Z"
}
```

### `GET /api/peers`

Returns list of connected peers.

**Response:**

```json
{
  "peers": [
    {
      "id": "enode://abc123...",
      "name": "XDC/v1.4.8",
      "network": {
        "localAddress": "192.168.1.100:30303",
        "remoteAddress": "203.0.113.50:30303"
      },
      "protocols": {
        "xdc": {
          "version": 66,
          "head": "0x7f8a9b..."
        }
      }
    }
  ],
  "count": 23
}
```

### `GET /api/heartbeat`

Returns SkyNet heartbeat status.

**Response:**

```json
{
  "enabled": true,
  "status": "connected",
  "lastHeartbeat": "2026-02-14T07:18:30Z",
  "timeSinceLastHeartbeat": 90,
  "skynetUrl": "https://skynet.xdcindia.com/api/v1",
  "nodeId": "node_abc123def456",
  "nodeName": "my-xdc-node",
  "error": null
}
```

**Status values:**
- `connected` — Heartbeat within last 2 minutes
- `pending` — Heartbeat 2-5 minutes ago
- `offline` — Heartbeat >5 minutes ago
- `error` — Heartbeat failed with error
- `disabled` — SkyNet not configured

---

## Theming

### Dark Theme (Default)

Optimized for low-light environments with:
- Dark backgrounds (#0A0E27, #1A1F3A)
- Light text (#E5E7EB)
- Blue accents (#1E90FF)
- High contrast for readability

### Light Theme

Activates automatically based on system preference or via `.light` class:
- Light backgrounds (#FFFFFF, #F3F4F6)
- Dark text (#1F2937)
- Same accent blue (#1E90FF)
- Adjusted shadows and borders

**CSS Variables (globals.css):**

```css
:root {
  /* Dark theme */
  --background: #0A0E27;
  --foreground: #E5E7EB;
  --card: #1A1F3A;
  --accent: #1E90FF;
}

@media (prefers-color-scheme: light) {
  :root {
    --background: #FFFFFF;
    --foreground: #1F2937;
    --card: #F3F4F6;
    --accent: #1E90FF;
  }
}
```

**Manual toggle (future):**

```typescript
// Add theme toggle button in Sidebar
const [theme, setTheme] = useState('dark')
const toggleTheme = () => {
  setTheme(theme === 'dark' ? 'light' : 'dark')
  document.documentElement.classList.toggle('light')
}
```

---

## Troubleshooting

### Dashboard shows "Node Offline"

**Check RPC connectivity:**

```bash
# Inside dashboard container
curl http://xdc-node:8545 -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

**If connection refused:**
- Verify `RPC_URL` environment variable
- Check XDC node is running: `docker ps | grep xdc-node`
- Ensure both containers are on same network

### Metrics API returns empty data

**Check diagnostics:**

```bash
curl http://localhost:7070/api/metrics
```

**If diagnostics missing:**
- Dashboard may not have access to `/proc` for system stats
- Mount `/proc:/host/proc:ro` in docker-compose.yml
- Restart dashboard container

### SkyNet status shows "Not configured"

**Verify config file exists:**

```bash
docker exec xdc-agent cat /etc/xdc-node/skynet.conf
```

**If file missing:**
- Create `/etc/xdc-node/skynet.conf` on host
- Mount it in docker-compose.yml
- Run `setup.sh` to auto-generate config

### Light theme not working

**Check CSS media query:**

```bash
# Inspect globals.css
grep -A 10 "prefers-color-scheme: light" dashboard/app/globals.css
```

**Force light theme:**

```typescript
// Add to app/layout.tsx
<html className="light">
```

### Dashboard won't build

**Clear Next.js cache:**

```bash
cd dashboard
rm -rf .next node_modules
npm install
npm run build
```

**Check TypeScript errors:**

```bash
npm run type-check
```

---

## Performance Optimization

### Reduce API polling frequency

Edit refresh intervals in components:

```typescript
// app/page.tsx
const REFRESH_INTERVAL = 60000 // 60 seconds instead of 30

// components/Sidebar.tsx
const HEARTBEAT_POLL_INTERVAL = 30000 // 30 seconds instead of 10
```

### Enable production build optimizations

```bash
# Build with optimization flags
NODE_ENV=production npm run build

# Verify bundle size
npm run analyze
```

### Use CDN for static assets

Add CDN URLs to `next.config.js`:

```javascript
module.exports = {
  assetPrefix: process.env.CDN_URL || '',
  images: {
    domains: ['cdn.example.com']
  }
}
```

---

## Security Best Practices

### 1. Restrict dashboard access

**Use reverse proxy with authentication:**

```nginx
location / {
  proxy_pass http://localhost:7070;
  auth_basic "XDC Dashboard";
  auth_basic_user_file /etc/nginx/.htpasswd;
}
```

### 2. Enable HTTPS

**Use Let's Encrypt with Nginx:**

```bash
certbot --nginx -d dashboard.example.com
```

### 3. Firewall rules

**Allow only from specific IPs:**

```bash
sudo ufw allow from 203.0.113.0/24 to any port 7070
```

### 4. Read-only RPC access

Ensure XDC node RPC has restricted permissions (no `personal_*` or `admin_*` methods exposed).

---

## Development Guide

### Project Structure

```
dashboard/
├── app/
│   ├── page.tsx              # Main dashboard page
│   ├── layout.tsx            # Root layout with sidebar
│   ├── globals.css           # Global styles and themes
│   ├── peers/page.tsx        # Peers list page
│   ├── alerts/page.tsx       # Alerts timeline page
│   ├── network/page.tsx      # Network stats page
│   └── api/
│       ├── metrics/route.ts  # Metrics API endpoint
│       ├── health/route.ts   # Health check endpoint
│       ├── peers/route.ts    # Peers API endpoint
│       └── heartbeat/route.ts # SkyNet heartbeat API
├── components/
│   ├── Sidebar.tsx           # Navigation sidebar with heartbeat indicator
│   ├── SkyNetStatus.tsx      # SkyNet connection status card
│   └── AlertCard.tsx         # Alert display component
├── lib/
│   └── rpc.ts                # XDC RPC client utilities
├── public/
│   └── logo.svg              # XDC SkyOne logo
└── package.json              # Dependencies and scripts
```

### Adding a new feature

**Example: Add transaction pool monitoring**

1. **Create API route:**

```typescript
// app/api/txpool/route.ts
export async function GET() {
  const rpcUrl = process.env.RPC_URL || 'http://xdc-node:8545'
  const response = await fetch(rpcUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      method: 'txpool_status',
      params: [],
      id: 1
    })
  })
  const data = await response.json()
  return Response.json(data.result)
}
```

2. **Create component:**

```typescript
// components/TxPoolCard.tsx
'use client'
import { useState, useEffect } from 'react'

export default function TxPoolCard() {
  const [txPool, setTxPool] = useState({ pending: 0, queued: 0 })

  useEffect(() => {
    const fetchTxPool = async () => {
      const res = await fetch('/api/txpool')
      const data = await res.json()
      setTxPool(data)
    }
    fetchTxPool()
    const interval = setInterval(fetchTxPool, 10000)
    return () => clearInterval(interval)
  }, [])

  return (
    <div className="card">
      <h3>Transaction Pool</h3>
      <p>Pending: {txPool.pending}</p>
      <p>Queued: {txPool.queued}</p>
    </div>
  )
}
```

3. **Add to main page:**

```typescript
// app/page.tsx
import TxPoolCard from '@/components/TxPoolCard'

export default function Home() {
  return (
    <main>
      {/* existing cards */}
      <TxPoolCard />
    </main>
  )
}
```

### Running tests

```bash
# Unit tests
npm run test

# E2E tests with Playwright
npm run test:e2e

# Type checking
npm run type-check

# Linting
npm run lint
```

---

## FAQ

**Q: Can I run the dashboard without Docker?**  
A: Yes, use `npm run dev` for development or `npm run build && npm start` for production. Set `RPC_URL` environment variable.

**Q: How do I change the dashboard port?**  
A: Set `PORT=8080` environment variable or change port mapping in docker-compose.yml.

**Q: Does the dashboard work with testnet?**  
A: Yes, just point `RPC_URL` to your testnet node (port 8545 by default).

**Q: Can I customize the branding?**  
A: Yes, replace logo in `public/logo.svg` and update colors in `globals.css`.

**Q: How do I enable authentication?**  
A: Use a reverse proxy (Nginx, Caddy) with basic auth or OAuth. Dashboard itself doesn't include auth.

**Q: What browsers are supported?**  
A: All modern browsers (Chrome, Firefox, Safari, Edge). Requires JavaScript enabled.

---

## Support

- **Documentation:** [https://docs.xdc.network/](https://docs.xdc.network/)
- **GitHub Issues:** [https://github.com/AnilChinchawale/XDC-Node-Setup/issues](https://github.com/AnilChinchawale/XDC-Node-Setup/issues)
- **Discord:** [XDC Network Discord](https://discord.gg/xdc)

---

**Built with Next.js 15, TypeScript, and Tailwind CSS**  
**Part of the XDC SkyOne ecosystem**
