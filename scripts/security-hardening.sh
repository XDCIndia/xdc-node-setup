#!/usr/bin/env bash
#===============================================================================
# XDC Compose Security Hardening
# Adds no-new-privileges, cap_drop, and read-only rootfs to compose files
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/286
#
# Usage:
#   security-hardening.sh <compose-file>
#   security-hardening.sh docker/apothem/gp5-pbss.yml
#===============================================================================

set -euo pipefail

FILE="${1:-}"
[[ -z "$FILE" ]] && { echo "Usage: $0 <compose-file>" >&2; exit 1; }
[[ -f "$FILE" ]] || { echo "File not found: $FILE" >&2; exit 1; }

# Check if already hardened
if grep -q "no-new-privileges:true" "$FILE" 2>/dev/null; then
    echo "Already hardened: $FILE"
    exit 0
fi

# Create backup
cp "$FILE" "$FILE.backup.$(date +%s)"

# Use yq if available, otherwise sed
if command -v yq &>/dev/null; then
    yq eval '(.services[].security_opt //= []) |= . + ["no-new-privileges:true"]
             | (.services[].cap_drop //= []) |= . + ["ALL"]
             | (.services[].read_only //= false) |= true' -i "$FILE"
else
    # Fallback: append security options before deploy: or logging:
    sed -i '/deploy:/i\    security_opt:\n    - no-new-privileges:true\n    cap_drop:\n    - ALL' "$FILE"
fi

echo "Hardened: $FILE"
echo "Backup: $FILE.backup.*"
