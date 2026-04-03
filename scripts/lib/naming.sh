#!/usr/bin/env bash
# ============================================================
# naming.sh — Node Naming Standard Library
# Issue: #141 — Enhanced naming with sync type and state scheme
# ============================================================
# Pattern: {location}-{client}-{sync}-{scheme}-{network}-{server_id}
# Example: xdc01-xdc-full-hbss-mainnet-125
#          xdc01-geth-full-pbss-mainnet-125
#
# Client mapping:
#   v2.6.8 official  → xdc
#   GP5 (go-ethereum) → geth
#   Erigon           → erigon
#   Nethermind       → nethermind
#   Reth             → reth
# ============================================================

[[ "${_XDC_NAMING_LOADED:-}" == "1" ]] && return 0
_XDC_NAMING_LOADED=1

_NAMING_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVERS_ENV="${SERVERS_ENV:-${_NAMING_SCRIPT_DIR}/../../configs/servers.env}"

[[ -f "${SERVERS_ENV}" ]] && source "${SERVERS_ENV}"

# Location map: server_id → location label
declare -A _LOCATION_MAP=(
    [168]="test"
    [213]="prod"
    [125]="xdc01"
    [109]="xdc02"
    [113]="xdc03"
    [4]="xdc07"
)

# Client map: input → normalized name
declare -A _CLIENT_MAP=(
    [v268]="xdc"
    [v2.6.8]="xdc"
    [xdc]="xdc"
    [gp5]="geth"
    [geth]="geth"
    [erigon]="erigon"
    [nethermind]="nethermind"
    [nm]="nethermind"
    [reth]="reth"
)

# Get server ID from IP (last octet)
get_server_id() {
    local ip="${1:-$(hostname -I | awk '{print $1}')}"
    echo "${ip##*.}"
}

# Get location label from server ID
get_location() {
    local sid="${1:-$(get_server_id)}"
    echo "${_LOCATION_MAP[$sid]:-srv${sid}}"
}

# Normalize client name
get_client_name() {
    local input="${1,,}" # lowercase
    echo "${_CLIENT_MAP[$input]:-$input}"
}

# Build full node name
# Usage: build_node_name <client> <network> [sync_mode] [state_scheme] [server_id]
build_node_name() {
    local client="$(get_client_name "${1:?client required}")"
    local network="${2:?network required}"
    local sync="${3:-full}"
    local scheme="${4:-hbss}"
    local sid="${5:-$(get_server_id)}"
    local location="$(get_location "$sid")"

    # Default scheme per client
    if [[ "$scheme" == "auto" ]]; then
        case "$client" in
            xdc) scheme="hbss" ;;
            geth) scheme="pbss" ;;
            erigon) scheme="hbss" ;;
            nethermind) scheme="hbss" ;;
            reth) scheme="hbss" ;;
            *) scheme="hbss" ;;
        esac
    fi

    echo "${location}-${client}-${sync}-${scheme}-${network}-${sid}"
}

# Build container name (same as node name)
build_container_name() { build_node_name "$@"; }

# Build SkyOne agent name
build_skyone_name() { echo "skyone-$(build_node_name "$@")"; }
