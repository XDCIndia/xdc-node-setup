#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDC Monitor - XDC-Specific Monitoring
# Beyond basic health checks - epoch tracking, masternode rewards, fork detection
#==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source notification library
if [[ -f "${SCRIPT_DIR}/lib/notify.sh" ]]; then
    # shellcheck source=lib/notify.sh
    source "${SCRIPT_DIR}/lib/notify.sh"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
readonly XDC_RPC_URL="${XDC_RPC_URL:-http://localhost:8545}"
# Detect network for network-aware directory structure
detect_network() {
    local network="${NETWORK:-}"
    if [[ -z "$network" && -f "$(pwd)/config.toml" ]]; then
        network=$(grep -E '^\s*name\s*=' "$(pwd)/config.toml" 2>/dev/null | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -1)
    fi
    if [[ -z "$network" && -f "/opt/xdc-node/config.toml" ]]; then
        network=$(grep -E '^\s*name\s*=' "/opt/xdc-node/config.toml" 2>/dev/null | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -1)
    fi
    echo "${network:-mainnet}"
}
readonly XDC_NETWORK="${XDC_NETWORK:-$(detect_network)}"
readonly XDC_DATADIR="${XDC_DATADIR:-$(pwd)/${XDC_NETWORK}/xdcchain}"
readonly EPOCH_LENGTH=900
readonly BLOCK_TIME=2
readonly MASTERNODE_STAKE=10000000

# Public RPCs for fork detection
declare -a PUBLIC_RPCS=(
    "https://erpc.xinfin.network"
    "https://rpc.xinfin.network"
    "https://rpc.xdc.org"
)

# State tracking
CONTINUOUS_MODE=false
CHECK_INTERVAL=60  # seconds between checks in continuous mode
# XDC_STATE_DIR is set below (after network detection)
REPORT_FILE="${XDC_STATE_DIR:-/var/lib/xdc-node}/monitor-report.json"
# Use network-aware state directory for history
XDC_STATE_DIR="${XDC_STATE_DIR:-$(pwd)/${XDC_NETWORK}/.xdc-node}"
HISTORY_FILE="${XDC_STATE_DIR}/monitor-history.json"

#==============================================================================
# Utility Functions
#==============================================================================

log() { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1" >&2; }
error() { echo -e "${RED}✗${NC} $1" >&2; }
die() { error "$1"; exit 1; }

rpc_call() {
    local url="${1:-$XDC_RPC_URL}"
    local method="$2"
    local params="${3:-[]}"
    
    curl -s -m 10 -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        "$url" 2>/dev/null || echo '{}'
}

hex_to_dec() {
    local hex="${1#0x}"
    printf "%d\n" "0x${hex}" 2>/dev/null || echo "0"
}

#==============================================================================
# Epoch & Round Tracking
#==============================================================================

track_epoch() {
    echo -e "${BOLD}━━━ Epoch & Round Tracking ━━━${NC}"
    echo ""
    
    local response
    response=$(rpc_call "$XDC_RPC_URL" "eth_blockNumber")
    local block_hex
    block_hex=$(echo "$response" | jq -r '.result // "0x0"')
    local block_number
    block_number=$(hex_to_dec "$block_hex")
    
    # Calculate epoch and round
    local epoch=$((block_number / EPOCH_LENGTH))
    local round=$((block_number % EPOCH_LENGTH))
    local blocks_to_next_epoch=$((EPOCH_LENGTH - round))
    local seconds_to_next_epoch=$((blocks_to_next_epoch * BLOCK_TIME))
    local minutes_to_next_epoch=$((seconds_to_next_epoch / 60))
    
    echo -e "${CYAN}Current Epoch Information:${NC}"
    printf "  ${BOLD}%-25s${NC} %d\n" "Block Number:" "$block_number"
    printf "  ${BOLD}%-25s${NC} %d\n" "Epoch Number:" "$epoch"
    printf "  ${BOLD}%-25s${NC} %d / %d\n" "Round:" "$round" "$EPOCH_LENGTH"
    printf "  ${BOLD}%-25s${NC} %d blocks\n" "Blocks to Next Epoch:" "$blocks_to_next_epoch"
    printf "  ${BOLD}%-25s${NC} ~%d minutes\n" "ETA Next Epoch:" "$minutes_to_next_epoch"
    
    # Store for history
    update_history "epoch" "$epoch"
    update_history "block" "$block_number"
    
    echo ""
}

#==============================================================================
# Masternode Rewards
#==============================================================================

check_masternode_rewards() {
    echo -e "${BOLD}━━━ Masternode Rewards ━━━${NC}"
    echo ""
    
    # Check if we have a coinbase address
    local coinbase_file="${XDC_DATADIR}/.coinbase"
    if [[ ! -f "$coinbase_file" ]]; then
        warn "No coinbase address configured. Run masternode-setup.sh first."
        return 1
    fi
    
    local address
    address=$(cat "$coinbase_file")
    
    info "Checking masternode status for: $address"
    
    # Get current balance
    local response
    response=$(rpc_call "$XDC_RPC_URL" "eth_getBalance" '["'"$address"'", "latest"]')
    local balance_hex
    balance_hex=$(echo "$response" | jq -r '.result // "0x0"')
    local balance_wei
    balance_wei=$(hex_to_dec "$balance_hex")
    local balance_xdc
    balance_xdc=$(echo "scale=6; $balance_wei / 1000000000000000000" | bc)
    
    echo ""
    echo -e "${CYAN}Masternode Information:${NC}"
    printf "  ${BOLD}%-25s${NC} %s\n" "Address:" "$address"
    printf "  ${BOLD}%-25s${NC} %s XDC\n" "Current Balance:" "$balance_xdc"
    printf "  ${BOLD}%-25s${NC} %s XDC\n" "Required Stake:" "$MASTERNODE_STAKE"
    
    # Check if stake requirement is met
    if (( $(echo "$balance_xdc >= $MASTERNODE_STAKE" | bc -l) )); then
        log "✓ Stake requirement met"
    else
        warn "✗ Insufficient stake (need $MASTERNODE_STAKE XDC)"
    fi
    
    # Calculate estimated rewards (rough estimate)
    # XDC masternodes typically earn ~5-8% APY
    local estimated_daily
    estimated_daily=$(echo "scale=4; $MASTERNODE_STAKE * 0.06 / 365" | bc)
    local estimated_monthly
    estimated_monthly=$(echo "scale=4; $estimated_daily * 30" | bc)
    local estimated_yearly
    estimated_yearly=$(echo "scale=4; $MASTERNODE_STAKE * 0.06" | bc)
    
    echo ""
    echo -e "${CYAN}Estimated Rewards (6% APY):${NC}"
    printf "  ${BOLD}%-25s${NC} ~%s XDC\n" "Daily:" "$estimated_daily"
    printf "  ${BOLD}%-25s${NC} ~%s XDC\n" "Monthly:" "$estimated_monthly"
    printf "  ${BOLD}%-25s${NC} ~%s XDC\n" "Yearly:" "$estimated_yearly"
    
    echo ""
    info "Track actual rewards at: https://explorer.xinfin.network/address/$address"
    
    # Store for history
    update_history "balance" "$balance_xdc"
    
    echo ""
}

#==============================================================================
# Fork Detection
#==============================================================================

detect_fork() {
    echo -e "${BOLD}━━━ Fork Detection ━━━${NC}"
    echo ""
    
    # Get local block hash
    local response
    response=$(rpc_call "$XDC_RPC_URL" "eth_blockNumber")
    local block_hex
    block_hex=$(echo "$response" | jq -r '.result // "0x0"')
    local block_number
    block_number=$(hex_to_dec "$block_hex")
    
    # Check a recent block (10 blocks back to ensure finality)
    local check_block=$((block_number - 10))
    local check_block_hex
    check_block_hex=$(printf "0x%x" "$check_block")
    
    info "Checking block $check_block hash across multiple RPCs..."
    echo ""
    
    # Get local hash
    local local_hash
    local_hash=$(rpc_call "$XDC_RPC_URL" "eth_getBlockByNumber" '["'"$check_block_hex"'", false]' | \
        jq -r '.result.hash // "unknown"')
    
    printf "  ${BOLD}%-30s${NC} %s\n" "Local RPC:" "$local_hash"
    
    local mismatches=0
    local checked=0
    
    for rpc_url in "${PUBLIC_RPCS[@]}"; do
        local remote_hash
        remote_hash=$(rpc_call "$rpc_url" "eth_getBlockByNumber" '["'"$check_block_hex"'", false]' | \
            jq -r '.result.hash // "unreachable"')
        
        printf "  ${BOLD}%-30s${NC} %s" "$(echo "$rpc_url" | cut -d'/' -f3):" "$remote_hash"
        
        if [[ "$remote_hash" != "$local_hash" && "$remote_hash" != "unreachable" ]]; then
            echo -e " ${RED}[MISMATCH]${NC}"
            mismatches=$((mismatches + 1))
        elif [[ "$remote_hash" == "unreachable" ]]; then
            echo -e " ${YELLOW}[UNREACHABLE]${NC}"
        else
            echo -e " ${GREEN}[OK]${NC}"
        fi
        
        checked=$((checked + 1))
    done
    
    echo ""
    
    if [[ $mismatches -gt 0 ]]; then
        error "FORK DETECTED! Local chain diverges from public RPCs."
        error "Consider re-syncing from a trusted snapshot."
        
        # Send notification if available
        if command -v notify_alert &>/dev/null; then
            notify_alert "critical" "🚨 Fork Detected" \
                "Local XDC node hash mismatch at block $check_block. $mismatches/$checked RPCs differ." \
                "fork_detection"
        fi
        
        return 1
    else
        log "✓ No fork detected - local chain matches public RPCs"
    fi
    
    echo ""
}

#==============================================================================
# Txpool Monitor
#==============================================================================

monitor_txpool() {
    echo -e "${BOLD}━━━ Txpool Monitor ━━━${NC}"
    echo ""
    
    local response
    response=$(rpc_call "$XDC_RPC_URL" "txpool_status")
    
    local pending_hex
    pending_hex=$(echo "$response" | jq -r '.result.pending // "0x0"')
    local queued_hex
    queued_hex=$(echo "$response" | jq -r '.result.queued // "0x0"')
    
    local pending
    pending=$(hex_to_dec "$pending_hex")
    local queued
    queued=$(hex_to_dec "$queued_hex")
    local total=$((pending + queued))
    
    echo -e "${CYAN}Transaction Pool Status:${NC}"
    printf "  ${BOLD}%-20s${NC} %d\n" "Pending:" "$pending"
    printf "  ${BOLD}%-20s${NC} %d\n" "Queued:" "$queued"
    printf "  ${BOLD}%-20s${NC} %d\n" "Total:" "$total"
    
    # Alert if congested
    if [[ $pending -gt 10000 ]]; then
        warn "High pending transaction count - network may be congested"
        
        if command -v notify_alert &>/dev/null; then
            notify_alert "warning" "⚠️ Txpool Congestion" \
                "XDC txpool has $pending pending transactions." \
                "txpool_congestion"
        fi
    fi
    
    # Get gas price
    local gas_response
    gas_response=$(rpc_call "$XDC_RPC_URL" "eth_gasPrice")
    local gas_hex
    gas_hex=$(echo "$gas_response" | jq -r '.result // "0x0"')
    local gas_wei
    gas_wei=$(hex_to_dec "$gas_hex")
    local gas_gwei
    gas_gwei=$(echo "scale=4; $gas_wei / 1000000000" | bc)
    
    echo ""
    printf "  ${BOLD}%-20s${NC} %s Gwei\n" "Current Gas Price:" "$gas_gwei"
    
    update_history "txpool_pending" "$pending"
    update_history "txpool_queued" "$queued"
    
    echo ""
}

#==============================================================================
# Block Propagation
#==============================================================================

measure_block_propagation() {
    echo -e "${BOLD}━━━ Block Propagation ━━━${NC}"
    echo ""
    
    # Measure time to receive latest block
    local start_time
    start_time=$(date +%s%N)
    
    local response
    response=$(rpc_call "$XDC_RPC_URL" "eth_getBlockByNumber" '["latest", false]')
    
    local end_time
    end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))
    
    local block_number
    block_number=$(echo "$response" | jq -r '.result.number // "0x0"')
    local block_timestamp
    block_timestamp=$(echo "$response" | jq -r '.result.timestamp // "0x0"')
    local block_hash
    block_hash=$(echo "$response" | jq -r '.result.hash // "unknown"')
    
    block_number=$(hex_to_dec "$block_number")
    block_timestamp=$(hex_to_dec "$block_timestamp")
    
    local current_time
    current_time=$(date +%s)
    local propagation_delay=$((current_time - block_timestamp))
    
    echo -e "${CYAN}Latest Block Information:${NC}"
    printf "  ${BOLD}%-25s${NC} %d\n" "Block Number:" "$block_number"
    printf "  ${BOLD}%-25s${NC} %s\n" "Block Hash:" "${block_hash:0:20}..."
    printf "  ${BOLD}%-25s${NC} %d ms\n" "RPC Response Time:" "$duration_ms"
    printf "  ${BOLD}%-25s${NC} %d seconds\n" "Propagation Delay:" "$propagation_delay"
    
    if [[ $propagation_delay -gt 10 ]]; then
        warn "High propagation delay - node may be behind"
    else
        log "✓ Block propagation within normal range"
    fi
    
    update_history "propagation_ms" "$duration_ms"
    
    echo ""
}

#==============================================================================
# Peer Quality
#==============================================================================

analyze_peer_quality() {
    echo -e "${BOLD}━━━ Peer Quality Analysis ━━━${NC}"
    echo ""
    
    local response
    response=$(rpc_call "$XDC_RPC_URL" "admin_peers")
    
    local peer_count
    peer_count=$(echo "$response" | jq '.result | length')
    
    echo -e "${CYAN}Connected Peers: $peer_count${NC}"
    echo ""
    
    if [[ $peer_count -eq 0 ]]; then
        error "No peers connected - check network connectivity"
        return 1
    fi
    
    # Analyze each peer
    echo -e "${BOLD}%-20s %-15s %-10s %-10s %s${NC}" "Node" "IP" "Protocol" "Height" "Score"
    echo "─────────────────────────────────────────────────────────────────────"
    
    local total_height=0
    local high_quality=0
    local stale_peers=0
    
    # Get our height for comparison
    local our_height_response
    our_height_response=$(rpc_call "$XDC_RPC_URL" "eth_blockNumber")
    local our_height_hex
    our_height_hex=$(echo "$our_height_response" | jq -r '.result // "0x0"')
    local our_height
    our_height=$(hex_to_dec "$our_height_hex")
    
    local i=0
    while [[ $i -lt $peer_count ]]; do
        local peer
        peer=$(echo "$response" | jq -r ".result[$i]")
        
        local node_id
        node_id=$(echo "$peer" | jq -r '.id // "unknown"')
        local network
        network=$(echo "$peer" | jq -r '.network // {}')
        local remote_address
        remote_address=$(echo "$network" | jq -r '.remoteAddress // "unknown"')
        local local_address
        local_address=$(echo "$network" | jq -r '.localAddress // "unknown"')
        local protocols
        protocols=$(echo "$peer" | jq -r '.protocols // {}')
        local eth_protocol
        eth_protocol=$(echo "$protocols" | jq -r '.eth // {}')
        local version
        version=$(echo "$eth_protocol" | jq -r '.version // "unknown"')
        local height_hex
        height_hex=$(echo "$eth_protocol" | jq -r '.head // "0x0"')
        local height
        height=$(hex_to_dec "$height_hex")
        
        # Calculate score
        local score=100
        
        # Deduct for height difference
        local height_diff=$((our_height - height))
        if [[ $height_diff -gt 10 ]]; then
            score=$((score - 30))
            ((stale_peers++))
        elif [[ $height_diff -gt 5 ]]; then
            score=$((score - 15))
        fi
        
        # Deduct for old protocol version
        if [[ "$version" != "eth/100" ]]; then
            score=$((score - 10))
        fi
        
        if [[ $score -gt 80 ]]; then
            ((high_quality++))
        fi
        
        # Format output
        local score_color="${GREEN}"
        if [[ $score -lt 60 ]]; then
            score_color="${RED}"
        elif [[ $score -lt 80 ]]; then
            score_color="${YELLOW}"
        fi
        
        local ip
        ip=$(echo "$remote_address" | cut -d':' -f1)
        
        printf "%-20s %-15s %-10s %-10d ${score_color}%d${NC}\n" \
            "${node_id:0:18}..." "$ip" "$version" "$height" "$score"
        
        total_height=$((total_height + height))
        i=$((i + 1))
    done
    
    echo ""
    echo -e "${CYAN}Summary:${NC}"
    printf "  ${BOLD}%-20s${NC} %d / %d\n" "High Quality Peers:" "$high_quality" "$peer_count"
    printf "  ${BOLD}%-20s${NC} %d\n" "Stale Peers:" "$stale_peers"
    
    if [[ $stale_peers -gt 0 ]]; then
        echo ""
        warn "Found $stale_peers stale peers. Consider restarting node to refresh peers."
    fi
    
    echo ""
}

#==============================================================================
# History Tracking
#==============================================================================

update_history() {
    local metric="$1"
    local value="$2"
    local timestamp
    timestamp=$(date +%s)
    
    mkdir -p "$(dirname "$HISTORY_FILE")"
    
    # Initialize if not exists
    if [[ ! -f "$HISTORY_FILE" ]]; then
        echo "{}" > "$HISTORY_FILE"
    fi
    
    # Update history (keep last 100 entries per metric)
    local tmp_file
    tmp_file=$(mktemp)
    jq --arg metric "$metric" --argjson value "$value" --argjson ts "$timestamp" \
        '.[$metric] = ((.[$metric] // []) + [{timestamp: $ts, value: $value}] | last([100] | length))' \
        "$HISTORY_FILE" > "$tmp_file" && mv "$tmp_file" "$HISTORY_FILE" 2>/dev/null || true
}

#==============================================================================
# Generate Report
#==============================================================================

generate_report() {
    local output_file="${1:-$REPORT_FILE}"
    
    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"node\": \"$(hostname)\","
    
    # Epoch info
    local response
    response=$(rpc_call "$XDC_RPC_URL" "eth_blockNumber")
    local block_number
    block_number=$(hex_to_dec "$(echo "$response" | jq -r '.result // "0x0"')")
    local epoch=$((block_number / EPOCH_LENGTH))
    local round=$((block_number % EPOCH_LENGTH))
    
    echo "  \"epoch\": {"
    echo "    \"number\": $epoch,"
    echo "    \"round\": $round,"
    echo "    \"block\": $block_number"
    echo "  },"
    
    # Peers
    local peer_count
    peer_count=$(rpc_call "$XDC_RPC_URL" "net_peerCount" | jq -r '.result // "0x0"')
    peer_count=$(hex_to_dec "$peer_count")
    
    echo "  \"peers\": $peer_count,"
    
    # Txpool
    local txpool
    txpool=$(rpc_call "$XDC_RPC_URL" "txpool_status")
    local pending
    pending=$(hex_to_dec "$(echo "$txpool" | jq -r '.result.pending // "0x0"')")
    local queued
    queued=$(hex_to_dec "$(echo "$txpool" | jq -r '.result.queued // "0x0"')")
    
    echo "  \"txpool\": {"
    echo "    \"pending\": $pending,"
    echo "    \"queued\": $queued"
    echo "  }"
    
    echo "}"
}

#==============================================================================
# Continuous Mode
#==============================================================================

run_continuous() {
    local check_interval="${1:-60}"
    local check_count=0
    
    echo -e "${BOLD}━━━ XDC Monitor - Continuous Mode ━━━${NC}"
    echo ""
    info "Running checks every $check_interval seconds"
    info "Press Ctrl+C to stop"
    echo ""
    
    while true; do
        clear
        echo -e "${BOLD}XDC Monitor - $(date '+%Y-%m-%d %H:%M:%S')${NC}"
        echo ""
        
        # Run all checks
        track_epoch
        check_masternode_rewards 2>/dev/null || true
        
        if [[ $((check_count % 10)) -eq 0 ]]; then
            # Run expensive checks every 10 iterations
            detect_fork
            analyze_peer_quality
        fi
        
        monitor_txpool
        measure_block_propagation
        
        # Generate report
        generate_report > "$REPORT_FILE"
        
        check_count=$((check_count + 1))
        
        echo ""
        echo -e "${DIM}Check #$check_count - Next check in ${check_interval}s...${NC}"
        sleep "$check_interval"
    done
}

#==============================================================================
# XDPoS Consensus Monitoring
#==============================================================================

cmd_consensus() {
    echo -e "${BOLD}━━━ XDPoS Consensus Check ━━━${NC}"
    echo ""
    
    # Run consensus monitor if available
    if [[ -f "${SCRIPT_DIR}/consensus-monitor.sh" ]]; then
        bash "${SCRIPT_DIR}/consensus-monitor.sh" --all
    else
        # Fallback to basic epoch tracking
        track_epoch
        
        # Check for epoch change alert
        mkdir -p "${XDC_STATE_DIR}" 2>&1 && local state_file="${XDC_STATE_DIR}/consensus-state.json"
        if [[ -f "$state_file" ]]; then
            local prev_epoch
            prev_epoch=$(jq -r '.epoch // 0' "$state_file" 2>/dev/null || echo "0")
            local current_block
            current_block=$(rpc_call "$XDC_RPC_URL" "eth_blockNumber" | jq -r '.result // "0x0"')
            current_block=$(hex_to_dec "$current_block")
            local current_epoch=$((current_block / EPOCH_LENGTH))
            
            if [[ "$prev_epoch" -ne "$current_epoch" && "$prev_epoch" -ne "0" ]]; then
                log "✓ Epoch transition detected: $prev_epoch → $current_epoch"
                if command -v notify_alert &>/dev/null; then
                    notify_alert "info" "🔄 Epoch Change" \
                        "XDPoS epoch transition: $prev_epoch → $current_epoch" \
                        "epoch_change"
                fi
            fi
            
            echo "{\"epoch\": $current_epoch, \"block\": $current_block, \"timestamp\": $(date +%s)}" > "$state_file"
        fi
    fi
}

#==============================================================================
# Governance Monitoring
#==============================================================================

cmd_governance() {
    echo -e "${BOLD}━━━ XDC Governance Check ━━━${NC}"
    echo ""
    
    # Run governance monitor if available
    if [[ -f "${SCRIPT_DIR}/governance.sh" ]]; then
        bash "${SCRIPT_DIR}/governance.sh" proposals
    else
        info "Governance tools not available. Install the full XDC Node Setup."
    fi
    
    # Check for new proposals
    mkdir -p "${XDC_STATE_DIR}" 2>&1 && local proposals_file="${XDC_STATE_DIR}/proposals.json"
    if [[ -f "$proposals_file" ]]; then
        local proposal_count
        proposal_count=$(jq 'length' "$proposals_file" 2>/dev/null || echo "0")
        
        if [[ "$proposal_count" -gt 0 ]]; then
            info "Found $proposal_count active proposal(s)"
            
            # Alert on new proposals
            mkdir -p "${XDC_STATE_DIR}" 2>&1 && local state_file="${XDC_STATE_DIR}/governance-state.json"
            if [[ -f "$state_file" ]]; then
                local prev_count
                prev_count=$(jq -r '.count // 0' "$state_file" 2>/dev/null || echo "0")
                if [[ "$proposal_count" -gt "$prev_count" ]]; then
                    local new_proposals=$((proposal_count - prev_count))
                    if command -v notify_alert &>/dev/null; then
                        notify_alert "info" "📋 New Proposal" \
                            "$new_proposals new governance proposal(s) available" \
                            "proposal_new"
                    fi
                fi
            fi
            
            echo "{\"count\": $proposal_count, \"timestamp\": $(date +%s)}" > "$state_file"
        fi
    fi
}

#==============================================================================
# Help
#==============================================================================

show_help() {
    cat << EOF
XDC Monitor - XDC-Specific Node Monitoring

Usage: $(basename "$0") [options]

Options:
    --epoch                 Show epoch and round information
    --rewards               Show masternode rewards status
    --fork                  Check for chain forks
    --txpool                Monitor transaction pool
    --propagation           Measure block propagation
    --peers                 Analyze peer quality
    --all                   Run all checks
    --continuous            Run in continuous monitoring mode
    --interval N            Check interval in seconds (default: 60)
    --report [file]         Generate JSON report
    --masternode-check      Quick masternode status check
    --masternode-status     Full masternode status report
    --help, -h              Show this help message

Examples:
    # Run all checks once
    $(basename "$0") --all

    # Continuous monitoring (default)
    $(basename "$0") --continuous

    # Check every 30 seconds
    $(basename "$0") --continuous --interval 30

    # Masternode status
    $(basename "$0") --masternode-status

    # Generate report
    $(basename "$0") --all --report /var/lib/xdc-node/monitor.json

Description:
    Advanced XDC-specific monitoring beyond basic health checks:
    - Epoch tracking (XDPoS consensus rounds)
    - Masternode rewards estimation
    - Fork detection via multiple RPCs
    - Transaction pool monitoring
    - Block propagation measurement
    - Peer quality scoring
    - XDPoS consensus monitoring (--consensus)
    - Governance monitoring (--governance)

Notifications:
    Critical alerts are sent via configured notification channels.
    Configure in /etc/xdc-node/notify.conf

EOF
}

#==============================================================================
# Main
#==============================================================================

main() {
    local command=""
    local interval=60
    local report_file=""
    local run_all=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --epoch|--rewards|--fork|--txpool|--propagation|--peers)
                command="${1#--}"
                shift
                ;;
            --all)
                run_all=true
                shift
                ;;
            --continuous)
                CONTINUOUS_MODE=true
                shift
                ;;
            --interval)
                interval="${2:-60}"
                shift 2
                ;;
            --report)
                report_file="${2:-$REPORT_FILE}"
                shift 2
                ;;
            --consensus)
                cmd_consensus
                shift
                ;;
            --governance)
                cmd_governance
                shift
                ;;
            --masternode-check)
                command="masternode_check"
                shift
                ;;
            --masternode-status)
                command="masternode_status"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    # Ensure data directory exists
    mkdir -p "$(dirname "$REPORT_FILE")"
    
    # Run continuous mode
    if [[ "$CONTINUOUS_MODE" == "true" ]]; then
        run_continuous "$interval"
        exit 0
    fi
    
    # Run specific or all checks
    if [[ "$run_all" == "true" ]]; then
        track_epoch
        check_masternode_rewards 2>/dev/null || true
        detect_fork
        monitor_txpool
        measure_block_propagation
        analyze_peer_quality
        
        if [[ -n "$report_file" ]]; then
            generate_report "$report_file" > "$report_file"
            log "Report saved to: $report_file"
        fi
    elif [[ "$command" == "masternode_check" ]]; then
        # Quick masternode check
        if [[ -f "${XDC_DATADIR}/.coinbase" ]]; then
            echo "Masternode configured: $(cat "${XDC_DATADIR}/.coinbase")"
            exit 0
        else
            echo "Masternode not configured"
            exit 1
        fi
    elif [[ "$command" == "masternode_status" ]]; then
        track_epoch
        check_masternode_rewards
        analyze_peer_quality
    elif [[ -n "$command" ]]; then
        case "$command" in
            epoch) track_epoch ;;
            rewards) check_masternode_rewards ;;
            fork) detect_fork ;;
            txpool) monitor_txpool ;;
            propagation) measure_block_propagation ;;
            peers) analyze_peer_quality ;;
            *) warn "Unknown command: $command" ;;
        esac
    else
        # Default: show help
        show_help
    fi
}

main "$@"
