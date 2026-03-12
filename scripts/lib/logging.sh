#!/usr/bin/env bash
#===============================================================================
# XDC Node Setup - Shared Logging Library
# Centralizes logging functions to avoid duplication across scripts
#
# Usage:
#   source "${SCRIPT_DIR}/../lib/logging.sh"
#   log "Starting operation..."
#   warn "This might take a while"
#   error "Something went wrong"
#
#===============================================================================

# Color codes
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

# Timestamp format
LOG_TIMESTAMP_FORMAT="${LOG_TIMESTAMP_FORMAT:-%Y-%m-%d %H:%M:%S}"

# Log levels
LOG_LEVEL_ERROR=0
LOG_LEVEL_WARN=1
LOG_LEVEL_INFO=2
LOG_LEVEL_DEBUG=3

# Default log level
CURRENT_LOG_LEVEL="${CURRENT_LOG_LEVEL:-$LOG_LEVEL_INFO}"

#-------------------------------------------------------------------------------
# Core Logging Functions
#-------------------------------------------------------------------------------

# Log a timestamped message to stderr
log() {
    echo "[$(date "+${LOG_TIMESTAMP_FORMAT}")] $1" >&2
}

# Log an info message with green checkmark
info() {
    echo -e "${GREEN}✓${NC} $1"
}

# Log a warning message with yellow warning symbol
warn() {
    echo -e "${YELLOW}⚠${NC} $1" >&2
}

# Log an error message with red X
error() {
    echo -e "${RED}✗${NC} $1" >&2
}

# Log a debug message (only if DEBUG is set)
debug() {
    if [[ "${DEBUG:-}" == "1" || "${VERBOSE:-}" == "1" ]]; then
        echo -e "${CYAN}ℹ${NC} [DEBUG] $1" >&2
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

# Log a fatal error and exit
die() {
    error "$1"
    exit "${2:-1}"
}

#-------------------------------------------------------------------------------
# Formatted Logging Functions
#-------------------------------------------------------------------------------

# Log with timestamp
log_info() {
    echo "[$(date "+${LOG_TIMESTAMP_FORMAT}")] INFO: $1" >&2
}

log_warn() {
    echo "[$(date "+${LOG_TIMESTAMP_FORMAT}")] WARN: $1" >&2
}

log_error() {
    echo "[$(date "+${LOG_TIMESTAMP_FORMAT}")] ERROR: $1" >&2
}

log_debug() {
    if [[ "${DEBUG:-}" == "1" || "${VERBOSE:-}" == "1" ]]; then
        echo "[$(date "+${LOG_TIMESTAMP_FORMAT}")] DEBUG: $1" >&2
    fi
}

#-------------------------------------------------------------------------------
# Visual Output Functions
#-------------------------------------------------------------------------------

# Print a banner
cprint_banner() {
    echo ""
    echo -e "${BOLD}$1${NC}"
    echo ""
}

# Print success message
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Print warning message  
print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Print error message
print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Print info message
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Print section header
print_section() {
    echo ""
    echo -e "${BOLD}${BLUE}▸ $1${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# Progress Indicators
#-------------------------------------------------------------------------------

# Show a spinner while a command runs
show_spinner() {
    local pid=$1
    local msg="${2:-Processing...}"
    local delay=0.1
    local spinstr='|/-\\'
    
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c] %s" "$spinstr" "$msg"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\r"
    done
    printf "    \r"
}

# Show progress bar
show_progress() {
    local current=$1
    local total=$2
    local msg="${3:-Progress}"
    local width=40
    
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))
    
    printf "\r%s: [" "$msg"
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%%" "$percentage"
}

#-------------------------------------------------------------------------------
# Log File Operations
#-------------------------------------------------------------------------------

# Initialize log file
init_log_file() {
    local log_file="$1"
    local log_dir
    log_dir=$(dirname "$log_file")
    
    mkdir -p "$log_dir"
    touch "$log_file"
    
    echo "=== Log started at $(date) ===" > "$log_file"
}

# Write to log file
log_to_file() {
    local log_file="$1"
    local message="$2"
    local level="${3:-INFO}"
    
    echo "[$(date "+${LOG_TIMESTAMP_FORMAT}")] [$level] $message" >> "$log_file"
}

# Rotate log file if it exceeds size limit
rotate_log() {
    local log_file="$1"
    local max_size="${2:-10485760}" # 10MB default
    local max_files="${3:-5}"
    
    if [[ -f "$log_file" ]]; then
        local size
        size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)
        
        if [[ $size -gt $max_size ]]; then
            # Rotate existing backups
            for ((i=max_files-1; i>=1; i--)); do
                if [[ -f "${log_file}.$i" ]]; then
                    mv "${log_file}.$i" "${log_file}.$((i+1))"
                fi
            done
            
            # Rotate current log
            mv "$log_file" "${log_file}.1"
            touch "$log_file"
        fi
    fi
}
