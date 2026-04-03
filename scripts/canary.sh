#!/usr/bin/env bash
#==============================================================================
# Canary Deployment Manager (Issue #104)
# deploy <client> <image>   — start canary container on port +1000
# check  <client>           — compare canary vs production block heights
# promote <client>          — swap canary to production
# rollback <client>         — kill and remove canary
#==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ── Client configuration ──────────────────────────────────────────────────────
declare -A CLIENT_PROD_PORTS=(
    [gp5]=8545
    [erigon]=8547
    [reth]=8548
    [nm]=8558
    [v268]=8550
)

declare -A CLIENT_PROD_CONTAINERS=(
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

# Canary ports = production port + 1000
CANARY_PORT_OFFSET="${CANARY_PORT_OFFSET:-1000}"
RPC_HOST="${XDC_RPC_HOST:-localhost}"
CANARY_STATE_DIR="${CANARY_STATE_DIR:-/var/lib/xdc/canary}"
LOG_FILE="${LOG_FILE:-/var/log/xdc/canary.log}"
BLOCK_LAG_TOLERANCE="${BLOCK_LAG_TOLERANCE:-10}"  # acceptable lag for promotion

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo -e "$msg"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

die() { echo -e "${RED}✗ Error: $*${RESET}" >&2; exit 1; }

validate_client() {
    local client="$1"
    [[ -z "${CLIENT_PROD_PORTS[$client]+x}" ]] && \
        die "Unknown client '${client}'. Available: ${!CLIENT_PROD_PORTS[*]}"
}

canary_name() {
    echo "${CLIENT_PROD_CONTAINERS[$1]}-canary"
}

canary_port() {
    echo $(( CLIENT_PROD_PORTS[$1] + CANARY_PORT_OFFSET ))
}

state_file() {
    echo "${CANARY_STATE_DIR}/${1}.json"
}

save_state() {
    local client="$1" image="$2" canary_c="$3" canary_p="$4"
    mkdir -p "$CANARY_STATE_DIR"
    cat > "$(state_file "$client")" <<EOF
{
  "client": "${client}",
  "image": "${image}",
  "canary_container": "${canary_c}",
  "canary_port": ${canary_p},
  "deployed_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "prod_container": "${CLIENT_PROD_CONTAINERS[$client]}",
  "prod_port": ${CLIENT_PROD_PORTS[$client]}
}
EOF
}

load_state() {
    local sf
    sf=$(state_file "$1")
    [[ -f "$sf" ]] && cat "$sf" || echo "{}"
}

rpc_block() {
    local port="$1"
    local resp
    resp=$(curl -sf --max-time 5 \
        -X POST "http://${RPC_HOST}:${port}" \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        2>/dev/null) || { echo ""; return; }
    local hex
    hex=$(echo "$resp" | grep -o '"result":"0x[^"]*"' | grep -o '0x[^"]*' 2>/dev/null || echo "")
    [[ -z "$hex" ]] && echo "" && return
    printf '%d\n' "$hex" 2>/dev/null || echo ""
}

container_running() {
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${1}$"
}

container_exists() {
    docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${1}$"
}

# ── DEPLOY ─────────────────────────────────────────────────────────────────────
cmd_deploy() {
    local client="${1:-}" image="${2:-}"
    [[ -z "$client" ]] && die "Usage: $0 deploy <client> <image>"
    [[ -z "$image"  ]] && die "Usage: $0 deploy <client> <image>"
    validate_client "$client"

    local c_name c_port prod_name prod_port
    c_name=$(canary_name "$client")
    c_port=$(canary_port "$client")
    prod_name="${CLIENT_PROD_CONTAINERS[$client]}"
    prod_port="${CLIENT_PROD_PORTS[$client]}"

    echo ""
    echo -e "${BOLD}${CYAN}🐦 Canary Deploy — ${CLIENT_LABELS[$client]}${RESET}"
    echo -e "  Image:          ${image}"
    echo -e "  Canary name:    ${c_name}"
    echo -e "  Canary port:    ${c_port} (prod: ${prod_port})"
    echo ""

    # Check if canary already running
    if container_running "$c_name"; then
        echo -e "${YELLOW}⚠  Canary container '${c_name}' already running.${RESET}"
        echo -e "  Run '${BOLD}$0 rollback ${client}${RESET}' first to replace it."
        exit 1
    fi
    if container_exists "$c_name"; then
        log "Removing stale canary container: ${c_name}"
        docker rm -f "$c_name" >/dev/null 2>&1 || true
    fi

    # Get production container config to mirror it for canary
    local prod_volumes="" prod_env_file="" prod_network=""
    if container_running "$prod_name"; then
        # Get network from prod
        prod_network=$(docker inspect "$prod_name" \
            --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' \
            2>/dev/null | head -1 || echo "")
    fi

    log "Starting canary: docker run -d --name ${c_name} -p ${c_port}:8545 ${image}"

    # Build docker run command
    local docker_args=(
        run -d
        --name "$c_name"
        --restart "no"
        -p "${c_port}:8545"
        -l "xdc.canary=true"
        -l "xdc.canary.client=${client}"
        -l "xdc.canary.prod_container=${prod_name}"
        -e "XDC_CANARY=true"
        -e "XDC_CLIENT=${client}"
    )

    # Copy volumes from prod container if available
    if container_exists "$prod_name"; then
        # Mount same volumes read-only for data (canary writes to temp volume)
        local vol_mounts
        mapfile -t vol_mounts < <(docker inspect "$prod_name" \
            --format '{{range .Mounts}}{{.Source}}:{{.Destination}}{{end}}' \
            2>/dev/null || true)
        for vm in "${vol_mounts[@]}"; do
            [[ -z "$vm" ]] && continue
            # Mount read-only for canary to avoid data corruption
            docker_args+=(-v "${vm}:ro")
        done
    fi

    # Attach to same network as production if available
    [[ -n "$prod_network" ]] && docker_args+=(--network "$prod_network")

    # Append remaining args for canary startup
    docker_args+=("$image")

    echo -e "  ${DIM}docker ${docker_args[*]}${RESET}"
    if docker "${docker_args[@]}" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Canary container started: ${c_name}${RESET}"
        log "Canary deployed: client=${client} image=${image} container=${c_name} port=${c_port}"
        save_state "$client" "$image" "$c_name" "$c_port"
        echo ""
        echo -e "  Test canary:    ${BOLD}curl http://${RPC_HOST}:${c_port} -X POST ...${RESET}"
        echo -e "  Check health:   ${BOLD}$0 check ${client}${RESET}"
        echo -e "  Promote:        ${BOLD}$0 promote ${client}${RESET}"
        echo -e "  Rollback:       ${BOLD}$0 rollback ${client}${RESET}"
    else
        echo -e "${RED}✗ Failed to start canary container${RESET}"
        log "ERROR: Failed to start canary for client=${client}"
        exit 1
    fi
    echo ""
}

# ── CHECK ──────────────────────────────────────────────────────────────────────
cmd_check() {
    local client="${1:-}"
    [[ -z "$client" ]] && die "Usage: $0 check <client>"
    validate_client "$client"

    local c_name c_port prod_name prod_port
    c_name=$(canary_name "$client")
    c_port=$(canary_port "$client")
    prod_name="${CLIENT_PROD_CONTAINERS[$client]}"
    prod_port="${CLIENT_PROD_PORTS[$client]}"

    echo ""
    echo -e "${BOLD}${CYAN}🔍 Canary Health Check — ${CLIENT_LABELS[$client]}${RESET}"
    echo ""

    # Check canary existence
    if ! container_running "$c_name"; then
        echo -e "${RED}✗ Canary container '${c_name}' is not running.${RESET}"
        echo -e "  Deploy first: ${BOLD}$0 deploy ${client} <image>${RESET}"
        exit 1
    fi

    # Container status
    local c_status
    c_status=$(docker ps --format '{{.Status}}' -f "name=^${c_name}$" 2>/dev/null | head -1)
    echo -e "  ${GREEN}●${RESET} Canary container: ${BOLD}${c_name}${RESET} — ${c_status}"

    # Block heights
    echo ""
    local prod_block canary_block
    prod_block=$(rpc_block "$prod_port")
    canary_block=$(rpc_block "$c_port")

    if [[ -z "$prod_block" ]]; then
        echo -e "  ${YELLOW}⚠ Production RPC (port ${prod_port}) not responding${RESET}"
    else
        echo -e "  Production block:  ${BOLD}${prod_block}${RESET} (port ${prod_port})"
    fi

    if [[ -z "$canary_block" ]]; then
        echo -e "  ${YELLOW}⚠ Canary RPC (port ${c_port}) not responding yet — may still be syncing${RESET}"
    else
        echo -e "  Canary block:      ${BOLD}${canary_block}${RESET} (port ${c_port})"
    fi

    if [[ -n "$prod_block" && -n "$canary_block" ]]; then
        local lag=$(( prod_block - canary_block ))
        echo ""
        if [[ "$lag" -le "$BLOCK_LAG_TOLERANCE" ]]; then
            echo -e "  ${GREEN}${BOLD}✓ Canary is in sync (lag: ${lag} blocks)${RESET}"
            echo -e "  Ready to promote: ${BOLD}$0 promote ${client}${RESET}"
        else
            echo -e "  ${YELLOW}⚠ Canary is ${lag} blocks behind production (tolerance: ${BLOCK_LAG_TOLERANCE})${RESET}"
            echo -e "  Wait for sync before promoting."
        fi
    fi

    # Show canary logs (last 10 lines)
    echo ""
    echo -e "${DIM}── Canary logs (last 10 lines) ──${RESET}"
    docker logs --tail 10 "$c_name" 2>&1 | sed 's/^/  /'
    echo ""
}

# ── PROMOTE ───────────────────────────────────────────────────────────────────
cmd_promote() {
    local client="${1:-}"
    [[ -z "$client" ]] && die "Usage: $0 promote <client>"
    validate_client "$client"

    local c_name c_port prod_name prod_port
    c_name=$(canary_name "$client")
    c_port=$(canary_port "$client")
    prod_name="${CLIENT_PROD_CONTAINERS[$client]}"
    prod_port="${CLIENT_PROD_PORTS[$client]}"

    echo ""
    echo -e "${BOLD}${CYAN}🚀 Promote Canary → Production — ${CLIENT_LABELS[$client]}${RESET}"
    echo ""

    if ! container_running "$c_name"; then
        die "Canary '${c_name}' is not running. Deploy first."
    fi

    # Final block comparison before promotion
    local prod_block canary_block
    prod_block=$(rpc_block "$prod_port" || echo "")
    canary_block=$(rpc_block "$c_port" || echo "")

    if [[ -n "$prod_block" && -n "$canary_block" ]]; then
        local lag=$(( prod_block - canary_block ))
        echo -e "  Production: block ${prod_block}"
        echo -e "  Canary:     block ${canary_block} (lag: ${lag})"
        if [[ "$lag" -gt "$BLOCK_LAG_TOLERANCE" ]]; then
            echo ""
            echo -e "${RED}✗ Cannot promote: canary is ${lag} blocks behind (threshold: ${BLOCK_LAG_TOLERANCE})${RESET}"
            echo -e "  Run '${BOLD}$0 check ${client}${RESET}' and wait for sync."
            exit 1
        fi
    fi

    echo ""
    echo -e "${YELLOW}⚠  This will stop production container '${prod_name}' and replace it with canary '${c_name}'.${RESET}"
    echo -n "  Proceed? [y/N] "
    read -r confirm < /dev/tty
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "Aborted." && exit 0

    log "Promoting canary ${c_name} → production ${prod_name}"

    # Get canary image
    local canary_image
    canary_image=$(docker inspect "$c_name" --format '{{.Config.Image}}' 2>/dev/null || echo "")
    local state_json
    state_json=$(load_state "$client")
    [[ -z "$canary_image" ]] && canary_image=$(echo "$state_json" | grep -o '"image":"[^"]*"' | cut -d'"' -f4 || echo "")

    # Step 1: Stop production
    echo -e "  Stopping production: ${prod_name}..."
    if container_running "$prod_name"; then
        docker stop "$prod_name" >/dev/null 2>&1 || true
        docker rename "$prod_name" "${prod_name}-old" >/dev/null 2>&1 || true
        echo -e "  ${GREEN}✓ Production stopped and renamed to ${prod_name}-old${RESET}"
    fi

    # Step 2: Stop canary and rename to production
    echo -e "  Stopping canary: ${c_name}..."
    docker stop "$c_name" >/dev/null 2>&1 || true

    echo -e "  Renaming canary → production..."
    docker rename "$c_name" "$prod_name" >/dev/null 2>&1 || true

    # Step 3: Update port binding — restart with prod port
    # (Docker doesn't support hot port remapping; need to commit + re-run)
    local new_image="${canary_image}"
    echo -e "  Recreating with production port ${prod_port}..."
    docker rm -f "$prod_name" >/dev/null 2>&1 || true

    # Get volumes from old prod container
    local vol_args=()
    if container_exists "${prod_name}-old"; then
        mapfile -t old_vols < <(docker inspect "${prod_name}-old" \
            --format '{{range .Mounts}}{{.Source}}:{{.Destination}}{{end}}' \
            2>/dev/null || true)
        for v in "${old_vols[@]}"; do
            [[ -n "$v" ]] && vol_args+=(-v "$v")
        done
    fi

    docker run -d --name "$prod_name" -p "${prod_port}:8545" \
        -l "xdc.promoted_from_canary=true" \
        "${vol_args[@]}" \
        "$new_image" >/dev/null 2>&1

    # Step 4: Cleanup
    docker rm -f "${prod_name}-old" >/dev/null 2>&1 || true
    rm -f "$(state_file "$client")" 2>/dev/null || true

    echo ""
    echo -e "${GREEN}${BOLD}✅ Promotion complete!${RESET}"
    echo -e "  Production '${prod_name}' now running image: ${new_image}"
    echo -e "  Port: ${prod_port}"
    log "Promoted: client=${client} image=${new_image} container=${prod_name} port=${prod_port}"
    echo ""
}

# ── ROLLBACK ──────────────────────────────────────────────────────────────────
cmd_rollback() {
    local client="${1:-}"
    [[ -z "$client" ]] && die "Usage: $0 rollback <client>"
    validate_client "$client"

    local c_name
    c_name=$(canary_name "$client")

    echo ""
    echo -e "${BOLD}${CYAN}⏪ Rollback — Kill Canary for ${CLIENT_LABELS[$client]}${RESET}"
    echo ""

    if ! container_exists "$c_name"; then
        echo -e "${YELLOW}No canary container '${c_name}' found — nothing to rollback.${RESET}"
        exit 0
    fi

    if container_running "$c_name"; then
        echo -e "  Stopping canary: ${c_name}..."
        docker stop "$c_name" >/dev/null 2>&1 || true
    fi

    echo -e "  Removing canary: ${c_name}..."
    docker rm -f "$c_name" >/dev/null 2>&1 || true

    # Clean state
    rm -f "$(state_file "$client")" 2>/dev/null || true

    echo -e "${GREEN}✓ Canary rolled back and removed.${RESET}"
    echo -e "  Production '${CLIENT_PROD_CONTAINERS[$client]}' is unaffected."
    log "Rollback: client=${client} canary=${c_name} removed"
    echo ""
}

# ── LIST ──────────────────────────────────────────────────────────────────────
cmd_list() {
    echo ""
    echo -e "${BOLD}${CYAN}🐦 Active Canary Deployments${RESET}"
    echo -e "${DIM}─────────────────────────────────────────────────────${RESET}"
    printf "${BOLD}%-12s %-22s %-8s %-30s${RESET}\n" "CLIENT" "CONTAINER" "PORT" "IMAGE"

    local found=0
    for client in "${!CLIENT_PROD_PORTS[@]}"; do
        local c_name c_port
        c_name=$(canary_name "$client")
        c_port=$(canary_port "$client")
        if container_exists "$c_name"; then
            local status="${RED}stopped${RESET}"
            container_running "$c_name" && status="${GREEN}running${RESET}"
            local img
            img=$(docker inspect "$c_name" --format '{{.Config.Image}}' 2>/dev/null | awk -F'/' '{print $NF}' | cut -c1-28 || echo "?")
            printf "%-12s %-22s %-8s " "${client}" "${c_name}" "${c_port}"
            echo -e "${img} [${status}]"
            found=1
        fi
    done
    [[ "$found" -eq 0 ]] && echo -e "  ${DIM}No canary deployments active.${RESET}"
    echo ""
}

# ── Entry point ───────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  deploy <client> <image>   Start canary container on port +${CANARY_PORT_OFFSET}"
    echo "  check  <client>           Compare canary vs production block heights"
    echo "  promote <client>          Swap canary to production (requires confirmation)"
    echo "  rollback <client>         Kill and remove canary container"
    echo "  list                      Show all active canary deployments"
    echo ""
    echo "Clients: ${!CLIENT_PROD_PORTS[*]}"
    echo ""
    echo "Ports:  production + ${CANARY_PORT_OFFSET} offset"
    printf "  %-10s prod:%-6s canary:%-6s\n" \
        "gp5"    "${CLIENT_PROD_PORTS[gp5]}"    "$(( CLIENT_PROD_PORTS[gp5]    + CANARY_PORT_OFFSET ))"
    printf "  %-10s prod:%-6s canary:%-6s\n" \
        "erigon" "${CLIENT_PROD_PORTS[erigon]}" "$(( CLIENT_PROD_PORTS[erigon] + CANARY_PORT_OFFSET ))"
    printf "  %-10s prod:%-6s canary:%-6s\n" \
        "reth"   "${CLIENT_PROD_PORTS[reth]}"   "$(( CLIENT_PROD_PORTS[reth]   + CANARY_PORT_OFFSET ))"
    printf "  %-10s prod:%-6s canary:%-6s\n" \
        "nm"     "${CLIENT_PROD_PORTS[nm]}"     "$(( CLIENT_PROD_PORTS[nm]     + CANARY_PORT_OFFSET ))"
    printf "  %-10s prod:%-6s canary:%-6s\n" \
        "v268"   "${CLIENT_PROD_PORTS[v268]}"   "$(( CLIENT_PROD_PORTS[v268]   + CANARY_PORT_OFFSET ))"
    echo ""
    echo "Environment:"
    echo "  XDC_RPC_HOST            RPC hostname (default: localhost)"
    echo "  CANARY_PORT_OFFSET      Port offset for canary (default: 1000)"
    echo "  BLOCK_LAG_TOLERANCE     Max lag blocks for promotion (default: 10)"
    echo "  CANARY_STATE_DIR        State directory (default: /var/lib/xdc/canary)"
}

case "${1:-list}" in
    deploy)   cmd_deploy   "${2:-}" "${3:-}" ;;
    check)    cmd_check    "${2:-}" ;;
    promote)  cmd_promote  "${2:-}" ;;
    rollback) cmd_rollback "${2:-}" ;;
    list)     cmd_list ;;
    --help|-h) usage ;;
    *) echo "Unknown command: $1"; usage; exit 1 ;;
esac
