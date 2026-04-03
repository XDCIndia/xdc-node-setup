#!/usr/bin/env bash
# ============================================================
# volume-check.sh — Persistent Volume Strategy
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/90
# ============================================================
# Verifies data dirs exist BEFORE docker start.
# Docker creates DIRECTORIES for bind mounts that don't exist —
# this causes silent failures when a FILE mount (e.g. static-nodes.json)
# is expected but a dir gets created instead.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load common lib if available
[[ -f "${SCRIPT_DIR}/lib/common.sh" ]] && source "${SCRIPT_DIR}/lib/common.sh"

# --- Configuration ---
DATA_ROOT="${DATA_ROOT:-${REPO_ROOT}/data}"
NETWORK="${NETWORK:-mainnet}"
CLIENTS=(gp5 erigon nethermind reth v268)
STATIC_NODES_SRC="${REPO_ROOT}/configs/mainnet/static-nodes.json"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [volume-check] $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" >&2; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; }
die() { error "$*"; exit 1; }

# ---- Helper: check if a path is DIR when it should be FILE ----
check_file_not_dir() {
    local path="$1"
    local label="$2"
    if [[ -d "${path}" ]]; then
        error "${label}: '${path}' is a DIRECTORY but should be a FILE!"
        error "Docker created a directory here instead of using a file mount."
        error "Fix: rm -rf '${path}' && cp <source> '${path}'"
        return 1
    fi
    return 0
}

# ---- Validate static-nodes.json is a FILE not DIR ----
validate_static_nodes() {
    local client="$1"
    local data_dir="$2"
    local static_nodes="${data_dir}/XDC/static-nodes.json"

    log "Checking static-nodes.json for ${client}..."

    # Check if parent XDC dir exists as file (shouldn't happen but guard it)
    if [[ -f "${data_dir}/XDC" ]]; then
        die "${client}: data_dir/XDC is a FILE, should be a directory"
    fi

    if [[ -e "${static_nodes}" ]]; then
        if check_file_not_dir "${static_nodes}" "${client}/static-nodes.json"; then
            log "  ✓ static-nodes.json is a valid file"
        else
            return 1
        fi
    else
        log "  → static-nodes.json not found, will pre-create from source"
        if [[ -f "${STATIC_NODES_SRC}" ]]; then
            mkdir -p "${data_dir}/XDC"
            cp "${STATIC_NODES_SRC}" "${static_nodes}"
            log "  ✓ Copied static-nodes.json to ${static_nodes}"
        else
            warn "  Source ${STATIC_NODES_SRC} not found — skipping"
        fi
    fi
}

# ---- Pre-create all mount targets for a client ----
precreate_mounts() {
    local client="$1"
    local data_dir="${DATA_ROOT}/${client}/${NETWORK}"

    log "Pre-creating mount targets for ${client}..."

    # Directories that should be directories
    local dirs=(
        "${data_dir}"
        "${data_dir}/XDC"
        "${data_dir}/keystore"
        "${data_dir}/logs"
    )

    for dir in "${dirs[@]}"; do
        if [[ -f "${dir}" ]]; then
            die "Path '${dir}' is a FILE but should be a DIRECTORY. Remove it first."
        fi
        if [[ ! -d "${dir}" ]]; then
            mkdir -p "${dir}"
            log "  ✓ Created dir: ${dir}"
        else
            log "  ✓ Exists:      ${dir}"
        fi
    done

    # Files that should be files (not dirs)
    validate_static_nodes "${client}" "${data_dir}"

    # Erigon-specific dirs
    if [[ "${client}" == "erigon" ]]; then
        local erigon_dirs=(
            "${data_dir}/erigon"
            "${data_dir}/erigon/chaindata"
        )
        for dir in "${erigon_dirs[@]}"; do
            if [[ ! -d "${dir}" ]]; then
                mkdir -p "${dir}"
                log "  ✓ Created erigon dir: ${dir}"
            fi
        done
    fi

    # Nethermind-specific
    if [[ "${client}" == "nethermind" ]]; then
        local nm_dirs=(
            "${data_dir}/nethermind"
            "${data_dir}/nethermind/chaindata"
            "${data_dir}/nethermind/logs"
        )
        for dir in "${nm_dirs[@]}"; do
            if [[ ! -d "${dir}" ]]; then
                mkdir -p "${dir}"
                log "  ✓ Created nethermind dir: ${dir}"
            fi
        done
    fi
}

# ---- Verify existing mounts haven't been clobbered by docker ----
verify_mounts() {
    local client="$1"
    local data_dir="${DATA_ROOT}/${client}/${NETWORK}"
    local ok=true

    log "Verifying mounts for ${client}..."

    # These must be directories
    local must_be_dirs=("${data_dir}" "${data_dir}/XDC")
    for d in "${must_be_dirs[@]}"; do
        if [[ ! -d "${d}" ]]; then
            warn "  Missing directory: ${d}"
            ok=false
        fi
    done

    # static-nodes.json must be a file
    local snj="${data_dir}/XDC/static-nodes.json"
    if [[ -e "${snj}" ]]; then
        if ! check_file_not_dir "${snj}" "static-nodes.json"; then
            ok=false
        fi
    fi

    if [[ "${ok}" == "true" ]]; then
        log "  ✓ ${client}: all mount targets valid"
    else
        error "  ✗ ${client}: mount issues detected (see above)"
        return 1
    fi
}

# ---- Main ----
usage() {
    echo "Usage: $0 [--clients <c1,c2,...>] [--network <mainnet|apothem>] [--verify-only] [--precreate]"
    echo ""
    echo "  --clients       Comma-separated client list (default: all)"
    echo "  --network       Network (default: mainnet)"
    echo "  --verify-only   Only verify, do not create"
    echo "  --precreate     Pre-create all mount targets (default)"
    exit 1
}

VERIFY_ONLY=false
PRECREATE=true
SELECTED_CLIENTS=("${CLIENTS[@]}")

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clients)
            IFS=',' read -ra SELECTED_CLIENTS <<< "$2"
            shift 2
            ;;
        --network)
            NETWORK="$2"
            shift 2
            ;;
        --verify-only)
            VERIFY_ONLY=true
            PRECREATE=false
            shift
            ;;
        --precreate)
            PRECREATE=true
            shift
            ;;
        -h|--help) usage ;;
        *) warn "Unknown option: $1"; usage ;;
    esac
done

log "=== XDC Volume Check ==="
log "DATA_ROOT: ${DATA_ROOT}"
log "NETWORK:   ${NETWORK}"
log "CLIENTS:   ${SELECTED_CLIENTS[*]}"

FAILED=0
for client in "${SELECTED_CLIENTS[@]}"; do
    echo ""
    if [[ "${PRECREATE}" == "true" ]]; then
        precreate_mounts "${client}" || FAILED=$((FAILED + 1))
    fi
    verify_mounts "${client}" || FAILED=$((FAILED + 1))
done

echo ""
if [[ "${FAILED}" -eq 0 ]]; then
    log "=== All volume checks PASSED ==="
else
    error "=== ${FAILED} volume check(s) FAILED ==="
    exit 1
fi
