#!/bin/bash
#==============================================================================
# XDC Node Owner Status CLI
# Quick terminal dashboard for XDC node owners
# Displays node status, rewards, disk usage, and system resources
#==============================================================================

set -euo pipefail

#==============================================================================
# Configuration
#==============================================================================
RPC_URL="${RPC_URL:-http://localhost:8545}"
DATADIR="${DATADIR:-/work/xdcchain}"

# Colors (can be disabled with NO_COLOR=1)
if [[ -z "${NO_COLOR:-}" ]]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
    BOLD='\033[1m'
    CHECK='✅'
    CROSS='❌'
    WARN='⚠️'
else
    GREEN=''
    YELLOW=''
    RED=''
    BLUE=''
    CYAN=''
    NC=''
    BOLD=''
    CHECK='[OK]'
    CROSS='[ERR]'
    WARN='[WARN]'
fi

#==============================================================================
# Helper Functions
#==============================================================================

hex_to_dec() {
    local hex="${1#0x}"
    printf '%d' "0x${hex}" 2>/dev/null || echo "0"
}

format_number() {
    local num="$1"
    printf '%'\''d' "$num" 2>/dev/null || echo "$num"
}

format_xdc() {
    local xdc="$1"
    if command -v bc >/dev/null 2>&1; then
        printf "%.2f" "$xdc" 2>/dev/null || echo "$xdc"
    else
        echo "$xdc"
    fi
}

format_bytes() {
    local bytes="$1"
    if [[ $bytes -ge 1099511627776 ]]; then
        echo "$(echo "scale=1; $bytes/1099511627776" | bc) TB"
    elif [[ $bytes -ge 1073741824 ]]; then
        echo "$(echo "scale=1; $bytes/1073741824" | bc) GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(echo "scale=1; $bytes/1048576" | bc) MB"
    else
        echo "$(echo "scale=1; $bytes/1024" | bc) KB"
    fi
}

format_duration() {
    local seconds="$1"
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local mins=$(((seconds % 3600) / 60))
    
    if [[ $days -gt 0 ]]; then
        echo "${days}d ${hours}h ${mins}m"
    elif [[ $hours -gt 0 ]]; then
        echo "${hours}h ${mins}m"
    else
        echo "${mins}m"
    fi
}

rpc_call() {
    local method="$1"
    local params="${2:-[]}"
    local timeout="${3:-5}"
    
    curl -s -m "$timeout" -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":${params},\"id\":1}" 2>/dev/null || echo '{}'
}

check_rpc() {
    local response
    response=$(rpc_call "eth_blockNumber" "[]" 3)
    echo "$response" | grep -q '"result"'
}

#==============================================================================
# Data Collection Functions
#==============================================================================

collect_node_data() {
    # Check RPC connectivity
    if ! check_rpc; then
        echo "ERROR: Cannot connect to XDC node at $RPC_URL"
        echo "Please ensure the node is running and RPC is enabled."
        exit 1
    fi
    
    # Get block info
    local response
    response=$(rpc_call "eth_syncing")
    local result
    result=$(echo "$response" | jq -r '.result')
    
    local current_block highest_block is_syncing sync_percent
    if [[ "$result" == "false" ]]; then
        is_syncing="false"
        current_block=$(hex_to_dec "$(rpc_call "eth_blockNumber" | jq -r '.result // "0x0"')")
        highest_block=$current_block
        sync_percent="100.0"
    else
        is_syncing="true"
        current_block=$(hex_to_dec "$(echo "$result" | jq -r '.currentBlock // "0x0"')")
        highest_block=$(hex_to_dec "$(echo "$result" | jq -r '.highestBlock // "0x0"')")
        if [[ $highest_block -gt 0 ]]; then
            sync_percent=$(echo "scale=2; ($current_block / $highest_block) * 100" | bc 2>/dev/null || echo "0")
        else
            sync_percent="0"
        fi
    fi
    
    # Get peers
    local peer_count
    peer_count=$(hex_to_dec "$(rpc_call "net_peerCount" | jq -r '.result // "0x0"')")
    
    # Try to get inbound/outbound
    local admin_peers
    admin_peers=$(rpc_call "admin_peers" "[]" 3)
    local outbound inbound
    if echo "$admin_peers" | grep -q '"result"'; then
        outbound=$(echo "$admin_peers" | jq '.result | length')
        # Estimate inbound (total - outbound)
        inbound=$((peer_count - outbound))
        [[ $inbound -lt 0 ]] && inbound=0
    else
        outbound="?"
        inbound="?"
    fi
    
    # Get coinbase
    local coinbase
    coinbase=$(rpc_call "eth_coinbase" | jq -r '.result // "unknown"')
    
    # Get uptime
    local uptime_sec
    if [[ -f /proc/uptime ]]; then
        uptime_sec=$(awk '{print int($1)}' /proc/uptime)
    else
        uptime_sec=0
    fi
    
    echo "${current_block}|${highest_block}|${is_syncing}|${sync_percent}|${peer_count}|${outbound}|${inbound}|${coinbase}|${uptime_sec}"
}

collect_reward_data() {
    local coinbase="$1"
    
    if [[ "$coinbase" == "unknown" || "$coinbase" == "0x0000000000000000000000000000000000000000" ]]; then
        echo "0|0|0|0|0"
        return
    fi
    
    # Get current balance
    local response
    response=$(rpc_call "eth_getBalance" "[\"${coinbase}\",\"latest\"]")
    local balance_wei
    balance_wei=$(hex_to_dec "$(echo "$response" | jq -r '.result // "0x0"')")
    local balance_xdc
    balance_xdc=$(echo "scale=18; $balance_wei / 1000000000000000000" | bc 2>/dev/null || echo "0")
    
    # For rewards, we need historical data - try to read from metrics state
    local state_file="/var/lib/node_exporter/textfile_collector/.xdc_metrics_state/reward_history"
    local total_rewards="0"
    local rewards_24h="0"
    local rewards_7d="0"
    local monthly_est="0"
    
    if [[ -f "$state_file" ]]; then
        local first_line last_line
        first_line=$(head -1 "$state_file" 2>/dev/null)
        last_line=$(tail -1 "$state_file" 2>/dev/null)
        
        if [[ -n "$first_line" && -n "$last_line" ]]; then
            local first_balance last_balance
            first_balance=$(echo "$first_line" | cut -d'|' -f3)
            last_balance=$(echo "$last_line" | cut -d'|' -f3)
            
            total_rewards=$(echo "scale=2; ($last_balance - $first_balance) / 1000000000000000000" | bc 2>/dev/null || echo "0")
            
            # 24h and 7d estimates
            local now timestamp_24h timestamp_7d
            now=$(date +%s)
            timestamp_24h=$((now - 86400))
            timestamp_7d=$((now - 604800))
            
            # Find closest historical entry
            local balance_24h_ago balance_7d_ago
            balance_24h_ago=$(awk -F'|' -v ts="$timestamp_24h" '$1 >= ts {print $3; exit}' "$state_file" 2>/dev/null || echo "$last_balance")
            balance_7d_ago=$(awk -F'|' -v ts="$timestamp_7d" '$1 >= ts {print $3; exit}' "$state_file" 2>/dev/null || echo "$last_balance")
            
            rewards_24h=$(echo "scale=2; ($last_balance - $balance_24h_ago) / 1000000000000000000" | bc 2>/dev/null || echo "0")
            rewards_7d=$(echo "scale=2; ($last_balance - $balance_7d_ago) / 1000000000000000000" | bc 2>/dev/null || echo "0")
            
            # Monthly estimate
            if [[ $(echo "$rewards_7d > 0" | bc 2>/dev/null) -eq 1 ]]; then
                monthly_est=$(echo "scale=2; $rewards_7d / 7 * 30" | bc 2>/dev/null || echo "0")
            fi
        fi
    fi
    
    echo "${balance_xdc}|${total_rewards}|${rewards_24h}|${rewards_7d}|${monthly_est}"
}

collect_masternode_data() {
    local coinbase="$1"
    
    if [[ "$coinbase" == "unknown" ]]; then
        echo "0|0|0|0"
        return
    fi
    
    local response
    response=$(rpc_call "XDPoS_getMasternodesByNumber" '["latest"]')
    
    if ! echo "$response" | grep -q '"result"'; then
        echo "0|0|0|0"
        return
    fi
    
    # Check if in masternodes list
    local is_masternode
    is_masternode=$(echo "$response" | jq -r --arg addr "$coinbase" '.result.Masternodes[]? | select(.address == $addr) | .address' 2>/dev/null | wc -l)
    
    if [[ "$is_masternode" -gt 0 ]]; then
        local stake deposit
        stake=$(echo "$response" | jq -r --arg addr "$coinbase" '.result.Masternodes[] | select(.address == $addr) | .stake // "0"' 2>/dev/null)
        deposit=$(echo "$response" | jq -r --arg addr "$coinbase" '.result.Masternodes[] | select(.address == $addr) | .deposit // "0"' 2>/dev/null)
        
        local stake_xdc
        stake_xdc=$(echo "scale=2; $stake / 1000000000000000000" | bc 2>/dev/null || echo "0")
        
        # Get penalties
        local penalties
        penalties=$(rpc_call "XDPoS_getPendingPenalties" '["latest"]' | jq --arg addr "$coinbase" '[.result[]? | select(contains($addr))] | length' 2>/dev/null || echo "0")
        
        echo "1|${stake_xdc}|${penalties}|${deposit}"
    else
        echo "0|0|0|0"
    fi
}

collect_disk_data() {
    local chain_size=0
    local disk_total=0
    local disk_used=0
    local disk_avail=0
    local growth_rate=0
    local days_until_full=-1
    
    # Get chain data size
    if [[ -d "$DATADIR" ]]; then
        chain_size=$(du -sb "$DATADIR" 2>/dev/null | cut -f1 || echo "0")
    elif [[ -d /work/xdcchain ]]; then
        chain_size=$(du -sb /work/xdcchain 2>/dev/null | cut -f1 || echo "0")
    fi
    
    # Get disk info
    local df_output
    df_output=$(df -B1 "$DATADIR" 2>/dev/null || df -B1 / 2>/dev/null || echo "")
    if [[ -n "$df_output" ]]; then
        disk_total=$(echo "$df_output" | tail -1 | awk '{print $2}')
        disk_used=$(echo "$df_output" | tail -1 | awk '{print $3}')
        disk_avail=$(echo "$df_output" | tail -1 | awk '{print $4}')
    fi
    
    # Calculate growth rate from history
    local state_file="/var/lib/node_exporter/textfile_collector/.xdc_metrics_state/disk_history"
    if [[ -f "$state_file" && $(wc -l < "$state_file" 2>/dev/null || echo "0") -gt 1 ]]; then
        local first last
        first=$(head -1 "$state_file")
        last=$(tail -1 "$state_file")
        
        local first_ts first_sz last_ts last_sz
        first_ts=$(echo "$first" | cut -d'|' -f1)
        first_sz=$(echo "$first" | cut -d'|' -f2)
        last_ts=$(echo "$last" | cut -d'|' -f1)
        last_sz=$(echo "$last" | cut -d'|' -f2)
        
        local time_diff=$((last_ts - first_ts))
        if [[ $time_diff -gt 3600 ]]; then
            local size_diff=$((last_sz - first_sz))
            if [[ $size_diff -gt 0 ]]; then
                growth_rate=$(echo "scale=2; ($size_diff / $time_diff) * 86400" | bc 2>/dev/null || echo "0")
                if [[ $(echo "$growth_rate > 0" | bc 2>/dev/null) -eq 1 && $disk_avail -gt 0 ]]; then
                    days_until_full=$(echo "scale=0; $disk_avail / $growth_rate" | bc 2>/dev/null || echo "-1")
                fi
            fi
        fi
    fi
    
    echo "${chain_size}|${disk_total}|${disk_used}|${disk_avail}|${growth_rate}|${days_until_full}"
}

collect_system_data() {
    local cpu_percent=0
    local mem_used_gb=0
    local mem_total_gb=0
    local mem_percent=0
    
    # CPU usage (5-second average)
    if [[ -f /proc/stat ]]; then
        local cpu1 cpu2 idle1 idle2 total1 total2
        cpu1=$(head -1 /proc/stat)
        idle1=$(echo "$cpu1" | awk '{print $5}')
        total1=$(echo "$cpu1" | awk '{sum=$2+$3+$4+$5+$6+$7+$8} END {print sum}')
        sleep 0.5
        cpu2=$(head -1 /proc/stat)
        idle2=$(echo "$cpu2" | awk '{print $5}')
        total2=$(echo "$cpu2" | awk '{sum=$2+$3+$4+$5+$6+$7+$8} END {print sum}')
        
        local total_diff idle_diff
        total_diff=$((total2 - total1))
        idle_diff=$((idle2 - idle1))
        
        if [[ $total_diff -gt 0 ]]; then
            cpu_percent=$(echo "scale=1; 100 * ($total_diff - $idle_diff) / $total_diff" | bc 2>/dev/null || echo "0")
        fi
    fi
    
    # Memory
    if [[ -f /proc/meminfo ]]; then
        local mem_total_kb mem_avail_kb
        mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        mem_avail_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        
        mem_total_gb=$(echo "scale=1; $mem_total_kb / 1048576" | bc 2>/dev/null || echo "0")
        local mem_avail_gb
        mem_avail_gb=$(echo "scale=1; $mem_avail_kb / 1048576" | bc 2>/dev/null || echo "0")
        mem_used_gb=$(echo "scale=1; $mem_total_gb - $mem_avail_gb" | bc 2>/dev/null || echo "0")
        
        if [[ $(echo "$mem_total_gb > 0" | bc 2>/dev/null) -eq 1 ]]; then
            mem_percent=$(echo "scale=1; ($mem_used_gb / $mem_total_gb) * 100" | bc 2>/dev/null || echo "0")
        fi
    fi
    
    echo "${cpu_percent}|${mem_used_gb}|${mem_total_gb}|${mem_percent}"
}

#==============================================================================
# Display Functions
#==============================================================================

draw_box_top() {
    echo "╔══════════════════════════════════════════╗"
}

draw_box_bottom() {
    echo "╚══════════════════════════════════════════╝"
}

draw_box_sep() {
    echo "╠══════════════════════════════════════════╣"
}

draw_box_line() {
    local label="$1"
    local value="$2"
    local color="${3:-$NC}"
    printf "║ ${BOLD}%-9s${NC}${color}%s${NC}%*s║\n" "$label" "$value" $((33 - ${#label} - ${#value})) ""
}

draw_box_line_center() {
    local text="$1"
    local color="${2:-$BOLD}"
    local len=${#text}
    local pad=$(( (42 - len) / 2 ))
    printf "║%*s${color}%s${NC}%*s║\n" $pad "" "$text" $((42 - len - pad)) ""
}

#==============================================================================
# Main Display
#==============================================================================

main() {
    # Check for jq
    if ! command -v jq >/dev/null 2>&1; then
        echo "ERROR: jq is required but not installed."
        echo "Install with: apt-get install jq  (or equivalent)"
        exit 1
    fi
    
    # Collect all data
    local node_data reward_data mn_data disk_data sys_data
    node_data=$(collect_node_data)
    
    local current_block highest_block is_syncing sync_percent peer_count outbound inbound coinbase uptime_sec
    current_block=$(echo "$node_data" | cut -d'|' -f1)
    highest_block=$(echo "$node_data" | cut -d'|' -f2)
    is_syncing=$(echo "$node_data" | cut -d'|' -f3)
    sync_percent=$(echo "$node_data" | cut -d'|' -f4)
    peer_count=$(echo "$node_data" | cut -d'|' -f5)
    outbound=$(echo "$node_data" | cut -d'|' -f6)
    inbound=$(echo "$node_data" | cut -d'|' -f7)
    coinbase=$(echo "$node_data" | cut -d'|' -f8)
    uptime_sec=$(echo "$node_data" | cut -d'|' -f9)
    
    reward_data=$(collect_reward_data "$coinbase")
    local balance total_rewards rewards_24h rewards_7d monthly_est
    balance=$(echo "$reward_data" | cut -d'|' -f1)
    total_rewards=$(echo "$reward_data" | cut -d'|' -f2)
    rewards_24h=$(echo "$reward_data" | cut -d'|' -f3)
    rewards_7d=$(echo "$reward_data" | cut -d'|' -f4)
    monthly_est=$(echo "$reward_data" | cut -d'|' -f5)
    
    mn_data=$(collect_masternode_data "$coinbase")
    local mn_status mn_stake mn_penalties mn_deposit
    mn_status=$(echo "$mn_data" | cut -d'|' -f1)
    mn_stake=$(echo "$mn_data" | cut -d'|' -f2)
    mn_penalties=$(echo "$mn_data" | cut -d'|' -f3)
    mn_deposit=$(echo "$mn_data" | cut -d'|' -f4)
    
    disk_data=$(collect_disk_data)
    local chain_size disk_total disk_used disk_avail growth_rate days_until_full
    chain_size=$(echo "$disk_data" | cut -d'|' -f1)
    disk_total=$(echo "$disk_data" | cut -d'|' -f2)
    disk_used=$(echo "$disk_data" | cut -d'|' -f3)
    disk_avail=$(echo "$disk_data" | cut -d'|' -f4)
    growth_rate=$(echo "$disk_data" | cut -d'|' -f5)
    days_until_full=$(echo "$disk_data" | cut -d'|' -f6)
    
    sys_data=$(collect_system_data)
    local cpu_percent mem_used_gb mem_total_gb mem_percent
    cpu_percent=$(echo "$sys_data" | cut -d'|' -f1)
    mem_used_gb=$(echo "$sys_data" | cut -d'|' -f2)
    mem_total_gb=$(echo "$sys_data" | cut -d'|' -f3)
    mem_percent=$(echo "$sys_data" | cut -d'|' -f4)
    
    # Determine status color and text
    local status_text status_color
    if [[ "$is_syncing" == "true" ]]; then
        status_text="${CHECK} Syncing (${sync_percent}%)"
        status_color="$YELLOW"
    else
        status_text="${CHECK} Synced (100%)"
        status_color="$GREEN"
    fi
    
    # Masternode status
    local mn_status_text mn_color
    case "$mn_status" in
        1) mn_status_text="${CHECK} Active"; mn_color="$GREEN" ;;
        2) mn_status_text="${CROSS} Slashed"; mn_color="$RED" ;;
        *) mn_status_text="${WARN} Inactive"; mn_color="$YELLOW" ;;
    esac
    
    # Calculate disk percentage
    local disk_percent
    if [[ $disk_total -gt 0 ]]; then
        disk_percent=$(echo "scale=1; ($disk_used / $disk_total) * 100" | bc 2>/dev/null || echo "0")
    else
        disk_percent="0"
    fi
    
    # Format growth rate
    local growth_text
    if [[ $(echo "$growth_rate > 0" | bc 2>/dev/null) -eq 1 ]]; then
        growth_text=$(format_bytes "${growth_rate%.*}")/day
    else
        growth_text="calculating..."
    fi
    
    # Format days until full
    local full_text
    if [[ "$days_until_full" == "-1" || "$days_until_full" == "0" ]]; then
        full_text="unknown"
    else
        full_text="~${days_until_full} days"
    fi
    
    # Draw the dashboard
    echo ""
    draw_box_top
    draw_box_line_center "XDC Node Owner Dashboard" "$BOLD"
    draw_box_sep
    draw_box_line "Node:" "xdc-mainnet-node"
    draw_box_line "Status:" "$status_text" "$status_color"
    draw_box_line "Block:" "$(format_number "$current_block") / $(format_number "$highest_block")"
    draw_box_line "Peers:" "${peer_count} (${outbound} out / ${inbound} in)"
    draw_box_line "Uptime:" "$(format_duration $uptime_sec)"
    draw_box_sep
    draw_box_line "Rewards:" "$(format_xdc "$total_rewards") XDC (total)"
    draw_box_line "Today:" "$(format_xdc "$rewards_24h") XDC"
    draw_box_line "Monthly:" "~$(format_xdc "$monthly_est") XDC (est.)"
    draw_box_sep
    draw_box_line "Disk:" "$(format_bytes "$disk_used") / $(format_bytes "$disk_total") (${disk_percent}%)"
    draw_box_line "Growth:" "${growth_text}"
    draw_box_line "Full in:" "${full_text}"
    draw_box_sep
    printf "║ ${BOLD}CPU:${NC} %5.1f%%  │  ${BOLD}RAM:${NC} %5.1f GB / %5.1f GB  ║\n" "$cpu_percent" "$mem_used_gb" "$mem_total_gb"
    draw_box_bottom
    echo ""
    
    # Show masternode info if active
    if [[ "$mn_status" == "1" ]]; then
        echo "  ${BOLD}Masternode Status:${NC} ${mn_status_text}"
        echo "  ${BOLD}Stake:${NC} $(format_xdc "$mn_stake") XDC"
        echo "  ${BOLD}Penalties:${NC} $mn_penalties"
        echo ""
    fi
    
    # Show wallet address (truncated)
    if [[ ${#coinbase} -gt 20 ]]; then
        echo "  ${BOLD}Wallet:${NC} ${coinbase:0:10}...${coinbase: -8}"
        echo ""
    fi
}

# Run main function
main "$@"
