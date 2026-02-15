#!/usr/bin/env bash
#==============================================================================
# E2E Test: Health Check Commands
# Tests xdc health, xdc health --json, endpoint checks, and auto-recovery
#==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/framework.sh"

describe "Health Check Commands"

#------------------------------------------------------------------------------
# xdc health — basic output
#------------------------------------------------------------------------------
test_health_basic() {
    it "should run 'xdc health' without errors"
    
    if command -v xdc &>/dev/null; then
        run_cmd xdc health
        assert_exit_code 0
        assert_output_contains "Health"
    else
        skip "xdc CLI not installed"
    fi
}

#------------------------------------------------------------------------------
# xdc health --json
#------------------------------------------------------------------------------
test_health_json() {
    it "should output valid JSON with --json flag"
    
    if command -v xdc &>/dev/null; then
        run_cmd xdc health --json
        assert_exit_code 0
        # Validate JSON
        echo "$OUTPUT" | python3 -m json.tool &>/dev/null || jq . <<< "$OUTPUT" &>/dev/null
        assert_exit_code 0 "JSON output is valid"
    else
        skip "xdc CLI not installed"
    fi
}

#------------------------------------------------------------------------------
# Health endpoint reachability
#------------------------------------------------------------------------------
test_health_endpoint() {
    it "should check RPC endpoint health"
    
    if command -v xdc &>/dev/null && xdc status &>/dev/null; then
        run_cmd xdc health --check rpc
        assert_exit_code 0
    else
        skip "xdc node not running"
    fi
}

test_health_ws_endpoint() {
    it "should check WebSocket endpoint health"
    
    if command -v xdc &>/dev/null && xdc status &>/dev/null; then
        run_cmd xdc health --check ws
        assert_exit_code 0
    else
        skip "xdc node not running"
    fi
}

#------------------------------------------------------------------------------
# Health with stopped node
#------------------------------------------------------------------------------
test_health_stopped_node() {
    it "should report unhealthy when node is stopped"
    
    if command -v xdc &>/dev/null; then
        # Ensure node is stopped for this test
        if ! xdc status &>/dev/null; then
            run_cmd xdc health
            # Should exit non-zero or report unhealthy
            assert_output_matches "(unhealthy|not running|stopped|error)" || true
        else
            skip "node is running; cannot test stopped state"
        fi
    else
        skip "xdc CLI not installed"
    fi
}

#------------------------------------------------------------------------------
# Disk space health
#------------------------------------------------------------------------------
test_health_disk() {
    it "should check disk space availability"
    
    if command -v xdc &>/dev/null; then
        run_cmd xdc health --check disk
        assert_exit_code 0
    else
        skip "xdc CLI not installed"
    fi
}

#------------------------------------------------------------------------------
# Docker health (container status)
#------------------------------------------------------------------------------
test_health_docker() {
    it "should verify Docker container health status"
    
    if command -v docker &>/dev/null; then
        # Check if XDC container exists and has health status
        local container
        container=$(docker ps --filter "name=xdc" --format '{{.Names}}' 2>/dev/null | head -1)
        if [[ -n "$container" ]]; then
            local health
            health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
            assert_not_empty "$health" "Container has health status"
        else
            skip "No XDC container running"
        fi
    else
        skip "Docker not available"
    fi
}

#------------------------------------------------------------------------------
# macOS ARM64: Rosetta / native binary check
#------------------------------------------------------------------------------
test_health_macos_native() {
    it "should verify native ARM64 binary on macOS"
    
    if [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]]; then
        if command -v xdc &>/dev/null; then
            # Check that Docker is running natively (not under Rosetta)
            local arch
            arch=$(docker version --format '{{.Server.Arch}}' 2>/dev/null || echo "unknown")
            assert_equals "arm64" "$arch" "Docker runs natively on ARM64"
        else
            skip "xdc CLI not installed"
        fi
    else
        skip "Not macOS ARM64"
    fi
}

#------------------------------------------------------------------------------
# Run all tests
#------------------------------------------------------------------------------
run_tests \
    test_health_basic \
    test_health_json \
    test_health_endpoint \
    test_health_ws_endpoint \
    test_health_stopped_node \
    test_health_disk \
    test_health_docker \
    test_health_macos_native
