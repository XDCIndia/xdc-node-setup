#!/usr/bin/env bash
# tournament.sh — Cross-Client Tournament (#124)
# Run all clients through benchmark suite, rank by composite score, output leaderboard.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKYONE_URL="${SKYONE_URL:-http://localhost:7070}"
CLIENTS=("geth" "erigon" "nethermind" "reth")
declare -A CLIENT_PORTS=([geth]=7070 [erigon]=7071 [nethermind]=7072 [reth]=8588)
RESULTS_DIR="${REPO_ROOT}/data/tournament"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_FILE="${RESULTS_DIR}/leaderboard-${TIMESTAMP}.md"

mkdir -p "$RESULTS_DIR"

log() { echo "[$(date +%H:%M:%S)] $*" >&2; }

get_metric() {
  local client="$1"
  local metric="$2"
  local port="${CLIENT_PORTS[$client]:-7070}"
  curl -sf --max-time 5 "http://localhost:${port}/api/v1/metrics" 2>/dev/null \
    | grep -o "\"${metric}\":[0-9.]*" | cut -d: -f2 | head -1 || echo "0"
}

check_client_running() {
  local client="$1"
  local port="${CLIENT_PORTS[$client]:-7070}"
  curl -sf --max-time 3 "http://localhost:${port}/api/v1/health" &>/dev/null
}

benchmark_client() {
  local client="$1"
  log "Benchmarking ${client}..."

  if ! check_client_running "$client"; then
    log "  ⚠️  ${client} not reachable — skipping"
    echo "0 0 0 0 0"
    return
  fi

  # Run benchmark script if available
  local bench_result="{}"
  if [[ -x "${SCRIPT_DIR}/benchmark-v2.sh" ]]; then
    bench_result="$("${SCRIPT_DIR}/benchmark-v2.sh" --client "$client" --json 2>/dev/null || echo '{}')"
  fi

  # Collect metrics
  local blocks_per_sec
  blocks_per_sec="$(get_metric "$client" "blocks_per_second")"
  local peers
  peers="$(get_metric "$client" "peer_count")"
  local mem_mb
  mem_mb="$(get_metric "$client" "memory_mb")"
  local txpool
  txpool="$(get_metric "$client" "txpool_size")"
  local sync_lag
  sync_lag="$(get_metric "$client" "sync_lag_blocks")"

  echo "$blocks_per_sec $peers $mem_mb $txpool $sync_lag"
}

compute_composite_score() {
  local bps="$1" peers="$2" mem_mb="$3" txpool="$4" sync_lag="$5"
  # Composite: higher bps/peers/txpool = better, lower mem/lag = better
  # Weights: bps*40 + peers*20 + txpool*10 - mem_mb*0.01 - sync_lag*5
  awk -v bps="$bps" -v peers="$peers" -v mem="$mem_mb" -v tp="$txpool" -v lag="$sync_lag" \
    'BEGIN { score = bps*40 + peers*20 + tp*10 - mem*0.01 - lag*5; if(score<0) score=0; printf "%.2f\n", score }'
}

declare -A SCORES
declare -A CLIENT_METRICS

run_tournament() {
  log "=== XDC Cross-Client Tournament ==="
  log "Clients: ${CLIENTS[*]}"
  echo ""

  for client in "${CLIENTS[@]}"; do
    local metrics
    read -r bps peers mem txpool lag <<< "$(benchmark_client "$client")"
    local score
    score="$(compute_composite_score "$bps" "$peers" "$mem" "$txpool" "$lag")"
    SCORES[$client]="$score"
    CLIENT_METRICS[$client]="${bps}|${peers}|${mem}|${txpool}|${lag}"
    log "  ${client}: score=${score} bps=${bps} peers=${peers} mem=${mem}MB lag=${lag}"
  done
}

generate_leaderboard() {
  # Sort clients by score descending
  local sorted
  sorted="$(for c in "${CLIENTS[@]}"; do echo "${SCORES[$c]} $c"; done | sort -rn)"

  local rank=1
  local table=""
  table+="# XDC Client Tournament Leaderboard\n"
  table+="\nGenerated: $(date -u '+%Y-%m-%d %H:%M UTC')\n\n"
  table+="| Rank | Client | Score | Blocks/s | Peers | Mem (MB) | TxPool | Sync Lag |\n"
  table+="|------|--------|-------|----------|-------|----------|--------|----------|\n"

  while IFS=" " read -r score client; do
    IFS='|' read -r bps peers mem txpool lag <<< "${CLIENT_METRICS[$client]}"
    local medal=""
    case $rank in
      1) medal="🥇" ;;
      2) medal="🥈" ;;
      3) medal="🥉" ;;
      *) medal="   " ;;
    esac
    table+="| ${medal} ${rank} | **${client}** | ${score} | ${bps} | ${peers} | ${mem} | ${txpool} | ${lag} |\n"
    ((rank++))
  done <<< "$sorted"

  table+="\n## Methodology\n"
  table+="Composite score = BPS×40 + Peers×20 + TxPool×10 - Memory×0.01 - SyncLag×5\n"

  echo -e "$table"
}

post_to_skyone() {
  local leaderboard_json="$1"
  curl -sf -X POST "${SKYONE_URL}/api/v2/tournament/results" \
    -H 'Content-Type: application/json' \
    -d "$leaderboard_json" 2>/dev/null \
    && log "✅ Results posted to SkyNet" \
    || log "⚠️  SkyNet post failed (non-fatal)"
}

run_tournament
LEADERBOARD="$(generate_leaderboard)"
echo -e "$LEADERBOARD"
echo -e "$LEADERBOARD" > "$OUTPUT_FILE"
log "Leaderboard saved: $OUTPUT_FILE"

# Build JSON for SkyNet
SCORE_JSON="{"
for c in "${CLIENTS[@]}"; do
  SCORE_JSON+="\"${c}\":${SCORES[$c]:-0},"
done
SCORE_JSON="${SCORE_JSON%,}}"
post_to_skyone "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"scores\":${SCORE_JSON}}"
