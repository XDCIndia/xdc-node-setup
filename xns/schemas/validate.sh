#!/usr/bin/env bash
set -euo pipefail

# XNS Schema Validation Script
# Usage: ./validate.sh [cue_file ...]
# If no args, validates all .cue files in this directory.

readonly SCHEMA_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly CUE_PKG="xns"
readonly OUTPUT_DIR="${SCHEMA_DIR}/../out"

mkdir -p "$OUTPUT_DIR"

# Determine files to validate
if [[ $# -gt 0 ]]; then
    FILES=("$@")
else
    mapfile -t FILES < <(find "$SCHEMA_DIR" -maxdepth 1 -name '*.cue' -not -name 'node.cue' | sort)
fi

PASS=0
FAIL=0

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

for f in "${FILES[@]}"; do
    base=$(basename "$f" .cue)
    log "--- Validating $base ---"

    # 1. cue vet
    if cue vet "$f" "${SCHEMA_DIR}/node.cue"; then
        log "  cue vet: PASS"
    else
        log "  cue vet: FAIL"
        ((FAIL++)) || true
        continue
    fi

    # 2. Export to JSON
    if cue export "$f" "${SCHEMA_DIR}/node.cue" --out json > "${OUTPUT_DIR}/${base}.json"; then
        log "  export JSON: PASS → ${OUTPUT_DIR}/${base}.json"
    else
        log "  export JSON: FAIL"
        ((FAIL++)) || true
        continue
    fi

    # 3. Export to YAML
    if cue export "$f" "${SCHEMA_DIR}/node.cue" --out yaml > "${OUTPUT_DIR}/${base}.yaml"; then
        log "  export YAML: PASS → ${OUTPUT_DIR}/${base}.yaml"
    else
        log "  export YAML: FAIL"
        ((FAIL++)) || true
        continue
    fi

    # 4. Diff against hand-edited compose file (best-effort)
    # Map example files to their source compose files
    compose_file=""
    case "$base" in
        apothem_gp5_pbss_168)
            compose_file="/root/xdc-node-setup/docker/docker-compose.gp5-apothem.yml"
            ;;
        apothem_v268_168)
            compose_file="/root/xdc-node-setup/docker/apothem/v268.yml"
            ;;
        mainnet_gp5_pbss_125)
            compose_file="/root/xdc-node-setup/docker/docker-compose.gp5-standalone.yml"
            ;;
    esac

    if [[ -n "$compose_file" && -f "$compose_file" ]]; then
        # Extract the compose service section from exported YAML for rough comparison
        # We compare the exported node.composeService block against the original
        log "  diff: comparing against $compose_file"
        if diff -u "$compose_file" "${OUTPUT_DIR}/${base}.yaml" > "${OUTPUT_DIR}/${base}.diff" 2>/dev/null; then
            log "  diff: IDENTICAL"
        else
            log "  diff: DIFFERS (see ${OUTPUT_DIR}/${base}.diff)"
        fi
    else
        log "  diff: SKIP (no reference compose file)"
    fi

    ((PASS++)) || true
done

log "========================================"
log "RESULTS: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    exit 1
else
    exit 0
fi
