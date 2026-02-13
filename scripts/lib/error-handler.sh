#!/bin/bash
#==============================================================================
# Error Handling and Cleanup Library for XDC Node Setup
# Provides: Trap handlers, cleanup functions, error reporting
#==============================================================================

set -euo pipefail

# Error codes
readonly E_SUCCESS=0
readonly E_GENERAL=1
readonly E_INVALID_ARGS=2
readonly E_FILE_NOT_FOUND=3
readonly E_PERMISSION_DENIED=4
readonly E_COMMAND_FAILED=5
readonly E_NETWORK_ERROR=6
readonly E_VALIDATION_FAILED=7
readonly E_DEPENDENCY_MISSING=8
readonly E_TIMEOUT=9
readonly E_INTERRUPTED=130

# State tracking
declare -a CLEANUP_FUNCTIONS=()
declare -a TEMP_FILES=()
declare -a TEMP_DIRS=()
declare -i SCRIPT_EXIT_CODE=$E_SUCCESS
SCRIPT_NAME="$(basename "$0")"
SCRIPT_PID=$$

#==============================================================================
# Trap Handlers
#==============================================================================

# Main error handler
_error_handler() {
    local exit_code=$?
    local line_no=$1
    
    # Don't handle errors during cleanup
    if [[ "${CLEANUP_IN_PROGRESS:-false}" == "true" ]]; then
        exit $exit_code
    fi
    
    SCRIPT_EXIT_CODE=$exit_code
    
    # Log error details
    _log_error "Script failed with exit code $exit_code at line $line_no"
    _log_error "Command: $BASH_COMMAND"
    _log_error "Working directory: $PWD"
    
    # Perform cleanup
    _perform_cleanup
    
    exit $exit_code
}

# Signal handler for interrupts
_interrupt_handler() {
    local signal=$1
    
    echo ""
    _log_warn "Received signal $signal, shutting down gracefully..."
    
    SCRIPT_EXIT_CODE=$E_INTERRUPTED
    
    # Perform cleanup
    _perform_cleanup
    
    exit $E_INTERRUPTED
}

# Exit handler - always runs
_exit_handler() {
    local exit_code=$?
    
    # Only run if not already cleaning up
    if [[ "${CLEANUP_IN_PROGRESS:-false}" != "true" ]]; then
        _perform_cleanup
    fi
    
    # Log script completion
    if [[ $exit_code -eq $E_SUCCESS ]]; then
        _log_info "Script completed successfully"
    else
        _log_error "Script exited with code $exit_code"
    fi
    
    exit $exit_code
}

#==============================================================================
# Cleanup Functions
#==============================================================================

# Register a function to be called during cleanup
register_cleanup_function() {
    local func_name=$1
    CLEANUP_FUNCTIONS+=("$func_name")
}

# Register a temporary file for automatic removal
register_temp_file() {
    local file_path=$1
    TEMP_FILES+=("$file_path")
}

# Register a temporary directory for automatic removal
register_temp_dir() {
    local dir_path=$1
    TEMP_DIRS+=("$dir_path")
}

# Create a temporary file that will be automatically cleaned up
create_temp_file() {
    local prefix="${1:-${SCRIPT_NAME}}"
    local temp_file
    
    temp_file=$(mktemp -t "${prefix}.XXXXXX")
    register_temp_file "$temp_file"
    
    echo "$temp_file"
}

# Create a temporary directory that will be automatically cleaned up
create_temp_dir() {
    local prefix="${1:-${SCRIPT_NAME}}"
    local temp_dir
    
    temp_dir=$(mktemp -d -t "${prefix}.XXXXXX")
    register_temp_dir "$temp_dir"
    
    echo "$temp_dir"
}

# Perform all registered cleanup
_perform_cleanup() {
    # Prevent recursive cleanup
    if [[ "${CLEANUP_IN_PROGRESS:-false}" == "true" ]]; then
        return
    fi
    CLEANUP_IN_PROGRESS=true
    
    _log_info "Performing cleanup..."
    
    # Run registered cleanup functions (in reverse order)
    for ((i=${#CLEANUP_FUNCTIONS[@]}-1; i>=0; i--)); do
        local func="${CLEANUP_FUNCTIONS[$i]}"
        _log_debug "Running cleanup function: $func"
        $func 2>/dev/null || true
    done
    
    # Remove temporary files
    for file in "${TEMP_FILES[@]:-}"; do
        if [[ -n "$file" && -f "$file" ]]; then
            _log_debug "Removing temp file: $file"
            rm -f "$file" 2>/dev/null || true
        fi
    done
    
    # Remove temporary directories
    for dir in "${TEMP_DIRS[@]:-}"; do
        if [[ -n "$dir" && -d "$dir" ]]; then
            _log_debug "Removing temp dir: $dir"
            rm -rf "$dir" 2>/dev/null || true
        fi
    done
    
    # Release locks
    if [[ -n "${LOCK_FILE:-}" && -f "$LOCK_FILE" ]]; then
        _log_debug "Releasing lock: $LOCK_FILE"
        rm -f "$LOCK_FILE" 2>/dev/null || true
    fi
    
    CLEANUP_IN_PROGRESS=false
}

#==============================================================================
# Logging Helpers
#==============================================================================

_log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" >&2
}

_log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" >&2
}

_log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

_log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*" >&2
    fi
}

#==============================================================================
# Initialization
#==============================================================================

# Initialize error handling
init_error_handling() {
    # Set up error handler with line number
    trap '_error_handler $LINENO' ERR
    
    # Set up signal handlers
    trap '_interrupt_handler INT' INT
    trap '_interrupt_handler TERM' TERM
    trap '_interrupt_handler HUP' HUP
    
    # Set up exit handler
    trap '_exit_handler' EXIT
    
    _log_debug "Error handling initialized"
}

#==============================================================================
# Lock Management
#==============================================================================

# Acquire a lock file
acquire_lock() {
    local lock_file=$1
    local timeout=${2:-30}
    LOCK_FILE="$lock_file"
    
    # Check if lock exists and is valid
    if [[ -f "$lock_file" ]]; then
        local lock_pid
        lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")
        
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            _log_error "Another instance is running (PID: $lock_pid)"
            return $E_GENERAL
        fi
        
        # Stale lock, remove it
        rm -f "$lock_file"
    fi
    
    # Create lock
    echo $$ > "$lock_file"
    
    _log_debug "Lock acquired: $lock_file"
}

# Release lock (called automatically during cleanup)
release_lock() {
    if [[ -n "${LOCK_FILE:-}" && -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
        _log_debug "Lock released: $LOCK_FILE"
    fi
}

#==============================================================================
# Retry Logic
#==============================================================================

# Retry a command with exponential backoff
retry_with_backoff() {
    local max_attempts=${1:-3}
    local initial_delay=${2:-1}
    shift 2
    
    local attempt=1
    local delay=$initial_delay
    
    while [[ $attempt -le $max_attempts ]]; do
        if "$@"; then
            return $E_SUCCESS
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            _log_warn "Command failed, retrying in ${delay}s (attempt $attempt/$max_attempts)..."
            sleep $delay
            delay=$((delay * 2))
        fi
        
        ((attempt++))
    done
    
    _log_error "Command failed after $max_attempts attempts"
    return $E_TIMEOUT
}

#==============================================================================
# Error Reporting
#==============================================================================

# Generate an error report
generate_error_report() {
    local report_file=$1
    
    cat > "$report_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "script": "$SCRIPT_NAME",
  "pid": $SCRIPT_PID,
  "exit_code": $SCRIPT_EXIT_CODE,
  "working_directory": "$PWD",
  "environment": {
    "user": "$(whoami)",
    "hostname": "$(hostname)",
    "shell": "$SHELL"
  },
  "cleanup_performed": ${CLEANUP_IN_PROGRESS:-false}
}
EOF
}

#==============================================================================
# Export Functions
#==============================================================================

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Export all public functions
    export -f init_error_handling
    export -f register_cleanup_function
    export -f register_temp_file
    export -f register_temp_dir
    export -f create_temp_file
    export -f create_temp_dir
    export -f acquire_lock
    export -f release_lock
    export -f retry_with_backoff
    export -f generate_error_report
    
    # Export error codes
    export E_SUCCESS
    export E_GENERAL
    export E_INVALID_ARGS
    export E_FILE_NOT_FOUND
    export E_PERMISSION_DENIED
    export E_COMMAND_FAILED
    export E_NETWORK_ERROR
    export E_VALIDATION_FAILED
    export E_DEPENDENCY_MISSING
    export E_TIMEOUT
    export E_INTERRUPTED
fi