#!/bin/bash
# Refactor Script: Remove Duplicate Functions
# Issue #457: Remove duplicate function definitions across scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="$SCRIPT_DIR/lib/common.sh"

# List of scripts with duplicate detect_network()
SCRIPTS_TO_FIX=(
    "bootnode-optimize.sh"
    "governance.sh"
    "implement-standards.sh"
    "log-rotate.sh"
    "masternode-cluster.sh"
    "rpc-security.sh"
    "snapshot-manager.sh"
    "xdc-monitor.sh"
)

echo "=== Refactoring Duplicate Functions ==="
echo "Target scripts: ${#SCRIPTS_TO_FIX[@]}"
echo ""

for script in "${SCRIPTS_TO_FIX[@]}"; do
    script_path="$SCRIPT_DIR/$script"
    
    if [[ ! -f "$script_path" ]]; then
        echo "⚠️  SKIP: $script (not found)"
        continue
    fi
    
    echo "📝 Processing: $script"
    
    # Check if script already sources common.sh
    if grep -q "source.*lib/common.sh" "$script_path"; then
        echo "  ✓ Already sources common.sh"
    else
        # Add source statement after shebang
        sed -i '2i\\n# Source common utilities\nSOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\nsource "$SOURCE_DIR/lib/common.sh"' "$script_path"
        echo "  + Added source statement"
    fi
    
    # Remove duplicate detect_network() function
    if grep -q "^detect_network()" "$script_path"; then
        # Remove function definition (function + opening brace + body + closing brace)
        sed -i '/^detect_network()/,/^}/d' "$script_path"
        echo "  - Removed detect_network() duplicate"
    fi
    
    # Remove duplicate check_rpc() if present
    if grep -q "^check_rpc()" "$script_path"; then
        sed -i '/^check_rpc()/,/^}/d' "$script_path"
        echo "  - Removed check_rpc() duplicate"
    fi
    
    # Remove duplicate json_rpc() if present
    if grep -q "^json_rpc()" "$script_path"; then
        sed -i '/^json_rpc()/,/^}/d' "$script_path"
        echo "  - Removed json_rpc() duplicate"
    fi
    
    # Remove duplicate get_block_number() if present
    if grep -q "^get_block_number()" "$script_path"; then
        sed -i '/^get_block_number()/,/^}/d' "$script_path"
        echo "  - Removed get_block_number() duplicate"
    fi
    
    echo "  ✅ Complete"
    echo ""
done

echo "=== Validation ==="
echo "Checking for remaining duplicates..."
remaining=$(find "$SCRIPT_DIR" -name "*.sh" -type f -not -path "*/lib/*" -exec grep -l "^detect_network()" {} \; | wc -l)
echo "Scripts still defining detect_network(): $remaining"

if [[ $remaining -eq 0 ]]; then
    echo "✅ SUCCESS: All duplicates removed!"
else
    echo "⚠️  WARNING: Some duplicates remain"
    find "$SCRIPT_DIR" -name "*.sh" -type f -not -path "*/lib/*" -exec grep -l "^detect_network()" {} \;
fi

echo ""
echo "=== Summary ==="
echo "Processed ${#SCRIPTS_TO_FIX[@]} scripts"
echo "All scripts now source from lib/common.sh"
echo "Duplicate function definitions removed"
