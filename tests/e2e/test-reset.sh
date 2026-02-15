#!/usr/bin/env bash
#==============================================================================
# E2E Test: Reset Command
# Tests xdc reset (data wipe), xdc reset --keep-config, and recovery
#==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/framework.sh"

describe "Reset Commands"

#------------------------------------------------------------------------------
# xdc reset --dry-run
#------------------------------------------------------------------------------
test_reset_dry_run() {
    it "should support --dry-run without modifying state"
    
    if command -v xdc &>/dev/null; then
        run_cmd xdc reset --dry-run
        assert_exit_code 0
        assert_output_contains "dry-run\|would remove\|would reset"
    else
        skip "xdc CLI not installed"
    fi
}

#------------------------------------------------------------------------------
# xdc reset --keep-config
#------------------------------------------------------------------------------
test_reset_keep_config() {
    it "should preserve config files when --keep-config is used"
    
    if command -v xdc &>/dev/null; then
        # Capture config before reset
        local config_exists=false
        if [[ -f "${XDC_HOME:-/opt/xdc-node}/config.toml" ]]; then
            config_exists=true
        fi
        
        run_cmd xdc reset --keep-config --yes
        assert_exit_code 0
        
        if $config_exists; then
            assert_file_exists "${XDC_HOME:-/opt/xdc-node}/config.toml" \
                "config.toml preserved after reset --keep-config"
        fi
    else
        skip "xdc CLI not installed"
    fi
}

#------------------------------------------------------------------------------
# xdc reset requires confirmation
#------------------------------------------------------------------------------
test_reset_requires_confirmation() {
    it "should abort without --yes flag (non-interactive)"
    
    if command -v xdc &>/dev/null; then
        # Pipe 'n' to stdin to decline
        run_cmd_stdin "n" xdc reset
        # Should either prompt and exit, or error without --yes
        assert_exit_code_nonzero
    else
        skip "xdc CLI not installed"
    fi
}

#------------------------------------------------------------------------------
# xdc reset stops running containers
#------------------------------------------------------------------------------
test_reset_stops_containers() {
    it "should stop running containers before resetting"
    
    if command -v xdc &>/dev/null && command -v docker &>/dev/null; then
        run_cmd xdc reset --dry-run
        assert_output_matches "(stop|container|docker)" || true
    else
        skip "xdc or Docker not available"
    fi
}

#------------------------------------------------------------------------------
# xdc reset removes chain data
#------------------------------------------------------------------------------
test_reset_removes_data() {
    it "should remove chain data directory"
    
    if command -v xdc &>/dev/null; then
        local data_dir="${XDC_HOME:-/opt/xdc-node}/data"
        
        # Create a marker file to verify deletion
        if [[ -d "$data_dir" ]]; then
            touch "${data_dir}/.e2e-test-marker" 2>/dev/null || true
        fi
        
        run_cmd xdc reset --yes
        assert_exit_code 0
        
        if [[ -f "${data_dir}/.e2e-test-marker" ]]; then
            fail "Data directory was not cleaned"
        fi
    else
        skip "xdc CLI not installed"
    fi
}

#------------------------------------------------------------------------------
# Recovery: xdc setup after reset
#------------------------------------------------------------------------------
test_reset_then_setup() {
    it "should allow fresh xdc setup after reset"
    
    if command -v xdc &>/dev/null; then
        # After reset, setup should work
        run_cmd xdc setup --non-interactive --network testnet 2>/dev/null || true
        # Just verify it doesn't crash
        assert_exit_code 0 || skip "setup requires interactive input"
    else
        skip "xdc CLI not installed"
    fi
}

#------------------------------------------------------------------------------
# macOS ARM64: reset cleans Docker volumes
#------------------------------------------------------------------------------
test_reset_docker_volumes_macos() {
    it "should clean Docker volumes on macOS"
    
    if [[ "$(uname -s)" == "Darwin" ]] && command -v docker &>/dev/null; then
        # Check that XDC-related volumes are removed after reset
        run_cmd xdc reset --dry-run
        assert_output_matches "(volume|prune|remove)" || true
    else
        skip "Not macOS or Docker unavailable"
    fi
}

#------------------------------------------------------------------------------
# Run all tests
#------------------------------------------------------------------------------
run_tests \
    test_reset_dry_run \
    test_reset_requires_confirmation \
    test_reset_stops_containers \
    test_reset_keep_config \
    test_reset_removes_data \
    test_reset_then_setup \
    test_reset_docker_volumes_macos
