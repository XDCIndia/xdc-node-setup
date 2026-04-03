#!/usr/bin/env bash
#==============================================================================
# AutoAgent Meta-Agent Optimization Loop v2
#
# Reads program.md (strategy file), runs benchmarks, scores the result,
# and automatically keeps or reverts config changes based on performance.
# Supports config mutation: maxpeers, cache size, gcmode, batch sizes.
#
# Usage:
#   ./auto-optimize.sh [--client geth|erigon|nethermind|reth] [--dry-run]
#                      [--strategy program.md] [--iterations N]
#                      [--mutate] [--param NAME] [--value VAL]
#
# Options:
#   --client      Client to optimize (default: geth)
#   --strategy    Strategy file to read (default: program.md)
#   --iterations  Max optimization rounds (default: 5)
#   --dry-run     Score and log without applying changes
#   --mutate      Enable config mutation mode (auto-discover params)
#   --param       Specific parameter to test (e.g., maxpeers)
#   --value       Specific value to test with --param
#   --no-restart  Apply changes without container restart (best-effort)
#
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/117
#==============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly EXPERIMENT_DIR="${REPO_DIR}/data/experiments"
readonly TODAY="$(date +%Y-%m-%d)"
readonly EXPERIMENT_LOG="${EXPERIMENT_DIR}/${TODAY}.json"
readonly BENCHMARK_SCRIPT="${SCRIPT_DIR}/benchmark.sh"

# --- Defaults ---
TARGET_CLIENT="${CLIENT:-geth}"
STRATEGY_FILE="${REPO_DIR}/program.md"
MAX_ITERATIONS="${MAX_ITERATIONS:-5}"
DRY_RUN=false
MUTATE_MODE=false
NO_RESTART=false
SPECIFIC_PARAM=""
SPECIFIC_VALUE=""
IMPROVEMENT_THRESHOLD="${IMPROVEMENT_THRESHOLD:-0.02}"  # 2% minimum improvement
readonly CONFIG_BACKUP_DIR="${REPO_DIR}/data/config-backups"
readonly WINNERS_LOG="${EXPERIMENT_DIR}/winners.json"

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

#==============================================================================
# Logging
#==============================================================================
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
warn() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] WARN: $*" >&2; }
err()  { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: $*" >&2; exit 1; }

#==============================================================================
# Step 1: Read strategy from program.md
#==============================================================================
read_strategy() {
  local strategy_file="$1"

  if [[ ! -f "${strategy_file}" ]]; then
    log "Strategy file not found: ${strategy_file}"
    log "Creating default strategy file..."
    cat > "${strategy_file}" <<'EOF'
# XDC Node Optimization Strategy

## Current Focus
Optimize sync speed and resource efficiency for all clients.

## Active Experiments
- Tune peer count limits (min/max peers)
- Adjust cache sizes for geth
- Optimize Erigon batch size
- Tune Nethermind memory budget

## Optimization Parameters

### geth
- `--cache`: current=1024, try=[512, 2048, 4096]
- `--maxpeers`: current=50, try=[25, 75, 100]

### erigon
- `--batchSize`: current=512M, try=[256M, 1G]
- `--maxPeers`: current=50, try=[30, 70]

### nethermind
- `Network.MaxActivePeers`: current=50, try=[30, 100]

## Score Weights
- sync_speed: 0.5     (blocks/sec, higher=better)
- peer_count: 0.2     (active peers, higher=better)
- cpu_usage:  0.1     (%, lower=better)
- mem_usage:  0.1     (%, lower=better)
- rpc_latency: 0.1    (ms, lower=better)

## Success Criteria
- Score improvement >= 0.02 (2%) to accept a change
- Never accept if sync stalls
- Never accept if peer count drops below 5
EOF
    log "Created default strategy at ${strategy_file}"
  fi

  log "Reading strategy from ${strategy_file}"
  cat "${strategy_file}"
}

#==============================================================================
# Step 2: Run benchmarks and compute score
#==============================================================================
run_benchmark() {
  local client="$1"
  local rpc_port="${CLIENT_RPC_PORTS[$client]:-8545}"

  log "Running benchmark for ${client}..."

  # If full benchmark script available, use it
  if [[ -f "${BENCHMARK_SCRIPT}" ]]; then
    local bench_result
    bench_result=$(bash "${BENCHMARK_SCRIPT}" full "${client}" 2>/dev/null || echo '{"score":0}')
    echo "${bench_result}"
    return 0
  fi

  # Fallback: quick inline benchmark
  local score=0.0
  local sync_score=0.0
  local peer_score=0.0
  local rpc_score=0.0
  local resource_score=0.0

  # Measure blocks/sec (2 samples, 30s apart)
  local block1_hex
  block1_hex=$(curl -sf --max-time 5 \
    -X POST "http://localhost:${rpc_port}" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    2>/dev/null | grep -oP '"result":"\K[^"]+' || echo "0x0")
  local block1=$((16#${block1_hex#0x}))
  local t1
  t1=$(date +%s)
  sleep 30
  local block2_hex
  block2_hex=$(curl -sf --max-time 5 \
    -X POST "http://localhost:${rpc_port}" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    2>/dev/null | grep -oP '"result":"\K[^"]+' || echo "${block1_hex}")
  local block2=$((16#${block2_hex#0x}))
  local t2
  t2=$(date +%s)
  local elapsed=$((t2 - t1))
  local blocks_synced=$((block2 - block1))
  local blocks_per_sec=0
  if [[ "${elapsed}" -gt 0 && "${blocks_synced}" -gt 0 ]]; then
    blocks_per_sec=$(echo "scale=3; ${blocks_synced} / ${elapsed}" | bc 2>/dev/null || echo "0")
  fi

  # Score sync speed (0.5–5.0 blocks/sec → 0.0–1.0)
  sync_score=$(echo "scale=3; if (${blocks_per_sec} > 5) print 1.0 else print ${blocks_per_sec} / 5.0" | bc 2>/dev/null || echo "0.5")

  # Measure peer count
  local peer_hex
  peer_hex=$(curl -sf --max-time 5 \
    -X POST "http://localhost:${rpc_port}" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
    2>/dev/null | grep -oP '"result":"\K[^"]+' || echo "0x0")
  local peer_count=$((16#${peer_hex#0x}))
  peer_score=$(echo "scale=3; if (${peer_count} >= 20) print 1.0 else print ${peer_count} / 20.0" | bc 2>/dev/null || echo "0.5")

  # Measure RPC latency (eth_blockNumber)
  local rpc_start rpc_end rpc_ms
  rpc_start=$(date +%s%N)
  curl -sf --max-time 5 \
    -X POST "http://localhost:${rpc_port}" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    >/dev/null 2>&1 || true
  rpc_end=$(date +%s%N)
  rpc_ms=$(( (rpc_end - rpc_start) / 1000000 ))
  rpc_score=$(echo "scale=3; if (${rpc_ms} < 50) print 1.0 else if (${rpc_ms} > 1000) print 0.0 else print (1000 - ${rpc_ms}) / 950.0" | bc 2>/dev/null || echo "0.5")

  # Resource usage
  local cpu_pct mem_pct
  local container="${CLIENT_CONTAINERS[$client]:-xdc-${client}}"
  if command -v docker &>/dev/null; then
    local stats
    stats=$(docker stats --no-stream --format "{{.CPUPerc}} {{.MemPerc}}" "${container}" 2>/dev/null || echo "0% 0%")
    cpu_pct=$(echo "${stats}" | awk '{print $1}' | tr -d '%' || echo "0")
    mem_pct=$(echo "${stats}" | awk '{print $2}' | tr -d '%' || echo "0")
  else
    cpu_pct=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | tr -d '%us,' || echo "50")
    mem_pct=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%.0f", (t-a)/t*100}' /proc/meminfo || echo "50")
  fi
  resource_score=$(echo "scale=3; cpu_w=0.5; mem_w=0.5; cpu_s=(100-${cpu_pct})/100; mem_s=(100-${mem_pct})/100; cpu_w*cpu_s + mem_w*mem_s" | bc 2>/dev/null || echo "0.5")

  # Weighted total score
  score=$(echo "scale=3; 0.5*${sync_score} + 0.2*${peer_score} + 0.1*${rpc_score} + 0.2*${resource_score}" | bc 2>/dev/null || echo "0.5")

  # Clamp to [0,1]
  score=$(echo "scale=3; if (${score} > 1.0) print 1.0 else if (${score} < 0.0) print 0.0 else print ${score}" | bc 2>/dev/null || echo "${score}")

  cat <<EOF
{
  "client": "${client}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "blocks_per_sec": ${blocks_per_sec},
  "peer_count": ${peer_count},
  "rpc_latency_ms": ${rpc_ms},
  "cpu_pct": ${cpu_pct},
  "score": ${score},
  "components": {
    "sync": ${sync_score},
    "peers": ${peer_score},
    "rpc": ${rpc_score},
    "resources": ${resource_score}
  }
}
EOF
}

#==============================================================================
# Config Mutation: Get mutable parameters per client
#==============================================================================

# Returns list of param|current_value|candidates (pipe-separated)
get_mutable_params() {
  local client="$1"
  local compose_file

  case "$client" in
    geth)
      compose_file="${REPO_DIR}/docker/geth/docker-compose.yml"
      cat <<'PARAMS'
maxpeers|50|25 50 75 100 150
cache|1024|512 1024 2048 4096
gcmode|full|full archive
txlookuplimit|2350000|0 2350000 10000000
PARAMS
      ;;
    erigon)
      compose_file="${REPO_DIR}/docker/erigon/docker-compose.yml"
      cat <<'PARAMS'
maxPeers|50|25 50 75 100
batchSize|512M|256M 512M 1G 2G
PARAMS
      ;;
    nethermind)
      compose_file="${REPO_DIR}/docker/nethermind/docker-compose.yml"
      cat <<'PARAMS'
Network.MaxActivePeers|50|25 50 75 100
JsonRpc.MaxBatchSize|128|64 128 256
Sync.MaxProcessingThreads|0|0 2 4
PARAMS
      ;;
    reth)
      compose_file="${REPO_DIR}/docker/reth/docker-compose.yml"
      cat <<'PARAMS'
max-peers|50|25 50 75 100
PARAMS
      ;;
  esac
}

#==============================================================================
# Config: Read current value of a param from compose file
#==============================================================================
read_current_param() {
  local client="$1"
  local param="$2"
  local compose_file

  case "$client" in
    geth)        compose_file="${REPO_DIR}/docker/geth/docker-compose.yml" ;;
    erigon)      compose_file="${REPO_DIR}/docker/erigon/docker-compose.yml" ;;
    nethermind)  compose_file="${REPO_DIR}/docker/nethermind/docker-compose.yml" ;;
    reth)        compose_file="${REPO_DIR}/docker/reth/docker-compose.yml" ;;
    *) echo "unknown"; return ;;
  esac

  if [[ ! -f "$compose_file" ]]; then
    echo "unknown"
    return
  fi

  # Try to extract current value from compose file
  local val
  val=$(grep -oE "--${param}[= ][^\" ]+" "$compose_file" 2>/dev/null | head -1 | sed "s/--${param}[= ]//" || echo "")
  [[ -z "$val" ]] && val="unknown"
  echo "$val"
}

#==============================================================================
# Config: Backup compose file
#==============================================================================
backup_compose() {
  local client="$1"
  local compose_file

  case "$client" in
    geth)        compose_file="${REPO_DIR}/docker/geth/docker-compose.yml" ;;
    erigon)      compose_file="${REPO_DIR}/docker/erigon/docker-compose.yml" ;;
    nethermind)  compose_file="${REPO_DIR}/docker/nethermind/docker-compose.yml" ;;
    reth)        compose_file="${REPO_DIR}/docker/reth/docker-compose.yml" ;;
    *) return ;;
  esac

  if [[ ! -f "$compose_file" ]]; then return; fi

  mkdir -p "${CONFIG_BACKUP_DIR}"
  local backup="${CONFIG_BACKUP_DIR}/${client}_$(date +%Y%m%d_%H%M%S).yml"
  cp "$compose_file" "$backup"
  log "Config backed up: $backup"
  echo "$backup"
}

#==============================================================================
# Config: Restore compose from backup
#==============================================================================
restore_compose() {
  local client="$1"
  local backup_file="$2"
  local compose_file

  case "$client" in
    geth)        compose_file="${REPO_DIR}/docker/geth/docker-compose.yml" ;;
    erigon)      compose_file="${REPO_DIR}/docker/erigon/docker-compose.yml" ;;
    nethermind)  compose_file="${REPO_DIR}/docker/nethermind/docker-compose.yml" ;;
    reth)        compose_file="${REPO_DIR}/docker/reth/docker-compose.yml" ;;
    *) return ;;
  esac

  if [[ -f "$backup_file" ]]; then
    cp "$backup_file" "$compose_file"
    log "Config restored from backup: $backup_file"
  fi
}

#==============================================================================
# Config: Mutate a parameter in compose file
#==============================================================================
mutate_param() {
  local client="$1"
  local param="$2"
  local new_value="$3"
  local compose_file

  case "$client" in
    geth)        compose_file="${REPO_DIR}/docker/geth/docker-compose.yml" ;;
    erigon)      compose_file="${REPO_DIR}/docker/erigon/docker-compose.yml" ;;
    nethermind)  compose_file="${REPO_DIR}/docker/nethermind/docker-compose.yml" ;;
    reth)        compose_file="${REPO_DIR}/docker/reth/docker-compose.yml" ;;
    *) warn "Unknown client: $client"; return 1 ;;
  esac

  if [[ ! -f "$compose_file" ]]; then
    warn "Compose file not found: $compose_file (skipping mutation)"
    return 0
  fi

  # Try to replace existing param
  if grep -qE "--${param}[= ]" "$compose_file" 2>/dev/null; then
    sed -i "s|--${param}[= ][^\" ]*|--${param}=${new_value}|g" "$compose_file"
    log "Mutated: --${param}=${new_value} in ${compose_file}"
  else
    # Inject new param after the command line start
    log "Parameter --${param} not found in compose; inserting"
    # For geth: inject into command section
    case "$client" in
      geth|erigon|reth)
        sed -i "/command:/a\      - --${param}=${new_value}" "$compose_file" 2>/dev/null || true ;;
      nethermind)
        sed -i "/environment:/a\      - ${param}=${new_value}" "$compose_file" 2>/dev/null || true ;;
    esac
  fi
}

#==============================================================================
# Config: Restart container after mutation
#==============================================================================
restart_client() {
  local client="$1"
  local cname="${CLIENT_CONTAINERS[$client]:-xdc-${client}}"

  if [[ "${NO_RESTART}" == true ]]; then
    warn "--no-restart: skipping container restart for ${client}"
    return 0
  fi

  log "Restarting ${cname} to apply config..."
  docker restart "${cname}" 2>/dev/null && sleep 10 || warn "Failed to restart ${cname}"
}

#==============================================================================
# Winners tracking
#==============================================================================
record_winner() {
  local client="$1" param="$2" value="$3" score="$4"
  mkdir -p "${EXPERIMENT_DIR}"
  local entry
  entry="{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"client\":\"${client}\",\"param\":\"${param}\",\"value\":\"${value}\",\"score\":${score}}"
  if [[ -f "${WINNERS_LOG}" ]]; then
    local tmp; tmp=$(mktemp)
    sed '$ d' "${WINNERS_LOG}" > "$tmp"
    echo ",${entry}]" >> "$tmp"
    mv "$tmp" "${WINNERS_LOG}"
  else
    echo "[${entry}]" > "${WINNERS_LOG}"
  fi
  log "Winner recorded: ${param}=${value} (score=${score})"
}

show_winners() {
  if [[ ! -f "${WINNERS_LOG}" ]]; then
    log "No winners recorded yet."
    return
  fi
  log "=== Winning Configurations ==="
  python3 - "${WINNERS_LOG}" <<'PYEOF' 2>/dev/null || cat "${WINNERS_LOG}"
import json, sys
with open(sys.argv[1]) as f:
    winners = json.load(f)
for w in winners[-20:]:
    print(f"  {w['client']:<12} {w['param']:<20} = {w['value']:<15} score={w['score']}")
PYEOF
}

#==============================================================================
# Step 3: Apply an experimental config change
#==============================================================================
apply_experiment() {
  local client="$1"
  local param="$2"
  local value="$3"

  log "EXPERIMENT: Apply ${param}=${value} to ${client}"

  if [[ "${DRY_RUN}" == true ]]; then
    log "[DRY-RUN] Would apply ${param}=${value} to ${client}"
    return 0
  fi

  mutate_param "$client" "$param" "$value"
  restart_client "$client"
}

#==============================================================================
# Step 4: Revert a change
#==============================================================================
revert_experiment() {
  local client="$1"
  local param="$2"
  local old_value="$3"
  local backup_file="${4:-}"

  log "REVERT: Restoring ${param}=${old_value} for ${client}"

  if [[ "${DRY_RUN}" == true ]]; then
    log "[DRY-RUN] Would revert ${param} to ${old_value}"
    return 0
  fi

  if [[ -n "$backup_file" && -f "$backup_file" ]]; then
    restore_compose "$client" "$backup_file"
  else
    mutate_param "$client" "$param" "$old_value"
  fi
  restart_client "$client"
  log "Reverted ${param} to ${old_value}"
}

#==============================================================================
# Step 5: Log experiment result
#==============================================================================
log_experiment() {
  local client="$1"
  local iteration="$2"
  local param="$3"
  local value="$4"
  local baseline_score="$5"
  local new_score="$6"
  local decision="$7"  # kept | reverted | dry_run

  mkdir -p "${EXPERIMENT_DIR}"

  local entry
  entry=$(cat <<EOF
{
  "iteration": ${iteration},
  "client": "${client}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "param": "${param}",
  "value": "${value}",
  "baseline_score": ${baseline_score},
  "new_score": ${new_score},
  "delta": $(echo "scale=3; ${new_score} - ${baseline_score}" | bc 2>/dev/null || echo "0"),
  "decision": "${decision}"
}
EOF
)

  if [[ -f "${EXPERIMENT_LOG}" ]]; then
    local tmp
    tmp=$(mktemp)
    sed '$ d' "${EXPERIMENT_LOG}" > "${tmp}"
    echo ",${entry}]" >> "${tmp}"
    mv "${tmp}" "${EXPERIMENT_LOG}"
  else
    echo "[${entry}]" > "${EXPERIMENT_LOG}"
  fi

  log "Experiment logged: ${EXPERIMENT_LOG}"
}

#==============================================================================
# Main optimization loop
#==============================================================================
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --client)     TARGET_CLIENT="$2"; shift 2 ;;
      --strategy)   STRATEGY_FILE="$2"; shift 2 ;;
      --iterations) MAX_ITERATIONS="$2"; shift 2 ;;
      --dry-run)    DRY_RUN=true; shift ;;
      --mutate)     MUTATE_MODE=true; shift ;;
      --no-restart) NO_RESTART=true; shift ;;
      --param)      SPECIFIC_PARAM="$2"; shift 2 ;;
      --value)      SPECIFIC_VALUE="$2"; shift 2 ;;
      --winners)    show_winners; exit 0 ;;
      --help|-h)
        grep "^#" "$0" | head -25 | sed 's/^#//'
        exit 0
        ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done
}

main() {
  parse_args "$@"

  log "AutoAgent Meta-Optimizer starting"
  log "Client: ${TARGET_CLIENT}, Iterations: ${MAX_ITERATIONS}, Dry-run: ${DRY_RUN}"

  # Step 1: Read strategy
  read_strategy "${STRATEGY_FILE}" > /dev/null

  # Extract optimization params from strategy (simple grep-based approach)
  # Real implementation would parse YAML/JSON strategy format
  log "Parsing optimization parameters from strategy..."

  # Build parameter list from mutation table or command line
  local -a PARAMS=()
  local -a VALUES=()

  if [[ -n "$SPECIFIC_PARAM" && -n "$SPECIFIC_VALUE" ]]; then
    # Single param test from CLI
    PARAMS=("$SPECIFIC_PARAM")
    VALUES=("$SPECIFIC_VALUE")
  elif [[ "$MUTATE_MODE" == true ]]; then
    # Auto-discover mutable params from config table
    log "Mutation mode: discovering parameters for ${TARGET_CLIENT}"
    while IFS='|' read -r param current candidates; do
      [[ -z "$param" ]] && continue
      # Use first candidate different from current
      for cand in $candidates; do
        if [[ "$cand" != "$current" ]]; then
          PARAMS+=("$param")
          VALUES+=("$cand")
          break
        fi
      done
    done < <(get_mutable_params "${TARGET_CLIENT}" 2>/dev/null || true)

    if [[ "${#PARAMS[@]}" -eq 0 ]]; then
      warn "No mutable parameters found for ${TARGET_CLIENT}"
    else
      log "Will test ${#PARAMS[@]} parameters: ${PARAMS[*]}"
    fi
  else
    # Default: legacy param list from strategy hints
    PARAMS=("cache" "maxpeers" "gcmode")
    VALUES=("2048" "75" "full")
  fi

  # Step 2: Get baseline benchmark
  log "=== Baseline benchmark ==="
  local baseline_json
  baseline_json=$(run_benchmark "${TARGET_CLIENT}")
  local baseline_score
  baseline_score=$(echo "${baseline_json}" | grep -oP '"score":\s*\K[\d.]+' || echo "0.5")
  log "Baseline score: ${baseline_score}"

  local best_score="${baseline_score}"
  local iteration=0

  # Step 3: Optimization loop
  for i in "${!PARAMS[@]}"; do
    param="${PARAMS[$i]}"
    value="${VALUES[$i]}"
    iteration=$((iteration + 1))

    if [[ "${iteration}" -gt "${MAX_ITERATIONS}" ]]; then
      log "Max iterations (${MAX_ITERATIONS}) reached"
      break
    fi

    log "=== Iteration ${iteration}/${MAX_ITERATIONS}: ${param}=${value} ==="

    # Read current value before mutation
    local current_val
    current_val=$(read_current_param "${TARGET_CLIENT}" "${param}")

    # Backup compose before mutation
    local backup_file=""
    [[ "${DRY_RUN}" == false ]] && backup_file=$(backup_compose "${TARGET_CLIENT}" 2>/dev/null || echo "")

    # Apply change
    apply_experiment "${TARGET_CLIENT}" "${param}" "${value}"

    # Wait for node to stabilize
    if [[ "${DRY_RUN}" == false && "${NO_RESTART}" == false ]]; then
      log "Waiting 30s for node to stabilize after restart..."
      sleep 30
    fi

    # Benchmark after change
    log "Benchmarking after change (${param}=${value})..."
    local new_json
    new_json=$(run_benchmark "${TARGET_CLIENT}")
    local new_score
    new_score=$(echo "${new_json}" | grep -oP '"score":\s*\K[\d.]+' || echo "0.5")

    local delta
    delta=$(echo "scale=3; ${new_score} - ${best_score}" | bc 2>/dev/null || echo "0")
    log "Score: ${best_score} → ${new_score} (delta=${delta})"

    # Decide: keep or revert
    local min_improvement
    min_improvement=$(echo "scale=3; ${IMPROVEMENT_THRESHOLD}" | bc)
    local improved
    improved=$(echo "${delta} >= ${min_improvement}" | bc 2>/dev/null || echo "0")

    if [[ "${DRY_RUN}" == true ]]; then
      log "[DRY-RUN] Would ${improved:+keep}${improved:-revert} change (delta=${delta})"
      log_experiment "${TARGET_CLIENT}" "${iteration}" "${param}" "${value}" \
        "${best_score}" "${new_score}" "dry_run"
    elif [[ "${improved}" -eq 1 ]]; then
      log "IMPROVEMENT detected (${delta} >= ${IMPROVEMENT_THRESHOLD}) — keeping change ✓"
      best_score="${new_score}"
      record_winner "${TARGET_CLIENT}" "${param}" "${value}" "${new_score}"
      log_experiment "${TARGET_CLIENT}" "${iteration}" "${param}" "${value}" \
        "${baseline_score}" "${new_score}" "kept"
    else
      log "NO IMPROVEMENT (${delta} < ${IMPROVEMENT_THRESHOLD}) — reverting"
      revert_experiment "${TARGET_CLIENT}" "${param}" "${current_val}" "${backup_file}"
      log_experiment "${TARGET_CLIENT}" "${iteration}" "${param}" "${value}" \
        "${best_score}" "${new_score}" "reverted"
    fi
  done

  log "=== Optimization complete ==="
  log "Final score: ${best_score} (baseline: ${baseline_score})"
  log "Experiment log: ${EXPERIMENT_LOG}"
  [[ "${best_score}" != "${baseline_score}" ]] && show_winners
}

main "$@"
