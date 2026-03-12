#!/bin/bash
set -euo pipefail

# Health Check Endpoint for Load Balancers
# Issue #521: Implement standardized health check endpoints for Kubernetes and load balancer integration

readonly SCRIPT_VERSION="1.0.0"
readonly LOG_FILE="${XDC_LOG_DIR:-/var/log/xdc}/health-check.log"

# Configuration
RPC_URL="${RPC_URL:-http://localhost:8545}"
HEALTH_PORT="${HEALTH_PORT:-8080}"
MAX_BLOCKS_BEHIND="${HEALTH_MAX_BEHIND:-10}"
MIN_PEERS="${HEALTH_MIN_PEERS:-3}"

# Logging
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
info() { log "INFO: $*"; }
error() { log "ERROR: $*" >&2; }

# RPC call helper
rpc_call() {
    local method=$1
    local params=${2:-'[]'}
    
    curl -sf -m 5 -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        2>/dev/null || echo '{}'
}

# Check liveness - is process running?
check_liveness() {
    local result
    result=$(rpc_call "web3_clientVersion")
    local version
    version=$(echo "$result" | jq -r '.result // empty')
    
    if [[ -n "$version" ]]; then
        echo '{"status":"alive","version":"'$version'"}'
        return 0
    else
        echo '{"status":"dead","error":"RPC not responding"}'
        return 1
    fi
}

# Check readiness - is node ready for traffic?
check_readiness() {
    local checks=()
    local overall_status="healthy"
    
    # Check 1: RPC connectivity
    local start_time
    start_time=$(date +%s%N)
    local rpc_result
    rpc_result=$(rpc_call "eth_blockNumber")
    local end_time
    end_time=$(date +%s%N)
    local latency_ms=$(( (end_time - start_time) / 1000000 ))
    
    local block_hex
    block_hex=$(echo "$rpc_result" | jq -r '.result // empty')
    
    if [[ -n "$block_hex" ]]; then
        checks+=("{\"name\":\"rpc\",\"status\":\"pass\",\"latency_ms\":$latency_ms}")
    else
        checks+=("{\"name\":\"rpc\",\"status\":\"fail\",\"error\":\"No response\"}")
        overall_status="unhealthy"
    fi
    
    # Check 2: Sync status
    local sync_result
    sync_result=$(rpc_call "eth_syncing")
    local syncing
    syncing=$(echo "$sync_result" | jq -r '.result')
    
    if [[ "$syncing" == "false" ]]; then
        # Fully synced
        checks+=("{\"name\":\"sync\",\"status\":\"pass\",\"synced\":true}")
    elif [[ "$syncing" == "{}" || -z "$syncing" ]]; then
        # Unknown state
        checks+=("{\"name\":\"sync\",\"status\":\"warn\",\"error\":\"Unknown sync state\"}")
        overall_status="degraded"
    else
        # Syncing - check how far behind
        local current
        current=$(printf '%d' "$(echo "$sync_result" | jq -r '.result.currentBlock // "0x0"')" 2>/dev/null || echo 0)
        local highest
        highest=$(printf '%d' "$(echo "$sync_result" | jq -r '.result.highestBlock // "0x0"')" 2>/dev/null || echo 1)
        local behind=$((highest - current))
        
        if [[ $behind -le $MAX_BLOCKS_BEHIND ]]; then
            checks+=("{\"name\":\"sync\",\"status\":\"pass\",\"blocks_behind\":$behind}")
        else
            checks+=("{\"name\":\"sync\",\"status\":\"fail\",\"blocks_behind\":$behind}")
            overall_status="unhealthy"
        fi
    fi
    
    # Check 3: Peers
    local peer_result
    peer_result=$(rpc_call "net_peerCount")
    local peers
    peers=$(printf '%d' "$(echo "$peer_result" | jq -r '.result // "0x0"')" 2>/dev/null || echo 0)
    
    if [[ $peers -ge $MIN_PEERS ]]; then
        checks+=("{\"name\":\"peers\",\"status\":\"pass\",\"count\":$peers}")
    else
        checks+=("{\"name\":\"peers\",\"status\":\"fail\",\"count\":$peers,\"min_required\":$MIN_PEERS}")
        overall_status="degraded"
    fi
    
    # Check 4: Disk space (if running locally)
    local data_dir="${DATA_DIR:-./xdcchain}"
    local disk_usage
    disk_usage=$(df -P "$data_dir" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%' || echo 100)
    local free_percent=$((100 - disk_usage))
    
    if [[ $free_percent -ge 10 ]]; then
        checks+=("{\"name\":\"disk\",\"status\":\"pass\",\"free_percent\":$free_percent}")
    else
        checks+=("{\"name\":\"disk\",\"status\":\"fail\",\"free_percent\":$free_percent}")
        overall_status="unhealthy"
    fi
    
    # Build response
    local checks_json
    checks_json=$(IFS=,; echo "[${checks[*]}]")
    
    jq -n \
        --arg status "$overall_status" \
        --argjson checks "$checks_json" \
        '{status: $status, checks: $checks, timestamp: now | todate}'
    
    if [[ "$overall_status" == "unhealthy" ]]; then
        return 1
    else
        return 0
    fi
}

# Check sync status in detail
check_sync() {
    local sync_result
    sync_result=$(rpc_call "eth_syncing")
    local syncing
    syncing=$(echo "$sync_result" | jq -r '.result')
    
    local current highest peers
    
    if [[ "$syncing" == "false" ]]; then
        # Get current block
        local block_result
        block_result=$(rpc_call "eth_blockNumber")
        current=$(printf '%d' "$(echo "$block_result" | jq -r '.result // "0x0"')" 2>/dev/null || echo 0)
        highest=$current
    else
        current=$(printf '%d' "$(echo "$sync_result" | jq -r '.result.currentBlock // "0x0"')" 2>/dev/null || echo 0)
        highest=$(printf '%d' "$(echo "$sync_result" | jq -r '.result.highestBlock // "0x0"')" 2>/dev/null || echo 1)
    fi
    
    # Get peers
    local peer_result
    peer_result=$(rpc_call "net_peerCount")
    peers=$(printf '%d' "$(echo "$peer_result" | jq -r '.result // "0x0"')" 2>/dev/null || echo 0)
    
    # Calculate progress
    local progress=100
    if [[ $highest -gt 0 ]]; then
        progress=$((current * 100 / highest))
    fi
    
    local behind=$((highest - current))
    
    jq -n \
        --arg current "$current" \
        --arg highest "$highest" \
        --arg progress "$progress" \
        --arg behind "$behind" \
        --arg peers "$peers" \
        --arg synced "$([[ "$syncing" == "false" ]] && echo "true" || echo "false")" \
        '{
            current_block: ($current | tonumber),
            highest_block: ($highest | tonumber),
            sync_progress: ($progress | tonumber),
            blocks_behind: ($behind | tonumber),
            peer_count: ($peers | tonumber),
            fully_synced: ($synced == "true")
        }'
}

# HTTP response helper
http_response() {
    local code=$1
    local content_type=${2:-"application/json"}
    local body=$3
    
    case $code in
        200) echo -e "HTTP/1.1 200 OK\r\nContent-Type: $content_type\r\nConnection: close\r\n\r\n$body" ;;
        503) echo -e "HTTP/1.1 503 Service Unavailable\r\nContent-Type: $content_type\r\nConnection: close\r\n\r\n$body" ;;
        404) echo -e "HTTP/1.1 404 Not Found\r\nContent-Type: $content_type\r\nConnection: close\r\n\r\n$body" ;;
        *) echo -e "HTTP/1.1 $code\r\nContent-Type: $content_type\r\nConnection: close\r\n\r\n$body" ;;
    esac
}

# Handle HTTP request
handle_request() {
    local request=$1
    
    if [[ "$request" == *"GET /health/live"* ]]; then
        local response
        if response=$(check_liveness); then
            http_response 200 "application/json" "$response"
        else
            http_response 503 "application/json" "$response"
        fi
        
    elif [[ "$request" == *"GET /health/ready"* ]]; then
        local response
        if response=$(check_readiness); then
            http_response 200 "application/json" "$response"
        else
            http_response 503 "application/json" "$response"
        fi
        
    elif [[ "$request" == *"GET /health/sync"* ]]; then
        local response
        response=$(check_sync)
        http_response 200 "application/json" "$response"
        
    elif [[ "$request" == *"GET /health"* ]]; then
        local response
        response=$(check_readiness)
        local code=200
        if [[ $(echo "$response" | jq -r '.status') == "unhealthy" ]]; then
            code=503
        fi
        http_response $code "application/json" "$response"
        
    else
        http_response 404 "application/json" '{"error":"Not found"}'
    fi
}

# Start health check server
start_server() {
    local port=${1:-$HEALTH_PORT}
    
    info "Starting health check server on port $port"
    info "Endpoints:"
    info "  - /health/live  - Liveness probe"
    info "  - /health/ready - Readiness probe"
    info "  - /health/sync  - Sync status"
    info "  - /health       - Full health check"
    
    # Check if netcat is available
    if command -v nc >/devdev/null 2>&1; then
        while true; do
            {
                read -r request
                handle_request "$request"
            } | nc -l -p "$port" -q 1
        done
    else
        error "netcat (nc) is required for the health check server"
        exit 1
    fi
}

# Kubernetes probe helper
k8s_probe() {
    local probe_type=$1
    
    case $probe_type in
        liveness)
            if check_liveness > /dev/null 2>&1; then
                echo "OK"
                exit 0
            else
                echo "FAIL"
                exit 1
            fi
            ;;
        readiness)
            if check_readiness > /dev/null 2>&1; then
                echo "OK"
                exit 0
            else
                echo "FAIL"
                exit 1
            fi
            ;;
        *)
            error "Unknown probe type: $probe_type"
            exit 1
            ;;
    esac
}

# Show usage
show_help() {
    cat <<'EOF'
XDC Health Check Endpoint v1.0.0

Usage: health-check.sh <command> [options]

Commands:
  server [port]           Start HTTP health check server
  k8s liveness            Kubernetes liveness probe
  k8s readiness           Kubernetes readiness probe
  check live              Check liveness (returns JSON)
  check ready             Check readiness (returns JSON)
  check sync              Check sync status (returns JSON)

Endpoints (when running server):
  GET /health/live        Liveness probe - returns 200 if process running
  GET /health/ready       Readiness probe - returns 200 if ready for traffic
  GET /health/sync        Sync status - detailed sync information
  GET /health             Full health check

Environment Variables:
  RPC_URL                 XDC node RPC endpoint (default: http://localhost:8545)
  HEALTH_PORT             Health check server port (default: 8080)
  HEALTH_MAX_BEHIND       Max blocks behind for readiness (default: 10)
  HEALTH_MIN_PEERS        Minimum peers for readiness (default: 3)

Kubernetes Integration:
  livenessProbe:
    exec:
      command:
        - /scripts/health-check.sh
        - k8s
        - liveness
    initialDelaySeconds: 60
    periodSeconds: 30
  
  readinessProbe:
    exec:
      command:
        - /scripts/health-check.sh
        - k8s
        - readiness
    initialDelaySeconds: 10
    periodSeconds: 5

Examples:
  ./health-check.sh server 8080          # Start server on port 8080
  ./health-check.sh k8s liveness         # Run liveness check
  ./health-check.sh check ready          # Check readiness
EOF
}

# Main
main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    
    case "${1:-server}" in
        server)
            start_server "${2:-$HEALTH_PORT}"
            ;;
        k8s)
            k8s_probe "${2:-liveness}"
            ;;
        check)
            case "${2:-ready}" in
                live|liveness) check_liveness ;;
                ready|readiness) check_readiness ;;
                sync) check_sync ;;
                *) error "Unknown check type: $2"; exit 1 ;;
            esac
            ;;
        --help|-h)
            show_help
            ;;
        *)
            error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
