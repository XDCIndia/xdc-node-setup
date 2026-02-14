# XDC Node Log Management

This document describes the logging architecture for XDC Node Setup.

## Overview

The XDC Node Setup implements a comprehensive logging system with the following features:

- **Docker log rotation**: Automatic container log management via Docker's json-file driver
- **Persistent log storage**: Component logs stored in `{network}/.xdc-node/logs/`
- **Automated rotation**: Daily log rotation with compression and retention policies
- **CLI access**: Convenient log viewing via `xdc logs` command

## Log Types

### 1. Docker Container Logs

Docker container logs are managed by the Docker daemon using the `json-file` logging driver.

**Configuration** (in `docker/docker-compose.yml`):
```yaml
logging:
  driver: "json-file"
  options:
    max-size: "50m"
    max-file: "5"
```

This ensures:
- Maximum log file size: 50MB per file
- Maximum number of files: 5 (per container)
- Total maximum per container: 250MB

**Viewing Docker logs**:
```bash
# View xdc-node container logs
docker logs xdc-node

# Follow logs
docker logs -f xdc-node

# View last 100 lines
docker logs --tail 100 xdc-node
```

### 2. Component Logs

Component logs are stored persistently in `{network}/.xdc-node/logs/`:

| Log File | Description | Source |
|----------|-------------|--------|
| `heartbeat.log` | SkyNet heartbeat status | xdc-agent |
| `lfg.log` | LFG peer discovery activity | xdc-agent |
| `dashboard.log` | Dashboard startup and runtime | xdc-agent |

**Access via CLI**:
```bash
# View heartbeat logs
xdc logs --component heartbeat

# Follow LFG logs
xdc logs --component lfg -f

# View dashboard logs (last 100 lines)
xdc logs --component dashboard -n 100
```

### 3. XDC Chain Logs

XDC node application logs are stored in `{network}/xdcchain/`:

- `xdc.log` - Main XDC node log output
- `XDC.log` - Alternative log file name
- Additional client-specific logs (geth.log, erigon.log)

## Log Rotation

### Automated Rotation

Log rotation is performed daily at 2:00 AM via cron job:

```bash
# Cron job location
0 2 * * * /path/to/scripts/log-rotate.sh
```

**Rotation process**:
1. Move logs older than 24 hours to `oldlogs/` directory
2. Compress rotated logs with gzip
3. Delete logs older than retention period (default: 7 days)

**Configurable retention**:
```bash
# Set retention period (in days)
export LOG_RETENTION_DAYS=14

# Run rotation manually
xdc logs --rotate
```

### Manual Rotation

```bash
# Trigger manual rotation
xdc logs --rotate

# Clean old logs
xdc logs --clean
```

## Directory Structure

```
{network}/
├── .xdc-node/
│   └── logs/
│       ├── heartbeat.log       # SkyNet heartbeat
│       ├── lfg.log             # Peer discovery
│       ├── dashboard.log       # Dashboard output
│       └── oldlogs/            # Rotated & compressed logs
│           ├── heartbeat-2024-01-15.log.gz
│           ├── lfg-2024-01-15.log.gz
│           └── ...
└── xdcchain/
    ├── xdc.log                 # Node logs
    └── oldlogs/                # Rotated chain logs
        └── ...
```

## CLI Commands

### View Logs

```bash
# Default: show node logs
xdc logs

# Show specific component
xdc logs --component heartbeat
xdc logs --component lfg
xdc logs --component dashboard
xdc logs --component node

# Follow logs (real-time)
xdc logs -f
xdc logs --component heartbeat -f

# Number of lines
xdc logs -n 100
xdc logs --component lfg -n 50

# Time-based filtering
xdc logs --since 1h      # Last hour
xdc logs --since 30m     # Last 30 minutes
xdc logs --since 2024-01-01  # Since specific date
```

### Log Management

```bash
# Manual rotation
xdc logs --rotate

# Clean old logs
xdc logs --clean

# Combined options
xdc logs --component heartbeat -f -n 100
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_RETENTION_DAYS` | 7 | Number of days to retain old logs |
| `NETWORK` | mainnet | Network type (affects log path) |

### Docker Compose

The docker-compose.yml includes log configuration for all services:

```yaml
services:
  xdc-node:
    # ...
    volumes:
      - ../${NETWORK:-mainnet}/.xdc-node/logs:/var/log/xdc
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"

  xdc-agent:
    # ...
    volumes:
      - ../${NETWORK:-mainnet}/.xdc-node/logs:/var/log/xdc
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"
```

## Troubleshooting

### Log files not appearing

1. Check directory permissions:
   ```bash
   ls -la {network}/.xdc-node/logs/
   ```

2. Verify container is running:
   ```bash
   docker ps | grep xdc
   ```

3. Check bind mount in container:
   ```bash
   docker exec xdc-agent ls -la /var/log/xdc/
   ```

### Rotation not working

1. Check cron job exists:
   ```bash
   crontab -l | grep log-rotate
   ```

2. Run manually to check for errors:
   ```bash
   bash scripts/log-rotate.sh
   ```

3. Check rotation log:
   ```bash
   cat {network}/.xdc-node/log-rotation.log
   ```

### Disk space issues

1. Check log sizes:
   ```bash
   du -sh {network}/.xdc-node/logs/
   du -sh {network}/xdcchain/oldlogs/
   ```

2. Reduce retention period:
   ```bash
   export LOG_RETENTION_DAYS=3
   xdc logs --rotate
   xdc logs --clean
   ```

3. Clean Docker logs:
   ```bash
   docker system prune --volumes
   ```

## Architecture Diagram

```
┌─────────────────┐     ┌─────────────────┐
│   xdc-node      │     │   xdc-agent     │
│   (container)   │     │   (container)   │
└────────┬────────┘     └────────┬────────┘
         │                       │
         │ Docker json-file      │ Docker json-file
         │ (max: 50m x 5)        │ (max: 50m x 5)
         │                       │
         ▼                       ▼
┌─────────────────────────────────────────┐
│         Docker Daemon Logs              │
└─────────────────────────────────────────┘
         │                       │
         │ Bind mount            │ Bind mount
         │ /var/log/xdc          │ /var/log/xdc
         │                       │
         ▼                       ▼
┌─────────────────────────────────────────┐
│    {network}/.xdc-node/logs/            │
│    ├── heartbeat.log                    │
│    ├── lfg.log                          │
│    └── dashboard.log                    │
└─────────────────────────────────────────┘
         │
         │ Daily rotation (2:00 AM)
         │ LOG_RETENTION_DAYS (default: 7)
         ▼
┌─────────────────────────────────────────┐
│    {network}/.xdc-node/logs/oldlogs/    │
│    ├── heartbeat-2024-01-15.log.gz      │
│    └── ...                              │
└─────────────────────────────────────────┘
```

## See Also

- [CLI Documentation](CLI.md) - Full CLI reference
- [Monitoring Guide](MONITORING.md) - Prometheus/Grafana setup
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues and solutions
