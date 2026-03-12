#!/bin/bash
#==============================================================================
# Multi-Client Block Divergence Detection & Alerting
# Issue: #488 - Detect when different XDC clients have divergent blocks
#==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-/etc/xdc-node/divergence.conf}"
LOG_FILE="${LOG_FILE:-/var/log/xdc-divergence.log}"

# Default configuration
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
DIVERGENCE_THRESHOLD="${DIVERGENCE_THRESHOLD:-100}"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
ALERT_TELEGRAM_BOT="${ALERT_TELEGRAM_BOT:-}"
ALERT_TELEGRAM_CHAT="${ALERT_TELEGRAM_CHAT:-}"

# Client RPC endpoints
GETH_RPC="${GETH_RPC:-http://127.0.0.1:8545}"
ERIGON_RPC="${ERIGON_RPC:-http://127.0.0.1:8546}"
NM_RPC="${NM_RPC:-http://127.0.0.1:8547}"
RETH_RPC="${RETH_RPC:-http://127.0.0.1:8548}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

#==============================================================================
# Logging
#==============================================================================
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "${YELLOW}$@${NC}"; }
log_error() { log "ERROR" "${RED}$@${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$@${NC}"; }

#==============================================================================
# RPC Functions
#==============================================================================
rpc_call() {
    local url="$1"
    local method="$2"
    local params="${3:-[]}"
    
    local response=$(curl -s --max-time 5 -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" 2>/dev/null)
    
    echo "$response"
}

get_block_number() {
    local url="$1"
    local response=$(rpc_call "$url" "eth_blockNumber")
    local hex=$(echo "$response" | jq -r '.result // "0x0"')
    printf "%d" "$hex" 2>/dev/null || echo "0"
}

get_block_hash() {
    local url="$1"
    local block_number="$2"
    local hex_block=$(printf "0x%x" "$block_number")
    local response=$(rpc_call "$url" "eth_getBlockByNumber" "[\"$hex_block\", false]")
    echo "$response" | jq -r '.result.hash // ""'
}

get_client_status() {
    local name="$1"
    local url="$2"
    
    local block=$(get_block_number "$url")
    local peers=$(rpc_call "$url" "net_peerCount" | jq -r '.result // "0x0"')
    local peer_count=$(printf "%d" "$peers" 2>/dev/null || echo "0")
    
    if [[ $block -gt 0 ]]; then
        echo "$name|$block|$peer_count|online"
    else
        echo "$name|0|0|offline"
    fi
}

#==============================================================================
# Divergence Detection
#==============================================================================
detect_divergence() {
    log_info "Starting divergence check..."
    
    # Get status from all clients
    local clients=()
    local max_block=0
    local online_count=0
    
    # Check each client
    for client_info in "geth:$GETH_RPC" "erigon:$ERIGON_RPC" "nethermind:$NM_RPC" "reth:$RETH_RPC"; do
        local name="${client_info%%:*}"
        local url="${client_info#*:}"
        
        local status=$(get_client_status "$name" "$url")
        clients+=("$status")
        
        local block=$(echo "$status" | cut -d'|' -f2)
        local state=$(echo "$status" | cut -d'|' -f4)
        
        if [[ "$state" == "online" ]]; then
            ((online_count++))
            [[ $block -gt $max_block ]] && max_block=$block
        fi
    done
    
    # Need at least 2 online clients to compare
    if [[ $online_count -lt 2 ]]; then
        log_warn "Less than 2 clients online, skipping divergence check"
        return 0
    fi
    
    log_info "Found $online_count online clients, max block: $max_block"
    
    # Find common block height to compare (min of all online clients minus safety margin)
    local compare_blocks=()
    for status in "${clients[@]}"; do
        local block=$(echo "$status" | cut -d'|' -f2)
        local state=$(echo "$status" | cut -d'|' -f4)
        if [[ "$state" == "online" && $block -gt 0 ]]; then
            compare_blocks+=($block)
        fi
    done
    
    # Sort and get minimum
    local min_block=$(printf '%s\n' "${compare_blocks[@]}" | sort -n | head -1)
    local compare_block=$((min_block - 10)) # Safety margin of 10 blocks
    
    if [[ $compare_block -lt 1 ]]; then
        log_warn "Blocks too low for comparison"
        return 0
    fi
    
    log_info "Comparing block hashes at height $compare_block"
    
    # Get block hashes from all online clients
    local hashes=()
    for client_info in "geth:$GETH_RPC" "erigon:$ERIGON_RPC" "nethermind:$NM_RPC" "reth:$RETH_RPC"; do
        local name="${client_info%%:*}"
        local url="${client_info#*:}"
        
        local block=$(get_block_number "$url")
        if [[ $block -ge $compare_block ]]; then
            local hash=$(get_block_hash "$url" "$compare_block")
            if [[ -n "$hash" && "$hash" != "null" ]]; then
                hashes+=("$name:$hash")
                log_info "$name at block $compare_block: ${hash:0:18}..."
            fi
        fi
    done
    
    # Check for divergence
    local unique_hashes=$(printf '%s\n' "${hashes[@]}" | cut -d: -f2 | sort -u | wc -l)
    
    if [[ $unique_hashes -gt 1 ]]; then
        log_error "DIVERGENCE DETECTED at block $compare_block!"
        log_error "Found $unique_hashes different block hashes:"
        for h in "${hashes[@]}"; do
            log_error "  $h"
        done
        
        # Send alerts
        send_divergence_alert "$compare_block" "${hashes[@]}"
        return 1
    else
        log_success "No divergence detected at block $compare_block"
        return 0
    fi
}

#==============================================================================
# Alerting
#==============================================================================
send_divergence_alert() {
    local block="$1"
    shift
    local hashes=("$@")
    
    local message="🚨 BLOCK DIVERGENCE DETECTED\n\nBlock: $block\n\nHashes:"
    for h in "${hashes[@]}"; do
        message+="\n• $h"
    done
    message+="\n\nTimestamp: $(date '+%Y-%m-%d %H:%M:%S UTC')"
    
    # Webhook alert
    if [[ -n "$ALERT_WEBHOOK" ]]; then
        log_info "Sending webhook alert..."
        curl -s -X POST "$ALERT_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{
                \"type\": \"divergence\",
                \"severity\": \"critical\",
                \"block\": $block,
                \"hashes\": $(printf '%s\n' "${hashes[@]}" | jq -R . | jq -s .),
                \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
            }" 2>/dev/null || log_warn "Webhook failed"
    fi
    
    # Telegram alert
    if [[ -n "$ALERT_TELEGRAM_BOT" && -n "$ALERT_TELEGRAM_CHAT" ]]; then
        log_info "Sending Telegram alert..."
        curl -s -X POST "https://api.telegram.org/bot$ALERT_TELEGRAM_BOT/sendMessage" \
            -d chat_id="$ALERT_TELEGRAM_CHAT" \
            -d text="$message" \
            -d parse_mode="HTML" 2>/dev/null || log_warn "Telegram failed"
    fi
}

#==============================================================================
# Monitoring Mode
#==============================================================================
monitor_loop() {
    log_info "Starting continuous divergence monitoring..."
    log_info "Check interval: ${CHECK_INTERVAL}s"
    
    while true; do
        detect_divergence || true
        sleep "$CHECK_INTERVAL"
    done
}

#==============================================================================
# CLI Interface
#==============================================================================
show_help() {
    cat << EOF
Multi-Client Block Divergence Detection

USAGE:
    $0 [COMMAND]

COMMANDS:
    check       Run a single divergence check
    monitor     Run continuous monitoring
    status      Show status of all clients
    help        Show this help

ENVIRONMENT:
    GETH_RPC        Geth RPC URL (default: http://127.0.0.1:8545)
    ERIGON_RPC      Erigon RPC URL (default: http://127.0.0.1:8546)
    NM_RPC          Nethermind RPC URL (default: http://127.0.0.1:8547)
    RETH_RPC        Reth RPC URL (default: http://127.0.0.1:8548)
    CHECK_INTERVAL  Seconds between checks (default: 60)
    ALERT_WEBHOOK   Webhook URL for alerts
    ALERT_TELEGRAM_BOT    Telegram bot token
    ALERT_TELEGRAM_CHAT   Telegram chat ID

EXAMPLES:
    # Single check
    $0 check

    # Continuous monitoring
    $0 monitor

    # Show all client status
    $0 status

EOF
}

show_status() {
    echo "=== XDC Multi-Client Status ==="
    echo ""
    printf "%-15s %-12s %-8s %-10s\n" "CLIENT" "BLOCK" "PEERS" "STATUS"
    printf '%.0s-' {1..50}; echo ""
    
    for client_info in "geth:$GETH_RPC" "erigon:$ERIGON_RPC" "nethermind:$NM_RPC" "reth:$RETH_RPC"; do
        local name="${client_info%%:*}"
        local url="${client_info#*:}"
        local status=$(get_client_status "$name" "$url")
        
        local block=$(echo "$status" | cut -d'|' -f2)
        local peers=$(echo "$status" | cut -d'|' -f3)
        local state=$(echo "$status" | cut -d'|' -f4)
        
        local state_icon="✅"
        [[ "$state" == "offline" ]] && state_icon="❌"
        
        printf "%-15s %-12s %-8s %s %s\n" "$name" "$block" "$peers" "$state_icon" "$state"
    done
    echo ""
}

#==============================================================================
# Main
#==============================================================================
main() {
    local command="${1:-help}"
    
    mkdir -p "$(dirname "$LOG_FILE")"
    
    case "$command" in
        check)
            detect_divergence
            ;;
        monitor)
            monitor_loop
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
