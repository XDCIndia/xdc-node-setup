#!/usr/bin/env bash

# Source utility functions
source "$(dirname "$0")/lib/utils.sh" || { echo "Failed to load utils"; exit 1; }
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }

#===============================================================================
# Chaos Engineering Test Suite for XDC Node Resilience
#
# Tests node resilience by simulating various failure scenarios:
# - Process kill (auto-restart)
# - Disk pressure (alerts)
# - Network disruption (peer recovery)
# - Resource exhaustion (CPU/memory)
#
# Usage:
#   ./chaos-test.sh                    # Run all tests
#   ./chaos-test.sh --test process     # Run specific test
#   ./chaos-test.sh --dry-run          # Show what would be done
#   ./chaos-test.sh --cleanup          # Clean up from previous runs
#
# IMPORTANT: Run in staging/test environment only!
#===============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/chaos-test-$(date +%Y%m%d-%H%M%S).log"
RPC_PORT="${RPC_PORT:-8545}"
P2P_PORT="${P2P_PORT:-30303}"
NODE_SERVICE="${NODE_SERVICE:-xdc-node}"
ALERT_CHECK_DELAY=120  # seconds to wait for alerts
RECOVERY_TIMEOUT=300   # seconds to wait for recovery

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Options
DRY_RUN=false
SPECIFIC_TEST=""
CLEANUP_ONLY=false
SKIP_CONFIRMATION=false

#===============================================================================
# Helper Functions
#===============================================================================

usage() {
    cat << EOF
Chaos Engineering Test Suite for XDC Nodes

Usage: $0 [OPTIONS]

Options:
    --test <name>       Run specific test only
                        (process, disk, network, cpu, memory)
    --dry-run           Show what would be done without executing
    --cleanup           Clean up from previous test runs
    --yes               Skip confirmation prompts
    -h, --help          Show this help message

Tests:
    process     Kill node process and verify auto-restart
    disk        Fill disk to 95% and verify alerts
    network     Block P2P port and verify peer recovery
    cpu         CPU stress test
    memory      Memory pressure test

Examples:
    $0                      # Run all tests
    $0 --test process       # Run process kill test only
    $0 --dry-run            # Preview all tests
    $0 --cleanup            # Clean up test artifacts

IMPORTANT: Run only in staging/test environments!

EOF
    exit 0
}

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}


info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

section() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}║ $1${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}" | tee -a "$LOG_FILE"
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
    
    # Check if node is running
    if ! systemctl is-active --quiet "$NODE_SERVICE"; then
        error "Node service '$NODE_SERVICE' is not running"
        exit 1
    fi
    
    # Check required tools
    local required_tools=(curl jq iptables stress-ng fallocate)
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            warn "Installing missing tool: $tool"
            apt-get install -y "$tool" 2>/dev/null || true
        fi
    done
    
    log "✓ Prerequisites check passed"
}

wait_for_node_ready() {
    local timeout="${1:-$RECOVERY_TIMEOUT}"
    local start_time=$(date +%s)
    
    info "Waiting for node to be ready (timeout: ${timeout}s)..."
    
    while true; do
        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -gt $timeout ]]; then
            return 1
        fi
        
        if curl -s -X POST "http://localhost:${RPC_PORT}" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            2>/dev/null | jq -e '.result' &>/dev/null; then
            return 0
        fi
        
        sleep 5
    done
}

check_alert_fired() {
    local alert_name="$1"
    
    # Check Prometheus alerts (if available)
    if curl -s "http://localhost:9090/api/v1/alerts" 2>/dev/null | jq -e ".data.alerts[] | select(.labels.alertname == \"$alert_name\")" &>/dev/null; then
        return 0
    fi
    
    # Check system logs for alert keywords
    if journalctl --since "5 minutes ago" | grep -qi "$alert_name\|alert\|warning"; then
        return 0
    fi
    
    return 1
}

record_result() {
    local test_name="$1"
    local status="$2"  # PASS or FAIL
    local details="${3:-}"
    
    ((TESTS_RUN++))
    
    if [[ "$status" == "PASS" ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}[PASS]${NC} $test_name" | tee -a "$LOG_FILE"
    else
        ((TESTS_FAILED++))
        echo -e "${RED}[FAIL]${NC} $test_name - $details" | tee -a "$LOG_FILE"
    fi
}

#===============================================================================
# Test 1: Process Kill (Auto-Restart)
#===============================================================================

test_process_kill() {
    section "Test: Process Kill & Auto-Restart"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would kill xdc-node process and verify systemd restarts it"
        return 0
    fi
    
    # Get initial PID
    local initial_pid
    initial_pid=$(pgrep -f "XDC\|erigon" | head -1 || echo "")
    
    if [[ -z "$initial_pid" ]]; then
        record_result "Process Kill" "FAIL" "Could not find node process"
        return 1
    fi
    
    info "Initial PID: $initial_pid"
    
    # Kill the process
    log "Killing node process..."
    kill -9 "$initial_pid" 2>/dev/null || true
    
    sleep 5
    
    # Verify systemd restarted it
    if ! systemctl is-active --quiet "$NODE_SERVICE"; then
        warn "Node not running, waiting for systemd restart..."
        sleep 30
    fi
    
    # Check new PID
    local new_pid
    new_pid=$(pgrep -f "XDC\|erigon" | head -1 || echo "")
    
    if [[ -n "$new_pid" && "$new_pid" != "$initial_pid" ]]; then
        log "Node restarted with new PID: $new_pid"
        
        # Wait for RPC to be ready
        if wait_for_node_ready 120; then
            record_result "Process Kill" "PASS"
        else
            record_result "Process Kill" "FAIL" "Node restarted but RPC not responding"
        fi
    else
        record_result "Process Kill" "FAIL" "Node did not restart automatically"
    fi
}

#===============================================================================
# Test 2: Disk Pressure (95% Full)
#===============================================================================

test_disk_pressure() {
    section "Test: Disk Pressure (95% Full)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would fill disk to 95% and verify alerts fire"
        return 0
    fi
    
    local test_file="/tmp/chaos-disk-test.tmp"
    
    # Get current usage
    local current_usage
    current_usage=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    
    if [[ $current_usage -gt 90 ]]; then
        warn "Disk already at ${current_usage}%, skipping test"
        record_result "Disk Pressure" "SKIP"
        return 0
    fi
    
    # Calculate how much to fill
    local available_kb
    available_kb=$(df / | awk 'NR==2 {print $4}')
    local target_usage=95
    local current_used_kb
    current_used_kb=$(df / | awk 'NR==2 {print $3}')
    local total_kb
    total_kb=$(df / | awk 'NR==2 {print $2}')
    
    local target_used_kb=$((total_kb * target_usage / 100))
    local fill_kb=$((target_used_kb - current_used_kb))
    
    if [[ $fill_kb -lt 0 ]]; then
        warn "Cannot calculate fill size, skipping test"
        record_result "Disk Pressure" "SKIP"
        return 0
    fi
    
    log "Creating ${fill_kb}KB test file to reach ${target_usage}% usage..."
    
    # Create large file
    fallocate -l "${fill_kb}K" "$test_file" 2>/dev/null || \
        dd if=/dev/zero of="$test_file" bs=1K count="$fill_kb" status=none
    
    # Verify new usage
    local new_usage
    new_usage=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    log "Disk usage now at ${new_usage}%"
    
    # Wait for alert
    info "Waiting ${ALERT_CHECK_DELAY}s for disk alert..."
    sleep "$ALERT_CHECK_DELAY"
    
    # Check if alert fired
    if check_alert_fired "DiskFull\|DiskSpaceLow\|disk"; then
        log "Disk alert detected!"
        record_result "Disk Pressure" "PASS"
    else
        warn "No disk alert detected within timeout"
        record_result "Disk Pressure" "FAIL" "Alert not fired"
    fi
    
    # Cleanup
    log "Cleaning up test file..."
    rm -f "$test_file"
    
    local final_usage
    final_usage=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    log "Disk usage restored to ${final_usage}%"
}

#===============================================================================
# Test 3: Network Disruption (Block P2P Port)
#===============================================================================

test_network_disruption() {
    section "Test: Network Disruption (P2P Port Block)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would block port ${P2P_PORT} and verify peer recovery after unblock"
        return 0
    fi
    
    # Get initial peer count
    local initial_peers
    initial_peers=$(curl -s -X POST "http://localhost:${RPC_PORT}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
        2>/dev/null | jq -r '.result' | xargs printf "%d" 2>/dev/null || echo "0")
    
    log "Initial peer count: $initial_peers"
    
    if [[ $initial_peers -eq 0 ]]; then
        warn "No peers connected initially, test may not be meaningful"
    fi
    
    # Block P2P port
    log "Blocking port ${P2P_PORT}..."
    iptables -A INPUT -p tcp --dport "$P2P_PORT" -j DROP
    iptables -A INPUT -p udp --dport "$P2P_PORT" -j DROP
    iptables -A OUTPUT -p tcp --dport "$P2P_PORT" -j DROP
    iptables -A OUTPUT -p udp --dport "$P2P_PORT" -j DROP
    
    # Wait for peers to drop
    info "Waiting 60s for peers to disconnect..."
    sleep 60
    
    # Check peer count dropped
    local blocked_peers
    blocked_peers=$(curl -s -X POST "http://localhost:${RPC_PORT}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
        2>/dev/null | jq -r '.result' | xargs printf "%d" 2>/dev/null || echo "0")
    
    log "Peer count during block: $blocked_peers"
    
    # Unblock port
    log "Unblocking port ${P2P_PORT}..."
    iptables -D INPUT -p tcp --dport "$P2P_PORT" -j DROP 2>/dev/null || true
    iptables -D INPUT -p udp --dport "$P2P_PORT" -j DROP 2>/dev/null || true
    iptables -D OUTPUT -p tcp --dport "$P2P_PORT" -j DROP 2>/dev/null || true
    iptables -D OUTPUT -p udp --dport "$P2P_PORT" -j DROP 2>/dev/null || true
    
    # Wait for peer recovery
    info "Waiting ${RECOVERY_TIMEOUT}s for peer recovery..."
    local recovery_start=$(date +%s)
    local recovered=false
    
    while true; do
        local elapsed=$(($(date +%s) - recovery_start))
        if [[ $elapsed -gt $RECOVERY_TIMEOUT ]]; then
            break
        fi
        
        local current_peers
        current_peers=$(curl -s -X POST "http://localhost:${RPC_PORT}" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
            2>/dev/null | jq -r '.result' | xargs printf "%d" 2>/dev/null || echo "0")
        
        if [[ $current_peers -gt 0 ]]; then
            log "Peers recovered: $current_peers (took ${elapsed}s)"
            recovered=true
            break
        fi
        
        sleep 10
    done
    
    if [[ "$recovered" == "true" ]]; then
        record_result "Network Disruption" "PASS"
    else
        record_result "Network Disruption" "FAIL" "Peers did not recover within timeout"
    fi
}

#===============================================================================
# Test 4: CPU Stress
#===============================================================================

test_cpu_stress() {
    section "Test: CPU Stress"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would run CPU stress for 60s and verify node remains responsive"
        return 0
    fi
    
    # Check if stress-ng is available
    if ! command -v stress-ng &> /dev/null; then
        apt-get install -y stress-ng 2>/dev/null || {
            warn "stress-ng not available, skipping test"
            record_result "CPU Stress" "SKIP"
            return 0
        }
    fi
    
    local cpu_count
    cpu_count=$(nproc)
    
    log "Starting CPU stress test (${cpu_count} CPUs for 60s)..."
    
    # Run stress in background
    stress-ng --cpu "$cpu_count" --cpu-load 90 --timeout 60s &
    local stress_pid=$!
    
    # Check node responsiveness during stress
    local responsive_count=0
    local check_count=6
    
    for i in $(seq 1 $check_count); do
        sleep 10
        if curl -s -X POST "http://localhost:${RPC_PORT}" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            --max-time 5 2>/dev/null | jq -e '.result' &>/dev/null; then
            ((responsive_count++))
            info "Check $i/$check_count: Node responding"
        else
            warn "Check $i/$check_count: Node not responding"
        fi
    done
    
    # Wait for stress to complete
    wait $stress_pid 2>/dev/null || true
    
    # Evaluate results
    local pass_threshold=$((check_count * 80 / 100))  # 80% must pass
    if [[ $responsive_count -ge $pass_threshold ]]; then
        record_result "CPU Stress" "PASS"
    else
        record_result "CPU Stress" "FAIL" "Node unresponsive $((check_count - responsive_count))/$check_count times"
    fi
}

#===============================================================================
# Test 5: Memory Pressure
#===============================================================================

test_memory_pressure() {
    section "Test: Memory Pressure"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would allocate 80% of free memory and verify node remains stable"
        return 0
    fi
    
    # Check if stress-ng is available
    if ! command -v stress-ng &> /dev/null; then
        apt-get install -y stress-ng 2>/dev/null || {
            warn "stress-ng not available, skipping test"
            record_result "Memory Pressure" "SKIP"
            return 0
        }
    fi
    
    # Get free memory
    local free_mem_mb
    free_mem_mb=$(free -m | awk '/^Mem:/ {print $7}')
    local stress_mem_mb=$((free_mem_mb * 70 / 100))  # Use 70% of free
    
    log "Starting memory pressure test (${stress_mem_mb}MB for 60s)..."
    
    # Run memory stress in background
    stress-ng --vm 2 --vm-bytes "${stress_mem_mb}M" --timeout 60s &
    local stress_pid=$!
    
    # Check node responsiveness during stress
    local responsive_count=0
    local check_count=6
    
    for i in $(seq 1 $check_count); do
        sleep 10
        if curl -s -X POST "http://localhost:${RPC_PORT}" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
            --max-time 10 2>/dev/null | jq -e '.result' &>/dev/null; then
            ((responsive_count++))
            info "Check $i/$check_count: Node responding"
        else
            warn "Check $i/$check_count: Node not responding"
        fi
    done
    
    # Wait for stress to complete
    wait $stress_pid 2>/dev/null || true
    
    # Evaluate results
    local pass_threshold=$((check_count * 70 / 100))  # 70% must pass
    if [[ $responsive_count -ge $pass_threshold ]]; then
        record_result "Memory Pressure" "PASS"
    else
        record_result "Memory Pressure" "FAIL" "Node unresponsive $((check_count - responsive_count))/$check_count times"
    fi
}

#===============================================================================
# Cleanup Function
#===============================================================================

cleanup() {
    section "Cleanup"
    
    log "Cleaning up test artifacts..."
    
    # Remove test files
    rm -f /tmp/chaos-disk-test.tmp
    
    # Remove iptables rules (in case test was interrupted)
    iptables -D INPUT -p tcp --dport "$P2P_PORT" -j DROP 2>/dev/null || true
    iptables -D INPUT -p udp --dport "$P2P_PORT" -j DROP 2>/dev/null || true
    iptables -D OUTPUT -p tcp --dport "$P2P_PORT" -j DROP 2>/dev/null || true
    iptables -D OUTPUT -p udp --dport "$P2P_PORT" -j DROP 2>/dev/null || true
    
    # Kill any remaining stress processes
    pkill -f stress-ng 2>/dev/null || true
    
    log "Cleanup complete"
}

#===============================================================================
# Summary Report
#===============================================================================

print_summary() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                   Chaos Test Summary                           ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Tests Run:    ${TESTS_RUN}"
    echo -e "  ${GREEN}Passed:${NC}       ${TESTS_PASSED}"
    echo -e "  ${RED}Failed:${NC}       ${TESTS_FAILED}"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 && $TESTS_RUN -gt 0 ]]; then
        echo -e "  ${GREEN}✅ All tests passed!${NC}"
    elif [[ $TESTS_RUN -eq 0 ]]; then
        echo -e "  ${YELLOW}⚠️  No tests were run${NC}"
    else
        echo -e "  ${RED}❌ Some tests failed. Review logs: $LOG_FILE${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
}

#===============================================================================
# Main
#===============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --test)
                SPECIFIC_TEST="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --cleanup)
                CLEANUP_ONLY=true
                shift
                ;;
            --yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         Chaos Engineering Test Suite for XDC Nodes             ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Cleanup only mode
    if [[ "$CLEANUP_ONLY" == "true" ]]; then
        cleanup
        exit 0
    fi
    
    # Warning
    if [[ "$DRY_RUN" == "false" && "$SKIP_CONFIRMATION" == "false" ]]; then
        echo -e "${RED}⚠️  WARNING: This will intentionally disrupt your XDC node!${NC}"
        echo -e "${YELLOW}Only run in staging/test environments.${NC}"
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            echo "Aborted."
            exit 0
        fi
    fi
    
    # Setup trap for cleanup
    trap cleanup EXIT
    
    # Prerequisites
    if [[ "$DRY_RUN" == "false" ]]; then
        check_prerequisites
    fi
    
    # Run tests
    if [[ -z "$SPECIFIC_TEST" || "$SPECIFIC_TEST" == "process" ]]; then
        test_process_kill
    fi
    
    if [[ -z "$SPECIFIC_TEST" || "$SPECIFIC_TEST" == "disk" ]]; then
        test_disk_pressure
    fi
    
    if [[ -z "$SPECIFIC_TEST" || "$SPECIFIC_TEST" == "network" ]]; then
        test_network_disruption
    fi
    
    if [[ -z "$SPECIFIC_TEST" || "$SPECIFIC_TEST" == "cpu" ]]; then
        test_cpu_stress
    fi
    
    if [[ -z "$SPECIFIC_TEST" || "$SPECIFIC_TEST" == "memory" ]]; then
        test_memory_pressure
    fi
    
    # Print summary
    print_summary
    
    # Exit code
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
