#!/usr/bin/env bash
# ============================================================
# naming.sh — Node Naming Standard Library
# Issue: #141 — Enhanced naming with sync type and state scheme
# Issue: #151 — 6-part XNS standard with backward compatibility
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

# Build full node name (6-part XNS standard)
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

# ============================================================
# Node Naming Functions (XNS 6-Part Standard)
# ============================================================

# Generate a full node name with explicit sync and scheme parameters.
# Usage: generate_node_name <client> <network> [sync_mode] [state_scheme] [server_id]
# Example: generate_node_name geth mainnet full pbss 125
# Returns: xdc01-geth-full-pbss-mainnet-125
generate_node_name() {
    local client="${1:?client required}"
    local network="${2:?network required}"
    local sync="${3:-full}"
    local scheme="${4:-auto}"
    local server_id="${5:-$(get_server_id)}"
    build_node_name "$client" "$network" "$sync" "$scheme" "$server_id"
}

# Parse a node name into components.
# Usage: parse_node_name <name>
# Sets: NODE_NAME_LOCATION, NODE_NAME_CLIENT, NODE_NAME_SYNC,
#       NODE_NAME_SCHEME, NODE_NAME_NETWORK, NODE_NAME_SERVER_ID
# Returns: 0 on success, 1 on failure
# Supports both 6-part XNS and 4-part legacy names.
parse_node_name() {
    local name="$1"
    local parts
    IFS='-' read -ra parts <<< "$name"

    # Reset output variables
    NODE_NAME_LOCATION=""
    NODE_NAME_CLIENT=""
    NODE_NAME_SYNC=""
    NODE_NAME_SCHEME=""
    NODE_NAME_NETWORK=""
    NODE_NAME_SERVER_ID=""

    if [[ ${#parts[@]} -eq 6 ]]; then
        # 6-part XNS: location-client-sync-scheme-network-server_id
        NODE_NAME_LOCATION="${parts[0]}"
        NODE_NAME_CLIENT="${parts[1]}"
        NODE_NAME_SYNC="${parts[2]}"
        NODE_NAME_SCHEME="${parts[3]}"
        NODE_NAME_NETWORK="${parts[4]}"
        NODE_NAME_SERVER_ID="${parts[5]}"
        return 0
    elif [[ ${#parts[@]} -eq 4 ]]; then
        # 4-part legacy: location-client-network-server_id
        NODE_NAME_LOCATION="${parts[0]}"
        NODE_NAME_CLIENT="${parts[1]}"
        NODE_NAME_NETWORK="${parts[2]}"
        NODE_NAME_SERVER_ID="${parts[3]}"
        return 0
    else
        echo "parse_node_name: expected 4 or 6 hyphen-separated parts, got ${#parts[@]}" >&2
        return 1
    fi
}

# Validate a node name conforms to XNS standard.
# Usage: validate_node_name <name>
# Returns: 0 if valid, 1 if invalid
# Accepts both 6-part XNS and 4-part legacy names.
validate_node_name() {
    local name="$1"
    if ! parse_node_name "$name"; then
        echo "validate_node_name: invalid node name: $name" >&2
        echo "  Expected 6-part: {location}-{client}-{sync}-{scheme}-{network}-{server_id}" >&2
        echo "  or 4-part (legacy): {location}-{client}-{network}-{server_id}" >&2
        return 1
    fi

    local valid_schemes=("hbss" "pbss" "archive" "erigon" "mdbx")
    local valid_syncs=("full" "fast" "snap" "archive")
    local valid_networks=("mainnet" "apothem" "devnet")
    local valid_clients=("xdc" "geth" "erigon" "nethermind" "reth")

    local ok=true

    # Validate client (always present)
    local client_ok=false
    for c in "${valid_clients[@]}"; do
        [[ "$NODE_NAME_CLIENT" == "$c" ]] && client_ok=true
    done
    if [[ "$client_ok" == "false" ]]; then
        echo "validate_node_name: unrecognized client: $NODE_NAME_CLIENT" >&2
        ok=false
    fi

    # Validate network (always present)
    local net_ok=false
    for n in "${valid_networks[@]}"; do
        [[ "$NODE_NAME_NETWORK" == "$n" ]] && net_ok=true
    done
    if [[ "$net_ok" == "false" ]]; then
        echo "validate_node_name: unrecognized network: $NODE_NAME_NETWORK" >&2
        ok=false
    fi

    # Validate sync mode (only for 6-part)
    if [[ -n "$NODE_NAME_SYNC" ]]; then
        local sync_ok=false
        for s in "${valid_syncs[@]}"; do
            [[ "$NODE_NAME_SYNC" == "$s" ]] && sync_ok=true
        done
        if [[ "$sync_ok" == "false" ]]; then
            echo "validate_node_name: unrecognized sync mode: $NODE_NAME_SYNC" >&2
            ok=false
        fi
    fi

    # Validate scheme (only for 6-part)
    if [[ -n "$NODE_NAME_SCHEME" ]]; then
        local scheme_ok=false
        for s in "${valid_schemes[@]}"; do
            [[ "$NODE_NAME_SCHEME" == "$s" ]] && scheme_ok=true
        done
        if [[ "$scheme_ok" == "false" ]]; then
            echo "validate_node_name: unrecognized scheme: $NODE_NAME_SCHEME" >&2
            ok=false
        fi
    fi

    [[ "$ok" == "true" ]] && return 0 || return 1
}

# ============================================================
# Snapshot Naming Standard (XNS 8-Part Extension)
# Pattern: {location}-{client}-{sync}-{scheme}-{network}-{server_id}-{image_digest}-{timestamp}.{ext}
# Minimal required: {client}-{sync}-{scheme}-{network}-{timestamp}.{ext}
# Full standard:     {location}-{client}-{sync}-{scheme}-{network}-{server_id}-{image_digest}-{timestamp}.{ext}
#
# Examples:
#   xdc01-xdc-full-hbss-mainnet-125-sha256abc-20260418-120000.tar.zst
#   xdc01-geth-full-pbss-mainnet-125-sha256def-20260418-120000.tar.zst
# ============================================================

# Build snapshot filename from components.
# Usage: build_snapshot_name <client> <network> [sync] [scheme] [location] [server_id] [image_digest] [timestamp] [ext]
build_snapshot_name() {
    local client="$(get_client_name "${1:?client required}")"
    local network="${2:?network required}"
    local sync="${3:-full}"
    local scheme="${4:-hbss}"
    local location="${5:-$(get_location)}"
    local sid="${6:-$(get_server_id)}"
    local image_digest="${7:-unknown}"
    local timestamp="${8:-$(date +%Y%m%d-%H%M%S)}"
    local ext="${9:-tar.zst}"

    echo "${location}-${client}-${sync}-${scheme}-${network}-${sid}-${image_digest}-${timestamp}.${ext}"
}

# Parse a snapshot filename into components.
# Usage: parse_snapshot_name <filename>
# Sets: SNAPSHOT_NAME_CLIENT, SNAPSHOT_NAME_SYNC, SNAPSHOT_NAME_SCHEME,
#       SNAPSHOT_NAME_NETWORK, SNAPSHOT_NAME_LOCATION, SNAPSHOT_NAME_SERVER_ID,
#       SNAPSHOT_NAME_DIGEST, SNAPSHOT_NAME_TIMESTAMP, SNAPSHOT_NAME_EXT
# Returns: 0 if parseable, 1 otherwise
parse_snapshot_name() {
    local filename="${1##*/}"  # strip path
    local ext=""
    local basename=""

    # Handle .tar.zst / .tar.gz double extension
    if [[ "$filename" == *.tar.zst ]]; then
        ext="tar.zst"
        basename="${filename%.tar.zst}"
    elif [[ "$filename" == *.tar.gz ]]; then
        ext="tar.gz"
        basename="${filename%.tar.gz}"
    else
        ext="${filename##*.}"
        basename="${filename%.*}"
    fi

    SNAPSHOT_NAME_EXT="$ext"

    # Extract timestamp from the end: YYYYMMDD-HHMMSS pattern
    local prefix=""
    if [[ "$basename" =~ ^(.*)-([0-9]{8}-[0-9]{6})$ ]]; then
        prefix="${BASH_REMATCH[1]}"
        SNAPSHOT_NAME_TIMESTAMP="${BASH_REMATCH[2]}"
    else
        # Fallback: last hyphen-separated token is the timestamp
        SNAPSHOT_NAME_TIMESTAMP="${basename##*-}"
        prefix="${basename%-${SNAPSHOT_NAME_TIMESTAMP}}"
    fi

    local parts
    IFS='-' read -ra parts <<< "$prefix"

    if [[ ${#parts[@]} -ge 7 ]]; then
        # Full 8-part: location-client-sync-scheme-network-sid-digest...
        SNAPSHOT_NAME_LOCATION="${parts[0]}"
        SNAPSHOT_NAME_CLIENT="${parts[1]}"
        SNAPSHOT_NAME_SYNC="${parts[2]}"
        SNAPSHOT_NAME_SCHEME="${parts[3]}"
        SNAPSHOT_NAME_NETWORK="${parts[4]}"
        SNAPSHOT_NAME_SERVER_ID="${parts[5]}"
        # Join remaining parts as digest (handles digests with hyphens)
        SNAPSHOT_NAME_DIGEST="${parts[6]}"
        local i
        for ((i=7; i<${#parts[@]}; i++)); do
            SNAPSHOT_NAME_DIGEST="${SNAPSHOT_NAME_DIGEST}-${parts[$i]}"
        done
        return 0
    elif [[ ${#parts[@]} -ge 4 ]]; then
        # Minimal 5-part: client-sync-scheme-network
        SNAPSHOT_NAME_LOCATION=""
        SNAPSHOT_NAME_CLIENT="${parts[0]}"
        SNAPSHOT_NAME_SYNC="${parts[1]}"
        SNAPSHOT_NAME_SCHEME="${parts[2]}"
        SNAPSHOT_NAME_NETWORK="${parts[3]}"
        SNAPSHOT_NAME_SERVER_ID=""
        SNAPSHOT_NAME_DIGEST=""
        return 0
    else
        echo "parse_snapshot_name: expected at least 4 hyphen-separated prefix parts, got ${#parts[@]}" >&2
        return 1
    fi
}

# Validate that a snapshot filename conforms to XNS standard.
# Usage: validate_snapshot_name <filename>
# Returns: 0 if valid, 1 if invalid
validate_snapshot_name() {
    local filename="$1"
    if ! parse_snapshot_name "$filename"; then
        echo "validate_snapshot_name: invalid snapshot filename: $filename" >&2
        echo "  Expected 8-part: {location}-{client}-{sync}-{scheme}-{network}-{server_id}-{digest}-{timestamp}.{ext}" >&2
        echo "  or 5-part (minimal): {client}-{sync}-{scheme}-{network}-{timestamp}.{ext}" >&2
        return 1
    fi

    local valid_schemes=("hbss" "pbss" "archive" "erigon" "mdbx")
    local valid_syncs=("full" "fast" "snap" "archive")
    local valid_networks=("mainnet" "apothem" "devnet")
    local valid_clients=("xdc" "geth" "erigon" "nethermind" "reth")

    local ok=true

    # Validate client
    local client_ok=false
    for c in "${valid_clients[@]}"; do
        [[ "$SNAPSHOT_NAME_CLIENT" == "$c" ]] && client_ok=true
    done
    if [[ "$client_ok" == "false" ]]; then
        echo "validate_snapshot_name: unrecognized client: $SNAPSHOT_NAME_CLIENT" >&2
        ok=false
    fi

    # Validate network
    local net_ok=false
    for n in "${valid_networks[@]}"; do
        [[ "$SNAPSHOT_NAME_NETWORK" == "$n" ]] && net_ok=true
    done
    if [[ "$net_ok" == "false" ]]; then
        echo "validate_snapshot_name: unrecognized network: $SNAPSHOT_NAME_NETWORK" >&2
        ok=false
    fi

    # Validate sync mode
    local sync_ok=false
    for s in "${valid_syncs[@]}"; do
        [[ "$SNAPSHOT_NAME_SYNC" == "$s" ]] && sync_ok=true
    done
    if [[ "$sync_ok" == "false" ]]; then
        echo "validate_snapshot_name: unrecognized sync mode: $SNAPSHOT_NAME_SYNC" >&2
        ok=false
    fi

    # Validate scheme
    local scheme_ok=false
    for s in "${valid_schemes[@]}"; do
        [[ "$SNAPSHOT_NAME_SCHEME" == "$s" ]] && scheme_ok=true
    done
    if [[ "$scheme_ok" == "false" ]]; then
        echo "validate_snapshot_name: unrecognized scheme: $SNAPSHOT_NAME_SCHEME" >&2
        ok=false
    fi

    [[ "$ok" == "true" ]] && return 0 || return 1
}
