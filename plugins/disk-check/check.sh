#!/bin/bash
#===============================================================================
# Plugin: disk-check
# Checks disk usage for the XDC node data directory.
# Output: JSON with used_gb, total_gb, percent_used, path.
#===============================================================================

PORT="${XDC_RPC_PORT:-8545}"
TIMEOUT="${XDC_TIMEOUT:-5}"
DATA_DIR="${XDC_DATA_DIR:-/opt/xdc-node/data}"
WARN_PCT="${XDC_DISK_WARN_PCT:-80}"
ERR_PCT="${XDC_DISK_ERR_PCT:-95}"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

_err() {
    printf '{"plugin":"disk-check","timestamp":"%s","status":"err","metrics":{},"error":"%s"}\n' "$TS" "$1"
    exit 2
}

# If DATA_DIR doesn't exist, try to infer from docker volume
if [[ ! -d "$DATA_DIR" ]]; then
    # Fallback: check the filesystem root
    DATA_DIR="/"
fi

# Get disk usage via df
df_out=$(df -k "$DATA_DIR" 2>/dev/null | tail -1) || _err "df_failed"

used_kb=$(echo "$df_out" | awk '{print $3}')
avail_kb=$(echo "$df_out" | awk '{print $4}')
total_kb=$(( used_kb + avail_kb ))
pct=$(echo "$df_out" | awk '{gsub(/%/,"",$5); print $5}')

# Convert to GB (2 decimal places using awk)
used_gb=$(awk "BEGIN {printf \"%.2f\", ${used_kb}/1048576}")
total_gb=$(awk "BEGIN {printf \"%.2f\", ${total_kb}/1048576}")
avail_gb=$(awk "BEGIN {printf \"%.2f\", ${avail_kb}/1048576}")

# Health threshold
if [[ $pct -ge $ERR_PCT ]]; then
    status="err"
elif [[ $pct -ge $WARN_PCT ]]; then
    status="warn"
else
    status="ok"
fi

# Also report actual data dir size if it exists
dir_size_gb="null"
if [[ -d "$DATA_DIR" && "$DATA_DIR" != "/" ]]; then
    dir_kb=$(du -sk "$DATA_DIR" 2>/dev/null | awk '{print $1}') || dir_kb=0
    dir_size_gb=$(awk "BEGIN {printf \"%.2f\", ${dir_kb}/1048576}")
fi

printf '{"plugin":"disk-check","timestamp":"%s","status":"%s","metrics":{"path":"%s","used_gb":%s,"avail_gb":%s,"total_gb":%s,"percent_used":%d,"warn_pct":%d,"err_pct":%d,"data_dir_gb":%s},"error":null}\n' \
    "$TS" "$status" "$DATA_DIR" "$used_gb" "$avail_gb" "$total_gb" "$pct" "$WARN_PCT" "$ERR_PCT" "${dir_size_gb:-null}"
