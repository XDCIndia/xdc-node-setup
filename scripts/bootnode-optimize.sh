#!/usr/bin/env bash

# Source utility functions
source "$(dirname "$0")/lib/utils.sh" || { echo "Failed to load utils"; exit 1; }
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }

#==============================================================================
# XDC Bootnode Optimizer
# Smart peer management for XDC nodes
# Tests latency to known bootnodes and generates optimized static-nodes.json
#==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Default settings
readonly DEFAULT_TOP_N=10
# Detect network for network-aware directory structure
readonly XDC_NETWORK="${XDC_NETWORK:-$(detect_network)}"
readonly DEFAULT_DATADIR="${XDC_DATADIR:-$(pwd)/${XDC_NETWORK}/xdcchain}"
readonly PING_TIMEOUT=5
readonly CONNECT_TIMEOUT=10

# Testnet flag
USE_TESTNET=false

#==============================================================================
# Utility Functions
#==============================================================================


parse_enode_port() {
    local enode="$1"
    # Extract port from enode://pubkey@IP:port
    echo "$enode" | sed -n 's|enode://[^@]*@[^:]*:\([0-9]*\).*|\1|p'
}

parse_enode_pubkey() {
    local enode="$1"
    # Extract pubkey from enode://pubkey@IP:port
    echo "$enode" | sed -n 's|enode://\([^@]*\)@.*|\1|p'
}

#==============================================================================
# Latency Measurement
#==============================================================================

measure_latency() {
    local ip="$1"
    local port="${2:-30303}"
    
    local latency=""
    
    # Try TCP connect time measurement
    if command -v nc &>/dev/null; then
        local start end
        start=$(date +%s%N)
        if timeout "$CONNECT_TIMEOUT" nc -z "$ip" "$port" 2>/dev/null; then
            end=$(date +%s%N)
            latency=$(( (end - start) / 1000000 ))  # Convert to ms
        fi
    fi
    
    # Fallback to ping if no TCP result
    if [[ -z "$latency" ]] && command -v ping &>/dev/null; then
        local ping_result
        ping_result=$(ping -c 1 -W "$PING_TIMEOUT" "$ip" 2>/dev/null | grep -oP 'time=\K[0-9.]+' || true)
        if [[ -n "$ping_result" ]]; then
            latency=$(echo "$ping_result * 1000" | bc | cut -d. -f1)
        fi
    fi
    
    # If still no result, mark as unreachable
    if [[ -z "$latency" ]]; then
        latency="99999"
    fi
    
    echo "$latency"
}

#==============================================================================
# P2P Connectivity Test
#==============================================================================

test_p2p_connectivity() {
    local ip="$1"
    local port="${2:-30303}"
    
    if command -v nc &>/dev/null; then
        if timeout "$CONNECT_TIMEOUT" nc -z "$ip" "$port" 2>/dev/null; then
            echo "yes"
        else
            echo "no"
        fi
    else
        echo "unknown"
    fi
}

#==============================================================================
# NAT Detection
#==============================================================================

detect_nat() {
    info "Checking for NAT configuration..."
    
    local external_ip
    local binding_ip
    
    # Get external IP
    external_ip=$(curl -s -m 10 https://api.ipify.org 2>/dev/null || echo "")
    
    # Get local binding IP (assume default interface)
    binding_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' | head -1 || echo "")
    
    if [[ -z "$external_ip" ]]; then
        warn "Could not determine external IP address"
        return 1
    fi
    
    if [[ -z "$binding_ip" ]]; then
        warn "Could not determine local binding IP"
        return 1
    fi
    
    echo ""
    echo "External IP: $external_ip"
    echo "Local IP:    $binding_ip"
    echo ""
    
    if [[ "$external_ip" != "$binding_ip" ]]; then
        warn "NAT DETECTED: External IP differs from local binding IP"
        echo ""
        echo -e "${YELLOW}Port Forwarding Required:${NC}"
        echo "  For optimal P2P connectivity, forward port 30303 to: $binding_ip"
        echo ""
        echo "Router configuration:"
        echo "  - Protocol: TCP and UDP"
        echo "  - External Port: 30303"
        echo "  - Internal Port: 30303"
        echo "  - Internal IP: $binding_ip"
        echo ""
        return 0
    else
        log "No NAT detected - node has direct internet connection"
        return 1
    fi
}

#==============================================================================
# Main Optimization
#==============================================================================

optimize_bootnodes() {
    local top_n="${1:-$DEFAULT_TOP_N}"
    local datadir="${2:-$DEFAULT_DATADIR}"
    
    echo -e "${BOLD}━━━ XDC Bootnode Optimizer ━━━${NC}"
    echo ""
    
    # Select bootnode list based on network
    local -n BOOTNODES
    if [[ "$USE_TESTNET" == "true" ]]; then
        BOOTNODES=TESTNET_BOOTNODES
        info "Using Apothem TESTNET bootnodes"
    else
        BOOTNODES=MAINNET_BOOTNODES
        info "Using MAINNET bootnodes"
    fi
    echo ""
    
    local total_nodes=${#BOOTNODES[@]}
    info "Testing $total_nodes bootnodes for latency..."
    echo ""
    
    # Create temp file for results
    local results_file
    results_file=$(mktemp)
    
    local current=0
    for enode in "${!BOOTNODES[@]}"; do
        current=$((current + 1))
        
        local ip
        ip=$(parse_enode_ip "$enode")
        local port
        port=$(parse_enode_port "$enode")
        local location="${BOOTNODES[$enode]}"
        
        printf "\r  Testing %d/%d: %-15s (%s)" "$current" "$total_nodes" "$ip" "$location"
        
        local latency
        latency=$(measure_latency "$ip" "$port")
        
        local p2p_status
        p2p_status=$(test_p2p_connectivity "$ip" "$port")
        
        echo "$latency $enode $location $p2p_status" >> "$results_file"
    done
    
    printf "\r%-50s\n" ""
    echo ""
    
    # Sort by latency and take top N
    log "Top $top_n fastest bootnodes:"
    echo ""
    
    printf "${BOLD}%-6s %-15s %-8s %-12s %s${NC}\n" "Rank" "IP" "Latency" "P2P" "Location"
    printf "%-6s %-15s %-8s %-12s %s\n" "----" "---" "-------" "---" "--------"
    
    local sorted_results
    sorted_results=$(sort -n "$results_file" | head -n "$top_n")
    
    local rank=1
    local selected_enodes=()
    
    while IFS= read -r line; do
        local latency enode location p2p_status
        latency=$(echo "$line" | awk '{print $1}')
        enode=$(echo "$line" | cut -d' ' -f2- | rev | cut -d' ' -f3- | rev)
        location=$(echo "$line" | awk '{print $(NF-1)}')
        p2p_status=$(echo "$line" | awk '{print $NF}')
        
        local ip
        ip=$(parse_enode_ip "$enode")
        
        local latency_display
        if [[ "$latency" == "99999" ]]; then
            latency_display="timeout"
        else
            latency_display="${latency}ms"
        fi
        
        local p2p_display
        if [[ "$p2p_status" == "yes" ]]; then
            p2p_display="✓"
        elif [[ "$p2p_status" == "no" ]]; then
            p2p_display="✗"
        else
            p2p_display="?"
        fi
        
        printf "%-6s %-15s %-8s %-12s %s\n" "$rank" "$ip" "$latency_display" "$p2p_display" "$location"
        
        selected_enodes+=("$enode")
        rank=$((rank + 1))
    done <<< "$sorted_results"
    
    rm -f "$results_file"
    
    echo ""
    
    # Generate static-nodes.json
    local output_file="${datadir}/static-nodes.json"
    
    info "Generating optimized static-nodes.json..."
    echo ""
    
    # Build JSON array
    local json_content="["
    local first=true
    for enode in "${selected_enodes[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            json_content+=","
        fi
        json_content+="\n  \"$enode\""
    done
    json_content+="\n]"
    
    # Write to file
    echo -e "$json_content" > "$output_file"
    
    log "Static nodes configuration saved to: $output_file"
    echo ""
    
    # Show the content
    echo -e "${CYAN}Generated configuration:${NC}"
    cat "$output_file"
    echo ""
}

#==============================================================================
# Help
#==============================================================================

show_help() {
    cat << EOF
XDC Bootnode Optimizer

Usage: $(basename "$0") [options]

Options:
    --testnet           Use Apothem testnet bootnodes instead of mainnet
    --top N             Use top N fastest nodes (default: $DEFAULT_TOP_N)
    --datadir PATH      XDC data directory (default: $DEFAULT_DATADIR)
    --nat-check         Check for NAT and suggest port forwarding
    --help, -h          Show this help message

Examples:
    # Optimize mainnet bootnodes (default)
    $(basename "$0")

    # Optimize with top 15 fastest nodes
    $(basename "$0") --top 15

    # Optimize for testnet
    $(basename "$0") --testnet

    # Check NAT configuration
    $(basename "$0") --nat-check

Description:
    This script tests latency to known XDC bootnodes and generates an
    optimized static-nodes.json file with the fastest peers. This improves
    sync speed and network connectivity for your XDC node.

    The script measures:
    - TCP connection latency to each bootnode
    - P2P port accessibility
    - Geographic location for diversity

Output:
    Updates static-nodes.json in your XDC data directory with the
    top N fastest bootnodes.

EOF
}

#==============================================================================
# Main
#==============================================================================

main() {
    local top_n="$DEFAULT_TOP_N"
    local datadir="$DEFAULT_DATADIR"
    local do_nat_check=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --testnet)
                USE_TESTNET=true
                shift
                ;;
            --top)
                top_n="${2:-$DEFAULT_TOP_N}"
                shift 2
                ;;
            --datadir)
                datadir="${2:-$DEFAULT_DATADIR}"
                shift 2
                ;;
            --nat-check)
                do_nat_check=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                warn "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Run NAT check if requested
    if [[ "$do_nat_check" == "true" ]]; then
        detect_nat
        exit 0
    fi
    
    # Ensure datadir exists
    mkdir -p "$datadir"
    
    # Run optimization
    optimize_bootnodes "$top_n" "$datadir"
    
    # Always run NAT check after optimization
    detect_nat
    
    echo ""
    log "Bootnode optimization complete!"
    echo ""
    info "Next steps:"
    echo "  1. Restart your XDC node to use the new static-nodes.json"
    echo "  2. Monitor peer connections: xdc-node status"
    echo "  3. Re-run this script weekly to maintain optimal peers"
    echo ""
    
    if [[ "$USE_TESTNET" == "true" ]]; then
        info "Testnet (Apothem) configured. Explorer: https://explorer.apothem.network"
    else
        info "Mainnet configured. Explorer: https://explorer.xinfin.network"
    fi
}

main "$@"
