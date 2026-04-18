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

# Check if a datadir uses normalized snapshot layout
# Returns: 0 if normalized, 1 otherwise
is_normalized_layout() {
    local datadir="$1"
    [[ -f "$datadir/.snapshot-layout" ]]
}

# Report snapshot layout status
show_snapshot_layout_status() {
    local datadir="$1"
    if is_normalized_layout "$datadir"; then
        log_info "Snapshot layout: normalized ($(cat "$datadir/.snapshot-layout"))"
    else
        log_info "Snapshot layout: legacy (no .snapshot-layout marker)"
    fi
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

#==============================================================================
# Snapshot Validation for XNS (Phase 1.2 - Geth Alignment)
# https://github.com/XDCIndia/xdc-node-setup/issues/165
#==============================================================================

# Validate snapshot before transfer
# Returns 0 if valid, 1 if invalid
validate_snapshot_for_transfer() {
    local datadir="${1:-${XDC_DATA:-${PROJECT_DIR}/${XDC_NETWORK}/xdcchain}}"
    local allow_incomplete="${2:-false}"
    
    log_info "Validating snapshot at: $datadir"

    # Report layout status (RC3)
    show_snapshot_layout_status "$datadir"

    local validation_script="${SCRIPT_DIR:-$(dirname "${BASH_SOURCE[0]}")}/validate-snapshot-deep.sh"
    if [[ ! -f "$validation_script" ]]; then
        log_warn "Deep validator not found at $validation_script, using basic checks"
        
        # Basic validation: check if chaindata exists and has data
        local chaindata_dir=$(find_chaindata_dir "$datadir")
        if [[ -z "$chaindata_dir" ]]; then
            log_error "No chaindata directory found"
            return 1
        fi
        
        local chaindata_path="$datadir/$chaindata_dir/chaindata"
        if [[ ! -d "$chaindata_path" ]]; then
            log_error "Chaindata not found at $chaindata_path"
            return 1
        fi
        
        # Check if chaindata has SST/LDB files
        local file_count=$(find "$chaindata_path" -type f \( -name "*.sst" -o -name "*.ldb" \) 2>/dev/null | wc -l)
        if [[ $file_count -eq 0 ]]; then
            log_error "No database files found in chaindata"
            return 1
        fi
        
        log_info "Basic validation passed ($file_count database files)"
        return 0
    fi
    
    # Run validation using the deep validator
    local report_file=$(mktemp)
    local level="standard"
    [[ "$allow_incomplete" == "true" ]] && level="quick"
    
    if ! bash "$validation_script" --"$level" --datadir "$datadir" --json --output "$report_file" >/dev/null 2>&1; then
        log_error "Snapshot validation failed!"
        if [[ -f "$report_file" ]] && command -v jq &>/dev/null; then
            jq -r '.checks | to_entries[] | select(.value.passed==false) | "  - \(.key): \(.value.detail // "failed")"' "$report_file" 2>/dev/null | while read err; do
                log_error "$err"
            done
        fi
        rm -f "$report_file"
        return 1
    fi
    
    # Parse results from JSON report
    local is_complete="false"
    local state_height=0
    local block_height=0
    
    if [[ -f "$report_file" ]] && command -v jq &>/dev/null; then
        # Check if all critical checks passed
        local failed_critical
        failed_critical=$(jq -r '.checks | to_entries[] | select(.value.passed==false and .value.severity!="warn") | .key' "$report_file" 2>/dev/null | wc -l)
        [[ "$failed_critical" -eq 0 ]] && is_complete="true"
        
        block_height=$(jq -r '.checks.blockStateConsistency.blockHeight // 0' "$report_file" 2>/dev/null || echo "0")
        state_height=$(jq -r '.checks.blockStateConsistency.stateHeight // 0' "$report_file" 2>/dev/null || echo "0")
    fi
    
    local state_gap=$((block_height - state_height))
    
    log_info "Validation results:"
    log_info "  Block height: $block_height"
    log_info "  State height: $state_height"
    log_info "  Gap: $state_gap blocks"
    log_info "  Complete: $is_complete"
    
    # Check if acceptable
    if [[ "$is_complete" != "true" ]]; then
        log_warn "Incomplete snapshot detected!"
        log_warn "  State is $state_gap blocks behind block height"
        
        if [[ "$allow_incomplete" != "true" ]]; then
            log_error "Transfer aborted. Use --allow-incomplete to override."
            rm -f "$report_file"
            return 1
        else
            log_warn "Continuing with incomplete snapshot (override enabled)"
        fi
    fi
    
    # Save report for later
    local report_dir="${XDC_STATE_DIR:-$datadir/.state}/validation-reports"
    mkdir -p "$report_dir"
    cp "$report_file" "$report_dir/pre-transfer-$(date +%Y%m%d-%H%M%S).json" 2>/dev/null || true
    
    rm -f "$report_file"
    return 0
}

# Quick validation (faster, less thorough)
quick_validate_snapshot() {
    local datadir="${1:-${XDC_DATA:-${PROJECT_DIR}/${XDC_NETWORK}/xdcchain}}"
    
    log_info "Quick validation at: $datadir"
    
    local validation_script="${SCRIPT_DIR:-$(dirname "${BASH_SOURCE[0]}")}/validate-snapshot-deep.sh"
    if [[ ! -f "$validation_script" ]]; then
        # Fallback to basic check
        local chaindata_dir=$(find_chaindata_dir "$datadir")
        if [[ -d "$datadir/$chaindata_dir/chaindata" ]]; then
            return 0
        fi
        return 1
    fi
    
    # Quick mode via deep validator
    if bash "$validation_script" --quick --datadir "$datadir" >/dev/null 2>&1; then
        log_info "Quick validation passed"
        return 0
    fi
    
    log_warn "Quick validation failed"
    return 1
}

# Get snapshot metadata without full validation
get_snapshot_metadata() {
    local datadir="${1:-${XDC_DATA:-${PROJECT_DIR}/${XDC_NETWORK}/xdcchain}}"
    
    local validation_script="${SCRIPT_DIR:-$(dirname "${BASH_SOURCE[0]}")}/validate-snapshot-deep.sh"
    if [[ ! -f "$validation_script" ]]; then
        echo "{}"
        return 0
    fi
    
    local report_file=$(mktemp)
    bash "$validation_script" --quick --datadir "$datadir" --json --output "$report_file" >/dev/null 2>&1 || true
    
    if [[ -f "$report_file" ]]; then
        cat "$report_file"
        rm -f "$report_file"
    else
        echo "{}"
    fi
}

# Display snapshot info in table format
show_snapshot_info() {
    local datadir="${1:-${XDC_DATA:-${PROJECT_DIR}/${XDC_NETWORK}/xdcchain}}"
    
    local meta=$(get_snapshot_metadata "$datadir")
    
    local block_height=$(echo "$meta" | jq -r '.blockHeight // "N/A"' 2>/dev/null || echo "N/A")
    local state_height=$(echo "$meta" | jq -r '.stateHeight // "N/A"' 2>/dev/null || echo "N/A")
    local ancient_height=$(echo "$meta" | jq -r '.ancientHeight // "N/A"' 2>/dev/null || echo "N/A")
    local is_complete=$(echo "$meta" | jq -r '.isComplete // "N/A"' 2>/dev/null || echo "N/A")
    local status=$(echo "$meta" | jq -r '.status // "N/A"' 2>/dev/null || echo "N/A")
    
    echo "========================================"
    echo "      SNAPSHOT INFORMATION"
    echo "========================================"
    printf "%-20s %s\n" "Data Directory:" "$datadir"
    printf "%-20s %s\n" "Block Height:" "$block_height"
    printf "%-20s %s\n" "State Height:" "$state_height"
    printf "%-20s %s\n" "Ancient Height:" "$ancient_height"
    printf "%-20s %s\n" "Complete:" "$is_complete"
    printf "%-20s %s\n" "Status:" "$status"
    echo "========================================"
}
