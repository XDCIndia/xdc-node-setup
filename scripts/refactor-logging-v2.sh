#!/bin/bash
# Refactor scripts to use shared logging library
# Fixes Issue #378: Code Duplication - Consolidate logging functions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Refactoring Scripts to Use Shared Logging Library ==="
echo ""

# Find all scripts with duplicate log() definitions
SCRIPTS=$(find "$REPO_ROOT/scripts" -name "*.sh" -type f ! -path "*/lib/*" -exec grep -l "^log()" {} \;)

refactor_script() {
    local script="$1"
    
    echo "📝 Processing: $(basename "$script")"
    
    # Backup
    cp "$script" "${script}.backup"
    
    # Check if already sources logging.sh
    if grep -q 'source.*lib/logging.sh' "$script"; then
        echo "  ✓ Already sources logging.sh"
    else
        # Add source after shebang
        local temp="$script.tmp"
        {
            head -n 1 "$script"  # Keep shebang
            echo ""
            echo "# Source shared logging library"
            echo 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"'
            echo 'source "${SCRIPT_DIR}/lib/logging.sh"'
            echo ""
            tail -n +2 "$script"  # Rest of file
        } > "$temp"
        mv "$temp" "$script"
        echo "  ✓ Added logging.sh source"
    fi
    
    # Remove duplicate function definitions
    # Using python for robust parsing
    python3 <<'PYTHON' "$script"
import sys
import re

script_path = sys.argv[1]

with open(script_path, 'r') as f:
    content = f.read()

# Patterns for functions to remove
functions_to_remove = ['log', 'info', 'warn', 'error', 'success', 'failure']

for func in functions_to_remove:
    # Match function definition including its body
    pattern = rf'^{func}\(\)\s*\{{.*?^\}}'
    content = re.sub(pattern, '', content, flags=re.MULTILINE | re.DOTALL)

with open(script_path, 'w') as f:
    f.write(content)
PYTHON
    
    # Verify syntax
    if bash -n "$script" 2>/dev/null; then
        echo "  ✓ Syntax check passed"
        rm -f "${script}.backup"
        return 0
    else
        echo "  ✗ Syntax error - restoring backup"
        mv "${script}.backup" "$script"
        return 1
    fi
}

success=0
failed=0

while IFS= read -r script; do
    if refactor_script "$script"; then
        ((success++))
    else
        ((failed++))
    fi
    echo ""
done <<< "$SCRIPTS"

echo "=== Summary ==="
echo "✓ Success: $success"
echo "✗ Failed: $failed"
echo ""

if [[ $failed -eq 0 ]]; then
    echo "🎉 Refactoring complete!"
    exit 0
else
    echo "⚠ Some failures occurred"
    exit 1
fi
