#!/usr/bin/env bash
#==============================================================================
# Harbor-Style Benchmarks for XDC Node Clients
#
# Measures sync speed, disk growth, and RPC latency per client.
# Outputs structured JSON scores (0.0-1.0) for automated optimization.
#
# Usage:
#   ./harbor-benchmark.sh sync <client>   — blocks/sec over 5 min
#   ./harbor-benchmark.sh disk <client>   — disk growth rate (MB/hour)
#   ./harbor-benchmark.sh rpc <client>    — RPC latency (eth_blockNumber, eth_getBalance)
#   ./harbor-benchmark.sh full <client>   — all benchmarks + composite score
#
# Clients: geth, erigon, nethermind, reth
#
# Results stored in: data/benchmarks/YYYY-MM-DD-<client>.json
#
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/127
#==============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly BENCHMARK_DIR="${REPO_DIR}/data/benchmarks"
readonly TODAY="$(date +%Y-%m-%d)"
readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- Sync benchmark duration ---
SYNC_DURATION="${SYNC_DURATION:-300}"   # 5 minutes by default
SYNC_FAST="${SYNC_FAST:-false}"         # Set to true for quick 30s test

# --- RPC sample count ---
RPC_SAMPLES="${RPC_SAMPLES:-20}"

# --- Client → RPC port mapping ---
declare -A CLIENT_RPC_PORTS=(
  [geth]=8545
  [erigon]=8547
  [nethermind]=8548
  [reth]=8588
)

# --- Client → data directory ---
declare -A CLIENT_DATA_DIRS=(
  [geth]="/data/geth"
  [erigon]="/data/erigon"
  [nethermind]="/data/nethermind"
  [reth]="/data/reth"
)

# --- Client → container name ---
declare -A CLIENT_CONTAINERS=(
  [geth]="xdc-geth"
  [erigon]="xdc-erigon"
  [nethermind]="xdc-nethermind"
  [reth]="xdc-reth"
)

#==============================================================================
# Utilities
#==============================================================================
log()  { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >&2; }
err()  { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: $*" >&2; exit 1; }

# Clamp a value between 0 and 1
clamp01() {
  local val="$1"
  echo "scale=4; v=${val}; if (v < 0) print 0 else if (v > 1) print 1.0 else print v" | bc 2>/dev/null || echo "0.5"
}

# Get current block number as decimal
get_block_number() {
  local port="$1"
  local hex
  hex=$(curl -sf --max-time 5 \
    -X POST "http://localhost:${port}" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    2>/dev/null | grep -oP '"result":"\K[^"]+' || echo "0x0")
  echo "$((16#${hex#0x}))"
}

# Timestamp in milliseconds
ts_ms() { date +%s%3N; }

# Get a sample Ethereum address for eth_getBalance
sample_address() {
  echo "0x0000000000000000000000000000000000000001"
}

#==============================================================================
# BENCHMARK: sync — blocks/sec over SYNC_DURATION seconds
#==============================================================================
benchmark_sync() {
  local client="$1"
  local port="${CLIENT_RPC_PORTS[$client]:-8545}"
  local duration="${SYNC_DURATION}"

  if [[ "${SYNC_FAST}" == true ]]; then
    duration=30
  fi

  log "SYNC benchmark: ${client} (port=${port}, duration=${duration}s)"

  # Check RPC is available
  local block_start
  block_start=$(get_block_number "${port}") || { log "RPC unavailable"; echo '{"error":"rpc_unavailable"}'; return 1; }

  local t_start
  t_start=$(date +%s)

  log "Waiting ${duration}s..."
  sleep "${duration}"

  local block_end
  block_end=$(get_block_number "${port}")
  local t_end
  t_end=$(date +%s)

  local blocks_synced=$((block_end - block_start))
  local elapsed=$((t_end - t_start))
  local blocks_per_sec=0

  if [[ "${elapsed}" -gt 0 && "${blocks_synced}" -gt 0 ]]; then
    blocks_per_sec=$(echo "scale=4; ${blocks_synced} / ${elapsed}" | bc 2>/dev/null || echo "0")
  fi

  # Scoring: 0 = 0 blocks/sec, 1.0 = 10+ blocks/sec
  # XDC produces ~0.5 blocks/sec at head; fast initial sync can be 5-10 blocks/sec
  local score
  score=$(clamp01 "$(echo "scale=4; ${blocks_per_sec} / 10.0" | bc 2>/dev/null || echo "0.5")")

  log "SYNC: ${blocks_synced} blocks in ${elapsed}s = ${blocks_per_sec} blocks/sec → score=${score}"

  cat <<EOF
{
  "benchmark": "sync",
  "client": "${client}",
  "timestamp": "${TIMESTAMP}",
  "duration_sec": ${elapsed},
  "block_start": ${block_start},
  "block_end": ${block_end},
  "blocks_synced": ${blocks_synced},
  "blocks_per_sec": ${blocks_per_sec},
  "score": ${score}
}
EOF
}

#==============================================================================
# BENCHMARK: disk — disk growth rate in MB/hour
#==============================================================================
benchmark_disk() {
  local client="$1"
  local data_dir="${CLIENT_DATA_DIRS[$client]:-/data/${client}}"
  local container="${CLIENT_CONTAINERS[$client]:-xdc-${client}}"

  log "DISK benchmark: ${client} (data_dir=${data_dir})"

  # Get initial disk usage
  local size_start_kb
  if [[ -d "${data_dir}" ]]; then
    size_start_kb=$(du -sk "${data_dir}" 2>/dev/null | awk '{print $1}' || echo "0")
  elif command -v docker &>/dev/null; then
    size_start_kb=$(docker exec "${container}" du -sk /data 2>/dev/null | awk '{print $1}' || echo "0")
  else
    size_start_kb=0
  fi

  local t_start
  t_start=$(date +%s)

  # Wait 60 seconds for measurable growth
  log "Waiting 60s to measure disk growth..."
  sleep 60

  local size_end_kb
  if [[ -d "${data_dir}" ]]; then
    size_end_kb=$(du -sk "${data_dir}" 2>/dev/null | awk '{print $1}' || echo "${size_start_kb}")
  elif command -v docker &>/dev/null; then
    size_end_kb=$(docker exec "${container}" du -sk /data 2>/dev/null | awk '{print $1}' || echo "${size_start_kb}")
  else
    size_end_kb="${size_start_kb}"
  fi

  local t_end
  t_end=$(date +%s)
  local elapsed=$((t_end - t_start))

  local growth_kb=$((size_end_kb - size_start_kb))
  local growth_mb_per_hour=0
  if [[ "${elapsed}" -gt 0 ]]; then
    growth_mb_per_hour=$(echo "scale=2; ${growth_kb} * 3600 / ${elapsed} / 1024" | bc 2>/dev/null || echo "0")
  fi

  # Current total usage
  local total_gb
  total_gb=$(echo "scale=2; ${size_end_kb} / 1024 / 1024" | bc 2>/dev/null || echo "0")

  # Scoring: lower growth rate is better
  # 0 MB/hr = 1.0, 1000 MB/hr (1 GB/hr during fast sync) = 0.5, 5000+ MB/hr = 0.0
  local score
  score=$(clamp01 "$(echo "scale=4; 1.0 - (${growth_mb_per_hour} / 5000.0)" | bc 2>/dev/null || echo "0.5")")

  log "DISK: ${growth_kb}KB in ${elapsed}s = ${growth_mb_per_hour} MB/hr, total=${total_gb}GB → score=${score}"

  cat <<EOF
{
  "benchmark": "disk",
  "client": "${client}",
  "timestamp": "${TIMESTAMP}",
  "data_dir": "${data_dir}",
  "elapsed_sec": ${elapsed},
  "size_start_kb": ${size_start_kb},
  "size_end_kb": ${size_end_kb},
  "growth_kb": ${growth_kb},
  "growth_mb_per_hour": ${growth_mb_per_hour},
  "total_gb": ${total_gb},
  "score": ${score}
}
EOF
}

#==============================================================================
# BENCHMARK: rpc — measure latency for eth_blockNumber and eth_getBalance
#==============================================================================
benchmark_rpc() {
  local client="$1"
  local port="${CLIENT_RPC_PORTS[$client]:-8545}"
  local samples="${RPC_SAMPLES}"
  local address
  address=$(sample_address)

  log "RPC benchmark: ${client} (port=${port}, samples=${samples})"

  # Measure eth_blockNumber latency
  local bn_total_ms=0
  local bn_count=0
  local bn_errors=0

  for ((i=1; i<=samples; i++)); do
    local t_start t_end latency
    t_start=$(ts_ms)
    if curl -sf --max-time 3 \
      -X POST "http://localhost:${port}" \
      -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
      >/dev/null 2>&1; then
      t_end=$(ts_ms)
      latency=$((t_end - t_start))
      bn_total_ms=$((bn_total_ms + latency))
      bn_count=$((bn_count + 1))
    else
      bn_errors=$((bn_errors + 1))
    fi
  done

  local bn_avg_ms=0
  if [[ "${bn_count}" -gt 0 ]]; then
    bn_avg_ms=$((bn_total_ms / bn_count))
  fi

  # Measure eth_getBalance latency
  local gb_total_ms=0
  local gb_count=0
  local gb_errors=0

  for ((i=1; i<=samples; i++)); do
    local t_start t_end latency
    t_start=$(ts_ms)
    if curl -sf --max-time 3 \
      -X POST "http://localhost:${port}" \
      -H "Content-Type: application/json" \
      -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"${address}\",\"latest\"],\"id\":1}" \
      >/dev/null 2>&1; then
      t_end=$(ts_ms)
      latency=$((t_end - t_start))
      gb_total_ms=$((gb_total_ms + latency))
      gb_count=$((gb_count + 1))
    else
      gb_errors=$((gb_errors + 1))
    fi
  done

  local gb_avg_ms=0
  if [[ "${gb_count}" -gt 0 ]]; then
    gb_avg_ms=$((gb_total_ms / gb_count))
  fi

  # Overall avg latency
  local avg_ms=$(( (bn_avg_ms + gb_avg_ms) / 2 ))
  local total_errors=$((bn_errors + gb_errors))
  local total_calls=$((samples * 2))
  local error_rate=0
  if [[ "${total_calls}" -gt 0 ]]; then
    error_rate=$(echo "scale=4; ${total_errors} / ${total_calls}" | bc 2>/dev/null || echo "0")
  fi

  # Scoring:
  # - Latency: <50ms=1.0, 50-500ms=linear, >500ms=0.0
  # - Error rate: 0%=1.0, 100%=0.0
  local latency_score
  latency_score=$(clamp01 "$(echo "scale=4; if (${avg_ms} < 50) print 1.0 else (500 - ${avg_ms}) / 450.0" | bc 2>/dev/null || echo "0.5")")
  local error_score
  error_score=$(echo "scale=4; 1.0 - ${error_rate}" | bc 2>/dev/null || echo "1.0")
  error_score=$(clamp01 "${error_score}")

  local score
  score=$(clamp01 "$(echo "scale=4; 0.7 * ${latency_score} + 0.3 * ${error_score}" | bc 2>/dev/null || echo "0.5")")

  log "RPC: eth_blockNumber avg=${bn_avg_ms}ms, eth_getBalance avg=${gb_avg_ms}ms, errors=${total_errors}/${total_calls} → score=${score}"

  cat <<EOF
{
  "benchmark": "rpc",
  "client": "${client}",
  "timestamp": "${TIMESTAMP}",
  "samples_per_method": ${samples},
  "eth_blockNumber": {
    "avg_ms": ${bn_avg_ms},
    "success": ${bn_count},
    "errors": ${bn_errors}
  },
  "eth_getBalance": {
    "avg_ms": ${gb_avg_ms},
    "success": ${gb_count},
    "errors": ${gb_errors}
  },
  "overall_avg_ms": ${avg_ms},
  "error_rate": ${error_rate},
  "score": ${score}
}
EOF
}

#==============================================================================
# BENCHMARK: full — all benchmarks + composite score
#==============================================================================
benchmark_full() {
  local client="$1"

  log "FULL benchmark: ${client}"
  log "This will take ~6 minutes (sync=300s + disk=60s + rpc=~20s)"

  # If SYNC_FAST=true, run faster
  if [[ "${SYNC_FAST}" == true ]]; then
    log "(SYNC_FAST mode: sync=30s)"
  fi

  # Run all benchmarks
  local sync_json disk_json rpc_json

  log "=== Phase 1: Sync benchmark ==="
  sync_json=$(benchmark_sync "${client}")
  local sync_score
  sync_score=$(echo "${sync_json}" | grep -oP '"score":\s*\K[\d.]+' || echo "0")

  log "=== Phase 2: Disk benchmark ==="
  disk_json=$(benchmark_disk "${client}")
  local disk_score
  disk_score=$(echo "${disk_json}" | grep -oP '"score":\s*\K[\d.]+' || echo "0")

  log "=== Phase 3: RPC benchmark ==="
  rpc_json=$(benchmark_rpc "${client}")
  local rpc_score
  rpc_score=$(echo "${rpc_json}" | grep -oP '"score":\s*\K[\d.]+' || echo "0")

  # Get resource usage for composite score
  local container="${CLIENT_CONTAINERS[$client]:-xdc-${client}}"
  local cpu_pct=50 mem_pct=50
  if command -v docker &>/dev/null; then
    local stats
    stats=$(docker stats --no-stream --format "{{.CPUPerc}} {{.MemPerc}}" "${container}" 2>/dev/null || echo "50% 50%")
    cpu_pct=$(echo "${stats}" | awk '{print $1}' | tr -d '%' || echo "50")
    mem_pct=$(echo "${stats}" | awk '{print $2}' | tr -d '%' || echo "50")
  fi
  local resource_score
  resource_score=$(clamp01 "$(echo "scale=4; (200 - ${cpu_pct} - ${mem_pct}) / 200.0" | bc 2>/dev/null || echo "0.5")")

  # Composite score weights:
  # sync: 50%, rpc: 20%, disk: 15%, resources: 15%
  local composite
  composite=$(clamp01 "$(echo "scale=4; 0.50 * ${sync_score} + 0.20 * ${rpc_score} + 0.15 * ${disk_score} + 0.15 * ${resource_score}" | bc 2>/dev/null || echo "0.5")")

  log "FULL: sync=${sync_score}, rpc=${rpc_score}, disk=${disk_score}, resources=${resource_score} → composite=${composite}"

  # Build output JSON
  local output
  output=$(cat <<EOF
{
  "benchmark": "full",
  "client": "${client}",
  "timestamp": "${TIMESTAMP}",
  "score": ${composite},
  "weights": {
    "sync": 0.50,
    "rpc": 0.20,
    "disk": 0.15,
    "resources": 0.15
  },
  "scores": {
    "sync": ${sync_score},
    "rpc": ${rpc_score},
    "disk": ${disk_score},
    "resources": ${resource_score}
  },
  "resources": {
    "cpu_pct": ${cpu_pct},
    "mem_pct": ${mem_pct}
  },
  "details": {
    "sync": ${sync_json},
    "disk": ${disk_json},
    "rpc": ${rpc_json}
  }
}
EOF
)

  # Store results
  mkdir -p "${BENCHMARK_DIR}"
  local result_file="${BENCHMARK_DIR}/${TODAY}-${client}.json"
  echo "${output}" > "${result_file}"
  log "Results saved: ${result_file}"

  echo "${output}"
}

#==============================================================================
# Save individual benchmark results
#==============================================================================
save_result() {
  local type="$1"
  local client="$2"
  local result="$3"

  mkdir -p "${BENCHMARK_DIR}"
  local result_file="${BENCHMARK_DIR}/${TODAY}-${client}-${type}.json"

  # Append to daily results file
  if [[ -f "${result_file}" ]]; then
    local tmp
    tmp=$(mktemp)
    # Wrap in array
    if head -1 "${result_file}" | grep -q '^\['; then
      sed '$ d' "${result_file}" > "${tmp}"
      echo ",${result}]" >> "${tmp}"
    else
      echo "[$(cat "${result_file}"),${result}]" > "${tmp}"
    fi
    mv "${tmp}" "${result_file}"
  else
    echo "[${result}]" > "${result_file}"
  fi

  log "Result saved: ${result_file}"
}

#==============================================================================
# Entry point
#==============================================================================
usage() {
  cat <<'EOF'
Usage: harbor-benchmark.sh <command> <client>

Commands:
  sync <client>   Measure blocks/sec over SYNC_DURATION seconds (default: 300s)
  disk <client>   Measure disk growth rate in MB/hour
  rpc  <client>   Measure RPC latency (eth_blockNumber, eth_getBalance)
  full <client>   All of the above, outputs composite score 0.0-1.0

Clients: geth, erigon, nethermind, reth

Environment:
  SYNC_DURATION   Duration for sync benchmark (default: 300)
  SYNC_FAST       Set to 'true' for 30s quick test
  RPC_SAMPLES     Number of RPC samples (default: 20)

Results stored in: data/benchmarks/YYYY-MM-DD-<client>.json
EOF
  exit 1
}

main() {
  local cmd="${1:-}"
  local client="${2:-}"

  if [[ -z "${cmd}" || -z "${client}" ]]; then
    usage
  fi

  if [[ -z "${CLIENT_RPC_PORTS[$client]+_}" ]]; then
    err "Unknown client: ${client}. Valid: geth, erigon, nethermind, reth"
  fi

  local result
  case "${cmd}" in
    sync)
      result=$(benchmark_sync "${client}")
      save_result "sync" "${client}" "${result}"
      echo "${result}" | python3 -m json.tool 2>/dev/null || echo "${result}"
      ;;
    disk)
      result=$(benchmark_disk "${client}")
      save_result "disk" "${client}" "${result}"
      echo "${result}" | python3 -m json.tool 2>/dev/null || echo "${result}"
      ;;
    rpc)
      result=$(benchmark_rpc "${client}")
      save_result "rpc" "${client}" "${result}"
      echo "${result}" | python3 -m json.tool 2>/dev/null || echo "${result}"
      ;;
    full)
      benchmark_full "${client}"
      ;;
    *)
      err "Unknown command: ${cmd}. Valid: sync, disk, rpc, full"
      ;;
  esac
}

main "$@"
