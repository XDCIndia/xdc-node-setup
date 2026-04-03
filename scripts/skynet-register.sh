#!/usr/bin/env bash
# ============================================================
# skynet-register.sh — Bidirectional SkyNet Integration
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/128
# ============================================================
# Auto-registers/deregisters XDC client nodes with SkyNet API.
#
# Usage:
#   skynet-register.sh register <client> [--network mainnet]
#   skynet-register.sh deregister <client> [--network mainnet]
#   skynet-register.sh heartbeat <client>
#   skynet-register.sh status
#
# Integrates with docker compose lifecycle:
#   - Post-start hook → register
#   - Pre-stop hook → deregister
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load config
[[ -f "${REPO_ROOT}/configs/ports.env" ]] && source "${REPO_ROOT}/configs/ports.env"
[[ -f "${REPO_ROOT}/configs/servers.env" ]] && source "${REPO_ROOT}/configs/servers.env"
[[ -f "${SCRIPT_DIR}/lib/naming.sh" ]] && source "${SCRIPT_DIR}/lib/naming.sh"

# --- SkyNet API Config ---
SKYNET_API="${SKYNET_API_URL:-http://127.0.0.1:7070}"
SKYNET_TOKEN="${SKYNET_API_TOKEN:-}"
SKYNET_STATE_DIR="${SKYNET_STATE_DIR:-/tmp/xdc-skynet}"

# --- Client → SkyOne agent port mapping ---
declare -A SKYONE_PORTS=(
    [gp5]="${GP5_MAINNET_SKYONE:-7060}"
    [erigon]="${ERIGON_MAINNET_SKYONE:-7061}"
    [nethermind]="${NM_MAINNET_SKYONE:-7062}"
    [reth]="${RETH_MAINNET_SKYONE:-7063}"
    [v268]="${V268_MAINNET_SKYONE:-7064}"
)

# --- Client → RPC port mapping ---
declare -A RPC_PORTS=(
    [gp5]="${GP5_MAINNET_RPC:-8545}"
    [erigon]="${ERIGON_MAINNET_RPC:-8547}"
    [nethermind]="${NM_MAINNET_RPC:-8558}"
    [reth]="${RETH_MAINNET_RPC:-8548}"
    [v268]="${V268_MAINNET_RPC:-8550}"
)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [skynet] $*"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [skynet] [ERROR] $*" >&2; }

# Ensure state dir
mkdir -p "${SKYNET_STATE_DIR}"

# --- Build registration payload ---
build_payload() {
    local client="$1"
    local network="${2:-mainnet}"
    local action="${3:-register}"
    local server_id="${SERVER_ID:-168}"
    local node_name

    # Use naming lib if available
    if command -v get_node_name &>/dev/null; then
        node_name=$(get_node_name "${client}" "${network}" "${server_id}")
    else
        node_name="${client}-${network}-${server_id}"
    fi

    local rpc_port="${RPC_PORTS[${client}]:-8545}"
    local skyone_port="${SKYONE_PORTS[${client}]:-7060}"
    local hostname
    hostname=$(hostname -f 2>/dev/null || hostname)

    # Get current block height
    local block_height="0"
    local hex
    hex=$(curl -sf --max-time 5 -X POST "http://127.0.0.1:${rpc_port}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null \
        | jq -r '.result // empty' 2>/dev/null) || hex=""
    if [[ -n "${hex}" && "${hex}" != "null" ]]; then
        block_height=$(printf '%d' "${hex}" 2>/dev/null) || block_height="0"
    fi

    # Get docker image
    local docker_image=""
    local container
    container=$(docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null | grep -i "${client}" | head -1 | awk '{print $2}') || container=""
    docker_image="${container:-unknown}"

    jq -n \
        --arg name "${node_name}" \
        --arg client "${client}" \
        --arg network "${network}" \
        --arg server_id "${server_id}" \
        --arg hostname "${hostname}" \
        --arg action "${action}" \
        --arg rpc_port "${rpc_port}" \
        --arg skyone_port "${skyone_port}" \
        --argjson block_height "${block_height}" \
        --arg docker_image "${docker_image}" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            node_name: $name,
            client: $client,
            network: $network,
            server_id: $server_id,
            hostname: $hostname,
            action: $action,
            rpc_port: ($rpc_port | tonumber),
            skyone_port: ($skyone_port | tonumber),
            block_height: $block_height,
            docker_image: $docker_image,
            timestamp: $timestamp,
            status: (if $action == "register" then "online" else "offline" end)
        }'
}

# --- Register with SkyNet ---
cmd_register() {
    local client="${1:-}"
    local network="${2:-mainnet}"

    if [[ -z "${client}" ]]; then
        error "Usage: skynet-register.sh register <client> [--network mainnet]"
        exit 1
    fi

    log "Registering ${client} (${network}) with SkyNet..."

    local payload
    payload=$(build_payload "${client}" "${network}" "register")

    # Save state locally
    echo "${payload}" > "${SKYNET_STATE_DIR}/${client}-${network}.json"

    # POST to SkyNet API
    local http_code
    local auth_header=""
    [[ -n "${SKYNET_TOKEN}" ]] && auth_header="-H \"Authorization: Bearer ${SKYNET_TOKEN}\""

    http_code=$(curl -sf -o /dev/null -w '%{http_code}' --max-time 10 \
        -X POST "${SKYNET_API}/api/nodes/register" \
        -H "Content-Type: application/json" \
        ${auth_header} \
        -d "${payload}" 2>/dev/null) || http_code="000"

    if [[ "${http_code}" == "200" || "${http_code}" == "201" ]]; then
        log "  ✓ Registered with SkyNet (HTTP ${http_code})"
    elif [[ "${http_code}" == "000" ]]; then
        log "  ⚠ SkyNet API unreachable — saved state locally"
        log "  State: ${SKYNET_STATE_DIR}/${client}-${network}.json"
    else
        error "  ✗ SkyNet registration failed (HTTP ${http_code})"
    fi

    log "  Node: $(echo "${payload}" | jq -r '.node_name')"
    log "  Block: $(echo "${payload}" | jq -r '.block_height')"
}

# --- Deregister from SkyNet ---
cmd_deregister() {
    local client="${1:-}"
    local network="${2:-mainnet}"

    if [[ -z "${client}" ]]; then
        error "Usage: skynet-register.sh deregister <client> [--network mainnet]"
        exit 1
    fi

    log "Deregistering ${client} (${network}) from SkyNet..."

    local payload
    payload=$(build_payload "${client}" "${network}" "deregister")

    # Update local state
    echo "${payload}" > "${SKYNET_STATE_DIR}/${client}-${network}.json"

    # POST to SkyNet API
    local auth_header=""
    [[ -n "${SKYNET_TOKEN}" ]] && auth_header="-H \"Authorization: Bearer ${SKYNET_TOKEN}\""

    local http_code
    http_code=$(curl -sf -o /dev/null -w '%{http_code}' --max-time 10 \
        -X POST "${SKYNET_API}/api/nodes/deregister" \
        -H "Content-Type: application/json" \
        ${auth_header} \
        -d "${payload}" 2>/dev/null) || http_code="000"

    if [[ "${http_code}" == "200" ]]; then
        log "  ✓ Deregistered from SkyNet"
    elif [[ "${http_code}" == "000" ]]; then
        log "  ⚠ SkyNet API unreachable — marked offline locally"
    else
        error "  ✗ SkyNet deregistration failed (HTTP ${http_code})"
    fi
}

# --- Heartbeat to SkyNet ---
cmd_heartbeat() {
    local client="${1:-}"
    local network="${2:-mainnet}"

    if [[ -z "${client}" ]]; then
        # Heartbeat all registered clients
        for state_file in "${SKYNET_STATE_DIR}"/*-*.json; do
            [[ -f "${state_file}" ]] || continue
            local c n
            c=$(jq -r '.client' "${state_file}" 2>/dev/null) || continue
            n=$(jq -r '.network' "${state_file}" 2>/dev/null) || continue
            cmd_heartbeat "${c}" "${n}"
        done
        return
    fi

    local payload
    payload=$(build_payload "${client}" "${network}" "heartbeat")

    local auth_header=""
    [[ -n "${SKYNET_TOKEN}" ]] && auth_header="-H \"Authorization: Bearer ${SKYNET_TOKEN}\""

    curl -sf --max-time 10 \
        -X POST "${SKYNET_API}/api/nodes/heartbeat" \
        -H "Content-Type: application/json" \
        ${auth_header} \
        -d "${payload}" >/dev/null 2>&1 || true

    # Update local state
    echo "${payload}" > "${SKYNET_STATE_DIR}/${client}-${network}.json"
}

# --- Status ---
cmd_status() {
    echo "=== SkyNet Registration Status ==="
    echo "API: ${SKYNET_API}"
    echo ""

    local found=false
    for state_file in "${SKYNET_STATE_DIR}"/*-*.json; do
        [[ -f "${state_file}" ]] || continue
        found=true
        local name status block ts
        name=$(jq -r '.node_name // "?"' "${state_file}" 2>/dev/null)
        status=$(jq -r '.status // "?"' "${state_file}" 2>/dev/null)
        block=$(jq -r '.block_height // 0' "${state_file}" 2>/dev/null)
        ts=$(jq -r '.timestamp // "?"' "${state_file}" 2>/dev/null)
        printf "  %-30s  status=%-8s  block=%-10s  updated=%s\n" "${name}" "${status}" "${block}" "${ts}"
    done

    if [[ "${found}" == "false" ]]; then
        echo "  No registered nodes."
    fi
}

# ============================================================
# Docker Compose Lifecycle Integration
# ============================================================
# Add to docker-compose.yml services:
#
#   gp5:
#     ...
#     labels:
#       - "com.xdc.client=gp5"
#       - "com.xdc.network=mainnet"
#     # Post-start: register with SkyNet
#     # Pre-stop: deregister from SkyNet
#
# Then in entrypoint or wrapper script:
#   trap 'skynet-register.sh deregister gp5' EXIT
#   skynet-register.sh register gp5
# ============================================================

# ============================================================
# CLI Router
# ============================================================
usage() {
    echo "Usage: skynet-register.sh <command> <client> [--network <network>]"
    echo ""
    echo "Commands:"
    echo "  register <client>      Register node with SkyNet (on start)"
    echo "  deregister <client>    Mark node offline in SkyNet (on stop)"
    echo "  heartbeat [client]     Send heartbeat (all if no client)"
    echo "  status                 Show local registration state"
    echo ""
    echo "Environment:"
    echo "  SKYNET_API_URL    SkyNet API base URL (default: http://127.0.0.1:7070)"
    echo "  SKYNET_API_TOKEN  Auth token for SkyNet API"
    exit 1
}

COMMAND="${1:-}"
shift || true

# Parse remaining args
CLIENT=""
NETWORK="mainnet"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --network) NETWORK="$2"; shift 2 ;;
        -*) error "Unknown flag: $1"; usage ;;
        *) CLIENT="$1"; shift ;;
    esac
done

case "${COMMAND}" in
    register)    cmd_register "${CLIENT}" "${NETWORK}" ;;
    deregister)  cmd_deregister "${CLIENT}" "${NETWORK}" ;;
    heartbeat)   cmd_heartbeat "${CLIENT}" "${NETWORK}" ;;
    status)      cmd_status ;;
    -h|--help|"") usage ;;
    *)           error "Unknown command: ${COMMAND}"; usage ;;
esac
