#!/usr/bin/env bash
#==============================================================================
# XDPoS Consensus Monitor (Issue #99)
# Queries XDPoS_getMasternodesByNumber and XDPoS_getV2BlockByNumber
# Tracks vote participation, penalties, epoch boundaries, missed votes.
#==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Configuration ─────────────────────────────────────────────────────────────
XDC_RPC_URL="${XDC_RPC_URL:-http://localhost:8545}"
EPOCH_SIZE="${EPOCH_SIZE:-900}"            # XDPoS v2 epoch size in blocks
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
LOG_FILE="${LOG_FILE:-/var/log/xdc/consensus-monitor.log}"
STATE_FILE="${STATE_FILE:-/var/lib/xdc/consensus-state.json}"
MISSED_VOTE_THRESHOLD="${MISSED_VOTE_THRESHOLD:-3}"   # consecutive missed votes before alert
PENALTY_ALERT_BLOCKS="${PENALTY_ALERT_BLOCKS:-1800}"  # alert if penalty issued in last N blocks

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

alert() {
    local severity="$1" msg="$2"
    local icon="⚠️"
    [[ "$severity" == "critical" ]] && icon="🚨"
    [[ "$severity" == "info" ]]     && icon="ℹ️"
    log "${icon} ALERT [${severity^^}]: $msg"
    if [[ -n "$ALERT_WEBHOOK" ]]; then
        curl -sf -X POST "$ALERT_WEBHOOK" \
            -H 'Content-Type: application/json' \
            -d "{\"text\":\"${icon} XDPoS Monitor [${severity^^}]: ${msg}\"}" \
            >/dev/null 2>&1 || true
    fi
}

rpc_call() {
    local method="$1" params="${2:-[]}"
    curl -sf --max-time 10 \
        -X POST "$XDC_RPC_URL" \
        -H 'Content-Type: application/json' \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":${params},\"id\":1}" \
        2>/dev/null || echo ""
}

hex_to_dec() {
    local hex="${1#0x}"
    [[ -z "$hex" ]] && echo "0" && return
    printf '%d\n' "0x${hex}" 2>/dev/null || echo "0"
}

# ── Get current block ─────────────────────────────────────────────────────────
get_current_block() {
    local resp
    resp=$(rpc_call "eth_blockNumber" "[]")
    [[ -z "$resp" ]] && echo "" && return
    local hex
    hex=$(echo "$resp" | grep -o '"result":"0x[^"]*"' | grep -o '0x[^"]*' 2>/dev/null || echo "")
    [[ -z "$hex" ]] && echo "" && return
    hex_to_dec "$hex"
}

# ── Get masternodes at block ──────────────────────────────────────────────────
get_masternodes() {
    local block_num="$1"
    local block_hex
    block_hex=$(printf '0x%x' "$block_num")
    rpc_call "XDPoS_getMasternodesByNumber" "[\"${block_hex}\"]"
}

# ── Get XDPoS v2 block data ───────────────────────────────────────────────────
get_v2_block() {
    local block_num="$1"
    local block_hex
    block_hex=$(printf '0x%x' "$block_num")
    rpc_call "XDPoS_getV2BlockByNumber" "[\"${block_hex}\"]"
}

# ── Get block by number ───────────────────────────────────────────────────────
get_block() {
    local block_num="$1"
    local block_hex
    block_hex=$(printf '0x%x' "$block_num")
    rpc_call "eth_getBlockByNumber" "[\"${block_hex}\",false]"
}

# ── Parse masternodes list from JSON response ─────────────────────────────────
parse_masternodes() {
    local resp="$1"
    # Extract addresses from the result array
    echo "$resp" | grep -o '"0x[0-9a-fA-F]*"' | tr -d '"' 2>/dev/null || echo ""
}

# ── Check vote participation for a block ─────────────────────────────────────
check_vote_participation() {
    local block_num="$1" block_data="$2" masternodes_resp="$3"

    local masternodes
    mapfile -t masternodes < <(parse_masternodes "$masternodes_resp")
    local total_mn=${#masternodes[@]}

    if [[ "$total_mn" -eq 0 ]]; then
        echo "0/0|0"
        return
    fi

    # Extract QC signers (voters) from v2 block data
    local signers
    signers=$(echo "$block_data" | grep -o '"validatorSet":\[[^]]*\]' 2>/dev/null || echo "")
    if [[ -z "$signers" ]]; then
        # Try votes field
        signers=$(echo "$block_data" | grep -o '"votes":\[[^]]*\]' 2>/dev/null || echo "")
    fi

    local vote_count
    vote_count=$(echo "$signers" | grep -o '"0x[0-9a-fA-F]*"' | wc -l 2>/dev/null || echo "0")
    vote_count="${vote_count// /}"

    local pct=0
    [[ "$total_mn" -gt 0 ]] && pct=$(( vote_count * 100 / total_mn ))

    echo "${vote_count}/${total_mn}|${pct}"
}

# ── Calculate epoch info ──────────────────────────────────────────────────────
epoch_info() {
    local block_num="$1"
    local epoch=$(( block_num / EPOCH_SIZE ))
    local epoch_start=$(( epoch * EPOCH_SIZE ))
    local epoch_end=$(( epoch_start + EPOCH_SIZE - 1 ))
    local blocks_left=$(( epoch_end - block_num ))
    echo "${epoch}|${epoch_start}|${epoch_end}|${blocks_left}"
}

# ── Load/save state ───────────────────────────────────────────────────────────
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo "{}"
    fi
}

save_state() {
    local state="$1"
    mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
    echo "$state" > "$STATE_FILE" 2>/dev/null || true
}

# ── Main monitor command ──────────────────────────────────────────────────────
cmd_monitor() {
    local continuous="${1:-false}"
    local interval="${2:-30}"

    while true; do
        run_check
        [[ "$continuous" == "false" ]] && break
        sleep "$interval"
    done
}

run_check() {
    echo ""
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${CYAN}   XDPoS Consensus Monitor — $(date '+%Y-%m-%d %H:%M:%S')   ${RESET}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════${RESET}"
    echo ""

    # Get current block
    local current_block
    current_block=$(get_current_block)
    if [[ -z "$current_block" || "$current_block" == "0" ]]; then
        echo -e "${RED}✗ Cannot reach XDC RPC at ${XDC_RPC_URL}${RESET}"
        alert "critical" "Cannot reach XDC RPC at ${XDC_RPC_URL}"
        return 1
    fi

    echo -e "${BOLD}Current block:${RESET} #${current_block}"

    # Epoch info
    local einfo
    einfo=$(epoch_info "$current_block")
    local epoch epoch_start epoch_end blocks_left
    epoch=$(echo "$einfo"       | cut -d'|' -f1)
    epoch_start=$(echo "$einfo" | cut -d'|' -f2)
    epoch_end=$(echo "$einfo"   | cut -d'|' -f3)
    blocks_left=$(echo "$einfo" | cut -d'|' -f4)

    echo -e "${BOLD}Epoch:${RESET}         #${epoch} (blocks ${epoch_start}–${epoch_end})"
    echo -e "${BOLD}Blocks to end:${RESET} ${blocks_left}"

    if [[ "$blocks_left" -lt 10 ]]; then
        echo -e "${YELLOW}⚠  Epoch boundary approaching in ${blocks_left} blocks${RESET}"
        alert "warning" "Epoch #${epoch} ending in ${blocks_left} blocks"
    fi

    # ── Masternode set ──
    echo ""
    echo -e "${BOLD}📋 Masternode Set (epoch #${epoch}):${RESET}"
    local mn_resp
    mn_resp=$(get_masternodes "$epoch_start")

    if [[ -z "$mn_resp" ]] || echo "$mn_resp" | grep -q '"error"'; then
        echo -e "${YELLOW}  ⚠ XDPoS_getMasternodesByNumber returned no data (may not be XDPoS v2 enabled)${RESET}"
    else
        local mn_count
        mn_count=$(parse_masternodes "$mn_resp" | grep -c '0x' 2>/dev/null || echo "0")
        echo -e "  Masternode count: ${BOLD}${mn_count}${RESET}"
        if [[ "$mn_count" -lt 21 ]]; then
            echo -e "  ${YELLOW}⚠ Low masternode count: ${mn_count} (expected ≥ 21)${RESET}"
            alert "warning" "Low masternode count: ${mn_count} at epoch #${epoch}"
        fi
    fi

    # ── Recent block analysis ──
    echo ""
    echo -e "${BOLD}🔍 Recent Block Analysis (last 5 blocks):${RESET}"
    echo -e "${DIM}──────────────────────────────────────────────────────${RESET}"
    printf "  ${BOLD}%-10s %-8s %-20s %-15s${RESET}\n" "BLOCK" "VOTE%" "VOTES/VALIDATORS" "MINER"

    local missed_count=0
    for i in 5 4 3 2 1; do
        local bnum=$(( current_block - i ))
        local v2_data block_data
        v2_data=$(get_v2_block "$bnum")
        block_data=$(get_block "$bnum")

        local miner="?"
        miner=$(echo "$block_data" | grep -o '"miner":"0x[^"]*"' | grep -o '0x[^"]*' | head -1 2>/dev/null || echo "?")
        # Short address
        local miner_short="${miner:0:10}...${miner: -6}"

        if [[ -z "$v2_data" ]] || echo "$v2_data" | grep -q '"result":null'; then
            printf "  ${DIM}%-10s %-8s %-20s %-15s${RESET}\n" "#${bnum}" "N/A" "N/A" "${miner_short}"
            missed_count=$(( missed_count + 1 ))
        else
            local participation
            participation=$(check_vote_participation "$bnum" "$v2_data" "$mn_resp")
            local vote_str pct
            vote_str=$(echo "$participation" | cut -d'|' -f1)
            pct=$(echo "$participation"      | cut -d'|' -f2)

            local color="$GREEN"
            [[ "$pct" -lt 67 ]] && color="$RED" && missed_count=$(( missed_count + 1 ))
            [[ "$pct" -lt 80 && "$pct" -ge 67 ]] && color="$YELLOW"

            printf "  ${color}%-10s %-8s %-20s %-15s${RESET}\n" "#${bnum}" "${pct}%" "${vote_str}" "${miner_short}"
        fi
    done

    # ── Penalty detection ──
    echo ""
    echo -e "${BOLD}⚖️  Penalty Check (last ${PENALTY_ALERT_BLOCKS} blocks):${RESET}"
    # Query for penalty events — look for blocks that had penalties recorded
    local penalty_start=$(( current_block - PENALTY_ALERT_BLOCKS ))
    [[ "$penalty_start" -lt 0 ]] && penalty_start=0

    # Check epoch boundaries for penalties (XDPoS records penalties at epoch start)
    local checked_epochs=0
    local penalties_found=0
    for e_offset in 0 1 2; do
        local check_epoch=$(( epoch - e_offset ))
        [[ "$check_epoch" -lt 0 ]] && continue
        local check_start=$(( check_epoch * EPOCH_SIZE ))
        [[ "$check_start" -lt "$penalty_start" ]] && break

        local ep_resp
        ep_resp=$(get_v2_block "$check_start")
        if [[ -n "$ep_resp" ]] && ! echo "$ep_resp" | grep -q '"result":null'; then
            local penalty_list
            penalty_list=$(echo "$ep_resp" | grep -o '"penalties":\[[^]]*\]' 2>/dev/null || echo "")
            if [[ -n "$penalty_list" && "$penalty_list" != '"penalties":[]' ]]; then
                local pen_count
                pen_count=$(echo "$penalty_list" | grep -o '"0x[^"]*"' | wc -l 2>/dev/null || echo "0")
                pen_count="${pen_count// /}"
                if [[ "$pen_count" -gt 0 ]]; then
                    penalties_found=$(( penalties_found + pen_count ))
                    echo -e "  ${RED}⚠ Epoch #${check_epoch} (block ${check_start}): ${pen_count} penalties recorded${RESET}"
                    alert "warning" "Epoch #${check_epoch}: ${pen_count} masternodes penalized at block ${check_start}"
                fi
            fi
        fi
        checked_epochs=$(( checked_epochs + 1 ))
    done

    if [[ "$penalties_found" -eq 0 ]]; then
        echo -e "  ${GREEN}✓ No penalties found in last ${PENALTY_ALERT_BLOCKS} blocks${RESET}"
    fi

    # ── Missed votes alert ──
    if [[ "$missed_count" -ge "$MISSED_VOTE_THRESHOLD" ]]; then
        echo ""
        echo -e "${RED}${BOLD}🚨 HIGH MISSED VOTE RATE: ${missed_count}/5 recent blocks had low participation${RESET}"
        alert "critical" "High missed vote rate: ${missed_count}/5 recent blocks below threshold at block #${current_block}"
    fi

    # ── Summary ──
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    local health="${GREEN}${BOLD}✅ CONSENSUS HEALTHY${RESET}"
    [[ "$missed_count" -ge "$MISSED_VOTE_THRESHOLD" || "$penalties_found" -gt 0 ]] && \
        health="${RED}${BOLD}⚠️  CONSENSUS ISSUES DETECTED${RESET}"
    echo -e "  Status: ${health}"
    echo -e "  Block: #${current_block} | Epoch: #${epoch} | Epoch ends in: ${blocks_left} blocks"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""

    log "OK: block=${current_block} epoch=${epoch} missed=${missed_count} penalties=${penalties_found}"
}

# ── Epoch history command ─────────────────────────────────────────────────────
cmd_epochs() {
    local count="${1:-10}"
    local current_block
    current_block=$(get_current_block)
    [[ -z "$current_block" ]] && echo "Cannot connect to RPC" && exit 1

    local current_epoch=$(( current_block / EPOCH_SIZE ))
    echo -e "${BOLD}${CYAN}📅 Last ${count} Epoch Boundaries${RESET}"
    echo -e "${DIM}───────────────────────────────────────${RESET}"
    printf "${BOLD}%-8s %-12s %-12s${RESET}\n" "EPOCH" "START BLOCK" "STATUS"

    for i in $(seq 0 $(( count - 1 ))); do
        local e=$(( current_epoch - i ))
        [[ "$e" -lt 0 ]] && break
        local e_start=$(( e * EPOCH_SIZE ))
        local status="past"
        [[ "$e" -eq "$current_epoch" ]] && status="current"
        printf "%-8s %-12s %-12s\n" "#${e}" "${e_start}" "${status}"
    done
}

# ── Masternodes command ───────────────────────────────────────────────────────
cmd_masternodes() {
    local block="${1:-}"
    if [[ -z "$block" ]]; then
        local current_block
        current_block=$(get_current_block)
        local epoch=$(( current_block / EPOCH_SIZE ))
        block=$(( epoch * EPOCH_SIZE ))
    fi

    echo -e "${BOLD}${CYAN}📋 Masternodes at block #${block}${RESET}"
    local resp
    resp=$(get_masternodes "$block")
    if [[ -z "$resp" ]] || echo "$resp" | grep -q '"error"'; then
        echo "No data (RPC error or not XDPoS v2)"
        return
    fi
    parse_masternodes "$resp" | nl -ba | head -100
}

# ── Entry point ───────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  check                   One-shot consensus check (default)"
    echo "  watch [interval]        Continuous monitoring (default: 30s)"
    echo "  epochs [count]          Show recent epoch boundaries (default: 10)"
    echo "  masternodes [block]     List masternodes at block (default: current epoch start)"
    echo ""
    echo "Environment:"
    echo "  XDC_RPC_URL             RPC endpoint (default: http://localhost:8545)"
    echo "  EPOCH_SIZE              Blocks per epoch (default: 900)"
    echo "  MISSED_VOTE_THRESHOLD   Alert threshold (default: 3)"
    echo "  PENALTY_ALERT_BLOCKS    Lookback for penalties (default: 1800)"
    echo "  ALERT_WEBHOOK           Webhook URL for alerts"
    echo "  LOG_FILE                Log path (default: /var/log/xdc/consensus-monitor.log)"
}

case "${1:-check}" in
    check)        run_check ;;
    watch)        cmd_monitor "true" "${2:-30}" ;;
    epochs)       cmd_epochs "${2:-10}" ;;
    masternodes)  cmd_masternodes "${2:-}" ;;
    --help|-h)    usage ;;
    *) echo "Unknown command: $1"; usage; exit 1 ;;
esac
