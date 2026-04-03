# XDC Node Setup — Plugin System

Plugins are self-contained scripts that collect metrics from a running XDC node
and emit a JSON object to stdout. They can be run individually or orchestrated
by `scripts/plugin-manager.sh`.

---

## Plugin Interface

### Input (environment variables)

| Variable         | Required | Description                          |
|------------------|----------|--------------------------------------|
| `XDC_RPC_PORT`   | ✅       | HTTP-RPC port of the target node     |
| `XDC_CLIENT`     | optional | Client name (geth/erigon/nethermind/reth) |
| `XDC_TIMEOUT`    | optional | RPC timeout in seconds (default: 5)  |
| `XDC_DATA_DIR`   | optional | Node data directory (for disk checks)|

### Output (stdout — JSON)

Every plugin **must** emit a single-line JSON object:

```json
{
  "plugin":    "sync-check",
  "timestamp": "2026-04-03T07:00:00Z",
  "status":    "ok",
  "metrics": {
    "key": value,
    ...
  },
  "error": null
}
```

Fields:

| Field       | Type             | Description                                           |
|-------------|------------------|-------------------------------------------------------|
| `plugin`    | string           | Plugin identifier (matches directory name)            |
| `timestamp` | ISO-8601 string  | UTC time of measurement                               |
| `status`    | "ok"/"warn"/"err"| Health signal                                         |
| `metrics`   | object           | Plugin-specific key/value pairs                       |
| `error`     | string or null   | Non-null if an error occurred during collection       |

### Exit codes

| Code | Meaning                       |
|------|-------------------------------|
| 0    | Plugin ran successfully       |
| 1    | Non-fatal warning             |
| 2    | Fatal error (no metrics)      |

---

## Built-in Plugins

| Plugin        | Description                          |
|---------------|--------------------------------------|
| `sync-check`  | Checks node sync status              |
| `peer-check`  | Checks current peer count            |
| `disk-check`  | Checks data directory disk usage     |

---

## Plugin Manager

```bash
scripts/plugin-manager.sh install  <path|url>     # install a plugin
scripts/plugin-manager.sh list                     # list installed plugins
scripts/plugin-manager.sh run      <name> [port]   # run a plugin
scripts/plugin-manager.sh remove   <name>          # remove a plugin
```

---

## Writing a Plugin

1. Create a directory under `plugins/<your-plugin>/`
2. Add `check.sh` — must be executable, reads env vars, emits JSON
3. Optionally add `plugin.json` with metadata:

```json
{
  "name":        "my-plugin",
  "version":     "1.0.0",
  "description": "What this plugin does",
  "author":      "you"
}
```

### Minimal template

```bash
#!/bin/bash
PORT="${XDC_RPC_PORT:-8545}"
TIMEOUT="${XDC_TIMEOUT:-5}"

result=$(curl -sf --max-time "$TIMEOUT" -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  "http://127.0.0.1:${PORT}" 2>/dev/null) || {
  echo '{"plugin":"my-plugin","timestamp":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","status":"err","metrics":{},"error":"rpc unreachable"}'
  exit 2
}

block=$(echo "$result" | grep -o '"result":"0x[^"]*"' | cut -d'"' -f4)

cat <<EOF
{"plugin":"my-plugin","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","status":"ok","metrics":{"block_hex":"${block}"},"error":null}
EOF
```
