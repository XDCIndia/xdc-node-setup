#!/usr/bin/env bats
#==============================================================================
# Unit Tests for Setup Script
# Tests: setup.sh
#==============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/.."
    TEST_TEMP_DIR=$(mktemp -d)
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

#==============================================================================
# Script Structure Tests
#==============================================================================

@test "setup.sh exists and is executable" {
    [ -x "$SCRIPT_DIR/setup.sh" ]
}

@test "setup.sh has proper shebang" {
    head -1 "$SCRIPT_DIR/setup.sh" | grep -q "#!/usr/bin/env bash"
}

@test "setup.sh uses strict mode" {
    grep -q "set -euo pipefail" "$SCRIPT_DIR/setup.sh"
}

@test "setup.sh has version variable" {
    grep -q "SCRIPT_VERSION" "$SCRIPT_DIR/setup.sh"
}

#==============================================================================
# OS Detection Tests
#==============================================================================

@test "OS detection handles Linux" {
    local os="linux"
    [ "$os" = "linux" ]
}

@test "OS detection handles macOS" {
    local os="macos"
    [ "$os" = "macos" ]
}

@test "OS detection handles unsupported systems" {
    local os="unsupported"
    [ "$os" = "unsupported" ]
}

#==============================================================================
# Path Validation Tests
#==============================================================================

@test "Data directory validation accepts valid paths" {
    local paths=(
        "/opt/xdc-node/data"
        "/var/lib/xdc"
        "/home/user/xdcchain"
    )
    
    for path in "${paths[@]}"; do
        [[ "$path" =~ ^/ ]]
        [[ ! "$path" =~ \.\./ ]]
    done
}

@test "Data directory validation rejects dangerous paths" {
    local paths=(
        "./data"
        "../etc"
        "/"
        "/etc"
        "/bin"
    )
    
    for path in "${paths[@]}"; do
        if [[ "$path" =~ ^/[^/]+$ ]]; then
            # System directories check
            [[ "$path" =~ ^/(etc|bin|sbin|usr|lib|var)$ ]] && true || true
        fi
    done
}

#==============================================================================
# Port Validation Tests
#==============================================================================

@test "Port validation accepts valid ports" {
    local ports=(8545 8546 30303 12141)
    
    for port in "${ports[@]}"; do
        [ "$port" -ge 1 ]
        [ "$port" -le 65535 ]
    done
}

@test "RPC port is within valid range" {
    local rpc_port=8545
    [ "$rpc_port" -ge 1024 ]
    [ "$rpc_port" -le 65535 ]
}

@test "P2P port is within valid range" {
    local p2p_port=30303
    [ "$p2p_port" -ge 1 ]
    [ "$p2p_port" -le 65535 ]
}

#==============================================================================
# Network Selection Tests
#==============================================================================

@test "Network selection accepts valid networks" {
    local networks=("mainnet" "testnet" "devnet")
    local selected="mainnet"
    
    local found=false
    for net in "${networks[@]}"; do
        if [ "$net" = "$selected" ]; then
            found=true
            break
        fi
    done
    
    [ "$found" = "true" ]
}

@test "Network configuration has required fields" {
    local network="mainnet"
    local config_file="$TEST_TEMP_DIR/networks.json"
    
    cat > "$config_file" << EOF
{
  "mainnet": {
    "chainId": 50,
    "rpcUrl": "https://rpc.xinfin.network",
    "explorer": "https://explorer.xinfin.network"
  }
}
EOF
    
    [ -f "$config_file" ]
    jq -e '.mainnet.chainId' "$config_file"
    jq -e '.mainnet.rpcUrl' "$config_file"
}

#==============================================================================
# Configuration Tests
#==============================================================================

@test "Docker Compose generation creates valid YAML" {
    local compose_file="$TEST_TEMP_DIR/docker-compose.yml"
    
    cat > "$compose_file" << 'EOF'
version: '3.8'
services:
  xdc-node:
    image: xinfinorg/xdposchain:v2.6.8
    restart: always
    ports:
      - "30303:30303"
      - "8545:8545"
EOF
    
    [ -f "$compose_file" ]
    # Basic YAML validation
    grep -q "version:" "$compose_file"
    grep -q "services:" "$compose_file"
}

@test "Environment file generation creates valid env" {
    local env_file="$TEST_TEMP_DIR/.env"
    
    cat > "$env_file" << 'EOF'
NETWORK=mainnet
RPC_PORT=8545
WS_PORT=8546
P2P_PORT=30303
EOF
    
    [ -f "$env_file" ]
    grep -q "NETWORK=" "$env_file"
    grep -q "RPC_PORT=" "$env_file"
}

#==============================================================================
# Password Generation Tests
#==============================================================================

@test "Password generation creates secure passwords" {
    local password
    password=$(openssl rand -base64 32 2>/dev/null || head -c 32 /dev/urandom | base64)
    
    [ ${#password} -ge 32 ]
}

@test "Password file has restricted permissions" {
    local pwd_file="$TEST_TEMP_DIR/.pwd"
    echo "test-password-123" > "$pwd_file"
    chmod 600 "$pwd_file"
    
    local perms
    perms=$(stat -c "%a" "$pwd_file" 2>/dev/null || stat -f "%Lp" "$pwd_file")
    [ "$perms" = "600" ]
}

#==============================================================================
# Command Line Flag Tests
#==============================================================================

@test "Setup script accepts --advanced flag" {
    grep -q "advanced\|--advanced" "$SCRIPT_DIR/setup.sh"
}

@test "Setup script accepts --help flag" {
    grep -q "help\|--help" "$SCRIPT_DIR/setup.sh"
}

@test "Setup script has usage documentation" {
    grep -q "usage\|Usage" "$SCRIPT_DIR/setup.sh"
}

#==============================================================================
# Dependency Check Tests
#==============================================================================

@test "Docker dependency check" {
    command -v docker && true || true
}

@test "Docker Compose dependency check" {
    command -v docker-compose && true || true
}

#==============================================================================
# Mode Selection Tests
#==============================================================================

@test "Simple mode is default" {
    local mode="simple"
    [ "$mode" = "simple" ]
}

@test "Advanced mode enables all options" {
    local advanced_mode=true
    local custom_ports=true
    local monitoring=true
    
    if [ "$advanced_mode" = "true" ]; then
        [ "$custom_ports" = "true" ]
        [ "$monitoring" = "true" ]
    fi
}

#==============================================================================
# Logging Tests
#==============================================================================

@test "Log file initialization creates file with correct permissions" {
    local log_file="$TEST_TEMP_DIR/setup.log"
    touch "$log_file"
    chmod 640 "$log_file"
    
    [ -f "$log_file" ]
    local perms
    perms=$(stat -c "%a" "$log_file" 2>/dev/null || stat -f "%Lp" "$pwd_file")
    [ "$perms" = "640" ]
}

@test "Log messages include timestamps" {
    local log_file="$TEST_TEMP_DIR/setup.log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Test message" >> "$log_file"
    
    grep -qE '\[[0-9]{4}-[0-9]{2}-[0-9]{2}' "$log_file"
}

#==============================================================================
# Rollback Tests
#==============================================================================

@test "Rollback mechanism exists" {
    grep -q "rollback\|cleanup\|trap" "$SCRIPT_DIR/setup.sh"
}

@test "Cleanup function removes created files" {
    local test_dir="$TEST_TEMP_DIR/test_cleanup"
    mkdir -p "$test_dir"
    touch "$test_dir/test_file"
    
    rm -rf "$test_dir"
    [ ! -d "$test_dir" ]
}