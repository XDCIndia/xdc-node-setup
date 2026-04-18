#!/usr/bin/env bash
#==============================================================================
# validate-snapshot-deep.sh — Deep Snapshot Validator
# Issue: #165 — XNS Snapshot Validation Integration (Phase 1.2)
#
# Purpose:
#   Perform state-completeness validation on extracted chaindata directories.
#   Supports three validation levels with human-readable or JSON output.
#
# Usage:
#   validate-snapshot-deep.sh --datadir <path> [--quick|--standard|--full]
#                             [--json] [--output <file>] [--fail-fast]
#                             [--notify] [--no-color] [--help]
#
# Validation Levels:
#   quick    (~5s)   File structure, CURRENT marker, non-empty ancient/,
#                    minimum SST count
#   standard (~30s)  Quick + metadata bounds + block vs state consistency
#   full     (~2min) Standard + sample trie key verification +
#                    ancient segment continuity
#
# Exit Codes:
#   0 — validation passed (warnings allowed)
#   1 — validation failed (critical check failed)
#   2 — bad arguments / missing dependencies
#   3 — datadir not found / no chaindata
#==============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/lib"

# ---------------------------------------------------------------------------
# Source shared libraries
# ---------------------------------------------------------------------------
source "${LIB_DIR}/snapshot-validation.sh" 2>/dev/null || {
  echo "[ERROR] Required library not found: ${LIB_DIR}/snapshot-validation.sh" >&2
  exit 2
}

# common.sh is already sourced by snapshot-validation.sh, but ensure logging
if ! command -v log_info &>/dev/null; then
  log_info()  { echo -e "[INFO]  $(date '+%H:%M:%S') $*"; }
  log_warn()  { echo -e "[WARN]  $(date '+%H:%M:%S') $*" >&2; }
  log_error() { echo -e "[ERROR] $(date '+%H:%M:%S') $*" >&2; }
  log_debug() { [[ "${DEBUG:-0}" == "1" ]] && echo -e "[DEBUG] $(date '+%H:%M:%S') $*"; }
fi

# ---------------------------------------------------------------------------
# Defaults & config
# SNAPVAL_CONFIG is already defined (possibly readonly) by snapshot-validation.sh
: "${SNAPVAL_CONFIG:=${REPO_DIR}/configs/snapshots.json}"

# CLI state
DATADIR=""
LEVEL="standard"
OUTPUT_JSON=false
OUTPUT_FILE=""
FAIL_FAST=false
NOTIFY=false
NO_COLOR=false
NETWORK="mainnet"
TYPE="full"

# ---------------------------------------------------------------------------
# Colors (toggleable)
# ---------------------------------------------------------------------------
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[0;34m'
C_BOLD='\033[1m'
C_RESET='\033[0m'

disable_color() {
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''; C_RESET=''
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die() {
  log_error "$*"
  exit 2
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Perform state-completeness validation on extracted chaindata directories.

Options:
  -d, --datadir <path>   Data directory to validate (required)
  --quick                Fast structural check (~5s)
  --standard             Structural + heuristic checks (~30-60s) [default]
  --full                 Deep database inspection (~2-5min)
  --json                 Output JSON instead of human-readable table
  -o, --output <file>    Write JSON report to file
  --fail-fast            Exit non-zero on first critical failure
  --notify               Send alert on failure (requires notify.conf)
  --no-color             Disable colored output
  --network <name>       Network: mainnet|testnet (default: mainnet)
  --type <type>          Snapshot type: full|archive (default: full)
  -h, --help             Show this help

Exit codes:
  0  Validation passed (warnings may be present)
  1  Validation failed
  2  Bad arguments / missing dependencies
  3  Datadir not found / no chaindata

Examples:
  $(basename "$0") --datadir /data/xdcchain --quick
  $(basename "$0") -d /data/xdcchain --full --json --output report.json
  $(basename "$0") --datadir /data --standard --fail-fast --notify
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --datadir|-d)
        DATADIR="$2"
        shift 2
        ;;
      --quick)
        LEVEL="quick"
        shift
        ;;
      --standard)
        LEVEL="standard"
        shift
        ;;
      --full)
        LEVEL="full"
        shift
        ;;
      --json)
        OUTPUT_JSON=true
        shift
        ;;
      --output|-o)
        OUTPUT_FILE="$2"
        shift 2
        ;;
      --fail-fast)
        FAIL_FAST=true
        shift
        ;;
      --notify)
        NOTIFY=true
        shift
        ;;
      --no-color)
        NO_COLOR=true
        shift
        ;;
      --network)
        NETWORK="$2"
        shift 2
        ;;
      --type)
        TYPE="$2"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  if [[ "$NO_COLOR" == "true" ]]; then
    disable_color
  fi

  if [[ -z "$DATADIR" ]]; then
    die "--datadir is required"
  fi
}

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
check_dependencies() {
  local missing=()

  if ! command -v jq &>/dev/null; then
    missing+=("jq")
  fi

  if ! command -v find &>/dev/null; then
    missing+=("find")
  fi

  if ! command -v du &>/dev/null; then
    missing+=("du")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required commands: ${missing[*]}"
  fi

  if [[ "$LEVEL" == "full" ]] && ! command -v ldb &>/dev/null; then
    log_warn "ldb (rocksdb-tools) not found — full-level key-prefix check will be skipped"
  fi
}

# ---------------------------------------------------------------------------
# Result tracking
# ---------------------------------------------------------------------------
declare -a CHECK_RESULTS=()
declare -i CRITICAL_FAILED=0
declare -i WARNING_COUNT=0

# _record <check_name> <passed:true|false> <severity:pass|warn|fail> <detail_json>
_record() {
  local name="$1"
  local passed="$2"
  local severity="$3"
  local detail="$4"

  CHECK_RESULTS+=("$(printf '%s\t%s\t%s\t%s' "$name" "$passed" "$severity" "$detail")")

  if [[ "$passed" == "false" && "$severity" == "fail" ]]; then
    ((CRITICAL_FAILED++)) || true
    if [[ "$FAIL_FAST" == "true" ]]; then
      return 1
    fi
  elif [[ "$passed" == "false" && "$severity" == "warn" ]]; then
    ((WARNING_COUNT++)) || true
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------------

run_check_layout() {
  local datadir="$1"
  local detail=""
  local passed="true"
  local severity="pass"

  if ! snapshot_check_layout "$datadir"; then
    passed="false"
    severity="fail"
    detail='{"detail":"No chaindata layout detected"}'
  else
    detail="{\"detail\":\"${SNAPSHOT_SUBDIR:-(direct)}/chaindata\"}"
  fi

  _record "layout" "$passed" "$severity" "$detail" || return 1
  return 0
}

run_check_engine() {
  local chaindata_path="$1"
  local engine=""
  local passed="true"
  local severity="pass"
  local detail=""

  engine=$(snapshot_detect_engine "$chaindata_path")
  if [[ "$engine" == "unknown" ]]; then
    passed="false"
    severity="fail"
    detail='{"detail":"No database engine detected (no .sst or .ldb files)"}'
  else
    detail="{\"detail\":\"$engine\"}"
  fi

  _record "databaseEngine" "$passed" "$severity" "$detail" || return 1
  return 0
}

run_check_current_marker() {
  local chaindata_path="$1"
  local passed="true"
  local severity="pass"
  local detail=""

  if [[ ! -f "$chaindata_path/CURRENT" ]]; then
    passed="false"
    severity="fail"
    detail='{"detail":"CURRENT marker missing"}'
  else
    detail='{"detail":"CURRENT marker present"}'
  fi

  _record "currentMarker" "$passed" "$severity" "$detail" || return 1
  return 0
}

run_check_min_files() {
  local chaindata_path="$1"
  local network="$2"
  local type="$3"
  local passed="true"
  local severity="pass"
  local count=0
  local min_files=0
  local detail=""

  snapshot_load_thresholds "$network" "$type" || true
  count=$(snapshot_count_files "$chaindata_path")
  min_files="${MIN_FILES:-0}"

  if [[ "$count" -lt "$min_files" ]]; then
    passed="false"
    severity="fail"
    detail="{\"actual\":$count,\"minimum\":$min_files,\"detail\":\"File count $count < minimum $min_files\"}"
  else
    detail="{\"actual\":$count,\"minimum\":$min_files,\"detail\":\"File count OK\"}"
  fi

  _record "fileCount" "$passed" "$severity" "$detail" || return 1
  return 0
}

run_check_min_size() {
  local chaindata_path="$1"
  local network="$2"
  local type="$3"
  local passed="true"
  local severity="pass"
  local size=0
  local min_size=0
  local detail=""

  snapshot_load_thresholds "$network" "$type" || true
  size=$(snapshot_get_size "$chaindata_path")
  min_size="${MIN_SIZE_BYTES:-0}"

  if [[ "$size" -lt "$min_size" ]]; then
    passed="false"
    severity="fail"
    detail="{\"actual\":$size,\"minimum\":$min_size,\"detail\":\"Chaindata size below minimum\"}"
  else
    detail="{\"actual\":$size,\"minimum\":$min_size,\"detail\":\"Size OK\"}"
  fi

  _record "chaindataSize" "$passed" "$severity" "$detail" || return 1
  return 0
}

run_check_ancient_integrity() {
  local chaindata_path="$1"
  local passed="true"
  local severity="pass"
  local detail=""

  if ! snapshot_check_ancient_integrity "$chaindata_path"; then
    passed="false"
    severity="fail"
    detail='{"detail":"Ancient store incomplete or empty"}'
  else
    local ancient_json=""
    ancient_json=$(snapshot_detect_ancient "$chaindata_path")
    detail="{\"segments\":$ancient_json,\"detail\":\"Ancient store OK\"}"
  fi

  _record "ancientStore" "$passed" "$severity" "$detail" || return 1
  return 0
}

run_check_state_cache() {
  local datadir="$1"
  local passed="true"
  local severity="pass"
  local detail=""
  local found=false

  if [[ -f "$datadir/xdc-state-root-cache.csv" ]]; then
    found=true
  elif [[ -f "$datadir/geth/xdc-state-root-cache.csv" ]]; then
    found=true
  elif [[ -f "$datadir/XDC/xdc-state-root-cache.csv" ]]; then
    found=true
  elif [[ -f "$datadir/xdcchain/xdc-state-root-cache.csv" ]]; then
    found=true
  fi

  if [[ "$found" == "true" ]]; then
    detail='{"detail":"State root cache found"}'
  else
    passed="false"
    severity="warn"
    detail='{"detail":"xdc-state-root-cache.csv missing — cold recovery may be slower"}'
  fi

  _record "stateRootCache" "$passed" "$severity" "$detail"
  return 0
}

run_check_block_state_consistency() {
  local chaindata_path="$1"
  local network="$2"
  local type="$3"
  local passed="true"
  local severity="pass"
  local detail=""
  local height=0
  local max_gap="${MAX_STATE_GAP:-10}"

  height=$(snapshot_estimate_block_height "$chaindata_path")

  # If height is 0, we can't validate; warn rather than fail
  if [[ "$height" -eq 0 ]]; then
    severity="warn"
    passed="false"
    detail='{"blockHeight":0,"stateHeight":0,"gap":0,"detail":"Could not estimate block height"}'
    _record "blockStateConsistency" "$passed" "$severity" "$detail"
    return 0
  fi

  # Heuristic: if estimated height seems very low, warn
  # Mainnet is well past 50M blocks; testnet past 30M.
  local min_expected=1000000
  if [[ "$network" == "testnet" ]]; then
    min_expected=500000
  fi

  if [[ "$height" -lt "$min_expected" ]]; then
    severity="warn"
    passed="false"
    detail="{\"blockHeight\":$height,\"stateHeight\":$height,\"gap\":0,\"detail\":\"Estimated block height ($height) seems low for $network\"}"
    _record "blockStateConsistency" "$passed" "$severity" "$detail"
    return 0
  fi

  # In bash-only validation we cannot walk the trie to get exact state height.
  # We use file-count heuristic as a proxy: if chaindata has many files,
  # we assume state is roughly aligned. A future Go plugin can replace this.
  local file_count=0
  file_count=$(snapshot_count_files "$chaindata_path")

  # Rough heuristic: each ~1000 files covers ~1M blocks of state keys
  local state_height=$((file_count * 1000))
  local gap=0

  if [[ "$state_height" -gt "$height" ]]; then
    gap=$((state_height - height))
  else
    gap=$((height - state_height))
  fi

  if [[ "$gap" -gt "$max_gap" && "$max_gap" -gt 0 ]]; then
    # For heuristic-based check, treat large gap as warning not critical
    severity="warn"
    passed="false"
    detail="{\"blockHeight\":$height,\"stateHeight\":$state_height,\"gap\":$gap,\"detail\":\"Heuristic state gap exceeds tolerance ($max_gap)\"}"
  else
    detail="{\"blockHeight\":$height,\"stateHeight\":$state_height,\"gap\":$gap,\"detail\":\"Within tolerance\"}"
  fi

  _record "blockStateConsistency" "$passed" "$severity" "$detail"
  return 0
}

run_check_key_prefixes() {
  local chaindata_path="$1"
  local passed="true"
  local severity="pass"
  local detail=""

  if ! snapshot_check_key_prefixes "$chaindata_path"; then
    passed="false"
    severity="warn"
    detail='{"detail":"No expected key prefixes found in database sample"}'
  else
    detail='{"detail":"Key prefixes detected"}'
  fi

  _record "keyPrefixes" "$passed" "$severity" "$detail"
  return 0
}

run_check_segment_continuity() {
  local chaindata_path="$1"
  local passed="true"
  local severity="pass"
  local detail=""

  if ! snapshot_check_segment_continuity "$chaindata_path/ancient"; then
    passed="false"
    severity="warn"
    detail='{"detail":"Ancient segment continuity check found gaps"}'
  else
    detail='{"detail":"Ancient segments are contiguous"}'
  fi

  _record "segmentContinuity" "$passed" "$severity" "$detail"
  return 0
}

# ---------------------------------------------------------------------------
# Dispatch checks by level
# ---------------------------------------------------------------------------
run_checks() {
  local datadir="$1"
  local chaindata_path="$2"
  local level="$3"
  local network="$4"
  local type="$5"

  # ---------- QUICK ----------
  run_check_layout "$datadir" || { [[ "$FAIL_FAST" == "true" ]] && return 1; }

  # If layout failed, we may not have a valid chaindata path; try anyway
  if [[ -z "$chaindata_path" || ! -d "$chaindata_path" ]]; then
    log_error "No chaindata directory found after layout check"
    return 1
  fi

  run_check_engine "$chaindata_path" || { [[ "$FAIL_FAST" == "true" ]] && return 1; }
  run_check_current_marker "$chaindata_path" || { [[ "$FAIL_FAST" == "true" ]] && return 1; }
  run_check_ancient_integrity "$chaindata_path" || { [[ "$FAIL_FAST" == "true" ]] && return 1; }
  run_check_min_files "$chaindata_path" "$network" "$type" || { [[ "$FAIL_FAST" == "true" ]] && return 1; }

  # ---------- STANDARD (and FULL) ----------
  if [[ "$level" == "standard" || "$level" == "full" ]]; then
    run_check_min_size "$chaindata_path" "$network" "$type" || { [[ "$FAIL_FAST" == "true" ]] && return 1; }
    run_check_block_state_consistency "$chaindata_path" "$network" "$type" || { [[ "$FAIL_FAST" == "true" ]] && return 1; }
  fi

  # ---------- FULL ----------
  if [[ "$level" == "full" ]]; then
    run_check_key_prefixes "$chaindata_path" || { [[ "$FAIL_FAST" == "true" ]] && return 1; }
    run_check_segment_continuity "$chaindata_path" || { [[ "$FAIL_FAST" == "true" ]] && return 1; }
  fi

  # State cache is always checked (warn only)
  run_check_state_cache "$datadir"

  return 0
}

# ---------------------------------------------------------------------------
# Output formatters
# ---------------------------------------------------------------------------
print_table() {
  local level="$1"
  local datadir="$2"
  local chaindata_subdir="${3:-}"
  local overall_passed="$4"
  local summary="$5"

  printf "\n"
  printf "${C_BOLD}══════════════════════════════════════════════════════════════════════${C_RESET}\n"
  printf "${C_BOLD}  XDC Snapshot Validation Report${C_RESET}\n"
  printf "${C_BOLD}══════════════════════════════════════════════════════════════════════${C_RESET}\n"
  printf "  Level:           %s\n" "$level"
  printf "  Datadir:         %s\n" "$datadir"
  printf "  Chaindata subdir: %s\n" "${chaindata_subdir:-(direct)}"
  printf "  Overall:         %b\n" "$overall_passed"
  printf "${C_BOLD}──────────────────────────────────────────────────────────────────────${C_RESET}\n"
  printf "  %-22s %-10s %s\n" "CHECK" "RESULT" "DETAIL"
  printf "${C_BOLD}──────────────────────────────────────────────────────────────────────${C_RESET}\n"

  local line name passed severity detail
  for line in "${CHECK_RESULTS[@]}"; do
    name="$(echo "$line" | cut -f1)"
    passed="$(echo "$line" | cut -f2)"
    severity="$(echo "$line" | cut -f3)"
    detail="$(echo "$line" | cut -f4-)"

    local status_color=""
    local status_text=""
    if [[ "$passed" == "true" ]]; then
      status_color="$C_GREEN"
      status_text="PASS"
    elif [[ "$severity" == "warn" ]]; then
      status_color="$C_YELLOW"
      status_text="WARN"
    else
      status_color="$C_RED"
      status_text="FAIL"
    fi

    # Extract a short detail for the table
    local short_detail=""
    short_detail=$(echo "$detail" | jq -r '.detail // empty' 2>/dev/null || echo "")
    if [[ -z "$short_detail" ]]; then
      short_detail="$detail"
    fi
    # Truncate if too long
    if [[ "${#short_detail}" -gt 42 ]]; then
      short_detail="${short_detail:0:39}..."
    fi

    printf "  ${status_color}%-22s %-10s${C_RESET} %s\n" "$name" "$status_text" "$short_detail"
  done

  printf "${C_BOLD}──────────────────────────────────────────────────────────────────────${C_RESET}\n"
  printf "  Summary: %s\n" "$summary"
  printf "${C_BOLD}══════════════════════════════════════════════════════════════════════${C_RESET}\n\n"
}

build_json() {
  local level="$1"
  local datadir="$2"
  local chaindata_subdir="${3:-}"
  local overall_valid="$4"
  local summary="$5"

  # Build checks as a JSON array of {name, passed, severity, detail} objects
  local checks_array="["
  local first=true
  local line name passed severity detail

  for line in "${CHECK_RESULTS[@]}"; do
    name="$(echo "$line" | cut -f1)"
    passed="$(echo "$line" | cut -f2)"
    severity="$(echo "$line" | cut -f3)"
    detail="$(echo "$line" | cut -f4-)"

    [[ "$first" == "true" ]] || checks_array+=","
    first=false

    local passed_json="false"
    [[ "$passed" == "true" ]] && passed_json="true"

    checks_array+="{\"name\":\"$name\",\"passed\":$passed_json,\"severity\":\"$severity\",\"detail\":$detail}"
  done

  checks_array+="]"

  # Convert array to keyed object and build final report with jq
  jq -n \
    --argjson valid "$overall_valid" \
    --arg level "$level" \
    --arg datadir "$datadir" \
    --arg chaindataSubdir "$chaindata_subdir" \
    --argjson checksArray "$checks_array" \
    --arg summary "$summary" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      valid: $valid,
      level: $level,
      datadir: $datadir,
      chaindataSubdir: $chaindataSubdir,
      checks: ($checksArray | map({(.name): (. | del(.name))}) | add // {}),
      summary: $summary,
      timestamp: $timestamp
    }'
}

# ---------------------------------------------------------------------------
# Notification
# ---------------------------------------------------------------------------
send_notification() {
  local level="$1"
  local summary="$2"

  if [[ "$NOTIFY" != "true" ]]; then
    return 0
  fi

  if [[ -f "${LIB_DIR}/notify.sh" ]]; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/notify.sh"
    if command -v notify_load_config &>/dev/null; then
      notify_load_config
    fi
    if command -v notify_alert &>/dev/null; then
      notify_alert "$level" "Snapshot Validation ${level^^}" \
        "$summary (datadir: $DATADIR, level: $LEVEL)"
    fi
  else
    log_warn "notify.sh not found, skipping notification"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  parse_args "$@"
  check_dependencies

  # Validate datadir exists
  if ! [[ -d "$DATADIR" ]]; then
    log_error "datadir not found: $DATADIR"
    exit 3
  fi

  # Detect layout
  local chaindata_subdir=""
  local chaindata_path=""

  if ! snapshot_check_layout "$DATADIR"; then
    log_error "No chaindata layout detected in $DATADIR"
    exit 3
  fi

  chaindata_subdir="${SNAPSHOT_SUBDIR:-}"
  if [[ -n "$chaindata_subdir" ]]; then
    chaindata_path="$DATADIR/$chaindata_subdir/chaindata"
  else
    chaindata_path="$DATADIR/chaindata"
  fi

  if ! [[ -d "$chaindata_path" ]]; then
    log_error "Chaindata directory not found: $chaindata_path"
    exit 3
  fi

  log_info "Starting $LEVEL validation of $chaindata_path"

  local start_time end_time duration
  start_time=$(date +%s)

  # Run all checks
  if ! run_checks "$DATADIR" "$chaindata_path" "$LEVEL" "$NETWORK" "$TYPE"; then
    # fail-fast path — a critical check failed early
    : # continue to output results collected so far
  fi

  end_time=$(date +%s)
  duration=$((end_time - start_time))

  # Determine overall result
  local overall_valid="false"
  local summary=""
  local exit_code=1

  if [[ "$CRITICAL_FAILED" -eq 0 ]]; then
    overall_valid="true"
    exit_code=0
    if [[ "$WARNING_COUNT" -gt 0 ]]; then
      summary="All critical checks passed ($WARNING_COUNT warning(s))"
    else
      summary="All checks passed"
    fi
  else
    overall_valid="false"
    exit_code=1
    summary="Validation failed: $CRITICAL_FAILED critical check(s) failed"
    if [[ "$WARNING_COUNT" -gt 0 ]]; then
      summary+=", $WARNING_COUNT warning(s)"
    fi
  fi

  # Output
  if [[ "$OUTPUT_JSON" == "true" ]]; then
    local json_output=""
    json_output=$(build_json "$LEVEL" "$DATADIR" "$chaindata_subdir" "$overall_valid" "$summary")
    echo "$json_output"
    if [[ -n "$OUTPUT_FILE" ]]; then
      echo "$json_output" > "$OUTPUT_FILE"
      log_info "JSON report written to $OUTPUT_FILE"
    fi
  else
    local overall_status=""
    if [[ "$overall_valid" == "true" ]]; then
      overall_status="${C_GREEN}PASS${C_RESET}"
    else
      overall_status="${C_RED}FAIL${C_RESET}"
    fi
    print_table "$LEVEL" "$DATADIR" "$chaindata_subdir" "$overall_status" "$summary"
    if [[ -n "$OUTPUT_FILE" ]]; then
      build_json "$LEVEL" "$DATADIR" "$chaindata_subdir" "$overall_valid" "$summary" > "$OUTPUT_FILE"
      log_info "JSON report written to $OUTPUT_FILE"
    fi
  fi

  log_info "Validation completed in ${duration}s"

  # Notification
  if [[ "$exit_code" -ne 0 ]]; then
    send_notification "critical" "$summary"
  elif [[ "$WARNING_COUNT" -gt 0 ]]; then
    send_notification "warning" "$summary"
  fi

  exit "$exit_code"
}

main "$@"
