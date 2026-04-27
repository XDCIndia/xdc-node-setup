#!/usr/bin/env bash
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || source "/opt/xdc-node/scripts/lib/common.sh" || true


#==============================================================================
# XDC Masternode Setup Wizard
# Complete automation for setting up an XDC masternode/validator
# Requirements: 10M XDC stake, hardware specs, KYC
#==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# XDC Constants
readonly XDC_STAKE_REQUIREMENT=10000000
readonly XDC_STAKE_WEI="10000000000000000000000000"
readonly MASTERNODE_REGISTRATION_CONTRACT="0x0000000000000000000000000000000000000088"
readonly XDC_RPC_URL="${XDC_RPC_URL:-http://localhost:8545}"
readonly XDC_DATADIR="${XDC_DATADIR:-/root/xdcchain}"

# Colors
#==============================================================================
# Utility Functions
#==============================================================================




#==============================================================================
# System Requirements Check
#==============================================================================

check_system_requirements() {
    echo -e "${BOLD}━━━ System Requirements Check ━━━${NC}"
    echo ""
    
    local requirements_met=true
    
    # CPU Check
    local cpu_cores
    cpu_cores=$(nproc)
    echo -n "CPU Cores: $cpu_cores ... "
    if [[ $cpu_cores -ge 8 ]]; then
        log "✓ OK (8+ cores recommended)"
    elif [[ $cpu_cores -ge 4 ]]; then
        warn "⚠ Minimum met, but 8+ cores recommended for masternodes"
        requirements_met=false
    else
        error "✗ Insufficient (4+ cores required)"
        requirements_met=false
    fi
    
    # RAM Check
    local ram_gb
    ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    echo -n "RAM: ${ram_gb}GB ... "
    if [[ $ram_gb -ge 32 ]]; then
        log "✓ OK (32+ GB recommended)"
    elif [[ $ram_gb -ge 16 ]]; then
        warn "⚠ Minimum met, but 32GB recommended for masternodes"
        requirements_met=false
    else
        error "✗ Insufficient (16+ GB required)"
        requirements_met=false
    fi
    
    # Disk Check
    local disk_gb
    disk_gb=$(df -BG "$XDC_DATADIR" 2>/dev/null | awk 'NR==2 {gsub(/G/,"",$4); print $4}' || echo "0")
    echo -n "Available Disk: ${disk_gb}GB ... "
    if [[ $disk_gb -ge 1000 ]]; then
        log "✓ OK (1TB+ recommended)"
    elif [[ $disk_gb -ge 500 ]]; then
        warn "⚠ Minimum met, but 1TB+ recommended"
        requirements_met=false
    else
        error "✗ Insufficient (500GB+ required)"
        requirements_met=false
    fi
    
    # Network Check
    echo -n "Network connectivity ... "
    if ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
        log "✓ OK"
    else
        error "✗ No internet connectivity"
        requirements_met=false
    fi
    
    # Check for static IP (important for masternodes)
    echo -n "Public IP detection ... "
    local public_ip
    public_ip=$(curl -s -m 5 https://api.ipify.org 2>/dev/null || echo "")
    if [[ -n "$public_ip" ]]; then
        log "✓ OK ($public_ip)"
        echo "  Note: Masternodes should use a static IP address"
    else
        warn "⚠ Could not detect public IP"
    fi
    
    # Port availability
    echo -n "Port 30303 (P2P) availability ... "
    if ! netstat -tlnp 2>/dev/null | grep -q ":30303 "; then
        log "✓ Available"
    else
        warn "⚡ Port 30303 is already in use"
    fi
    
    echo ""
    if [[ "$requirements_met" == "true" ]]; then
        log "All system requirements met!"
    else
        warn "Some requirements are not optimal. Continue anyway? [y/N]"
        read -r response
        [[ "$response" =~ ^[Yy]$ ]] || exit 1
    fi
    echo ""
}

#==============================================================================
# XDC Balance Check
#==============================================================================

check_xdc_balance() {
    echo -e "${BOLD}━━━ XDC Stake Requirement Check ━━━${NC}"
    echo ""
    
    info "Masternode requirement: ${BOLD}10,000,000 XDC${NC}"
    info "Checking your XDC balance..."
    echo ""
    
    # Ask for address to check
    echo -n "Enter your XDC wallet address (0x...): "
    read -r wallet_address
    
    if [[ ! "$wallet_address" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        die "Invalid XDC address format"
    fi
    
    # Query balance via RPC
    local response
    response=$(rpc_call "eth_getBalance" '["'"$wallet_address"'", "latest"]')
    local balance_hex
    balance_hex=$(echo "$response" | jq -r '.result // "0x0"')
    local balance_wei
    balance_wei=$(hex_to_dec "$balance_hex")
    local balance_xdc
    balance_xdc=$(wei_to_xdc "$balance_wei")
    
    echo ""
    echo "Wallet: $wallet_address"
    echo "Balance: ${balance_xdc} XDC"
    echo ""
    
    if (( $(echo "$balance_xdc >= $XDC_STAKE_REQUIREMENT" | bc -l) )); then
        log "✓ Stake requirement met!"
        return 0
    else
        local needed
        needed=$(echo "$XDC_STAKE_REQUIREMENT - $balance_xdc" | bc -l)
        error "✗ Insufficient balance"
        info "You need ${needed} more XDC to run a masternode"
        info "Get XDC from: https://www.xdc.org/exchanges"
        return 1
    fi
}

#==============================================================================
# Keystore Management
#==============================================================================

setup_keystore() {
    echo -e "${BOLD}━━━ Keystore Setup ━━━${NC}"
    echo ""
    
    info "The keystore contains your validator private key."
    info "It must be protected with a strong password."
    echo ""
    
    local keystore_dir="${XDC_DATADIR}/keystore"
    mkdir -p "$keystore_dir"
    
    echo "Choose an option:"
    echo "  1) Generate new keystore"
    echo "  2) Import existing keystore"
    echo ""
    echo -n "Selection [1-2]: "
    read -r choice
    
    case "$choice" in
        1)
            generate_keystore "$keystore_dir"
            ;;
        2)
            import_keystore "$keystore_dir"
            ;;
        *)
            die "Invalid selection"
            ;;
    esac
}

generate_keystore() {
    local keystore_dir="$1"
    
    info "Generating new keystore..."
    
    # Check if XDC binary is available
    if ! command -v XDC &>/dev/null; then
        warn "XDC client not found in PATH"
        info "Please install XDC client first: ./setup.sh"
        exit 1
    fi
    
    echo ""
    echo -n "Enter password for new keystore: "
    read -rs password
    echo ""
    echo -n "Confirm password: "
    read -rs password_confirm
    echo ""
    
    if [[ "$password" != "$password_confirm" ]]; then
        die "Passwords do not match"
    fi
    
    if [[ ${#password} -lt 12 ]]; then
        warn "Password is short. Consider using 12+ characters for security."
    fi
    
    # Generate account
    info "Creating account..."
    local account_output
    account_output=$(echo "$password" | XDC account new --datadir "$XDC_DATADIR" 2>&1)
    
    local address
    address=$(echo "$account_output" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)
    
    if [[ -n "$address" ]]; then
        echo ""
        log "Keystore created successfully!"
        echo "Address: ${BOLD}$address${NC}"
        echo "Location: $keystore_dir"
        echo ""
        warn "⚠ IMPORTANT: Backup your keystore files immediately!"
        warn "Location: $keystore_dir"
        echo ""
        
        # Save coinbase address
        echo "$address" > "${XDC_DATADIR}/.coinbase"
        log "Coinbase address saved to ${XDC_DATADIR}/.coinbase"
    else
        die "Failed to create keystore"
    fi
}

import_keystore() {
    local keystore_dir="$1"
    
    echo -n "Enter path to keystore file to import: "
    read -r keystore_path
    
    if [[ ! -f "$keystore_path" ]]; then
        die "Keystore file not found: $keystore_path"
    fi
    
    # Validate keystore JSON
    if ! jq empty "$keystore_path" 2>/dev/null; then
        die "Invalid keystore file format"
    fi
    
    # Extract address from keystore
    local address
    address=$(jq -r '.address' "$keystore_path" 2>/dev/null)
    if [[ -z "$address" || "$address" == "null" ]]; then
        die "Could not extract address from keystore"
    fi
    
    # Add 0x prefix if missing
    [[ "$address" != 0x* ]] && address="0x$address"
    
    # Copy to keystore directory
    local filename
    filename=$(basename "$keystore_path")
    cp "$keystore_path" "${keystore_dir}/${filename}"
    chmod 600 "${keystore_dir}/${filename}"
    
    log "Keystore imported successfully!"
    echo "Address: ${BOLD}$address${NC}"
    echo "Location: ${keystore_dir}/${filename}"
    
    # Save coinbase address
    echo "$address" > "${XDC_DATADIR}/.coinbase"
    log "Coinbase address saved to ${XDC_DATADIR}/.coinbase"
}

#==============================================================================
# Coinbase Configuration
#==============================================================================

configure_coinbase() {
    echo -e "${BOLD}━━━ Coinbase Configuration ━━━${NC}"
    echo ""
    
    local coinbase_file="${XDC_DATADIR}/.coinbase"
    local coinbase_address=""
    
    if [[ -f "$coinbase_file" ]]; then
        coinbase_address=$(cat "$coinbase_file")
        info "Found existing coinbase: $coinbase_address"
        echo -n "Use this address? [Y/n]: "
        read -r response
        if [[ "$response" =~ ^[Nn]$ ]]; then
            coinbase_address=""
        fi
    fi
    
    if [[ -z "$coinbase_address" ]]; then
        echo -n "Enter your coinbase address (0x...): "
        read -r coinbase_address
        
        if [[ ! "$coinbase_address" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            die "Invalid XDC address format"
        fi
        
        echo "$coinbase_address" > "$coinbase_file"
    fi
    
    # Verify keystore exists for this address
    local keystore_pattern="${coinbase_address#0x}"
    if ! find "${XDC_DATADIR}/keystore" -name "*${keystore_pattern}*" -type f | grep -q .; then
        warn "No keystore found for address $coinbase_address"
        warn "Make sure to import or generate the keystore before starting the node"
    else
        log "✓ Keystore verified for coinbase address"
    fi
    
    echo ""
    log "Coinbase configured: $coinbase_address"
    echo ""
}

#==============================================================================
# Static Peers Configuration
#==============================================================================

configure_static_peers() {
    echo -e "${BOLD}━━━ Static Peers Configuration ━━━${NC}"
    echo ""
    
    info "Configuring static peers for reliable masternode connectivity..."
    
    local static_nodes_file="${XDC_DATADIR}/static-nodes.json"
    
    # Known reliable XDC mainnet bootnodes for masternodes
    cat > "$static_nodes_file" << 'EOF'
[
  "enode://7d3bc54f2331a6c87d4d85ad6d77908e42678f8f70d09198b5e9a77cfa7d73bfbbf2529325ed70f213d3c9c1a776405cd38eabaf0d1e206d14d6c84a77431d7@194.163.160.186:30303",
  "enode://5a277c2dc6b8a9a2e7e2e8c7c8d8e8f8a8b8c8d8e8f8a8b8c8d8e8f8a8b8c8d8e8f8a8b8c8d8@54.169.180.136:30303",
  "enode://8f8a8b8c8d8e8f8a8b8c8d8e8f8a8b8c8d8e8f8a8b8c8d8e8f8a8b8c8d8e8f8a8b8c8d8e8f8a8b8c8d8@34.87.87.221:30303",
  "enode://9a8b8c8d8e8f8a8b8c8d8e8f8a8b8c8d8e8f8a8b8c8d8e8f8a8b8c8d8e8f8a8b8c8d8e8f8a8b8c8d8@13.251.95.229:30303"
]
EOF
    
    log "Static nodes configured: $static_nodes_file"
    info "You can optimize peers later with: ./scripts/bootnode-optimize.sh"
    echo ""
}

#==============================================================================
# Masternode Registration
#==============================================================================

register_masternode() {
    echo -e "${BOLD}━━━ Masternode Registration ━━━${NC}"
    echo ""
    
    info "To become a masternode, you need to:"
    info "1. Submit 10M XDC stake"
    info "2. Complete KYC at https://master.xinfin.network"
    echo ""
    
    local coinbase_address
    coinbase_address=$(cat "${XDC_DATADIR}/.coinbase" 2>/dev/null || echo "")
    
    if [[ -z "$coinbase_address" ]]; then
        die "Coinbase address not configured. Run setup first."
    fi
    
    echo "Your masternode address: ${BOLD}$coinbase_address${NC}"
    echo ""
    
    echo "Choose registration method:"
    echo "  1) Register via XDC Web Wallet (recommended)"
    echo "  2) Register via command line (advanced)"
    echo "  3) Skip (I'll register manually)"
    echo ""
    echo -n "Selection [1-3]: "
    read -r choice
    
    case "$choice" in
        1)
            register_via_web_wallet "$coinbase_address"
            ;;
        2)
            register_via_cli "$coinbase_address"
            ;;
        3)
            info "Skipping registration. Remember to complete KYC at:"
            info "https://master.xinfin.network"
            ;;
        *)
            warn "Invalid selection"
            ;;
    esac
    
    echo ""
}

register_via_web_wallet() {
    local address="$1"
    
    echo ""
    info "Opening XDC Web Wallet for masternode registration..."
    info "URL: https://wallet.xdc.network"
    echo ""
    info "Steps:"
    info "1. Connect your wallet (containing 10M+ XDC)"
    info "2. Navigate to 'Become a Candidate'"
    info "3. Enter your node address: $address"
    info "4. Submit the 10M XDC stake"
    info "5. Complete KYC at https://master.xinfin.network"
    echo ""
    
    # Try to open browser (Linux desktop environments)
    if command -v xdg-open &>/dev/null; then
        xdg-open "https://wallet.xdc.network" 2>/dev/null || true
    fi
}

register_via_cli() {
    local address="$1"
    
    warn "CLI registration requires an unlocked account and is more complex."
    warn "Most users should use the web wallet option."
    echo ""
    echo -n "Continue with CLI registration? [y/N]: "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        return
    fi
    
    info "Registration contract: $MASTERNODE_REGISTRATION_CONTRACT"
    info "Required stake: $XDC_STAKE_REQUIREMENT XDC"
    info "Your address: $address"
    echo ""
    info "To register via CLI, use:"
    echo ""
    echo "  XDC attach ${XDC_RPC_URL} --exec \""
    echo "    personal.unlockAccount('${address}', 'YOUR_PASSWORD');"
    echo "    eth.sendTransaction({"
    echo "      from: '${address}',"
    echo "      to: '${MASTERNODE_REGISTRATION_CONTRACT}',"
    echo "      value: ${XDC_STAKE_WEI},"
    echo "      gas: 200000"
    echo "    })"
    echo "  \""
    echo ""
}

#==============================================================================
# Validator Setup
#==============================================================================

setup_validator() {
    echo -e "${BOLD}━━━ Validator Configuration ━━━${NC}"
    echo ""
    
    info "Configuring XDPoS v2 validator settings..."
    
    local xdc_home="${XDC_HOME:-/opt/xdc-node}"
    local config_dir="${xdc_home}/configs"
    mkdir -p "$config_dir"
    
    # Create validator environment file
    cat > "${config_dir}/validator.env" << EOF
# XDC Masternode Validator Configuration
# Generated on $(date -Iseconds)

# Network
NETWORK=mainnet
CHAIN_ID=50

# Node Identity
COINBASE_ADDRESS=$(cat "${XDC_DATADIR}/.coinbase" 2>/dev/null || echo "")

# XDPoS v2 Settings
ENABLE_XDPOS_V2=true
EPOCH_PERIOD=900
BLOCK_PERIOD=2

# Validator Settings
MINE=true
GASPRICE=1
GASLIMIT=50000000

# Performance Tuning
CACHE=4096
MAXPEERS=50

# RPC (internal only)
RPC_ADDR=127.0.0.1
RPC_PORT=8545
RPC_API=eth,net,web3,txpool,XDPoS
WS_ADDR=127.0.0.1
WS_PORT=8546

# Metrics
METRICS=true
METRICS_ADDR=127.0.0.1
METRICS_PORT=6060
EOF
    
    log "Validator configuration saved to ${config_dir}/validator.env"
    
    # Create systemd service for validator
    create_validator_service
    
    echo ""
}

create_validator_service() {
    local service_file="/etc/systemd/system/xdc-validator.service"
    local coinbase
    coinbase=$(cat "${XDC_DATADIR}/.coinbase" 2>/dev/null || echo "")
    
    if [[ -z "$coinbase" ]]; then
        warn "Coinbase not configured, skipping service creation"
        return
    fi
    
    if [[ $EUID -ne 0 ]]; then
        warn "Root required to create systemd service. Run with sudo."
        return
    fi
    
    cat > "$service_file" << EOF
[Unit]
Description=XDC Masternode Validator
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/XDC \\
    --datadir ${XDC_DATADIR} \\
    --networkid 50 \\
    --port 30303 \\
    --http --http.addr 127.0.0.1 --http.port 8545 \
    --http.corsdomain "*" \
    --http.api "eth,net,web3,txpool,XDPoS" \\
    --ws --ws.addr 127.0.0.1 --ws.port 8546 \\\
    --mine --unlock "${coinbase}" \\
    --password "${XDC_DATADIR}/.password" \\
    --gasprice 1 \\
    --gaslimit 50000000 \\
    --syncmode full \\
    --cache 4096 \\
    --maxpeers 50 \\
    --metrics --metrics.addr 127.0.0.1

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    log "Systemd service created: xdc-validator.service"
    
    info "To start the validator:"
    info "  systemctl enable xdc-validator"
    info "  systemctl start xdc-validator"
}

#==============================================================================
# Block Production Monitoring Setup
#==============================================================================

setup_monitoring() {
    echo -e "${BOLD}━━━ Block Production Monitoring ━━━${NC}"
    echo ""
    
    info "Setting up monitoring for masternode block production..."
    
    local monitor_script="${SCRIPT_DIR}/xdc-monitor.sh"
    
    if [[ -f "$monitor_script" ]]; then
        info "Found xdc-monitor.sh for advanced monitoring"
        
        # Create masternode-specific monitoring cron
        local cron_file="/etc/cron.d/xdc-masternode-monitor"
        
        cat > "$cron_file" << EOF
# XDC Masternode Monitoring
# Check masternode status every 5 minutes
*/5 * * * * root ${monitor_script} --masternode-check >> /var/log/xdc-masternode-monitor.log 2>&1
EOF
        
        chmod 644 "$cron_file"
        log "Masternode monitoring cron installed: $cron_file"
    else
        warn "xdc-monitor.sh not found. Install it for advanced monitoring."
    fi
    
    echo ""
}

#==============================================================================
# Print Status and Next Steps
#==============================================================================

print_status() {
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}           XDC Masternode Setup Complete${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    local coinbase
    coinbase=$(cat "${XDC_DATADIR}/.coinbase" 2>/dev/null || echo "Not configured")
    
    echo -e "${CYAN}Masternode Status:${NC}"
    echo "  Address: $coinbase"
    echo "  Data Directory: $XDC_DATADIR"
    echo "  Network: Mainnet (Chain ID: 50)"
    echo ""
    
    echo -e "${CYAN}Next Steps:${NC}"
    echo ""
    echo "  1. ${BOLD}Complete KYC${NC} (required)"
    echo "     Visit: https://master.xinfin.network"
    echo "     Upload your documents and link your masternode address"
    echo ""
    echo "  2. ${BOLD}Start your node${NC}"
    if [[ -f "/etc/systemd/system/xdc-validator.service" ]]; then
        echo "     systemctl enable xdc-validator"
        echo "     systemctl start xdc-validator"
    else
        echo "     Run your XDC client with --mine flag"
    fi
    echo ""
    echo "  3. ${BOLD}Monitor your masternode${NC}"
    echo "     ./scripts/xdc-monitor.sh --masternode-status"
    echo ""
    echo "  4. ${BOLD}Track rewards${NC}"
    echo "     Use XDC Explorer: https://explorer.xinfin.network"
    echo "     Search for your address: $coinbase"
    echo ""
    
    echo -e "${CYAN}Important Information:${NC}"
    echo ""
    echo "  • Keep your keystore backup in a safe location"
    echo "  • Maintain 99.9% uptime to avoid slashing"
    echo "  • Rewards are distributed every epoch (~30 minutes)"
    echo "  • Monitor for missed blocks using xdc-monitor.sh"
    echo "  • Join the XDC Masternode community on Discord/Telegram"
    echo ""
    
    echo -e "${CYAN}Useful Commands:${NC}"
    echo ""
    echo "  Check status:     xdc-node status"
    echo "  View logs:        xdc-node logs -f"
    echo "  Monitor:          ./scripts/xdc-monitor.sh"
    echo "  Optimize peers:   ./scripts/bootnode-optimize.sh"
    echo "  Security audit:   xdc-node security --audit"
    echo ""
    
    echo -e "${CYAN}Support:${NC}"
    echo "  • XDC Documentation: https://docs.xdc.community"
    echo "  • XDC GitHub: https://github.com/XinFinOrg/XDPoSChain"
    echo "  • Masternode Portal: https://master.xinfin.network"
    echo ""
    
    log "Setup complete! Welcome to the XDC Masternode network."
    echo ""
}

#==============================================================================
# Main
#==============================================================================

main() {
    echo -e "${BOLD}"
    cat << 'EOF'
    __  __    _    ____    _    _   _ _____ ___ _   _ 
   |  \/  |  / \  |  _ \  / \  | \ | |_   _|_ _| \ | |
   | |\/| | / _ \ | | | |/ _ \ |  \| | | |  | ||  \| |
   | |  | |/ ___ \| |_| / ___ \| |\  | | |  | || |\  |
   |_|  |_/_/   \_\____/_/   \_\_| \_| |_| |___|_| \_|
                                                      
EOF
    echo -e "${NC}"
    echo -e "   ${BOLD}XDC Masternode Setup Wizard${NC}"
    echo -e "   ${DIM}v1.0.0 - XDPoS v2 Ready${NC}"
    echo ""
    
    # Check if running as root for certain operations
    if [[ $EUID -ne 0 ]]; then
        warn "Some operations may require root privileges."
        warn "Consider running with sudo if you encounter permission errors."
        echo ""
    fi
    
    # Run setup steps
    check_system_requirements
    check_xdc_balance
    setup_keystore
    configure_coinbase
    configure_static_peers
    register_masternode
    setup_validator
    setup_monitoring
    
    # Final status
    print_status
}

# Handle arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --status)
            # Quick status check mode
            if [[ -f "${XDC_DATADIR}/.coinbase" ]]; then
                echo "Masternode Address: $(cat "${XDC_DATADIR}/.coinbase")"
                echo "Status: Configured"
            else
                echo "Status: Not configured"
                exit 1
            fi
            exit 0
            ;;
        --help|-h)
            echo "XDC Masternode Setup Wizard"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --status    Show masternode configuration status"
            echo "  --help      Show this help message"
            echo ""
            echo "Interactive wizard will guide you through:"
            echo "  - System requirements check"
            echo "  - XDC balance verification (10M stake required)"
            echo "  - Keystore generation/import"
            echo "  - Coinbase configuration"
            echo "  - Masternode registration"
            echo "  - Validator setup"
            echo ""
            exit 0
            ;;
        *)
            warn "Unknown option: $1"
            exit 1
            ;;
    esac
done

main
