#!/usr/bin/env bash

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }
#==============================================================================
#==============================================================================
# XDC Node Log Rotation Script
# Compress daily logs, move to oldlogs/, and delete logs older than retention period
# Compatible with: bash 3.2+ (macOS, Linux)
#
# NOTE: Docker container logs are handled separately by Docker's json-file
#       logging driver with max-size: 50m and max-file: 5 (configured in
#       docker-compose.yml). This script manages XDC node application logs
#       in {network}/xdcchain/ directory and /var/log/xdc/ for component logs.
#==============================================================================

set -euo pipefail

# Script metadata
readonly SCRIPT_VERSION="1.1.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Log retention policy (configurable via environment variable)
readonly LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-7}"

# Network auto-detection

readonly NETWORK="$(detect_network)"
readonly CHAINDATA_DIR="${PROJECT_ROOT}/${NETWORK}/xdcchain"
readonly OLDLOGS_DIR="${CHAINDATA_DIR}/oldlogs"
readonly ROTATION_LOG="${PROJECT_ROOT}/${NETWORK}/.xdc-node/log-rotation.log"

# Log directories for component logs
readonly LOG_DIR="${PROJECT_ROOT}/${NETWORK}/.xdc-node/logs"
readonly OLD_COMPONENT_LOGS_DIR="${LOG_DIR}/oldlogs"

#==============================================================================
# Logging Functions
#==============================================================================
log_message() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" | tee -a "$ROTATION_LOG" 2>/dev/null || echo "$msg"
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"
    echo "$msg" | tee -a "$ROTATION_LOG" &>2 || echo "$msg" &>2
}

#==============================================================================
# Initialization
#==============================================================================
init_directories() {
    # Create oldlogs directory for xdcchain logs if it doesn't exist
    if [[ ! -d "$OLDLOGS_DIR" ]]; then
        mkdir -p "$OLDLOGS_DIR"
        log_message "Created oldlogs directory: $OLDLOGS_DIR"
    fi
    
    # Create oldlogs directory for component logs if it doesn't exist
    if [[ ! -d "$OLD_COMPONENT_LOGS_DIR" ]]; then
        mkdir -p "$OLD_COMPONENT_LOGS_DIR"
        log_message "Created component oldlogs directory: $OLD_COMPONENT_LOGS_DIR"
    fi
    
    # Create state directory for rotation log
    local state_dir
    state_dir=$(dirname "$ROTATION_LOG")
    if [[ ! -d "$state_dir" ]]; then
        mkdir -p "$state_dir"
    fi
    
    # Ensure rotation log exists
    if [[ ! -f "$ROTATION_LOG" ]]; then
        touch "$ROTATION_LOG"
    fi
}

#==============================================================================
# Component Log Rotation Logic
#==============================================================================
rotate_component_logs() {
    log_message "Starting component log rotation for network: $NETWORK"
    log_message "Log directory: $LOG_DIR"
    
    # Check if log directory exists
    if [[ ! -d "$LOG_DIR" ]]; then
        log_message "Component log directory not found: $LOG_DIR, skipping"
        return 0
    fi
    
    local rotated_count=0
    local compressed_count=0
    local error_count=0
    
    # Define component log files to rotate
    local component_logs=("heartbeat.log" "lfg.log" "dashboard.log")
    
    for logfile_name in "${component_logs[@]}"; do
        local logfile="${LOG_DIR}/${logfile_name}"
        
        # Skip if file doesn't exist
        if [[ ! -f "$logfile" ]]; then
            continue
        fi
        
        # Skip if file is empty
        if [[ ! -s "$logfile" ]]; then
            continue
        fi
        
        # Skip if file is actively being written (less than 1 day old)
        # Use find -mtime +0 to find files modified more than 24 hours ago
        if ! find "$logfile" -mtime +0 -print 2>/dev/null | grep -q .; then
            log_message "Skipping active log file: $logfile_name"
            continue
        fi
        
        # Generate timestamp-based filename for archived log
        local file_mtime
        file_mtime=$(stat -c %Y "$logfile" 2>/dev/null || stat -f %m "$logfile" 2>/dev/null)
        local archive_date
        archive_date=$(date -d "@${file_mtime}" '+%Y-%m-%d' 2>/dev/null || date -r "${file_mtime}" '+%Y-%m-%d')
        local archive_name="${logfile_name%.log}-${archive_date}.log"
        
        # Move log to oldlogs directory
        log_message "Moving $logfile_name to oldlogs/"
        if mv "$logfile" "${OLD_COMPONENT_LOGS_DIR}/${archive_name}"; then
            rotated_count=$((rotated_count + 1))
            
            # Create new empty log file
            touch "$logfile"
            
            # Compress the moved log with gzip
            log_message "Compressing ${archive_name}"
            if gzip "${OLD_COMPONENT_LOGS_DIR}/${archive_name}"; then
                compressed_count=$((compressed_count + 1))
            else
                log_error "Failed to compress ${archive_name}"
                error_count=$((error_count + 1))
            fi
        else
            log_error "Failed to move $logfile_name"
            error_count=$((error_count + 1))
        fi
    done
    
    log_message "Component log rotation summary: $rotated_count moved, $compressed_count compressed, $error_count errors"
}

#==============================================================================
# XDC Chain Log Rotation Logic
#==============================================================================
rotate_xdcchain_logs() {
    log_message "Starting XDC chain log rotation for network: $NETWORK"
    
    # Check if chaindata directory exists
    if [[ ! -d "$CHAINDATA_DIR" ]]; then
        log_error "Chaindata directory not found: $CHAINDATA_DIR"
        return 1
    fi
    
    local rotated_count=0
    local compressed_count=0
    local error_count=0
    
    # Find all .log files in xdcchain directory (not in subdirectories)
    # Exclude nodekey and other non-log files
    while IFS= read -r -d '' logfile; do
        local filename
        filename=$(basename "$logfile")
        
        # Skip if file is nodekey or other non-log files
        if [[ "$filename" == "nodekey" ]] || [[ ! "$filename" =~ \.log$ ]]; then
            continue
        fi
        
        # Skip if file is actively being written (less than 1 day old)
        # Use find -mtime +0 to find files modified more than 24 hours ago
        if ! find "$logfile" -mtime +0 -print 2>/dev/null | grep -q .; then
            continue
        fi
        
        # Generate timestamp-based filename for archived log
        local file_mtime
        file_mtime=$(stat -c %Y "$logfile" 2>/dev/null || stat -f %m "$logfile" 2>/dev/null)
        local archive_date
        archive_date=$(date -d "@${file_mtime}" '+%Y-%m-%d' 2>/dev/null || date -r "${file_mtime}" '+%Y-%m-%d')
        local archive_name="${filename%.log}-${archive_date}.log"
        
        # Move log to oldlogs directory
        log_message "Moving $filename to oldlogs/"
        if mv "$logfile" "${OLDLOGS_DIR}/${archive_name}"; then
            rotated_count=$((rotated_count + 1))
            
            # Compress the moved log with gzip
            log_message "Compressing ${archive_name}"
            if gzip "${OLDLOGS_DIR}/${archive_name}"; then
                compressed_count=$((compressed_count + 1))
            else
                log_error "Failed to compress ${archive_name}"
                error_count=$((error_count + 1))
            fi
        else
            log_error "Failed to move $filename"
            error_count=$((error_count + 1))
        fi
        
    done < <(find "$CHAINDATA_DIR" -maxdepth 1 -type f -name "*.log" -print0 2>/dev/null)
    
    log_message "XDC chain log rotation summary: $rotated_count moved, $compressed_count compressed, $error_count errors"
}

#==============================================================================
# Cleanup Old Logs
#==============================================================================
cleanup_old_logs() {
    log_message "Cleaning up logs older than ${LOG_RETENTION_DAYS} days"
    
    local deleted_count=0
    
    # Cleanup XDC chain oldlogs
    if [[ -d "$OLDLOGS_DIR" ]]; then
        while IFS= read -r -d '' oldlog; do
            log_message "Deleting old XDC chain log: $(basename "$oldlog")"
            if rm -f "$oldlog"; then
                deleted_count=$((deleted_count + 1))
            else
                log_error "Failed to delete: $oldlog"
            fi
        done < <(find "$OLDLOGS_DIR" -type f -mtime +${LOG_RETENTION_DAYS} -print0 2>/dev/null)
    fi
    
    # Cleanup component oldlogs
    if [[ -d "$OLD_COMPONENT_LOGS_DIR" ]]; then
        while IFS= read -r -d '' oldlog; do
            log_message "Deleting old component log: $(basename "$oldlog")"
            if rm -f "$oldlog"; then
                deleted_count=$((deleted_count + 1))
            else
                log_error "Failed to delete: $oldlog"
            fi
        done < <(find "$OLD_COMPONENT_LOGS_DIR" -type f -mtime +${LOG_RETENTION_DAYS} -print0 2>/dev/null)
    fi
    
    if [[ $deleted_count -gt 0 ]]; then
        log_message "Deleted $deleted_count old log file(s)"
    else
        log_message "No logs older than ${LOG_RETENTION_DAYS} days found"
    fi
}

#==============================================================================
# Main Execution
#==============================================================================
main() {
    log_message "========================================"
    log_message "XDC Node Log Rotation v${SCRIPT_VERSION}"
    log_message "Network: $NETWORK"
    log_message "Retention: ${LOG_RETENTION_DAYS} days"
    log_message "========================================"
    
    # Initialize directories
    init_directories
    
    # Rotate component logs (heartbeat, lfg, dashboard)
    rotate_component_logs
    
    # Rotate XDC chain logs
    rotate_xdcchain_logs
    
    # Cleanup old logs
    cleanup_old_logs
    
    log_message "Log rotation completed successfully"
    log_message "========================================"
}

# Handle script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
