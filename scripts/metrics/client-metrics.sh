#!/bin/bash
set -euo pipefail

# Client-Specific Node Metrics Collector
# Issue #524: Implement detailed performance metrics for different XDC client types

readonly SCRIPT_VERSION="1.0.0"
readonly METRICS_DIR="${XDC_METRICS_DIR:-/var/lib/xdc-metrics}"
readonly LOG_FILE="${XDC_LOG_DIR:-/var/log/xdc}/metrics.log"

# Client types
CLIENT_TYPES=("geth" "erigon" "nethermind" "reth")

# Logging
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
info() { log "INFO: $*"; }
warn() { log "WARN: $*" >&2; }

# Initialize directories
init() {
    mkdir -p "$METRICS_DIR" "$(dirname "$LOG_FILE")"
    for client in "${CLIENT_TYPES[@]}"; do
        mkdir -p "$METRICS_DIR/$client"
    done
}

# Get RPC URL for client
get_client_rpc() {
    local client=$1
    case $client in
        geth) echo "${GETH_RPC:-http://localhost:8545}" ;;
        erigon) echo "${ERIGON_RPC:-http://localhost:8547}" ;;
        nethermind) echo "${NETHERMIND_RPC:-http://localhost:8558}" ;;
        reth) echo "${RETH_RPC:-http://localhost:7073}" ;;
        *) echo "http://localhost:8545" ;;
    esac
}

# RPC call helper
rpc_call() {
    local rpc_url=$1
    local method=$2
    local params=${3:-'[]'}
    
    curl -sf -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        2>/dev/null || echo '{}'
}

# Get system metrics for a process
get_system_metrics() {
    local pid=$1
    
    if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
        echo '{"cpu":0,"memory_rss":0,"memory_vms":0,"threads":0}'
        return
    fi
    
    # Read /proc/[pid]/stat
    local stat
    stat=$(cat "/proc/$pid/stat" 2>/dev/null || echo "")
    
    if [[ -z "$stat" ]]; then
        echo '{"cpu":0,"memory_rss":0,"memory_vms":0,"threads":0}'
        return
    fi
    
    # Parse stat fields
    local utime stime rss vms threads
    utime=$(echo "$stat" | awk '{print $14}')
    stime=$(echo "$stat" | awk '{print $15}')
    rss=$(echo "$stat" | awk '{print $24}')
    threads=$(echo "$stat" | awk '{print $20}')
    
    # Get VMS from status file
    vms=$(grep VmSize "/proc/$pid/status" 2>/dev/null | awk '{print $2}' || echo 0)
    
    # Calculate CPU usage (simplified)
    local cpu=0
    if [[ -n "$utime" && -n "$stime" ]]; then
        cpu=$(( (utime + stime) / 100 ))
    fi
    
    # Convert pages to bytes (typically 4096 bytes per page)
    rss=$((rss * 4096))
    vms=$((vms * 1024))
    
    jq -n \
        --arg cpu "$cpu" \
        --arg rss "$rss" \
        --arg vms "$vms" \
        --arg threads "$threads" \
        '{cpu: ($cpu | tonumber), memory_rss: ($rss | tonumber), memory_vms: ($vms | tonumber), threads: ($threads | tonumber)}'
}

# Get disk I/O metrics
get_disk_io() {
    local pid=$1
    
    if [[ -z "$pid" ]] || [[ ! -f "/proc/$pid/io" ]]; then
        echo '{"read_bytes":0,"write_bytes":0}'
        return
    fi
    
    local read_bytes write_bytes
    read_bytes=$(grep read_bytes "/proc/$pid/io" 2>/dev/null | awk '{print $2}' || echo 0)
    write_bytes=$(grep write_bytes "/proc/$pid/io" 2>/dev/null | awk '{print $2}' || echo 0)
    
    jq -n \
        --arg read "$read_bytes" \
        --arg write "$write_bytes" \
        '{read_bytes: ($read | tonumber), write_bytes: ($write | tonumber)}'
}

# Get Geth-specific metrics
collect_geth_metrics() {
    local rpc_url=$1
    local container=${2:-xdc-node-geth}
    
    # Get process metrics
    local pid
    pid=$(docker inspect -f '{{.State.Pid}}' "$container" 2>/dev/null || echo "")
    
    local system_metrics
    system_metrics=$(get_system_metrics "$pid")
    
    local disk_io
    disk_io=$(get_disk_io "$pid")
    
    # Blockchain metrics
    local block_result
    block_result=$(rpc_call "$rpc_url" "eth_blockNumber")
    local block_num
    block_num=$(printf '%d' "$(echo "$block_result" | jq -r '.result // "0x0"')" 2>/dev/null || echo 0)
    
    local peer_result
    peer_result=$(rpc_call "$rpc_url" "net_peerCount")
    local peers
    peers=$(printf '%d' "$(echo "$peer_result" | jq -r '.result // "0x0"')" 2>/dev/null || echo 0)
    
    # Sync status
    local sync_result
    sync_result=$(rpc_call "$rpc_url" "eth_syncing")
    local syncing
    syncing=$(echo "$sync_result" | jq -r '.result')
    local sync_progress=100
    
    if [[ "$syncing" != "false" ]]; then
        local current highest
        current=$(printf '%d' "$(echo "$sync_result" | jq -r '.result.currentBlock // "0x0"')" 2>/dev/null || echo 0)
        highest=$(printf '%d' "$(echo "$sync_result" | jq -r '.result.highestBlock // "0x0"')" 2>/dev/null || echo 1)
        if [[ $highest -gt 0 ]]; then
            sync_progress=$((current * 100 / highest))
        fi
    fi
    
    # Build metrics object
    jq -n \
        --argjson system "$system_metrics" \
        --argjson disk "$disk_io" \
        --arg block_num "$block_num" \
        --arg peers "$peers" \
        --arg sync_progress "$sync_progress" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            client: "geth",
            timestamp: $timestamp,
            system: $system,
            disk: $disk,
            blockchain: {
                block_number: ($block_num | tonumber),
                peers: ($peers | tonumber),
                sync_progress: ($sync_progress | tonumber)
            }
        }'
}

# Get Erigon-specific metrics
collect_erigon_metrics() {
    local rpc_url=$1
    local container=${2:-xdc-node-erigon}
    
    local pid
    pid=$(docker inspect -f '{{.State.Pid}}' "$container" 2>/dev/null || echo "")
    
    local system_metrics
    system_metrics=$(get_system_metrics "$pid")
    local disk_io
    disk_io=$(get_disk_io "$pid")
    
    # Erigon-specific: stages progress
    local block_result
    block_result=$(rpc_call "$rpc_url" "eth_blockNumber")
    local block_num
    block_num=$(printf '%d' "$(echo "$block_result" | jq -r '.result // "0x0"')" 2>/dev/null || echo 0)
    
    local peer_result
    peer_result=$(rpc_call "$rpc_url" "net_peerCount")
    local peers
    peers=$(printf '%d' "$(echo "$peer_result" | jq -r '.result // "0x0"')" 2>/dev/null || echo 0)
    
    jq -n \
        --argjson system "$system_metrics" \
        --argjson disk "$disk_io" \
        --arg block_num "$block_num" \
        --arg peers "$peers" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            client: "erigon",
            timestamp: $timestamp,
            system: $system,
            disk: $disk,
            blockchain: {
                block_number: ($block_num | tonumber),
                peers: ($peers | tonumber)
            }
        }'
}

# Get Nethermind-specific metrics
collect_nethermind_metrics() {
    local rpc_url=$1
    local container=${2:-xdc-node-nethermind}
    
    local pid
    pid=$(docker inspect -f '{{.State.Pid}}' "$container" 2>/dev/null || echo "")
    
    local system_metrics
    system_metrics=$(get_system_metrics "$pid")
    local disk_io
    disk_io=$(get_disk_io "$pid")
    
    local block_result
    block_result=$(rpc_call "$rpc_url" "eth_blockNumber")
    local block_num
    block_num=$(printf '%d' "$(echo "$block_result" | jq -r '.result // "0x0"')" 2>/dev/null || echo 0)
    
    local peer_result
    peer_result=$(rpc_call "$rpc_url" "net_peerCount")
    local peers
    peers=$(printf '%d' "$(echo "$peer_result" | jq -r '.result // "0x0"')" 2>/dev/null || echo 0)
    
    jq -n \
        --argjson system "$system_metrics" \
        --argjson disk "$disk_io" \
        --arg block_num "$block_num" \
        --arg peers "$peers" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            client: "nethermind",
            timestamp: $timestamp,
            system: $system,
            disk: $disk,
            blockchain: {
                block_number: ($block_num | tonumber),
                peers: ($peers | tonumber)
            }
        }'
}

# Get Reth-specific metrics
collect_reth_metrics() {
    local rpc_url=$1
    local container=${2:-xdc-node-reth}
    
    local pid
    pid=$(docker inspect -f '{{.State.Pid}}' "$container" 2>/dev/null || echo "")
    
    local system_metrics
    system_metrics=$(get_system_metrics "$pid")
    local disk_io
    disk_io=$(get_disk_io "$pid")
    
    local block_result
    block_result=$(rpc_call "$rpc_url" "eth_blockNumber")
    local block_num
    block_num=$(printf '%d' "$(echo "$block_result" | jq -r '.result // "0x0"')" 2>/dev/null || echo 0)
    
    local peer_result
    peer_result=$(rpc_call "$rpc_url" "net_peerCount")
    local peers
    peers=$(printf '%d' "$(echo "$peer_result" | jq -r '.result // "0x0"')" 2>/dev/null || echo 0)
    
    jq -n \
        --argjson system "$system_metrics" \
        --argjson disk "$disk_io" \
        --arg block_num "$block_num" \
        --arg peers "$peers" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            client: "reth",
            timestamp: $timestamp,
            system: $system,
            disk: $disk,
            blockchain: {
                block_number: ($block_num | tonumber),
                peers: ($peers | tonumber)
            }
        }'
}

# Collect metrics for a specific client
collect_client_metrics() {
    local client=$1
    local rpc_url
    rpc_url=$(get_client_rpc "$client")
    
    case $client in
        geth) collect_geth_metrics "$rpc_url" ;;
        erigon) collect_erigon_metrics "$rpc_url" ;;
        nethermind) collect_nethermind_metrics "$rpc_url" ;;
        reth) collect_reth_metrics "$rpc_url" ;;
    esac
}

# Export metrics in Prometheus format
export_prometheus() {
    local timestamp
    timestamp=$(date +%s)
    
    for client in "${CLIENT_TYPES[@]}"; do
        local metrics_file="$METRICS_DIR/$client/latest.json"
        
        if [[ -f "$metrics_file" ]]; then
            local metrics
            metrics=$(cat "$metrics_file")
            
            # Extract values
            local cpu memory_rss memory_vms block_number peers
            cpu=$(echo "$metrics" | jq -r '.system.cpu // 0')
            memory_rss=$(echo "$metrics" | jq -r '.system.memory_rss // 0')
            memory_vms=$(echo "$metrics" | jq -r '.system.memory_vms // 0')
            block_number=$(echo "$metrics" | jq -r '.blockchain.block_number // 0')
            peers=$(echo "$metrics" | jq -r '.blockchain.peers // 0')
            
            # Output Prometheus format
            echo "# HELP xdc_client_cpu_usage CPU usage for $client"
            echo "# TYPE xdc_client_cpu_usage gauge"
            echo "xdc_client_cpu_usage{client=\"$client\"} $cpu"
            
            echo "# HELP xdc_client_memory_rss_bytes RSS memory for $client"
            echo "# TYPE xdc_client_memory_rss_bytes gauge"
            echo "xdc_client_memory_rss_bytes{client=\"$client\"} $memory_rss"
            
            echo "# HELP xdc_client_block_number Current block number for $client"
            echo "# TYPE xdc_client_block_number gauge"
            echo "xdc_client_block_number{client=\"$client\"} $block_number"
            
            echo "# HELP xdc_client_peer_count Peer count for $client"
            echo "# TYPE xdc_client_peer_count gauge"
            echo "xdc_client_peer_count{client=\"$client\"} $peers"
        fi
    done
}

# Collect all metrics
collect_all() {
    for client in "${CLIENT_TYPES[@]}"; do
        info "Collecting metrics for $client..."
        local metrics
        if metrics=$(collect_client_metrics "$client"); then
            echo "$metrics" > "$METRICS_DIR/$client/latest.json"
            
            # Also append to history
            echo "$metrics" >> "$METRICS_DIR/$client/history.jsonl"
        else
            warn "Failed to collect metrics for $client"
        fi
    done
}

# Main
main() {
    init
    
    case "${1:-collect}" in
        collect)
            collect_all
            ;;
        export-prometheus)
            export_prometheus
            ;;
        get)
            client="${2:-geth}"
            collect_client_metrics "$client"
            ;;
        daemon)
            interval="${2:-60}"
            info "Starting metrics collector daemon (interval: ${interval}s)"
            while true; do
                collect_all
                sleep "$interval"
            done
            ;;
        --help|-h)
            cat <<'EOF'
Client-Specific Node Metrics Collector v1.0.0

Usage: client-metrics.sh [command] [options]

Commands:
  collect              Collect metrics for all clients (default)
  export-prometheus    Export metrics in Prometheus format
  get [client]         Get metrics for specific client
  daemon [interval]    Run as daemon (default interval: 60s)

Supported Clients:
  geth, erigon, nethermind, reth

Environment Variables:
  GETH_RPC            Geth RPC endpoint (default: http://localhost:8545)
  ERIGON_RPC          Erigon RPC endpoint (default: http://localhost:8547)
  NETHERMIND_RPC      Nethermind RPC endpoint (default: http://localhost:8558)
  RETH_RPC            Reth RPC endpoint (default: http://localhost:7073)
  XDC_METRICS_DIR     Metrics storage directory
  XDC_LOG_DIR         Log directory

Examples:
  ./client-metrics.sh collect
  ./client-metrics.sh get geth
  ./client-metrics.sh daemon 30
  ./client-metrics.sh export-prometheus > /var/lib/prometheus/node-exporter/xdc.prom
EOF
            ;;
        *)
            error "Unknown command: ${1:-}"
            error "Use --help for usage information"
            exit 1
            ;;
    esac
}

main "$@"
