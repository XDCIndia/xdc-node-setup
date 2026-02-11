# XDC Node Dashboard

A comprehensive web dashboard for monitoring and managing XDC Network nodes.

![Dashboard Screenshot](../docs/images/dashboard-overview.png)

## Quick Start

### Option 1: Docker (Recommended)

The full monitoring stack includes Grafana, Prometheus, and the XDC node.

```bash
cd docker && docker compose up -d

# Access:
# Grafana:   http://localhost:3000 (admin/admin)
# Prometheus: http://localhost:9090
```

### Option 2: Next.js Dashboard (Development)

For local development with hot reloading:

```bash
cd dashboard
npm install
npm run dev

# Dashboard: http://localhost:3001
```

### Option 3: Next.js Dashboard (Production)

For production deployment:

```bash
cd dashboard
npm install
npm run build
npm start

# Dashboard: http://localhost:3001
```

### Option 4: Docker Build (Dashboard Only)

```bash
docker build -t xdc-dashboard .
docker run -p 3001:3000 \
  -v $(pwd)/../reports:/app/reports:ro \
  -v $(pwd)/../configs:/app/configs:ro \
  xdc-dashboard

# Dashboard: http://localhost:3001
```

## Monitoring Stack Overview

| Service | Port | URL | Description |
|---------|------|-----|-------------|
| Grafana | 3000 | http://localhost:3000 | Pre-configured dashboards |
| Next.js Dashboard | 3001 | http://localhost:3001 | Custom web UI |
| Prometheus | 9090 | http://localhost:9090 | Metrics database |
| Node Exporter | 9100 | (internal) | System metrics |
| cAdvisor | 8080 | (internal) | Container metrics |

## Grafana Dashboards

Two pre-configured dashboards are available:

### XDC Node Monitor (`xdc-node-main`)
- Node Overview: Block height, peer count, sync status, uptime
- System Metrics: CPU, memory, disk usage
- Disk Performance: I/O throughput, IOPS
- Container Metrics: Docker resource usage
- Chain Metrics: Epoch progress, blocks per minute

### XDC Consensus & Rewards (`xdc-consensus`)
- Epoch Info: Current epoch, progress, countdown
- Masternode Status: Active nodes, rankings
- Rewards: Daily earnings, APY, missed blocks
- Network Health: Block time, peer count, TX rate

## Features

- **Overview Dashboard** — Summary cards, network stats, and recent alerts
- **Node Management** — View all nodes with real-time status, metrics, and filtering
- **Node Details** — Historical charts, security checklist, and node-specific actions
- **Security Dashboard** — Fleet security score, per-node audits, and recommendations
- **Version Management** — Track client versions across all nodes with auto-update support
- **Alert System** — Timeline view of all alerts with acknowledge/dismiss functionality
- **Settings** — Notification channels, node registration, API keys, and theme

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `API_KEY` | API key for write operations | (none) |
| `PORT` | Server port | 3000 |
| `REPORTS_DIR` | Path to health reports | `../reports` |
| `CONFIGS_DIR` | Path to configuration files | `../configs` |

### Metrics Collection

XDC-specific metrics are collected via the `scripts/metrics-collector.sh` script:

```bash
# Install as cron job (every 15 seconds via systemd timer recommended)
sudo cp scripts/metrics-collector.sh /opt/xdc-node/scripts/
sudo chmod +x /opt/xdc-node/scripts/metrics-collector.sh

# Create textfile collector directory
sudo mkdir -p /var/lib/node_exporter/textfile_collector

# Test manually
sudo /opt/xdc-node/scripts/metrics-collector.sh

# Add to crontab for periodic collection
echo "* * * * * root /opt/xdc-node/scripts/metrics-collector.sh" | sudo tee /etc/cron.d/xdc-metrics
```

The metrics collector provides:
- `xdc_block_number` - Current block height
- `xdc_peer_count` - Connected peers
- `xdc_syncing` - Sync status (0=synced, 1=syncing)
- `xdc_epoch_number` - Current epoch
- `xdc_epoch_progress` - Epoch progress (0-100%)
- `xdc_chain_id` - Chain ID
- `xdc_client_version` - Client version label

### API Authentication

Read operations (GET) are public by default. Write operations (POST, PUT) require an API key:

```bash
# Set in environment
export API_KEY=your-secret-key

# Or in .env.local
echo "API_KEY=your-secret-key" >> .env.local
```

Include the key in requests:

```bash
curl -X POST http://localhost:3001/api/health \
  -H "x-api-key: your-secret-key"
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/nodes` | GET | List all nodes with current status |
| `/api/nodes/[id]` | GET | Get single node details |
| `/api/health` | POST | Trigger health check |
| `/api/versions` | GET | Get version configuration |
| `/api/versions` | POST | Trigger version check |
| `/api/alerts` | GET | Get all alerts |
| `/api/alerts` | POST | Acknowledge/dismiss alert |
| `/api/security` | GET | Get security scores |
| `/api/security` | POST | Run security audit |
| `/api/settings` | GET/PUT | Read/write settings |

## Directory Structure

```
dashboard/
├── src/
│   ├── app/
│   │   ├── api/          # REST API routes
│   │   ├── nodes/        # Node pages
│   │   ├── security/     # Security dashboard
│   │   ├── versions/     # Version management
│   │   ├── alerts/       # Alert history
│   │   ├── settings/     # Settings page
│   │   ├── layout.tsx    # Root layout
│   │   ├── page.tsx      # Overview dashboard
│   │   └── globals.css   # Global styles
│   ├── components/       # Reusable UI components
│   └── lib/              # Utility functions and types
├── public/               # Static assets
├── package.json
├── tailwind.config.js
└── tsconfig.json
```

## Tech Stack

- **Framework:** Next.js 14 (App Router)
- **Styling:** Tailwind CSS
- **Charts:** Recharts
- **Language:** TypeScript

## Design

- **Dark Theme** — `#0a0a0f` background, `#1a1a2e` cards
- **XDC Branding** — Primary blue `#1F4CED`
- **Status Colors:**
  - Healthy: `#10B981` (green)
  - Warning: `#F59E0B` (yellow)
  - Critical: `#EF4444` (red)
- **Typography:** Fira Sans

## Troubleshooting

### Grafana shows "No Data"

1. Check if metrics-collector.sh is running:
   ```bash
   cat /var/lib/node_exporter/textfile_collector/xdc_metrics.prom
   ```

2. Verify Prometheus is scraping node-exporter:
   ```bash
   curl http://localhost:9090/api/v1/targets
   ```

3. Check if XDC RPC is accessible:
   ```bash
   curl -X POST http://localhost:8545 \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
   ```

### Next.js Dashboard won't start

1. Ensure Node.js 18+ is installed:
   ```bash
   node --version
   ```

2. Clear node_modules and reinstall:
   ```bash
   rm -rf node_modules package-lock.json
   npm install
   ```

3. Check if port 3001 is available:
   ```bash
   lsof -i :3001
   ```

## License

MIT — See [LICENSE](../LICENSE)
