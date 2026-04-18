#!/usr/bin/env bash
#=============================================================================
# Snapshot Validation Metrics Exporter
# Issue: #165 — XNS Snapshot Validation Integration (Phase 1.2)
#
# Reads validation log entries and exports Prometheus-compatible metrics.
# Intended to run as a cron job or systemd timer every 5-15 minutes.
#
# Usage:
#   snapshot-validation-metrics.sh [--output <prom-file>]
#
# Output:
#   Prometheus textfile collector format (node_exporter compatible)
#=============================================================================
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
readonly LOG_FILE="${XDC_STATE_DIR:-${PROJECT_ROOT}/.state}/metrics/snapshot-validation.log"
readonly OUTPUT_FILE="${1:-/var/lib/node_exporter/textfile_collector/xdc_snapshot_validation.prom}"
readonly TEMP_FILE="$(mktemp)"

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")" 2>/dev/null || true

#-----------------------------------------------------------------------------
# Helpers
#-----------------------------------------------------------------------------

_timestamp_now() {
    date +%s
}

_emit_header() {
    cat <<EOF
# HELP xdc_snapshot_validation_total Total number of snapshot validations run
# TYPE xdc_snapshot_validation_total counter
# HELP xdc_snapshot_validation_duration_seconds Duration of last validation run
# TYPE xdc_snapshot_validation_duration_seconds gauge
# HELP xdc_snapshot_state_gap_blocks Gap between block height and state height
# TYPE xdc_snapshot_state_gap_blocks gauge
# HELP xdc_snapshot_validation_last_timestamp Unix timestamp of last validation
# TYPE xdc_snapshot_validation_last_timestamp gauge
# HELP xdc_snapshot_validation_last_result Result of last validation (1=passed, 0=failed)
# TYPE xdc_snapshot_validation_last_result gauge
EOF
}

#-----------------------------------------------------------------------------
# Main
#-----------------------------------------------------------------------------

main() {
    _emit_header > "$TEMP_FILE"

    if [[ ! -f "$LOG_FILE" ]]; then
        # No data yet — emit zeros and exit cleanly
        {
            echo "xdc_snapshot_validation_total{level=\"unknown\",result=\"unknown\"} 0"
            echo "xdc_snapshot_validation_duration_seconds{level=\"unknown\"} 0"
            echo "xdc_snapshot_state_gap_blocks 0"
            echo "xdc_snapshot_validation_last_timestamp $(_timestamp_now)"
            echo "xdc_snapshot_validation_last_result{level=\"unknown\"} 0"
        } >> "$TEMP_FILE"
        mv "$TEMP_FILE" "$OUTPUT_FILE"
        exit 0
    fi

    local total_passed=0
    local total_failed=0
    local last_duration=0
    local last_level="unknown"
    local last_gap=0
    local last_timestamp=0
    local last_result=0

    # Parse JSON-lines log
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local result level duration gap ts
        result=$(echo "$line" | jq -r '.result // "unknown"' 2>/dev/null || echo "unknown")
        level=$(echo "$line" | jq -r '.level // "unknown"' 2>/dev/null || echo "unknown")
        duration=$(echo "$line" | jq -r '.duration_ms // 0' 2>/dev/null || echo "0")
        gap=$(echo "$line" | jq -r '.state_gap // 0' 2>/dev/null || echo "0")
        ts=$(echo "$line" | jq -r '.timestamp // 0' 2>/dev/null || echo "0")

        # Convert ms to seconds
        duration=$(awk "BEGIN {printf \"%.3f\", $duration/1000}")

        # Counters
        if [[ "$result" == "passed" ]]; then
            total_passed=$((total_passed + 1))
            last_result=1
        elif [[ "$result" == "failed" ]]; then
            total_failed=$((total_failed + 1))
            last_result=0
        fi

        # Track most recent entry
        if [[ "$ts" -gt "$last_timestamp" ]]; then
            last_timestamp="$ts"
            last_duration="$duration"
            last_level="$level"
            last_gap="$gap"
        fi
    done < "$LOG_FILE"

    # Emit metrics
    {
        echo "xdc_snapshot_validation_total{level=\"quick\",result=\"passed\"} ${total_passed}"
        echo "xdc_snapshot_validation_total{level=\"quick\",result=\"failed\"} ${total_failed}"
        echo "xdc_snapshot_validation_duration_seconds{level=\"${last_level}\"} ${last_duration}"
        echo "xdc_snapshot_state_gap_blocks ${last_gap}"
        echo "xdc_snapshot_validation_last_timestamp ${last_timestamp}"
        echo "xdc_snapshot_validation_last_result{level=\"${last_level}\"} ${last_result}"
    } >> "$TEMP_FILE"

    # Atomic write
    mv "$TEMP_FILE" "$OUTPUT_FILE"
}

# Handle --output flag
if [[ "${1:-}" == "--output" && -n "${2:-}" ]]; then
    OUTPUT_FILE="$2"
    shift 2
fi

main "$@"
