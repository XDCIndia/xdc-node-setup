#!/bin/bash
# XDC Self-Healing Monitor
# Issue #490: Container-Native Health Checks & Self-Healing

set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly CONTAINER_NAME="${CONTAINER_NAME:-xdc-node}"
readonly MAX_RESTARTS="${MAX_RESTARTS:-5}"
readonly RESTART_WINDOW="${RESTART_WINDOW:-3600}"  # 1 hour
readonly HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-30}"

# Restart tracking
RESTART_LOG="${RESTART_LOG:-/tmp/xdc-restarts.log}"

# Logging
log() { echo "[$(date -Iseconds)] $*"; }
info() { log "INFO: $*"; }
warn() { log "WARN: $*" &&2; }
error() { log "ERROR: $*" &&2; }

# Initialize restart log
init_restart_log() {
    touch "$RESTART_LOG" 2>/dev/null || RESTART_LOG="/tmp/xdc-restarts-$USER.log"
}

# Count recent restarts
count_recent_restarts() {
    local window_start
    window_start=$(date -d "@$(( $(date +%s) - RESTART_WINDOW ))" +%s 2>/dev/null || echo 0)
    
    if [[ ! -f "$RESTART_LOG" ]]; then
        echo 0
        return
    fi
    
    local count=0
    while IFS= read -r line; do
        local timestamp
        timestamp=$(echo "$line" | awk '{print $1}')
        if [[ "$timestamp" -gt "$window_start" ]] 2>/dev/null; then
            count=$((count + 1))
        fi
    done < "$RESTART_LOG"
    
    echo "$count"
}

# Log a restart
log_restart() {
    local reason=$1
    echo "$(date +%s) $(date -Iseconds) $reason" >> "$RESTART_LOG"
}

# Check if Docker is available
check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker not found"
        return 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        error "Cannot connect to Docker daemon"
        return 1
    fi
    
    return 0
}

# Get container status
get_container_status() {
    docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "not_found"
}

# Get container health
get_container_health() {
    docker inspect -f '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "none"
}

# Check container health status
check_health() {
    local status
    status=$(get_container_status)
    
    if [[ "$status" == "not_found" ]]; then
        error "Container $CONTAINER_NAME not found"
        return 1
    fi
    
    if [[ "$status" != "running" ]]; then
        error "Container $CONTAINER_NAME is not running (status: $status)"
        return 1
    fi
    
    local health
    health=$(get_container_health)
    
    # If health check is configured, verify it
    if [[ "$health" != "none" ]] && [[ "$health" != "healthy" ]]; then
        warn "Container health status: $health"
        return 1
    fi
    
    return 0
}

# Restart container
restart_container() {
    local reason=$1
    
    info "Restarting container $CONTAINER_NAME (reason: $reason)"
    
    # Log the restart
    log_restart "$reason"
    
    # Perform restart
    if docker restart "$CONTAINER_NAME" >/dev/null 2>&1; then
        info "Container restarted successfully"
        
        # Wait for container to be healthy
        local attempts=0
        local max_attempts=30
        
        while [[ $attempts -lt $max_attempts ]]; do
            sleep 10
            
            if check_health; then
                info "Container is healthy after restart"
                return 0
            fi
            
            attempts=$((attempts + 1))
            info "Waiting for container to be healthy... ($attempts/$max_attempts)"
        done
        
        error "Container did not become healthy after restart"
        return 1
    else
        error "Failed to restart container"
        return 1
    fi
}

# Main healing loop
heal_loop() {
    info "Starting XDC Self-Healing Monitor"
    info "Container: $CONTAINER_NAME"
    info "Max restarts: $MAX_RESTARTS per $RESTART_WINDOW seconds"
    info "Health check interval: ${HEALTH_CHECK_INTERVAL}s"
    
    init_restart_log
    
    while true; do
        # Check recent restart count
        local recent_restarts
        recent_restarts=$(count_recent_restarts)
        
        if [[ "$recent_restarts" -ge "$MAX_RESTARTS" ]]; then
            error "CRITICAL: Maximum restart count ($MAX_RESTARTS) reached within window"
            error "Self-healing suspended to prevent restart loop"
            
            # Send alert (if configured)
            if command -v skynet-alert >/dev/null 2>&1; then
                skynet-alert --severity critical \
                    --message "XDC container restart loop detected" \
                    --component "$CONTAINER_NAME"
            fi
            
            # Sleep longer before checking again
            sleep 300
            continue
        fi
        
        # Check container health
        if ! check_health; then
            warn "Health check failed, attempting restart ($recent_restarts/$MAX_RESTARTS recent)"
            
            if ! restart_container "health_check_failed"; then
                error "Restart failed, will retry"
            fi
        fi
        
        sleep "$HEALTH_CHECK_INTERVAL"
    done
}

# One-time health check
one_time_check() {
    if ! check_docker; then
        exit 1
    fi
    
    if check_health; then
        info "Container $CONTAINER_NAME is healthy"
        exit 0
    else
        error "Container $CONTAINER_NAME is unhealthy"
        exit 1
    fi
}

# Show status
show_status() {
    if ! check_docker; then
        exit 1
    fi
    
    local status
    status=$(get_container_status)
    local health
    health=$(get_container_health)
    local recent_restarts
    recent_restarts=$(count_recent_restarts)
    
    echo "=== XDC Self-Healing Monitor Status ==="
    echo "Container: $CONTAINER_NAME"
    echo "Status: $status"
    echo "Health: $health"
    echo "Recent restarts (last $RESTART_WINDOW s): $recent_restarts/$MAX_RESTARTS"
    echo ""
    echo "Configuration:"
    echo "  Max restarts: $MAX_RESTARTS"
    echo "  Restart window: $RESTART_WINDOW seconds"
    echo "  Health check interval: $HEALTH_CHECK_INTERVAL seconds"
    
    if [[ -f "$RESTART_LOG" ]] && [[ -s "$RESTART_LOG" ]]; then
        echo ""
        echo "Recent restart history:"
        tail -5 "$RESTART_LOG" | while read -r line; do
            local timestamp reason
            timestamp=$(echo "$line" | awk '{print $2}')
            reason=$(echo "$line" | cut -d' ' -f3-)
            echo "  $timestamp - $reason"
        done
    fi
}

# CLI interface
case "${1:-}" in
    daemon|heal)
        if ! check_docker; then
            exit 1
        fi
        heal_loop
        ;;
    check)
        one_time_check
        ;;
    status)
        show_status
        ;;
    *)
        echo "XDC Self-Healing Monitor v$SCRIPT_VERSION"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  daemon     Run continuous self-healing monitor"
        echo "  check      One-time health check"
        echo "  status     Show current status"
        echo ""
        echo "Environment Variables:"
        echo "  CONTAINER_NAME          Container to monitor (default: xdc-node)"
        echo "  MAX_RESTARTS            Max restarts per window (default: 5)"
        echo "  RESTART_WINDOW          Window in seconds (default: 3600)"
        echo "  HEALTH_CHECK_INTERVAL   Check interval in seconds (default: 30)"
        exit 1
        ;;
esac
