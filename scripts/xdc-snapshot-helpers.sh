#!/usr/bin/env bash
# xdc-snapshot-helpers.sh — Snapshot utilities for XDC CLI
# Version: 1.2.0
# Auto-detects chaindata directories and provides snapshot operations

# Auto-detect chaindata directory (XDC/ vs geth/ vs xdcchain/ vs direct)
# Priority: geth/ > XDC/ > xdcchain/ > direct chaindata/ > create geth/
find_chaindata_dir() {
    local base_dir="${1:-${XDC_DATA:-${PROJECT_DIR}/${XDC_NETWORK}/xdcchain}}"
    local min_size="${2:-10000000000}"  # Default 10GB minimum
    
    # Priority 1: Check geth/ (standard Geth 1.17+ naming)
    if [[ -d "$base_dir/geth/chaindata" ]]; then
        local geth_size=$(du -sb "$base_dir/geth/chaindata" 2>/dev/null | cut -f1 || echo "0")
        if [[ -n "$geth_size" && "$geth_size" -gt "$min_size" ]]; then
            log_info "Found standard geth/ chaindata directory ($(du -sh "$base_dir/geth" 2>/dev/null | cut -f1))"
            echo "geth"
            return 0
        fi
    fi
    
    # Priority 2: Check XDC/ (GP5 legacy naming)
    if [[ -d "$base_dir/XDC/chaindata" ]]; then
        local xdc_size=$(du -sb "$base_dir/XDC/chaindata" 2>/dev/null | cut -f1 || echo "0")
        if [[ -n "$xdc_size" && "$xdc_size" -gt "$min_size" ]]; then
            log_warn "Found legacy XDC/ chaindata directory ($(du -sh "$base_dir/XDC" 2>/dev/null | cut -f1))"
            log_info "Consider migrating to geth/ standard: xdc migrate --datadir $base_dir"
            echo "XDC"
            return 0
        fi
    fi
    
    # Priority 3: Check xdcchain/ (XNS legacy naming)
    if [[ -d "$base_dir/xdcchain" ]]; then
        log_warn "Found legacy xdcchain/ directory ($(du -sh "$base_dir/xdcchain" 2>/dev/null | cut -f1))"
        log_info "Consider migrating to geth/ standard: xdc migrate --datadir $base_dir"
        echo "xdcchain"
        return 0
    fi
    
    # Priority 4: Check for chaindata directly under base_dir
    if [[ -d "$base_dir/chaindata" ]]; then
        log_info "Found direct chaindata/ directory"
        echo ""
        return 0
    fi
    
    # Priority 5: Default to geth/ for new installations
    log_info "No existing chaindata found, defaulting to geth/ standard"
    mkdir -p "$base_dir/geth"
    echo "geth"
    return 0
}

# Get compression command based on type
get_compress_cmd() {
    local compress_type="$1"
    case "$compress_type" in
        pigz)
            if command -v pigz &>/dev/null; then
                echo "pigz -c"
            else
                echo "gzip -c"
            fi
            ;;
        zstd)
            if command -v zstd &>/dev/null; then
                echo "zstd -c"
            else
                echo "gzip -c"
            fi
            ;;
        gzip|*)
            echo "gzip -c"
            ;;
    esac
}

# Get decompression command based on file extension
get_decompress_cmd() {
    local file="$1"
    if [[ "$file" == *.zst ]] || [[ "$file" == *.zstd ]]; then
        if command -v zstd &>/dev/null; then
            echo "zstd -dc"
        else
            echo ""
        fi
    elif [[ "$file" == *.bz2 ]]; then
        echo "bzip2 -dc"
    else
        echo "gzip -dc"
    fi
}

# Show state cache regeneration warning
show_state_cache_warning() {
    local RED='\033[0;31m'
    local YELLOW='\033[1;33m'
    local CYAN='\033[0;36m'
    local NC='\033[0m'
    
    echo ""
    echo -e "${YELLOW}⚠️  Important: State root cache needs regeneration${NC}"
    echo -e "   The state cache (100K LRU entries) is stored in RAM and not preserved in snapshots."
    echo -e "   To rebuild the cache:"
    echo -e "   ${CYAN}xdc restart --syncmode full${NC}"
    echo -e "   This may take 10-30 minutes depending on block height."
    echo ""
}

# Migrate legacy chaindata directories (XDC/ or xdcchain/) to standard geth/
# Usage: migrate_to_geth_dir <datadir> [--dry-run|--execute]
migrate_to_geth_dir() {
    local datadir="${1:-${XDC_DATA:-${PROJECT_DIR}/${XDC_NETWORK}/xdcchain}}"
    local mode="${2:---dry-run}"
    
    log_info "Analyzing chaindata directories in $datadir..."
    
    # Check if geth/ already exists with substantial data
    if [[ -d "$datadir/geth/chaindata" ]]; then
        local geth_size=$(du -sb "$datadir/geth" 2>/dev/null | cut -f1 || echo "0")
        if [[ "$geth_size" -gt 1000000000 ]]; then  # > 1GB
            log_info "geth/ directory already exists with data ($(du -sh "$datadir/geth" 2>/dev/null | cut -f1))"
            log_info "Checking for legacy directories to consolidate..."
        fi
    fi
    
    # Find source legacy directory
    local source_dir=""
    local source_name=""
    
    if [[ -d "$datadir/XDC/chaindata" ]]; then
        source_dir="$datadir/XDC"
        source_name="XDC"
    elif [[ -d "$datadir/xdcchain/chaindata" ]]; then
        source_dir="$datadir/xdcchain"
        source_name="xdcchain"
    elif [[ -d "$datadir/xdcchain" ]] && [[ -n "$(ls -A "$datadir/xdcchain" 2>/dev/null)" ]]; then
        source_dir="$datadir/xdcchain"
        source_name="xdcchain"
    else
        log_info "No legacy directories found - nothing to migrate"
        return 0
    fi
    
    local source_size=$(du -sh "$source_dir" 2>/dev/null | cut -f1 || echo "unknown")
    log_info "Found legacy $source_name/ directory: $source_dir ($source_size)"
    
    if [[ "$mode" == "--dry-run" ]]; then
        log_info "[DRY RUN] Would migrate: $source_dir/ → $datadir/geth/"
        log_info "[DRY RUN] Files to migrate:"
        for item in chaindata keystore nodekey jwtsecret transactions.rlp; do
            if [[ -e "$source_dir/$item" ]]; then
                log_info "  - $item"
            fi
        done
        log_info "Run with --execute to perform actual migration"
        return 0
    fi
    
    if [[ "$mode" != "--execute" ]]; then
        log_error "Usage: migrate_to_geth_dir <datadir> [--dry-run|--execute]"
        return 1
    fi
    
    # Check if geth/ already has data
    if [[ -d "$datadir/geth/chaindata" ]] && [[ -n "$(ls -A "$datadir/geth/chaindata" 2>/dev/null)" ]]; then
        log_error "geth/ directory already contains chaindata! Cannot migrate."
        log_error "Backup and remove geth/ first if you want to replace it."
        return 1
    fi
    
    # Create backup of source
    local backup_dir="${source_dir}-backup-$(date +%Y%m%d-%H%M%S)"
    log_info "Creating backup: $backup_dir"
    cp -r "$source_dir" "$backup_dir" || {
        log_error "Failed to create backup"
        return 1
    }
    
    # Create geth/ directory
    log_info "Creating geth/ directory..."
    mkdir -p "$datadir/geth"
    
    # Migrate each component
    local migrated_items=()
    for item in chaindata keystore nodekey jwtsecret transactions.rlp blobpool nodes; do
        if [[ -e "$source_dir/$item" ]]; then
            log_info "Migrating $item..."
            mv "$source_dir/$item" "$datadir/geth/" && migrated_items+=("$item") || {
                log_error "Failed to migrate $item"
                log_error "Restoring from backup..."
                rm -rf "$datadir/geth"
                mv "$backup_dir" "$source_dir"
                return 1
            }
        fi
    done
    
    # Migrate files
    for file in LOCK; do
        if [[ -f "$source_dir/$file" ]]; then
            mv "$source_dir/$file" "$datadir/geth/" 2>/dev/null || true
        fi
    done
    
    # Create migration marker
    echo "Migrated from $source_name/ on $(date -Iseconds)" > "$datadir/geth/.migration_marker"
    echo "Source backup: $backup_dir" >> "$datadir/geth/.migration_marker"
    
    log_success "Migration complete!"
    log_info "Migrated items: ${migrated_items[*]}"
    log_info "Source backup: $backup_dir"
    log_info "New location: $datadir/geth/"
    log_warn "You can remove the backup after verifying the node works: rm -rf $backup_dir"
    
    return 0
}

# Show migration status for a datadir
show_migration_status() {
    local datadir="${1:-${XDC_DATA:-${PROJECT_DIR}/${XDC_NETWORK}/xdcchain}}"
    
    echo "=== Chaindata Directory Status ==="
    echo "Base directory: $datadir"
    echo ""
    
    for dir in geth XDC xdcchain; do
        if [[ -d "$datadir/$dir" ]]; then
            local size=$(du -sh "$datadir/$dir" 2>/dev/null | cut -f1 || echo "unknown")
            local chaindata_size=""
            if [[ -d "$datadir/$dir/chaindata" ]]; then
                chaindata_size=$(du -sh "$datadir/$dir/chaindata" 2>/dev/null | cut -f1 || echo "unknown")
                echo "  $dir/: $size (chaindata: $chaindata_size)"
            else
                echo "  $dir/: $size (no chaindata)"
            fi
            
            # Check for migration marker
            if [[ -f "$datadir/$dir/.migration_marker" ]]; then
                echo "    → Migrated: $(cat "$datadir/$dir/.migration_marker" | head -1)"
            fi
        fi
    done
    
    echo ""
    local current=$(find_chaindata_dir "$datadir" 0)
    echo "Active directory: $current/"
}
