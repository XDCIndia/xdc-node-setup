#!/usr/bin/env bash
#==============================================================================
# Cross-Client Block Verification (Issue #94)
# Query all running XDC clients, compare block hash at same height.
# Alert if divergence detected.
#==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Client RPC endpoints ──────────────────────────────────────────────────────
declare -A CLIENT_PORTS=(
    [gp5]=8545
    [erigon]=8547
    [reth]=8548
    [nm]=8558
    [v268]=8550
)

declare -A CLIENT_NAMES=(
    [gp5]="XDC GP5 (go-xdc)"
    [erigon]="Erigon XDC"
    [reth]="Reth XDC"
    [nm]="Nethermind XDC"
    [v268]="XDC v2.6.8"
)

RPC_HOST="${XDC_RPC_HOST:-localhost}"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
LOG_FILE="${LOG_FILE:-/var/log/xdc/cross-verify.log}"
DIVERGENCE_THRESHOLD="${DIVERGENCE_THRESHOLD:-1}"   # blocks behind before alert

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE" 2>/dev/null || echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

rpc_call() {
    local port="$1" method="$2" params="${3:-[]}"
    curl -sf --max-time 5 \
        -X POST "http://${RPC_HOST}:${port}" \
        -H 'Content-Type: application/json' \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":${params},\"id\":1}" \
        2>/dev/null || echo ""
}

hex_to_dec() {
    local hex="${1#0x}"
    printf '%d\n' "0x${hex}" 2>/dev/null || echo "0"
}

alert() {
    local msg="$1"
    log "⚠️  ALERT: $msg"
    if [[ -n "$ALERT_WEBHOOK" ]]; then
        curl -sf -X POST "$ALERT_WEBHOOK" \
            -H 'Content-Type: application/json' \
            -d "{\"text\":\"🚨 XDC Cross-Verify Alert: ${msg}\"}" \
            >/dev/null 2>&1 || true
    fi
}

# ── Check if client is reachable ──────────────────────────────────────────────
client_alive() {
    local port="$1"
    curl -sf --max-time 3 -X POST "http://${RPC_HOST}:${port}" \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
        >/dev/null 2>&1
}

# ── Get latest block number for a client ─────────────────────────────────────
get_block_number() {
    local port="$1"
    local resp
    resp=$(rpc_call "$port" "eth_blockNumber" "[]")
    [[ -z "$resp" ]] && echo "" && return
    local hex
    hex=$(echo "$resp" | grep -o '"result":"0x[^"]*"' | grep -o '0x[^"]*' 2>/dev/null || echo "")
    [[ -z "$hex" ]] && echo "" && return
    hex_to_dec "$hex"
}

# ── Get block hash at a specific block number ─────────────────────────────────
get_block_hash() {
    local port="$1" block_num="$2"
    local block_hex
    block_hex=$(printf '0x%x' "$block_num")
    local resp
    resp=$(rpc_call "$port" "eth_getBlockByNumber" "[\"${block_hex}\",false]")
    [[ -z "$resp" ]] && echo "" && return
    echo "$resp" | grep -o '"hash":"0x[^"]*"' | head -1 | grep -o '0x[^"]*' 2>/dev/null || echo ""
}

# ── Get peer count ────────────────────────────────────────────────────────────
get_peer_count() {
    local port="$1"
    local resp
    resp=$(rpc_call "$port" "net_peerCount" "[]")
    [[ -z "$resp" ]] && echo "?" && return
    local hex
    hex=$(echo "$resp" | grep -o '"result":"0x[^"]*"' | grep -o '0x[^"]*' 2>/dev/null || echo "")
    [[ -z "$hex" ]] && echo "?" && return
    hex_to_dec "$hex"
}

# ── Main verification logic ───────────────────────────────────────────────────
main() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo ""
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${CYAN}   XDC Cross-Client Block Verification        ${RESET}"
    echo -e "${BOLD}${CYAN}   $(date '+%Y-%m-%d %H:%M:%S')               ${RESET}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════${RESET}"
    echo ""

    declare -A client_blocks
    declare -A client_hashes
    declare -A client_peers
    declare -a alive_clients=()

    # Step 1: Probe all clients
    echo -e "${BOLD}📡 Probing clients...${RESET}"
    for client in "${!CLIENT_PORTS[@]}"; do
        port="${CLIENT_PORTS[$client]}"
        name="${CLIENT_NAMES[$client]}"
        if client_alive "$port"; then
            block=$(get_block_number "$port")
            peers=$(get_peer_count "$port")
            if [[ -n "$block" && "$block" -gt 0 ]]; then
                client_blocks[$client]="$block"
                client_peers[$client]="$peers"
                alive_clients+=("$client")
                echo -e "  ${GREEN}✓${RESET} ${name} — block ${BOLD}${block}${RESET} | peers: ${peers}"
            else
                echo -e "  ${YELLOW}⚠${RESET} ${name} — reachable but no block data"
            fi
        else
            echo -e "  ${RED}✗${RESET} ${name} (port ${port}) — not responding"
        fi
    done

    if [[ ${#alive_clients[@]} -lt 2 ]]; then
        echo ""
        echo -e "${YELLOW}⚠  Need at least 2 clients online for cross-verification.${RESET}"
        echo ""
        exit 0
    fi

    # Step 2: Find the reference block (min of all alive clients, to ensure all have it)
    echo ""
    echo -e "${BOLD}🔍 Finding common reference block...${RESET}"
    local ref_block=999999999
    for client in "${alive_clients[@]}"; do
        b="${client_blocks[$client]}"
        if [[ "$b" -lt "$ref_block" ]]; then
            ref_block="$b"
        fi
    done
    # Go back a few blocks to be safe (avoid tip race)
    ref_block=$(( ref_block - 5 ))
    echo -e "  Reference block: ${BOLD}${ref_block}${RESET}"

    # Step 3: Fetch hashes at reference block from all clients
    echo ""
    echo -e "${BOLD}🔗 Fetching block hashes at #${ref_block}...${RESET}"
    for client in "${alive_clients[@]}"; do
        port="${CLIENT_PORTS[$client]}"
        hash=$(get_block_hash "$port" "$ref_block")
        client_hashes[$client]="${hash:-UNAVAILABLE}"
        echo -e "  ${CLIENT_NAMES[$client]}: ${client_hashes[$client]}"
    done

    # Step 4: Compare hashes — detect divergence
    echo ""
    echo -e "${BOLD}⚖️  Comparing hashes...${RESET}"
    local first_hash="" first_client="" diverged=0 diverge_list=""

    for client in "${alive_clients[@]}"; do
        h="${client_hashes[$client]}"
        [[ "$h" == "UNAVAILABLE" ]] && continue
        if [[ -z "$first_hash" ]]; then
            first_hash="$h"
            first_client="$client"
        elif [[ "$h" != "$first_hash" ]]; then
            diverged=1
            diverge_list+=" ${CLIENT_NAMES[$client]} (${h})"
        fi
    done

    # Step 5: Check block height divergence
    echo -e "${BOLD}📊 Block height comparison:${RESET}"
    local max_block=0
    for client in "${alive_clients[@]}"; do
        b="${client_blocks[$client]}"
        [[ "$b" -gt "$max_block" ]] && max_block="$b"
    done

    local height_issues=0
    for client in "${alive_clients[@]}"; do
        b="${client_blocks[$client]}"
        lag=$(( max_block - b ))
        if [[ "$lag" -gt "$DIVERGENCE_THRESHOLD" ]]; then
            echo -e "  ${RED}⚠${RESET} ${CLIENT_NAMES[$client]}: block ${b} (${lag} blocks behind)"
            alert "${CLIENT_NAMES[$client]} is ${lag} blocks behind the chain tip (${max_block})"
            height_issues=1
        else
            echo -e "  ${GREEN}✓${RESET} ${CLIENT_NAMES[$client]}: block ${b} (lag: ${lag})"
        fi
    done

    # Step 6: Report
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    if [[ "$diverged" -eq 0 && "$height_issues" -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}✅ ALL CLIENTS AGREE — No divergence detected${RESET}"
        log "OK: All clients agree at block ${ref_block} hash=${first_hash}"
    else
        if [[ "$diverged" -eq 1 ]]; then
            echo -e "${RED}${BOLD}🚨 HASH DIVERGENCE DETECTED at block #${ref_block}${RESET}"
            echo -e "  Reference (${CLIENT_NAMES[$first_client]}): ${first_hash}"
            echo -e "  Diverging: ${diverge_list}"
            alert "Hash divergence at block #${ref_block}! Reference=${first_hash}. Diverging:${diverge_list}"
            log "DIVERGENCE: block ${ref_block}, diverging:${diverge_list}"
        fi
        if [[ "$height_issues" -eq 1 ]]; then
            echo -e "${YELLOW}${BOLD}⚠️  Some clients are lagging behind the chain tip${RESET}"
        fi
        echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        exit 1
    fi
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

# ── Continuous watch mode ──────────────────────────────────────────────────────
watch_mode() {
    local interval="${1:-60}"
    echo "🔁 Watch mode — checking every ${interval}s (Ctrl+C to stop)"
    while true; do
        main || true
        sleep "$interval"
    done
}

# ── Entry point ───────────────────────────────────────────────────────────────
case "${1:-check}" in
    check)   main ;;
    watch)   watch_mode "${2:-60}" ;;
    --help|-h)
        echo "Usage: $0 [check|watch [interval_secs]]"
        echo ""
        echo "Commands:"
        echo "  check         One-shot cross-client block verification (default)"
        echo "  watch [N]     Continuous mode, check every N seconds (default 60)"
        echo ""
        echo "Environment:"
        echo "  XDC_RPC_HOST          RPC hostname (default: localhost)"
        echo "  ALERT_WEBHOOK         Webhook URL for divergence alerts"
        echo "  DIVERGENCE_THRESHOLD  Block lag before alerting (default: 1)"
        echo "  LOG_FILE              Log path (default: /var/log/xdc/cross-verify.log)"
        ;;
    *) echo "Unknown command: $1. Use --help for usage." && exit 1 ;;
esac
