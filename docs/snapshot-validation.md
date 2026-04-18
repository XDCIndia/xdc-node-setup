# Snapshot Validation Guide

**Issue:** [#165](https://github.com/XDCIndia/xdc-node-setup/issues/165)  
**Phase:** 1.2

---

## Overview

Snapshot validation ensures that downloaded or restored chaindata is complete and usable before a node starts syncing. Incomplete or corrupted snapshots can cause nodes to crash-loop, sync from genesis, or get stuck at an unexpected block height.

XNS (XDC Node Setup) now includes automated snapshot validation at three levels:

| Level | Speed | What It Checks |
|-------|-------|----------------|
| **Quick** | ~5 seconds | File structure, database engine, CURRENT marker, non-empty ancient store |
| **Standard** | ~30-60 seconds | Quick checks + file count/size heuristics + block-to-state consistency |
| **Full** | ~2-5 minutes | Standard checks + sample trie key verification + ancient segment continuity |

---

## Validation Levels

### Quick (`--quick`)

Best for: rapid pre-transfer checks, CI gates, frequent health checks

```bash
xdc snapshot validate --quick
```

Checks performed:
- Chaindata directory layout (auto-detects `geth/`, `XDC/`, `xdcchain/`)
- Database engine (LevelDB vs Pebble)
- `CURRENT` marker file exists
- Ancient store directory is non-empty
- Minimum file count threshold

### Standard (`--standard`, default)

Best for: post-download validation, pre-deployment checks

```bash
xdc snapshot validate
```

Additional checks:
- Chaindata size against network-aware minimums
- Block height vs state height gap within tolerance
- Ancient segment file count

### Full (`--full`)

Best for: deep forensic validation after incidents

```bash
xdc snapshot validate --full
```

Additional checks:
- Sample key-prefix verification (requires `rocksdb-tools`)
- Ancient segment continuity (no gaps in body/header/receipt sequences)

---

## CLI Reference

```
USAGE:
    xdc snapshot validate [OPTIONS]

OPTIONS:
    --datadir, -d <path>    Data directory to validate (default: $XDC_DATA)
    --quick                 Fast structural check (~5s)
    --standard              Structural + heuristic checks (~30-60s) [default]
    --full                  Deep database inspection (~2-5min)
    --json                  Output JSON instead of human-readable table
    --output, -o <file>     Write JSON report to file
    --fail-fast             Exit non-zero on first failure
    --notify                Send alert on failure (requires notify.conf)
    --no-color              Disable colored output
    --help, -h              Show help

EXIT CODES:
    0  Validation passed (warnings may be present)
    1  Validation failed
    2  Bad arguments / missing dependencies
    3  Datadir not found / no chaindata
```

### Examples

```bash
# Standard validation on default datadir
xdc snapshot validate

# Quick check with JSON output
xdc snapshot validate --quick --json

# Full validation with report file
xdc snapshot validate --full --output /tmp/validation-report.json

# Validate a specific datadir
xdc snapshot validate --datadir /mnt/xdc-data/mainnet/xdcchain

# Fail fast (exit on first critical failure)
xdc snapshot validate --fail-fast

# Send notification on failure
xdc snapshot validate --notify
```

### JSON Output Schema

```json
{
  "valid": true,
  "level": "standard",
  "datadir": "/data/mainnet/xdcchain",
  "chaindataSubdir": "geth",
  "checks": {
    "layout": {"passed": true, "detail": "geth/chaindata"},
    "databaseEngine": {"passed": true, "detail": "pebble"},
    "fileCount": {"passed": true, "actual": 52341, "minimum": 50000},
    "ancientStore": {"passed": true, "segments": {"headers": 1240, "bodies": 1240, "receipts": 1240}},
    "stateRootCache": {"passed": false, "severity": "warn", "detail": "xdc-state-root-cache.csv missing"},
    "blockStateConsistency": {"passed": true, "blockHeight": 98543210, "stateHeight": 98543210, "gap": 0}
  },
  "summary": "All critical checks passed (1 warning)",
  "timestamp": "2026-04-18T09:30:00Z"
}
```

---

## Pre-Deployment Gate

Starting with Phase 1.2, `scripts/deploy.sh` automatically validates existing chaindata before starting the node.

### Flow

```
┌─────────────────┐
│   deploy.sh     │
└────────┬────────┘
         │
         ▼
┌─────────────────────┐
│ preflight-check.sh  │  (existing: ports, disk, docker)
└────────┬────────────┘
         │
         ▼
┌──────────────────────────┐
│ validate-snapshot-deep.sh │────▶ notify.sh (on failure)
│    --quick --json         │     alert operators
└────────┬─────────────────┘
         │
    ┌────┴────┐
    ▼         ▼
 PASS       FAIL
    │         │
    ▼         ▼
docker    EXIT 1 — log failures
compose   Operator must remediate
up -d     or set SKIP env var
```

### Skipping Validation (Emergency)

If you need to force deployment despite validation failures:

```bash
export XDC_SKIP_SNAPSHOT_VALIDATION=true
xdc deploy
```

> ⚠️ Only use this in emergencies. Skipping validation on a corrupted snapshot will likely cause the node to crash-loop.

---

## Failure Reference

| Failure Code | Meaning | Remediation |
|-------------|---------|-------------|
| `NO_CHAINDATA` | No chaindata directory found | Check `--datadir` path, run `xdc init` |
| `INSUFFICIENT_FILES` | Too few database files (`.sst`/`.ldb`) | Snapshot incomplete — re-download from a trusted source |
| `ANCIENT_STORE_MISSING` | Ancient store directory empty or missing | Archive extraction incomplete — re-extract or re-download |
| `STATE_GAP_EXCEEDED` | State trie lags behind block height by > threshold | State trie incomplete — sync from a newer snapshot or sync from genesis |
| `CHECKSUM_MISMATCH` | GPG/SHA256 signature verification failed | Use `xdc snapshot verify <file>` for cryptographic verification |
| `DATABASE_ENGINE_UNKNOWN` | Cannot detect LevelDB or Pebble | Check chaindata integrity, may be a non-standard client |

---

## Metrics

Validation results are exported as Prometheus-compatible metrics.

### Metric Names

| Metric | Type | Description |
|--------|------|-------------|
| `xdc_snapshot_validation_total` | counter | Total validations run, labeled by `level` and `result` |
| `xdc_snapshot_validation_duration_seconds` | gauge | Duration of the most recent validation |
| `xdc_snapshot_state_gap_blocks` | gauge | Gap between block height and state height |
| `xdc_snapshot_validation_last_timestamp` | gauge | Unix timestamp of the most recent validation |
| `xdc_snapshot_validation_last_result` | gauge | Result of last validation (1=passed, 0=failed) |

### Alert Rule Example

```yaml
- alert: XdcSnapshotValidationFailed
  expr: xdc_snapshot_validation_last_result == 0
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Snapshot validation failed on {{ $labels.instance }}"
    description: "Pre-deployment snapshot validation has failed. Deployment is blocked."

- alert: XdcSnapshotStateGapHigh
  expr: xdc_snapshot_state_gap_blocks > 100
  for: 15m
  labels:
    severity: warning
  annotations:
    summary: "Large state gap detected on {{ $labels.instance }}"
    description: "State is {{ $value }} blocks behind block height."
```

### Running the Metrics Exporter

```bash
# Manual run
scripts/metrics/snapshot-validation-metrics.sh

# Cron (every 5 minutes)
*/5 * * * * /opt/xdc-node-setup/scripts/metrics/snapshot-validation-metrics.sh

# With custom output path
scripts/metrics/snapshot-validation-metrics.sh --output /tmp/custom.prom
```

---

## Troubleshooting

### "Deep validator not found"

Ensure `scripts/validate-snapshot-deep.sh` exists and is executable:

```bash
ls -la scripts/validate-snapshot-deep.sh
chmod +x scripts/validate-snapshot-deep.sh
```

### "No database files found"

Check if the chaindata uses a different subdirectory:

```bash
find /data/xdcchain -type f \( -name "*.sst" -o -name "*.ldb" \) | head -5
```

### Validation passes but node still crashes

The validator checks structural completeness, not consensus validity. If the node crashes with consensus errors (bad block, invalid merkle root), the snapshot may be from a forked chain or have corrupted state. In this case:

1. Download a fresh snapshot from an official source
2. Verify with `xdc snapshot verify <file>` (cryptographic)
3. Re-validate with `xdc snapshot validate --full`

### Where are reports stored?

- Validation logs: `${XDC_STATE_DIR}/metrics/snapshot-validation.log`
- Pre-transfer reports: `${XDC_STATE_DIR}/validation-reports/`
- Prometheus metrics: `/var/lib/node_exporter/textfile_collector/xdc_snapshot_validation.prom`

---

## Related

- [Issue #165](https://github.com/XDCIndia/xdc-node-setup/issues/165)
- `scripts/validate-snapshot-deep.sh`
- `scripts/lib/snapshot-validation.sh`
- `configs/snapshots.json`
