#!/usr/bin/env bash
# ============================================================
# fix-sync.sh — Unified sync issue recovery for XDC nodes
# Addresses: #149 (pivot header not found), #146 (0 peers),
#            #148/#147 (bad block workarounds)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/chaindata.sh" 2>/dev/null || true

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
die()   { error "$*"; exit 1; }

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------
DEFAULT_RPC="http://localhost:8545"
RPC_URL="${XDC_RPC_URL:-$DEFAULT_RPC}"
LOG_LINES="${LOG_LINES:-200}"
CONTAINER="${CONTAINER:-}"
COMPOSE_FILE="${COMPOSE_FILE:-}"

# Auto-detect container if not set
find_container() {
    if [[ -n "$CONTAINER" ]]; then
        echo "$CONTAINER"
        return 0
    fi
    local candidates
    candidates=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E 'xdc-(node|gp5|geth|v268)' | head -1 || true)
    if [[ -n "$candidates" ]]; then
        echo "$candidates"
        return 0
    fi
    die "No running XDC container found. Set CONTAINER=... or COMPOSE_FILE=..."
}

# Auto-detect compose file if not set
find_compose_file() {
    if [[ -n "$COMPOSE_FILE" && -f "$COMPOSE_FILE" ]]; then
        echo "$COMPOSE_FILE"
        return 0
    fi
    local project_dir="$(dirname "$SCRIPT_DIR")"
    for f in \
        "$project_dir/docker/docker-compose.yml" \
        "$project_dir/docker/docker-compose.gp5-apothem.yml" \
        "$project_dir/docker/docker-compose.geth-pr5.yml" \
        "$project_dir/docker/docker-compose.skyone.v2.yml"; do
        [[ -f "$f" ]] && echo "$f" && return 0
    done
    echo ""
}

# ------------------------------------------------------------
# RPC helpers
# ------------------------------------------------------------
rpc_call() {
    local method="$1"
    local params="${2:-[]}"
    curl -sf -m 3 -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" 2>/dev/null || echo '{}'
}

get_peer_count() {
    local resp
    resp=$(rpc_call "net_peerCount")
    local hex
    hex=$(echo "$resp" | jq -r '.result // "0x0"')
    if [[ "$hex" == "0x0" || -z "$hex" || "$hex" == "null" ]]; then
        echo "0"
    else
        printf "%d\n" "$((16#${hex#0x}))" 2>/dev/null || echo "0"
    fi
}

get_syncing() {
    local resp
    resp=$(rpc_call "eth_syncing")
    echo "$resp" | jq -r '.result // false'
}

get_block_number() {
    local resp
    resp=$(rpc_call "eth_blockNumber")
    local hex
    hex=$(echo "$resp" | jq -r '.result // "0x0"')
    printf "%d\n" "$((16#${hex#0x}))" 2>/dev/null || echo "0"
}

# ------------------------------------------------------------
# Log analysis
# ------------------------------------------------------------
get_logs() {
    local container="$1"
    docker logs --tail "$LOG_LINES" "$container" 2>&1
}

has_log_pattern() {
    local container="$1"
    local pattern="$2"
    get_logs "$container" | grep -qiE "$pattern"
}

# ------------------------------------------------------------
# Issue #149: pivot header not found
# ------------------------------------------------------------
fix_pivot_header() {
    local container="$1"
    local compose="$2"

    echo ""
    echo -e "${BOLD}━━━━━ Fix: Pivot Header Not Found ━━━━━${NC}"
    echo ""

    warn "Detected 'pivot header is not found' errors."
    info "This usually means snap sync cannot anchor to a trusted header."
    info "Switching to full sync mode and restarting the node..."
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would stop container and set SYNC_MODE=full"
        return 0
    fi

    if [[ -n "$compose" && -f "$compose" ]]; then
        info "Stopping container via compose..."
        docker compose -f "$compose" stop 2>/dev/null || docker stop "$container" || true

        info "Updating SYNC_MODE to 'full' in compose environment..."
        local env_file
        env_file="$(dirname "$compose")/.env"
        if [[ -f "$env_file" ]]; then
            if grep -q "^SYNC_MODE=" "$env_file"; then
                sed -i.bak "s/^SYNC_MODE=.*/SYNC_MODE=full/" "$env_file" && rm -f "$env_file.bak"
            else
                echo "SYNC_MODE=full" >> "$env_file"
            fi
            ok "Updated $env_file: SYNC_MODE=full"
        fi

        export SYNC_MODE=full
        info "Restarting with SYNC_MODE=full ..."
        docker compose -f "$compose" up -d
    else
        info "Stopping container..."
        docker stop "$container" || true
        info "Please restart manually with SYNC_MODE=full"
    fi

    ok "Node restarted in full sync mode. Monitor with: docker logs -f $container"
    info "Expected: pivot header errors should stop within 5-10 minutes."
}

# ------------------------------------------------------------
# Issue #146: 0 peers
# ------------------------------------------------------------
fix_zero_peers() {
    local container="$1"
    local compose="$2"

    echo ""
    echo -e "${BOLD}━━━━━ Fix: Zero Peers ━━━━━${NC}"
    echo ""

    warn "Node has 0 peers."
    info "Attempting peer injection and container restart..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would inject bootnodes and restart container"
        return 0
    fi

    local bootnodes_file="${SCRIPT_DIR}/../docker/apothem/bootnodes.list"
    if [[ ! -f "$bootnodes_file" ]]; then
        bootnodes_file="${SCRIPT_DIR}/../docker/mainnet/bootnodes.list"
    fi
    if [[ ! -f "$bootnodes_file" ]]; then
        bootnodes_file="${SCRIPT_DIR}/../docker/geth-pr5/bootnodes.list"
    fi

    if [[ -f "$bootnodes_file" ]]; then
        info "Injecting peers from $bootnodes_file ..."
        local added=0
        while IFS= read -r enode || [[ -n "$enode" ]]; do
            [[ -z "$enode" || "$enode" == \#* ]] && continue
            if docker exec "$container" sh -c "XDC --exec \"admin.addPeer('$enode')\" attach /work/xdcchain/XDC/geth.ipc" >/dev/null 2>&1 || \
               docker exec "$container" sh -c "geth --exec \"admin.addPeer('$enode')\" attach /work/xdcchain/geth/geth.ipc" >/dev/null 2>&1; then
                added=$((added + 1))
            fi
        done < "$bootnodes_file"
        ok "Injected $added peers"
    fi

    info "Restarting container to refresh peer discovery..."
    if [[ -n "$compose" && -f "$compose" ]]; then
        docker compose -f "$compose" restart
    else
        docker restart "$container"
    fi

    ok "Container restarted. Wait 3-5 minutes for peer discovery."
}

# ------------------------------------------------------------
# Issue #148/#147: Bad block / invalid merkle root
# ------------------------------------------------------------
fix_bad_block() {
    local container="$1"
    local compose="$2"

    echo ""
    echo -e "${BOLD}━━━━━ Fix: Bad Block / Invalid Merkle Root ━━━━━${NC}"
    echo ""

    error "Detected BAD BLOCK or invalid merkle root errors."
    warn "This is often a v2.6.8 client bug at epoch boundaries (#148/#147)."
    echo ""
    info "Options:"
    echo "  1) Reset chaindata and resync from snapshot (fastest recovery)"
    echo "  2) Switch to a different client image (e.g., GP5 instead of v2.6.8)"
    echo "  3) Do nothing and attempt to wait for a patch (not recommended)"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would prompt for reset, image switch, or no action"
        return 0
    fi

    echo -n "Select option [1-3]: "
    read -r choice

    case "$choice" in
        1)
            info "Running xdc reset --confirm ..."
            if command -v xdc &>/dev/null; then
                xdc reset --confirm
            else
                warn "xdc CLI not found. Please reset manually:"
                warn "  ./scripts/fix-stuck-sync.sh"
            fi
            ;;
        2)
            info "To switch client image, update your docker-compose.yml:"
            info "  image: anilchinchawale/gp5-xdc:v34"
            info "Then run: docker compose up -d"
            ;;
        *)
            warn "No action taken. The node will likely remain stuck."
            ;;
    esac
}

# ------------------------------------------------------------
# Main diagnosis flow
# ------------------------------------------------------------
run_diagnosis() {
    local container
    container=$(find_container)
    local compose
    compose=$(find_compose_file)

    echo ""
    echo -e "${BOLD}━━━━━ XDC Sync Diagnostics ━━━━━${NC}"
    echo ""
    info "Container: $container"
    [[ -n "$compose" ]] && info "Compose file: $compose"
    info "RPC URL: $RPC_URL"
    echo ""

    local peers syncing block
    peers=$(get_peer_count)
    syncing=$(get_syncing)
    block=$(get_block_number)

    printf "  ${BOLD}%-20s${NC} %s\n" "Peers:" "$peers"
    printf "  ${BOLD}%-20s${NC} %s\n" "Syncing:" "$syncing"
    printf "  ${BOLD}%-20s${NC} %s\n" "Current Block:" "$block"
    echo ""

    local issues_found=0

    if [[ "$peers" -eq 0 ]]; then
        fix_zero_peers "$container" "$compose"
        issues_found=$((issues_found + 1))
    fi

    if has_log_pattern "$container" "pivot header is not found"; then
        fix_pivot_header "$container" "$compose"
        issues_found=$((issues_found + 1))
    fi

    if has_log_pattern "$container" "BAD BLOCK|invalid merkle root|retrieved hash chain is invalid"; then
        fix_bad_block "$container" "$compose"
        issues_found=$((issues_found + 1))
    fi

    if has_log_pattern "$container" "State indexer is in recovery"; then
        warn "State indexer is in recovery. This may resolve after sync stabilizes."
        info "If it persists for >30 minutes, consider a chaindata reset."
        issues_found=$((issues_found + 1))
    fi

    if [[ "$issues_found" -eq 0 ]]; then
        ok "No common sync issues detected in recent logs."
        info "If the node is still stuck, try:"
        info "  • Increasing LOG_LINES and re-running this script"
        info "  • Checking disk space: df -h"
        info "  • Checking container resources: docker stats $container"
        info "  • Manual reset: xdc reset --confirm"
    else
        echo ""
        ok "Diagnosis complete. $issues_found issue(s) addressed."
    fi
}

# ------------------------------------------------------------
# Entry point
# ------------------------------------------------------------
usage() {
    cat <<EOF
${BOLD}fix-sync.sh${NC} — Detect and fix common XDC sync issues

Usage:
  fix-sync.sh [options]

Options:
  --rpc URL        RPC endpoint (default: $DEFAULT_RPC)
  --container NAME Docker container name (auto-detected if omitted)
  --compose FILE   Docker compose file (auto-detected if omitted)
  --logs N         Number of log lines to analyze (default: $LOG_LINES)
  --dry-run        Only diagnose, do not apply fixes
  --help           Show this help

Fixes applied:
  • 0 peers (#146)       → Inject bootnodes and restart container
  • Pivot header (#149)  → Switch SYNC_MODE to full and restart
  • Bad block (#148/147) → Offer reset or client switch
EOF
}

DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rpc) RPC_URL="$2"; shift 2 ;;
        --container) CONTAINER="$2"; shift 2 ;;
        --compose) COMPOSE_FILE="$2"; shift 2 ;;
        --logs) LOG_LINES="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) warn "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if [[ "$DRY_RUN" == "true" ]]; then
    warn "DRY RUN mode — fixes will be suggested but not applied"
fi

run_diagnosis
