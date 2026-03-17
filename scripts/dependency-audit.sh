#!/usr/bin/env bash
#==============================================================================
# Dependency Security Audit (Issue #400)
#==============================================================================
set -euo pipefail

echo "🔒 XDC Node Dependency Security Audit"
echo ""

# Check Docker image vulnerabilities
echo "=== Docker Image Scan ==="
for img in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E 'xdc|gx|nmx|reth|erigon' | head -10); do
    echo "Scanning: $img"
    if command -v trivy >/dev/null 2>&1; then
        trivy image --severity HIGH,CRITICAL --no-progress "$img" 2>/dev/null | tail -5
    elif docker scout version >/dev/null 2>&1; then
        docker scout cves "$img" --only-severity critical,high 2>/dev/null | head -10
    else
        echo "  Install trivy or docker scout for vulnerability scanning"
    fi
    echo ""
done

# Check system packages
echo "=== System Package Updates ==="
if command -v apt >/dev/null 2>&1; then
    apt list --upgradable 2>/dev/null | grep -i security | head -10
elif command -v yum >/dev/null 2>&1; then
    yum check-update --security 2>/dev/null | head -10
fi

# Check Node.js dependencies (if applicable)
echo ""
echo "=== Node.js Audit ==="
if [[ -f "package.json" ]]; then
    npm audit --omit=dev 2>/dev/null | tail -10
elif [[ -f "dashboard/package.json" ]]; then
    cd dashboard && npm audit --omit=dev 2>/dev/null | tail -10
fi

echo ""
echo "✅ Audit complete"
