#!/usr/bin/env bash
# experiment-loop.sh — Cross-Repo Experiment Loop (#131)
# Reads program.md, runs benchmark, POSTs score to SkyNet, logs result.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROGRAM_MD="${REPO_ROOT}/program.md"
DATA_DIR="${REPO_ROOT}/data/research"
LOG_FILE="${DATA_DIR}/experiment-loop.jsonl"
SKYONE_URL="${SKYONE_URL:-http://localhost:7070}"
SKYONE_OPTIMIZE_URL="${SKYONE_OPTIMIZE_URL:-${SKYONE_URL}/api/v2/optimize/score}"
BENCHMARK_SCRIPT="${SCRIPT_DIR}/benchmark-v2.sh"
MAX_ITERATIONS="${MAX_ITERATIONS:-10}"
IMPROVE_THRESHOLD="${IMPROVE_THRESHOLD:-0.01}"

mkdir -p "$DATA_DIR"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

read_program() {
  if [[ -f "$PROGRAM_MD" ]]; then
    log "Reading program.md..."
    cat "$PROGRAM_MD"
  else
    log "WARN: program.md not found at $PROGRAM_MD — using defaults"
    echo "# Default Program\nclients: [geth]\nbenchmark: block-sync\nmetric: blocks_per_second"
  fi
}

run_benchmark() {
  local iteration="$1"
  log "Running benchmark (iteration ${iteration})..."

  if [[ -x "$BENCHMARK_SCRIPT" ]]; then
    local raw
    raw="$("$BENCHMARK_SCRIPT" --json 2>/dev/null || echo '{}')"
    echo "$raw"
  else
    # Fallback: collect basic metrics
    local blocks_per_sec
    blocks_per_sec="$(curl -sf "${SKYONE_URL}/api/v1/metrics" 2>/dev/null \
      | grep -o '"blocks_per_second":[0-9.]*' | cut -d: -f2 || echo 0)"
    echo "{\"blocks_per_second\": ${blocks_per_sec:-0}, \"iteration\": ${iteration}}"
  fi
}

post_score() {
  local score_json="$1"
  local iteration="$2"
  log "POSTing score to SkyNet: ${SKYONE_OPTIMIZE_URL}"

  local payload
  payload="$(cat <<JSON
{
  "source": "xdc-node-setup",
  "iteration": ${iteration},
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "scores": ${score_json},
  "repo": "XDC-Node-Setup"
}
JSON
)"

  local response
  response="$(curl -sf -X POST "${SKYONE_OPTIMIZE_URL}" \
    -H 'Content-Type: application/json' \
    -d "$payload" 2>/dev/null || echo '{"status":"unreachable"}')"
  echo "$response"
}

extract_metric() {
  local json="$1"
  local metric="${2:-blocks_per_second}"
  echo "$json" | grep -o "\"${metric}\":[0-9.]*" | cut -d: -f2 | head -1 || echo "0"
}

append_log() {
  local entry="$1"
  echo "$entry" >> "$LOG_FILE"
}

main() {
  log "=== Experiment Loop Starting ==="
  read_program > /dev/null

  local best_score=0
  local improved=false
  local iteration=1

  while [[ $iteration -le $MAX_ITERATIONS ]]; do
    log "--- Iteration ${iteration}/${MAX_ITERATIONS} ---"

    local benchmark_result
    benchmark_result="$(run_benchmark "$iteration")"

    local current_score
    current_score="$(extract_metric "$benchmark_result" "blocks_per_second")"
    log "Current score: ${current_score}"

    local response
    response="$(post_score "$benchmark_result" "$iteration")"
    log "SkyNet response: ${response}"

    # Check improvement
    local delta
    delta="$(echo "$current_score $best_score $IMPROVE_THRESHOLD" | awk '{
      if ($1 > $2 * (1 + $3)) print "yes"; else print "no"
    }')"

    if [[ "$delta" == "yes" ]]; then
      log "✅ Improved! ${best_score} → ${current_score}"
      best_score="$current_score"
      improved=true
    else
      log "➖ No significant improvement (${current_score} vs best ${best_score})"
    fi

    # Append to log
    append_log "$(cat <<JSON
{"iteration":${iteration},"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","score":${current_score},"best":${best_score},"improved":${delta},"response":${response}}
JSON
)"

    ((iteration++))

    # Stop early if stagnant for 3 iterations
    if [[ $iteration -gt 3 ]] && [[ "$improved" == "false" ]]; then
      log "No improvement in ${iteration} iterations — stopping early"
      break
    fi
    improved=false

    sleep 5
  done

  log "=== Experiment Loop Complete. Best score: ${best_score} ==="
  log "Log saved to: ${LOG_FILE}"
}

main "$@"
