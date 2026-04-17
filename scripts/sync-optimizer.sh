#!/usr/bin/env bash
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || source "/opt/xdc-node/scripts/lib/common.sh" || true
source "${SCRIPT_DIR}/lib/chaindata.sh" 2>/dev/null || source "/opt/xdc-node/scripts/lib/chaindata.sh" || true


#==============================================================================
# XDC Sync Optimizer
# Smart sync management for XDC nodes
# Recommends sync modes, calculates ETAs, manages pruning
#==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
# Configuration
readonly XDC_RPC_URL="${XDC_RPC_URL:-http://localhost:8545}"
readonly XDC_DATADIR="${XDC_DATADIR:-/root/xdcchain}"
readonly XDC_STATE_DIR="${XDC_STATE_DIR:-${XDC_DATA:-/root/xdcchain}/.state}"
readonly HISTORY_FILE="${XDC_STATE_DIR}/sync-history.json"

#==============================================================================
# Utility Functions
#==============================================================================




format_duration() {
    local seconds="$1"
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local remaining=$((seconds % 60))
    
    if [[ $hours -gt 0 ]]; then
        echo "${hours}h ${minutes}m"
    elif [[ $minutes -gt 0 ]]; then
        echo "${minutes}m ${remaining}s"
    else
        echo "${seconds}s"
    fi
}

#==============================================================================
# Sync Mode Recommendation
#==============================================================================

recommend_sync_mode() {
    echo -e "${BOLD}━━━ Sync Mode Recommendation ━━━${NC}"
    echo ""
    
    # Check available disk space
    local available_gb
    available_gb=$(df -BG "$XDC_DATADIR" 2>/dev/null | awk 'NR==2 {gsub(/G/,"",$4); print $4}' || echo "0")
    
    # Check current chaindata size
    local chaindata_size=0
    local subdir
    subdir=$(find_chaindata_subdir_or_default "$XDC_DATADIR" 2>/dev/null || echo "")
    local chaindata_path="$XDC_DATADIR/${subdir:+$subdir/}chaindata"
    if [[ -d "$chaindata_path" ]]; then
        chaindata_size=$(du -sb "$chaindata_path" 2>/dev/null | awk '{print $1}' || echo "0")
    fi
    local chaindata_gb=$((chaindata_size / 1073741824))
    
    echo -e "${CYAN}System Analysis:${NC}"
    printf "  ${BOLD}%-30s${NC} %d GB\n" "Available Disk Space:" "$available_gb"
    printf "  ${BOLD}%-30s${NC} %d GB\n" "Current Chaindata Size:" "$chaindata_gb"
    echo ""
    
    # Determine recommended mode
    local recommended=""
    local reason=""
    
    if [[ $available_gb -lt 500 ]]; then
        recommended="snap"
        reason="Limited disk space (<500GB)"
    elif [[ $available_gb -lt 1000 ]]; then
        recommended="full"
        reason="Moderate disk space (500GB-1TB)"
    else
        recommended="archive"
        reason="Ample disk space (>1TB)"
    fi
    
    # Adjust based on use case
    echo -e "${CYAN}Use Case Considerations:${NC}"
    echo ""
    echo "What is the primary purpose of this node?"
    echo "  1) Validator / Masternode (minimal queries)"
    echo "  2) RPC endpoint (query-heavy)"
    echo "  3) Archive / Explorer (historical data)"
    echo "  4) Development (flexible)"
    echo ""
    echo -n "Selection [1-4] (press Enter for auto): "
    read -r use_case
    
    case "$use_case" in
        1)
            if [[ "$recommended" == "archive" ]]; then
                recommended="full"
                reason="Validators don't need archive mode"
            fi
            ;;
        2)
            if [[ "$recommended" == "snap" ]]; then
                recommended="full"
                reason="RPC nodes need full state for queries"
            fi
            ;;
        3)
            recommended="archive"
            reason="Archive/explorer requires full historical state"
            ;;
        *)
            # Keep auto recommendation
            ;;
    esac
    
    echo ""
    echo -e "${CYAN}Recommendation:${NC}"
    echo ""
    
    case "$recommended" in
        snap)
            echo -e "  ${BOLD}Recommended Mode:${NC} ${GREEN}Snap Sync${NC}"
            echo ""
            echo "  Pros:"
            echo "    • Fastest sync time (hours, not days)"
            echo "    • Minimal disk usage (~300GB)"
            echo "  Cons:"
            echo "    • Cannot serve historical state queries"
            echo "    • Not suitable for archive/explorer"
            echo ""
            echo "  Usage: XDC --syncmode snap"
            ;;
        full)
            echo -e "  ${BOLD}Recommended Mode:${NC} ${GREEN}Full Sync${NC}"
            echo ""
            echo "  Pros:"
            echo "    • Complete state verification"
            echo "    • Suitable for validators and RPC"
            echo "  Cons:"
            echo "    • Slower sync (days)"
            echo "    • Higher disk usage (~500GB)"
            echo ""
            echo "  Usage: XDC --syncmode full"
            ;;
        archive)
            echo -e "  ${BOLD}Recommended Mode:${NC} ${GREEN}Archive Sync${NC}"
            echo ""
            echo "  Pros:"
            echo "    • Full historical state available"
            echo "    • Required for explorers and indexers"
            echo "  Cons:"
            echo "    • Slowest sync (weeks)"
            echo "    • Highest disk usage (1-2TB+)"
            echo ""
            echo "  Usage: XDC --syncmode full --gcmode archive"
            ;;
    esac
    
    echo ""
    info "Reason: $reason"
    echo ""
}

#==============================================================================
# Sync ETA Calculator
#==============================================================================

calculate_sync_eta() {
    local watch_mode="${1:-false}"
    
    echo -e "${BOLD}━━━ Sync Progress & ETA ━━━${NC}"
    echo ""
    
    # Get current sync status
    local sync_response
    sync_response=$(rpc_call "$XDC_RPC_URL" "eth_syncing")
    local is_syncing
    is_syncing=$(echo "$sync_response" | jq -r '.result')
    
    if [[ "$is_syncing" == "false" ]]; then
        log "✓ Node is fully synced!"
        return 0
    fi
    
    if [[ "$is_syncing" == "null" || "$is_syncing" == "" ]]; then
        warn "Could not determine sync status. Is the node running?"
        return 1
    fi
    
    # Parse sync info
    local current_block
    current_block=$(echo "$sync_response" | jq -r '.result.currentBlock // "0x0"')
    local highest_block
    highest_block=$(echo "$sync_response" | jq -r '.result.highestBlock // "0x0"')
    local starting_block
    starting_block=$(echo "$sync_response" | jq -r '.result.startingBlock // "0x0"')
    
    current_block=$(hex_to_dec "$current_block")
    highest_block=$(hex_to_dec "$highest_block")
    starting_block=$(hex_to_dec "$starting_block")
    
    local remaining_blocks=$((highest_block - current_block))
    local total_sync_blocks=$((highest_block - starting_block))
    local progress_blocks=$((current_block - starting_block))
    local progress_pct=0
    
    if [[ $total_sync_blocks -gt 0 ]]; then
        progress_pct=$((progress_blocks * 100 / total_sync_blocks))
    fi
    
    echo -e "${CYAN}Sync Status:${NC}"
    printf "  ${BOLD}%-25s${NC} %'d\n" "Current Block:" "$current_block"
    printf "  ${BOLD}%-25s${NC} %'d\n" "Highest Block:" "$highest_block"
    printf "  ${BOLD}%-25s${NC} %'d\n" "Remaining Blocks:" "$remaining_blocks"
    printf "  ${BOLD}%-25s${NC} %d%%\n" "Progress:" "$progress_pct"
    echo ""
    
    # Progress bar
    local filled=$((progress_pct / 2))
    local empty=$((50 - filled))
    printf "  ["
    printf "%${filled}s" '' | tr ' ' '█'
    printf "%${empty}s" '' | tr ' ' '░'
    printf "] %d%%\n" "$progress_pct"
    echo ""
    
    # Calculate ETA based on historical speed
    local blocks_per_minute=0
    if [[ -f "$HISTORY_FILE" ]]; then
        # Read previous measurements
        local prev_block prev_time
        prev_block=$(jq -r '.last_block // 0' "$HISTORY_FILE")
        prev_time=$(jq -r '.last_time // 0' "$HISTORY_FILE")
        
        local current_time
        current_time=$(date +%s)
        
        if [[ $prev_block -gt 0 && $prev_time -gt 0 ]]; then
            local time_diff=$((current_time - prev_time))
            local block_diff=$((current_block - prev_block))
            
            if [[ $time_diff -gt 0 && $block_diff -gt 0 ]]; then
                blocks_per_minute=$((block_diff * 60 / time_diff))
            fi
        fi
        
        # Save current state
        jq -n --argjson block "$current_block" --argjson time "$current_time" \
            '{last_block: $block, last_time: $time}' > "$HISTORY_FILE"
    else
        # First run - use default estimate
        blocks_per_minute=100
        mkdir -p "$(dirname "$HISTORY_FILE")"
        jq -n --argjson block "$current_block" --argjson time "$(date +%s)" \
            '{last_block: $block, last_time: $time}' > "$HISTORY_FILE"
    fi
    
    if [[ $blocks_per_minute -gt 0 ]]; then
        local minutes_remaining=$((remaining_blocks / blocks_per_minute))
        local eta
        eta=$(format_duration $((minutes_remaining * 60)))
        
        printf "  ${BOLD}%-25s${NC} %d blocks/min\n" "Sync Speed:" "$blocks_per_minute"
        printf "  ${BOLD}%-25s${NC} %s\n" "Estimated Time Remaining:" "$eta"
        printf "  ${BOLD}%-25s${NC} %s\n" "ETA:" "$(date -d "+${minutes_remaining} minutes" '+%Y-%m-%d %H:%M')"
    else
        info "Calculating sync speed... (check again in a few minutes)"
    fi
    
    echo ""
    
    # Watch mode
    if [[ "$watch_mode" == "true" ]]; then
        return 0
    fi
}

watch_sync() {
    local interval="${1:-30}"
    
    info "Watching sync progress (updates every ${interval}s)..."
    info "Press Ctrl+C to stop"
    echo ""
    
    while true; do
        clear
        echo -e "${BOLD}XDC Sync Progress - $(date '+%H:%M:%S')${NC}"
        echo ""
        
        calculate_sync_eta "true"
        
        echo ""
        diagnose_sync_issues "true"
        
        echo ""
        echo -e "${DIM}Refreshing in ${interval}s...${NC}"
        sleep "$interval"
    done
}

#==============================================================================
# Sync Issue Diagnosis
#==============================================================================

diagnose_sync_issues() {
    local quiet="${1:-false}"
    local container=""
    container=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'xdc-(node|gp5|geth|v268)' | head -1 || true)
    
    if [[ -z "$container" ]]; then
        return 0
    fi
    
    local issues_found=0
    local log_lines=200
    
    if [[ "$quiet" != "true" ]]; then
        echo -e "${BOLD}━━━━━ Sync Health Diagnostics ━━━━━${NC}"
        echo ""
    fi
    
    # Check peer count
    local peers_hex
    peers_hex=$(rpc_call "$XDC_RPC_URL" "net_peerCount" | jq -r '.result // "0x0"')
    local peers=0
    peers=$(hex_to_dec "$peers_hex")
    
    if [[ "$peers" -eq 0 ]]; then
        warn "0 peers detected (#146)"
        info "  Run: xdc-node fix-sync"
        issues_found=$((issues_found + 1))
    fi
    
    # Check logs for pivot header
    if docker logs --tail "$log_lines" "$container" 2>&1 | grep -qiE "pivot header is not found"; then
        warn "'pivot header not found' detected in logs (#149)"
        info "  Run: xdc-node fix-sync"
        info "  Or manually: export SYNC_MODE=full; docker compose restart"
        issues_found=$((issues_found + 1))
    fi
    
    # Check logs for bad block
    if docker logs --tail "$log_lines" "$container" 2>&1 | grep -qiE "BAD BLOCK|invalid merkle root|retrieved hash chain is invalid"; then
        warn "Bad block / merkle root error detected (#148/#147)"
        info "  Run: xdc-node fix-sync"
        info "  Or consider switching client image or resetting chaindata"
        issues_found=$((issues_found + 1))
    fi
    
    # Check logs for state indexer recovery stuck
    if docker logs --tail "$log_lines" "$container" 2>&1 | grep -qiE "State indexer is in recovery"; then
        warn "State indexer in recovery detected"
        info "  Monitor for 30 minutes. If stuck, consider chaindata reset"
        issues_found=$((issues_found + 1))
    fi
    
    # Stalled sync detection: if syncing but block hasn't changed in a while
    local syncing
    syncing=$(rpc_call "$XDC_RPC_URL" "eth_syncing" | jq -r '.result // false')
    if [[ "$syncing" != "false" && "$peers" -gt 0 ]]; then
        local current_block
        current_block=$(rpc_call "$XDC_RPC_URL" "eth_blockNumber" | jq -r '.result // "0x0"')
        current_block=$(hex_to_dec "$current_block")
        
        if [[ -f "$HISTORY_FILE" ]]; then
            local prev_block
            prev_block=$(jq -r '.last_block // 0' "$HISTORY_FILE")
            if [[ "$prev_block" -gt 0 && "$current_block" -eq "$prev_block" ]]; then
                local prev_time
                prev_time=$(jq -r '.last_time // 0' "$HISTORY_FILE")
                local current_time
                current_time=$(date +%s)
                local stalled_seconds=$((current_time - prev_time))
                
                if [[ "$stalled_seconds" -gt 300 ]]; then
                    warn "Sync appears stalled (no block progress for ${stalled_seconds}s)"
                    info "  Run: xdc-node fix-sync"
                    issues_found=$((issues_found + 1))
                fi
            fi
        fi
    fi
    
    if [[ "$issues_found" -eq 0 && "$quiet" != "true" ]]; then
        ok "No common sync issues detected"
    fi
    
    if [[ "$quiet" != "true" ]]; then
        echo ""
    fi
}

#==============================================================================
# Chaindata Pruning
#==============================================================================

analyze_pruning() {
    echo -e "${BOLD}━━━ Chaindata Pruning Analysis ━━━${NC}"
    echo ""
    
    local subdir
    subdir=$(find_chaindata_subdir_or_default "$XDC_DATADIR" 2>/dev/null || echo "")
    local chaindata_path="$XDC_DATADIR/${subdir:+$subdir/}chaindata"
    if [[ ! -d "$chaindata_path" ]]; then
        warn "Chaindata directory not found"
        return 1
    fi
    
    # Get sizes
    local current_size
    current_size=$(du -sb "$chaindata_path" 2>/dev/null | awk '{print $1}' || echo "0")
    
    # Estimate ancient data size (roughly 70% for full nodes)
    local ancient_size=$((current_size * 70 / 100))
    local expected_after=$((current_size - ancient_size))
    
    echo -e "${CYAN}Current Chaindata:${NC}"
    printf "  ${BOLD}%-25s${NC} %s\n" "Location:" "$chaindata_path"
    printf "  ${BOLD}%-25s${NC} %s\n" "Current Size:" "$(format_bytes $current_size)"
    echo ""
    
    echo -e "${CYAN}Pruning Estimates:${NC}"
    printf "  ${BOLD}%-25s${NC} %s\n" "Ancient Data:" "~$(format_bytes $ancient_size)"
    printf "  ${BOLD}%-25s${NC} %s\n" "Expected After Pruning:" "~$(format_bytes $expected_after)"
    printf "  ${BOLD}%-25s${NC} ~%s\n" "Space Savings:" "$(format_bytes $ancient_size)"
    echo ""
    
    warn "Pruning requires stopping the node and may take several hours"
    echo ""
    echo -n "Proceed with pruning? [y/N]: "
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        perform_pruning
    else
        info "Pruning cancelled"
    fi
}

perform_pruning() {
    echo ""
    echo -e "${BOLD}━━━ Performing Chaindata Pruning ━━━${NC}"
    echo ""
    
    # Step 1: Stop node
    info "Step 1: Stopping XDC node..."
    systemctl stop xdc-node 2>/dev/null || \
    systemctl stop xdc-validator 2>/dev/null || \
    pkill -f "XDC" || true
    sleep 5
    log "Node stopped"
    
    # Step 2: Backup (optional)
    echo ""
    echo -n "Create backup before pruning? [y/N]: "
    read -r backup_response
    
    if [[ "$backup_response" =~ ^[Yy]$ ]]; then
        info "Creating backup..."
        local backup_dir="/backup/xdc-node/pre-prune-$(date +%Y%m%d)"
        mkdir -p "$backup_dir"
        tar -czf "${backup_dir}/keystore.tar.gz" -C "$XDC_DATADIR" keystore/ 2>/dev/null || true
        log "Keystore backed up to $backup_dir"
    fi
    
    # Step 3: Prune (XDC doesn't have built-in prune, so we guide user)
    echo ""
    info "Step 3: Pruning instructions"
    echo ""
    echo "XDC uses geth-style chaindata. To prune:"
    echo ""
    local subdir
    subdir=$(find_chaindata_subdir_or_default "$XDC_DATADIR" 2>/dev/null || echo "")
    local chaindata_path="$XDC_DATADIR/${subdir:+$subdir/}chaindata"
    echo "  Option 1: Offline prune (requires resync from snapshot)"
    echo "    - Delete chaindata directory: rm -rf $chaindata_path"
    echo "    - Download fresh snapshot: ./scripts/snapshot-manager.sh download mainnet-full"
    echo ""
    echo "  Option 2: Ancient data prune (if using XDC v2.5+)"
    echo "    - XDC supports --datadir.ancient flag for ancient storage"
    echo "    - See: https://docs.xdc.community"
    echo ""
    
    # Step 4: Restart
    echo ""
    echo -n "Restart node now? [Y/n]: "
    read -r restart_response
    
    if [[ ! "$restart_response" =~ ^[Nn]$ ]]; then
        info "Starting XDC node..."
        systemctl start xdc-node 2>/dev/null || \
        systemctl start xdc-validator 2>/dev/null || \
        warn "Could not start node automatically"
    fi
    
    echo ""
    log "Pruning process complete"
}

#==============================================================================
# Multi-Client Comparison
#==============================================================================

compare_clients() {
    echo -e "${BOLD}━━━ Multi-Client Comparison ━━━${NC}"
    echo ""
    
    # Check for running clients
    local has_geth=false
    local has_erigon=false
    local has_nethermind=false
    
    if pgrep -x "XDC" >/dev/null || pgrep -f "geth.*xdc" >/dev/null; then
        has_geth=true
    fi
    
    if pgrep -x "erigon" >/dev/null; then
        has_erigon=true
    fi
    
    if pgrep -f "Nethermind.Runner" >/dev/null || pgrep -f "nethermind" >/dev/null; then
        has_nethermind=true
    fi
    
    if [[ "$has_geth" == "false" && "$has_erigon" == "false" && "$has_nethermind" == "false" ]]; then
        warn "No XDC clients detected as running"
        return 1
    fi
    
    echo -e "${CYAN}Detected Clients:${NC}"
    [[ "$has_geth" == "true" ]] && echo "  ✓ XDPoSChain (geth-xdc)"
    [[ "$has_erigon" == "true" ]] && echo "  ✓ Erigon-XDC"
    [[ "$has_nethermind" == "true" ]] && echo "  ✓ Nethermind-XDC"
    echo ""
    
    # Get metrics for each client
    printf "${BOLD}%-20s${NC}" "Metric"
    [[ "$has_geth" == "true" ]] && printf "${BOLD}%-20s${NC}" "XDPoSChain"
    [[ "$has_erigon" == "true" ]] && printf "${BOLD}%-20s${NC}" "Erigon-XDC"
    [[ "$has_nethermind" == "true" ]] && printf "${BOLD}%-20s${NC}" "Nethermind-XDC"
    echo ""
    printf "%-20s" "--------------------"
    [[ "$has_geth" == "true" ]] && printf "%-20s" "--------------------"
    [[ "$has_erigon" == "true" ]] && printf "%-20s" "--------------------"
    [[ "$has_nethermind" == "true" ]] && printf "%-20s" "--------------------"
    echo ""
    
    # Block Height
    printf "%-20s" "Block Height"
    if [[ "$has_geth" == "true" ]]; then
        local geth_height
        geth_height=$(rpc_call "http://localhost:8545" "eth_blockNumber" | jq -r '.result // "0x0"')
        geth_height=$(hex_to_dec "$geth_height")
        printf "%-20s" "$geth_height"
    fi
    if [[ "$has_erigon" == "true" ]]; then
        local erigon_height
        erigon_height=$(rpc_call "http://localhost:8546" "eth_blockNumber" | jq -r '.result // "0x0"')
        erigon_height=$(hex_to_dec "$erigon_height")
        printf "%-20s" "$erigon_height"
    fi
    if [[ "$has_nethermind" == "true" ]]; then
        local nethermind_height
        nethermind_height=$(rpc_call "http://localhost:8556" "eth_blockNumber" | jq -r '.result // "0x0"')
        nethermind_height=$(hex_to_dec "$nethermind_height")
        printf "%-20s" "$nethermind_height"
    fi
    echo ""
    
    # Peer Count
    printf "%-20s" "Peers"
    if [[ "$has_geth" == "true" ]]; then
        local geth_peers
        geth_peers=$(rpc_call "http://localhost:8545" "net_peerCount" | jq -r '.result // "0x0"')
        geth_peers=$(hex_to_dec "$geth_peers")
        printf "%-20s" "$geth_peers"
    fi
    if [[ "$has_erigon" == "true" ]]; then
        local erigon_peers
        erigon_peers=$(rpc_call "http://localhost:8546" "net_peerCount" | jq -r '.result // "0x0"')
        erigon_peers=$(hex_to_dec "$erigon_peers")
        printf "%-20s" "$erigon_peers"
    fi
    if [[ "$has_nethermind" == "true" ]]; then
        local nethermind_peers
        nethermind_peers=$(rpc_call "http://localhost:8556" "net_peerCount" | jq -r '.result // "0x0"')
        nethermind_peers=$(hex_to_dec "$nethermind_peers")
        printf "%-20s" "$nethermind_peers"
    fi
    echo ""
    
    # Disk Usage
    printf "%-20s" "Disk Usage"
    if [[ "$has_geth" == "true" ]]; then
        local geth_size
        geth_size=$(du -sb "${XDC_DATADIR}" 2>/dev/null | awk '{print $1}' || echo "0")
        printf "%-20s" "$(format_bytes $geth_size)"
    fi
    if [[ "$has_erigon" == "true" ]]; then
        local erigon_size
        erigon_size=$(du -sb "${XDC_DATADIR}-erigon" 2>/dev/null | awk '{print $1}' || echo "0")
        printf "%-20s" "$(format_bytes $erigon_size)"
    fi
    if [[ "$has_nethermind" == "true" ]]; then
        local nethermind_size
        nethermind_size=$(du -sb "${XDC_DATADIR}-nethermind" 2>/dev/null | awk '{print $1}' || echo "0")
        printf "%-20s" "$(format_bytes $nethermind_size)"
    fi
    echo ""
    
    # Memory Usage (if available)
    printf "%-20s" "Memory (RSS)"
    if [[ "$has_geth" == "true" ]]; then
        local geth_mem
        geth_mem=$(ps -o rss= -p "$(pgrep -x XDC)" 2>/dev/null || echo "0")
        geth_mem=$((geth_mem * 1024))
        printf "%-20s" "$(format_bytes $geth_mem)"
    fi
    if [[ "$has_erigon" == "true" ]]; then
        local erigon_mem
        erigon_mem=$(ps -o rss= -p "$(pgrep -x erigon)" 2>/dev/null || echo "0")
        erigon_mem=$((erigon_mem * 1024))
        printf "%-20s" "$(format_bytes $erigon_mem)"
    fi
    if [[ "$has_nethermind" == "true" ]]; then
        local nethermind_mem
        nethermind_mem=$(ps -o rss= -p "$(pgrep -f Nethermind.Runner | head -1)" 2>/dev/null || echo "0")
        nethermind_mem=$((nethermind_mem * 1024))
        printf "%-20s" "$(format_bytes $nethermind_mem)"
    fi
    echo ""
    
    echo ""
}

#==============================================================================
# Help
#==============================================================================

show_help() {
    cat << EOF
XDC Sync Optimizer

Usage: $(basename "$0") <command> [options]

Commands:
    recommend               Recommend optimal sync mode based on hardware
    status                  Show current sync status, ETA, and health check
    diagnose                Check for common sync issues and recommend fixes
    watch                   Auto-refresh sync status every 30 seconds
    prune                   Analyze and perform chaindata pruning
    compare                 Compare multiple XDC clients (if running)

Options:
    --interval N            Refresh interval for watch mode (default: 30)
    --datadir PATH          XDC data directory (default: $XDC_DATADIR)
    --help, -h              Show this help message

Examples:
    # Get sync mode recommendation
    $(basename "$0") recommend

    # Check sync status with ETA
    $(basename "$0") status

    # Watch sync progress (auto-refresh)
    $(basename "$0") watch

    # Watch with custom interval
    $(basename "$0") watch --interval 60

    # Analyze pruning potential
    $(basename "$0") prune

    # Compare running clients
    $(basename "$0") compare

Sync Modes:
    Snap Sync    - Fastest, minimal disk, no historical state
    Full Sync    - Balanced, complete verification, ~500GB
    Archive Sync - Slowest, full history, ~1-2TB

Description:
    This script helps optimize XDC node synchronization by:
    - Recommending appropriate sync modes based on available resources
    - Calculating accurate sync ETAs based on historical performance
    - Managing chaindata pruning to reclaim disk space
    - Comparing performance across multiple client implementations

EOF
}

#==============================================================================
# Main
#==============================================================================

main() {
    local command=""
    local interval=30
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            recommend|status|watch|prune|compare|diagnose)
                command="$1"
                shift
                ;;
            --interval)
                interval="${2:-30}"
                shift 2
                ;;
            --datadir)
                XDC_DATADIR="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                if [[ -z "$command" ]]; then
                    command="$1"
                fi
                shift
                ;;
        esac
    done
    
    # Ensure history directory exists (best effort)
    mkdir -p "$(dirname "$HISTORY_FILE")" 2>/dev/null || true
    
    case "$command" in
        recommend)
            recommend_sync_mode
            ;;
        diagnose)
            diagnose_sync_issues
            ;;
        status)
            calculate_sync_eta
            diagnose_sync_issues
            ;;
        watch)
            watch_sync "$interval"
            ;;
        prune)
            analyze_pruning
            ;;
        compare)
            compare_clients
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

main "$@"
