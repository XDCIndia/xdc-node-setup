#!/usr/bin/env bash
# ============================================================
# snapshot-restore.sh — Robust snapshot restore for XNS
# Issue: #151 — Highest block cold snapshot fails to restore properly
# ============================================================
# Handles:
#   • Datadir layout translation (XDC/ ↔ geth/ ↔ xdcchain/)
#   • State root cache placement (xdc-state-root-cache.csv)
#   • State scheme compatibility (--state.scheme detection)
#   • Database type detection (Pebble vs LevelDB)
#   • Pre-flight validation before overwriting chaindata
#
# Usage: snapshot-restore.sh <snapshot.tar.gz> [datadir]
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

SNAPSHOT_PATH=""
DATADIR="${XDC_DATADIR:-/root/xdcchain}"
FORCE=false
SKIP_VALIDATE=false
TEMP_DIR=""

cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

usage() {
    cat <<EOF
${BOLD}snapshot-restore.sh${NC} — Restore XDC snapshot with layout translation

Usage:
  snapshot-restore.sh <snapshot.tar.gz> [options]

Options:
  --datadir PATH   Target data directory (default: $DATADIR)
  --force          Skip confirmation prompt
  --skip-validate  Skip pre-flight snapshot validation
  --help           Show this help

Examples:
  snapshot-restore.sh /backup/xdc-mainnet-56828700.tar.gz
  snapshot-restore.sh /backup/xdc-apothem.tar.gz --datadir /mnt/data/xdcchain --force

EOF
}

# Detect snapshot layout from tar listing
detect_snapshot_layout() {
    local snapshot="$1"
    tar -tzf "$snapshot" 2>/dev/null | head -20 | while read -r line; do
        case "$line" in
            geth/*) echo "geth"; return ;;
            XDC/*) echo "XDC"; return ;;
            xdcchain/*) echo "xdcchain"; return ;;
            chaindata/*) echo "direct"; return ;;
        esac
    done
    echo "unknown"
}

# Detect target layout from existing datadir or default
detect_target_layout() {
    local datadir="$1"
    if [[ -d "$datadir/geth/chaindata" ]]; then
        echo "geth"
    elif [[ -d "$datadir/XDC/chaindata" ]]; then
        echo "XDC"
    elif [[ -d "$datadir/xdcchain/chaindata" ]]; then
        echo "xdcchain"
    elif [[ -d "$datadir/chaindata" ]]; then
        echo "direct"
    else
        echo "geth"  # Default for new installations
    fi
}

# Detect database type
detect_db_type() {
    local chaindata_dir="$1"
    if [[ ! -d "$chaindata_dir" ]]; then
        echo "unknown"
        return
    fi
    if ls "$chaindata_dir"/*.ldb 2>/dev/null | head -1 | grep -q .; then
        if [[ -f "$chaindata_dir/OPTIONS" ]] || ls "$chaindata_dir"/OPTIONS* 2>/dev/null | head -1 | grep -q .; then
            echo "Pebble"
        else
            echo "LevelDB"
        fi
    elif ls "$chaindata_dir"/*.sst 2>/dev/null | head -1 | grep -q .; then
        echo "LevelDB (legacy)"
    else
        echo "unknown"
    fi
}

# Detect state scheme from snapshot chaindata
detect_snapshot_scheme() {
    local snapshot_dir="$1"
    local layout="$2"
    local subdir=""
    case "$layout" in
        geth|XDC|xdcchain) subdir="$layout" ;;
        direct) subdir="" ;;
        *) subdir="" ;;
    esac
    
    local chaindata_path
    if [[ -n "$subdir" ]]; then
        chaindata_path="$snapshot_dir/$subdir/chaindata"
    else
        chaindata_path="$snapshot_dir/chaindata"
    fi
    
    # Check triedb/ dir (path scheme)
    if [[ -n "$subdir" && -d "$snapshot_dir/$subdir/triedb" ]]; then
        echo "path"
        return
    fi
    
    # Check Pebble OPTIONS (usually path)
    if [[ -f "$chaindata_path/OPTIONS" ]]; then
        echo "path"
        return
    fi
    
    # LevelDB without triedb is likely hash
    if ls "$chaindata_path"/*.ldb 2>/dev/null | head -1 | grep -q .; then
        echo "hash"
        return
    fi
    
    echo "unknown"
}

# Main restore logic
restore_snapshot() {
    local snapshot_path="$1"
    
    if [[ ! -f "$snapshot_path" ]]; then
        die "Snapshot not found: $snapshot_path"
    fi
    
    info "Snapshot: $snapshot_path"
    info "Target datadir: $DATADIR"
    
    # Pre-flight validation
    if [[ "$SKIP_VALIDATE" != "true" ]]; then
        info "Running pre-flight validation..."
        if ! "$SCRIPT_DIR/validate-snapshot-deep.sh" --json "$snapshot_path" >/dev/null 2>&1; then
            warn "Snapshot validation reported issues."
            if [[ "$FORCE" != "true" ]]; then
                echo -n "Continue anyway? [y/N]: "
                read -r confirm
                [[ "$confirm" =~ ^[Yy]$ ]] || die "Restore aborted"
            fi
        else
            ok "Pre-flight validation passed"
        fi
    fi
    
    # Detect snapshot layout
    local snapshot_layout
    snapshot_layout=$(detect_snapshot_layout "$snapshot_path")
    info "Snapshot layout: $snapshot_layout"
    
    # Detect target layout
    local target_layout
    target_layout=$(detect_target_layout "$DATADIR")
    info "Target layout: $target_layout"
    
    # Create temp extraction dir
    TEMP_DIR=$(mktemp -d -t xdc-snapshot-restore-XXXXXX)
    info "Extracting snapshot to temp dir..."
    tar -xzf "$snapshot_path" -C "$TEMP_DIR" || die "Failed to extract snapshot"
    
    # Find actual extracted directory
    local extracted_dir=""
    for d in "$TEMP_DIR"/*/; do
        if [[ -d "$d" ]]; then
            extracted_dir="${d%/}"
            break
        fi
    done
    
    if [[ -z "$extracted_dir" ]]; then
        # Maybe snapshot contents are at top level
        extracted_dir="$TEMP_DIR"
    fi
    
    # Detect database type and state scheme from snapshot
    local snapshot_chaindata_path
    case "$snapshot_layout" in
        geth|XDC|xdcchain) snapshot_chaindata_path="$extracted_dir/$snapshot_layout/chaindata" ;;
        direct) snapshot_chaindata_path="$extracted_dir/chaindata" ;;
        *) snapshot_chaindata_path="" ;;
    esac
    
    local db_type="unknown"
    local state_scheme="unknown"
    if [[ -n "$snapshot_chaindata_path" && -d "$snapshot_chaindata_path" ]]; then
        db_type=$(detect_db_type "$snapshot_chaindata_path")
        state_scheme=$(detect_snapshot_scheme "$extracted_dir" "$snapshot_layout")
    fi
    
    info "Snapshot DB type: $db_type"
    info "Snapshot state scheme: $state_scheme"
    
    # Handle state root cache
    local cache_src=""
    local cache_target="$DATADIR/xdc-state-root-cache.csv"
    if [[ -f "$extracted_dir/xdc-state-root-cache.csv" ]]; then
        cache_src="$extracted_dir/xdc-state-root-cache.csv"
    elif [[ -f "$extracted_dir/xdc-state-root-cache.csv.migrated" ]]; then
        cache_src="$extracted_dir/xdc-state-root-cache.csv.migrated"
        warn "State root cache is in .migrated format; copying anyway"
    fi
    
    # Confirmation
    if [[ "$FORCE" != "true" ]]; then
        echo ""
        echo -e "${BOLD}This will overwrite chaindata in:${NC} $DATADIR"
        echo -n "Proceed? [y/N]: "
        read -r confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || die "Restore aborted"
    fi
    
    # Stop any running container
    local container=""
    container=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "xdc-(node|gp5|geth)" | head -1 || true)
    if [[ -n "$container" ]]; then
        info "Stopping running container: $container"
        docker stop "$container" || true
    fi
    
    # Backup existing chaindata
    if [[ -d "$DATADIR" && -n "$(ls -A "$DATADIR" 2>/dev/null)" ]]; then
        local backup_dir="$DATADIR.pre-restore.$(date +%Y%m%d-%H%M%S)"
        info "Backing up existing datadir to $backup_dir"
        mv "$DATADIR" "$backup_dir" || die "Failed to backup existing datadir"
        mkdir -p "$DATADIR"
    fi
    
    # Restore with layout translation if needed
    if [[ "$snapshot_layout" == "$target_layout" ]]; then
        info "Layouts match, copying directly..."
        cp -a "$extracted_dir"/* "$DATADIR/" || die "Failed to copy snapshot"
    else
        info "Translating layout from $snapshot_layout to $target_layout..."
        
        # Create target structure
        mkdir -p "$DATADIR"
        
        # Copy non-chaindata files directly
        for item in "$extracted_dir"/*; do
            local basename_item
            basename_item=$(basename "$item")
            case "$basename_item" in
                geth|XDC|xdcchain|chaindata)
                    # These will be handled separately
                    ;;
                *)
                    cp -a "$item" "$DATADIR/" || true
                    ;;
            esac
        done
        
        # Map chaindata to target layout
        local snapshot_subdir=""
        case "$snapshot_layout" in
            geth|XDC|xdcchain) snapshot_subdir="$snapshot_layout" ;;
            direct) snapshot_subdir="" ;;
        esac
        
        local target_subdir=""
        case "$target_layout" in
            geth|XDC|xdcchain) target_subdir="$target_layout" ;;
            direct) target_subdir="" ;;
        esac
        
        if [[ -n "$snapshot_subdir" ]]; then
            if [[ -n "$target_subdir" ]]; then
                mkdir -p "$DATADIR/$target_subdir"
                cp -a "$extracted_dir/$snapshot_subdir"/* "$DATADIR/$target_subdir/" || die "Failed to translate chaindata"
            else
                cp -a "$extracted_dir/$snapshot_subdir"/* "$DATADIR/" || die "Failed to translate chaindata"
            fi
        else
            if [[ -n "$target_subdir" ]]; then
                mkdir -p "$DATADIR/$target_subdir"
                cp -a "$extracted_dir"/chaindata "$extracted_dir"/ancient "$extracted_dir"/nodekey* "$DATADIR/$target_subdir/" 2>/dev/null || true
                cp -a "$extracted_dir"/keystore "$DATADIR/" 2>/dev/null || true
            else
                cp -a "$extracted_dir"/* "$DATADIR/" || die "Failed to copy snapshot"
            fi
        fi
        
        ok "Layout translation complete"
    fi
    
    # Place state root cache
    if [[ -n "$cache_src" ]]; then
        if [[ -f "$cache_src" ]]; then
            cp -a "$cache_src" "$cache_target"
            ok "State root cache restored"
        fi
    else
        warn "No state root cache found in snapshot"
    fi
    
    # Write scheme marker for future auto-detection
    if [[ "$state_scheme" != "unknown" ]]; then
        local marker_dir=""
        case "$target_layout" in
            geth|XDC|xdcchain) marker_dir="$DATADIR/$target_layout/chaindata" ;;
            direct) marker_dir="$DATADIR/chaindata" ;;
        esac
        if [[ -n "$marker_dir" && -d "$marker_dir" ]]; then
            echo "$state_scheme" > "$marker_dir/scheme.txt"
            ok "Wrote scheme marker: $state_scheme"
        fi
    fi
    
    # Write .env hint for docker compose
    if [[ "$state_scheme" != "unknown" ]]; then
        local env_file="$(dirname "$DATADIR")/.env"
        if [[ -f "$env_file" ]]; then
            if grep -q "^STATE_SCHEME=" "$env_file"; then
                sed -i.bak "s/^STATE_SCHEME=.*/STATE_SCHEME=$state_scheme/" "$env_file" && rm -f "$env_file.bak"
            else
                echo "STATE_SCHEME=$state_scheme" >> "$env_file"
            fi
            info "Updated $env_file: STATE_SCHEME=$state_scheme"
        fi
    fi
    
    # Summary
    echo ""
    ok "Snapshot restore complete!"
    info "Datadir: $DATADIR"
    info "State scheme: $state_scheme"
    info "Next steps:"
    info "  1. Ensure your docker-compose.yml passes STATE_SCHEME=$state_scheme"
    info "  2. Start container: docker compose up -d"
    info "  3. Monitor logs: docker logs -f <container>"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --datadir)
            DATADIR="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --skip-validate)
            SKIP_VALIDATE=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        -*)
            die "Unknown option: $1"
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
    die "Snapshot path required"
fi

restore_snapshot "$SNAPSHOT_PATH"
