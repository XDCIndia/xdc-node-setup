#!/bin/bash
# Script to fix declare -A compatibility issues in shell scripts

fix_declare_a() {
    local file="$1"
    echo "Fixing $file..."
    
    # Comment out declare -A lines
    sed -i 's/^declare -A /# declare -A /g' "$file"
    
    # Replace VAR["key"]="value" with VAR_key="value"
    sed -i 's/\([A-Za-z_][A-Za-z0-9_]*\)\["\([^"]*\)"\]="\([^"]*\)"/\1_\2="\3"/g' "$file"
    
    # Replace ${VAR["key"]} with ${VAR_key}
    sed -i 's/\${\([A-Za-z_][A-Za-z0-9_]*\)\["\([^"]*\)"\]}/${\1_\2}/g' "$file"
    
    # Replace ${VAR["key"]:-default} with ${VAR_key:-default}
    sed -i 's/\${\([A-Za-z_][A-Za-z0-9_]*\)\["\([^"]*\)"\]:-\([^}]*\)}/${\1_\2:-\3}/g' "$file"
    
    # Replace for key in "${!VAR[@]}" with eval-based loop
    # This is more complex and may need manual review
}

# Fix files
for file in "$@"; do
    if [[ -f "$file" ]]; then
        fix_declare_a "$file"
    fi
done

echo "Done. Please review the changes."
