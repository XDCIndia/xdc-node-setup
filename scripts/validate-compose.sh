#!/usr/bin/env bash
# ============================================================
# validate-compose.sh — Local compose validation gate
# Issue: #141 — CI gate F4 from OPUS47-STRATEGIC-REVIEW.md
# ============================================================
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly COMPOSE_DIR="${REPO_ROOT}/docker"

ERRORS=0
WARNINGS=0

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
error() { log "ERROR: $*"; ((ERRORS++)) || true; }
warn()  { log "WARN:  $*"; ((WARNINGS++)) || true; }

# ------------------------------------------------------------------
# 1. docker compose config -q on every compose file
# ------------------------------------------------------------------
validate_syntax() {
    log "=== Phase 1: docker compose syntax validation ==="
    local files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "${REPO_ROOT}" -type f \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" \) -print0 | sort -z)

    if [[ ${#files[@]} -eq 0 ]]; then
        error "No docker-compose files found"
        return
    fi

    log "Found ${#files[@]} compose file(s)"
    for f in "${files[@]}"; do
        if docker compose -f "$f" config -q >/dev/null 2>&1; then
            log "  OK  $f"
        else
            error "docker compose config failed: $f"
        fi
    done
}

# ------------------------------------------------------------------
# 2. Regex check for $$ escapes in environment *values*
#    $$ in shell commands inside compose is expected; in env values
#    it may indicate a typo (should be single $ for Compose vars).
# ------------------------------------------------------------------
check_env_dollar_escapes() {
    log "=== Phase 2: env-value $$ escape check ==="
    local files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "${REPO_ROOT}" -type f \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" \) -print0)

    for f in "${files[@]}"; do
        # Look for lines under 'environment:' that contain $$ but are NOT inside command blocks
        # We use a heuristic: if the line is indented under environment and has $$, flag it.
        local hits
        hits=$(awk '
            /^[[:space:]]*environment:/ { in_env=1; next }
            in_env && /^[[:space:]]*[^ #]/ && !/^[[:space:]]+-?[[:space:]]*[A-Za-z]/ { in_env=0 }
            in_env && /\$\$/ { print NR ":" $0 }
        ' "$f" 2>/dev/null || true)
        if [[ -n "$hits" ]]; then
            warn "$$ in env values in $f"
            echo "$hits" | while read -r line; do
                log "  LINE $line"
            done
        fi
    done
}

# ------------------------------------------------------------------
# 3. Check for 0.0.0.0 + admin + * cors/vhosts triple in commands
#    Pattern: 0.0.0.0 binding combined with admin API and open CORS.
# ------------------------------------------------------------------
check_insecure_admin_cors() {
    log "=== Phase 3: insecure admin + 0.0.0.0 + open CORS check ==="
    local files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "${REPO_ROOT}" -type f \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" \) -print0)

    for f in "${files[@]}"; do
        # Read entire file into a single string so we can match across lines inside a service block
        local content
        content=$(cat "$f")

        # Heuristic: if file contains 0.0.0.0 AND (admin_addPeer|admin_peers|admin_*) AND ("*"|origins "*"|corsdomain "*")
        if echo "$content" | grep -q "0\.0\.0\.0"; then
            if echo "$content" | grep -qiE "admin_(addPeer|addTrustedPeer|peers|nodeInfo)"; then
                if echo "$content" | grep -qiE '(wsorigins|origins|corsdomain|allowedorigins|allowedhosts|vhosts)[[:space:]=]*"?\*"?'; then
                    error "Insecure triple found (0.0.0.0 + admin + open CORS): $f"
                fi
            fi
        fi
    done
}

# ------------------------------------------------------------------
# 4. Check for 0.0.0.0 on RPC/HTTP/WS without explicit CORS restriction
# ------------------------------------------------------------------
check_open_rpc_without_cors() {
    log "=== Phase 4: open RPC binding without CORS restriction ==="
    local files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "${REPO_ROOT}" -type f \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" \) -print0)

    for f in "${files[@]}"; do
        # If file has 0.0.0.0 on rpc/http/ws but no CORS/vhosts restriction at all
        if grep -q "0\.0\.0\.0" "$f"; then
            if grep -qiE "(rpcaddr|http\.addr|ws\.addr|JsonRpc\.Host)" "$f"; then
                if ! grep -qiE "(corsdomain|vhosts|origins|allowedorigins|allowedhosts)" "$f"; then
                    warn "RPC bound to 0.0.0.0 with no CORS/vhosts restriction: $f"
                fi
            fi
        fi
    done
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
main() {
    log "Starting compose validation (repo: ${REPO_ROOT})"
    validate_syntax
    check_env_dollar_escapes
    check_insecure_admin_cors
    check_open_rpc_without_cors

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
