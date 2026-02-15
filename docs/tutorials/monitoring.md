# Monitoring Your XDC Node

Set up comprehensive monitoring with Prometheus, Grafana, and alerting for your XDC node.

## Quick Health Check

```bash
# One-liner health status
xdc health

# Detailed JSON report
xdc health --json | jq .
```

## Built-in Monitoring

### Status Dashboard
```bash
xdc status            # Quick overview
xdc status --json     # Machine-readable
xdc status --sync     # Sync progress
xdc status --peers    # Peer information
```

### Log Monitoring
```bash
xdc logs                    # Live logs
xdc logs --tail 100         # Last 100 lines
xdc logs --filter "error"   # Filter by keyword
xdc logs --since 1h         # Last hour
```

## Prometheus + Grafana Stack

### Step 1: Enable Metrics

```bash
xdc config set metrics.enabled true
xdc config set metrics.port 9090
xdc restart
```

### Step 2: Deploy Monitoring Stack

```bash
xdc monitoring start
```

This deploys:
- **Prometheus** on port 9090 — metrics collection
- **Grafana** on port 3000 — dashboards (default login: `admin`/`admin`)
- **Node Exporter** on port 9100 — system metrics
- **Alertmanager** on port 9093 — alert routing

### Step 3: Access Grafana

Open `http://your-server-ip:3000` and import the included XDC dashboard.

Pre-built dashboards:
- **XDC Node Overview** — block height, peer count, sync status
- **System Resources** — CPU, RAM, disk, network
- **Masternode Performance** — blocks signed, uptime, rewards

## Key Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `xdc_block_height` | Current block number | Falling behind network |
| `xdc_peer_count` | Connected peers | < 3 peers |
| `xdc_sync_status` | Sync state (0/1) | Not synced for > 5 min |
| `xdc_rpc_latency_ms` | RPC response time | > 500 ms |
| `system_disk_free_bytes` | Available disk | < 20 GB |
| `system_cpu_usage_percent` | CPU utilization | > 90% sustained |

## Alert Configuration

### Slack Alerts
```bash
xdc config set alerts.slack.webhook "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
xdc config set alerts.slack.channel "#xdc-alerts"
```

### Email Alerts
```bash
xdc config set alerts.email.to "admin@example.com"
xdc config set alerts.email.smtp "smtp.gmail.com:587"
```

### PagerDuty
```bash
xdc config set alerts.pagerduty.key "YOUR_INTEGRATION_KEY"
```

## Alert Rules

Default alert rules (configurable in `monitoring/alerts.yml`):

```yaml
- alert: NodeDown
  expr: up{job="xdc-node"} == 0
  for: 2m
  labels:
    severity: critical

- alert: SyncLagging
  expr: xdc_blocks_behind > 100
  for: 5m
  labels:
    severity: warning

- alert: LowPeers
  expr: xdc_peer_count < 3
  for: 10m
  labels:
    severity: warning

- alert: DiskSpaceLow
  expr: node_filesystem_avail_bytes{mountpoint="/"} < 20e9
  for: 5m
  labels:
    severity: critical
```

## Uptime Monitoring

For external uptime monitoring, expose the health endpoint:

```bash
# Check from outside
curl -s http://your-server:8545 -X POST \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

Integrate with:
- **UptimeRobot** — free, checks every 5 min
- **Pingdom** — advanced SLA reporting
- **Datadog** — full infrastructure monitoring

## Stopping Monitoring

```bash
xdc monitoring stop
```

## Next Steps

- [Masternode Setup](./masternode-setup.md) — If you're running a validator
- [Troubleshooting](../TROUBLESHOOTING.md) — When alerts fire
