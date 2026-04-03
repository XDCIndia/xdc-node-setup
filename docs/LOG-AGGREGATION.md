# XDC Node Log Aggregation Guide

This guide covers setting up centralized log aggregation for XDC nodes using Grafana Loki, Promtail, and Grafana.

## Overview

The logging stack consists of:

| Component | Purpose | Port |
|-----------|---------|------|
| **Loki** | Log aggregation backend | 3100 |
| **Promtail** | Log collection agent | 9080 |
| **Grafana** | Visualization dashboard | 3200 |

```
┌─────────────┐     ┌──────────────┐     ┌─────────┐
│  XDC Nodes  │────▶│   Promtail   │────▶│  Loki   │
│  (logs)     │     │  (collector) │     │ (store) │
└─────────────┘     └──────────────┘     └────┬────┘
                                              │
                                         ┌────▼────┐
                                         │ Grafana │
                                         │ (view)  │
                                         └─────────┘
```

## Quick Start

### Using XDC CLI

```bash
# Start XDC node with logging stack
xdc start --logging

# Or add logging to existing node
xdc logging start

# Search logs
xdc logs --search "error"

# Stop logging stack
xdc logging stop
```

### Using Docker Compose

```bash
cd docker
docker compose -f docker-compose.logging.yml up -d
```

### Access Grafana

1. Open http://localhost:3200
2. Login with:
   - Username: `admin`
   - Password: `xdcadmin` (default)
3. Navigate to "XDC Node Logs" dashboard

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `XDC_DATA_DIR` | `/xdcchain` | XDC node data directory |
| `GRAFANA_ADMIN_USER` | `admin` | Grafana admin username |
| `GRAFANA_ADMIN_PASSWORD` | `xdcadmin` | Grafana admin password |
| `GRAFANA_ROOT_URL` | `http://localhost:3200` | External Grafana URL |

### Loki Configuration

Edit `configs/loki/config.yml`:

```yaml
# Retention period (default: 30 days)
limits_config:
  retention_period: 720h

# Max log line size
  max_line_size: 256kb

# Storage location
common:
  path_prefix: /loki
```

### Promtail Configuration

Edit `configs/promtail/config.yml` to add custom log sources:

```yaml
scrape_configs:
  - job_name: custom-logs
    static_configs:
      - targets: [localhost]
        labels:
          job: my-custom-job
          __path__: /var/log/myapp/*.log
```

## Log Sources

### XDC Node Logs

| Log File | Description |
|----------|-------------|
| `/xdcchain/XDC.log` | Main node log |
| `/xdcchain/rpc.log` | JSON-RPC request logs |
| `/xdcchain/masternode.log` | Masternode operations |
| `/xdcchain/consensus.log` | XDPoS consensus logs |

### Docker Container Logs

Containers with label `com.xdc.node=true` are automatically discovered.

### System Logs

- `/var/log/syslog` - System messages
- systemd journal - Service logs

## Log Queries (LogQL)

### Basic Queries

```logql
# All XDC node logs
{job="xdc-node"}

# Filter by log level
{job="xdc-node", level="ERROR"}

# Search for text
{job="xdc-node"} |= "sync"

# Regex match
{job="xdc-node"} |~ "block [0-9]+"
```

### Advanced Queries

```logql
# Count errors per minute
count_over_time({job="xdc-node", level="ERROR"}[1m])

# Error rate
rate({job="xdc-node", level="ERROR"}[5m])

# Top 10 error messages
topk(10, sum by (message) (count_over_time({job="xdc-node", level="ERROR"}[1h])))

# Logs from specific component
{job="xdc-node", component="eth"} |= "block"
```

### CLI Search

```bash
# Search for errors
xdc logs --search "error"

# Filter by level
xdc logs --search "level=ERROR"

# Search with time range
xdc logs --search "sync" --since "1h"

# Output as JSON
xdc logs --search "block" --format json

# Follow logs in real-time
xdc logs --follow
```

## Grafana Dashboard

### Pre-built Panels

1. **Total Log Entries** - Total count in time range
2. **Error Count** - Errors with threshold alerts
3. **Warning Count** - Warnings with threshold alerts
4. **Log Rate** - Logs per second (5m average)
5. **Log Volume by Level** - Stacked bar chart
6. **Logs by Component** - Pie chart breakdown
7. **Logs by Source** - Pie chart by job
8. **XDC Node Logs** - Full log viewer
9. **Errors & Warnings** - Filtered critical logs
10. **Docker Logs** - Container log viewer

### Variables

- **Search** - Full-text search across logs
- **Job** - Filter by log source
- **Level** - Filter by log level

### Creating Alerts

1. Go to Alerting → Alert rules
2. Create new rule:
   ```logql
   count_over_time({job="xdc-node", level="ERROR"}[5m]) > 10
   ```
3. Set notification channels

## Resource Usage

### Estimated Storage

| Log Volume | Daily Storage | 30-day Retention |
|------------|---------------|------------------|
| Low (~100MB/day) | ~30MB compressed | ~1GB |
| Medium (~1GB/day) | ~300MB compressed | ~10GB |
| High (~10GB/day) | ~3GB compressed | ~100GB |

### Memory Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| Loki | 256MB | 1GB |
| Promtail | 128MB | 256MB |
| Grafana | 256MB | 512MB |

## Troubleshooting

### Logs Not Appearing

1. Check Promtail status:
   ```bash
   docker logs xdc-promtail
   ```

2. Verify log paths exist:
   ```bash
   ls -la /xdcchain/XDC.log
   ```

3. Check Loki health:
   ```bash
   curl http://localhost:3100/ready
   ```

### High Memory Usage

1. Reduce retention period in Loki config
2. Increase chunk_idle_period
3. Add rate limits in Promtail

### Query Timeouts

1. Reduce time range
2. Add more specific label filters
3. Use streaming queries for large ranges

## Production Recommendations

### Security

1. Change default Grafana password:
   ```bash
   export GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 32)
   ```

2. Enable HTTPS with reverse proxy

3. Restrict network access:
   ```yaml
   ports:
     - "127.0.0.1:3100:3100"  # Loki - local only
     - "127.0.0.1:3200:3000"  # Grafana - local only
   ```

### High Availability

For production deployments, consider:

1. **Loki Cluster Mode** - Multiple read/write replicas
2. **Object Storage** - S3/GCS/MinIO for log storage
3. **External Grafana** - Dedicated Grafana instance

### Monitoring the Monitors

Add Loki/Promtail metrics to Prometheus:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'loki'
    static_configs:
      - targets: ['loki:3100']
  - job_name: 'promtail'
    static_configs:
      - targets: ['promtail:9080']
```

## Integration with SkyNet

The logging stack integrates with SkyNet for:

- Centralized multi-node log aggregation
- Alert forwarding to SkyNet dashboard
- Log-based anomaly detection
- Compliance log archival

Configure SkyNet integration:

```bash
xdc config set skynet.logs.enabled true
xdc config set skynet.logs.endpoint https://logs.skyskynet.xdcindia.com
```

## References

- [Grafana Loki Documentation](https://grafana.com/docs/loki/)
- [LogQL Query Language](https://grafana.com/docs/loki/latest/logql/)
- [Promtail Configuration](https://grafana.com/docs/loki/latest/send-data/promtail/)
- [XDC Network Documentation](https://docs.xdc.network/)

---

*Last Updated: February 2026*
