#!/usr/bin/env bash
# ============================================================
# naming.sh — Node Naming Standard Library
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/96
# ============================================================
# Pattern: {location}-{client}-{network}-{server_id}
# Example: test-gp5-mainnet-168
#          prod-erigon-mainnet-213
#          test-nethermind-apothem-168
#
# Location mapping (from configs/servers.env):
#   168 → test
#   213 → prod
#   (add more as fleet grows)
# ============================================================

# Guard against double-sourcing
[[ "${_XDC_NAMING_LOADED:-}" == "1" ]] && return 0
_XDC_NAMING_LOADED=1

# Default servers.env location (relative to repo root)
_NAMING_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVERS_ENV="${SERVERS_ENV:-${_NAMING_SCRIPT_DIR}/../../configs/servers.env}"

# ---- Load servers.env if it exists ----
if [[ -f "${SERVERS_ENV}" ]]; then
    # shellcheck source=/dev/null
    source "${SERVERS_ENV}"
fi

# ---- Location map: server_id → location label ----
# Extend this as fleet grows
declare -A _LOCATION_MAP=(
    [168]="test"
    [213]="prod"
    [42]="staging"
    [100]="eu-west"
    [101]="ap-southeast"
)

# ---- get_location(server_id) ----
# Returns location label for a server ID.
# Falls back to LOCATION env var, then "unknown".
get_location() {
    local server_id="${1:-${SERVER_ID:-}}"

    # Check env var from servers.env first (e.g. SERVER_168_LOCATION=test)
    local env_key="SERVER_${server_id}_LOCATION"
    if [[ -n "${!env_key:-}" ]]; then
        echo "${!env_key}"
        return 0
    fi

    # Check static map
    if [[ -n "${_LOCATION_MAP[${server_id}]:-}" ]]; then
        echo "${_LOCATION_MAP[${server_id}]}"
        return 0
    fi

    # Fall back to LOCATION env var
    if [[ -n "${LOCATION:-}" ]]; then
        echo "${LOCATION}"
        return 0
    fi

    # Last resort
    echo "unknown"
}

# ---- get_node_name(client, network, server_id) ----
# Returns: {location}-{client}-{network}-{server_id}
# All args are optional; falls back to env vars.
#
# Usage:
#   get_node_name gp5 mainnet 168
#   get_node_name               # uses CLIENT, NETWORK, SERVER_ID env vars
#   NODE_NAME=$(get_node_name erigon mainnet 213)
get_node_name() {
    local client="${1:-${CLIENT:-unknown}}"
    local network="${2:-${NETWORK:-mainnet}}"
    local server_id="${3:-${SERVER_ID:-0}}"
    local location

    location="$(get_location "${server_id}")"

    # Normalize: lowercase, strip special chars
    client="${client,,}"
    network="${network,,}"
    location="${location,,}"

    echo "${location}-${client}-${network}-${server_id}"
}

# ---- parse_node_name(node_name) ----
# Parses a node name and exports PARSED_LOCATION, PARSED_CLIENT,
# PARSED_NETWORK, PARSED_SERVER_ID
parse_node_name() {
    local node_name="$1"
    IFS='-' read -ra parts <<< "${node_name}"

    if [[ ${#parts[@]} -lt 4 ]]; then
        echo "ERROR: Invalid node name format '${node_name}'. Expected: {location}-{client}-{network}-{server_id}" >&2
        return 1
    fi

    export PARSED_LOCATION="${parts[0]}"
    export PARSED_CLIENT="${parts[1]}"
    export PARSED_NETWORK="${parts[2]}"
    export PARSED_SERVER_ID="${parts[3]}"
}

# ---- validate_node_name(node_name) ----
# Returns 0 if valid, 1 if not
validate_node_name() {
    local node_name="$1"
    if [[ "${node_name}" =~ ^[a-z0-9]+-[a-z0-9]+-[a-z0-9]+-[0-9]+$ ]]; then
        return 0
    fi
    return 1
}

# ---- If run directly (not sourced), demo / test ----
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "=== XDC Node Naming Demo ==="
    echo ""
    echo "Pattern: {location}-{client}-{network}-{server_id}"
    echo ""
    printf "%-30s → %s\n" "gp5, mainnet, 168"       "$(get_node_name gp5 mainnet 168)"
    printf "%-30s → %s\n" "erigon, mainnet, 213"     "$(get_node_name erigon mainnet 213)"
    printf "%-30s → %s\n" "nethermind, apothem, 168" "$(get_node_name nethermind apothem 168)"
    printf "%-30s → %s\n" "reth, mainnet, 213"       "$(get_node_name reth mainnet 213)"
    printf "%-30s → %s\n" "v268, mainnet, 168"       "$(get_node_name v268 mainnet 168)"
    echo ""
    echo "=== Parse test ==="
    parse_node_name "prod-erigon-mainnet-213"
    echo "PARSED_LOCATION=${PARSED_LOCATION}"
    echo "PARSED_CLIENT=${PARSED_CLIENT}"
    echo "PARSED_NETWORK=${PARSED_NETWORK}"
    echo "PARSED_SERVER_ID=${PARSED_SERVER_ID}"
fi
