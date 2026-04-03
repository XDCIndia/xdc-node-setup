#!/usr/bin/env bash
#==============================================================================
# Unified Observability Dashboard (Issue #97)
# status   — all clients block+peers+sync in one view
# logs     — tail docker logs for a client
# metrics  — disk usage, memory, CPU of container
# export   — dump JSON for external consumption
#==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Client configuration ──────────────────────────────────────────────────────
declare -A CLIENT_PORTS=(
    [gp5]=8545
    [erigon]=8547
    [reth]=8548
    [nm]=8558
    [v268]=8550
)

declare -A CLIENT_CONTAINERS=(
    [gp5]="${GP5_CONTAINER:-xdc-gp5}"
    [erigon]="${ERIGON_CONTAINER:-xdc-erigon}"
    [reth]="${RETH_CONTAINER:-xdc-reth}"
    [nm]="${NM_CONTAINER:-xdc-nethermind}"
    [v268]="${V268_CONTAINER:-xdc-v268}"
)

declare -A CLIENT_LABELS=(
    [gp5]="GP5 (go-xdc)"
    [erigon]="Erigon"
    [reth]="Reth"
    [nm]="Nethermind"
    [v268]="v2.6.8"
)

RPC_HOST="${XDC_RPC_HOST:-localhost}"
EXPORT_DIR="${EXPORT_DIR:-/var/log/xdc/observability}"
LOG_LINES="${LOG_LINES:-50}"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# ── RPC helper ────────────────────────────────────────────────────────────────
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

# ── Fetch client data ─────────────────────────────────────────────────────────
get_client_info() {
    local client="$1"
    local port="${CLIENT_PORTS[$client]}"

    local block_num="" block_hash="" peers="" syncing="" sync_block="" sync_highest=""

    # eth_blockNumber
    local resp
    resp=$(rpc_call "$port" "eth_blockNumber" "[]")
    if [[ -n "$resp" ]]; then
        local hex
        hex=$(echo "$resp" | grep -o '"result":"0x[^"]*"' | grep -o '0x[^"]*' 2>/dev/null || echo "")
        [[ -n "$hex" ]] && block_num=$(hex_to_dec "$hex")
    fi

    # eth_syncing
    resp=$(rpc_call "$port" "eth_syncing" "[]")
    if echo "$resp" | grep -q '"result":false'; then
        syncing="synced"
    elif [[ -n "$resp" ]]; then
        syncing="syncing"
        sync_block=$(echo "$resp" | grep -o '"currentBlock":"0x[^"]*"' | grep -o '0x[^"]*' 2>/dev/null || echo "")
        sync_highest=$(echo "$resp" | grep -o '"highestBlock":"0x[^"]*"' | grep -o '0x[^"]*' 2>/dev/null || echo "")
        [[ -n "$sync_block" ]]   && sync_block=$(hex_to_dec "$sync_block")
        [[ -n "$sync_highest" ]] && sync_highest=$(hex_to_dec "$sync_highest")
    fi

    # net_peerCount
    resp=$(rpc_call "$port" "net_peerCount" "[]")
    if [[ -n "$resp" ]]; then
        local hex
        hex=$(echo "$resp" | grep -o '"result":"0x[^"]*"' | grep -o '0x[^"]*' 2>/dev/null || echo "")
        [[ -n "$hex" ]] && peers=$(hex_to_dec "$hex")
    fi

    echo "${block_num:-N/A}|${peers:-N/A}|${syncing:-unknown}|${sync_block:-}|${sync_highest:-}"
}

# ── STATUS command ─────────────────────────────────────────────────────────────
cmd_status() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║       XDC Unified Observability — Node Status                ║${RESET}"
    echo -e "${BOLD}${CYAN}║       $(date '+%Y-%m-%d %H:%M:%S %Z')                              ║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    printf "${BOLD}%-14s %-12s %-8s %-12s %-22s${RESET}\n" "CLIENT" "BLOCK" "PEERS" "STATUS" "SYNC PROGRESS"
    echo -e "${DIM}──────────────────────────────────────────────────────────────${RESET}"

    local max_block=0
    declare -A info_cache

    # Collect all client info first
    for client in "${!CLIENT_PORTS[@]}"; do
        local info
        info=$(get_client_info "$client" 2>/dev/null || echo "N/A|N/A|offline||")
        info_cache[$client]="$info"
        local block
        block=$(echo "$info" | cut -d'|' -f1)
        if [[ "$block" =~ ^[0-9]+$ ]] && [[ "$block" -gt "$max_block" ]]; then
            max_block="$block"
        fi
    done

    # Display
    for client in gp5 erigon reth nm v268; do
        [[ -z "${CLIENT_PORTS[$client]+x}" ]] && continue
        local info="${info_cache[$client]}"
        local block peers syncing sync_cur sync_hi
        block=$(echo "$info"   | cut -d'|' -f1)
        peers=$(echo "$info"   | cut -d'|' -f2)
        syncing=$(echo "$info" | cut -d'|' -f3)
        sync_cur=$(echo "$info"| cut -d'|' -f4)
        sync_hi=$(echo "$info" | cut -d'|' -f5)

        local status_color="$RED"
        local sync_str=""

        if [[ "$block" == "N/A" || "$syncing" == "offline" ]]; then
            status_color="$RED"
            syncing="OFFLINE"
        elif [[ "$syncing" == "synced" ]]; then
            status_color="$GREEN"
            local lag=$(( max_block - ${block:-0} ))
            [[ "$lag" -gt 5 ]] && status_color="$YELLOW"
            sync_str="tip lag: ${lag}"
        elif [[ "$syncing" == "syncing" ]]; then
            status_color="$YELLOW"
            if [[ -n "$sync_cur" && -n "$sync_hi" && "$sync_hi" -gt 0 ]]; then
                local pct=$(( sync_cur * 100 / sync_hi ))
                sync_str="${sync_cur}/${sync_hi} (${pct}%)"
            fi
        fi

        printf "${status_color}%-14s${RESET} %-12s %-8s ${status_color}%-12s${RESET} %-22s\n" \
            "${CLIENT_LABELS[$client]}" \
            "${block}" \
            "${peers}" \
            "${syncing^^}" \
            "${sync_str}"
    done
    echo ""

    # Container status
    echo -e "${BOLD}🐳 Container Status:${RESET}"
    echo -e "${DIM}──────────────────────────────────────────────────────────────${RESET}"
    for client in gp5 erigon reth nm v268; do
        [[ -z "${CLIENT_CONTAINERS[$client]+x}" ]] && continue
        local cname="${CLIENT_CONTAINERS[$client]}"
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${cname}$"; then
            local uptime
            uptime=$(docker ps --format '{{.Names}}\t{{.Status}}' 2>/dev/null | grep "^${cname}" | awk '{$1=""; print $0}' | xargs)
            echo -e "  ${GREEN}●${RESET} ${CLIENT_LABELS[$client]} (${cname}): ${uptime}"
        elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${cname}$"; then
            echo -e "  ${RED}●${RESET} ${CLIENT_LABELS[$client]} (${cname}): stopped"
        else
            echo -e "  ${DIM}○${RESET} ${CLIENT_LABELS[$client]} (${cname}): not found"
        fi
    done
    echo ""
}

# ── LOGS command ──────────────────────────────────────────────────────────────
cmd_logs() {
    local client="${1:-}"
    if [[ -z "$client" ]]; then
        echo "Usage: $0 logs <client>"
        echo "Available clients: ${!CLIENT_CONTAINERS[*]}"
        exit 1
    fi

    if [[ -z "${CLIENT_CONTAINERS[$client]+x}" ]]; then
        echo "Unknown client: $client. Available: ${!CLIENT_CONTAINERS[*]}"
        exit 1
    fi

    local cname="${CLIENT_CONTAINERS[$client]}"
    echo -e "${BOLD}${CYAN}📋 Logs for ${CLIENT_LABELS[$client]} (${cname}) — last ${LOG_LINES} lines${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────────${RESET}"

    if ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${cname}$"; then
        echo -e "${RED}Container '${cname}' not found.${RESET}"
        echo "  Set ${client^^}_CONTAINER env var to override container name."
        exit 1
    fi

    docker logs --tail "$LOG_LINES" --timestamps "${cname}" 2>&1
}

# ── METRICS command ───────────────────────────────────────────────────────────
cmd_metrics() {
    local client="${1:-}"
    if [[ -z "$client" ]]; then
        # Show metrics for all clients
        echo -e "${BOLD}${CYAN}📊 Container Metrics — All Clients${RESET}"
        echo -e "${DIM}────────────────────────────────────────────────────────────────${RESET}"
        printf "${BOLD}%-14s %-12s %-12s %-10s %-20s${RESET}\n" "CLIENT" "CPU%" "MEM USAGE" "MEM%" "DISK (data volume)"
        echo -e "${DIM}────────────────────────────────────────────────────────────────${RESET}"
        for c in gp5 erigon reth nm v268; do
            [[ -z "${CLIENT_CONTAINERS[$c]+x}" ]] && continue
            _print_metrics_row "$c"
        done
        echo ""
        return
    fi

    if [[ -z "${CLIENT_CONTAINERS[$client]+x}" ]]; then
        echo "Unknown client: $client. Available: ${!CLIENT_CONTAINERS[*]}"
        exit 1
    fi

    local cname="${CLIENT_CONTAINERS[$client]}"
    echo -e "${BOLD}${CYAN}📊 Metrics — ${CLIENT_LABELS[$client]} (${cname})${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────────${RESET}"

    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${cname}$"; then
        echo -e "${YELLOW}Container '${cname}' is not running.${RESET}"
        return
    fi

    echo -e "${BOLD}CPU & Memory:${RESET}"
    docker stats --no-stream --format \
        "  CPU: {{.CPUPerc}}\n  Memory: {{.MemUsage}} ({{.MemPerc}})\n  Net I/O: {{.NetIO}}\n  Block I/O: {{.BlockIO}}" \
        "$cname" 2>/dev/null || echo "  (stats unavailable)"

    echo ""
    echo -e "${BOLD}Volume disk usage:${RESET}"
    docker inspect "$cname" --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' 2>/dev/null | \
    while read -r mount; do
        [[ -z "$mount" ]] && continue
        if [[ -d "$mount" ]]; then
            du -sh "$mount" 2>/dev/null | awk "{print \"  \$1  $mount\"}" || true
        fi
    done || echo "  (no volumes or unable to inspect)"
    echo ""
}

_print_metrics_row() {
    local c="$1"
    local cname="${CLIENT_CONTAINERS[$c]}"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${cname}$"; then
        local stats
        stats=$(docker stats --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}" "$cname" 2>/dev/null || echo "?|?|?")
        local cpu mem memp
        cpu=$(echo "$stats"  | cut -d'|' -f1)
        mem=$(echo "$stats"  | cut -d'|' -f2)
        memp=$(echo "$stats" | cut -d'|' -f3)

        # Disk: sum of volumes
        local disk="?"
        local vols
        vols=$(docker inspect "$cname" --format '{{range .Mounts}}{{.Source}} {{end}}' 2>/dev/null || echo "")
        for v in $vols; do
            [[ -d "$v" ]] && disk=$(du -sh "$v" 2>/dev/null | awk '{print $1}') && break
        done

        printf "${GREEN}%-14s${RESET} %-12s %-12s %-10s %-20s\n" \
            "${CLIENT_LABELS[$c]}" "$cpu" "${mem}" "$memp" "$disk"
    else
        printf "${RED}%-14s${RESET} %-12s %-12s %-10s %-20s\n" \
            "${CLIENT_LABELS[$c]}" "-" "-" "-" "-"
    fi
}

# ── EXPORT command ────────────────────────────────────────────────────────────
cmd_export() {
    mkdir -p "$EXPORT_DIR"
    local outfile="${EXPORT_DIR}/observability-$(date '+%Y%m%d-%H%M%S').json"
    local ts
    ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    echo -e "${BOLD}📤 Exporting observability data...${RESET}"

    local json='{'
    json+="\"timestamp\":\"${ts}\","
    json+="\"host\":\"${RPC_HOST}\","
    json+='"clients":{'

    local first=1
    for client in gp5 erigon reth nm v268; do
        [[ -z "${CLIENT_PORTS[$client]+x}" ]] && continue
        local port="${CLIENT_PORTS[$client]}"
        local info
        info=$(get_client_info "$client" 2>/dev/null || echo "N/A|N/A|offline||")

        local block peers syncing sync_cur sync_hi
        block=$(echo "$info"   | cut -d'|' -f1)
        peers=$(echo "$info"   | cut -d'|' -f2)
        syncing=$(echo "$info" | cut -d'|' -f3)
        sync_cur=$(echo "$info"| cut -d'|' -f4)
        sync_hi=$(echo "$info" | cut -d'|' -f5)

        local cname="${CLIENT_CONTAINERS[$client]}"
        local container_status="stopped"
        docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${cname}$" && container_status="running"

        [[ "$first" -eq 0 ]] && json+=','
        first=0
        json+="\"${client}\":{"
        json+="\"name\":\"${CLIENT_LABELS[$client]}\","
        json+="\"port\":${port},"
        json+="\"block\":\"${block}\","
        json+="\"peers\":\"${peers}\","
        json+="\"syncing\":\"${syncing}\","
        json+="\"sync_current\":\"${sync_cur}\","
        json+="\"sync_highest\":\"${sync_hi}\","
        json+="\"container\":\"${cname}\","
        json+="\"container_status\":\"${container_status}\""
        json+='}'
    done

    json+='}'  # end clients
    json+='}'  # end root

    echo "$json" | python3 -m json.tool > "$outfile" 2>/dev/null || echo "$json" > "$outfile"
    echo -e "${GREEN}✓ Exported to: ${outfile}${RESET}"
    cat "$outfile"
    echo ""

    # Also write a "latest" symlink
    ln -sf "$outfile" "${EXPORT_DIR}/observability-latest.json" 2>/dev/null || true
    echo -e "${DIM}Symlink: ${EXPORT_DIR}/observability-latest.json${RESET}"
}

# ── Entry point ───────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  status              Show all clients: block, peers, sync status"
    echo "  logs <client>       Tail docker logs for a specific client"
    echo "  metrics [client]    Show CPU, memory, disk for container(s)"
    echo "  export              Dump full observability JSON for external tools"
    echo ""
    echo "Clients: gp5, erigon, reth, nm, v268"
    echo ""
    echo "Environment:"
    echo "  XDC_RPC_HOST        RPC hostname (default: localhost)"
    echo "  EXPORT_DIR          JSON export directory (default: /var/log/xdc/observability)"
    echo "  LOG_LINES           Lines to tail in logs command (default: 50)"
    echo "  GP5_CONTAINER       Override GP5 container name (default: xdc-gp5)"
    echo "  ERIGON_CONTAINER    Override Erigon container name"
    echo "  RETH_CONTAINER      Override Reth container name"
    echo "  NM_CONTAINER        Override Nethermind container name"
    echo "  V268_CONTAINER      Override v268 container name"
}

case "${1:-status}" in
    status)          cmd_status ;;
    logs)            cmd_logs "${2:-}" ;;
    metrics)         cmd_metrics "${2:-}" ;;
    export)          cmd_export ;;
    --help|-h|help)  usage ;;
    *) echo "Unknown command: $1"; usage; exit 1 ;;
esac
