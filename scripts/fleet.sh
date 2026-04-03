#!/usr/bin/env bash
# ============================================================
# fleet.sh — Fleet Management
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/93
# ============================================================
# Manages XDC node fleet across multiple servers.
#
# Usage:
#   fleet.sh status                         — block heights across all servers
#   fleet.sh deploy <client> <network>      — deploy client to all servers
#   fleet.sh rolling-update <client>        — rolling restart across fleet
#   fleet.sh exec <command>                 — run command on all servers
#
# Uses configs/servers.env for server list.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load servers
SERVERS_ENV="${REPO_ROOT}/configs/servers.env"
[[ -f "${SERVERS_ENV}" ]] && source "${SERVERS_ENV}"

# Load ports
[[ -f "${REPO_ROOT}/configs/ports.env" ]] && source "${REPO_ROOT}/configs/ports.env"

# Load naming lib
[[ -f "${SCRIPT_DIR}/lib/naming.sh" ]] && source "${SCRIPT_DIR}/lib/naming.sh"

# --- Config ---
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o BatchMode=yes"
DEPLOY_DIR="/root/XDC-Node-Setup"

# --- Client RPC ports ---
declare -A CLIENT_PORTS=(
    [gp5]="${GP5_MAINNET_RPC:-8545}"
    [erigon]="${ERIGON_MAINNET_RPC:-8547}"
    [nethermind]="${NM_MAINNET_RPC:-8558}"
    [reth]="${RETH_MAINNET_RPC:-8548}"
    [v268]="${V268_MAINNET_RPC:-8550}"
)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; }

# --- Get server list from servers.env ---
get_servers() {
    if [[ -z "${SERVERS:-}" ]]; then
        error "SERVERS not defined in configs/servers.env"
        exit 1
    fi
    echo "${SERVERS}"
}

# --- SSH to server ---
ssh_server() {
    local server_id="$1"
    shift
    local host_var="SERVER_${server_id}_HOST"
    local user_var="SERVER_${server_id}_USER"
    local host="${!host_var:-}"
    local user="${!user_var:-root}"

    if [[ -z "${host}" ]]; then
        error "No host defined for server ${server_id} (set ${host_var} in servers.env)"
        return 1
    fi

    # shellcheck disable=SC2086
    ssh ${SSH_OPTS} "${user}@${host}" "$@"
}

# --- Get block height from remote server ---
remote_block_height() {
    local server_id="$1"
    local port="$2"
    ssh_server "${server_id}" "curl -sf --max-time 5 -X POST http://127.0.0.1:${port} \
        -H 'Content-Type: application/json' \
        -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' \
        | jq -r '.result // empty'" 2>/dev/null || echo ""
}

# ============================================================
# Commands
# ============================================================

# --- fleet status ---
cmd_status() {
    local servers
    servers=$(get_servers)

    printf "%-25s %-12s %-12s %s\n" "NODE" "CLIENT" "BLOCK" "STATUS"
    printf "%s\n" "$(printf '%.0s-' {1..65})"

    for server_id in ${servers}; do
        local loc_var="SERVER_${server_id}_LOCATION"
        local location="${!loc_var:-unknown}"

        for client in "${!CLIENT_PORTS[@]}"; do
            local port="${CLIENT_PORTS[${client}]}"
            local node_name="${location}-${client}-mainnet-${server_id}"
            local hex_height status block

            hex_height=$(remote_block_height "${server_id}" "${port}" 2>/dev/null) || hex_height=""

            if [[ -n "${hex_height}" && "${hex_height}" != "null" ]]; then
                block=$(printf '%d' "${hex_height}" 2>/dev/null) || block="?"
                status="✓ syncing"
            else
                block="-"
                status="✗ down/unreachable"
            fi

            printf "%-25s %-12s %-12s %s\n" "${node_name}" "${client}" "${block}" "${status}"
        done
    done
}

# --- fleet deploy ---
cmd_deploy() {
    local client="${1:-}"
    local network="${2:-mainnet}"

    if [[ -z "${client}" ]]; then
        error "Usage: fleet.sh deploy <client> <network>"
        exit 1
    fi

    local servers
    servers=$(get_servers)

    log "=== Deploying ${client} (${network}) to fleet ==="

    for server_id in ${servers}; do
        local label_var="SERVER_${server_id}_LABEL"
        local label="${!label_var:-Server ${server_id}}"
        log "Deploying to ${label} (${server_id})..."

        # Sync repo
        ssh_server "${server_id}" "
            cd ${DEPLOY_DIR} 2>/dev/null || { git clone https://github.com/XDCIndia/xdc-node-setup.git ${DEPLOY_DIR} && cd ${DEPLOY_DIR}; }
            git pull --ff-only origin main 2>/dev/null || true
        " || { error "Failed to sync repo on ${server_id}"; continue; }

        # Run volume check
        ssh_server "${server_id}" "
            cd ${DEPLOY_DIR}
            bash scripts/volume-check.sh --clients ${client} --network ${network}
        " || { error "Volume check failed on ${server_id}"; continue; }

        # Start client
        local compose_file="docker/docker-compose.${client}.yml"
        if [[ "${client}" == "gp5" ]]; then
            compose_file="docker/docker-compose.geth-pr5.yml"
        fi

        ssh_server "${server_id}" "
            cd ${DEPLOY_DIR}
            export SERVER_ID=${server_id}
            docker compose --env-file docker/shared/.env.mainnet -f ${compose_file} up -d
        " || { error "Failed to start ${client} on ${server_id}"; continue; }

        log "  ✓ ${client} deployed on ${server_id}"
    done

    log "=== Deploy complete ==="
}

# --- fleet rolling-update ---
cmd_rolling_update() {
    local client="${1:-}"

    if [[ -z "${client}" ]]; then
        error "Usage: fleet.sh rolling-update <client>"
        exit 1
    fi

    local servers
    servers=$(get_servers)
    local server_count
    server_count=$(echo "${servers}" | wc -w)

    log "=== Rolling update: ${client} across ${server_count} servers ==="

    for server_id in ${servers}; do
        local label_var="SERVER_${server_id}_LABEL"
        local label="${!label_var:-Server ${server_id}}"
        log "Updating ${label} (${server_id})..."

        # Pull latest image
        ssh_server "${server_id}" "
            cd ${DEPLOY_DIR}
            git pull --ff-only origin main 2>/dev/null || true
        " || { error "Git pull failed on ${server_id}"; continue; }

        # Find and restart container
        local container
        container=$(ssh_server "${server_id}" "docker ps --format '{{.Names}}' | grep -i '${client}' | head -1" 2>/dev/null) || container=""

        if [[ -n "${container}" ]]; then
            log "  Restarting ${container}..."
            ssh_server "${server_id}" "docker restart ${container}" || {
                error "Failed to restart ${container} on ${server_id}"
                continue
            }

            # Wait for node to start responding
            log "  Waiting for RPC to come up..."
            local port="${CLIENT_PORTS[${client}]:-8545}"
            local attempts=0
            while [[ ${attempts} -lt 12 ]]; do
                local hex
                hex=$(remote_block_height "${server_id}" "${port}" 2>/dev/null) || hex=""
                if [[ -n "${hex}" && "${hex}" != "null" ]]; then
                    local block
                    block=$(printf '%d' "${hex}" 2>/dev/null) || block="?"
                    log "  ✓ ${server_id} back online at block ${block}"
                    break
                fi
                sleep 10
                attempts=$((attempts + 1))
            done

            if [[ ${attempts} -ge 12 ]]; then
                error "  ✗ ${server_id} RPC not responding after 120s — continuing anyway"
            fi
        else
            log "  No running ${client} container on ${server_id} — skipping"
        fi

        # Brief pause between servers
        if [[ "${server_id}" != "$(echo "${servers}" | awk '{print $NF}')" ]]; then
            log "  Pausing 30s before next server..."
            sleep 30
        fi
    done

    log "=== Rolling update complete ==="
}

# --- fleet exec ---
cmd_exec() {
    local cmd="$*"
    if [[ -z "${cmd}" ]]; then
        error "Usage: fleet.sh exec <command>"
        exit 1
    fi

    local servers
    servers=$(get_servers)

    for server_id in ${servers}; do
        local label_var="SERVER_${server_id}_LABEL"
        local label="${!label_var:-Server ${server_id}}"
        echo "=== ${label} (${server_id}) ==="
        ssh_server "${server_id}" "${cmd}" 2>&1 || error "Failed on ${server_id}"
        echo ""
    done
}

# ============================================================
# CLI Router
# ============================================================
usage() {
    echo "Usage: fleet.sh <command> [args...]"
    echo ""
    echo "Commands:"
    echo "  status                     Show block heights across all servers"
    echo "  deploy <client> <network>  Deploy client to all servers"
    echo "  rolling-update <client>    Rolling restart across fleet"
    echo "  exec <command>             Run command on all servers"
    echo ""
    echo "Servers defined in: configs/servers.env"
    exit 1
}

case "${1:-}" in
    status)         cmd_status ;;
    deploy)         shift; cmd_deploy "$@" ;;
    rolling-update) shift; cmd_rolling_update "$@" ;;
    exec)           shift; cmd_exec "$@" ;;
    -h|--help|"")   usage ;;
    *)              error "Unknown command: $1"; usage ;;
esac
