#!/bin/bash
#==============================================================================
# Graceful Shutdown Handler for XDC Node
# Handles SIGTERM/SIGINT for clean shutdown
#==============================================================================

# Source logging library if available
if [[ -f /opt/xdc-node/scripts/lib/logging.sh ]]; then
    source /opt/xdc-node/scripts/lib/logging.sh
else
    log_info() { echo "[INFO] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
fi

# Configuration
GRACEFUL_SHUTDOWN_TIMEOUT=${GRACEFUL_SHUTDOWN_TIMEOUT:-60}
FORCE_KILL_TIMEOUT=${FORCE_KILL_TIMEOUT:-10}
XDC_DATA_DIR="${XDC_DATA_DIR:-/opt/xdc-node/mainnet/xdcchain}"
SHUTDOWN_IN_PROGRESS=false

#==============================================================================
# Shutdown Functions
#==============================================================================

# Main shutdown handler
graceful_shutdown() {
    local signal="$1"
    
    # Prevent recursive shutdown
    if [[ "$SHUTDOWN_IN_PROGRESS" == "true" ]]; then
        log_info "Shutdown already in progress, ignoring $signal"
        return
    fi
    
    SHUTDOWN_IN_PROGRESS=true
    
    log_info "Received $signal signal, initiating graceful shutdown..."
    log_info "Shutdown timeout: ${GRACEFUL_SHUTDOWN_TIMEOUT}s"
    
    # Create shutdown marker
    touch "${XDC_DATA_DIR}/.shutdown_in_progress"
    
    # Stop accepting new connections
    stop_accepting_connections
    
    # Wait for active operations to complete
    wait_for_active_operations
    
    # Sync data to disk
    sync_data
    
    # Stop services
    stop_services
    
    # Final cleanup
    cleanup
    
    log_info "Graceful shutdown completed"
    rm -f "${XDC_DATA_DIR}/.shutdown_in_progress"
    
    exit 0
}

# Stop accepting new connections
stop_accepting_connections() {
    log_info "Stopping acceptance of new connections..."
    
    # If using Docker, we can modify the container's network mode
    if [[ -f /var/run/docker.pid ]]; then
        docker pause xdc-node 2>/dev/null || true
    fi
    
    # Close RPC ports if managed by firewall
    if command -v ufw >/dev/null 2>&1; then
        ufw deny 8545/tcp 2>/dev/null || true
        ufw deny 8546/tcp 2>/dev/null || true
    fi
}

# Wait for active operations to complete
wait_for_active_operations() {
    log_info "Waiting for active operations to complete..."
    
    local wait_time=0
    local check_interval=5
    
    while [[ $wait_time -lt $GRACEFUL_SHUTDOWN_TIMEOUT ]]; do
        # Check if node is still syncing
        local syncing
        syncing=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
            http://localhost:8545 2>/dev/null | jq -r '.result')
        
        # If not syncing, we can proceed
        if [[ "$syncing" == "false" ]]; then
            log_info "Node is synced, proceeding with shutdown"
            return
        fi
        
        # Check peer count
        local peer_count
        peer_count=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
            http://localhost:8545 2>/dev/null | jq -r '.result // "0x0"')
        
        log_info "Waiting... (syncing: $syncing, peers: $peer_count)"
        
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    log_info "Shutdown timeout reached, proceeding anyway"
}

# Sync data to disk
sync_data() {
    log_info "Syncing data to disk..."
    
    # Sync filesystem
    sync
    
    # If XDC node supports admin RPC, trigger database flush
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"admin_exportChain","params":["'"${XDC_DATA_DIR}/export_backup"'"],"id":1}' \
        http://localhost:8545 2>/dev/null || true
    
    log_info "Data sync completed"
}

# Stop services
stop_services() {
    log_info "Stopping XDC node service..."
    
    # Try systemd first
    if systemctl is-active --quiet xdc-node 2>/dev/null; then
        log_info "Stopping via systemd..."
        systemctl stop xdc-node
        
        # Wait for service to stop
        local wait_time=0
        while systemctl is-active --quiet xdc-node 2>/dev/null && [[ $wait_time -lt $GRACEFUL_SHUTDOWN_TIMEOUT ]]; do
            sleep 1
            wait_time=$((wait_time + 1))
        done
        
        # Force kill if still running
        if systemctl is-active --quiet xdc-node 2>/dev/null; then
            log_error "Service did not stop gracefully, forcing..."
            systemctl kill --signal=SIGKILL xdc-node 2>/dev/null || true
        fi
    fi
    
    # Try Docker
    if docker ps | grep -q xdc-node; then
        log_info "Stopping via Docker..."
        docker stop --time=$GRACEFUL_SHUTDOWN_TIMEOUT xdc-node 2>/dev/null || true
        
        # Force kill if still running
        if docker ps | grep -q xdc-node; then
            log_error "Container did not stop gracefully, forcing..."
            docker kill xdc-node 2>/dev/null || true
        fi
    fi
    
    # Kill any remaining XDC processes
    local xdc_pids
    xdc_pids=$(pgrep -f "XDC|xdposchain" 2>/dev/null || true)
    if [[ -n "$xdc_pids" ]]; then
        log_info "Sending SIGTERM to remaining XDC processes..."
        kill -TERM $xdc_pids 2>/dev/null || true
        
        sleep $FORCE_KILL_TIMEOUT
        
        # Force kill remaining processes
        xdc_pids=$(pgrep -f "XDC|xdposchain" 2>/dev/null || true)
        if [[ -n "$xdc_pids" ]]; then
            log_error "Force killing remaining processes..."
            kill -KILL $xdc_pids 2>/dev/null || true
        fi
    fi
}

# Cleanup
cleanup() {
    log_info "Performing cleanup..."
    
    # Remove temporary files
    rm -f /tmp/xdc-node.* 2>/dev/null || true
    
    # Reopen ports if they were closed
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 8545/tcp 2>/dev/null || true
        ufw allow 8546/tcp 2>/dev/null || true
    fi
    
    # Unpause Docker container if paused
    if [[ -f /var/run/docker.pid ]]; then
        docker unpause xdc-node 2>/dev/null || true
    fi
}

#==============================================================================
# Signal Handlers Setup
#==============================================================================

setup_shutdown_handlers() {
    trap 'graceful_shutdown SIGTERM' SIGTERM
    trap 'graceful_shutdown SIGINT' SIGINT
    trap 'graceful_shutdown SIGHUP' SIGHUP
    
    log_info "Graceful shutdown handlers installed"
}

#==============================================================================
# Main
#==============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_shutdown_handlers
    
    # If run directly, wait for signals
    log_info "Shutdown handler is running. Press Ctrl+C to test shutdown."
    while true; do
        sleep 1
    done
fi