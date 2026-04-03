#!/bin/bash
#===============================================================================
# XDC Node Setup - Prometheus /metrics Exporter (#137)
# Starts a simple HTTP server (via netcat loop) on port 9090 that serves
# Prometheus-format metrics: block_number, peer_count, sync_status.
# One exporter instance per client.
# Usage: prometheus-exporter.sh <client> [--port PORT]
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-lib.sh"

declare -A CLIENT_RPC_PORTS=(
    ["geth"]="7070"
    ["erigon"]="7071"
    ["nethermind"]="7072"
    ["reth"]="8588"
)

# Default exporter ports per client (can be overridden with --port)
declare -A EXPORTER_PORTS=(
    ["geth"]="9090"
    ["erigon"]="9091"
    ["nethermind"]="9092"
    ["reth"]="9093"
)

TIMEOUT_S="${TIMEOUT_S:-5}"
PID_DIR="${PID_DIR:-/var/run/xdc-exporter}"
LOG_DIR="${LOG_DIR:-/var/log/xdc}"

#-------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [client] [OPTIONS]

Commands:
  start  <client>    Start Prometheus exporter for a client
  stop   <client>    Stop running exporter
  status             Show running exporters
  all                Start exporters for all clients

Options:
  --port PORT        Override default exporter port
  --rpc-port PORT    Override RPC port for client
  --bg               Run in background (daemonize)
  -h                 Show this help

Client → Default exporter port:
  geth        → 9090
  erigon      → 9091
  nethermind  → 9092
  reth        → 9093

Metrics exposed (Prometheus text format):
  xdc_block_number{client}     Current head block number
  xdc_peer_count{client}       Number of connected peers
  xdc_sync_status{client}      1=synced, 0=syncing
  xdc_sync_lag_blocks{client}  Blocks behind highest known
  xdc_rpc_up{client}           1=RPC reachable, 0=down

Examples:
  $(basename "$0") start geth
  $(basename "$0") start erigon --port 9099
  $(basename "$0") all --bg
  $(basename "$0") status
  $(basename "$0") stop geth
EOF
}

#-------------------------------------------------------------------------------
collect_metrics() {
    local client="$1"
    local rpc_port="$2"
    local endpoint="http://127.0.0.1:${rpc_port}"
    
    local ts
    ts=$(date +%s)
    local block_number=0
    local peer_count=0
    local sync_status=1   # 1 = synced
    local sync_lag=0
    local rpc_up=0
    
    # --- eth_blockNumber ---
    local bn_result
    bn_result=$(curl -sf --max-time "$TIMEOUT_S" \
        -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$endpoint" 2>/dev/null) && rpc_up=1 || { rpc_up=0; }
    
    if [[ $rpc_up -eq 1 ]]; then
        local bn_hex
        bn_hex=$(echo "$bn_result" | grep -o '"result":"0x[^"]*"' | cut -d'"' -f4) || true
        [[ -n "$bn_hex" ]] && block_number=$(( 16#${bn_hex#0x} )) || true
    fi
    
    # --- net_peerCount ---
    if [[ $rpc_up -eq 1 ]]; then
        local pc_result
        pc_result=$(curl -sf --max-time "$TIMEOUT_S" \
            -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":2}' \
            "$endpoint" 2>/dev/null) || true
        local pc_hex
        pc_hex=$(echo "$pc_result" | grep -o '"result":"0x[^"]*"' | cut -d'"' -f4) || true
        [[ -n "$pc_hex" ]] && peer_count=$(( 16#${pc_hex#0x} )) || true
    fi
    
    # --- eth_syncing ---
    if [[ $rpc_up -eq 1 ]]; then
        local sync_result
        sync_result=$(curl -sf --max-time "$TIMEOUT_S" \
            -X POST -H "Content-Type: application/json" \
            --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":3}' \
            "$endpoint" 2>/dev/null) || true
        
        if echo "$sync_result" | grep -q '"result":false'; then
            sync_status=1
            sync_lag=0
        else
            sync_status=0
            local highest_hex current_hex
            highest_hex=$(echo "$sync_result" | grep -o '"highestBlock":"0x[^"]*"' | cut -d'"' -f4) || true
            current_hex=$(echo "$sync_result" | grep -o '"currentBlock":"0x[^"]*"' | cut -d'"' -f4) || true
            if [[ -n "$highest_hex" && -n "$current_hex" ]]; then
                local highest current
                highest=$(( 16#${highest_hex#0x} ))
                current=$(( 16#${current_hex#0x} ))
                sync_lag=$(( highest - current ))
            fi
        fi
    fi
    
    # Emit Prometheus text format
    cat <<PROM
# HELP xdc_block_number Current head block number
# TYPE xdc_block_number gauge
xdc_block_number{client="${client}"} ${block_number}
# HELP xdc_peer_count Number of connected peers
# TYPE xdc_peer_count gauge
xdc_peer_count{client="${client}"} ${peer_count}
# HELP xdc_sync_status Node sync status (1=synced, 0=syncing)
# TYPE xdc_sync_status gauge
xdc_sync_status{client="${client}"} ${sync_status}
# HELP xdc_sync_lag_blocks Blocks behind the highest known block
# TYPE xdc_sync_lag_blocks gauge
xdc_sync_lag_blocks{client="${client}"} ${sync_lag}
# HELP xdc_rpc_up RPC endpoint reachability (1=up, 0=down)
# TYPE xdc_rpc_up gauge
xdc_rpc_up{client="${client}"} ${rpc_up}
# HELP xdc_scrape_timestamp Unix timestamp of last scrape
# TYPE xdc_scrape_timestamp gauge
xdc_scrape_timestamp{client="${client}"} ${ts}
PROM
}

#-------------------------------------------------------------------------------
serve_exporter() {
    local client="$1"
    local rpc_port="$2"
    local exporter_port="$3"
    
    # Check nc availability
    if ! command -v nc &>/dev/null; then
        die "netcat (nc) not found — install netcat-openbsd"
    fi
    
    log "Starting Prometheus exporter: ${client} → http://0.0.0.0:${exporter_port}/metrics"
    info "Scraping XDC RPC: http://127.0.0.1:${rpc_port}"
    info "Press Ctrl+C to stop"
    
    # Save PID
    mkdir -p "${PID_DIR}" 2>/dev/null || true
    echo $$ > "${PID_DIR}/${client}.pid"
    
    # Main nc server loop — handles one connection at a time
    while true; do
        local metrics_body
        metrics_body=$(collect_metrics "$client" "$rpc_port")
        local content_length=${#metrics_body}
        
        # Build HTTP response
        local response
        response="HTTP/1.1 200 OK
Content-Type: text/plain; version=0.0.4; charset=utf-8
Content-Length: ${content_length}
Connection: close

${metrics_body}"
        
        # Handle the connection via nc
        # Different nc versions have different syntax
        if nc -h 2>&1 | grep -q '\-l.*port'; then
            # BSD/macOS nc: nc -l port
            echo -e "$response" | nc -l "$exporter_port" -q 1 2>/dev/null || true
        elif nc -h 2>&1 | grep -q '\-p'; then
            # GNU nc: nc -l -p port
            echo -e "$response" | nc -l -p "$exporter_port" -q 1 2>/dev/null || true
        else
            # Try the more common form
            printf '%s' "$response" | nc -l "$exporter_port" 2>/dev/null || true
        fi
        
        sleep 0.1
    done
}

#-------------------------------------------------------------------------------
cmd_start() {
    local client="$1"
    local exporter_port="${2:-${EXPORTER_PORTS[$client]:-9090}}"
    local rpc_port="${3:-${CLIENT_RPC_PORTS[$client]:-8545}}"
    local bg="${4:-false}"
    
    if [[ -z "${CLIENT_RPC_PORTS[$client]:-}" ]]; then
        die "Unknown client: ${client}. Known: ${!CLIENT_RPC_PORTS[*]}"
    fi
    
    if $bg; then
        mkdir -p "${LOG_DIR}" 2>/dev/null || true
        local log_file="${LOG_DIR}/prometheus-exporter-${client}.log"
        info "Starting in background. Logs: ${log_file}"
        nohup bash "$0" start "$client" --port "$exporter_port" --rpc-port "$rpc_port" \
            >> "$log_file" 2>&1 &
        log "Started exporter for ${client} (PID $!) on port ${exporter_port}"
    else
        serve_exporter "$client" "$rpc_port" "$exporter_port"
    fi
}

#-------------------------------------------------------------------------------
cmd_stop() {
    local client="$1"
    local pid_file="${PID_DIR}/${client}.pid"
    
    if [[ ! -f "$pid_file" ]]; then
        warn "No PID file found for ${client} at ${pid_file}"
        return
    fi
    
    local pid
    pid=$(cat "$pid_file")
    
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        rm -f "$pid_file"
        log "Stopped exporter for ${client} (PID ${pid})"
    else
        warn "Process ${pid} not running — cleaning up PID file"
        rm -f "$pid_file"
    fi
}

#-------------------------------------------------------------------------------
cmd_status() {
    info "=== Prometheus Exporter Status ==="
    
    for client in "${!EXPORTER_PORTS[@]}"; do
        local port="${EXPORTER_PORTS[$client]}"
        local pid_file="${PID_DIR}/${client}.pid"
        local status="stopped"
        local pid_info=""
        
        if [[ -f "$pid_file" ]]; then
            local pid
            pid=$(cat "$pid_file")
            if kill -0 "$pid" 2>/dev/null; then
                status="running"
                pid_info=" (PID ${pid})"
            else
                status="stale"
            fi
        fi
        
        printf "  %-15s port=%-6s %s%s\n" "$client" "$port" "$status" "$pid_info"
    done
}

#-------------------------------------------------------------------------------
main() {
    local cmd="${1:-help}"
    shift || true
    
    local client=""
    local exporter_port=""
    local rpc_port=""
    local bg=false
    
    # Parse remaining args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --port)     exporter_port="$2"; shift ;;
            --rpc-port) rpc_port="$2"; shift ;;
            --bg)       bg=true ;;
            -h|--help)  usage; exit 0 ;;
            -*)         error "Unknown option: $1"; usage; exit 1 ;;
            *)
                if [[ -z "$client" ]]; then
                    client="$1"
                fi
                ;;
        esac
        shift
    done
    
    case "$cmd" in
        start)
            [[ -z "$client" ]] && { error "Client required"; usage; exit 1; }
            cmd_start "$client" \
                "${exporter_port:-${EXPORTER_PORTS[$client]:-9090}}" \
                "${rpc_port:-${CLIENT_RPC_PORTS[$client]:-8545}}" \
                "$bg"
            ;;
        stop)
            [[ -z "$client" ]] && { error "Client required"; usage; exit 1; }
            cmd_stop "$client"
            ;;
        status)
            cmd_status
            ;;
        all)
            for c in "${!CLIENT_RPC_PORTS[@]}"; do
                cmd_start "$c" \
                    "${EXPORTER_PORTS[$c]:-9090}" \
                    "${CLIENT_RPC_PORTS[$c]}" \
                    "true"
            done
            log "All exporters started in background"
            ;;
        -h|--help|help)
            usage; exit 0
            ;;
        *)
            error "Unknown command: ${cmd}"
            usage; exit 1
            ;;
    esac
}

main "$cmd" "$@"
