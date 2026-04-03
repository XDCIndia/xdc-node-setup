#!/bin/bash
set -euo pipefail
# Self-Modifying Config Daemon — auto-adjusts node configs based on performance
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/118
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
INTERVAL=${1:-300}  # 5 min default
LOG_DIR="$ROOT_DIR/data/daemon"
mkdir -p "$LOG_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_DIR/daemon.log"; }

# Tunable parameters
PARAMS="maxpeers cache gcmode"

get_current_config() {
  local client="$1"
  docker inspect "$client" --format '{{join .Args " "}}' 2>/dev/null || echo ""
}

suggest_optimization() {
  local client="$1" port="$2"
  local peers=$(curl -s -m 2 -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' "http://localhost:$port" 2>/dev/null | \
    jq -r '.result // "0x0"')
  local peerCount=$((16#${peers#0x})) 2>/dev/null || peerCount=0
  
  # Low peers → increase maxpeers
  if [ "$peerCount" -lt 3 ]; then
    log "$client: Only $peerCount peers — suggest increasing maxpeers to 100"
    echo "maxpeers:100"
  # High peers → can reduce
  elif [ "$peerCount" -gt 40 ]; then
    log "$client: $peerCount peers — can reduce maxpeers to 30 to save bandwidth"
    echo "maxpeers:30"
  else
    echo "ok"
  fi
}

log "Config daemon started (interval: ${INTERVAL}s)"

while true; do
  for entry in "gp5-mainnet:8545" "erigon-mainnet:8547" "reth-mainnet:8548" "nm-mainnet:8558"; do
    client="${entry%%:*}"; port="${entry##*:}"
    status=$(docker inspect -f '{{.State.Status}}' "$client" 2>/dev/null || echo "missing")
    [ "$status" != "running" ] && continue
    
    suggestion=$(suggest_optimization "$client" "$port")
    if [ "$suggestion" != "ok" ]; then
      param="${suggestion%%:*}"; value="${suggestion##*:}"
      log "SUGGESTION: $client → $param=$value (dry-run, not auto-applying)"
      echo "{\"timestamp\":\"$(date -Iseconds)\",\"client\":\"$client\",\"param\":\"$param\",\"value\":\"$value\",\"applied\":false}" >> "$LOG_DIR/suggestions.jsonl"
    fi
  done
  
  sleep "$INTERVAL"
done
