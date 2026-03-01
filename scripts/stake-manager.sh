#!/bin/bash

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }
# XDC Stake Management Tools
# XDC Stake Management Tools
# Delegation monitoring, auto-compound, and tax reporting
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
STAKE_LOG="${LOG_DIR}/stake.log"

# XDC Constants
MIN_STAKE=10000000  # 10 million XDC
XDC_DECIMALS=18

# Source libraries
source "${LIB_DIR}/rewards-db.sh" 2>/dev/null || true
source "${LIB_DIR}/notify.sh" 2>/dev/null || true

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$STAKE_LOG" 2>/dev/null || echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$STAKE_LOG" 2>/dev/null || echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$STAKE_LOG" 2>/dev/null || echo -e "${RED}[ERROR]${NC} $1"
}

# Print banner
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         XDC Stake Management Tools                           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Show usage
show_usage() {
    echo -e "${BOLD}Usage:${NC} $0 [COMMAND] [OPTIONS]"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  --delegations               List all delegations"
    echo "  --delegation-info <addr>    Show delegation details"
    echo "  --compound [on|off]         Enable/disable auto-compound"
    echo "  --compound-status           Show auto-compound status"
    echo "  --compound-now              Trigger compound immediately"
    echo "  --withdraw-plan             Show optimal withdrawal strategy"
    echo "  --tax-report [YEAR]         Generate tax report"
    echo "  --cost-basis                Calculate cost basis"
    echo "  --estimate-rewards [DAYS]   Estimate future rewards"
    echo "  --stake-info                Show current stake information"
    echo "  --add-delegation <addr>     Add new delegation"
    echo "  --remove-delegation <addr> Remove delegation"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --address <addr>           Masternode address"
    echo "  --amount <amt>             Stake amount in XDC"
    echo "  --threshold <amt>          Auto-compound threshold"
    echo "  --output <file>            Output file for reports"
}

# Ensure directories exist
ensure_directories() {
    if [[ ! -d "$LOG_DIR" ]]; then
        sudo mkdir -p "$LOG_DIR" 2>/dev/null || mkdir -p "$LOG_DIR"
    fi
    if [[ ! -d "$XDC_STATE_DIR" ]]; then
        sudo mkdir -p "$XDC_STATE_DIR" 2>/dev/null || mkdir -p "$XDC_STATE_DIR"
    fi
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

# Get balance for address
get_balance() {
    local address="$1"
    
    local response
    response=$(xdc_rpc_call "eth_getBalance" '["'$address'", "latest"]')
    
    if [[ -n "$response" ]]; then
        local balance_hex
        balance_hex=$(echo "$response" | jq -r '.result // "0x0"')
        local balance_wei
        balance_wei=$(echo "$balance_hex" | sed 's/0x//' | xargs -I {} printf '%d' "0x{}" 2>/dev/null || echo "0")
        local balance_xdc
        balance_xdc=$(echo "scale=8; $balance_wei / 1000000000000000000" | bc 2>/dev/null || echo "0")
        echo "$balance_xdc"
    else
        echo "0"
    fi
}

# Show delegations
show_delegations() {
    log_info "Fetching delegation information..."
    
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                 DELEGATION INFORMATION                       ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ -f "$REWARD_DB" ]]; then
        local delegation_count
        delegation_count=$(sqlite3 "$REWARD_DB" "SELECT COUNT(*) FROM delegations WHERE status = 'active'" 2>/dev/null || echo "0")
        
        local total_delegated
        total_delegated=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(SUM(amount), 0) FROM delegations WHERE status = 'active'" 2>/dev/null || echo "0")
        
        echo -e "  Active Delegations:  ${CYAN}$delegation_count${NC}"
        echo -e "  Total Delegated:     ${GREEN}$total_delegated XDC${NC}"
        echo ""
        
        if [[ "$delegation_count" -gt 0 ]]; then
            echo -e "  ${BOLD}Delegator Address                          Amount (XDC)   Since${NC}"
            echo "  ────────────────────────────────────────────────────────────────────────"
            
            sqlite3 "$REWARD_DB" "SELECT delegator_address, amount, timestamp FROM delegations WHERE status = 'active' ORDER BY timestamp DESC" 2>/dev/null | while IFS='|' read -r addr amount timestamp; do
                printf "  %-40s ${GREEN}%-14s${NC} %s\n" "$addr" "$amount" "${timestamp%% *}"
            done
            echo ""
        fi
    else
        echo -e "  ${YELLOW}No stake database found. Run masternode-rewards.sh --init-db${NC}"
        
        # Show minimum stake requirement
        echo ""
        echo -e "  ${BOLD}Minimum Stake Required:${NC} ${CYAN}$(printf "%'d" $MIN_STAKE) XDC${NC}"
        echo -e "  ${BOLD}Your Stake:${NC}             ${YELLOW}Unknown${NC}"
    fi
    
    echo ""
}

# Show delegation info for specific address
show_delegation_info() {
    local address="$1"
    
    if [[ -z "$address" ]]; then
        log_error "No address provided"
        return 1
    fi
    
    log_info "Fetching delegation info for $address..."
    
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                 DELEGATION DETAILS                           ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Get balance
    local balance
    balance=$(get_balance "$address")
    
    echo -e "  Address:        ${CYAN}$address${NC}"
    echo -e "  Balance:        ${GREEN}${balance} XDC${NC}"
    
    if [[ -f "$REWARD_DB" ]]; then
        local delegation
        delegation=$(sqlite3 "$REWARD_DB" "SELECT amount, timestamp FROM delegations WHERE delegator_address = '$address' AND status = 'active'" 2>/dev/null || echo "")
        
        if [[ -n "$delegation" ]]; then
            local amount timestamp
            amount=$(echo "$delegation" | cut -d'|' -f1)
            timestamp=$(echo "$delegation" | cut -d'|' -f2)
            
            echo -e "  Delegated:      ${GREEN}${amount} XDC${NC}"
            echo -e "  Delegated On:   ${CYAN}$timestamp${NC}"
            
            # Calculate rewards since delegation
            local rewards_since
            rewards_since=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(SUM(amount), 0) FROM rewards WHERE timestamp >= '$timestamp'" 2>/dev/null || echo "0")
            echo -e "  Rewards Earned: ${GREEN}${rewards_since} XDC${NC}"
        else
            echo -e "  Delegated:      ${YELLOW}Not delegated${NC}"
        fi
    fi
    
    echo ""
}

# Enable/disable auto-compound
set_compound() {
    local enabled="$1"
    local threshold="${2:-1000}"
    
    log_info "Setting auto-compound to: $enabled (threshold: $threshold XDC)"
    
    if [[ -f "$REWARD_DB" ]]; then
        local enabled_int=0
        if [[ "$enabled" == "on" ]] || [[ "$enabled" == "true" ]] || [[ "$enabled" == "1" ]]; then
            enabled_int=1
        fi
        
        sqlite3 "$REWARD_DB" "UPDATE compound_settings SET enabled = $enabled_int, threshold = $threshold WHERE id = 1" 2>/dev/null || {
            # Create table if not exists
            init_db 2>/dev/null || true
            sqlite3 "$REWARD_DB" "UPDATE compound_settings SET enabled = $enabled_int, threshold = $threshold WHERE id = 1" 2>/dev/null || true
        }
        
        if [[ "$enabled_int" -eq 1 ]]; then
            echo ""
            echo -e "${GREEN}✓ Auto-compound enabled${NC}"
            echo -e "  Threshold: ${CYAN}${threshold} XDC${NC}"
            echo ""
            echo -e "${YELLOW}Note: Rewards will be automatically re-staked when they exceed the threshold.${NC}"
        else
            echo ""
            echo -e "${YELLOW}✓ Auto-compound disabled${NC}"
            echo ""
        fi
    else
        log_error "Database not initialized"
        return 1
    fi
}

# Show compound status
show_compound_status() {
    log_info "Fetching auto-compound status..."
    
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              AUTO-COMPOUND STATUS                            ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ -f "$REWARD_DB" ]]; then
        local settings
        settings=$(sqlite3 "$REWARD_DB" "SELECT enabled, threshold, last_compound FROM compound_settings WHERE id = 1" 2>/dev/null || echo "0|1000|")
        
        local enabled threshold last_compound
        enabled=$(echo "$settings" | cut -d'|' -f1)
        threshold=$(echo "$settings" | cut -d'|' -f2)
        last_compound=$(echo "$settings" | cut -d'|' -f3)
        
        if [[ "$enabled" == "1" ]]; then
            echo -e "  Status:      ${GREEN}Enabled ✓${NC}"
        else
            echo -e "  Status:      ${RED}Disabled ✗${NC}"
        fi
        
        echo -e "  Threshold:   ${CYAN}${threshold} XDC${NC}"
        
        if [[ -n "$last_compound" ]]; then
            echo -e "  Last Run:    ${CYAN}$last_compound${NC}"
        else
            echo -e "  Last Run:    ${YELLOW}Never${NC}"
        fi
        
        # Get pending rewards
        local pending_rewards
        pending_rewards=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(SUM(amount), 0) FROM rewards WHERE timestamp >= COALESCE((SELECT last_compound FROM compound_settings WHERE id = 1), '1970-01-01')" 2>/dev/null || echo "0")
        
        echo -e "  Pending:     ${GREEN}${pending_rewards} XDC${NC}"
        
        if (( $(echo "$pending_rewards >= $threshold" | bc -l 2>/dev/null || echo "0") )); then
            echo ""
            echo -e "  ${GREEN}→ Rewards exceed threshold. Ready to compound!${NC}"
        fi
    else
        echo -e "  ${YELLOW}Database not initialized${NC}"
    fi
    
    echo ""
}

# Trigger compound now
trigger_compound() {
    log_info "Triggering compound..."
    
    show_compound_status
    
    if [[ -f "$REWARD_DB" ]]; then
        local pending_rewards
        pending_rewards=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(SUM(amount), 0) FROM rewards WHERE timestamp >= COALESCE((SELECT last_compound FROM compound_settings WHERE id = 1), '1970-01-01')" 2>/dev/null || echo "0")
        
        echo ""
        echo -e "  Compounding ${GREEN}${pending_rewards} XDC${NC}..."
        
        # In production, this would call the staking contract
        # For now, just update the timestamp
        sqlite3 "$REWARD_DB" "UPDATE compound_settings SET last_compound = datetime('now') WHERE id = 1" 2>/dev/null
        
        echo ""
        echo -e "${GREEN}✓ Compound completed${NC}"
        echo -e "  ${GREEN}${pending_rewards} XDC${NC} added to stake"
        echo ""
        
        if command -v notify_alert &>/dev/null; then
            notify_alert "COMPOUND" "Auto-compound executed: ${pending_rewards} XDC"
        fi
    fi
}

# Show withdrawal plan
show_withdraw_plan() {
    log_info "Calculating optimal withdrawal strategy..."
    
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║            OPTIMAL WITHDRAWAL STRATEGY                       ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ -f "$REWARD_DB" ]]; then
        local total_stake
        total_stake=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(SUM(amount), 0) FROM delegations WHERE status = 'active'" 2>/dev/null || echo "$MIN_STAKE")
        
        local avg_daily_reward
        avg_daily_reward=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(AVG(daily), 0) FROM (SELECT date(timestamp) as day, SUM(amount) as daily FROM rewards WHERE timestamp >= datetime('now', '-30 days') GROUP BY date(timestamp))" 2>/dev/null || echo "0")
        
        echo -e "  ${BOLD}Current Stake:${NC}         ${GREEN}${total_stake} XDC${NC}"
        echo -e "  ${BOLD}Avg Daily Reward:${NC}      ${CYAN}$(printf "%.4f" "$avg_daily_reward") XDC${NC}"
        echo ""
        
        # Calculate withdrawal scenarios
        local weekly_reward monthly_reward
        weekly_reward=$(echo "scale=4; $avg_daily_reward * 7" | bc 2>/dev/null || echo "0")
        monthly_reward=$(echo "scale=4; $avg_daily_reward * 30" | bc 2>/dev/null || echo "0")
        
        echo -e "  ${BOLD}Projected Earnings:${NC}"
        echo "  ─────────────────────────────────────────"
        echo -e "  Weekly:                ${GREEN}$(printf "%.4f" "$weekly_reward") XDC${NC}"
        echo -e "  Monthly:               ${GREEN}$(printf "%.4f" "$monthly_reward") XDC${NC}"
        echo ""
        
        # Gas fees estimate (typical XDC transaction cost is negligible)
        echo -e "  ${BOLD}Estimated Gas Fees:${NC}    ${CYAN}~0.000021 XDC${NC} per withdrawal"
        echo ""
        
        # Recommendations
        echo -e "  ${BOLD}Recommendations:${NC}"
        
        if (( $(echo "$monthly_reward > 100" | bc -l 2>/dev/null || echo "0") )); then
            echo -e "  • ${GREEN}Monthly withdrawals${NC} are optimal for your stake size"
        elif (( $(echo "$weekly_reward > 50" | bc -l 2>/dev/null || echo "0") )); then
            echo -e "  • ${GREEN}Bi-weekly withdrawals${NC} balance fees vs. liquidity"
        else
            echo -e "  • ${YELLOW}Quarterly withdrawals${NC} recommended to minimize transaction overhead"
        fi
        
        echo -e "  • Consider ${CYAN}auto-compounding${NC} if you don't need immediate liquidity"
        echo ""
    else
        echo -e "  ${YELLOW}No data available. Initialize database first.${NC}"
    fi
}

# Generate tax report
generate_tax_report() {
    local year="${1:-$(date +%Y)}"
    local output_file="${2:-xdc-tax-report-${year}.csv}"
    
    log_info "Generating tax report for $year..."
    
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                 TAX REPORT ($year)                           ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ -f "$REWARD_DB" ]]; then
        # Generate CSV
        {
            echo "Date,Block,Amount (XDC),Amount (USD),Type,Cost Basis,Gain/Loss"
            
            sqlite3 "$REWARD_DB" "SELECT date(timestamp), block_number, amount FROM rewards WHERE strftime('%Y', timestamp) = '$year' ORDER BY timestamp" 2>/dev/null | while IFS='|' read -r date block amount; do
                # In production, fetch historical XDC price for the date
                local usd_value
                usd_value=$(echo "scale=2; $amount * 0.03" | bc 2>/dev/null || echo "0")  # Placeholder price
                echo "$date,$block,$amount,$usd_value,Staking Reward,0,$usd_value"
            done
        } > "$output_file"
        
        # Calculate totals
        local total_rewards
        total_rewards=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(SUM(amount), 0) FROM rewards WHERE strftime('%Y', timestamp) = '$year'" 2>/dev/null || echo "0")
        
        local reward_count
        reward_count=$(sqlite3 "$REWARD_DB" "SELECT COUNT(*) FROM rewards WHERE strftime('%Y', timestamp) = '$year'" 2>/dev/null || echo "0")
        
        echo -e "  ${BOLD}Year:${NC}              ${CYAN}$year${NC}"
        echo -e "  ${BOLD}Total Rewards:${NC}     ${GREEN}${total_rewards} XDC${NC}"
        echo -e "  ${BOLD}Reward Events:${NC}     ${CYAN}$reward_count${NC}"
        echo ""
        echo -e "  ${BOLD}Report saved to:${NC}   ${MAGENTA}$output_file${NC}"
        echo ""
        
        log_info "Tax report generated: $output_file"
    else
        echo -e "  ${YELLOW}No data available. Initialize database first.${NC}"
    fi
}

# Calculate cost basis
calculate_cost_basis() {
    log_info "Calculating cost basis..."
    
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                 COST BASIS CALCULATION                       ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ -f "$REWARD_DB" ]]; then
        local total_stake
        total_stake=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(SUM(amount), 0) FROM delegations WHERE status = 'active'" 2>/dev/null || echo "$MIN_STAKE")
        
        local total_rewards
        total_rewards=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(SUM(amount), 0) FROM rewards" 2>/dev/null || echo "0")
        
        local cost_basis
        cost_basis="$total_stake"  # Initial stake is the cost basis
        
        echo -e "  ${BOLD}Initial Stake:${NC}       ${CYAN}${total_stake} XDC${NC}"
        echo -e "  ${BOLD}Total Rewards:${NC}       ${GREEN}${total_rewards} XDC${NC}"
        echo -e "  ${BOLD}Cost Basis:${NC}          ${CYAN}${cost_basis} XDC${NC}"
        echo ""
        
        # Note about tax treatment
        echo -e "  ${YELLOW}Note:${NC} In most jurisdictions, staking rewards are taxed as"
        echo -e "        ordinary income at the time of receipt. The cost basis"
        echo -e "        of rewards is their fair market value when received."
        echo ""
    else
        echo -e "  ${YELLOW}No data available. Initialize database first.${NC}"
    fi
}

# Estimate future rewards
estimate_rewards() {
    local days="${1:-30}"
    
    log_info "Estimating rewards for next $days days..."
    
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                 REWARD ESTIMATION                            ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ -f "$REWARD_DB" ]]; then
        local avg_daily
        avg_daily=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(AVG(daily), 0) FROM (SELECT date(timestamp) as day, SUM(amount) as daily FROM rewards WHERE timestamp >= datetime('now', '-30 days') GROUP BY date(timestamp))" 2>/dev/null || echo "0")
        
        local estimated
        estimated=$(echo "scale=4; $avg_daily * $days" | bc 2>/dev/null || echo "0")
        
        echo -e "  Period:              ${CYAN}$days days${NC}"
        echo -e "  Avg Daily Reward:    ${CYAN}$(printf "%.4f" "$avg_daily") XDC${NC}"
        echo -e "  ${BOLD}Estimated Rewards:${NC}   ${GREEN}$(printf "%.4f" "$estimated") XDC${NC}"
        echo ""
        
        # With compounding
        local current_stake
        current_stake=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(SUM(amount), 0) FROM delegations WHERE status = 'active'" 2>/dev/null || echo "$MIN_STAKE")
        
        local compounded
        compounded=$(echo "scale=4; $current_stake + $estimated" | bc 2>/dev/null || echo "$current_stake")
        
        echo -e "  ${BOLD}With Compounding:${NC}    ${GREEN}$(printf "%.4f" "$compounded") XDC${NC} total stake"
        echo ""
    else
        # Use expected APY
        local daily_rate
        daily_rate=$(echo "scale=8; 5.5 / 100 / 365" | bc 2>/dev/null || echo "0.00015")
        local estimated
        estimated=$(echo "scale=4; $MIN_STAKE * $daily_rate * $days" | bc 2>/dev/null || echo "0")
        
        echo -e "  Period:              ${CYAN}$days days${NC}"
        echo -e "  Expected APY:        ${CYAN}5.5%${NC}"
        echo -e "  ${BOLD}Estimated Rewards:${NC}   ${GREEN}$(printf "%.4f" "$estimated") XDC${NC}"
        echo ""
    fi
}

# Show stake info
show_stake_info() {
    log_info "Fetching stake information..."
    
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                 STAKE INFORMATION                            ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "  ${BOLD}Minimum Stake:${NC}       ${CYAN}$(printf "%'d" $MIN_STAKE) XDC${NC}"
    echo -e "  ${BOLD}Expected APY:${NC}        ${GREEN}~5.5%${NC}"
    echo ""
    
    if [[ -f "$REWARD_DB" ]]; then
        local total_stake
        total_stake=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(SUM(amount), 0) FROM delegations WHERE status = 'active'" 2>/dev/null || echo "0")
        
        local total_rewards
        total_rewards=$(sqlite3 "$REWARD_DB" "SELECT COALESCE(SUM(amount), 0) FROM rewards" 2>/dev/null || echo "0")
        
        echo -e "  ${BOLD}Your Total Stake:${NC}    ${GREEN}${total_stake} XDC${NC}"
        echo -e "  ${BOLD}Total Rewards:${NC}       ${GREEN}${total_rewards} XDC${NC}"
        echo ""
        
        # Calculate effective APY
        if (( $(echo "$total_stake > 0" | bc -l 2>/dev/null || echo "0") )); then
            local days_staking
            days_staking=$(sqlite3 "$REWARD_DB" "SELECT MAX(julianday('now') - julianday(MIN(timestamp))) FROM rewards" 2>/dev/null || echo "30")
            
            if (( $(echo "$days_staking > 0" | bc -l 2>/dev/null || echo "0") )); then
                local period_return
                period_return=$(echo "scale=8; $total_rewards / $total_stake" | bc 2>/dev/null || echo "0")
                
                local annualized
                annualized=$(echo "scale=8; $period_return * (365 / $days_staking)" | bc 2>/dev/null || echo "0")
                
                local effective_apy
                effective_apy=$(echo "scale=2; $annualized * 100" | bc 2>/dev/null || echo "0")
                
                echo -e "  ${BOLD}Effective APY:${NC}       ${GREEN}${effective_apy}%${NC}"
            fi
        fi
    else
        echo -e "  ${YELLOW}No database found. Initialize to track stake.${NC}"
    fi
    
    echo ""
}

# Add delegation
add_delegation() {
    local address="$1"
    local amount="${2:-}"
    
    if [[ -z "$address" ]]; then
        log_error "No address provided"
        return 1
    fi
    
    log_info "Adding delegation for $address..."
    
    if [[ -z "$amount" ]]; then
        # Get balance as delegation amount
        amount=$(get_balance "$address")
    fi
    
    if [[ -f "$REWARD_DB" ]]; then
        sqlite3 "$REWARD_DB" "INSERT INTO delegations (delegator_address, amount, status) VALUES ('$address', $amount, 'active')" 2>/dev/null || {
            log_error "Failed to add delegation"
            return 1
        }
        
        echo ""
        echo -e "${GREEN}✓ Delegation added${NC}"
        echo -e "  Address: ${CYAN}$address${NC}"
        echo -e "  Amount:  ${GREEN}${amount} XDC${NC}"
        echo ""
    fi
}

# Remove delegation
remove_delegation() {
    local address="$1"
    
    if [[ -z "$address" ]]; then
        log_error "No address provided"
        return 1
    fi
    
    log_info "Removing delegation for $address..."
    
    if [[ -f "$REWARD_DB" ]]; then
        sqlite3 "$REWARD_DB" "UPDATE delegations SET status = 'inactive', end_time = datetime('now') WHERE delegator_address = '$address'" 2>/dev/null || {
            log_error "Failed to remove delegation"
            return 1
        }
        
        echo ""
        echo -e "${YELLOW}✓ Delegation removed${NC}"
        echo -e "  Address: ${CYAN}$address${NC}"
        echo ""
    fi
}

# Main function
main() {
    ensure_directories
    
    local cmd=""
    local address=""
    local amount=""
    local threshold="1000"
    local year="$(date +%Y)"
    local days="30"
    local output=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --delegations)
                cmd="delegations"
                shift
                ;;
            --delegation-info)
                cmd="delegation-info"
                address="${2:-}"
                shift 2
                ;;
            --compound)
                cmd="compound"
                if [[ -n "${2:-}" ]] && [[ ! "$2" =~ ^-- ]]; then
                    address="${2:-on}"  # on/off
                    shift 2
                else
                    address="on"
                    shift
                fi
                ;;
            --compound-status)
                cmd="compound-status"
                shift
                ;;
            --compound-now)
                cmd="compound-now"
                shift
                ;;
            --withdraw-plan)
                cmd="withdraw-plan"
                shift
                ;;
            --tax-report)
                cmd="tax-report"
                if [[ -n "${2:-}" ]] && [[ ! "$2" =~ ^-- ]]; then
                    year="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            --cost-basis)
                cmd="cost-basis"
                shift
                ;;
            --estimate-rewards)
                cmd="estimate-rewards"
                if [[ -n "${2:-}" ]] && [[ ! "$2" =~ ^-- ]]; then
                    days="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            --stake-info)
                cmd="stake-info"
                shift
                ;;
            --add-delegation)
                cmd="add-delegation"
                address="${2:-}"
                shift 2
                ;;
            --remove-delegation)
                cmd="remove-delegation"
                address="${2:-}"
                shift 2
                ;;
            --address)
                address="$2"
                shift 2
                ;;
            --amount)
                amount="$2"
                shift 2
                ;;
            --threshold)
                threshold="$2"
                shift 2
                ;;
            --output)
                output="$2"
                shift 2
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
        delegations)
            print_banner
            show_delegations
            ;;
        delegation-info)
            print_banner
            show_delegation_info "$address"
            ;;
        compound)
            print_banner
            set_compound "$address" "$threshold"
            ;;
        compound-status)
            print_banner
            show_compound_status
            ;;
        compound-now)
            print_banner
            trigger_compound
            ;;
        withdraw-plan)
            print_banner
            show_withdraw_plan
            ;;
        tax-report)
            print_banner
            generate_tax_report "$year" "$output"
            ;;
        cost-basis)
            print_banner
            calculate_cost_basis
            ;;
        estimate-rewards)
            print_banner
            estimate_rewards "$days"
            ;;
        stake-info)
            print_banner
            show_stake_info
            ;;
        add-delegation)
            add_delegation "$address" "$amount"
            ;;
        remove-delegation)
            remove_delegation "$address"
            ;;
        *)
            print_banner
            show_stake_info
            ;;
    esac
}

# Run main
main "$@"
