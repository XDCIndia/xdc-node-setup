#!/bin/bash
# Test for Grafana password fix - Issue #506
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/../.."

echo "=== Testing Issue #506 Fix: Remove Hardcoded Grafana Password ==="

# Test 1: No hardcoded password in docker-compose.monitoring.yml
echo -n "Test 1: docker-compose.monitoring.yml requires password... "
if grep -q "XDCGrafana2026!" "${REPO_DIR}/docker/docker-compose.monitoring.yml"; then
    echo "FAILED - Hardcoded password XDCGrafana2026! still exists"
    exit 1
fi
# Check that it uses the :? syntax to require the variable
if ! grep -q 'GRAFANA_ADMIN_PASSWORD:\?\|GRAFANA_ADMIN_PASSWORD:?"' "${REPO_DIR}/docker/docker-compose.monitoring.yml"; then
    echo "FAILED - Password is not required via :? syntax"
    exit 1
fi
echo "PASSED"

# Test 2: No hardcoded password in docker-compose.logging.yml
echo -n "Test 2: docker-compose.logging.yml requires password... "
if grep -q "GRAFANA_ADMIN_PASSWORD:-xdcadmin" "${REPO_DIR}/docker/docker-compose.logging.yml"; then
    echo "FAILED - Default password xdcadmin still exists"
    exit 1
fi
echo "PASSED"

# Test 3: No hardcoded password in docker-compose.skyone.yml
echo -n "Test 3: docker-compose.skyone.yml requires password... "
if grep -q "GRAFANA_PASSWORD:-admin" "${REPO_DIR}/docker/docker-compose.skyone.yml"; then
    echo "FAILED - Default admin password still exists"
    exit 1
fi
echo "PASSED"

# Test 4: .env.example documents required passwords
echo -n "Test 4: .env.example documents password requirements... "
if ! grep -q "REQUIRED: Grafana Security" "${REPO_DIR}/.env.example"; then
    echo "FAILED - .env.example doesn't document required Grafana config"
    exit 1
fi
if ! grep -q "GRAFANA_SECRET_KEY" "${REPO_DIR}/.env.example"; then
    echo "FAILED - GRAFANA_SECRET_KEY not documented"
    exit 1
fi
echo "PASSED"

echo ""
echo "=== All tests passed for Issue #506 ==="
