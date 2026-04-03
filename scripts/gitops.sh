#!/usr/bin/env bash
# gitops.sh — GitOps Fleet Deployment (#129)
# Watch git repo for changes, on new commit: pull → rebuild → rolling restart.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POLL_INTERVAL="${POLL_INTERVAL:-30}"
BRANCH="${BRANCH:-main}"
PID_FILE="/tmp/gitops-watch.pid"
LOG_FILE="/tmp/gitops-watch.log"
COMPOSE_FILE="${REPO_ROOT}/docker-compose.yml"
CLIENTS=("geth" "erigon" "nethermind")

usage() {
  cat <<EOF
Usage: $(basename "$0") <watch|deploy|stop|status>

Commands:
  watch   Start daemon watching git repo for changes
  deploy  One-shot: pull latest, rebuild, rolling restart
  stop    Stop the watch daemon
  status  Show daemon status

Environment:
  POLL_INTERVAL  Seconds between git checks (default: 30)
  BRANCH         Git branch to watch (default: main)
  CLIENTS        Space-separated list of client names
EOF
  exit 1
}

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

get_current_commit() {
  git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "unknown"
}

git_pull() {
  log "Pulling latest from origin/${BRANCH}..."
  git -C "$REPO_ROOT" fetch origin "$BRANCH" 2>&1
  local remote_commit
  remote_commit="$(git -C "$REPO_ROOT" rev-parse "origin/${BRANCH}" 2>/dev/null)"
  local local_commit
  local_commit="$(get_current_commit)"

  if [[ "$remote_commit" == "$local_commit" ]]; then
    echo "up-to-date"
    return 0
  fi

  git -C "$REPO_ROOT" pull origin "$BRANCH" 2>&1
  echo "updated"
}

rebuild() {
  log "Rebuilding Docker images..."
  if [[ -f "$COMPOSE_FILE" ]]; then
    docker compose -f "$COMPOSE_FILE" build --pull 2>&1 | tail -5
  else
    log "No docker-compose.yml found — skipping rebuild"
  fi
}

rolling_restart() {
  log "Starting rolling restart..."
  for client in "${CLIENTS[@]}"; do
    local container="xdc-${client}"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
      log "  Restarting ${container}..."
      docker restart "$container" 2>&1 && log "  ✅ ${container} restarted" \
        || log "  ⚠️  ${container} restart failed"
      sleep 10  # Stagger restarts
    else
      log "  ℹ️  ${container} not running — skipping"
    fi
  done

  # Also handle docker compose services
  if [[ -f "$COMPOSE_FILE" ]]; then
    docker compose -f "$COMPOSE_FILE" up -d --remove-orphans 2>&1 | tail -5
  fi
  log "Rolling restart complete"
}

cmd_deploy() {
  local before
  before="$(get_current_commit)"
  log "=== GitOps Deploy ==="
  log "Current commit: ${before}"

  local pull_result
  pull_result="$(git_pull)"

  local after
  after="$(get_current_commit)"

  if [[ "$pull_result" == "up-to-date" ]]; then
    log "Already up to date — no action needed"
    return 0
  fi

  log "Updated to: ${after}"
  rebuild
  rolling_restart
  log "=== Deploy Complete ==="
}

watch_loop() {
  log "=== GitOps Watch Starting (branch: ${BRANCH}, interval: ${POLL_INTERVAL}s) ==="
  local last_commit
  last_commit="$(get_current_commit)"
  log "Watching from commit: ${last_commit}"

  while true; do
    sleep "$POLL_INTERVAL"

    git -C "$REPO_ROOT" fetch origin "$BRANCH" --quiet 2>/dev/null || true
    local remote_commit
    remote_commit="$(git -C "$REPO_ROOT" rev-parse "origin/${BRANCH}" 2>/dev/null || echo 'unknown')"

    if [[ "$remote_commit" != "$last_commit" ]] && [[ "$remote_commit" != "unknown" ]]; then
      log "🔔 New commit detected: ${last_commit:0:8} → ${remote_commit:0:8}"
      cmd_deploy 2>&1 | tee -a "$LOG_FILE"
      last_commit="$(get_current_commit)"
    fi
  done
}

cmd_watch() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    log "Watch daemon already running (PID $(cat "$PID_FILE"))"
    exit 0
  fi

  watch_loop >> "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  log "✅ Watch daemon started (PID $(cat "$PID_FILE"))"
  log "   Log: $LOG_FILE"
}

cmd_stop() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    kill "$(cat "$PID_FILE")"
    rm -f "$PID_FILE"
    log "✅ Watch daemon stopped"
  else
    log "Not running"
  fi
}

cmd_status() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    log "✅ Watch daemon running (PID $(cat "$PID_FILE"))"
    log "   Branch: ${BRANCH}, interval: ${POLL_INTERVAL}s"
    log "   Current commit: $(get_current_commit)"
  else
    log "❌ Watch daemon not running"
  fi
}

CMD="${1:-}"
case "$CMD" in
  watch)  cmd_watch ;;
  deploy) cmd_deploy ;;
  stop)   cmd_stop ;;
  status) cmd_status ;;
  *)      usage ;;
esac
