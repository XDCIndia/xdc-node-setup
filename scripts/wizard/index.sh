#!/bin/bash
#==============================================================================
# XDC Node Setup Wizard - Main Entry Point
# Interactive wizard for guided node deployment
#==============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WIZARD_VERSION="1.0.0"

# Configuration storage - using prefixed variables for bash 3.2 compatibility
# Instead of: declare -A WIZARD_CONFIG
WIZARD_CONFIG_network=""
WIZARD_CONFIG_role=""
WIZARD_CONFIG_cloud=""
WIZARD_CONFIG_region=""
WIZARD_CONFIG_instance_type=""

# Helper functions for config access
set_config() {
    local key="$1"
    local value="$2"
    eval "WIZARD_CONFIG_$key=\"$value\""
}

get_config() {
    local key="$1"
    eval "echo \${WIZARD_CONFIG_$key:-}"
}

#==============================================================================
# Colors
#==============================================================================
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    MAGENTA=''
    BOLD=''
    NC=''
fi

#==============================================================================
# UI Detection
#==============================================================================

DIALOG_TOOL=""

init_dialog() {
    if [[ "${1:-}" == "--dialog" ]] || [[ "${1:-}" == "--gui" ]]; then
        if command -v whiptail >/dev/null 2>&1; then
            DIALOG_TOOL="whiptail"
        elif command -v dialog >/dev/null 2>&1; then
            DIALOG_TOOL="dialog"
        fi
    fi
}

#==============================================================================
# Banner
#==============================================================================

print_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
 __  ______   ____  _   _______________________ 
 \ \/ /  _ \ / __ \/ | / / ____/_  __/  _/ __ \
  \  / / / / / / /  |/ / __/   / /  / // /_/ /
  / / /_/ / /_/ / /|  / /___  / / _/ // ____/ 
 /_/_____/\____/_/ |_/_____/ /_/ /___/_/      
                                               
EOF
    echo -e "${NC}"
    echo -e "${BOLD}Interactive Setup Wizard v${WIZARD_VERSION}${NC}"
    echo -e "${BLUE}Guided deployment for XDC Network nodes${NC}"
    echo ""
}

#==============================================================================
# Progress Bar
#==============================================================================

show_wizard_progress() {
    local step=$1
    local total=5
    local label="${2:-Step $step}"
    
    echo ""
    echo -e "${BOLD}Progress:${NC} [$step/$total] $label"
    echo -n "["
    
    for ((i=1; i<=total; i++)); do
        if [[ $i -le $step ]]; then
            echo -n -e "${GREEN}●${NC}"
        else
            echo -n -e "${CYAN}○${NC}"
        fi
        echo -n " "
    done
    
    echo "]"
    echo ""
}

#==============================================================================
# Step 1: Network Selection
#==============================================================================

step_network_select() {
    show_wizard_progress 1 "Network Selection"
    
    local choice
    
    if [[ -n "$DIALOG_TOOL" ]]; then
        # Dialog-based selection
        if [[ "$DIALOG_TOOL" == "whiptail" ]]; then
            choice=$(whiptail --title "Network Selection" \
                --menu "Choose the XDC Network to connect:" 15 60 3 \
                "mainnet" "XDC Mainnet (Production)" \
                "testnet" "Apothem Testnet (Testing)" \
                "devnet" "Devnet (Development)" \
                3>&1 1>&2 2>&3)
        else
            choice=$(dialog --title "Network Selection" \
                --menu "Choose the XDC Network to connect:" 15 60 3 \
                "mainnet" "XDC Mainnet (Production)" \
                "testnet" "Apothem Testnet (Testing)" \
                "devnet" "Devnet (Development)" \
                3>&1 1>&2 2>&3)
        fi
    else
        # Text-based selection
        echo -e "${BOLD}Select Network:${NC}"
        echo ""
        echo "  1) Mainnet - Production XDC Network"
        echo "     Full network participation, requires 10M XDC for masternode"
        echo ""
        echo "  2) Testnet - Apothem Test Network"  
        echo "     Free testing environment, faucet-available XDC"
        echo ""
        echo "  3) Devnet - Local Development Network"
        echo "     Isolated development environment"
        echo ""
        echo -n "Enter choice (1-3): "
        read -r selection
        
        case $selection in
            1) choice="mainnet" ;;
            2) choice="testnet" ;;
            3) choice="devnet" ;;
            *) 
                echo -e "${RED}Invalid choice${NC}"
                sleep 1
                step_network_select
                return
                ;;
        esac
    fi
    
    set_config "network" "$choice"
    
    echo ""
    echo -e "${GREEN}✓${NC} Selected network: ${BOLD}$choice${NC}"
    sleep 1
}

#==============================================================================
# Step 2: Role Selection
#==============================================================================

step_role_select() {
    show_wizard_progress 2 "Node Role"
    
    local choice
    
    if [[ -n "$DIALOG_TOOL" ]]; then
        if [[ "$DIALOG_TOOL" == "whiptail" ]]; then
            choice=$(whiptail --title "Node Role" \
                --menu "Choose your node's role:" 17 70 5 \
                "fullnode" "Full Node - Network participation" \
                "archive" "Archive Node - Historical data" \
                "masternode" "Masternode - Block production (10M XDC required)" \
                "rpc" "RPC Node - API endpoint for dApps" \
                "light" "Light Node - Minimal requirements" \
                3>&1 1>&2 2>&3)
        else
            choice=$(dialog --title "Node Role" \
                --menu "Choose your node's role:" 17 70 5 \
                "fullnode" "Full Node - Network participation" \
                "archive" "Archive Node - Historical data" \
                "masternode" "Masternode - Block production (10M XDC required)" \
                "rpc" "RPC Node - API endpoint for dApps" \
                "light" "Light Node - Minimal requirements" \
                3>&1 1>&2 2>&3)
        fi
    else
        echo -e "${BOLD}Select Node Role:${NC}"
        echo ""
        echo "  1) Full Node"
        echo "     • Verify transactions and blocks"
        echo "     • Participate in network consensus"
        echo "     • Recommended for most users"
        echo "     • Requirements: 4 CPU, 8GB RAM, 500GB storage"
        echo ""
        echo "  2) Archive Node"
        echo "     • Store complete historical state"
        echo "     • Required for historical queries"
        echo "     • Requirements: 8 CPU, 32GB RAM, 2TB+ storage"
        echo ""
        echo "  3) Masternode"
        echo "     • Produce and validate blocks"
        echo "     • Earn rewards (requires 10M XDC stake)"
        echo "     • Requirements: 8 CPU, 32GB RAM, 1TB storage"
        echo ""
        echo "  4) RPC Node"
        echo "     • Serve API requests for dApps"
        echo "     • Optimized for high throughput"
        echo "     • Requirements: 4 CPU, 16GB RAM, 750GB storage"
        echo ""
        echo "  5) Light Node"
        echo "     • Minimal resource requirements"
        echo "     • Limited functionality"
        echo "     • Requirements: 2 CPU, 4GB RAM, 100GB storage"
        echo ""
        echo -n "Enter choice (1-5): "
        read -r selection
        
        case $selection in
            1) choice="fullnode" ;;
            2) choice="archive" ;;
            3) choice="masternode" ;;
            4) choice="rpc" ;;
            5) choice="light" ;;
            *) 
                echo -e "${RED}Invalid choice${NC}"
                sleep 1
                step_role_select
                return
                ;;
        esac
    fi
    
    WIZARD_CONFIG[role]="$choice"
    
    echo ""
    echo -e "${GREEN}✓${NC} Selected role: ${BOLD}$choice${NC}"
    
    if [[ "$choice" == "masternode" ]]; then
        echo -e "${YELLOW}⚠${NC} Note: Masternode requires 10M XDC stake"
        echo -e "${YELLOW}⚠${NC} Ensure you have the required XDC in your wallet"
    fi
    
    sleep 1
}

#==============================================================================
# Step 3: Cloud Provider Selection
#==============================================================================

step_cloud_select() {
    show_wizard_progress 3 "Deployment Method"
    
    local choice
    
    if [[ -n "$DIALOG_TOOL" ]]; then
        if [[ "$DIALOG_TOOL" == "whiptail" ]]; then
            choice=$(whiptail --title "Deployment Method" \
                --menu "Where would you like to deploy?" 15 60 6 \
                "local" "Local Docker (This machine)" \
                "aws" "Amazon Web Services (AWS)" \
                "digitalocean" "DigitalOcean" \
                "azure" "Microsoft Azure" \
                "gcp" "Google Cloud Platform" \
                "existing" "Use existing server" \
                3>&1 1>&2 2>&3)
        else
            choice=$(dialog --title "Deployment Method" \
                --menu "Where would you like to deploy?" 15 60 6 \
                "local" "Local Docker (This machine)" \
                "aws" "Amazon Web Services (AWS)" \
                "digitalocean" "DigitalOcean" \
                "azure" "Microsoft Azure" \
                "gcp" "Google Cloud Platform" \
                "existing" "Use existing server" \
                3>&1 1>&2 2>&3)
        fi
    else
        echo -e "${BOLD}Select Deployment Method:${NC}"
        echo ""
        echo "  1) Local Docker"
        echo "     Deploy on this machine using Docker Compose"
        echo ""
        echo "  2) Amazon Web Services (AWS)"
        echo "     Deploy using CloudFormation"
        echo ""
        echo "  3) DigitalOcean"
        echo "     Deploy using 1-Click App or Droplet"
        echo ""
        echo "  4) Microsoft Azure"
        echo "     Deploy using ARM templates"
        echo ""
        echo "  5) Google Cloud Platform"
        echo "     Deploy using Deployment Manager"
        echo ""
        echo "  6) Existing Server"
        echo "     Configure for manual deployment"
        echo ""
        echo -n "Enter choice (1-6): "
        read -r selection
        
        case $selection in
            1) choice="local" ;;
            2) choice="aws" ;;
            3) choice="digitalocean" ;;
            4) choice="azure" ;;
            5) choice="gcp" ;;
            6) choice="existing" ;;
            *) 
                echo -e "${RED}Invalid choice${NC}"
                sleep 1
                step_cloud_select
                return
                ;;
        esac
    fi
    
    WIZARD_CONFIG[cloud]="$choice"
    
    echo ""
    echo -e "${GREEN}✓${NC} Selected deployment: ${BOLD}$choice${NC}"
    
    # If cloud provider selected, ask for region
    if [[ "$choice" != "local" && "$choice" != "existing" ]]; then
        step_region_select "$choice"
    fi
    
    sleep 1
}

step_region_select() {
    local provider="$1"
    local choice
    
    # Default regions for each provider
    declare -A regions
    regions[aws]="us-east-1"
    regions[digitalocean]="nyc3"
    regions[azure]="eastus"
    regions[gcp]="us-central1"
    
    if [[ -n "$DIALOG_TOOL" ]]; then
        # Simplified region selection
        choice="${regions[$provider]}"
    else
        echo ""
        echo -e "${BOLD}Select Region:${NC}"
        echo ""
        
        case "$provider" in
            aws)
                echo "  1) us-east-1 (N. Virginia)"
                echo "  2) us-west-2 (Oregon)"
                echo "  3) eu-west-1 (Ireland)"
                echo "  4) ap-southeast-1 (Singapore)"
                ;;
            digitalocean)
                echo "  1) nyc3 (New York)"
                echo "  2) sfo3 (San Francisco)"
                echo "  3) ams3 (Amsterdam)"
                echo "  4) sgp1 (Singapore)"
                ;;
            azure)
                echo "  1) eastus (East US)"
                echo "  2) westus2 (West US 2)"
                echo "  3) westeurope (West Europe)"
                echo "  4) southeastasia (Southeast Asia)"
                ;;
            gcp)
                echo "  1) us-central1 (Iowa)"
                echo "  2) us-east1 (S. Carolina)"
                echo "  3) europe-west1 (Belgium)"
                echo "  4) asia-southeast1 (Singapore)"
                ;;
        esac
        
        echo ""
        echo -n "Enter choice (1-4): "
        read -r selection
        
        choice="${regions[$provider]}"
    fi
    
    WIZARD_CONFIG[region]="$choice"
    echo -e "${GREEN}✓${NC} Selected region: ${BOLD}$choice${NC}"
}

#==============================================================================
# Step 4: Configuration Review
#==============================================================================

step_config_review() {
    show_wizard_progress 4 "Configuration Review"
    
    if [[ -n "$DIALOG_TOOL" ]]; then
        local text="Configuration Summary:\n\n"
        text+="Network: ${WIZARD_CONFIG[network]}\n"
        text+="Role: ${WIZARD_CONFIG[role]}\n"
        text+="Deployment: ${WIZARD_CONFIG[cloud]}\n"
        [[ -n "${WIZARD_CONFIG[region]}" ]] && text+="Region: ${WIZARD_CONFIG[region]}\n"
        text+="\nProceed with deployment?"
        
        if [[ "$DIALOG_TOOL" == "whiptail" ]]; then
            whiptail --title "Review Configuration" \
                --yesno "$text" 15 60 \
                --yes-button "Deploy" \
                --no-button "Back"
            if [[ $? -ne 0 ]]; then
                return 1
            fi
        else
            dialog --title "Review Configuration" \
                --yesno "$text" 15 60
            if [[ $? -ne 0 ]]; then
                return 1
            fi
        fi
    else
        echo -e "${BOLD}Configuration Summary:${NC}"
        echo "================================"
        echo ""
        printf "  %-20s %s\n" "Network:" "${WIZARD_CONFIG[network]}"
        printf "  %-20s %s\n" "Node Role:" "${WIZARD_CONFIG[role]}"
        printf "  %-20s %s\n" "Deployment:" "${WIZARD_CONFIG[cloud]}"
        [[ -n "${WIZARD_CONFIG[region]}" ]] && printf "  %-20s %s\n" "Region:" "${WIZARD_CONFIG[region]}"
        echo ""
        echo "================================"
        echo ""
        
        echo -n "Proceed with deployment? [Y/n]: "
        read -r confirm
        
        if [[ "$confirm" =~ ^[Nn]$ ]]; then
            echo ""
            echo "Returning to previous steps..."
            sleep 1
            return 1
        fi
    fi
    
    return 0
}

#==============================================================================
# Step 5: Deploy
#==============================================================================

step_deploy() {
    show_wizard_progress 5 "Deployment"
    
    echo ""
    echo -e "${BOLD}Starting deployment...${NC}"
    echo ""
    
    # Save configuration to file
    local config_file="/tmp/xdc-wizard-config.json"
    cat > "$config_file" << EOF
{
  "network": "${WIZARD_CONFIG[network]}",
  "role": "${WIZARD_CONFIG[role]}",
  "cloud": "${WIZARD_CONFIG[cloud]}",
  "region": "${WIZARD_CONFIG[region]}",
  "timestamp": "$(date -Iseconds)"
}
EOF
    
    # Call deploy script
    export WIZARD_CONFIG_FILE="$config_file"
    bash "${SCRIPT_DIR}/deploy.sh"
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}${BOLD}✓ Deployment complete!${NC}"
        echo ""
        echo "Next steps:"
        echo "  • Check status: xdc-status"
        echo "  • View logs: xdc-logs"
        echo "  • Documentation: https://docs.xdc.network"
    else
        echo ""
        echo -e "${RED}${BOLD}✗ Deployment failed${NC}"
        echo ""
        echo "Check the logs above for errors."
        echo "For help, visit: https://github.com/XDC-Node-Setup/issues"
    fi
    
    return $exit_code
}

#==============================================================================
# Main Wizard Flow
#==============================================================================

main() {
    init_dialog "${1:-}"
    
    # Check if being sourced
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    fi
    
    print_banner
    
    local step=1
    local max_steps=5
    
    while [[ $step -le $max_steps ]]; do
        case $step in
            1)
                step_network_select
                ((step++))
                ;;
            2)
                step_role_select
                ((step++))
                ;;
            3)
                step_cloud_select
                ((step++))
                ;;
            4)
                if step_config_review; then
                    ((step++))
                else
                    # Go back
                    step=$((step - 1))
                fi
                ;;
            5)
                step_deploy
                exit $?
                ;;
        esac
    done
}

main "$@"
