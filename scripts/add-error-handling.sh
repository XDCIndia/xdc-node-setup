#!/bin/bash
set -euo pipefail

# Error Handling Enhancement for Shell Scripts
# Issue #508: Add proper error handling with set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"

# Find scripts without error handling
find_scripts_without_error_handling() {
    local dir=${1:-.}
    
    find "$dir" -name "*.sh" -type f | while read -r script; do
        # Skip if already has proper error handling
        if ! grep -q "set -euo pipefail" "$script" 2>/dev/null; then
            echo "$script"
        fi
    done
}

# Add error handling to a script
add_error_handling() {
    local script=$1
    local backup=true
    
    if [[ "$backup" == true ]]; then
        cp "$script" "$script.backup.$(date +%Y%m%d%H%M%S)"
    fi
    
    # Read the script content
    local content
    content=$(cat "$script")
    
    # Check if it has a shebang
    if [[ ! "$content" =~ ^#! ]]; then
        echo "Warning: $script missing shebang, skipping"
        return 1
    fi
    
    # Check if already has error handling
    if echo "$content" | grep -q "set -euo pipefail"; then
        echo "Already has error handling: $script"
        return 0
    fi
    
    # Add error handling after shebang
    local new_content
    new_content=$(echo "$content" | awk '
        NR==1 { print; print "set -euo pipefail"; next }
        { print }
    ')
    
    # Add error trap if not present
    if ! echo "$new_content" | grep -q "trap.*ERR"; then
        new_content=$(echo "$new_content" | awk '
        NR==2 { print; print ""; print "# Error handling"; print "trap '"'"'echo \"Error on line \$LINENO\" >&2'"'"' ERR"; next }
        { print }
    ')
    fi
    
    echo "$new_content" > "$script"
    chmod +x "$script"
    
    echo "Updated: $script"
}

# Create pre-commit hook
create_precommit_hook() {
    local hook_file=".git/hooks/pre-commit"
    
    cat > "$hook_file" <<'EOF'
#!/bin/bash
# Pre-commit hook to check shell script error handling

echo "Checking shell scripts for error handling..."

failed=0
while IFS= read -r script; do
    # Skip if in vendor or node_modules
    if [[ "$script" == *"/vendor/"* ]] || [[ "$script" == *"/node_modules/"* ]]; then
        continue
    fi
    
    if ! grep -q "set -euo pipefail" "$script"; then
        echo "❌ Missing error handling: $script"
        failed=1
    fi
done < <(find . -name "*.sh" -type f 2>/dev/null)

if [[ $failed -eq 1 ]]; then
    echo ""
    echo "Add 'set -euo pipefail' to the beginning of these scripts"
    echo "Or run: ./scripts/add-error-handling.sh apply"
    exit 1
fi

echo "✅ All scripts have proper error handling"
exit 0
EOF
    
    chmod +x "$hook_file"
    echo "Created pre-commit hook: $hook_file"
}

# Apply error handling to all scripts
apply_to_all() {
    local dir=${1:-.}
    local count=0
    
    while IFS= read -r script; do
        if add_error_handling "$script"; then
            ((count++))
        fi
    done < <(find_scripts_without_error_handling "$dir")
    
    echo ""
    echo "Updated $count scripts with error handling"
}

# Show usage
show_help() {
    cat <<'EOF'
Error Handling Enhancement v1.0.0

Usage: add-error-handling.sh <command> [options]

Commands:
  find [directory]          Find scripts without error handling
  apply [directory]         Apply error handling to all scripts
  fix <script>              Fix specific script
  hook                      Create pre-commit hook

Examples:
  ./add-error-handling.sh find ./scripts
  ./add-error-handling.sh apply
  ./add-error-handling.sh fix ./scripts/setup.sh
  ./add-error-handling.sh hook

What gets added:
  - set -euo pipefail at the beginning
  - trap for ERR to show line numbers
  - Backup of original file

EOF
}

# Main
main() {
    case "${1:-}" in
        find)
            find_scripts_without_error_handling "${2:-.}"
            ;;
        apply)
            apply_to_all "${2:-.}"
            ;;
        fix)
            script="${2:-}"
            if [[ -z "$script" ]]; then
                echo "Error: Script path required"
                exit 1
            fi
            add_error_handling "$script"
            ;;
        hook)
            create_precommit_hook
            ;;
        --help|-h)
            show_help
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

main "$@"
