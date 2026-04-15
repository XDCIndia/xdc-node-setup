#!/usr/bin/env bash
# xdc-snapshot-helpers.sh — Snapshot utilities for XDC CLI
# Version: 1.1.0
# Auto-detects chaindata directories and provides snapshot operations

# Auto-detect chaindata directory (XDC/ vs geth/ vs xdcchain/)
find_chaindata_dir() {
    local base_dir="${1:-${XDC_DATA:-${PROJECT_DIR}/${XDC_NETWORK}/xdcchain}}"
    local min_size="${2:-10000000000}"  # Default 10GB minimum
    
    # Check XDC/ first (GP5 naming, typically larger)
    if [[ -d "$base_dir/XDC/chaindata" ]]; then
        local xdc_size=$(du -sb "$base_dir/XDC/chaindata" 2>/dev/null | cut -f1 || echo "0")
        if [[ -n "$xdc_size" && "$xdc_size" -gt "$min_size" ]]; then
            echo "XDC"
            return 0
        fi
    fi
    
    # Check geth/ (standard Geth naming)
    if [[ -d "$base_dir/geth/chaindata" ]]; then
        echo "geth"
        return 0
    fi
    
    # Fallback to xdcchain/ (XNS standard)
    if [[ -d "$base_dir/xdcchain" ]]; then
        echo "xdcchain"
        return 0
    fi
    
    # Check for chaindata directly under base_dir
    if [[ -d "$base_dir/chaindata" ]]; then
        echo ""
        return 0
    fi
    
    echo ""
    return 1
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
