#!/bin/bash
# Test for health check endpoints - Issue #521
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/../.."

echo "=== Testing Issue #521 Fix: Health Check Endpoints ==="

# Test 1: Health check server script exists
echo -n "Test 1: health-check-server.sh exists... "
if [[ ! -f "${REPO_DIR}/scripts/health-check-server.sh" ]]; then
    echo "FAILED - Script not found"
    exit 1
fi
# Check it has proper error handling
if ! grep -q "set -euo pipefail" "${REPO_DIR}/scripts/health-check-server.sh"; then
    echo "FAILED - Missing error handling"
    exit 1
fi
echo "PASSED"

# Test 2: Docker Compose for health check exists
echo -n "Test 2: docker-compose.health.yml exists... "
if [[ ! -f "${REPO_DIR}/docker/docker-compose.health.yml" ]]; then
    echo "FAILED - Compose file not found"
    exit 1
fi
# Check for health endpoints
if ! grep -q "/health/live" "${REPO_DIR}/docker/docker-compose.health.yml"; then
    echo "FAILED - /health/live endpoint not defined"
    exit 1
fi
echo "PASSED"

# Test 3: Health check functions exist in script
echo -n "Test 3: Health check functions implemented... "
if ! grep -q "check_liveness()" "${REPO_DIR}/scripts/health-check-server.sh"; then
    echo "FAILED - check_liveness function not found"
    exit 1
fi
if ! grep -q "check_readiness()" "${REPO_DIR}/scripts/health-check-server.sh"; then
    echo "FAILED - check_readiness function not found"
    exit 1
fi
if ! grep -q "check_sync()" "${REPO_DIR}/scripts/health-check-server.sh"; then
    echo "FAILED - check_sync function not found"
    exit 1
fi
echo "PASSED"

# Test 4: Kubernetes-compatible responses
echo -n "Test 4: Script provides Kubernetes-compatible responses... "
if ! grep -q 'HTTP/1.1 200 OK' "${REPO_DIR}/scripts/health-check-server.sh"; then
    echo "FAILED - 200 OK response not found"
    exit 1
fi
if ! grep -q 'HTTP/1.1 503 Service Unavailable' "${REPO_DIR}/scripts/health-check-server.sh"; then
    echo "FAILED - 503 response not found"
    exit 1
fi
echo "PASSED"

echo ""
echo "=== All tests passed for Issue #521 ==="
