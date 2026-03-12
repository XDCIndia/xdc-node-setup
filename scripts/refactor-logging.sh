#!/bin/bash
# Refactor scripts to use shared logging library
# Fixes Issue #378: Code Duplication - Consolidate logging functions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Scripts with duplicate log() functions
SCRIPTS=(
    "scripts/rpc-security.sh"
    "scripts/implement-standards.sh"
    "scripts/version-check.sh"
    "scripts/masternode-cluster.sh"
    "scripts/security-harden.sh"
    "scripts/notify-test.sh"
    "scripts/setup-ssl.sh"
    "scripts/node-health-check.sh"
    "scripts/auto-update.sh"
    "scripts/chaos-test.sh"
    "scripts/consensus-health.sh"
    "scripts/backup.sh"
    "scripts/skynet-agent.sh"
    "scripts/bootnode-optimize.sh"
)

# Patterns to remove (duplicate function definitions)
PATTERNS_TO_REMOVE=(
    '^log\(\) \{$'
    '^info\(\) \{$'
    '^warn\(\) \{$'
    '^error\(\) \{$'
    '^success\(\) \{$'
    '^failure\(\) \{$'
)

echo "=== Refactoring Scripts to Use Shared Logging Library ==="
echo "Target: scripts/lib/logging.sh"
echo ""

refactor_script() {
    local script="$1"
    local full_path="$REPO_ROOT/$script"
    
    if [[ ! -f "$full_path" ]]; then
        echo "⚠ Skipping $script (not found)"
        return 1
    fi
    
    echo "📝 Refactoring: $script"
    
    # Backup original
    cp "$full_path" "${full_path}.backup"
    
    # Check if already sources logging.sh
    if grep -q 'source.*lib/logging.sh' "$full_path"; then
        echo "  ✓ Already sources logging.sh"
    else
        # Add source line after shebang and before any functions
        local temp_file="${full_path}.tmp"
        awk '
            /^#!/ { print; next }
            /^#/ && !printed { print; next }
            !printed && !/^#/ {
                print ""
                print "# Source shared logging library"
                print "SCRIPT_DIR=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\""
                print "source \"${SCRIPT_DIR}/lib/logging.sh\""
                print ""
                printed=1
            }
            { print }
        ' "$full_path" > "$temp_file"
        mv "$temp_file" "$full_path"
        echo "  ✓ Added logging.sh source"
    fi
    
    # Remove duplicate function definitions
    local removed_count=0
    for pattern in "${PATTERNS_TO_REMOVE[@]}"; do
        if grep -q "$pattern" "$full_path"; then
            # Remove function definition and its body (until closing })
            local temp_file="${full_path}.tmp"
            awk -v pat="$pattern" '
                $0 ~ pat {
                    in_func=1
                    brace_count=0
                    next
                }
                in_func {
                    gsub(/[{}]/, " & ")
                    for (i=1; i<=NF; i++) {
                        if ($i == "{") brace_count++
                        if ($i == "}") brace_count--
                    }
                    if (brace_count == 0 && /}/) {
                        in_func=0
                        next
                    }
                    next
                }
                { print }
            ' "$full_path" > "$temp_file"
            mv "$temp_file" "$full_path"
            ((removed_count++))
        fi
    done
    
    if [[ $removed_count -gt 0 ]]; then
        echo "  ✓ Removed $removed_count duplicate function(s)"
    else
        echo "  ℹ No duplicate functions found"
    fi
    
    # Verify script still has valid bash syntax
    if bash -n "$full_path" 2>/dev/null; then
        echo "  ✓ Syntax check passed"
        rm -f "${full_path}.backup"
        return 0
    else
        echo "  ✗ Syntax error detected - restoring backup"
        mv "${full_path}.backup" "$full_path"
        return 1
    fi
}

# Refactor all scripts
success_count=0
fail_count=0

for script in "${SCRIPTS[@]}"; do
    if refactor_script "$script"; then
        ((success_count++))
    else
        ((fail_count++))
    fi
    echo ""
done

echo "=== Refactoring Summary ==="
echo "✓ Success: $success_count scripts"
echo "✗ Failed: $fail_count scripts"
echo ""

if [[ $fail_count -eq 0 ]]; then
    echo "🎉 All scripts refactored successfully!"
    echo "Next: Test scripts and commit changes"
    exit 0
else
    echo "⚠ Some scripts failed refactoring - check manually"
    exit 1
fi
