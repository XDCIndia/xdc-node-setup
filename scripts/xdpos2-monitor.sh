#!/bin/bash
#==============================================================================
# XDPoS 2.0 Consensus Monitoring
# Issues: #500 - Epoch Transition Monitoring, #501 - Vote and QC Monitoring
#==============================================================================

set -euo pipefail

# Configuration
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
LOG_FILE="${LOG_FILE:-/var/log/xdc-xdpos2.log}"
CHECK_INTERVAL="${CHECK_INTERVAL:-15}"
EPOCH_SIZE="${EPOCH_SIZE:-900}"  # XDC mainnet epoch size

# Alert configuration
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
ALERT_TELEGRAM_BOT="${ALERT_TELEGRAM_BOT:-}"
ALERT_TELEGRAM_CHAT="${ALERT_TELEGRAM_CHAT:-}"

# State tracking
LAST_EPOCH=0
LAST_ROUND=0
CONSECUTIVE_GAPS=0
MAX_CONSECUTIVE_GAPS=3

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

#==============================================================================
# Logging
#==============================================================================
log() {
    local level="$1"
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $*" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "${YELLOW}$@${NC}"; }
log_error() { log "ERROR" "${RED}$@${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$@${NC}"; }

#==============================================================================
# RPC Functions
#==============================================================================
rpc_call() {
    local method="$1"
    local params="${2:-[]}"
    
    curl -s --max-time 10 -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" 2>/dev/null
}

get_block_number() {
    local response=$(rpc_call "eth_blockNumber")
    local hex=$(echo "$response" | jq -r '.result // "0x0"')
    printf "%d" "$hex" 2>/dev/null || echo "0"
}

get_block() {
    local block_num="$1"
    local hex_block=$(printf "0x%x" "$block_num")
    rpc_call "eth_getBlockByNumber" "[\"$hex_block\", true]" | jq -r '.result'
}

get_block_extra() {
    local block_num="$1"
    local hex_block=$(printf "0x%x" "$block_num")
    local block=$(rpc_call "eth_getBlockByNumber" "[\"$hex_block\", false]")
    echo "$block" | jq -r '.result.extraData // ""'
}

#==============================================================================
# XDPoS 2.0 Parsing
#==============================================================================
parse_epoch_info() {
    local block_num="$1"
    
    # Epoch number is block_num / EPOCH_SIZE
    local epoch=$((block_num / EPOCH_SIZE))
    local epoch_block=$((epoch * EPOCH_SIZE))
    local blocks_in_epoch=$((block_num - epoch_block))
    local blocks_to_next=$((EPOCH_SIZE - blocks_in_epoch))
    
    echo "$epoch|$epoch_block|$blocks_in_epoch|$blocks_to_next"
}

parse_round_info() {
    local extra_data="$1"
    
    # XDPoS 2.0 extra data format (simplified):
    # First 32 bytes: vanity
    # Next bytes: XDPOS2 data including round, QC, TC
    
    # For this implementation, we extract round from block header
    # The actual parsing would need the full XDPoS 2.0 spec
    
    # Simplified: extract round from extra data if available
    local round=0
    if [[ ${#extra_data} -gt 66 ]]; then
        # Round is typically at a specific offset
        # This is a placeholder - actual implementation depends on exact format
        round=$(echo "$extra_data" | cut -c67-74 | xargs -I {} printf "%d" "0x{}" 2>/dev/null || echo "0")
    fi
    
    echo "$round"
}

check_qc_in_block() {
    local block_num="$1"
    local extra=$(get_block_extra "$block_num")
    
    # Check if QC (Quorum Certificate) is present
    # QC presence indicates successful vote aggregation
    local has_qc="false"
    if [[ ${#extra} -gt 200 ]]; then
        # QC is present if extra data is long enough
        has_qc="true"
    fi
    
    echo "$has_qc"
}

check_timeout_certificate() {
    local block_num="$1"
    local extra=$(get_block_extra "$block_num")
    
    # TC (Timeout Certificate) indicates round timeout
    # This is a simplified check
    local has_tc="false"
    # In actual implementation, parse extra data for TC signature
    echo "$has_tc"
}

#==============================================================================
# Monitoring Functions
#==============================================================================
monitor_epoch_transition() {
    local block_num="$1"
    local epoch_info=$(parse_epoch_info "$block_num")
    
    local epoch=$(echo "$epoch_info" | cut -d'|' -f1)
    local epoch_block=$(echo "$epoch_info" | cut -d'|' -f2)
    local blocks_in=$(echo "$epoch_info" | cut -d'|' -f3)
    local blocks_to=$(echo "$epoch_info" | cut -d'|' -f4)
    
    # Check for epoch transition
    if [[ $epoch -ne $LAST_EPOCH && $LAST_EPOCH -ne 0 ]]; then
        log_success "=== EPOCH TRANSITION ==="
        log_info "New Epoch: $epoch (from $LAST_EPOCH)"
        log_info "Epoch Block: $epoch_block"
        
        # Alert on epoch transition
        send_alert "epoch_transition" "info" "Epoch transition to $epoch at block $epoch_block"
    fi
    
    LAST_EPOCH=$epoch
    
    # Progress update
    local progress=$((blocks_in * 100 / EPOCH_SIZE))
    echo "epoch=$epoch|progress=${progress}%|blocks_to_next=$blocks_to"
}

monitor_vote_formation() {
    local block_num="$1"
    
    # Check last N blocks for vote/QC presence
    local qc_count=0
    local gap_count=0
    local check_range=10
    
    for ((i=0; i<check_range; i++)); do
        local check_block=$((block_num - i))
        [[ $check_block -lt 1 ]] && continue
        
        local has_qc=$(check_qc_in_block "$check_block")
        if [[ "$has_qc" == "true" ]]; then
            ((qc_count++))
        else
            ((gap_count++))
        fi
    done
    
    local qc_rate=$((qc_count * 100 / check_range))
    
    # Alert if QC formation rate is low
    if [[ $qc_rate -lt 70 ]]; then
        log_warn "Low QC formation rate: ${qc_rate}% (last $check_range blocks)"
        ((CONSECUTIVE_GAPS++))
        
        if [[ $CONSECUTIVE_GAPS -ge $MAX_CONSECUTIVE_GAPS ]]; then
            send_alert "qc_formation" "warning" "Low QC formation rate: ${qc_rate}% for $CONSECUTIVE_GAPS consecutive checks"
            CONSECUTIVE_GAPS=0
        fi
    else
        CONSECUTIVE_GAPS=0
    fi
    
    echo "qc_rate=${qc_rate}%|qc_count=$qc_count|gap_count=$gap_count"
}

monitor_block_gaps() {
    local current_block="$1"
    
    # Get last few blocks to check for gaps
    local gap_blocks=()
    local prev_block=$current_block
    
    for ((i=1; i<=5; i++)); do
        local check_block=$((current_block - i))
        [[ $check_block -lt 1 ]] && continue
        
        local block_data=$(get_block "$check_block")
        local block_time=$(echo "$block_data" | jq -r '.timestamp // "0x0"')
        block_time=$(printf "%d" "$block_time" 2>/dev/null || echo "0")
        
        local prev_data=$(get_block "$((check_block + 1))")
        local prev_time=$(echo "$prev_data" | jq -r '.timestamp // "0x0"')
        prev_time=$(printf "%d" "$prev_time" 2>/dev/null || echo "0")
        
        local time_diff=$((prev_time - block_time))
        
        # XDC block time is ~2 seconds
        if [[ $time_diff -gt 10 ]]; then
            gap_blocks+=("$check_block:${time_diff}s")
            log_warn "Block gap detected at $check_block (${time_diff}s between blocks)"
        fi
    done
    
    if [[ ${#gap_blocks[@]} -gt 0 ]]; then
        echo "gaps=${#gap_blocks[@]}|blocks=${gap_blocks[*]}"
    else
        echo "gaps=0|blocks=none"
    fi
}

monitor_validator_activity() {
    local current_block="$1"
    
    # Track which validators are producing blocks
    local validators=()
    local sample_size=10
    
    for ((i=0; i<sample_size; i++)); do
        local check_block=$((current_block - i))
        [[ $check_block -lt 1 ]] && continue
        
        local block_data=$(get_block "$check_block")
        local miner=$(echo "$block_data" | jq -r '.miner // ""')
        
        if [[ -n "$miner" ]]; then
            validators+=("$miner")
        fi
    done
    
    # Count unique validators
    local unique_count=$(printf '%s\n' "${validators[@]}" | sort -u | wc -l)
    
    echo "unique_validators=$unique_count|sample_size=$sample_size"
}

#==============================================================================
# Alerting
#==============================================================================
send_alert() {
    local alert_type="$1"
    local severity="$2"
    local message="$3"
    
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Webhook
    if [[ -n "$ALERT_WEBHOOK" ]]; then
        curl -s -X POST "$ALERT_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{
                \"type\": \"xdpos2_$alert_type\",
                \"severity\": \"$severity\",
                \"message\": \"$message\",
                \"timestamp\": \"$timestamp\"
            }" 2>/dev/null || true
    fi
    
    # Telegram
    if [[ -n "$ALERT_TELEGRAM_BOT" && -n "$ALERT_TELEGRAM_CHAT" ]]; then
        local emoji="🔵"
        [[ "$severity" == "warning" ]] && emoji="🟡"
        [[ "$severity" == "critical" ]] && emoji="🔴"
        
        curl -s -X POST "https://api.telegram.org/bot$ALERT_TELEGRAM_BOT/sendMessage" \
            -d chat_id="$ALERT_TELEGRAM_CHAT" \
            -d text="$emoji XDPoS 2.0: $message" \
            -d parse_mode="HTML" 2>/dev/null || true
    fi
}

#==============================================================================
# Main Monitoring Loop
#==============================================================================
run_check() {
    local block_num=$(get_block_number)
    
    if [[ $block_num -eq 0 ]]; then
        log_error "Cannot get block number from RPC"
        return 1
    fi
    
    log_info "=== XDPoS 2.0 Check at Block $block_num ==="
    
    # Epoch monitoring
    local epoch_status=$(monitor_epoch_transition "$block_num")
    log_info "Epoch: $epoch_status"
    
    # Vote/QC monitoring
    local vote_status=$(monitor_vote_formation "$block_num")
    log_info "Votes: $vote_status"
    
    # Block gap monitoring
    local gap_status=$(monitor_block_gaps "$block_num")
    log_info "Gaps: $gap_status"
    
    # Validator activity
    local validator_status=$(monitor_validator_activity "$block_num")
    log_info "Validators: $validator_status"
    
    echo ""
}

monitor_loop() {
    log_info "Starting XDPoS 2.0 consensus monitoring..."
    log_info "RPC: $RPC_URL"
    log_info "Interval: ${CHECK_INTERVAL}s"
    log_info "Epoch Size: $EPOCH_SIZE blocks"
    echo ""
    
    while true; do
        run_check || true
        sleep "$CHECK_INTERVAL"
    done
}

#==============================================================================
# CLI
#==============================================================================
show_help() {
    cat << EOF
XDPoS 2.0 Consensus Monitoring

USAGE:
    $0 [COMMAND]

COMMANDS:
    check       Run a single monitoring check
    monitor     Run continuous monitoring
    epoch       Show current epoch info
    help        Show this help

ENVIRONMENT:
    RPC_URL         RPC endpoint (default: http://127.0.0.1:8545)
    CHECK_INTERVAL  Seconds between checks (default: 15)
    EPOCH_SIZE      Blocks per epoch (default: 900)
    ALERT_WEBHOOK   Webhook URL for alerts
    ALERT_TELEGRAM_BOT    Telegram bot token
    ALERT_TELEGRAM_CHAT   Telegram chat ID

EXAMPLES:
    # Single check
    $0 check

    # Continuous monitoring
    $0 monitor

    # Show epoch info
    $0 epoch

EOF
}

show_epoch() {
    local block_num=$(get_block_number)
    local epoch_info=$(parse_epoch_info "$block_num")
    
    local epoch=$(echo "$epoch_info" | cut -d'|' -f1)
    local epoch_block=$(echo "$epoch_info" | cut -d'|' -f2)
    local blocks_in=$(echo "$epoch_info" | cut -d'|' -f3)
    local blocks_to=$(echo "$epoch_info" | cut -d'|' -f4)
    
    echo "=== XDPoS 2.0 Epoch Info ==="
    echo ""
    echo "Current Block:    $block_num"
    echo "Current Epoch:    $epoch"
    echo "Epoch Start:      $epoch_block"
    echo "Blocks in Epoch:  $blocks_in / $EPOCH_SIZE"
    echo "Progress:         $((blocks_in * 100 / EPOCH_SIZE))%"
    echo "Blocks to Next:   $blocks_to"
    echo ""
}

main() {
    local command="${1:-help}"
    
    mkdir -p "$(dirname "$LOG_FILE")"
    
    case "$command" in
        check)
            run_check
            ;;
        monitor)
            monitor_loop
            ;;
        epoch)
            show_epoch
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
