# Monitoring Setup Guide

Complete guide for setting up monitoring and alerting for XDC Network nodes.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Grafana Dashboards](#2-grafana-dashboards)
3. [Prometheus Configuration](#3-prometheus-configuration)
4. [Alerting Rules](#4-alerting-rules)
5. [Telegram Bot Setup](#5-telegram-bot-setup)
6. [NetOwn Fleet Monitoring](#6-netown-fleet-monitoring)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Overview

The monitoring stack consists of:

- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **Node Exporter**: System metrics (CPU, RAM, disk)
- **cAdvisor**: Container metrics
- **Alertmanager**: Alert routing (optional)

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Monitoring Stack                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐      ┌──────────────┐                    │
│  │  XDC Node    │──────▶│  Prometheus  │                    │
│  │  (metrics)   │      │  (storage)   │                    │
│  └──────────────┘      └──────┬───────┘                    │
│                               │                             │
│  ┌──────────────┐             ▼                             │
│  │ Node Exporter│      ┌──────────────┐                    │
│  │  (system)    │──────▶│   Grafana    │                    │
│  └──────────────┘      │ (dashboards) │                    │
│                        └──────────────┘                    │
│                               │                             │
│  ┌──────────────┐             ▼                             │
│  │   cAdvisor   │      ┌──────────────┐                    │
│  │ (containers) │──────▶│  Telegram    │                    │
│  └──────────────┘      │  (alerts)    │                    │
│                        └──────────────┘                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Grafana Dashboards

### Accessing Grafana

```bash
# Via SSH tunnel (recommended for security)
ssh -L 3000:localhost:3000 root@your-server-ip -p 12141

# Then open http://localhost:3000 in your browser
```

Default credentials:
- Username: `admin`
- Password: `admin` (change on first login)

### Available Dashboards

| Dashboard | URL | Description |
|-----------|-----|-------------|
| XDC Node Overview | `/d/xdc-node-dashboard` | Main node health dashboard |
| System Metrics | `/d/system-metrics` | CPU, RAM, disk, network |
| Container Metrics | `/d/container-metrics` | Docker container stats |

### Dashboard Panels

#### XDC Node Overview

| Panel | Metric | Alert Threshold |
|-------|--------|-----------------|
| Block Height | `xdpos_head_block` | Behind by >100 blocks |
| Peer Count | `xdpos_peers` | <3 peers |
| Sync Status | `xdpos_syncing` | Not synced >10 min |
| RPC Calls | `xdpos_rpc_calls_total` | N/A |

#### System Metrics

| Panel | Metric | Alert Threshold |
|-------|--------|-----------------|
| CPU Usage | `node_cpu_seconds_total` | >90% for 15 min |
| Memory Usage | `node_memory_MemAvailable_bytes` | <10% available |
| Disk Usage | `node_filesystem_avail_bytes` | >85% used |
| Network I/O | `node_network_*_bytes_total` | N/A |

### Custom Dashboard Creation

1. Click **+** → **Dashboard**
2. Add panel → Select metric
3. Configure visualization:
   - Graph for time series
   - Stat for single values
   - Gauge for percentages

Example query:
```promql
# Block height
xdpos_head_block{job="xdc-node"}

# Peer count
xdpos_peers{job="xdc-node"}

# Disk usage percentage
100 - ((node_filesystem_avail_bytes{mountpoint="/root/xdcchain"} / node_filesystem_size_bytes{mountpoint="/root/xdcchain"}) * 100)
```

---

## 3. Prometheus Configuration

### Configuration File

Located at: `/opt/xdc-node/monitoring/prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: []  # Add alertmanager here if configured

rule_files:
  - 'alerts.yml'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'xdc-node'
    static_configs:
      - targets: ['xdc-node:6060']
    metrics_path: /debug/metrics/prometheus

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
```

### Reloading Configuration

```bash
# Send SIGHUP to reload config
docker kill -s HUP xdc-prometheus

# Or use API
curl -X POST http://localhost:9090/-/reload
```

### Retention

Default retention: **30 days**

To change retention, edit `docker-compose.yml`:
```yaml
command:
  - '--storage.tsdb.retention.time=90d'
```

---

## 4. Alerting Rules

### Default Alerts

Located at: `/opt/xdc-node/monitoring/alerts.yml`

| Alert | Condition | Severity |
|-------|-----------|----------|
| XDCNodeDown | Node not responding | Critical |
| HighDiskUsage | Disk >85% | Warning |
| CriticalDiskUsage | Disk >95% | Critical |
| HighMemoryUsage | RAM >90% | Warning |
| HighCPUUsage | CPU >90% for 15min | Warning |
| XDCPeerCountLow | Peers <3 | Warning |
| XDCPeerCountZero | Peers = 0 | Critical |

### Custom Alert Example

```yaml
groups:
  - name: custom-alerts
    rules:
      - alert: BlockProductionSlow
        expr: rate(xdpos_head_block[5m]) < 0.3
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Block production is slow"
          description: "Block production rate is below 0.3 blocks/minute"
```

### Alert Routing (Alertmanager)

Create `/opt/xdc-node/monitoring/alertmanager.yml`:

```yaml
global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'alerts@xdc-node.local'

route:
  receiver: 'telegram'
  group_by: ['alertname', 'severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h

receivers:
  - name: 'telegram'
    telegram_configs:
      - bot_token: '${TELEGRAM_BOT_TOKEN}'
        chat_id: ${TELEGRAM_CHAT_ID}
        message: |
          {{ range .Alerts }}
          {{ .Annotations.summary }}
          {{ .Annotations.description }}
          {{ end }}

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname']
```

---

## 5. Telegram Bot Setup

### Creating a Bot

1. Message [@BotFather](https://t.me/botfather) on Telegram
2. Send `/newbot`
3. Follow prompts to create bot
4. Save the **HTTP API token**

### Getting Chat ID

**Method 1: Via Bot**
```
1. Message your new bot
2. Visit: https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates
3. Look for "chat":{"id":123456789
```

**Method 2: Via Group**
```
1. Add bot to your group
2. Send a message in the group
3. Visit: https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates
4. Look for "chat":{"id":-123456789
```

### Configuration

Add to `/opt/xdc-node/configs/node.env`:
```bash
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here
```

Reload configuration:
```bash
docker compose -f /opt/xdc-node/docker/docker-compose.yml up -d
```

### Testing

```bash
# Run health check with notification
/opt/xdc-node/scripts/node-health-check.sh --notify
```

### Message Format

Example alert message:
```
🟢 XDC Node Health Report

Server: xdc-node-01
Status: HEALTHY
Time: 2026-02-11 12:00:00 UTC

Metrics:
• Block Height: 12345678
• Peers: 15
• Sync: SYNCED
• Disk: 45%
• RAM: 62%
• Security: 🟢 Excellent (95/100)

Checks:
• block height: ✅
• peer count: ✅
• sync status: ✅
• disk usage: ✅
• cpu usage: ✅
```

---

## 6. Troubleshooting

### Grafana Not Loading

```bash
# Check if container is running
docker ps | grep grafana

# Check logs
docker logs xdc-grafana

# Restart Grafana
docker compose -f /opt/xdc-node/docker/docker-compose.yml restart grafana

# Check port binding
ss -tlnp | grep 3000
```

### No Metrics in Prometheus

```bash
# Check targets
curl http://localhost:9090/api/v1/targets | jq

# Check if exporters are running
docker ps | grep exporter

# Check node-exporter logs
docker logs xdc-node-exporter
```

### Alerts Not Firing

```bash
# Check alert rules
curl http://localhost:9090/api/v1/rules | jq

# Check alert status
curl http://localhost:9090/api/v1/alerts | jq

# Test alert manually
curl -X POST http://localhost:9090/-/reload
```

### Dashboard Shows No Data

1. Verify time range (top right of Grafana)
2. Check Prometheus is scraping targets
3. Verify metrics exist:
   ```bash
   curl 'http://localhost:9090/api/v1/label/__name__/values' | jq
   ```
4. Check for typos in queries

### High Memory Usage

```bash
# Check Prometheus retention
docker exec xdc-prometheus ps aux

# Reduce retention period
# Edit docker-compose.yml and add:
# --storage.tsdb.retention.time=15d

# Restart Prometheus
docker compose -f /opt/xdc-node/docker/docker-compose.yml restart prometheus
```

---

## 6. NetOwn Fleet Monitoring

NetOwn provides centralized fleet monitoring for XDC nodes with automatic registration, health reporting, and security scoring.

### Overview

The NetOwn Agent runs as a Docker sidecar container alongside your XDC node:

- **Auto-registration**: Nodes self-register with the NetOwn platform
- **Heartbeat reporting**: Sends health metrics every 60 seconds
- **Security scoring**: Analyzes SSH config, firewall rules, and system hardening
- **Fleet dashboard**: View all nodes at https://net.xdc.network

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    XDC Node Server                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐      ┌──────────────┐                    │
│  │   XDC Node   │      │ NetOwn Agent │──────┐              │
│  │   (Docker)   │      │  (Sidecar)   │      │              │
│  └──────────────┘      └──────────────┘      │              │
│                                              │              │
└──────────────────────────────────────────────┼──────────────┘
                                               │
                                               ▼
                                      ┌──────────────────┐
                                      │  NetOwn Platform │
                                      │ net.xdc.network  │
                                      └──────────────────┘
```

### Enabling NetOwn Agent

#### Option 1: With Docker Compose (New Install)

Enable the `netown` profile when starting services:

```bash
cd /opt/xdc-node/docker

# Copy the agent script and config template
cp ../scripts/netown-agent.sh ./netown-agent.sh
cp ../configs/netown.conf.template ./netown.conf

# Edit configuration
nano netown.conf
```

Configure your `netown.conf`:
```bash
# Required: Your NetOwn API endpoint
NETOWN_API_URL=https://net.xdc.network/api/v1

# Required: Your node's API key (get from NetOwn dashboard)
NETOWN_API_KEY=your-api-key-here

# Required: Your node ID (assigned during registration)
NETOWN_NODE_ID=your-node-id-here

# RPC endpoint of the XDC node
RPC_URL=http://127.0.0.1:8545

# Optional: Node name for display
NODE_NAME=my-xdc-node
```

Start with the netown profile:
```bash
docker compose --profile netown up -d
```

#### Option 2: Standalone Agent (Existing Node)

For nodes already running that you want to add monitoring to:

```bash
mkdir -p /opt/netown-agent
cd /opt/netown-agent

# Download agent files
curl -O https://raw.githubusercontent.com/XDC-Node-Setup/main/scripts/netown-agent.sh
curl -O https://raw.githubusercontent.com/XDC-Node-Setup/main/configs/netown.conf.template
mv netown.conf.template netown.conf

# Edit configuration
nano netown.conf
# Fill in your API key and node ID

# Download standalone compose file
curl -O https://raw.githubusercontent.com/XDC-Node-Setup/main/docker/netown-agent-standalone.yml

# Start the agent
docker compose -f netown-agent-standalone.yml up -d
```

### Configuration Options

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NETOWN_API_URL` | Yes | - | NetOwn API endpoint |
| `NETOWN_API_KEY` | Yes | - | Your API key from NetOwn dashboard |
| `NETOWN_NODE_ID` | Yes | - | Unique node identifier |
| `RPC_URL` | No | `http://127.0.0.1:8545` | XDC node RPC endpoint |
| `NODE_NAME` | No | Hostname | Display name for the node |

### Registering a New Node

1. **Get API credentials**: Visit https://net.xdc.network/dashboard
2. **Create node entry**: Click "Add Node" and note the assigned Node ID
3. **Generate API key**: Create an API key for the node
4. **Configure agent**: Add credentials to `netown.conf`
5. **Start agent**: Run `docker compose up -d`
6. **Verify**: Check the dashboard for the node's first heartbeat

### Verifying Agent Operation

Check container status:
```bash
docker ps --filter "name=netown-agent"
```

View agent logs:
```bash
docker logs netown-agent --tail 50
```

Check fleet status via API:
```bash
curl -s https://net.xdc.network/api/v1/fleet/status | jq '.nodes[] | {name, status, security_score}'
```

### Troubleshooting NetOwn Agent

#### Agent Not Reporting

**Symptoms**: Node shows as offline in dashboard

**Checklist**:
1. Verify container is running:
   ```bash
   docker ps | grep netown-agent
   ```

2. Check for configuration errors:
   ```bash
   docker logs netown-agent --tail 20
   ```

3. Verify RPC endpoint is accessible:
   ```bash
   curl -X POST http://localhost:8545 \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
   ```

4. Check API credentials are correct in `netown.conf`

5. Restart the agent:
   ```bash
   docker restart netown-agent
   ```

#### Security Score Low

**Symptoms**: Security score below 80 in dashboard

**Common issues**:
- **SSH password auth enabled**: Disable in `/etc/ssh/sshd_config`:
  ```
  PasswordAuthentication no
  ChallengeResponseAuthentication no
  ```
- **Root login allowed**: Set `PermitRootLogin no`
- **Missing firewall rules**: Ensure UFW or iptables is active

#### Network Connectivity Issues

The agent requires outbound HTTPS access to `net.xdc.network`:

```bash
# Test connectivity
curl -I https://net.xdc.network/api/v1/health

# Check DNS resolution
nslookup net.xdc.network
```

---

## 7. Troubleshooting

### XDC Node Metrics

| Metric | Description | Type |
|--------|-------------|------|
| `xdpos_head_block` | Current block height | Gauge |
| `xdpos_peers` | Number of connected peers | Gauge |
| `xdpos_rpc_calls_total` | Total RPC calls | Counter |
| `xdpos_txpool_pending` | Pending transactions | Gauge |

### System Metrics (Node Exporter)

| Metric | Description |
|--------|-------------|
| `node_cpu_seconds_total` | CPU usage by mode |
| `node_memory_MemTotal_bytes` | Total RAM |
| `node_memory_MemAvailable_bytes` | Available RAM |
| `node_filesystem_size_bytes` | Filesystem size |
| `node_filesystem_avail_bytes` | Available space |
| `node_network_receive_bytes_total` | Network received |
| `node_network_transmit_bytes_total` | Network transmitted |

---

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Node Exporter](https://github.com/prometheus/node_exporter)
- [Telegram Bot API](https://core.telegram.org/bots/api)
