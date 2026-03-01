#!/usr/bin/env bash
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }

#==============================================================================
# XDC Node Setup E2E Test Script
# Tests setup.sh functionality without requiring actual installation
#==============================================================================

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SETUP_SCRIPT="${TEST_SCRIPT_DIR}/../setup.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

#==============================================================================
# Test Utilities
#==============================================================================
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    if [[ -n "${2:-}" ]]; then
        echo "  Details: $2"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

run_test() {
    local name="$1"
    echo ""
    echo -e "${BLUE}Testing:${NC} $name"
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Count matching patterns
count_matches() {
    local pattern="$1"
    grep -c "$pattern" "$SETUP_SCRIPT" 2>/dev/null || echo 0
}

#==============================================================================
# Static Analysis Tests
#==============================================================================

test_script_exists() {
    run_test "Script file exists"
    
    if [[ -f "$SETUP_SCRIPT" ]]; then
        pass "Setup script exists at $SETUP_SCRIPT"
    else
        fail "Setup script not found"
    fi
}

test_bash_shebang() {
    run_test "Bash shebang"
    
    if head -1 "$SETUP_SCRIPT" | grep -q "#!/usr/bin/env bash"; then
        pass "Correct bash shebang present"
    else
        fail "Missing or incorrect shebang"
    fi
}

test_strict_mode() {
    run_test "Strict mode (set -euo pipefail)"
    
    if head -5 "$SETUP_SCRIPT" | grep -q "set -euo pipefail"; then
        pass "Strict error handling enabled"
    else
        fail "Strict mode not found"
    fi
}

test_help_flag() {
    run_test "--help flag implementation"
    
    if grep -q "\-\-help|-h" "$SETUP_SCRIPT" && grep -q "show_help" "$SETUP_SCRIPT"; then
        pass "--help flag implemented"
    else
        fail "--help flag not properly implemented"
    fi
}

test_version_flag() {
    run_test "--version flag implementation"
    
    if grep -q "\-\-version|-v" "$SETUP_SCRIPT"; then
        pass "--version flag implemented"
    else
        fail "--version flag not found"
    fi
}

test_os_detection() {
    run_test "OS detection function"
    
    if grep -q "detect_os()" "$SETUP_SCRIPT"; then
        pass "detect_os function exists"
    else
        fail "detect_os function not found"
    fi
}

test_linux_detection() {
    run_test "Linux OS detection"
    
    local indicators=0
    indicators=$(( $(count_matches "linux-gnu") + $(count_matches "ubuntu") + $(count_matches "debian") ))
    
    if [[ $indicators -ge 2 ]]; then
        pass "Linux detection implemented ($indicators matches)"
    else
        fail "Linux detection incomplete ($indicators found)"
    fi
}

test_macos_detection() {
    run_test "macOS detection"
    
    if grep -q "darwin" "$SETUP_SCRIPT" && grep -q "macos" "$SETUP_SCRIPT"; then
        pass "macOS detection implemented"
    else
        fail "macOS detection not found"
    fi
}

test_simple_mode() {
    run_test "Simple mode (default)"
    
    if grep -q 'MODE="simple"' "$SETUP_SCRIPT" || grep -q "MODE=simple" "$SETUP_SCRIPT"; then
        pass "Simple mode as default"
    else
        fail "Simple mode not set as default"
    fi
}

test_advanced_mode() {
    run_test "Advanced mode flag"
    
    if grep -q "\-\-advanced" "$SETUP_SCRIPT"; then
        pass "--advanced flag recognized"
    else
        fail "--advanced flag not found"
    fi
}

test_brew_for_macos() {
    run_test "Homebrew for macOS"
    
    if grep -q "brew" "$SETUP_SCRIPT"; then
        pass "Homebrew package management implemented"
    else
        fail "Homebrew not used for macOS"
    fi
}

test_apt_for_linux() {
    run_test "apt for Linux"
    
    if grep -q "apt-get" "$SETUP_SCRIPT"; then
        pass "apt package management implemented"
    else
        fail "apt not used for Linux"
    fi
}

test_docker_check() {
    run_test "Docker checking"
    
    if grep -q "check_docker" "$SETUP_SCRIPT" || grep -q "docker" "$SETUP_SCRIPT"; then
        pass "Docker handling present"
    else
        fail "Docker checks not found"
    fi
}

test_docker_macos_requirement() {
    run_test "Docker Desktop requirement for macOS"
    
    if grep -q "Docker Desktop" "$SETUP_SCRIPT" || grep -q "docker.com" "$SETUP_SCRIPT"; then
        pass "Docker Desktop requirement documented"
    else
        fail "Docker Desktop requirement not found"
    fi
}

test_gnu_bsd_compat() {
    run_test "GNU/BSD compatibility"
    
    if grep -q "sed_inplace" "$SETUP_SCRIPT" || grep -q "darwin.*sed\|macos.*sed" "$SETUP_SCRIPT"; then
        pass "sed compatibility handling exists"
    else
        fail "GNU/BSD compatibility not handled"
    fi
}

test_uninstall_flag() {
    run_test "--uninstall flag"
    
    if grep -q "\-\-uninstall" "$SETUP_SCRIPT"; then
        pass "--uninstall flag implemented"
    else
        fail "--uninstall flag not found"
    fi
}

test_status_flag() {
    run_test "--status flag"
    
    if grep -q "\-\-status" "$SETUP_SCRIPT"; then
        pass "--status flag implemented"
    else
        fail "--status flag not found"
    fi
}

test_idempotency() {
    run_test "Idempotency"
    
    local indicators=0
    grep -q "already installed" "$SETUP_SCRIPT" && indicators=$((indicators + 1))
    grep -q "check_docker" "$SETUP_SCRIPT" && indicators=$((indicators + 1))
    grep -q "docker compose up -d" "$SETUP_SCRIPT" && indicators=$((indicators + 1))
    
    if [[ $indicators -ge 2 ]]; then
        pass "Idempotency checks present ($indicators indicators)"
    else
        fail "Insufficient idempotency checks"
    fi
}

test_banner() {
    run_test "ASCII art banner"
    
    if grep -q "show_banner" "$SETUP_SCRIPT" && grep -q "XDC" "$SETUP_SCRIPT"; then
        pass "Banner function exists"
    else
        fail "Banner not found"
    fi
}

test_colors() {
    run_test "Color definitions"
    
    local colors=0
    grep -q "RED=" "$SETUP_SCRIPT" && colors=$((colors + 1))
    grep -q "GREEN=" "$SETUP_SCRIPT" && colors=$((colors + 1))
    grep -q "YELLOW=" "$SETUP_SCRIPT" && colors=$((colors + 1))
    grep -q "BLUE=" "$SETUP_SCRIPT" && colors=$((colors + 1))
    
    if [[ $colors -ge 4 ]]; then
        pass "Color definitions present ($colors colors)"
    else
        fail "Insufficient colors ($colors found)"
    fi
}

test_logging() {
    run_test "Logging functions"
    
    local funcs=0
    grep -q "^log()" "$SETUP_SCRIPT" && funcs=$((funcs + 1))
    grep -q "^info()" "$SETUP_SCRIPT" && funcs=$((funcs + 1))
    grep -q "^warn()" "$SETUP_SCRIPT" && funcs=$((funcs + 1))
    grep -q "^error()" "$SETUP_SCRIPT" && funcs=$((funcs + 1))
    
    if [[ $funcs -ge 3 ]]; then
        pass "Logging functions present ($funcs functions)"
    else
        fail "Insufficient logging functions"
    fi
}

test_log_file() {
    run_test "Log file configuration"
    
    if grep -q "LOG_FILE" "$SETUP_SCRIPT"; then
        pass "Log file configuration exists"
    else
        fail "LOG_FILE not defined"
    fi
}

test_spinner() {
    run_test "Progress spinner"
    
    if grep -q "spinner" "$SETUP_SCRIPT"; then
        pass "Spinner function exists"
    else
        fail "Spinner not found"
    fi
}

test_docker_compose() {
    run_test "Docker Compose generation"
    
    if grep -q "docker-compose.yml" "$SETUP_SCRIPT" && grep -q "setup_docker_compose" "$SETUP_SCRIPT"; then
        pass "Docker Compose setup implemented"
    else
        fail "Docker Compose generation not found"
    fi
}

test_monitoring() {
    run_test "Monitoring setup"
    
    if grep -q "prometheus" "$SETUP_SCRIPT" && grep -q "grafana" "$SETUP_SCRIPT"; then
        pass "Monitoring (Prometheus/Grafana) configured"
    else
        fail "Monitoring setup incomplete"
    fi
}

test_security() {
    run_test "Security hardening"
    
    local checks=0
    grep -qi "ufw" "$SETUP_SCRIPT" && checks=$((checks + 1))
    grep -qi "fail2ban" "$SETUP_SCRIPT" && checks=$((checks + 1))
    
    if [[ $checks -ge 1 ]]; then
        pass "Security hardening present ($checks indicators)"
    else
        fail "Security hardening not found"
    fi
}

test_cli_tool() {
    run_test "CLI tool installation"
    
    if grep -q "xdc-node" "$SETUP_SCRIPT" && grep -q "install_cli_tool" "$SETUP_SCRIPT"; then
        pass "CLI tool (xdc-node) installation implemented"
    else
        fail "CLI tool not found"
    fi
}

test_env_vars() {
    run_test "Environment variables"
    
    local vars=0
    grep -q "NODE_TYPE" "$SETUP_SCRIPT" && vars=$((vars + 1))
    grep -q "NETWORK" "$SETUP_SCRIPT" && vars=$((vars + 1))
    grep -q "DATA_DIR" "$SETUP_SCRIPT" && vars=$((vars + 1))
    grep -q "RPC_PORT" "$SETUP_SCRIPT" && vars=$((vars + 1))
    
    if [[ $vars -ge 4 ]]; then
        pass "Environment variables supported ($vars vars)"
    else
        fail "Insufficient environment variables"
    fi
}

test_proxy_support() {
    run_test "Proxy support"
    
    if grep -q "HTTP_PROXY\|HTTPS_PROXY" "$SETUP_SCRIPT"; then
        pass "HTTP/HTTPS proxy support implemented"
    else
        fail "Proxy support not found"
    fi
}

test_hardware_checks() {
    run_test "Hardware checks"
    
    if grep -q "check_hardware" "$SETUP_SCRIPT"; then
        pass "Hardware requirement checks implemented"
    else
        fail "Hardware checks not found"
    fi
}

test_post_install() {
    run_test "Post-install output"
    
    if grep -q "print_summary" "$SETUP_SCRIPT"; then
        pass "Post-install summary function exists"
    else
        fail "Post-install summary not found"
    fi
}

test_os_paths() {
    run_test "OS-specific paths"
    
    if grep -q "DEFAULT_DATA_DIR" "$SETUP_SCRIPT" && grep -q "INSTALL_DIR" "$SETUP_SCRIPT"; then
        pass "OS-specific paths configured"
    else
        fail "OS-specific paths not configured"
    fi
}

test_node_types() {
    run_test "Node type options"
    
    local types=0
    grep -q "full" "$SETUP_SCRIPT" && types=$((types + 1))
    grep -q "archive" "$SETUP_SCRIPT" && types=$((types + 1))
    grep -q "rpc" "$SETUP_SCRIPT" && types=$((types + 1))
    grep -q "masternode" "$SETUP_SCRIPT" && types=$((types + 1))
    
    if [[ $types -ge 3 ]]; then
        pass "Node types available ($types types)"
    else
        fail "Insufficient node types"
    fi
}

test_networks() {
    run_test "Network options"
    
    if grep -q "mainnet" "$SETUP_SCRIPT" && grep -q "testnet" "$SETUP_SCRIPT"; then
        pass "Network options (mainnet/testnet) implemented"
    else
        fail "Network options not found"
    fi
}

test_sync_modes() {
    run_test "Sync mode options"
    
    if grep -q "syncmode\|SYNC_MODE" "$SETUP_SCRIPT"; then
        pass "Sync mode configuration exists"
    else
        fail "Sync modes not found"
    fi
}

test_root_check() {
    run_test "Root user check"
    
    if grep -q "check_root" "$SETUP_SCRIPT" && grep -q "EUID" "$SETUP_SCRIPT"; then
        pass "Root check implemented"
    else
        fail "Root check not found"
    fi
}

test_error_handling() {
    run_test "Error handling patterns"
    
    local patterns=0
    grep -q "|| true" "$SETUP_SCRIPT" && patterns=$((patterns + 1))
    grep -q "2>/dev/null" "$SETUP_SCRIPT" && patterns=$((patterns + 1))
    
    if [[ $patterns -ge 2 ]]; then
        pass "Error handling patterns present"
    else
        fail "Insufficient error handling"
    fi
}

#==============================================================================
# Main
#==============================================================================
main() {
    echo "========================================"
    echo "  XDC Node Setup - E2E Test Suite"
    echo "========================================"
    echo ""
    echo "Testing: $SETUP_SCRIPT"
    echo ""
    
    if [[ ! -f "$SETUP_SCRIPT" ]]; then
        echo -e "${RED}ERROR: Setup script not found at $SETUP_SCRIPT${NC}"
        exit 1
    fi
    
    # Run all tests
    test_script_exists
    test_bash_shebang
    test_strict_mode
    test_help_flag
    test_version_flag
    test_os_detection
    test_linux_detection
    test_macos_detection
    test_simple_mode
    test_advanced_mode
    test_brew_for_macos
    test_apt_for_linux
    test_docker_check
    test_docker_macos_requirement
    test_gnu_bsd_compat
    test_uninstall_flag
    test_status_flag
    test_idempotency
    test_banner
    test_colors
    test_logging
    test_log_file
    test_spinner
    test_docker_compose
    test_monitoring
    test_security
    test_cli_tool
    test_env_vars
    test_proxy_support
    test_hardware_checks
    test_post_install
    test_os_paths
    test_node_types
    test_networks
    test_sync_modes
    test_root_check
    test_error_handling
    
    # Print summary
    echo ""
    echo "========================================"
    echo "  Test Summary"
    echo "========================================"
    echo -e "  Total:  $TESTS_RUN"
    echo -e "  ${GREEN}Passed:${NC} $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC} $TESTS_FAILED"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed! ✓${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed! ✗${NC}"
        exit 1
    fi
}

main "$@"
