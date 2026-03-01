#!/bin/bash
#===============================================================================
# Unified Logging Library for XDC Node Setup
# Provides consistent, structured logging across all scripts
# Supports: JSON output, log levels, colors, file logging
#===============================================================================

# Prevent multiple sourcing
[[ -n "${XDC_LOGGING_SOURCED:-}" ]] && return 0
XDC_LOGGING_SOURCED=1

# Source utils for color support
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh" 2>/dev/null || true

#==============================================================================
# Configuration
#==============================================================================
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FORMAT="${LOG_FORMAT:-text}"  # text|json
LOG_FILE="${LOG_FILE:-}"
LOG_COMPONENT="${LOG_COMPONENT:-xdc-node}"

#==============================================================================
# Log Level Constants
#==============================================================================
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_FATAL=4

#==============================================================================
# Convert log level string to number
#==============================================================================
log_level_to_number() {
    case "$(echo "$1" | tr '[:lower:]' '[:upper:]')" in
        DEBUG) echo $LOG_LEVEL_DEBUG ;;
        INFO)  echo $LOG_LEVEL_INFO ;;
        WARN|WARNING)  echo $LOG_LEVEL_WARN ;;
        ERROR) echo $LOG_LEVEL_ERROR ;;
        FATAL) echo $LOG_LEVEL_FATAL ;;
        *) echo $LOG_LEVEL_INFO ;;
    esac
}

#==============================================================================
# Core logging function
#==============================================================================
_log() {
    local level="$1"
    local message="$2"
    local metadata="${3:-}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Check if we should log this level
    local current_level
    local message_level
    current_level=$(log_level_to_number "$LOG_LEVEL")
    message_level=$(log_level_to_number "$level")
    
    if [[ $message_level -lt $current_level ]]; then
        return 0
    fi
    
    # Format output based on LOG_FORMAT
    local output
    if [[ "$LOG_FORMAT" == "json" ]]; then
        # JSON output
        local json_meta="${metadata:-{}}"
        [[ "$json_meta" != "{}"* && "$json_meta" != "["* ]] && json_meta="{}"
        
        output=$(cat <<EOF
{"timestamp":"$timestamp","level":"$level","component":"$LOG_COMPONENT","message":"$message","metadata":$json_meta}
EOF
)
    else
        # Text output with colors
        local color_code=""
        local icon=""
        case "$level" in
            DEBUG)
                color_code="${CYAN}"
                icon="🔍"
                ;;
            INFO)
                color_code="${BLUE}"
                icon="ℹ"
                ;;
            WARN|WARNING)
                color_code="${YELLOW}"
                icon="⚠"
                ;;
            ERROR)
                color_code="${RED}"
                icon="✗"
                ;;
            FATAL)
                color_code="${MAGENTA}${BOLD}"
                icon="💀"
                ;;
        esac
        
        output="${color_code}${icon} [${level}]${NC} ${message}"
        [[ -n "$metadata" && "$metadata" != "{}" ]] && output="${output} ${CYAN}${metadata}${NC}"
    fi
    
    # Output to stdout/stderr
    if [[ "$level" == "ERROR" || "$level" == "FATAL" ]]; then
        echo -e "$output" >&2
    else
        echo -e "$output"
    fi
    
    # Log to file if configured
    if [[ -n "$LOG_FILE" ]]; then
        if [[ "$LOG_FORMAT" == "json" ]]; then
            echo "$output" >> "$LOG_FILE"
        else
            # Strip colors for file output
            echo "[$timestamp] [$level] $message $metadata" >> "$LOG_FILE"
        fi
    fi
    
    # Exit on FATAL
    if [[ "$level" == "FATAL" ]]; then
        exit 1
    fi
}

#==============================================================================
# Public Logging Functions - Modern (log_*)
#==============================================================================
log_debug() {
    _log "DEBUG" "$1" "${2:-}"
}

log_info() {
    _log "INFO" "$1" "${2:-}"
}

log_warn() {
    _log "WARN" "$1" "${2:-}"
}

log_error() {
    _log "ERROR" "$1" "${2:-}"
}

log_fatal() {
    _log "FATAL" "$1" "${2:-}"
}

#==============================================================================
# Public Logging Functions - Legacy Compatibility (info/warn/error)
#==============================================================================
info() {
    log_info "$1" "${2:-}"
}

warn() {
    log_warn "$1" "${2:-}"
}

error() {
    log_error "$1" "${2:-}"
}

debug() {
    log_debug "$1" "${2:-}"
}

fatal() {
    log_fatal "$1" "${2:-}"
}

#==============================================================================
# Success/Failure helpers
#==============================================================================
success() {
    echo -e "${GREEN}✓${NC} $1"
}

failure() {
    echo -e "${RED}✗${NC} $1" >&2
}

#==============================================================================
# Section headers
#==============================================================================
log_section() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

#==============================================================================
# Progress indicators
#==============================================================================
log_step() {
    local step_num="$1"
    local step_total="$2"
    local step_name="$3"
    echo -e "${CYAN}[${step_num}/${step_total}]${NC} ${step_name}"
}

#==============================================================================
# Spinner for long-running tasks
#==============================================================================
spinner() {
    local pid=$1
    local message="${2:-Processing}"
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " ${CYAN}[%c]${NC} %s\r" "$spinstr" "$message"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "    \r"  # Clear spinner line
}

#==============================================================================
# Confirmation prompts
#==============================================================================
confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"
    
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    read -r -p "$prompt" response
    response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$default" == "y" ]]; then
        [[ "$response" != "n" ]]
    else
        [[ "$response" == "y" ]]
    fi
}

#==============================================================================
# Export functions for use in other scripts
#==============================================================================
export -f _log log_debug log_info log_warn log_error log_fatal 2>/dev/null || true
export -f info warn error debug fatal success failure 2>/dev/null || true
export -f log_section log_step spinner confirm 2>/dev/null || true
