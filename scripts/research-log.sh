#!/usr/bin/env bash
# research-log.sh — Research Log (#120)
# log add <experiment> <score>  — record experiment result
# log show                       — display all entries
# log trend <metric>             — ASCII chart of metric over time
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="${REPO_ROOT}/data/research"
LOG_FILE="${DATA_DIR}/log.jsonl"

mkdir -p "$DATA_DIR"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  add <experiment> <score> [metric] [notes]  Add a log entry
  show [--last N]                             Show all entries (or last N)
  trend <metric>                              ASCII chart for a metric
  list-metrics                               Show available metrics in log

Examples:
  $(basename "$0") add block-sync-test 142.5
  $(basename "$0") add erigon-cache-512 98.3 blocks_per_second "increased cache"
  $(basename "$0") show --last 20
  $(basename "$0") trend blocks_per_second
EOF
  exit 1
}

cmd_add() {
  local experiment="${1:?ERROR: experiment name required}"
  local score="${2:?ERROR: score required}"
  local metric="${3:-blocks_per_second}"
  local notes="${4:-}"

  local entry
  entry="$(cat <<JSON
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","experiment":"${experiment}","metric":"${metric}","score":${score},"notes":"${notes}","host":"$(hostname)"}
JSON
)"

  echo "$entry" >> "$LOG_FILE"
  echo "✅ Logged: ${experiment} → ${metric}=${score}"
}

cmd_show() {
  local last_n=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --last) last_n="${2:-10}"; shift ;;
    esac
    shift
  done

  [[ -f "$LOG_FILE" ]] || { echo "(no log entries yet)"; return; }

  local entries
  if [[ $last_n -gt 0 ]]; then
    entries="$(tail -n "$last_n" "$LOG_FILE")"
  else
    entries="$(cat "$LOG_FILE")"
  fi

  echo "=== Research Log ==="
  printf "%-30s %-30s %-20s %-10s %s\n" "Timestamp" "Experiment" "Metric" "Score" "Notes"
  printf "%-30s %-30s %-20s %-10s %s\n" "----------" "----------" "------" "-----" "-----"

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local ts exp metric score notes
    ts="$(echo "$line" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)"
    exp="$(echo "$line" | grep -o '"experiment":"[^"]*"' | cut -d'"' -f4)"
    metric="$(echo "$line" | grep -o '"metric":"[^"]*"' | cut -d'"' -f4)"
    score="$(echo "$line" | grep -o '"score":[0-9.]*' | cut -d: -f2)"
    notes="$(echo "$line" | grep -o '"notes":"[^"]*"' | cut -d'"' -f4)"
    printf "%-30s %-30s %-20s %-10s %s\n" "${ts:0:19}" "${exp:0:29}" "${metric:0:19}" "$score" "$notes"
  done <<< "$entries"
  echo ""
  echo "Total entries: $(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)"
}

cmd_trend() {
  local metric="${1:?ERROR: metric required for trend}"
  [[ -f "$LOG_FILE" ]] || { echo "No log data"; return; }

  # Extract (timestamp, score) pairs for this metric
  local data=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local m
    m="$(echo "$line" | grep -o '"metric":"[^"]*"' | cut -d'"' -f4)"
    [[ "$m" != "$metric" ]] && continue
    local score
    score="$(echo "$line" | grep -o '"score":[0-9.]*' | cut -d: -f2)"
    local ts
    ts="$(echo "$line" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4 | cut -c1-16)"
    data+=("$score|$ts")
  done < "$LOG_FILE"

  if [[ ${#data[@]} -eq 0 ]]; then
    echo "No entries found for metric: ${metric}"
    return
  fi

  echo "=== Trend: ${metric} ==="
  echo ""

  # Find min/max
  local min max sum count=0
  min="$(for d in "${data[@]}"; do echo "${d%%|*}"; done | sort -n | head -1)"
  max="$(for d in "${data[@]}"; do echo "${d%%|*}"; done | sort -n | tail -1)"

  local range
  range="$(awk -v mx="$max" -v mn="$min" 'BEGIN { printf "%.2f", mx - mn }')"
  [[ "$range" == "0.00" ]] && range=1

  local chart_height=10
  local chart_width=60

  # Build ASCII chart using printf
  echo "Max: ${max}"
  echo "Min: ${min}"
  echo ""

  # Print each data point as a bar
  local i=1
  for d in "${data[@]}"; do
    local val="${d%%|*}"
    local label="${d##*|}"
    local bar_len
    bar_len="$(awk -v v="$val" -v mn="$min" -v r="$range" -v w="$chart_width" \
      'BEGIN { printf "%d", (v - mn) / r * w }')"
    [[ $bar_len -lt 1 ]] && bar_len=1

    printf "%3d │ " "$i"
    printf '%0.s█' $(seq 1 "$bar_len")
    printf ' %.2f  %s\n' "$val" "$label"
    ((i++))
  done

  echo "    └$(printf '%0.s─' $(seq 1 $chart_width))"
  echo ""

  # Show last 5 and trend direction
  if [[ ${#data[@]} -ge 2 ]]; then
    local first_val="${data[0]%%|*}"
    local last_val="${data[-1]%%|*}"
    local trend
    trend="$(awk -v f="$first_val" -v l="$last_val" \
      'BEGIN { if (l > f) print "📈 Improving"; else if (l < f) print "📉 Declining"; else print "➡️  Stable" }')"
    echo "Trend: $trend (${first_val} → ${last_val})"
  fi
}

cmd_list_metrics() {
  [[ -f "$LOG_FILE" ]] || { echo "No log data"; return; }
  echo "Available metrics:"
  grep -o '"metric":"[^"]*"' "$LOG_FILE" | cut -d'"' -f4 | sort -u | sed 's/^/  /'
}

CMD="${1:-}"
shift || true

case "$CMD" in
  add)           cmd_add   "$@" ;;
  show)          cmd_show  "$@" ;;
  trend)         cmd_trend "$@" ;;
  list-metrics)  cmd_list_metrics ;;
  *)             usage ;;
esac
