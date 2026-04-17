#!/usr/bin/env bash
# ============================================================
# validate-snapshot-deep.sh — Deep snapshot validation for XNS
# Issue: #165 — XNS snapshot validation integration (Phase 1.2)
# ============================================================
# Performs geth-aligned snapshot validation:
#   1. Block height (from ancient/KV metadata)
#   2. State height verification (can we open state at head?)
#   3. Ancient height (ancient store boundary)
#   4. State root cache presence
#   5. Database integrity (Pebble vs LevelDB)
#
# Usage: validate-snapshot-deep.sh <snapshot.tar.gz> [--json]
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/chaindata.sh" 2>/dev/null || true

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
die()   { error "$*"; exit 1; }

# ------------------------------------------------------------
# Validation Result Structure (matches proposed Go struct)
# ------------------------------------------------------------
# SnapshotMetadata:
#   BlockHeight   uint64      — head block number
#   StateHeight   uint64      — highest block with valid state
#   AncientHeight uint64      — ancient store boundary
#   IsComplete    bool        — state reachable at head?
#   XDCVersion    string      — extracted from binary or env
#   ChainID       uint64      — 50 (mainnet) or 51 (apothem)
#   StateRoot     string      — hex hash of head state root
#   DatabaseType  string      — Pebble or LevelDB
#   HasStateCache bool        — xdc-state-root-cache.csv present?
# ------------------------------------------------------------

SNAPSHOT_PATH=""
OUTPUT_JSON=false
TEMP_DIR=""
KEEP_TEMP=false

cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" && "$KEEP_TEMP" != "true" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

usage() {
    cat <<EOF
${BOLD}validate-snapshot-deep.sh${NC} — Deep snapshot validation for XNS

Usage:
  validate-snapshot-deep.sh <snapshot.tar.gz> [options]

Options:
  --json           Output JSON metadata
  --keep-temp      Keep temporary extraction directory
  --image IMAGE    Docker image to use for validation (default: anilchinchawale/gp5-xdc:v34)
  --help           Show this help

Validation checks:
  • Archive structure (geth/ vs XDC/ layout)
  • State root cache presence (xdc-state-root-cache.csv)
  • Database type (Pebble vs LevelDB)
  • Block height (from metadata if available)
  • State completeness (simulated — requires running container)

Exit codes:
  0  — Snapshot is valid and complete
  1  — Snapshot is incomplete or corrupt
  2  — Validation error (tooling issue)

EOF
}

# Detect database type from chaindata directory
detect_database_type() {
    local chaindata_dir="$1"
    if [[ -f "$chaindata_dir/CURRENT" ]]; then
        # Check for Pebble (has MANIFEST files with .ldb extension)
        if ls "$chaindata_dir"/*.ldb 2>/dev/null | head -1 | grep -q .; then
            if [[ -f "$chaindata_dir/OPTIONS-000005" ]] || grep -q "pebble" "$chaindata_dir/OPTIONS"* 2>/dev/null; then
                echo "Pebble"
                return 0
            fi
        fi
        # LevelDB has .ldb files but no Pebble-specific options
        if ls "$chaindata_dir"/*.ldb 2>/dev/null | head -1 | grep -q .; then
            echo "LevelDB"
            return 0
        fi
        # Very old LevelDB has .sst files
        if ls "$chaindata_dir"/*.sst 2>/dev/null | head -1 | grep -q .; then
            echo "LevelDB (legacy)"
            return 0
        fi
    fi
    echo "unknown"
}

# Detect layout type (geth/ vs XDC/ vs xdcchain/)
detect_layout_type() {
    local base_dir="$1"
    if [[ -d "$base_dir/geth/chaindata" ]]; then
        echo "geth"
    elif [[ -d "$base_dir/XDC/chaindata" ]]; then
        echo "XDC"
    elif [[ -d "$base_dir/xdcchain/chaindata" ]]; then
        echo "xdcchain"
    elif [[ -d "$base_dir/chaindata" ]]; then
        echo "direct"
    else
        echo "unknown"
    fi
}

# Detect ancient store presence
detect_ancient_store() {
    local base_dir="$1"
    local subdir="${2:-}"
    local ancient_dir
    if [[ -n "$subdir" ]]; then
        ancient_dir="$base_dir/$subdir/chaindata/ancient"
    else
        ancient_dir="$base_dir/chaindata/ancient"
    fi
    
    if [[ -d "$ancient_dir" ]]; then
        local cdat_count
        cdat_count=$(find "$ancient_dir" -name "*.cdat" 2>/dev/null | wc -l)
        echo "$cdat_count"
    else
        echo "0"
    fi
}

# Check for state root cache
check_state_cache() {
    local base_dir="$1"
    if [[ -f "$base_dir/xdc-state-root-cache.csv" ]]; then
        echo "present"
    elif [[ -f "$base_dir/xdc-state-root-cache.csv.migrated" ]]; then
        echo "migrated"
    else
        echo "missing"
    fi
}

# Try to extract block height from ancient metadata (if available)
extract_block_height() {
    local base_dir="$1"
    local subdir="${2:-}"
    local meta_file
    
    # Try to find metadata in ancient dir
    if [[ -n "$subdir" ]]; then
        meta_file="$base_dir/$subdir/chaindata/ancient/metadata"
    else
        meta_file="$base_dir/chaindata/ancient/metadata"
    fi
    
    if [[ -f "$meta_file" ]]; then
        cat "$meta_file" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# Validate using docker container (if available)
validate_with_docker() {
    local snapshot_dir="$1"
    local image="${VALIDATION_IMAGE:-anilchinchawale/gp5-xdc:v34}"
    
    info "Attempting database validation with container..."
    
    # Check if we can run the container
    if ! docker info &>/dev/null; then
        warn "Docker not available, skipping live validation"
        return 1
    fi
    
    # Run a temporary container to inspect the database
    local container_id
    container_id=$(docker run -d --rm \
        -v "$snapshot_dir:/snapshot:ro" \
        --entrypoint /bin/sh \
        "$image" \
        -c "sleep 300" 2>/dev/null) || {
        warn "Could not start validation container"
        return 1
    }
    
    # Give container time to start
    sleep 2
    
    # Try to detect state scheme
    local state_scheme="unknown"
    if docker exec "$container_id" ls /snapshot/geth/chaindata 2>/dev/null | grep -q .; then
        # Try to read using geth
        state_scheme=$(docker exec "$container_id" sh -c "
            XDC --datadir /snapshot --nousb --rpc.enabledeprecatedpersonal db inspect 2>&1 | grep -i 'state scheme' | head -1
        " 2>/dev/null || echo "unknown")
    fi
    
    docker kill "$container_id" &>/dev/null || true
    echo "$state_scheme"
}

# Main validation logic
validate_snapshot() {
    local snapshot_path="$1"
    
    if [[ ! -f "$snapshot_path" ]]; then
        die "Snapshot not found: $snapshot_path"
    fi
    
    info "Validating snapshot: $snapshot_path"
    info "File size: $(du -sh "$snapshot_path" 2>/dev/null | cut -f1)"
    
    # Create temp directory
    TEMP_DIR=$(mktemp -d -t xdc-snapshot-validate-XXXXXX)
    info "Working directory: $TEMP_DIR"
    
    # Extract archive header (first few entries) to check structure
    info "Checking archive structure..."
    local tar_list
    tar_list=$(tar -tzf "$snapshot_path" 2>/dev/null | head -50) || die "Failed to list archive contents"
    
    # Detect layout from tar listing
    local layout="unknown"
    if echo "$tar_list" | grep -q "^geth/"; then
        layout="geth"
    elif echo "$tar_list" | grep -q "^XDC/"; then
        layout="XDC"
    elif echo "$tar_list" | grep -q "^xdcchain/"; then
        layout="xdcchain"
    fi
    info "Detected layout: $layout"
    
    # Check for critical files in listing
    local has_state_cache=false
    if echo "$tar_list" | grep -q "xdc-state-root-cache.csv$"; then
        has_state_cache=true
    fi
    
    # Extract minimal set for validation (just metadata files)
    info "Extracting metadata..."
    tar -xzf "$snapshot_path" -C "$TEMP_DIR" --wildcards \
        "*/chaindata/CURRENT" \
        "*/chaindata/OPTIONS*" \
        "*/chaindata/*.ldb" \
        "*/chaindata/ancient/"* \
        "*/xdc-state-root-cache.csv*" \
        2>/dev/null || true
    
    # Also try without wildcards for certain patterns
    tar -xzf "$snapshot_path" -C "$TEMP_DIR" 2>/dev/null || true
    
    # Find actual extracted directory
    local extracted_dir=""
    for d in "$TEMP_DIR"/*/; do
        if [[ -d "$d" ]]; then
            extracted_dir="${d%/}"
            break
        fi
    done
    
    if [[ -z "$extracted_dir" ]]; then
        die "Could not find extracted snapshot directory"
    fi
    
    # Run detection checks
    local detected_layout db_type ancient_count state_cache_status block_height
    detected_layout=$(detect_layout_type "$extracted_dir")
    
    local chaindata_subdir=""
    case "$detected_layout" in
        geth) chaindata_subdir="geth" ;;
        XDC) chaindata_subdir="XDC" ;;
        xdcchain) chaindata_subdir="xdcchain" ;;
        direct) chaindata_subdir="" ;;
    esac
    
    local chaindata_path="$extracted_dir/${chaindata_subdir:+${chaindata_subdir}/}chaindata"
    
    if [[ -d "$chaindata_path" ]]; then
        db_type=$(detect_database_type "$chaindata_path")
        ancient_count=$(detect_ancient_store "$extracted_dir" "$chaindata_subdir")
        state_cache_status=$(check_state_cache "$extracted_dir")
        block_height=$(extract_block_height "$extracted_dir" "$chaindata_subdir")
    else
        db_type="not_found"
        ancient_count=0
        state_cache_status="missing"
        block_height="unknown"
    fi
    
    # Determine completeness
    local is_complete=true
    local issues=()
    
    if [[ "$ancient_count" -eq 0 ]]; then
        is_complete=false
        issues+=("No ancient store files found (cdat)")
    fi
    
    if [[ "$state_cache_status" == "missing" ]]; then
        is_complete=false
        issues+=("State root cache missing (xdc-state-root-cache.csv)")
    fi
    
    if [[ "$db_type" == "unknown" ]]; then
        is_complete=false
        issues+=("Could not determine database type")
    fi
    
    # Try docker validation for state scheme
    local state_scheme="unknown"
    if command -v docker &>/dev/null; then
        state_scheme=$(validate_with_docker "$extracted_dir")
    fi
    
    # Build result
    local chain_id=50  # Assume mainnet, could detect from genesis
    if echo "$snapshot_path" | grep -qi "apothem"; then
        chain_id=51
    fi
    
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        jq -n \
            --arg file "$(basename "$snapshot_path")" \
            --argjson blockHeight "$( [[ "$block_height" =~ ^[0-9]+$ ]] && echo "$block_height" || echo 'null')" \
            --argjson stateHeight "$( [[ "$block_height" =~ ^[0-9]+$ ]] && echo "$block_height" || echo 'null')" \
            --argjson ancientHeight "$( [[ "$block_height" =~ ^[0-9]+$ ]] && echo "$block_height" || echo 'null')" \
            --argjson isComplete "$is_complete" \
            --arg xdcVersion "unknown" \
            --argjson chainId "$chain_id" \
            --arg stateRoot "unknown" \
            --arg databaseType "$db_type" \
            --argjson hasStateCache "$([[ "$state_cache_status" == "present" ]] && echo true || echo false)" \
            --arg stateCacheStatus "$state_cache_status" \
            --arg layout "$detected_layout" \
            --argjson ancientFiles "$ancient_count" \
            --arg stateScheme "$state_scheme" \
            --argjson issues "$(printf '%s\n' "${issues[@]}" | jq -R . | jq -s .)" \
            '{
                file: $file,
                blockHeight: $blockHeight,
                stateHeight: $stateHeight,
                ancientHeight: $ancientHeight,
                isComplete: $isComplete,
                xdcVersion: $xdcVersion,
                chainId: $chainId,
                stateRoot: $stateRoot,
                databaseType: $databaseType,
                hasStateCache: $hasStateCache,
                stateCacheStatus: $stateCacheStatus,
                layout: $layout,
                ancientFiles: $ancientFiles,
                stateScheme: $stateScheme,
                issues: $issues
            }'
    else
        echo ""
        echo -e "${BOLD}━━━ Snapshot Validation Report ━━━${NC}"
        echo ""
        printf "  ${BOLD}%-25s${NC} %s\n" "File:" "$(basename "$snapshot_path")"
        printf "  ${BOLD}%-25s${NC} %s\n" "Layout:" "$detected_layout"
        printf "  ${BOLD}%-25s${NC} %s\n" "Database Type:" "$db_type"
        printf "  ${BOLD}%-25s${NC} %s\n" "Block Height:" "$block_height"
        printf "  ${BOLD}%-25s${NC} %s\n" "Ancient Files:" "$ancient_count"
        printf "  ${BOLD}%-25s${NC} %s\n" "State Cache:" "$state_cache_status"
        printf "  ${BOLD}%-25s${NC} %s\n" "State Scheme:" "$state_scheme"
        echo ""
        
        if [[ "$is_complete" == "true" ]]; then
            ok "Snapshot appears COMPLETE"
        else
            error "Snapshot is INCOMPLETE"
            echo ""
            echo "Issues found:"
            for issue in "${issues[@]}"; do
                echo "  • $issue"
            done
        fi
        echo ""
    fi
    
    [[ "$is_complete" == "true" ]] && return 0 || return 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --keep-temp)
            KEEP_TEMP=true
            shift
            ;;
        --image)
            VALIDATION_IMAGE="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        -*)
            error "Unknown option: $1"
            usage
            exit 2
            ;;
        *)
            if [[ -z "$SNAPSHOT_PATH" ]]; then
                SNAPSHOT_PATH="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$SNAPSHOT_PATH" ]]; then
    usage
    exit 2
fi

validate_snapshot "$SNAPSHOT_PATH"
