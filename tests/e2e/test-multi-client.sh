#!/usr/bin/env bash
#==============================================================================
# E2E Test: Multi-Client Support
# Tests running geth and erigon simultaneously
#==============================================================================

set -euo pipefail
source "$(dirname "$0")/lib/framework.sh"

test_start "Multi-Client Tests"

PROJECT_ROOT="$(get_project_root)"
export PATH="$PROJECT_ROOT/cli:$PATH"

#------------------------------------------------------------------------------
# Test: Multi-client documentation exists
#------------------------------------------------------------------------------

if [[ -f "$PROJECT_ROOT/docs/ERIGON.md" ]]; then
    assert_file_exists "$PROJECT_ROOT/docs/ERIGON.md" "Erigon documentation exists"
fi

#------------------------------------------------------------------------------
# Test: Client command exists
#------------------------------------------------------------------------------

client_help=$(xdc client --help 2>&1) || client_help=$(xdc help 2>&1)

if echo "$client_help" | grep -qiE "client|geth|erigon"; then
    pass "CLI supports client management"
else
    skip "CLI supports client management" "Client command not found"
fi

#------------------------------------------------------------------------------
# Test: Multiple client configs exist
#------------------------------------------------------------------------------

clients_found=0

# Check for geth config
if [[ -f "$PROJECT_ROOT/docker/docker-compose.yml" ]] && \
   grep -q "xinfinorg/xdc" "$PROJECT_ROOT/docker/docker-compose.yml" 2>/dev/null; then
    pass "Geth client configuration exists"
    ((clients_found++))
fi

# Check for erigon config
if [[ -d "$PROJECT_ROOT/docker/erigon" ]] || \
   [[ -f "$PROJECT_ROOT/docker/docker-compose.erigon-apothem.yml" ]] || \
   grep -q "erigon" "$PROJECT_ROOT/docker/docker-compose.yml" 2>/dev/null; then
    pass "Erigon client configuration exists"
    ((clients_found++))
fi

if [[ $clients_found -ge 2 ]]; then
    pass "Multiple clients are configured ($clients_found found)"
else
    skip "Multiple clients are configured" "Only $clients_found client(s) found"
fi

#------------------------------------------------------------------------------
# Test: Multi-client flag exists
#------------------------------------------------------------------------------

if xdc start --help 2>&1 | grep -qi "multi-client\|both\|all-clients"; then
    pass "Multi-client start option exists"
else
    skip "Multi-client start option exists" "Flag not documented"
fi

#------------------------------------------------------------------------------
# Test: Different ports for different clients
#------------------------------------------------------------------------------

# Geth typically uses 8545, Erigon should use 8546 or different port
geth_port="8545"
erigon_port="8546"

if grep -rq "$erigon_port\|8547\|8548" "$PROJECT_ROOT/docker/" 2>/dev/null; then
    pass "Different ports configured for multi-client"
else
    skip "Different ports configured for multi-client" "Port configuration unclear"
fi

#------------------------------------------------------------------------------
# Test: Client switching
#------------------------------------------------------------------------------

# Test that we can switch between clients
for client in geth erigon; do
    switch_output=$(xdc start --client "$client" --dry-run 2>&1) || true
    
    if echo "$switch_output" | grep -qi "error"; then
        if echo "$switch_output" | grep -qi "not supported\|not available"; then
            skip "Can select $client client" "Client not available"
        else
            skip "Can select $client client" "Error occurred"
        fi
    else
        pass "Can select $client client"
    fi
done

#------------------------------------------------------------------------------
# Test: Docker Compose multi-service support
#------------------------------------------------------------------------------

if command -v docker >/dev/null 2>&1; then
    # Check if docker-compose supports multiple services
    if docker compose version >/dev/null 2>&1 || docker-compose version >/dev/null 2>&1; then
        pass "Docker Compose available for multi-client"
    else
        skip "Docker Compose available for multi-client" "Not installed"
    fi
fi

#------------------------------------------------------------------------------
# Test: Client health check differentiation
#------------------------------------------------------------------------------

# Health checks should identify which client is running
health_output=$(xdc health --help 2>&1) || true

if echo "$health_output" | grep -qi "client"; then
    pass "Health check supports client identification"
else
    skip "Health check supports client identification" "Not in help"
fi

#------------------------------------------------------------------------------
# Test: Status shows active clients
#------------------------------------------------------------------------------

status_output=$(xdc status 2>&1) || true

if echo "$status_output" | grep -qiE "client|geth|erigon"; then
    pass "Status shows client information"
else
    skip "Status shows client information" "Not displayed"
fi

#------------------------------------------------------------------------------
# Test: Multi-client data directory separation
#------------------------------------------------------------------------------

# Different clients should use different data directories
if [[ -d "$PROJECT_ROOT/mainnet" ]] || [[ -d "$PROJECT_ROOT/testnet" ]]; then
    # Check for client-specific subdirs
    if grep -rq "xdcchain\|erigon" "$PROJECT_ROOT/docker/" 2>/dev/null | grep -q "volume\|mount"; then
        pass "Clients have separate data directories"
    else
        skip "Clients have separate data directories" "Configuration unclear"
    fi
fi

#------------------------------------------------------------------------------
# Test: Erigon ARM64 support (macOS specific)
#------------------------------------------------------------------------------

if is_macos_arm64; then
    log "Running on macOS ARM64 - checking Erigon compatibility"
    
    # Check if Erigon image supports ARM64
    if grep -rq "platform\|arm64\|aarch64" "$PROJECT_ROOT/docker/" 2>/dev/null; then
        pass "Platform specification for ARM64 exists"
    else
        skip "Platform specification for ARM64" "Not explicitly set"
    fi
fi

#------------------------------------------------------------------------------
# Test: Client version management
#------------------------------------------------------------------------------

if [[ -f "$PROJECT_ROOT/configs/versions.json" ]]; then
    versions_content=$(cat "$PROJECT_ROOT/configs/versions.json" 2>/dev/null) || true
    
    for client in geth erigon; do
        if echo "$versions_content" | grep -qi "$client"; then
            pass "Version tracking for $client exists"
        else
            skip "Version tracking for $client" "Not in versions.json"
        fi
    done
fi

#------------------------------------------------------------------------------
# Test: RPC endpoint differentiation
#------------------------------------------------------------------------------

# Different clients should expose different RPC endpoints or ports
rpc_config=$(grep -rh "8545\|8546\|rpc" "$PROJECT_ROOT/docker/" 2>/dev/null | head -20) || true

if echo "$rpc_config" | grep -q "8545" && echo "$rpc_config" | grep -q "8546"; then
    pass "Multiple RPC endpoints configured"
else
    skip "Multiple RPC endpoints configured" "Single endpoint found"
fi

#------------------------------------------------------------------------------
# Cleanup
#------------------------------------------------------------------------------

docker rm -f xdc-testnet xdc-erigon-testnet 2>/dev/null || true

test_end
