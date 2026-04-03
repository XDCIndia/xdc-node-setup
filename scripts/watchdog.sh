#!/usr/bin/env bash
# ============================================================
# watchdog.sh — Sync Stall Detection & Self-Healing
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/91
# ============================================================
# Checks each running XDC client's block height.
# If block hasn't advanced in 15 min → restart container.
# If block hasn't advanced in 30 min → log critical alert.
#
# State stored in /tmp/xdc-watchdog-state.json
# Run via cron every 5 minutes:
#   */5 * * * * /path/to/scripts/watchdog.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load ports config
[[ -f "${REPO_ROOT}/configs/ports.env" ]] && source "${REPO_ROOT}/configs/ports.env"

# --- Config ---
STATE_FILE="${WATCHDOG_STATE:-/tmp/xdc-watchdog-state.json}"
STALL_RESTART_SEC=900    # 15 min — restart container
STALL_CRITICAL_SEC=1800  # 30 min — critical alert
LOG_FILE="${WATCHDOG_LOG:-/var/log/xdc-watchdog.log}"
NOW=$(date +%s)

# --- Client RPC ports ---
declare -A CLIENT_PORTS=(
    [gp5]="${GP5_MAINNET_RPC:-8545}"
    [erigon]="${ERIGON_MAINNET_RPC:-8547}"
    [nethermind]="${NM_MAINNET_RPC:-8558}"
    [reth]="${RETH_MAINNET_RPC:-8548}"
    [v268]="${V268_MAINNET_RPC:-8550}"
)

# --- Container name patterns ---
declare -A CLIENT_CONTAINERS=(
    [gp5]="gp5"
    [erigon]="erigon"
    [nethermind]="nethermind"
    [reth]="reth"
    [v268]="v268"
)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}" 2>/dev/null || echo "$*"; }
warn() { log "[WARN] $*"; }
critical() { log "[CRITICAL] $*"; }

# --- Get block height via RPC ---
get_block_height() {
    local port="$1"
    local result
    result=$(curl -sf --max-time 5 -X POST "http://127.0.0.1:${port}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null) || return 1

    local hex
    hex=$(echo "${result}" | jq -r '.result // empty' 2>/dev/null) || return 1
    [[ -z "${hex}" || "${hex}" == "null" ]] && return 1

    # Convert hex to decimal
    printf '%d\n' "${hex}" 2>/dev/null || return 1
}

# --- Load state ---
load_state() {
    if [[ -f "${STATE_FILE}" ]]; then
        cat "${STATE_FILE}"
    else
        echo '{}'
    fi
}

# --- Save state ---
save_state() {
    local state="$1"
    echo "${state}" > "${STATE_FILE}"
}

# --- Get state value ---
state_get() {
    local state="$1" client="$2" field="$3"
    echo "${state}" | jq -r ".\"${client}\".\"${field}\" // empty" 2>/dev/null
}

# --- Find running container matching client name ---
find_container() {
    local client="$1"
    docker ps --format '{{.Names}}' 2>/dev/null | grep -i "${client}" | head -1
}

# --- Restart container ---
restart_container() {
    local container="$1"
    log "Restarting container: ${container}"
    docker restart "${container}" 2>&1 | while read -r line; do log "  docker: ${line}"; done
}

# --- Main check loop ---
main() {
    local state
    state=$(load_state)
    local new_state="{}"
    local any_running=false

    log "=== Watchdog check ==="

    for client in "${!CLIENT_PORTS[@]}"; do
        local port="${CLIENT_PORTS[${client}]}"
        local container

        # Find running container
        container=$(find_container "${CLIENT_CONTAINERS[${client}]}")
        if [[ -z "${container}" ]]; then
            continue
        fi
        any_running=true

        # Get current block height
        local height
        height=$(get_block_height "${port}") || {
            warn "${client}: RPC not responding on port ${port}"
            # Preserve state but mark RPC down
            local prev_height prev_ts
            prev_height=$(state_get "${state}" "${client}" "height")
            prev_ts=$(state_get "${state}" "${client}" "last_advance")
            new_state=$(echo "${new_state}" | jq \
                --arg c "${client}" \
                --arg h "${prev_height:-0}" \
                --arg t "${prev_ts:-${NOW}}" \
                --arg n "${NOW}" \
                '.[$c] = {"height": ($h|tonumber), "last_advance": ($t|tonumber), "last_check": ($n|tonumber), "rpc_down": true}')
            continue
        }

        log "${client}: block ${height} (port ${port}, container ${container})"

        # Compare with previous state
        local prev_height prev_advance_ts
        prev_height=$(state_get "${state}" "${client}" "height")
        prev_advance_ts=$(state_get "${state}" "${client}" "last_advance")

        local last_advance="${NOW}"
        if [[ -n "${prev_height}" && "${height}" -le "${prev_height}" && -n "${prev_advance_ts}" ]]; then
            # Block hasn't advanced
            last_advance="${prev_advance_ts}"
            local stall_sec=$((NOW - last_advance))

            if [[ ${stall_sec} -ge ${STALL_CRITICAL_SEC} ]]; then
                critical "${client}: STALLED for ${stall_sec}s (>30min) at block ${height}!"
                critical "Container: ${container} — manual intervention may be needed"
                # Still try a restart
                restart_container "${container}"
            elif [[ ${stall_sec} -ge ${STALL_RESTART_SEC} ]]; then
                warn "${client}: stalled for ${stall_sec}s (>15min) at block ${height} — restarting"
                restart_container "${container}"
            else
                log "${client}: block unchanged (stall ${stall_sec}s < ${STALL_RESTART_SEC}s threshold)"
            fi
        else
            # Block advanced or first check
            if [[ -n "${prev_height}" ]]; then
                local delta=$((height - prev_height))
                log "${client}: advanced +${delta} blocks since last check"
            fi
        fi

        # Update state
        new_state=$(echo "${new_state}" | jq \
            --arg c "${client}" \
            --argjson h "${height}" \
            --argjson t "${last_advance}" \
            --argjson n "${NOW}" \
            '.[$c] = {"height": $h, "last_advance": $t, "last_check": $n, "rpc_down": false}')
    done

    save_state "${new_state}"

    if [[ "${any_running}" == "false" ]]; then
        log "No running XDC containers found"
    fi

    log "=== Watchdog done ==="
}

# --- CLI ---
case "${1:-check}" in
    check|"")
        main
        ;;
    status)
        if [[ -f "${STATE_FILE}" ]]; then
            echo "=== Watchdog State ==="
            jq '.' "${STATE_FILE}"
        else
            echo "No state file found (${STATE_FILE})"
        fi
        ;;
    install-cron)
        CRON_LINE="*/5 * * * * ${SCRIPT_DIR}/watchdog.sh check >> /var/log/xdc-watchdog.log 2>&1"
        (crontab -l 2>/dev/null | grep -v 'watchdog.sh'; echo "${CRON_LINE}") | crontab -
        echo "Installed cron: ${CRON_LINE}"
        ;;
    *)
        echo "Usage: $0 [check|status|install-cron]"
        exit 1
        ;;
esac
