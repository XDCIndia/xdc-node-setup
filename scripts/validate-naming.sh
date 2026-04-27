#!/usr/bin/env bash
# ============================================================
# validate-naming.sh — Validate XNS naming against compose files
# Issue: #141 — CI gate F4 from OPUS47-STRATEGIC-REVIEW.md
# ============================================================
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly NAMING_LIB="${SCRIPT_DIR}/lib/naming.sh"

ERRORS=0
WARNINGS=0

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
error() { log "ERROR: $*"; ((ERRORS++)) || true; }
warn()  { log "WARN:  $*"; ((WARNINGS++)) || true; }

# ------------------------------------------------------------------
# Load naming library
# ------------------------------------------------------------------
if [[ ! -f "${NAMING_LIB}" ]]; then
    error "Naming library not found: ${NAMING_LIB}"
    exit 1
fi

# shellcheck source=scripts/lib/naming.sh
source "${NAMING_LIB}"

# ------------------------------------------------------------------
# Extract declared service names from compose files and compare
# against XNS pattern: {location}-{client}-{sync}-{scheme}-{network}-{server_id}
# ------------------------------------------------------------------
validate_naming() {
    log "=== Phase 1: container / service name XNS validation ==="
    local files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "${REPO_ROOT}" -type f \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" \) -print0 | sort -z)

    for f in "${files[@]}"; do
        # Extract container_name fields
        local names
        names=$(grep -oP 'container_name:\s*\K[^[:space:]]+' "$f" 2>/dev/null || true)
        if [[ -z "$names" ]]; then
            # Try service names if no container_name
            names=$(yq eval '.services | keys | .[]' "$f" 2>/dev/null || true)
        fi

        if [[ -z "$names" ]]; then
            warn "No service/container names found in $f"
            continue
        fi

        while IFS= read -r name; do
            [[ -z "$name" ]] && continue
            # Skip utility containers (prometheus, grafana, etc.)
            if [[ "$name" =~ ^(prometheus|grafana|node-exporter|cadvisor|redis|postgres|mysql|nginx|traefik|certbot|skyone-dashboard|skyone-agent|monitoring|log-rotate|peer-keeper|bootnode|seed|relay|healthcheck|watchdog|snapshot)$ ]]; then
                continue
            fi

            # Validate against XNS pattern: word-word-word-word-word-number
            if [[ ! "$name" =~ ^[a-z0-9]+-[a-z]+-[a-z]+-[a-z]+-(mainnet|apothem|testnet|devnet)-[0-9]+$ ]]; then
                warn "Name '$name' in $f does not match XNS pattern (location-client-sync-scheme-network-sid)"
            else
                log "  OK  $name"
            fi
        done <<< "$names"
    done
}

# ------------------------------------------------------------------
# Phase 2: Validate that client names in compose match known clients
# ------------------------------------------------------------------
validate_client_names() {
    log "=== Phase 2: client name normalization ==="
    local known_clients="xdc geth erigon nethermind reth"
    for f in $(find "${REPO_ROOT}" -type f \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" \) | sort); do
        # Extract image names to infer client
        local images
        images=$(grep -oP 'image:\s*\K[^[:space:]]+' "$f" 2>/dev/null || true)
        while IFS= read -r img; do
            [[ -z "$img" ]] && continue
            local client=""
            case "$img" in
                *xinfin*|*xdc*) client="xdc" ;;
                *geth*|*go-ethereum*) client="geth" ;;
                *erigon*) client="erigon" ;;
                *nethermind*) client="nethermind" ;;
                *reth*) client="reth" ;;
                *prometheus*|*grafana*|*node-exporter*|*cadvisor*|*redis*|*postgres*|*nginx*|*traefik*|*certbot*|*alpine*|*busybox*|*curlimages*) continue ;;
                *) warn "Unknown client image '$img' in $f" ; continue ;;
            esac
            local normalized
            normalized=$(get_client_name "$client" 2>/dev/null || echo "unknown")
            if [[ "$normalized" == "unknown" ]]; then
                error "Could not normalize client '$client' from $f"
            fi
        done <<< "$images"
    done
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
main() {
    log "Starting naming validation (repo: ${REPO_ROOT})"
    validate_naming
    validate_client_names

    log "========================================"
    log "ERRORS:   ${ERRORS}"
    log "WARNINGS: ${WARNINGS}"
    if [[ $ERRORS -gt 0 ]]; then
        log "VALIDATION FAILED"
        exit 1
    fi
    log "VALIDATION PASSED"
    exit 0
}

main "$@"
