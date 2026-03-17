#!/usr/bin/env bash
#==============================================================================
# JSON Structured Logging (Issue #329)
# Drop-in replacement for echo-based logging
#==============================================================================

JSON_LOG_FILE="${JSON_LOG_FILE:-/var/log/xdc-node/node.json.log}"
JSON_LOG_LEVEL="${JSON_LOG_LEVEL:-info}"

# Ensure log directory exists
mkdir -p "$(dirname "$JSON_LOG_FILE")" 2>/dev/null || true

_json_log() {
    local level="$1"
    local message="$2"
    local extra="${3:-}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    local json="{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":\"$message\""
    
    # Add extra fields if provided
    if [[ -n "$extra" ]]; then
        json="$json,$extra"
    fi
    
    # Add hostname and PID
    json="$json,\"hostname\":\"$(hostname)\",\"pid\":$$}"
    
    # Write to file and stdout
    echo "$json" >> "$JSON_LOG_FILE" 2>/dev/null || true
    
    # Also output to stdout in human-readable format
    case "$level" in
        error) echo -e "\033[0;31m[$level]\033[0m $message" >&2 ;;
        warn)  echo -e "\033[1;33m[$level]\033[0m $message" ;;
        info)  echo -e "\033[0;32m[$level]\033[0m $message" ;;
        debug) [[ "$JSON_LOG_LEVEL" == "debug" ]] && echo -e "\033[0;34m[$level]\033[0m $message" ;;
    esac
}

jlog_info()  { _json_log "info" "$1" "${2:-}"; }
jlog_warn()  { _json_log "warn" "$1" "${2:-}"; }
jlog_error() { _json_log "error" "$1" "${2:-}"; }
jlog_debug() { _json_log "debug" "$1" "${2:-}"; }

# Log node metrics in structured format
jlog_metrics() {
    local block="$1"
    local peers="$2"
    local client="${3:-unknown}"
    _json_log "info" "node_metrics" "\"block_height\":$block,\"peer_count\":$peers,\"client\":\"$client\""
}

# Log sync progress
jlog_sync() {
    local block="$1"
    local target="$2"
    local rate="$3"
    local eta="$4"
    _json_log "info" "sync_progress" "\"current_block\":$block,\"target_block\":$target,\"blocks_per_sec\":$rate,\"eta_seconds\":$eta"
}
