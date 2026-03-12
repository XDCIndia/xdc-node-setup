#!/bin/bash

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }
#==============================================================================
#==============================================================================
# Interactive TUI Mode for XDC Node Setup
# Uses whiptail/dialog for interactive configuration
#==============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/lib"

# Source libraries
# shellcheck source=/dev/null
source "${LIB_DIR}/banners.sh" 2>/dev/null || true
source "${LIB_DIR}/logging.sh" 2>/dev/null || true

# TUI Configuration
readonly DIALOG_HEIGHT=20
readonly DIALOG_WIDTH=70
readonly DIALOG_LIST_HEIGHT=10

# Check if whiptail or dialog is available
detect_dialog_tool() {
    if command -v whiptail >/dev/null 2>&1; then
        echo "whiptail"
    elif command -v dialog >/dev/null 2>&1; then
        echo "dialog"
    else
        echo "none"
    fi
}

readonly DIALOG_TOOL=$(detect_dialog_tool)

#==============================================================================
# Dialog Helper Functions
#==============================================================================

# Show message box
show_msgbox() {
    local title="$1"
    local message="$2"

    case "$DIALOG_TOOL" in
        whiptail)
            whiptail --title "$title" --msgbox "$message" "$DIALOG_HEIGHT" "$DIALOG_WIDTH"
            ;;
        dialog)
            dialog --title "$title" --msgbox "$message" "$DIALOG_HEIGHT" "$DIALOG_WIDTH"
            ;;
        *)
            echo -e "\n=== $title ==="
            echo "$message"
            echo "Press Enter to continue..."
            read -r
            ;;
    esac
}

# Show yes/no dialog
show_yesno() {
    local title="$1"
    local message="$2"

    case "$DIALOG_TOOL" in
        whiptail)
            whiptail --title "$title" --yesno "$message" "$DIALOG_HEIGHT" "$DIALOG_WIDTH"
            return $?
            ;;
        dialog)
            dialog --title "$title" --yesno "$message" "$DIALOG_HEIGHT" "$DIALOG_WIDTH"
            return $?
            ;;
        *)
            echo -e "\n=== $title ==="
            echo "$message (y/n)"
            read -r response
            [[ "$response" =~ ^[Yy]$ ]]
            return $?
            ;;
    esac
}

# Show input box
show_input() {
    local title="$1"
    local message="$2"
    local default="${3:-}"

    case "$DIALOG_TOOL" in
        whiptail)
            whiptail --title "$title" --inputbox "$message" "$DIALOG_HEIGHT" "$DIALOG_WIDTH" "$default" 3>&1 1>&2 2>&3
            ;;
        dialog)
            dialog --title "$title" --inputbox "$message" "$DIALOG_HEIGHT" "$DIALOG_WIDTH" "$default" 3>&1 1>&2 2>&3
            ;;
        *)
            echo -e "\n=== $title ==="
            echo "$message"
            echo -n "[$default]: "
            read -r response
            echo "${response:-$default}"
            ;;
    esac
}

# Show menu
show_menu() {
    local title="$1"
    local message="$2"
    shift 2

    case "$DIALOG_TOOL" in
        whiptail)
            whiptail --title "$title" --menu "$message" "$DIALOG_HEIGHT" "$DIALOG_WIDTH" "$DIALOG_LIST_HEIGHT" "$@" 3>&1 1>&2 2>&3
            ;;
        dialog)
            dialog --title "$title" --menu "$message" "$DIALOG_HEIGHT" "$DIALOG_WIDTH" "$DIALOG_LIST_HEIGHT" "$@" 3>&1 1>&2 2>&3
            ;;
        *)
            echo -e "\n=== $title ==="
            echo "$message"
            local i=1
            while [[ $# -gt 0 ]]; do
                echo "  $i) $1 - $2"
                shift 2
                ((i++))
            done
            echo -n "Select option: "
            read -r choice
            echo "$choice"
            ;;
    esac
}

# Show checklist
show_checklist() {
    local title="$1"
    local message="$2"
    shift 2

    case "$DIALOG_TOOL" in
        whiptail)
            whiptail --title "$title" --checklist "$message" "$DIALOG_HEIGHT" "$DIALOG_WIDTH" "$DIALOG_LIST_HEIGHT" "$@" 3>&1 1>&2 2>&3
            ;;
        dialog)
            dialog --title "$title" --checklist "$message" "$DIALOG_HEIGHT" "$DIALOG_WIDTH" "$DIALOG_LIST_HEIGHT" "$@" 3>&1 1>&2 2>&3
            ;;
        *)
            echo -e "\n=== $title ==="
            echo "$message"
            echo "(Multiple selection not supported in fallback mode)"
            local i=1
            while [[ $# -gt 0 ]]; do
                local status="${3:-off}"
                echo "  $i) $1 - $2 [$status]"
                shift 3
                ((i++))
            done
            echo -n "Select option: "
            read -r choice
            echo "$choice"
            ;;
    esac
}

# Show progress gauge
show_progress() {
    local title="$1"
    local percent="$2"

    case "$DIALOG_TOOL" in
        whiptail)
            echo "$percent" | whiptail --title "$title" --gauge "Please wait..." 7 "$DIALOG_WIDTH" 0
            ;;
        dialog)
            echo "$percent" | dialog --title "$title" --gauge "Please wait..." 7 "$DIALOG_WIDTH" 0
            ;;
        *)
            banner_progress "Processing..." "$percent"
            ;;
    esac
}

# Show password box
show_password() {
    local title="$1"
    local message="$2"

    case "$DIALOG_TOOL" in
        whiptail)
            whiptail --title "$title" --passwordbox "$message" "$DIALOG_HEIGHT" "$DIALOG_WIDTH" 3>&1 1>&2 2>&3
            ;;
        dialog)
            dialog --title "$title" --passwordbox "$message" "$DIALOG_HEIGHT" "$DIALOG_WIDTH" 3>&1 1>&2 2>&3
            ;;
        *)
            echo -e "\n=== $title ==="
            echo "$message"
            read -rs password
            echo "$password"
            ;;
    esac
}

#==============================================================================
# Configuration Wizard
#==============================================================================

run_config_wizard() {
    local config_file="${1:-xdc-node.conf}"

    # Welcome screen
    show_msgbox "XDC Node Setup" "Welcome to the XDC Node Setup Wizard!\n\nThis wizard will guide you through configuring your XDC node.\n\nPress OK to continue."

    # Network selection
    local network
    network=$(show_menu "Network Selection" "Choose the XDC network to connect to:" \
        "mainnet" "XDC Mainnet (Production)" \
        "testnet" "Apothem Testnet (Testing)" \
        "devnet" "Devnet (Development)")

    # Data directory
    local data_dir
    data_dir=$(show_input "Data Directory" "Enter the path for blockchain data:" "/opt/xdc-node/data")

    # Sync mode
    local sync_mode
    sync_mode=$(show_menu "Synchronization Mode" "Choose sync mode:" \
        "full" "Full sync - Download entire blockchain" \
        "fast" "Fast sync - Download headers first" \
        "snap" "Snap sync - Fastest, uses snapshots")

    # Monitoring
    local enable_monitoring=false
    if show_yesno "Monitoring" "Enable Prometheus and Grafana monitoring?"; then
        enable_monitoring=true
    fi

    # Features checklist
    local features
    features=$(show_checklist "Additional Features" "Select features to enable:" \
        "BACKUP" "Automated backups" OFF \
        "SECURITY" "Security hardening" ON \
        "UPDATES" "Auto-update checks" ON \
        "WATCHDOG" "Node watchdog service" ON)

    # Review configuration
    local config_summary="Network: $network\nData Directory: $data_dir\nSync Mode: $sync_mode\nMonitoring: $enable_monitoring\nFeatures: $features"

    if ! show_yesno "Review Configuration" "Please review your configuration:\n\n$config_summary\n\nIs this correct?"; then
        show_msgbox "Cancelled" "Configuration cancelled. Please run the wizard again."
        return 1
    fi

    # Save configuration
    generate_config_file "$config_file" "$network" "$data_dir" "$sync_mode" "$enable_monitoring" "$features"

    show_msgbox "Complete" "Configuration saved to $config_file\n\nYou can now run: ./setup.sh --config $config_file"

    return 0
}

# Generate configuration file
generate_config_file() {
    local file="$1"
    local network="$2"
    local data_dir="$3"
    local sync_mode="$4"
    local monitoring="$5"
    local features="$6"

    cat > "$file" << EOF
# XDC Node Configuration
# Generated by setup wizard on $(date)

NETWORK=$network
DATA_DIR=$data_dir
SYNC_MODE=$sync_mode

# Features
ENABLE_MONITORING=$monitoring
ENABLE_FEATURES="$features"

# Ports
RPC_PORT=8545
WS_PORT=8546
P2P_PORT=30303
METRICS_PORT=6060

# Resources
MAX_PEERS=50
CACHE_SIZE=4096
EOF

    chmod 600 "$file"
}

#==============================================================================
# Status Dashboard
#==============================================================================

show_status_dashboard() {
    local status_info
    status_info=$(get_node_status)

    show_msgbox "Node Status" "$status_info"
}

get_node_status() {
    local height syncing peers version

    height=$(curl -s -X POST http://localhost:8545 \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        2>/dev/null | jq -r '.result // "unknown"' || echo "unavailable")

    syncing=$(curl -s -X POST http://localhost:8545 \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
        2>/dev/null | jq -r '.result // false' || echo "unknown")

    peers=$(curl -s -X POST http://localhost:8545 \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
        2>/dev/null | jq -r '.result // "0x0"' | sed 's/0x//' || echo "0")
    peers=$((16#$peers))

    cat << EOF
Block Height: $height
Sync Status: $syncing
Peers: $peers

Docker Status: $(docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | grep xdc-node || echo "Not running")
Disk Usage: $(df -h /opt/xdc-node 2>/dev/null | tail -1 | awk '{print $5}' || echo "N/A")
Memory Usage: $(free -h 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2}' || echo "N/A")
EOF
}

#==============================================================================
# Main Menu
#==============================================================================

show_main_menu() {
    while true; do
        local choice
        choice=$(show_menu "XDC Node Setup" "Main Menu - Select an option:" \
            "install" "Install XDC Node" \
            "config" "Configuration Wizard" \
            "status" "View Node Status" \
            "health" "Run Health Check" \
            "backup" "Create Backup" \
            "update" "Check for Updates" \
            "logs" "View Logs" \
            "exit" "Exit")

        case "$choice" in
            install)
                ./setup.sh --interactive
                ;;
            config)
                run_config_wizard
                ;;
            status)
                show_status_dashboard
                ;;
            health)
                ./scripts/node-health-check.sh --full
                show_msgbox "Health Check" "Health check completed. Check terminal output for details."
                ;;
            backup)
                if show_yesno "Create Backup" "This will create a backup of your node data. Continue?"; then
                    ./scripts/backup.sh create
                    show_msgbox "Backup" "Backup created successfully."
                fi
                ;;
            update)
                ./scripts/version-check.sh
                show_msgbox "Update Check" "Version check completed. Check terminal output for details."
                ;;
            logs)
                local log_choice
                log_choice=$(show_menu "View Logs" "Select log type:" \
                    "node" "Node Logs" \
                    "docker" "Docker Logs" \
                    "system" "System Logs")
                case "$log_choice" in
                    node)
                        docker logs --tail 100 xdc-node 2>&1 | show_msgbox "Node Logs" "$(cat)" || true
                        ;;
                    docker)
                        docker-compose logs --tail 50 2>&1 | show_msgbox "Docker Logs" "$(cat)" || true
                        ;;
                    system)
                        journalctl -u xdc-node --no-pager -n 50 2>&1 | show_msgbox "System Logs" "$(cat)" || true
                        ;;
                esac
                ;;
            exit)
                break
                ;;
        esac
    done
}

#==============================================================================
# Main Execution
#==============================================================================

main() {
    # Check if running in terminal
    if [[ ! -t 0 ]]; then
        echo "Error: TUI mode requires an interactive terminal"
        exit 1
    fi

    # Show banner
    if [[ "$DIALOG_TOOL" == "none" ]]; then
        clear
        source "${LIB_DIR}/banners.sh"
        banner_xdc_compact
    fi

    # Run main menu
    show_main_menu
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
