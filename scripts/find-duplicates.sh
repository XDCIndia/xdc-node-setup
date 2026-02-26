#!/bin/bash
#===============================================================================
# Duplicate Function Finder and Consolidator for XDC-Node-Setup
# This script identifies duplicate shell functions across the codebase
# and generates a consolidation report
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORT_FILE="${PROJECT_ROOT}/reports/duplicate-functions-report.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1" >&2; }

# Function to extract function names from a shell script
extract_functions() {
    local file="$1"
    grep -E '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)[[:space:]]*\{' "$file" 2>/dev/null | \
        sed 's/[[:space:]]*(.*$//' | \
        sed 's/^[[:space:]]*//' | \
        sort -u
}

# Function to count lines in a function
function_lines() {
    local file="$1"
    local func="$2"
    awk -v func="$func" '
        /^[[:space:]]*'"$func"'[[:space:]]*\(\)/ {start=1; count=0}
        start {count++}
        start && /^[[:space:]]*\}/ && count > 1 {print count; exit}
    ' "$file"
}

# Main analysis
main() {
    info "Scanning for duplicate shell functions..."
    
    mkdir -p "$(dirname "$REPORT_FILE")"
    
    # Find all shell scripts
    local scripts=()
    while IFS= read -r -d '' file; do
        scripts+=("$file")
    done < <(find "${PROJECT_ROOT}/scripts" -name "*.sh" -type f -print0 2>/dev/null)
    
    info "Found ${#scripts[@]} shell scripts"
    
    # Build function map
    declare -A func_map
    declare -A func_lines
    
    for script in "${scripts[@]}"; do
        # Skip lib files (they're already consolidated)
        if [[ "$script" == *"/lib/"* ]]; then
            continue
        fi
        
        local funcs
        funcs=$(extract_functions "$script" || true)
        
        for func in $funcs; do
            # Skip common patterns that aren't duplicates
            case "$func" in
                main|usage|help|die|cleanup)
                    continue
                    ;;
            esac
            
            if [[ -n "${func_map[$func]:-}" ]]; then
                func_map[$func]="${func_map[$func]},$script"
                ((func_lines[$func]++)) || true
            else
                func_map[$func]="$script"
                func_lines[$func]=1
            fi
        done
    done
    
    # Generate report
    {
        echo "# Duplicate Shell Functions Report"
        echo "Generated: $(date -Iseconds)"
        echo ""
        echo "## Summary"
        echo ""
        
        local duplicates=0
        for func in "${!func_lines[@]}"; do
            if [[ ${func_lines[$func]} -gt 1 ]]; then
                ((duplicates++)) || true
            fi
        done
        
        echo "- Total duplicate functions: $duplicates"
        echo "- Scripts scanned: ${#scripts[@]}"
        echo ""
        echo "## Duplicate Functions to Consolidate"
        echo ""
        echo "| Function | Occurrences | Files | Action |"
        echo "|----------|-------------|-------|--------|"
        
        for func in "${!func_lines[@]}"; do
            if [[ ${func_lines[$func]} -gt 1 ]]; then
                local files="${func_map[$func]}"
                local count=${func_lines[$func]}
                echo "| \`$func\` | $count | ${files//,/\|} | Move to lib/common.sh |"
            fi
        done
        
        echo ""
        echo "## Already Consolidated (in lib/)"
        echo ""
        echo "These functions are already in shared libraries:"
        echo ""
        
        for lib in "${PROJECT_ROOT}/scripts/lib/"*.sh; do
            if [[ -f "$lib" ]]; then
                echo "### $(basename "$lib")"
                echo '```'
                extract_functions "$lib" || true
                echo '```'
                echo ""
            fi
        done
        
        echo ""
        echo "## Recommendations"
        echo ""
        echo "1. Move duplicate logging functions to \`scripts/lib/logging.sh\`"
        echo "2. Move duplicate RPC helpers to \`scripts/lib/common.sh\`"
        echo "3. Move duplicate validation functions to \`scripts/lib/validation.sh\`"
        echo "4. Update scripts to source the appropriate library files"
        echo "5. Use the existing library sourcing pattern:"
        echo '   ```bash'
        echo '   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"'
        echo '   source "${SCRIPT_DIR}/lib/common.sh"'
        echo '   ```'
        echo ""
        echo "## Next Steps"
        echo ""
        echo "1. Review this report"
        echo "2. Prioritize functions with 3+ occurrences"
        echo "3. Create migration plan for each function"
        echo "4. Test scripts after consolidation"
        echo "5. Update documentation"
        
    } > "$REPORT_FILE"
    
    log "Report generated: $REPORT_FILE"
    
    # Print summary
    echo ""
    warn "Found $duplicates duplicate functions across ${#scripts[@]} scripts"
    echo ""
    echo "Top duplicates:"
    for func in "${!func_lines[@]}"; do
        if [[ ${func_lines[$func]} -gt 2 ]]; then
            echo "  - $func: ${func_lines[$func]} occurrences"
        fi
    done
}

main "$@"
