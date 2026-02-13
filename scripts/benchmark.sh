#!/usr/bin/env bash
#==============================================================================
# Performance Benchmarks for XDC Node Operations
# Measures: Sync speed, RPC latency, disk I/O, memory usage
#==============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/lib"

# Source libraries
# shellcheck source=/dev/null
source "${LIB_DIR}/logging.sh" 2>/dev/null || true
# shellcheck source=/dev/null
source "${LIB_DIR}/error-handler.sh" 2>/dev/null || init_error_handling

# Configuration
readonly BENCHMARK_LOG="${BENCHMARK_LOG:-/var/log/xdc-node/benchmarks.log}"
readonly RPC_URL="${RPC_URL:-http://localhost:8545}"
readonly OUTPUT_FORMAT="${OUTPUT_FORMAT:-json}"  # json or text

# Benchmark results storage
declare -A BENCHMARK_RESULTS

#==============================================================================
# Utility Functions
#==============================================================================

log_benchmark() {
    local test_name="$1"
    local value="$2"
    local unit="$3"
    local timestamp
    timestamp=$(date -Iseconds)

    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "{\"timestamp\":\"$timestamp\",\"benchmark\":\"$test_name\",\"value\":$value,\"unit\":\"$unit\"}"
    else
        echo "[$timestamp] $test_name: $value $unit"
    fi >> "$BENCHMARK_LOG"
}

# Get current timestamp in milliseconds
timestamp_ms() {
    date +%s%3N
}

# Calculate duration from start time
calculate_duration() {
    local start_ms=$1
    local end_ms
    end_ms=$(timestamp_ms)
    echo $((end_ms - start_ms))
}

#==============================================================================
# RPC Latency Benchmarks
#==============================================================================

benchmark_rpc_latency() {
    echo "Running RPC latency benchmark..."

    local methods=("eth_blockNumber" "eth_syncing" "net_peerCount" "eth_gasPrice")
    local iterations=100

    for method in "${methods[@]}"; do
        local total_latency=0
        local min_latency=999999
        local max_latency=0

        for ((i=0; i<iterations; i++)); do
            local start_ms
            start_ms=$(timestamp_ms)

            curl -s -X POST \
                -H "Content-Type: application/json" \
                -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":[],\"id\":1}" \
                "$RPC_URL" > /dev/null 2>&1 || true

            local latency
            latency=$(calculate_duration "$start_ms")

            total_latency=$((total_latency + latency))

            if [[ $latency -lt $min_latency ]]; then
                min_latency=$latency
            fi
            if [[ $latency -gt $max_latency ]]; then
                max_latency=$latency
            fi
        done

        local avg_latency=$((total_latency / iterations))

        BENCHMARK_RESULTS["${method}_avg"]=$avg_latency
        BENCHMARK_RESULTS["${method}_min"]=$min_latency
        BENCHMARK_RESULTS["${method}_max"]=$max_latency

        log_benchmark "rpc_${method}_avg" "$avg_latency" "ms"
        log_benchmark "rpc_${method}_min" "$min_latency" "ms"
        log_benchmark "rpc_${method}_max" "$max_latency" "ms"
    done
}

#==============================================================================
# Block Sync Speed Benchmark
#==============================================================================

benchmark_sync_speed() {
    echo "Running sync speed benchmark..."

    local duration_seconds=60
    local start_height
    local end_height

    # Get starting block height
    start_height=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$RPC_URL" 2>/dev/null | jq -r '.result // "0x0"' | sed 's/0x//')
    start_height=$((16#$start_height))

    echo "Monitoring sync for ${duration_seconds} seconds..."
    sleep $duration_seconds

    # Get ending block height
    end_height=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$RPC_URL" 2>/dev/null | jq -r '.result // "0x0"' | sed 's/0x//')
    end_height=$((16#$end_height))

    local blocks_synced=$((end_height - start_height))
    local blocks_per_second
    blocks_per_second=$(echo "scale=2; $blocks_synced / $duration_seconds" | bc)

    BENCHMARK_RESULTS["sync_blocks_per_sec"]=$blocks_per_second

    log_benchmark "sync_blocks_per_second" "$blocks_per_second" "blocks/s"
}

#==============================================================================
# Disk I/O Benchmarks
#==============================================================================

benchmark_disk_io() {
    echo "Running disk I/O benchmark..."

    local data_dir="${DATA_DIR:-/opt/xdc-node/mainnet/xdcchain}"

    if [[ ! -d "$data_dir" ]]; then
        echo "Warning: Data directory not found, skipping disk benchmark"
        return
    fi

    # Sequential write test
    local test_file="$data_dir/.benchmark_write_test"
    local write_start
    write_start=$(timestamp_ms)

    dd if=/dev/zero of="$test_file" bs=1M count=100 oflag=direct 2>/dev/null || true

    local write_duration
    write_duration=$(calculate_duration "$write_start")
    local write_speed
    write_speed=$(echo "scale=2; 100 * 1000 / $write_duration" | bc)

    rm -f "$test_file"

    # Sequential read test
    # Create test file first
    dd if=/dev/zero of="$test_file" bs=1M count=100 2>/dev/null || true

    local read_start
    read_start=$(timestamp_ms)

    dd if="$test_file" of=/dev/null bs=1M iflag=direct 2>/dev/null || true

    local read_duration
    read_duration=$(calculate_duration "$read_start")
    local read_speed
    read_speed=$(echo "scale=2; 100 * 1000 / $read_duration" | bc)

    rm -f "$test_file"

    BENCHMARK_RESULTS["disk_write_mbps"]=$write_speed
    BENCHMARK_RESULTS["disk_read_mbps"]=$read_speed

    log_benchmark "disk_write_speed" "$write_speed" "MB/s"
    log_benchmark "disk_read_speed" "$read_speed" "MB/s"
}

#==============================================================================
# Memory Usage Benchmark
#==============================================================================

benchmark_memory_usage() {
    echo "Running memory usage benchmark..."

    local sample_count=10
    local sample_interval=5
    local total_memory=0

    for ((i=0; i<sample_count; i++)); do
        local mem_usage
        mem_usage=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
        total_memory=$((total_memory + mem_usage))
        sleep $sample_interval
    done

    local avg_memory_usage=$((total_memory / sample_count))

    BENCHMARK_RESULTS["memory_usage_percent"]=$avg_memory_usage

    log_benchmark "memory_usage" "$avg_memory_usage" "percent"
}

#==============================================================================
# CPU Usage Benchmark
#==============================================================================

benchmark_cpu_usage() {
    echo "Running CPU usage benchmark..."

    local sample_count=10
    local sample_interval=5
    local total_cpu=0

    for ((i=0; i<sample_count; i++)); do
        local cpu_usage
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d',' -f1)
        total_cpu=$(echo "$total_cpu + $cpu_usage" | bc)
        sleep $sample_interval
    done

    local avg_cpu_usage
    avg_cpu_usage=$(echo "scale=1; $total_cpu / $sample_count" | bc)

    BENCHMARK_RESULTS["cpu_usage_percent"]=$avg_cpu_usage

    log_benchmark "cpu_usage" "$avg_cpu_usage" "percent"
}

#==============================================================================
# Network Throughput Benchmark
#==============================================================================

benchmark_network_throughput() {
    echo "Running network throughput benchmark..."

    # Check peer count and network stats
    local peer_count
    peer_count=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
        "$RPC_URL" 2>/dev/null | jq -r '.result // "0x0"' | sed 's/0x//')
    peer_count=$((16#$peer_count))

    BENCHMARK_RESULTS["peer_count"]=$peer_count

    log_benchmark "peer_count" "$peer_count" "peers"

    # Get network interface stats
    if command -v ifconfig >/dev/null 2>&1 || command -v ip >/dev/null 2>&1; then
        local interface
        interface=$(ip route | grep default | awk '{print $5}' | head -1)

        if [[ -n "$interface" ]]; then
            local rx_bytes_before tx_bytes_before
            rx_bytes_before=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo 0)
            tx_bytes_before=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo 0)

            sleep 10

            local rx_bytes_after tx_bytes_after
            rx_bytes_after=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null || echo 0)
            tx_bytes_after=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null || echo 0)

            local rx_mbps tx_mbps
            rx_mbps=$(echo "scale=2; ($rx_bytes_after - $rx_bytes_before) * 8 / 10 / 1000000" | bc)
            tx_mbps=$(echo "scale=2; ($tx_bytes_after - $tx_bytes_before) * 8 / 10 / 1000000" | bc)

            BENCHMARK_RESULTS["network_rx_mbps"]=$rx_mbps
            BENCHMARK_RESULTS["network_tx_mbps"]=$tx_mbps

            log_benchmark "network_rx" "$rx_mbps" "Mbps"
            log_benchmark "network_tx" "$tx_mbps" "Mbps"
        fi
    fi
}

#==============================================================================
# Report Generation
#==============================================================================

generate_report() {
    echo ""
    echo "========================================"
    echo "XDC Node Performance Benchmark Results"
    echo "========================================"
    echo ""

    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        echo "{"
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"benchmarks\": {"

        local first=true
        for key in "${!BENCHMARK_RESULTS[@]}"; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            echo -n "    \"$key\": ${BENCHMARK_RESULTS[$key]}"
        done
        echo ""
        echo "  }"
        echo "}"
    else
        printf "%-30s %15s\n" "Benchmark" "Value"
        echo "----------------------------------------------"
        for key in "${!BENCHMARK_RESULTS[@]}"; do
            printf "%-30s %15s\n" "$key" "${BENCHMARK_RESULTS[$key]}"
        done
    fi

    echo ""
    echo "Results logged to: $BENCHMARK_LOG"
}

#==============================================================================
# Main
#==============================================================================

main() {
    echo "XDC Node Performance Benchmark Suite"
    echo "====================================="
    echo ""

    # Create log directory
    mkdir -p "$(dirname "$BENCHMARK_LOG")"

    # Run benchmarks
    benchmark_rpc_latency
    benchmark_sync_speed
    benchmark_disk_io
    benchmark_memory_usage
    benchmark_cpu_usage
    benchmark_network_throughput

    # Generate report
    generate_report
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi