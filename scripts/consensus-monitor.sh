#!/usr/bin/env bash
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || source "/opt/xdc-node/scripts/lib/common.sh" || true


#==============================================================================
# XDPoS Consensus Monitor - Real-time XDPoS v2 Consensus Monitoring
#==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source notification library
if [[ -f "${SCRIPT_DIR}/lib/notify.sh" ]]; then
    # shellcheck source=lib/notify.sh
    source "${SCRIPT_DIR}/lib/notify.sh"
fi

# Source XDC contracts library
if [[ -f "${SCRIPT_DIR}/lib/xdc-contracts.sh" ]]; then
    # shellcheck source=lib/xdc-contracts.sh
    source "${SCRIPT_DIR}/lib/xdc-contracts.sh"
fi

# Colors
# Configuration
readonly XDC_RPC_URL="${XDC_RPC_URL:-http://localhost:8545}"
readonly EPOCH_LENGTH=900
readonly BLOCK_TIME=2
readonly XDPOS_V2_CONFIG="${PROJECT_DIR}/configs/xdpos-v2.json"

# State tracking
WATCH_MODE=false
WATCH_INTERVAL=5

#==============================================================================
# Utility Functions
#==============================================================================

# XDPoS v2 gap block detection
is_gap_block() {
    local block_num=$1
    local epoch_start=$(( (block_num / EPOCH_LENGTH) * EPOCH_LENGTH ))
    local offset=$((block_num - epoch_start))
    # Gap blocks at positions: 0, 1, 2, 3, 4, 450, 451, 452, 453, 454
    [[ $offset -le 4 || ($offset -ge 450 && $offset -le 454) ]]
}

format_time() {
    local seconds="$1"
    local minutes=$((seconds / 60))
    local remaining_seconds=$((seconds % 60))
    printf "%dm %ds" "$minutes" "$remaining_seconds"
}

progress_bar() {
    local current="$1"
    local total="$2"
    local width="${3:-40}"
    
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "["
    for ((i = 0; i < filled; i++)); do printf "▓"; done
    for ((i = 0; i < empty; i++)); do printf "░"; done
    printf "]"
}

#==============================================================================
# Epoch Tracking
#==============================================================================

track_epoch() {
    echo -e "${BOLD}━━━ XDPoS Epoch Tracking ━━━${NC}"
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
    local epoch_progress=$((round * 100 / EPOCH_LENGTH))
    
    echo -e "${CYAN}Epoch Information:${NC}"
    printf "  ${BOLD}%-25s${NC} %d\n" "Current Epoch:" "$epoch"
    printf "  ${BOLD}%-25s${NC} %d\n" "Current Block:" "$block_number"
    printf "  ${BOLD}%-25s${NC} %d / %d\n" "Round:" "$round" "$EPOCH_LENGTH"
    printf "  ${BOLD}%-25s${NC} %d%%\n" "Epoch Progress:" "$epoch_progress"
    printf "  ${BOLD}%-25s${NC} %d blocks\n" "Blocks to Next Epoch:" "$blocks_to_next_epoch"
    printf "  ${BOLD}%-25s${NC} ~%s\n" "ETA Next Epoch:" "$(format_time $seconds_to_next_epoch)"
    
    # Gap block status
    printf "  ${BOLD}%-25s${NC} " "Gap Block:"
    if is_gap_block "$block_number"; then
        echo -e "${YELLOW}YES (positions 0-4 or 450-454)${NC}"
    else
        echo -e "${GREEN}No${NC}"
    fi
    
    # Progress bar
    echo ""
    progress_bar "$round" "$EPOCH_LENGTH" 50
    printf " %d%%\n" "$epoch_progress"
    
    # Store for alerts
    mkdir -p "${XDC_STATE_DIR}" 2>&1 && local state_file="${XDC_STATE_DIR}/consensus-state.json"
    mkdir -p "$(dirname "$state_file")"
    
    if [[ -f "$state_file" ]]; then
        local prev_epoch
        prev_epoch=$(jq -r '.epoch // 0' "$state_file" 2>/dev/null || echo "0")
        if [[ "$prev_epoch" -ne "$epoch" && "$prev_epoch" -ne "0" ]]; then
            log "✓ Epoch transition detected: $prev_epoch → $epoch"
            if command -v notify_alert &>/dev/null; then
                notify_alert "info" "🔄 Epoch Change" \
                    "XDPoS epoch transition: $prev_epoch → $epoch" \
                    "epoch_change"
            fi
        fi
    fi
    
    echo "{\"epoch\": $epoch, \"round\": $round, \"block\": $block_number, \"timestamp\": $(date +%s)}" > "$state_file"
    
    echo ""
}

#==============================================================================
# Round Tracking
#==============================================================================

track_rounds() {
    echo -e "${BOLD}━━━ XDPoS Round Tracking ━━━${NC}"
    echo ""
    
    local response
    response=$(rpc_call "$XDC_RPC_URL" "eth_blockNumber")
    local block_hex
    block_hex=$(echo "$response" | jq -r '.result // "0x0"')
    local block_number
    block_number=$(hex_to_dec "$block_hex")
    
    local epoch=$((block_number / EPOCH_LENGTH))
    local round=$((block_number % EPOCH_LENGTH))
    local round_in_epoch=$((round % 10))
    
    # Get masternode rotation info
    local masternodes
    masternodes=$(get_masternodes 2>/dev/null || echo "[]")
    local mn_count
    mn_count=$(echo "$masternodes" | jq 'length')
    
    echo -e "${CYAN}Round Information:${NC}"
    printf "  ${BOLD}%-25s${NC} %d\n" "Current Round:" "$round"
    printf "  ${BOLD}%-25s${NC} %d\n" "Epoch Number:" "$epoch"
    printf "  ${BOLD}%-25s${NC} %d/10\n" "Round in Epoch Cycle:" "$round_in_epoch"
    printf "  ${BOLD}%-25s${NC} %d\n" "Active Masternodes:" "$mn_count"
    
    # Round timeline
    echo ""
    echo -e "${CYAN}Round Timeline (Epoch $epoch):${NC}"
    local timeline_start=$((epoch * EPOCH_LENGTH))
    local i
    for ((i = 0; i < 10; i++)); do
        local cycle_start=$((timeline_start + i * 90))
        local cycle_end=$((cycle_start + 89))
        local current_marker=""
        
        if [[ $i -eq $((round / 90)) ]]; then
            current_marker="${GREEN}◀ CURRENT${NC}"
        elif [[ $i -lt $((round / 90)) ]]; then
            current_marker="${DIM}✓${NC}"
        fi
        
        printf "  Round %d: Blocks %d-%d %s\n" "$i" "$cycle_start" "$cycle_end" "$current_marker"
    done
    
    echo ""
}

#==============================================================================
# Vote Tracking
#==============================================================================

track_votes() {
    echo -e "${BOLD}━━━ XDPoS Vote Tracking ━━━${NC}"
    echo ""
    
    # Get recent blocks and their vote counts
    local response
    response=$(rpc_call "$XDC_RPC_URL" "eth_blockNumber")
    local current_block
    current_block=$(hex_to_dec "$(echo "$response" | jq -r '.result // "0x0"')")
    
    echo -e "${CYAN}Recent Block Votes:${NC}"
    printf "  ${BOLD}%-12s %-15s %-15s %-10s${NC}\n" "Block" "Hash" "Signer" "Votes"
    echo "─────────────────────────────────────────────────────────────"
    
    local i
    for ((i = 0; i < 10; i++)); do
        local block_num=$((current_block - i))
        local block_hex
        block_hex=$(printf "0x%x" "$block_num")
        
        local block_data
        block_data=$(rpc_call "$XDC_RPC_URL" "eth_getBlockByNumber" '["'"$block_hex"'", false]')
        
        local hash
        hash=$(echo "$block_data" | jq -r '.result.hash // "unknown"' | cut -c1-12)
        local signer
        signer=$(echo "$block_data" | jq -r '.result.miner // "unknown"' | cut -c1-12)
        local extra_data
        extra_data=$(echo "$block_data" | jq -r '.result.extraData // "0x"')
        
        # Extract vote count from extraData (XDPoS v2 specific)
        local vote_count="N/A"
        if [[ ${#extra_data} -gt 130 ]]; then
            # XDPoS v2 stores validator signatures in extraData
            local sig_start=130
            local sig_length=$((${#extra_data} - sig_start))
            vote_count=$((sig_length / 130))
        fi
        
        if [[ $i -eq 0 ]]; then
            printf "  ${GREEN}%-12d${NC} %-15s %-15s %-10s\n" "$block_num" "$hash..." "$signer..." "$vote_count"
        else
            printf "  %-12d %-15s %-15s %-10s\n" "$block_num" "$hash..." "$signer..." "$vote_count"
        fi
    done
    
    echo ""
    info "Vote data extracted from block extraData field"
    echo ""
}

#==============================================================================
# Block Finality
#==============================================================================

check_finality() {
    echo -e "${BOLD}━━━ XDPoS Block Finality ━━━${NC}"
    echo ""
    
    local response
    response=$(rpc_call "$XDC_RPC_URL" "eth_blockNumber")
    local current_block
    current_block=$(hex_to_dec "$(echo "$response" | jq -r '.result // "0x0"')")
    
    local epoch=$((current_block / EPOCH_LENGTH))
    local epoch_start=$((epoch * EPOCH_LENGTH))
    local checkpoint=$((epoch_start + EPOCH_LENGTH))
    local blocks_to_checkpoint=$((checkpoint - current_block))
    local seconds_to_checkpoint=$((blocks_to_checkpoint * BLOCK_TIME))
    
    # Check if current block is a checkpoint
    local is_checkpoint=false
    if [[ $((current_block % EPOCH_LENGTH)) -eq 0 ]]; then
        is_checkpoint=true
    fi
    
    echo -e "${CYAN}Finality Status:${NC}"
    printf "  ${BOLD}%-25s${NC} %d\n" "Current Block:" "$current_block"
    printf "  ${BOLD}%-25s${NC} %d\n" "Current Epoch:" "$epoch"
    printf "  ${BOLD}%-25s${NC} %d\n" "Next Checkpoint:" "$checkpoint"
    printf "  ${BOLD}%-25s${NC} %d blocks\n" "Blocks to Checkpoint:" "$blocks_to_checkpoint"
    printf "  ${BOLD}%-25s${NC} ~%s\n" "ETA Checkpoint:" "$(format_time $seconds_to_checkpoint)"
    printf "  ${BOLD}%-25s${NC} " "Is Checkpoint Block:"
    if [[ "$is_checkpoint" == "true" ]]; then
        echo -e "${GREEN}YES ✓${NC}"
    else
        echo -e "${YELLOW}No${NC}"
    fi
    
    # Check latest finalized block (XDPoS v2)
    local finalized_response
    finalized_response=$(rpc_call "$XDC_RPC_URL" "eth_getFinalizedBlock" '[]' 2>/dev/null || echo '{}')
    local finalized_block
    finalized_block=$(hex_to_dec "$(echo "$finalized_response" | jq -r '.result // "0x0"')" 2>/dev/null || echo "0")
    
    if [[ "$finalized_block" -gt 0 ]]; then
        local finality_gap=$((current_block - finalized_block))
        echo ""
        printf "  ${BOLD}%-25s${NC} %d\n" "Finalized Block:" "$finalized_block"
        printf "  ${BOLD}%-25s${NC} %d blocks\n" "Finality Gap:" "$finality_gap"
    fi
    
    echo ""
}

#==============================================================================
# Masternode Rotation
#==============================================================================

check_rotation() {
    echo -e "${BOLD}━━━ Masternode Rotation Schedule ━━━${NC}"
    echo ""
    
    local masternodes
    masternodes=$(get_masternodes 2>/dev/null || echo "[]")
    local mn_count
    mn_count=$(echo "$masternodes" | jq 'length')
    
    if [[ "$mn_count" -eq 0 ]]; then
        warn "Unable to retrieve masternode list. Ensure node is fully synced."
        echo ""
        return 1
    fi
    
    local response
    response=$(rpc_call "$XDC_RPC_URL" "eth_blockNumber")
    local current_block
    current_block=$(hex_to_dec "$(echo "$response" | jq -r '.result // "0x0"')")
    
    local epoch=$((current_block / EPOCH_LENGTH))
    local round=$((current_block % EPOCH_LENGTH))
    local current_cycle=$((round / 90))
    local blocks_in_cycle=$((round % 90))
    local blocks_to_next_cycle=$((90 - blocks_in_cycle))
    
    echo -e "${CYAN}Rotation Status:${NC}"
    printf "  ${BOLD}%-25s${NC} %d\n" "Current Epoch:" "$epoch"
    printf "  ${BOLD}%-25s${NC} %d / 9\n" "Current Cycle:" "$current_cycle"
    printf "  ${BOLD}%-25s${NC} %d blocks\n" "Blocks in Cycle:" "$blocks_in_cycle"
    printf "  ${BOLD}%-25s${NC} %d blocks\n" "Blocks to Next Cycle:" "$blocks_to_next_cycle"
    printf "  ${BOLD}%-25s${NC} %d\n" "Total Masternodes:" "$mn_count"
    
    echo ""
    echo -e "${CYAN}Upcoming Masternode Schedule:${NC}"
    printf "  ${BOLD}%-10s %-45s %-20s${NC}\n" "Cycle" "Masternode Address" "Status"
    echo "─────────────────────────────────────────────────────────────────────"
    
    # Show masternodes for next few cycles
    local i
    for ((i = 0; i < 5 && i < mn_count; i++)); do
        local cycle=$((current_cycle + i))
        if [[ $cycle -ge 10 ]]; then
            cycle=$((cycle % 10))
        fi
        
        local mn_index=$(( (epoch * 10 + cycle) % mn_count ))
        local mn_address
        mn_address=$(echo "$masternodes" | jq -r ".[$mn_index] // \"unknown\"")
        
        local status=""
        if [[ $i -eq 0 ]]; then
            status="${GREEN}CURRENT${NC}"
        elif [[ $i -eq 1 ]]; then
            status="${YELLOW}NEXT${NC}"
        else
            status="${DIM}Upcoming${NC}"
        fi
        
        printf "  %-10d %-45s %b\n" "$cycle" "$mn_address" "$status"
    done
    
    echo ""
}

#==============================================================================
# Penalty Tracking
#==============================================================================

check_penalties() {
    echo -e "${BOLD}━━━ XDPoS Penalty Tracking ━━━${NC}"
    echo ""
    
    local penalties
    penalties=$(get_penalties 2>/dev/null || echo "[]")
    local penalty_count
    penalty_count=$(echo "$penalties" | jq 'length')
    
    if [[ "$penalty_count" -eq 0 ]]; then
        log "✓ No active penalties"
        echo ""
        return 0
    fi
    
    warn "Found $penalty_count active penalties!"
    echo ""
    
    echo -e "${CYAN}Active Penalties:${NC}"
    printf "  ${BOLD}%-45s %-15s %-30s${NC}\n" "Masternode" "Reason Code" "Description"
    echo "─────────────────────────────────────────────────────────────────────────────────"
    
    # Parse penalties
    echo "$penalties" | jq -r '.[] | @base64' | while read -r penalty; do
        local decoded
        decoded=$(echo "$penalty" | base64 -d)
        local address
        address=$(echo "$decoded" | jq -r '.address // "unknown"')
        local reason
        reason=$(echo "$decoded" | jq -r '.reason // "unknown"')
        local desc
        desc=$(echo "$decoded" | jq -r '.description // "No description"')
        
        local reason_text=""
        case "$reason" in
            1) reason_text="MissedBlocks" ;;
            2) reason_text="ForkDetected" ;;
            3) reason_text="DoubleSign" ;;
            4) reason_text="Offline" ;;
            *) reason_text="Unknown($reason)" ;;
        esac
        
        printf "  ${RED}%-45s${NC} %-15s %-30s\n" "$address" "$reason_text" "$desc"
    done
    
    # Alert on new penalties
    mkdir -p "${XDC_STATE_DIR}" 2>&1 && local state_file="${XDC_STATE_DIR}/penalty-state.json"
    if [[ -f "$state_file" ]]; then
        local prev_count
        prev_count=$(jq -r '.count // 0' "$state_file" 2>/dev/null || echo "0")
        if [[ "$penalty_count" -gt "$prev_count" ]]; then
            local new_penalties=$((penalty_count - prev_count))
            if command -v notify_alert &>/dev/null; then
                notify_alert "warning" "⚠️ New Penalty Issued" \
                    "$new_penalties new masternode penalty(s) detected" \
                    "penalty_issued"
            fi
        fi
    fi
    
    echo "{\"count\": $penalty_count, \"timestamp\": $(date +%s)}" > "$state_file"
    
    echo ""
}

#==============================================================================
# Watch Mode - Continuous Monitoring
#==============================================================================

watch_mode() {
    local interval="${1:-5}"
    
    echo -e "${BOLD}━━━ XDPoS Consensus Monitor - Watch Mode ━━━${NC}"
    echo ""
    info "Updating every $interval seconds. Press Ctrl+C to exit."
    echo ""
    
    while true; do
        clear
        echo -e "${BOLD}XDPoS Consensus Monitor - $(date '+%Y-%m-%d %H:%M:%S')${NC}"
        echo ""
        
        track_epoch
        check_finality
        check_rotation 2>/dev/null || true
        check_penalties 2>/dev/null || true
        
        echo ""
        echo -e "${DIM}Refreshing in ${interval}s... (Ctrl+C to exit)${NC}"
        sleep "$interval"
    done
}

#==============================================================================
# JSON Output Mode
#==============================================================================

output_json() {
    local response
    response=$(rpc_call "$XDC_RPC_URL" "eth_blockNumber")
    local block_number
    block_number=$(hex_to_dec "$(echo "$response" | jq -r '.result // "0x0"')")
    
    local epoch=$((block_number / EPOCH_LENGTH))
    local round=$((block_number % EPOCH_LENGTH))
    
    local masternodes
    masternodes=$(get_masternodes 2>/dev/null || echo "[]")
    local penalties
    penalties=$(get_penalties 2>/dev/null || echo "[]")
    
    jq -n \
        --argjson block "$block_number" \
        --argjson epoch "$epoch" \
        --argjson round "$round" \
        --argjson masternodes "$masternodes" \
        --argjson penalties "$penalties" \
        --arg timestamp "$(date -Iseconds)" \
        '{
            timestamp: $timestamp,
            consensus: {
                blockNumber: $block,
                epoch: $epoch,
                round: $round,
                epochProgress: (($round * 100 / 900) | floor),
                blocksToNextEpoch: (900 - $round)
            },
            masternodes: {
                count: ($masternodes | length),
                list: $masternodes
            },
            penalties: {
                count: ($penalties | length),
                list: $penalties
            }
        }'
}

#==============================================================================
# Help
#==============================================================================

show_help() {
    cat << EOF
XDPoS Consensus Monitor - Real-time XDPoS v2 Consensus Monitoring

Usage: $(basename "$0") [options]

Options:
    --epoch                 Show current epoch information
    --rounds                Show round tracking
    --votes                 Show vote monitoring
    --finality              Show block finality status
    --rotation              Show masternode rotation schedule
    --penalties             Show penalty tracking
    --all                   Run all checks
    --watch [interval]      Continuous monitoring mode (default: 5s)
    --json                  Output as JSON
    --help, -h              Show this help message

Examples:
    # Show current epoch
    $(basename "$0") --epoch

    # Watch mode with 10 second updates
    $(basename "$0") --watch 10

    # All checks as JSON
    $(basename "$0") --all --json

Description:
    Monitor XDPoS v2 consensus in real-time:
    - Track epochs and rounds
    - Monitor block finality
    - View masternode rotation
    - Track penalties and slashing events
    - Vote count analysis

EOF
}

#==============================================================================
# Main
#==============================================================================

main() {
    local command=""
    local watch_interval=5
    local json_output=false
    local run_all=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --epoch|--rounds|--votes|--finality|--rotation|--penalties)
                command="${1#--}"
                shift
                ;;
            --all)
                run_all=true
                shift
                ;;
            --watch)
                WATCH_MODE=true
                if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
                    watch_interval="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            --json)
                json_output=true
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
    
    # Run watch mode
    if [[ "$WATCH_MODE" == "true" ]]; then
        watch_mode "$watch_interval"
        exit 0
    fi
    
    # Run all checks
    if [[ "$run_all" == "true" ]]; then
        if [[ "$json_output" == "true" ]]; then
            output_json
        else
            track_epoch
            track_rounds
            track_votes
            check_finality
            check_rotation 2>/dev/null || true
            check_penalties 2>/dev/null || true
        fi
    elif [[ -n "$command" ]]; then
        case "$command" in
            epoch) track_epoch ;;
            rounds) track_rounds ;;
            votes) track_votes ;;
            finality) check_finality ;;
            rotation) check_rotation ;;
            penalties) check_penalties ;;
            *) warn "Unknown command: $command" ;;
        esac
    else
        # Default: show help
        show_help
    fi
}

main "$@"
