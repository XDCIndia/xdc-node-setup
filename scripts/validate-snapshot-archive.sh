#!/usr/bin/env bash
# ============================================================
# validate-snapshot-archive.sh — Validate XDC snapshot archives
# Issue: #151 — Add snapshot validation CI step
#
# Performs lightweight checks on a snapshot archive without
# fully extracting it. Ensures the archive contains readable
# chaindata, ancient store metadata, and required state files.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/chaindata.sh" 2>/dev/null || true

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
die()   { error "$*"; exit 1; }

usage() {
    cat <<EOF
${BOLD}validate-snapshot-archive.sh${NC} — Validate XDC snapshot archives

Usage:
  validate-snapshot-archive.sh [--no-size-check] <archive.tar.gz>

Checks performed:
  • Archive is readable and not empty
  • Contains chaindata/ directory (under geth/, XDC/, xdcchain/, or root)
  • Chaindata has database files (*.sst or *.ldb or CURRENT)
  • Contains ancient/ metadata or body files (for HBSS/PBSS)
  • Warns if xdc-state-root-cache.csv is missing
  • Detects multiple chaindata layouts (signals packaging error)

Options:
  --no-size-check   Skip the minimum archive size check

Exit codes:
  0 — validation passed
  1 — validation failed
EOF
}

NO_SIZE_CHECK=false

# Parse optional flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-size-check)
            NO_SIZE_CHECK=true
            shift
            ;;
        -h|--help|help)
            usage
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

validate_archive() {
    local file="$1"
    local fail=0

    info "Validating archive: $file"
    echo ""

    # Basic file checks
    if [[ ! -f "$file" ]]; then
        die "File not found: $file"
    fi

    local file_size
    file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
    if [[ "$NO_SIZE_CHECK" != "true" && "$file_size" -lt 1048576 ]]; then
        error "Archive is suspiciously small (< 1 MB)"
        fail=1
    fi

    # Determine list command
    local list_cmd=""
    case "$file" in
        *.tar.gz|*.tgz)   list_cmd="tar -tzf" ;;
        *.tar.zst|*.tzst) list_cmd="tar --zstd -tf" ;;
        *.tar.bz2)        list_cmd="tar -tjf" ;;
        *.tar)            list_cmd="tar -tf" ;;
        *) die "Unsupported archive format: $file" ;;
    esac

    if ! $list_cmd "$file" >/dev/null 2>&1; then
        die "Cannot read archive (corrupted or wrong format?)"
    fi

    local manifest
    manifest=$($list_cmd "$file" 2>/dev/null | sed 's|^\./||' | sort)

    # Detect layout
    local has_geth=false has_xdc=false has_xdcchain=false has_direct=false
    if echo "$manifest" | grep -qE '^geth/chaindata(/|$)'; then
        has_geth=true
    fi
    if echo "$manifest" | grep -qE '^XDC/chaindata(/|$)'; then
        has_xdc=true
    fi
    if echo "$manifest" | grep -qE '^xdcchain/chaindata(/|$)'; then
        has_xdcchain=true
    fi
    if echo "$manifest" | grep -qE '^(chaindata/|[^/]+/chaindata/)'; then
        # crude direct detection if no subdir prefix matched
        if [[ "$has_geth" == "false" && "$has_xdc" == "false" && "$has_xdcchain" == "false" ]]; then
            has_direct=true
        fi
    fi

    local layout_count=0
    [[ "$has_geth" == "true" ]] && ((layout_count++))
    [[ "$has_xdc" == "true" ]] && ((layout_count++))
    [[ "$has_xdcchain" == "true" ]] && ((layout_count++))
    [[ "$has_direct" == "true" ]] && ((layout_count++))

    if [[ $layout_count -eq 0 ]]; then
        error "No chaindata directory found in archive"
        info "Expected one of: geth/chaindata, XDC/chaindata, xdcchain/chaindata, or chaindata/"
        fail=1
    elif [[ $layout_count -gt 1 ]]; then
        warn "Multiple chaindata layouts detected in archive"
        [[ "$has_geth" == "true" ]] && info "  • geth/chaindata"
        [[ "$has_xdc" == "true" ]] && info "  • XDC/chaindata"
        [[ "$has_xdcchain" == "true" ]] && info "  • xdcchain/chaindata"
        warn "This may indicate a packaging error"
    fi

    # Determine effective prefix for further checks
    local prefix=""
    if [[ "$has_geth" == "true" ]]; then
        prefix="geth"
    elif [[ "$has_xdc" == "true" ]]; then
        prefix="XDC"
    elif [[ "$has_xdcchain" == "true" ]]; then
        prefix="xdcchain"
    fi

    # Check for database files
    local db_files=0
    if [[ -n "$prefix" ]]; then
        db_files=$(echo "$manifest" | grep -cE "^${prefix}/chaindata/.*\.(sst|ldb)$" || true)
    else
        db_files=$(echo "$manifest" | grep -cE "^chaindata/.*\.(sst|ldb)$" || true)
    fi

    if [[ "$db_files" -eq 0 ]]; then
        error "No database files (*.sst / *.ldb) found in chaindata"
        fail=1
    else
        ok "Found $db_files database files"
    fi

    # Check for CURRENT marker
    local has_current=false
    if [[ -n "$prefix" ]]; then
        echo "$manifest" | grep -qE "^${prefix}/chaindata/CURRENT$" && has_current=true
    else
        echo "$manifest" | grep -qE "^chaindata/CURRENT$" && has_current=true
    fi

    if [[ "$has_current" == "true" ]]; then
        ok "Database CURRENT marker present"
    else
        warn "Missing CURRENT marker file"
    fi

    # Check ancient store presence
    local ancient_files=0
    if [[ -n "$prefix" ]]; then
        ancient_files=$(echo "$manifest" | grep -cE "^${prefix}/chaindata/ancient/" || true)
    else
        ancient_files=$(echo "$manifest" | grep -cE "^chaindata/ancient/" || true)
    fi

    if [[ "$ancient_files" -gt 0 ]]; then
        ok "Ancient store present ($ancient_files files)"
    else
        warn "No ancient store found in archive"
    fi

    # Check state root cache
    local has_state_cache=false
    echo "$manifest" | grep -qE "xdc-state-root-cache\.csv$" && has_state_cache=true

    if [[ "$has_state_cache" == "true" ]]; then
        ok "State root cache (xdc-state-root-cache.csv) present"
    else
        warn "Missing xdc-state-root-cache.csv — snapshot may fail cold recovery"
    fi

    # Summary
    echo ""
    if [[ "$fail" -eq 0 ]]; then
        ok "Snapshot validation passed"
        return 0
    else
        error "Snapshot validation failed"
        return 1
    fi
}

# Entry point
if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

case "$1" in
    -h|--help|help) usage; exit 0 ;;
    *) validate_archive "$1" ;;
esac
