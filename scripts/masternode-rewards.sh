#!/bin/bash

# Source shared logging library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/logging.sh" 2>/dev/null || source "$(dirname "$0")/lib/logging.sh" || { echo "Error: Cannot find lib/logging.sh" >&2; exit 1; }


# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }
# XDC Masternode Rewards Analytics System
# XDC Masternode Rewards Analytics System
# Tracks historical rewards, calculates APY, and provides export capabilities
# Author: anilcinchawale <anil24593@gmail.com>

set -euo pipefail

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
XDC_STATE_DIR="${XDC_STATE_DIR:-${XDC_DATA:-/root/xdcchain}/.state}"
REWARD_DB="${XDC_STATE_DIR}/rewards.db"
LOG_DIR="/var/log/xdc-node"
REWARD_LOG="${LOG_DIR}/rewards.log"

# XDC Constants
MASTERNODE_CONTRACT="0x0000000000000000000000000000000000000088"
MIN_STAKE=10000000  # 10 million XDC
BLOCK_TIME=2        # 2 seconds per block
BLOCKS_PER_DAY=$((86400 / BLOCK_TIME))
EXPECTED_APY=5.5    # Expected APY in percentage

# Source libraries
source "${LIB_DIR}/rewards-db.sh" 2>/dev/null || true
source "${LIB_DIR}/notify.sh" 2>/dev/null || true

# Ensure directories exist
ensure_directories() {
    if [[ ! -d "$LOG_DIR" ]]; then
        sudo mkdir -p "$LOG_DIR"
    fi
    if [[ ! -d "$XDC_STATE_DIR" ]]; then
        sudo mkdir -p "$XDC_STATE_DIR" 2>/dev/null || mkdir -p "$XDC_STATE_DIR"
    fi
}

# Logging functions



# Print banner
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         XDC Masternode Rewards Analytics System              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Show usage
show_usage() {
    echo -e "${BOLD}Usage:${NC} $0 [OPTIONS]"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --summary              Show current period reward summary"
    echo "  --history [DAYS]       Show reward history (default: 30 days)"
    echo "  --apy                  Calculate current APY"
    echo "  --missed               Show missed blocks report"
    echo "  --slashing             Show slashing events"
    echo "  --export FORMAT        Export data (json, csv, pdf)"
    echo "  --track                Track current reward cycle"
    echo "  --init-db              Initialize rewards database"
    echo "  --compare              Compare actual vs expected rewards"
    echo "  --alert-test           Test alert notifications"
    echo "  -h, --help             Show this help message"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  $0 --summary                          # Current summary"
    echo "  $0 --history --days 30                # Last 30 days"
    echo "  $0 --apy                              # Calculate APY"
    echo "  $0 --export csv                       # Export to CSV"
    echo "  $0 --missed                           # Missed blocks"
}

# Get XDC node RPC endpoint
get_rpc_endpoint() {
    local network="${XDC_NETWORK:-mainnet}"
    if [[ "$network" == "testnet" ]]; then
        echo "http://localhost:8546"
    else
        echo "http://localhost:8545"
    fi
}

# Make RPC call to XDC node
xdc_rpc_call() {
    local method="$1"
    local params="${2:-[]}"
    local endpoint
    endpoint=$(get_rpc_endpoint)
    
    local response
    if ! response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        "$endpoint" 2>/dev/null); then
        echo ""
        return 1
    fi
    
    echo "$response"
}

# Get current block number
get_current_block() {
    local response
    response=$(xdc_rpc_call "eth_blockNumber")
    if [[ -n "$response" ]]; then
        echo "$response" | jq -r '.result' 2>/dev/null | sed 's/0x//' | xargs -I {} printf '%d\n' "0x{}" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Get masternode info for an address
get_masternode_info() {
    local address="${1:-}"
    
    if [[ -z "$address" ]]; then
        # Try to get from environment or config
        address="${MASTERNODE_ADDRESS:-}"
    fi
    
    if [[ -z "$address" ]]; then
        log_error "No masternode address provided"
        return 1
    fi
    
    # Query masternode contract
    local data="0x${address:2}"
    local response
    response=$(xdc_rpc_call "eth_call" '[{"to":"'$MASTERNODE_CONTRACT'","data":"'$data'"}, "latest"]')
    
    echo "$response"
}

# Get reward events from logs
get_reward_events() {
    local from_block="${1:-0}"
    local to_block="${2:-latest}"
    local masternode_addr="${3:-}"
    
    # Reward event signature: RewardReceived(address indexed masternode, uint256 amount, uint256 blockNumber)
    local topic="0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925"
    
    local params
    if [[ -n "$masternode_addr" ]]; then
        local padded_addr="0x000000000000000000000000${masternode_addr:2}"
        params="[{"""fromBlock""":"$from_block","""toBlock""":"$to_block","""address""":"$MASTERNODE_CONTRACT","""topics""":["$topic","$padded_addr"]}]"
    else
        params="[{"""fromBlock""":"$from_block","""toBlock""":"$to_block","""address""":"$MASTERNODE_CONTRACT","""topics""":["$topic"]}]"
    fi
    
    local response
    response=$(xdc_rpc_call "eth_getLogs" "$params")
    
    echo "$response"
}

# Calculate APY from rewards
calculate_apy() {
    local days="${1:-30}"
    local stake_amount="${2:-$MIN_STAKE}"
    
    log_info "Calculating APY based on last $days days..."
    
    # Get rewards from database
    local total_rewards=0
    if [[ -f "$REWARD_DB" ]]; then
        total_rewards=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(SUM(amount), 0) FROM rewards WHERE timestamp >= datetime('now', '-$days days')" 2>/dev/null || echo "0")
    fi
    
    # Convert from wei to XDC if needed (assuming stored in XDC)
    if (( $(echo "$total_rewards < 1" | bc -l 2>/dev/null || echo "0") )); then
        # Likely in wei, convert
        total_rewards=$(echo "scale=8; $total_rewards / 1000000000000000000" | bc 2>/dev/null || echo "0")
    fi
    
    # Calculate APY: (rewards / stake) * (365 / days) * 100
    local period_return
    period_return=$(echo "scale=8; $total_rewards / $stake_amount" | bc 2>/dev/null || echo "0")
    
    local annualized_return
    annualized_return=$(echo "scale=8; $period_return * (365 / $days)" | bc 2>/dev/null || echo "0")
    
    local apy
    apy=$(echo "scale=2; $annualized_return * 100" | bc 2>/dev/null || echo "0")
    
    # Output results
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                    APY CALCULATION                           ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Period Analyzed:    ${CYAN}${days} days${NC}"
    echo -e "  Stake Amount:       ${CYAN}${stake_amount} XDC${NC}"
    echo -e "  Total Rewards:      ${GREEN}${total_rewards} XDC${NC}"
    echo -e "  Period Return:      ${CYAN}$(printf "%.6f" "$period_return")${NC}"
    echo ""
    echo -e "  ${BOLD}Actual APY:${NC}         ${GREEN}${apy}%${NC}"
    echo -e "  ${BOLD}Expected APY:${NC}       ${YELLOW}${EXPECTED_APY}%${NC}"
    
    local apy_diff
    apy_diff=$(echo "scale=2; $apy - $EXPECTED_APY" | bc 2>/dev/null || echo "0")
    
    if (( $(echo "$apy_diff >= 0" | bc -l 2>/dev/null || echo "0") )); then
        echo -e "  ${BOLD}Difference:${NC}         ${GREEN}+${apy_diff}%${NC} ✓"
    else
        echo -e "  ${BOLD}Difference:${NC}         ${RED}${apy_diff}%${NC} ⚠"
    fi
    echo ""
    
    # Store for comparison
    if command -v sqlite3 &>/dev/null && [[ -f "$REWARD_DB" ]]; then
        sqlite3 "$REWARD_DB" "INSERT INTO apy_history (calculated_at, period_days, total_rewards, apy_percent, expected_apy) VALUES (datetime('now'), $days, $total_rewards, $apy, $EXPECTED_APY)" 2>/dev/null || true
    fi
    
    echo "$apy"
}

# Show reward summary
show_summary() {
    log_info "Fetching reward summary..."
    
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                 REWARD SUMMARY                               ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Current block info
    local current_block
    current_block=$(get_current_block)
    echo -e "  Current Block:      ${CYAN}$current_block${NC}"
    echo ""
    
    # Today's rewards
    if [[ -f "$REWARD_DB" ]]; then
        local today_rewards today_count
        today_rewards=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(SUM(amount), 0) FROM rewards WHERE date(timestamp) = date('now')" 2>/dev/null || echo "0")
        today_count=$(sqlite3 "$REWARD_DB" "SELECT COUNT(*) FROM rewards WHERE date(timestamp) = date('now')" 2>/dev/null || echo "0")
        
        local week_rewards week_count
        week_rewards=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(SUM(amount), 0) FROM rewards WHERE timestamp >= datetime('now', '-7 days')" 2>/dev/null || echo "0")
        week_count=$(sqlite3 "$REWARD_DB" "SELECT COUNT(*) FROM rewards WHERE timestamp >= datetime('now', '-7 days')" 2>/dev/null || echo "0")
        
        local month_rewards month_count
        month_rewards=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(SUM(amount), 0) FROM rewards WHERE timestamp >= datetime('now', '-30 days')" 2>/dev/null || echo "0")
        month_count=$(sqlite3 "$REWARD_DB" "SELECT COUNT(*) FROM rewards WHERE timestamp >= datetime('now', '-30 days')" 2>/dev/null || echo "0")
        
        local total_rewards total_count
        total_rewards=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(SUM(amount), 0) FROM rewards" 2>/dev/null || echo "0")
        total_count=$(sqlite3 "$REWARD_DB" "SELECT COUNT(*) FROM rewards" 2>/dev/null || echo "0")
        
        echo -e "  ${BOLD}Period${NC}        ${BOLD}Rewards (XDC)${NC}    ${BOLD}Events${NC}"
        echo "  ─────────────────────────────────────────"
        echo -e "  Today         ${GREEN}${today_rewards}${NC}            ${CYAN}${today_count}${NC}"
        echo -e "  Last 7 days   ${GREEN}${week_rewards}${NC}            ${CYAN}${week_count}${NC}"
        echo -e "  Last 30 days  ${GREEN}${month_rewards}${NC}            ${CYAN}${month_count}${NC}"
        echo -e "  All time      ${GREEN}${total_rewards}${NC}            ${CYAN}${total_count}${NC}"
    else
        echo -e "  ${YELLOW}No reward database found. Run --init-db to initialize.${NC}"
    fi
    
    # Missed blocks
    local missed_count
    if [[ -f "$REWARD_DB" ]]; then
        missed_count=$(sqlite3 "$REWARD_DB" "SELECT COUNT(*) FROM missed_blocks WHERE timestamp >= datetime('now', '-7 days')" 2>/dev/null || echo "0")
        echo ""
        echo -e "  ${BOLD}Missed Blocks (7d):${NC} ${YELLOW}${missed_count}${NC}"
    fi
    
    # Last reward
    if [[ -f "$REWARD_DB" ]]; then
        local last_reward
        last_reward=$(sqlite3 "$REWARD_DB" "SELECT amount, timestamp FROM rewards ORDER BY timestamp DESC LIMIT 1" 2>/dev/null || echo "")
        if [[ -n "$last_reward" ]]; then
            echo ""
            echo -e "  ${BOLD}Last Reward:${NC}        ${GREEN}${last_reward}${NC}"
        fi
    fi
    
    echo ""
}

# Show reward history
show_history() {
    local days="${1:-30}"
    log_info "Showing reward history for last $days days..."
    
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                 REWARD HISTORY ($days days)                     ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ ! -f "$REWARD_DB" ]]; then
        echo -e "  ${YELLOW}No reward database found. Run --init-db to initialize.${NC}"
        return 1
    fi
    
    echo -e "  ${BOLD}Date          Block      Amount (XDC)   Type${NC}"
    echo "  ─────────────────────────────────────────────────"
    
    sqlite3 "$REWARD_DB" "SELECT strftime('%Y-%m-%d %H:%M', timestamp), block_number, amount, reward_type FROM rewards WHERE timestamp >= datetime('now', '-$days days') ORDER BY timestamp DESC LIMIT 50" 2>/dev/null | while IFS='|' read -r date block amount type; do
        printf "  %-13s %-10s %-14s %s\n" "$date" "$block" "${GREEN}${amount}${NC}" "$type"
    done
    
    # Daily summary
    echo ""
    echo -e "  ${BOLD}Daily Summary:${NC}"
    echo "  ─────────────────────────────────────────"
    echo -e "  ${BOLD}Date          Rewards    Count   Avg/Block${NC}"
    echo "  ─────────────────────────────────────────"
    
    sqlite3 "$REWARD_DB" "SELECT date(timestamp), ROUND(SUM(amount), 4), COUNT(*), ROUND(AVG(amount), 4) FROM rewards WHERE timestamp >= datetime('now', '-$days days') GROUP BY date(timestamp) ORDER BY date(timestamp) DESC" 2>/dev/null | while IFS='|' read -r date total count avg; do
        printf "  %-13s ${GREEN}%-10s${NC} ${CYAN}%-7s${NC} %s\n" "$date" "$total" "$count" "$avg"
    done
    
    echo ""
}

# Show missed blocks report
show_missed_blocks() {
    local days="${1:-7}"
    log_info "Showing missed blocks report..."
    
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                 MISSED BLOCKS REPORT                         ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ ! -f "$REWARD_DB" ]]; then
        echo -e "  ${YELLOW}No reward database found. Run --init-db to initialize.${NC}"
        return 1
    fi
    
    local total_missed
    total_missed=$(sqlite3 "$REWARD_DB" "SELECT COUNT(*) FROM missed_blocks WHERE timestamp >= datetime('now', '-$days days')" 2>/dev/null || echo "0")
    
    echo -e "  Missed blocks (last $days days): ${YELLOW}${total_missed}${NC}"
    echo ""
    
    if [[ "$total_missed" -gt 0 ]]; then
        echo -e "  ${BOLD}Date                Block      Reason${NC}"
        echo "  ─────────────────────────────────────────"
        
        sqlite3 "$REWARD_DB" "SELECT timestamp, block_number, reason FROM missed_blocks WHERE timestamp >= datetime('now', '-$days days') ORDER BY timestamp DESC" 2>/dev/null | while IFS='|' read -r timestamp block reason; do
            printf "  %-19s %-10s %s\n" "$timestamp" "$block" "${RED}${reason}${NC}"
        done
        
        # Pattern analysis
        echo ""
        echo -e "  ${BOLD}Pattern Analysis:${NC}"
        local hourly_pattern
        hourly_pattern=$(sqlite3 "$REWARD_DB" "SELECT strftime('%H', timestamp), COUNT(*) FROM missed_blocks WHERE timestamp >= datetime('now', '-$days days') GROUP BY strftime('%H', timestamp) ORDER BY COUNT(*) DESC LIMIT 3" 2>/dev/null)
        
        if [[ -n "$hourly_pattern" ]]; then
            echo "  Top problematic hours:"
            echo "$hourly_pattern" | while IFS='|' read -r hour count; do
                echo "    ${hour}:00 - ${count} missed blocks"
            done
        fi
    else
        echo -e "  ${GREEN}✓ No missed blocks in the last $days days!${NC}"
    fi
    
    echo ""
}

# Show slashing events
show_slashing() {
    log_info "Showing slashing events..."
    
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                 SLASHING EVENTS                              ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ ! -f "$REWARD_DB" ]]; then
        echo -e "  ${YELLOW}No reward database found. Run --init-db to initialize.${NC}"
        return 1
    fi
    
    local slash_count
    slash_count=$(sqlite3 "$REWARD_DB" "SELECT COUNT(*) FROM slashing_events" 2>/dev/null || echo "0")
    
    if [[ "$slash_count" -gt 0 ]]; then
        echo -e "  Total slashing events: ${RED}${slash_count}${NC}"
        echo ""
        echo -e "  ${BOLD}Date                Block      Amount (XDC)   Reason${NC}"
        echo "  ─────────────────────────────────────────────────────"
        
        sqlite3 "$REWARD_DB" "SELECT timestamp, block_number, amount, reason FROM slashing_events ORDER BY timestamp DESC" 2>/dev/null | while IFS='|' read -r timestamp block amount reason; do
            printf "  %-19s %-10s ${RED}%-14s${NC} %s\n" "$timestamp" "$block" "$amount" "$reason"
        done
    else
        echo -e "  ${GREEN}✓ No slashing events recorded!${NC}"
    fi
    
    echo ""
}

# Export data
export_data() {
    local format="${1:-json}"
    local output_file="${2:-}"
    
    log_info "Exporting data to $format format..."
    
    if [[ ! -f "$REWARD_DB" ]]; then
        log_error "No reward database found. Run --init-db to initialize."
        return 1
    fi
    
    # Generate timestamp for filename
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    
    case "$format" in
        json)
            output_file="${output_file:-xdc_rewards_${timestamp}.json}"
            sqlite3 "$REWARD_DB" "SELECT json_object('timestamp', timestamp, 'block_number', block_number, 'amount', amount, 'reward_type', reward_type) FROM rewards" 2>/dev/null | jq -s '.' > "$output_file"
            ;;
        csv)
            output_file="${output_file:-xdc_rewards_${timestamp}.csv}"
            echo "timestamp,block_number,amount,reward_type" > "$output_file"
            sqlite3 "$REWARD_DB" ".mode csv\nSELECT timestamp, block_number, amount, reward_type FROM rewards" 2>/dev/null >> "$output_file"
            ;;
        pdf)
            output_file="${output_file:-xdc_rewards_${timestamp}.txt}"
            {
                echo "XDC Masternode Rewards Report"
                echo "Generated: $(date)"
                echo "========================================"
                echo ""
                sqlite3 "$REWARD_DB" "SELECT * FROM rewards" 2>/dev/null
            } > "$output_file"
            log_warn "Text format generated (PDF requires additional tools). File: $output_file"
            return 0
            ;;
        *)
            log_error "Unknown format: $format. Use json, csv, or pdf."
            return 1
            ;;
    esac
    
    log_info "Data exported to: $output_file"
    echo "$output_file"
}

# Track current reward cycle
track_rewards() {
    log_info "Starting reward tracking..."
    
    ensure_directories
    init_db 2>/dev/null || true
    
    local current_block last_block
    current_block=$(get_current_block)
    last_block="$current_block"
    
    echo "Current block: $current_block"
    
    # Simulate tracking loop (in real implementation, this would be a daemon)
    local cycles=0
    local max_cycles="${1:-10}"
    
    while [[ $cycles -lt $max_cycles ]]; do
        sleep 5
        current_block=$(get_current_block)
        
        if [[ "$current_block" -gt "$last_block" ]]; then
            echo "New block: $current_block"
            
            # Check for rewards at this block
            # In production, query actual reward events
            
            last_block="$current_block"
        fi
        
        ((cycles++))
    done
}

# Compare actual vs expected rewards
compare_rewards() {
    log_info "Comparing actual vs expected rewards..."
    
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║            ACTUAL vs EXPECTED REWARDS                        ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ ! -f "$REWARD_DB" ]]; then
        echo -e "  ${YELLOW}No reward database found. Run --init-db to initialize.${NC}"
        return 1
    fi
    
    # Calculate expected rewards for last 30 days
    local days=30
    local daily_expected
    daily_expected=$(echo "scale=8; $MIN_STAKE * $EXPECTED_APY / 100 / 365" | bc 2>/dev/null || echo "0")
    local period_expected
    period_expected=$(echo "scale=8; $daily_expected * $days" | bc 2>/dev/null || echo "0")
    
    local actual_rewards
    actual_rewards=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(SUM(amount), 0) FROM rewards WHERE timestamp >= datetime('now', '-$days days')" 2>/dev/null || echo "0")
    
    local difference
    difference=$(echo "scale=8; $actual_rewards - $period_expected" | bc 2>/dev/null || echo "0")
    local percent_diff
    if (( $(echo "$period_expected > 0" | bc -l 2>/dev/null || echo "0") )); then
        percent_diff=$(echo "scale=2; ($difference / $period_expected) * 100" | bc 2>/dev/null || echo "0")
    else
        percent_diff="0"
    fi
    
    echo -e "  Period:             ${CYAN}Last $days days${NC}"
    echo -e "  Stake:              ${CYAN}${MIN_STAKE} XDC${NC}"
    echo ""
    echo -e "  ${BOLD}Expected Rewards:${NC}   ${YELLOW}$(printf "%.4f" "$period_expected") XDC${NC}"
    echo -e "  ${BOLD}Actual Rewards:${NC}     ${GREEN}${actual_rewards} XDC${NC}"
    echo ""
    
    if (( $(echo "$difference >= 0" | bc -l 2>/dev/null || echo "0") )); then
        echo -e "  ${BOLD}Difference:${NC}         ${GREEN}+$(printf "%.4f" "$difference") XDC (+${percent_diff}%)${NC} ✓"
    else
        echo -e "  ${BOLD}Difference:${NC}         ${RED}$(printf "%.4f" "$difference") XDC (${percent_diff}%)${NC} ⚠"
    fi
    
    echo ""
}

# Test alerts
test_alerts() {
    log_info "Testing alert notifications..."
    
    if command -v notify-send &>/dev/null; then
        notify-send "XDC Masternode" "Test alert from rewards system"
    fi
    
    if [[ -f "${LIB_DIR}/notify.sh" ]]; then
        notify_alert "TEST" "Test notification from masternode rewards system"
    fi
    
    echo -e "${GREEN}Alert test completed.${NC}"
}

# Main function
main() {
    ensure_directories
    
    local cmd=""
    local days=30
    local export_format=""
    local output_file=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --summary)
                cmd="summary"
                shift
                ;;
            --history)
                cmd="history"
                if [[ -n "${2:-}" ]] && [[ ! "$2" =~ ^-- ]]; then
                    days="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            --days)
                days="$2"
                shift 2
                ;;
            --apy)
                cmd="apy"
                shift
                ;;
            --missed)
                cmd="missed"
                shift
                ;;
            --slashing)
                cmd="slashing"
                shift
                ;;
            --export)
                cmd="export"
                export_format="${2:-json}"
                shift 2
                ;;
            --output)
                output_file="$2"
                shift 2
                ;;
            --track)
                cmd="track"
                shift
                ;;
            --init-db)
                cmd="init-db"
                shift
                ;;
            --compare)
                cmd="compare"
                shift
                ;;
            --alert-test)
                cmd="alert-test"
                shift
                ;;
            -h|--help)
                print_banner
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Execute command
    case "$cmd" in
        summary)
            print_banner
            show_summary
            ;;
        history)
            print_banner
            show_history "$days"
            ;;
        apy)
            print_banner
            calculate_apy "$days"
            ;;
        missed)
            print_banner
            show_missed_blocks "$days"
            ;;
        slashing)
            print_banner
            show_slashing
            ;;
        export)
            export_data "$export_format" "$output_file"
            ;;
        track)
            track_rewards
            ;;
        init-db)
            init_db
            ;;
        compare)
            print_banner
            compare_rewards
            ;;
        alert-test)
            test_alerts
            ;;
        *)
            print_banner
            show_summary
            ;;
    esac
}

# Run main
main "$@"
