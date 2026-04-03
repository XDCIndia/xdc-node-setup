#!/usr/bin/env bash
# log-streamer.sh — Stream container logs via WebSocket (#114)
# Tails docker container logs and pipes to SkyNet WebSocket live log viewer.
# Uses websocat if available, fallback to netcat with HTTP upgrade handshake.
set -euo pipefail

SKYONE_WS_URL="${SKYONE_WS_URL:-ws://localhost:7070/api/v2/logs/stream}"
CONTAINER="${1:-xdc-geth}"
LINES="${LOG_TAIL_LINES:-100}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [container] [options]

  container     Docker container name (default: xdc-geth)

Options:
  --ws URL      WebSocket endpoint (default: ${SKYONE_WS_URL})
  --tail N      Initial tail lines (default: ${LINES})
  --list        List available XDC containers
  --test        Test connectivity only

Environment:
  SKYONE_WS_URL  WebSocket URL for log streaming
  LOG_TAIL_LINES Number of initial lines to tail

Examples:
  $(basename "$0") xdc-erigon
  $(basename "$0") xdc-geth --ws ws://localhost:7070/api/v2/logs/stream
  $(basename "$0") --list
EOF
  exit 1
}

log() { echo "[$(date +%H:%M:%S)] $*" >&2; }

list_containers() {
  echo "Available XDC containers:"
  docker ps --format '  {{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null \
    | grep -i xdc || echo "  (none running)"
}

check_container() {
  local name="$1"
  docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"
}

stream_with_websocat() {
  local container="$1"
  local ws_url="$2"
  log "Streaming '${container}' → ${ws_url} via websocat"

  # Send container name as connection header, then pipe logs
  docker logs --follow --tail "${LINES}" --timestamps "$container" 2>&1 \
    | websocat --text --no-close \
        --header "X-Container: ${container}" \
        --header "X-Source: xdc-node-setup" \
        "$ws_url"
}

stream_with_nc() {
  local container="$1"
  local ws_url="$2"

  # Parse WS URL into host/port/path
  local url="${ws_url#ws://}"
  url="${url#wss://}"
  local host_port="${url%%/*}"
  local path="/${url#*/}"
  local host="${host_port%%:*}"
  local port="${host_port##*:}"
  [[ "$port" == "$host" ]] && port=80

  log "Streaming '${container}' → ${host}:${port}${path} via netcat (degraded)"
  log "NOTE: For full WebSocket support, install websocat: cargo install websocat"

  # Minimal HTTP/1.1 upgrade + line-by-line pipe
  {
    printf "GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" \
      "$path" "$host_port"
    printf "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
    printf "Sec-WebSocket-Version: 13\r\nX-Container: %s\r\n\r\n" "$container"

    # Send log lines as plain text frames (non-standard but functional for HTTP fallback)
    docker logs --follow --tail "${LINES}" --timestamps "$container" 2>&1 \
      | while IFS= read -r line; do
          printf '%s\n' "$line"
        done
  } | nc -q 1 "$host" "$port" > /dev/null 2>&1 || true
}

stream_to_file() {
  local container="$1"
  local logfile="/tmp/${container}-stream.log"
  log "WebSocket unavailable — writing to ${logfile}"
  docker logs --follow --tail "${LINES}" --timestamps "$container" 2>&1 \
    | tee -a "$logfile"
}

test_connectivity() {
  local ws_url="$1"
  log "Testing connectivity to: ${ws_url}"

  local http_url="${ws_url/ws:\/\//http://}"
  http_url="${http_url/wss:\/\//https://}"

  if curl -sf --max-time 5 "${http_url%/*}" &>/dev/null; then
    log "✅ SkyNet endpoint reachable"
  else
    log "⚠️  SkyNet endpoint not reachable: ${http_url}"
  fi

  if command -v websocat &>/dev/null; then
    log "✅ websocat available: $(websocat --version 2>/dev/null | head -1)"
  else
    log "⚠️  websocat not found (install: cargo install websocat)"
  fi
}

main() {
  local ws_url="$SKYONE_WS_URL"
  local test_only=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ws)     ws_url="$2"; shift ;;
      --tail)   LINES="$2"; shift ;;
      --list)   list_containers; exit 0 ;;
      --test)   test_only=true ;;
      --help|-h) usage ;;
      xdc-*|*)  CONTAINER="$1" ;;
    esac
    shift
  done

  if [[ "$test_only" == "true" ]]; then
    test_connectivity "$ws_url"
    exit 0
  fi

  log "=== Log Streamer ==="
  log "  Container: ${CONTAINER}"
  log "  WS URL: ${ws_url}"
  log "  Tail: ${LINES} lines"

  if ! check_container "$CONTAINER"; then
    log "ERROR: Container '${CONTAINER}' not running"
    list_containers
    exit 1
  fi

  # Choose streaming method
  if command -v websocat &>/dev/null; then
    stream_with_websocat "$CONTAINER" "$ws_url"
  elif command -v nc &>/dev/null; then
    stream_with_nc "$CONTAINER" "$ws_url"
  else
    stream_to_file "$CONTAINER"
  fi
}

main "$@"
