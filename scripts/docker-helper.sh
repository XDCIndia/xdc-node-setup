#!/bin/bash
#============================================================================
# Docker Helper Script - Safe wrapper for docker commands
# Fixes issue #553: set -euo pipefail exits on port conflicts
#============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Safe docker start - handles port conflicts gracefully
docker_safe_start() {
    local container_name="$1"
    local max_retries="${2:-3}"
    local retry_delay="${3:-5}"
    
    log_info "Starting container: $container_name"
    
    for ((i=1; i<=max_retries; i++)); do
        # Check if container exists
        if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
            # Try to start
            if docker start "$container_name" 2>/tmp/docker_error.log; then
                log_info "Container $container_name started successfully"
                return 0
            else
                local error_msg=$(cat /tmp/docker_error.log)
                
                # Handle port conflict
                if echo "$error_msg" | grep -q "port.*already allocated"; then
                    log_warn "Port conflict detected for $container_name"
                    local port=$(echo "$error_msg" | grep -oE '[0-9]+/tcp' | head -1 | tr -d '/tcp')
                    log_warn "Port $port is already in use"
                    
                    # Try to find what's using the port
                    if command -v lsof >/dev/null 2>&1; then
                        local pid=$(lsof -ti :"$port" 2>/dev/null || echo "")
                        if [ -n "$pid" ]; then
                            log_warn "Port $port is used by PID $pid"
                        fi
                    fi
                    
                    if [ $i -lt $max_retries ]; then
                        log_info "Retrying in ${retry_delay}s... (attempt $i/$max_retries)"
                        sleep "$retry_delay"
                        continue
                    fi
                fi
                
                # Handle other errors
                log_error "Failed to start $container_name: $error_msg"
                if [ $i -lt $max_retries ]; then
                    log_info "Retrying in ${retry_delay}s... (attempt $i/$max_retries)"
                    sleep "$retry_delay"
                else
                    log_error "Max retries reached for $container_name"
                    return 1
                fi
            fi
        else
            log_error "Container $container_name does not exist"
            return 1
        fi
    done
    
    return 1
}

# Safe docker run with conflict detection
docker_safe_run() {
    local max_retries="${1:-3}"
    shift
    local docker_args="$@"
    
    for ((i=1; i<=max_retries; i++)); do
        if eval "docker run $docker_args" 2>/tmp/docker_run_error.log; then
            return 0
        else
            local error_msg=$(cat /tmp/docker_run_error.log)
            
            if echo "$error_msg" | grep -q "port.*already allocated"; then
                log_warn "Port conflict on attempt $i"
                if [ $i -lt $max_retries ]; then
                    log_info "Waiting 5s before retry..."
                    sleep 5
                    continue
                fi
            fi
            
            log_error "Docker run failed: $error_msg"
            return 1
        fi
    done
    
    return 1
}

# Check if docker daemon is running
docker_check_daemon() {
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        return 1
    fi
    return 0
}

# Export functions for use in other scripts
export -f docker_safe_start
export -f docker_safe_run
export -f docker_check_daemon
export -f log_info
export -f log_warn
export -f log_error
