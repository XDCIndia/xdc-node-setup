#!/usr/bin/env bash
#==============================================================================
# snapshot-validation.sh — Reusable Snapshot Validation Library
# Issue: #165 — XNS Snapshot Validation Integration
#
# Purpose:
#   Reusable validation functions sourced by both the standalone script
#   and the CLI. All functions are local-variable safe and cross-platform.
#
# Usage:
#   source "${LIB_DIR}/snapshot-validation.sh"
#   snapshot_check_layout "/data/xdcchain" || exit 1
#
# Dependencies: jq (for threshold loading), find, du, stat
# Optional:     ldb (from rocksdb-tools) for full-level key verification
#==============================================================================
set -euo pipefail

[[ "${_XDC_SNAPSHOT_VALIDATION_LOADED:-}" == "1" ]] && return 0
_XDC_SNAPSHOT_VALIDATION_LOADED=1

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
readonly _SNAPVAL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly _SNAPVAL_REPO_DIR="$(cd "${_SNAPVAL_SCRIPT_DIR}/../.." && pwd)"

# Source shared libs if available
source "${_SNAPVAL_SCRIPT_DIR}/common.sh" 2>/dev/null || true
source "${_SNAPVAL_SCRIPT_DIR}/chaindata.sh" 2>/dev/null || true

# Fallback logging if common.sh was not sourced
if ! command -v log_info &>/dev/null; then
  log_info()  { echo -e "[INFO]  $(date '+%H:%M:%S') $*"; }
  log_warn()  { echo -e "[WARN]  $(date '+%H:%M:%S') $*" >&2; }
  log_error() { echo -e "[ERROR] $(date '+%H:%M:%S') $*" >&2; }
  log_debug() { [[ "${DEBUG:-0}" == "1" ]] && echo -e "[DEBUG] $(date '+%H:%M:%S') $*"; }
fi

# ---------------------------------------------------------------------------
# Config path
# ---------------------------------------------------------------------------
readonly SNAPVAL_CONFIG="${SNAPVAL_CONFIG:-${_SNAPVAL_REPO_DIR}/configs/snapshots.json}"

# ---------------------------------------------------------------------------
# Cross-platform helpers
# ---------------------------------------------------------------------------

# _snapval_file_size <path>  → bytes (single file)
_snapval_file_size() {
  local path="$1"
  if command -v stat &>/dev/null && stat -f%z "$path" &>/dev/null 2>&1; then
    # macOS/BSD
    stat -f%z "$path" 2>/dev/null || echo "0"
  else
    # Linux
    stat -c%s "$path" 2>/dev/null || echo "0"
  fi
}

# _snapval_dir_size <path>  → bytes (recursive directory size)
_snapval_dir_size() {
  local path="$1"
  du -sb "$path" 2>/dev/null | cut -f1 || echo "0"
}

# ---------------------------------------------------------------------------
# Core detection functions
# ---------------------------------------------------------------------------

# snapshot_detect_engine <chaindata_path>
# Prints: "leveldb" | "pebble" | "unknown"
snapshot_detect_engine() {
  local chaindata_path="$1"
  local sst_count=0
  local ldb_count=0

  if [[ ! -d "$chaindata_path" ]]; then
    echo "unknown"
    return 0
  fi

  sst_count=$(find "$chaindata_path" -maxdepth 1 -name '*.sst' -type f 2>/dev/null | wc -l | tr -d ' ')
  ldb_count=$(find "$chaindata_path" -maxdepth 1 -name '*.ldb' -type f 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$sst_count" -gt 0 ]]; then
    echo "pebble"
  elif [[ "$ldb_count" -gt 0 ]]; then
    echo "leveldb"
  else
    echo "unknown"
  fi
}

# snapshot_count_files <chaindata_path>
# Prints: integer count of .sst + .ldb files (excludes ancient/)
snapshot_count_files() {
  local chaindata_path="$1"
  local count=0

  if [[ ! -d "$chaindata_path" ]]; then
    echo "0"
    return 0
  fi

  count=$(find "$chaindata_path" -maxdepth 1 \( -name '*.sst' -o -name '*.ldb' \) -type f 2>/dev/null | wc -l | tr -d ' ')
  echo "$count"
}

# snapshot_get_size <chaindata_path>
# Prints: size in bytes
snapshot_get_size() {
  local chaindata_path="$1"
  if [[ ! -d "$chaindata_path" ]]; then
    echo "0"
    return 0
  fi
  _snapval_dir_size "$chaindata_path"
}

# snapshot_detect_ancient <chaindata_path>
# Prints: JSON {"headers":N,"bodies":N,"receipts":N}
snapshot_detect_ancient() {
  local chaindata_path="$1"
  local ancient_path="$chaindata_path/ancient"
  local headers=0
  local bodies=0
  local receipts=0

  if [[ -d "$ancient_path/headers" ]]; then
    headers=$(find "$ancient_path/headers" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [[ -d "$ancient_path/bodies" ]]; then
    bodies=$(find "$ancient_path/bodies" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [[ -d "$ancient_path/receipts" ]]; then
    receipts=$(find "$ancient_path/receipts" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
  fi

  printf '{"headers":%s,"bodies":%s,"receipts":%s}\n' "$headers" "$bodies" "$receipts"
}

# ---------------------------------------------------------------------------
# Heuristic checks (no external tools needed beyond jq for thresholds)
# ---------------------------------------------------------------------------

# snapshot_check_layout <datadir>
# Returns: 0 if layout OK, 1 otherwise
# Sets:    SNAPSHOT_SUBDIR (exported to caller)
snapshot_check_layout() {
  local datadir="$1"
  local subdir=""

  if [[ -z "${datadir}" ]]; then
    log_error "datadir is required"
    return 1
  fi

  if ! [[ -d "$datadir" ]]; then
    log_error "datadir not found: $datadir"
    return 1
  fi

  if command -v find_chaindata_dir &>/dev/null; then
    subdir=$(find_chaindata_dir "$datadir" 0)
  else
    # Fallback inline detection
    if [[ -d "$datadir/geth/chaindata" ]]; then
      subdir="geth"
    elif [[ -d "$datadir/XDC/chaindata" ]]; then
      subdir="XDC"
    elif [[ -d "$datadir/xdcchain/chaindata" ]]; then
      subdir="xdcchain"
    elif [[ -d "$datadir/chaindata" ]]; then
      subdir=""
    else
      log_error "No chaindata layout detected in $datadir"
      return 1
    fi
  fi

  SNAPSHOT_SUBDIR="$subdir"
  log_debug "Detected layout: ${subdir:-(direct)}/chaindata"
  return 0
}

# snapshot_check_min_files <chaindata_path> <network> <type>
# Returns: 0 if file count meets threshold
snapshot_check_min_files() {
  local chaindata_path="$1"
  local network="$2"
  local type="$3"
  local count=0
  local min_files=0

  snapshot_load_thresholds "$network" "$type" || return 1
  count=$(snapshot_count_files "$chaindata_path")

  min_files="${MIN_FILES:-0}"
  if [[ "$count" -lt "$min_files" ]]; then
    log_error "File count $count < minimum $min_files"
    return 1
  fi

  log_debug "File count OK: $count >= $min_files"
  return 0
}

# snapshot_check_min_size <chaindata_path> <network> <type>
# Returns: 0 if size meets threshold
snapshot_check_min_size() {
  local chaindata_path="$1"
  local network="$2"
  local type="$3"
  local size=0
  local min_size=0

  snapshot_load_thresholds "$network" "$type" || return 1
  size=$(snapshot_get_size "$chaindata_path")

  min_size="${MIN_SIZE_BYTES:-0}"
  if [[ "$size" -lt "$min_size" ]]; then
    local size_human=""
    local min_human=""
    size_human=$(numfmt --to=iec-i "$size" 2>/dev/null || echo "${size}B")
    min_human=$(numfmt --to=iec-i "$min_size" 2>/dev/null || echo "${min_size}B")
    log_error "Chaindata size $size_human < minimum $min_human"
    return 1
  fi

  log_debug "Size OK: $size >= $min_size"
  return 0
}

# snapshot_check_ancient_integrity <chaindata_path>
# Returns: 0 if ancient store has required segments
snapshot_check_ancient_integrity() {
  local chaindata_path="$1"
  local ancient_path="$chaindata_path/ancient"
  local missing=()

  if [[ ! -d "$ancient_path" ]]; then
    log_error "Ancient store missing: $ancient_path"
    return 1
  fi

  local subdir=""
  for subdir in headers bodies receipts; do
    if [[ ! -d "$ancient_path/$subdir" ]]; then
      missing+=("$subdir")
    elif [[ -z "$(ls -A "$ancient_path/$subdir" 2>/dev/null)" ]]; then
      missing+=("$subdir (empty)")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Ancient store incomplete: ${missing[*]}"
    return 1
  fi

  log_debug "Ancient store integrity OK"
  return 0
}

# snapshot_check_state_cache <datadir>
# Returns: 0 always (warn only)
snapshot_check_state_cache() {
  local datadir="$1"
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
    log_debug "State root cache found"
  else
    log_warn "xdc-state-root-cache.csv missing — cold recovery may be slower"
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Deep checks (require optional tools)
# ---------------------------------------------------------------------------

# snapshot_estimate_block_height <chaindata_path>
# Prints: estimated block height (integer)
snapshot_estimate_block_height() {
  local chaindata_path="$1"
  local ancient_path="$chaindata_path/ancient"
  local height=0

  # Try to estimate from ancient bodies segment count.
  # Geth ancient files are named by starting block number in hex.
  # Each file holds up to 8192 blocks.
  local max_hex=""
  if [[ -d "$ancient_path/bodies" ]]; then
    max_hex=$(find "$ancient_path/bodies" -maxdepth 1 -type f 2>/dev/null | sed 's|.*/||' | sort | tail -n1)
  fi

  if [[ -n "$max_hex" ]]; then
    local max_dec=0
    max_dec=$(printf '%d' "0x$max_hex" 2>/dev/null || echo "0")
    # Add ~8191 to approximate the top of the last segment
    height=$((max_dec + 8191))
  else
    # Fallback: rough heuristic from chaindata file count
    local file_count=0
    file_count=$(snapshot_count_files "$chaindata_path")
    height=$((file_count * 2))
  fi

  echo "$height"
}

# snapshot_check_key_prefixes <chaindata_path>
# Returns: 0 if key prefixes detected (requires ldb)
snapshot_check_key_prefixes() {
  local chaindata_path="$1"
  local dump_output=""

  if ! command -v ldb &>/dev/null; then
    log_debug "ldb not available, skipping key prefix check"
    return 0
  fi

  if [[ ! -d "$chaindata_path" ]]; then
    log_error "Chaindata path not found: $chaindata_path"
    return 1
  fi

  local sample_file=""
  sample_file=$(find "$chaindata_path" -maxdepth 1 \( -name '*.sst' -o -name '*.ldb' \) -type f 2>/dev/null | head -n1)

  if [[ -z "$sample_file" ]]; then
    log_error "No database files found for key prefix scan"
    return 1
  fi

  # Try various ldb command forms (rocksdb-tools vs leveldb-tools)
  if ldb dump --hex "$sample_file" >/dev/null 2>&1; then
    dump_output=$(ldb dump --hex "$sample_file" 2>/dev/null | head -n 100)
  elif ldb scan --db="$chaindata_path" --max_keys=50 >/dev/null 2>&1; then
    dump_output=$(ldb scan --db="$chaindata_path" --max_keys=50 2>/dev/null | head -n 100)
  elif ldb scan "$chaindata_path" >/dev/null 2>&1; then
    dump_output=$(ldb scan "$chaindata_path" 2>/dev/null | head -n 100)
  fi

  if [[ -z "$dump_output" ]]; then
    log_debug "Could not extract key sample from database"
    return 0
  fi

  local has_header=false
  local has_body=false
  local has_receipt=false
  # Geth key prefixes in ASCII: h=header, b=body, r=receipt, t=trie
  # We grep for the hex representation of these prefixes in the dump.
  if echo "$dump_output" | grep -qi '68'; then
    has_header=true
  fi
  if echo "$dump_output" | grep -qi '62'; then
    has_body=true
  fi
  if echo "$dump_output" | grep -qi '72'; then
    has_receipt=true
  fi

  if [[ "$has_header" == "false" && "$has_body" == "false" && "$has_receipt" == "false" ]]; then
    log_warn "No expected key prefixes found in database sample"
    return 1
  fi

  log_debug "Key prefixes detected (header=$has_header body=$has_body receipt=$has_receipt)"
  return 0
}

# snapshot_check_segment_continuity <ancient_path>
# Returns: 0 if segments are contiguous
snapshot_check_segment_continuity() {
  local ancient_path="$1"
  local fail=0

  if [[ ! -d "$ancient_path" ]]; then
    log_error "Ancient path not found: $ancient_path"
    return 1
  fi

  local subdir=""
  for subdir in headers bodies receipts; do
    local dir="$ancient_path/$subdir"
    if [[ ! -d "$dir" ]]; then
      continue
    fi

    local files=""
    files=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | sed 's|.*/||' | sort)
    if [[ -z "$files" ]]; then
      continue
    fi

    local prev_dec=-1
    local step=-1
    local f=""
    while IFS= read -r f; do
      # Convert hex filename to decimal
      local dec=0
      dec=$(printf '%d' "0x$f" 2>/dev/null || echo "")
      [[ -z "$dec" ]] && continue

      if [[ "$prev_dec" -ge 0 ]]; then
        local gap=0
        gap=$((dec - prev_dec))
        if [[ "$step" -lt 0 ]]; then
          step=$gap
        elif [[ "$gap" -ne "$step" ]]; then
          log_warn "Gap anomaly in $subdir: expected step $step, got $gap at $f"
          fail=1
        fi
      fi
      prev_dec="$dec"
    done <<< "$files"
  done

  if [[ "$fail" -eq 0 ]]; then
    log_debug "Ancient segment continuity OK"
  fi
  return "$fail"
}

# ---------------------------------------------------------------------------
# Threshold config loader
# ---------------------------------------------------------------------------

# snapshot_load_thresholds <network> <type>
# Sets exported env vars: MIN_FILES, MIN_SIZE_BYTES, MAX_STATE_GAP
# Returns: 0 if thresholds loaded
snapshot_load_thresholds() {
  local network="$1"
  local type="$2"
  local config_file="$SNAPVAL_CONFIG"

  if [[ ! -f "$config_file" ]]; then
    log_error "Snapshot config not found: $config_file"
    return 1
  fi

  if ! command -v jq &>/dev/null; then
    log_error "jq is required for threshold loading"
    return 1
  fi

  local min_files=""
  local min_size=""
  local max_gap=""
  min_files=$(jq -r ".validation.thresholds.${network}.${type}.minSstLdbFiles // empty" "$config_file" 2>/dev/null)
  min_size=$(jq -r ".validation.thresholds.${network}.${type}.minChaindataSizeBytes // empty" "$config_file" 2>/dev/null)
  max_gap=$(jq -r ".validation.thresholds.${network}.${type}.maxStateBlockGap // empty" "$config_file" 2>/dev/null)

  if [[ -z "$min_files" || -z "$min_size" ]]; then
    log_warn "No thresholds defined for ${network}/${type}, using defaults"
    min_files="${min_files:-0}"
    min_size="${min_size:-0}"
    max_gap="${max_gap:-10}"
  fi

  MIN_FILES="$min_files"
  MIN_SIZE_BYTES="$min_size"
  MAX_STATE_GAP="${max_gap:-10}"

  log_debug "Thresholds loaded: MIN_FILES=$MIN_FILES MIN_SIZE_BYTES=$MIN_SIZE_BYTES MAX_STATE_GAP=$MAX_STATE_GAP"
  return 0
}
