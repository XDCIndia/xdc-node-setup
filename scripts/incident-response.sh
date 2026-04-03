#!/usr/bin/env bash
#==============================================================================
# Autonomous Incident Response — Detect → Diagnose → Remediate → Verify
#
# Implements a full incident response loop for XDC nodes.
# Logs all actions to data/incidents/YYYY-MM-DD.json
#
# Usage:
#   ./incident-response.sh [--client geth|erigon|nethermind|reth] [--loop] [--dry-run]
#
# Options:
#   --client   Target a specific client (default: all)
#   --loop     Run continuously (poll every 60s)
#   --dry-run  Print actions without executing
#
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/121
#==============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly INCIDENT_DIR="${REPO_DIR}/data/incidents"
readonly TODAY="$(date +%Y-%m-%d)"
readonly INCIDENT_LOG="${INCIDENT_DIR}/${TODAY}.json"

# --- Defaults ---
TARGET_CLIENT="${CLIENT:-all}"
DRY_RUN=false
LOOP_MODE=false
POLL_INTERVAL="${POLL_INTERVAL:-60}"

# --- Client RPC ports ---
declare -A CLIENT_RPC_PORTS=(
  [geth]=8545
  [erigon]=8547
  [nethermind]=8548
  [reth]=8588
)

declare -A CLIENT_CONTAINERS=(
  [geth]="xdc-geth"
  [erigon]="xdc-erigon"
  [nethermind]="xdc-nethermind"
  [reth]="xdc-reth"
)

# --- Incident state ---
INCIDENT_ID=""
INCIDENT_SEVERITY="P3"
declare -a INCIDENT_ACTIONS=()

#==============================================================================
# Logging
#==============================================================================
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
log_action() {
  local action="$1"
  local result="${2:-ok}"
  local detail="${3:-}"
  INCIDENT_ACTIONS+=("{\"time\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"action\":\"${action}\",\"result\":\"${result}\",\"detail\":\"${detail}\"}")
  log "ACTION: ${action} → ${result} ${detail:+(${detail})}"
}

init_incident() {
  local severity="$1"
  local trigger="$2"
  mkdir -p "${INCIDENT_DIR}"
  INCIDENT_ID="INC-${TODAY//-/}-$(date +%H%M%S)"
  INCIDENT_SEVERITY="${severity}"
  INCIDENT_ACTIONS=()
  log "=== INCIDENT ${INCIDENT_ID} [${severity}] triggered by: ${trigger} ==="
}

write_incident_log() {
  local status="$1"
  local root_cause="${2:-unknown}"
  local resolution="${3:-}"
  local actions_json
  actions_json=$(printf '%s,' "${INCIDENT_ACTIONS[@]}" 2>/dev/null | sed 's/,$//')

  local entry
  entry=$(cat <<EOF
{
  "incident_id": "${INCIDENT_ID}",
  "severity": "${INCIDENT_SEVERITY}",
  "status": "${status}",
  "client": "${TARGET_CLIENT}",
  "root_cause": "${root_cause}",
  "resolution": "${resolution}",
  "actions": [${actions_json}]
}
EOF
)

  # Append to daily log (array format)
  if [[ -f "${INCIDENT_LOG}" ]]; then
    local tmp
    tmp=$(mktemp)
    # Remove trailing ] and append new entry
    sed '$ d' "${INCIDENT_LOG}" > "${tmp}"
    echo ",${entry}]" >> "${tmp}"
    mv "${tmp}" "${INCIDENT_LOG}"
  else
    echo "[${entry}]" > "${INCIDENT_LOG}"
  fi

  log "Incident logged: ${INCIDENT_LOG}"
}

#==============================================================================
# Phase 1: DETECT
#==============================================================================
detect_issues() {
  local client="$1"
  local rpc_port="${CLIENT_RPC_PORTS[$client]:-8545}"
  local container="${CLIENT_CONTAINERS[$client]:-xdc-${client}}"

  log "--- DETECT [${client}] ---"

  # Check 1: Is container running?
  local container_status
  if command -v docker &>/dev/null; then
    container_status=$(docker inspect --format='{{.State.Status}}' "${container}" 2>/dev/null || echo "not_found")
  else
    container_status="docker_unavailable"
  fi

  if [[ "${container_status}" == "not_found" || "${container_status}" == "exited" ]]; then
    log "DETECT: Container ${container} is ${container_status}"
    echo "container_down"
    return 0
  fi

  # Check 2: Is RPC responding?
  local block_hex
  block_hex=$(curl -sf --max-time 5 \
    -X POST "http://localhost:${rpc_port}" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    2>/dev/null | grep -oP '"result":"\K[^"]+' || echo "")

  if [[ -z "${block_hex}" ]]; then
    log "DETECT: RPC not responding on port ${rpc_port}"
    echo "rpc_down"
    return 0
  fi

  # Check 3: Block advancing? (two samples, 30s apart)
  local block1
  block1=$((16#${block_hex#0x}))
  sleep 30
  local block2_hex
  block2_hex=$(curl -sf --max-time 5 \
    -X POST "http://localhost:${rpc_port}" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    2>/dev/null | grep -oP '"result":"\K[^"]+' || echo "${block_hex}")
  local block2
  block2=$((16#${block2_hex#0x}))

  if [[ "${block1}" -eq "${block2}" ]]; then
    log "DETECT: Block height stalled at ${block1}"
    echo "sync_stalled:${block1}"
    return 0
  fi

  # Check 4: Peer count
  local peer_hex
  peer_hex=$(curl -sf --max-time 5 \
    -X POST "http://localhost:${rpc_port}" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
    2>/dev/null | grep -oP '"result":"\K[^"]+' || echo "0x0")
  local peer_count
  peer_count=$((16#${peer_hex#0x}))

  if [[ "${peer_count}" -lt 2 ]]; then
    log "DETECT: Low peer count: ${peer_count}"
    echo "low_peers:${peer_count}"
    return 0
  fi

  log "DETECT: ${client} healthy (block=${block2}, peers=${peer_count})"
  echo "healthy"
}

#==============================================================================
# Phase 2: DIAGNOSE
#==============================================================================
diagnose() {
  local client="$1"
  local issue="$2"
  local container="${CLIENT_CONTAINERS[$client]:-xdc-${client}}"

  log "--- DIAGNOSE [${client}] issue=${issue} ---"

  # Check logs for errors
  local log_errors=""
  if command -v docker &>/dev/null; then
    log_errors=$(docker logs "${container}" --tail=100 2>&1 | grep -iE "(error|fatal|panic|OOM|killed|exception)" | tail -5 || true)
  fi

  # Check disk usage
  local disk_usage
  disk_usage=$(df -h / 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%' || echo "0")

  # Check memory
  local mem_available_mb
  mem_available_mb=$(awk '/MemAvailable/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")

  log "DIAGNOSE: disk_usage=${disk_usage}%, mem_available=${mem_available_mb}MB"
  log "DIAGNOSE: log_errors='${log_errors:-none}'"

  # Classify root cause
  local root_cause="unknown"

  if [[ "${disk_usage}" -gt 95 ]]; then
    root_cause="disk_full"
  elif [[ "${mem_available_mb}" -lt 512 ]]; then
    root_cause="oom"
  elif echo "${log_errors}" | grep -qi "state root\|bad block\|invalid block"; then
    root_cause="bad_block"
  elif echo "${log_errors}" | grep -qi "panic\|fatal"; then
    root_cause="crash"
  elif [[ "${issue}" == low_peers* ]]; then
    root_cause="network_isolation"
  elif [[ "${issue}" == sync_stalled* ]]; then
    root_cause="sync_stall"
  elif [[ "${issue}" == container_down* ]]; then
    root_cause="container_crash"
  fi

  log "DIAGNOSE: root_cause=${root_cause}"
  log_action "diagnose" "complete" "${root_cause}"
  echo "${root_cause}"
}

#==============================================================================
# Phase 3: REMEDIATE
#==============================================================================
remediate() {
  local client="$1"
  local root_cause="$2"
  local container="${CLIENT_CONTAINERS[$client]:-xdc-${client}}"
  local rpc_port="${CLIENT_RPC_PORTS[$client]:-8545}"

  log "--- REMEDIATE [${client}] cause=${root_cause} ---"

  case "${root_cause}" in
    container_crash|crash|rpc_down)
      log "REMEDIATE: Restarting container ${container}"
      if [[ "${DRY_RUN}" == false ]]; then
        docker restart "${container}" 2>/dev/null && log_action "restart_container" "ok" "${container}" \
          || log_action "restart_container" "failed" "${container}"
      else
        log "[DRY-RUN] Would restart ${container}"
        log_action "restart_container" "dry_run" "${container}"
      fi
      ;;

    network_isolation|low_peers)
      log "REMEDIATE: Adding bootnodes for ${client}"
      local bootnodes_file="${REPO_DIR}/configs/bootnodes-mainnet.json"
      local bootnodes=""
      if [[ -f "${bootnodes_file}" ]]; then
        bootnodes=$(python3 -c "import json,sys; d=json.load(open('${bootnodes_file}')); print(' '.join(d.get('${client}',[])[:3]))" 2>/dev/null || echo "")
      fi
      if [[ -n "${bootnodes}" && "${DRY_RUN}" == false ]]; then
        for enode in ${bootnodes}; do
          curl -sf --max-time 5 \
            -X POST "http://localhost:${rpc_port}" \
            -H "Content-Type: application/json" \
            -d "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addPeer\",\"params\":[\"${enode}\"],\"id\":1}" \
            >/dev/null 2>&1 || true
        done
        log_action "add_bootnodes" "ok" "added ${bootnodes}"
      else
        log "[DRY-RUN] Would add bootnodes: ${bootnodes:-none available}"
        log_action "add_bootnodes" "dry_run"
      fi
      ;;

    sync_stall|bad_block)
      log "REMEDIATE: Restarting container to clear sync stall"
      if [[ "${DRY_RUN}" == false ]]; then
        docker restart "${container}" 2>/dev/null && log_action "restart_for_sync" "ok" "${container}" \
          || log_action "restart_for_sync" "failed" "${container}"
      else
        log "[DRY-RUN] Would restart ${container} to clear stall"
        log_action "restart_for_sync" "dry_run"
      fi
      ;;

    disk_full)
      log "REMEDIATE: Clearing Docker build cache and old logs"
      if [[ "${DRY_RUN}" == false ]]; then
        docker system prune -f --filter "until=48h" 2>/dev/null && log_action "clear_cache" "ok" \
          || log_action "clear_cache" "failed"
        find /var/log -name "*.gz" -mtime +7 -delete 2>/dev/null || true
        log_action "clear_old_logs" "ok"
      else
        log "[DRY-RUN] Would prune Docker cache and old logs"
        log_action "clear_cache" "dry_run"
      fi
      ;;

    oom)
      log "REMEDIATE: Restarting container after OOM (may need resource limit increase)"
      if [[ "${DRY_RUN}" == false ]]; then
        docker restart "${container}" 2>/dev/null && log_action "restart_after_oom" "ok" "${container}" \
          || log_action "restart_after_oom" "failed" "${container}"
      else
        log "[DRY-RUN] Would restart ${container} after OOM"
        log_action "restart_after_oom" "dry_run"
      fi
      ;;

    *)
      log "REMEDIATE: No automated remediation for '${root_cause}' — escalating"
      log_action "escalate" "manual_required" "${root_cause}"
      ;;
  esac
}

#==============================================================================
# Phase 4: VERIFY
#==============================================================================
verify_recovery() {
  local client="$1"
  local rpc_port="${CLIENT_RPC_PORTS[$client]:-8545}"
  local max_wait=120
  local wait=0
  local last_block=0

  log "--- VERIFY [${client}] (waiting up to ${max_wait}s) ---"

  # Wait for RPC to come back
  while [[ "${wait}" -lt "${max_wait}" ]]; do
    local block_hex
    block_hex=$(curl -sf --max-time 5 \
      -X POST "http://localhost:${rpc_port}" \
      -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
      2>/dev/null | grep -oP '"result":"\K[^"]+' || echo "")

    if [[ -n "${block_hex}" ]]; then
      local block
      block=$((16#${block_hex#0x}))
      if [[ "${last_block}" -eq 0 ]]; then
        last_block="${block}"
      elif [[ "${block}" -gt "${last_block}" ]]; then
        log "VERIFY: Block advancing (${last_block} → ${block}) ✓"
        log_action "verify" "recovered" "block=${block}"
        return 0
      fi
    fi

    sleep 10
    wait=$((wait + 10))
    log "VERIFY: Waiting... (${wait}s/${max_wait}s)"
  done

  log "VERIFY: Recovery not confirmed within ${max_wait}s"
  log_action "verify" "timeout"
  return 1
}

#==============================================================================
# Main incident loop
#==============================================================================
run_client() {
  local client="$1"

  log "Checking client: ${client}"
  local issue
  issue=$(detect_issues "${client}")

  if [[ "${issue}" == "healthy" ]]; then
    log "${client}: healthy — no incident"
    return 0
  fi

  # Determine severity
  local severity="P2"
  case "${issue}" in
    container_down|rpc_down) severity="P1" ;;
    sync_stalled*)           severity="P2" ;;
    low_peers*)              severity="P3" ;;
  esac

  init_incident "${severity}" "${issue}"
  log_action "detect" "issue_found" "${issue}"

  local root_cause
  root_cause=$(diagnose "${client}" "${issue}")

  remediate "${client}" "${root_cause}"

  local recovered=false
  if verify_recovery "${client}"; then
    recovered=true
  fi

  if [[ "${recovered}" == true ]]; then
    write_incident_log "resolved" "${root_cause}" "automated_remediation"
    log "Incident ${INCIDENT_ID} resolved ✓"
  else
    write_incident_log "unresolved" "${root_cause}" "manual_intervention_required"
    log "Incident ${INCIDENT_ID} unresolved — manual intervention needed"
    return 1
  fi
}

#==============================================================================
# Entry point
#==============================================================================
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --client) TARGET_CLIENT="$2"; shift 2 ;;
      --loop)   LOOP_MODE=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      --help|-h)
        grep "^#" "$0" | head -20 | sed 's/^#//'
        exit 0
        ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
}

main() {
  parse_args "$@"

  log "XDC Incident Response starting (client=${TARGET_CLIENT}, loop=${LOOP_MODE}, dry_run=${DRY_RUN})"

  local clients=()
  if [[ "${TARGET_CLIENT}" == "all" ]]; then
    clients=(geth erigon nethermind reth)
  else
    clients=("${TARGET_CLIENT}")
  fi

  if [[ "${LOOP_MODE}" == true ]]; then
    log "Running in loop mode (interval=${POLL_INTERVAL}s)"
    while true; do
      for client in "${clients[@]}"; do
        run_client "${client}" || true
      done
      log "Sleeping ${POLL_INTERVAL}s before next poll..."
      sleep "${POLL_INTERVAL}"
    done
  else
    for client in "${clients[@]}"; do
      run_client "${client}" || true
    done
  fi
}

main "$@"
