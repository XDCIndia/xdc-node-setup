#!/usr/bin/env bash
# snapshot-serve.sh — Snapshot Distribution Network (#130)
# Serve local snapshots via HTTP and register with SkyNet as snapshot source.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SNAPSHOT_DIR="${SNAPSHOT_DIR:-${REPO_ROOT}/data/snapshots}"
SERVE_PORT="${SERVE_PORT:-8888}"
PID_FILE="/tmp/snapshot-serve.pid"
LOG_FILE="/tmp/snapshot-serve.log"
SKYONE_URL="${SKYONE_URL:-http://localhost:7070}"
PUBLIC_URL="${PUBLIC_URL:-http://$(hostname -I | awk '{print $1}'):${SERVE_PORT}}"

mkdir -p "$SNAPSHOT_DIR"

usage() {
  cat <<EOF
Usage: $(basename "$0") <start|stop|status>

Commands:
  start   Start HTTP snapshot server (port ${SERVE_PORT})
  stop    Stop the snapshot server
  status  Show server status and available snapshots

Environment:
  SNAPSHOT_DIR  Directory to serve (default: data/snapshots)
  SERVE_PORT    HTTP port (default: 8888)
  SKYONE_URL    SkyNet API base URL
  PUBLIC_URL    Publicly accessible URL for registration
EOF
  exit 1
}

register_with_skyone() {
  local url="$1"
  log "Registering snapshot source with SkyNet: ${url}"

  # List available snapshots
  local snapshots=()
  while IFS= read -r -d '' f; do
    snapshots+=("\"$(basename "$f")\"")
  done < <(find "$SNAPSHOT_DIR" -name "*.tar.gz" -o -name "*.lz4" -o -name "*.zst" 2>/dev/null -print0)

  local snap_list="[$(IFS=,; echo "${snapshots[*]:-}")]"

  curl -sf -X POST "${SKYONE_URL}/api/v2/snapshots/register" \
    -H 'Content-Type: application/json' \
    -d "{\"url\":\"${url}\",\"snapshots\":${snap_list},\"registered\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
    2>/dev/null && log "✅ Registered with SkyNet" || log "⚠️  SkyNet registration failed (non-fatal)"
}

log() { echo "[$(date +%H:%M:%S)] $*"; }

cmd_start() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    log "Already running (PID $(cat "$PID_FILE"))"
    exit 0
  fi

  log "Starting snapshot server on port ${SERVE_PORT}..."
  log "Serving directory: ${SNAPSHOT_DIR}"

  # Try python3 first, then busybox httpd
  if command -v python3 &>/dev/null; then
    (cd "$SNAPSHOT_DIR" && python3 -m http.server "$SERVE_PORT" \
      >> "$LOG_FILE" 2>&1) &
    echo $! > "$PID_FILE"
    log "✅ Started with python3 (PID $(cat "$PID_FILE"))"
  elif busybox httpd --help 2>/dev/null | grep -q httpd; then
    busybox httpd -p "$SERVE_PORT" -h "$SNAPSHOT_DIR" -f >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    log "✅ Started with busybox httpd (PID $(cat "$PID_FILE"))"
  else
    log "ERROR: Neither python3 nor busybox httpd available" >&2
    exit 1
  fi

  sleep 1
  if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    log "Server listening at: http://0.0.0.0:${SERVE_PORT}"
    register_with_skyone "$PUBLIC_URL"
  else
    log "ERROR: Server failed to start. Check log: $LOG_FILE" >&2
    rm -f "$PID_FILE"
    exit 1
  fi
}

cmd_stop() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    kill "$(cat "$PID_FILE")"
    rm -f "$PID_FILE"
    log "✅ Snapshot server stopped"
  else
    log "Not running"
  fi
}

cmd_status() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    log "✅ Running (PID $(cat "$PID_FILE")) on port ${SERVE_PORT}"
    log "   URL: http://0.0.0.0:${SERVE_PORT}"
    log "   Public URL: ${PUBLIC_URL}"
  else
    log "❌ Not running"
  fi

  echo ""
  echo "Available snapshots in ${SNAPSHOT_DIR}:"
  find "$SNAPSHOT_DIR" \( -name "*.tar.gz" -o -name "*.lz4" -o -name "*.zst" -o -name "*.tar" \) \
    -printf "  %f  (%s bytes)\n" 2>/dev/null || echo "  (none found)"
}

CMD="${1:-}"
case "$CMD" in
  start)  cmd_start ;;
  stop)   cmd_stop ;;
  status) cmd_status ;;
  *)      usage ;;
esac
