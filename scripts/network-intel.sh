#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDC Network Intelligence
# Peer mapping, upgrade readiness, client diversity, network health
#==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source notification library
if [[ -f "${SCRIPT_DIR}/lib/notify.sh" ]]; then
    # shellcheck source=lib/notify.sh
    source "${SCRIPT_DIR}/lib/notify.sh"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
readonly XDC_RPC_URL="${XDC_RPC_URL:-http://localhost:8545}"
readonly GEOIP_API="http://ip-api.com/json"
readonly GITHUB_API="https://api.github.com/repos/XinFinOrg/XDPoSChain/releases/latest"

#==============================================================================
# Utility Functions
#==============================================================================

log() { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1" >&2; }
error() { echo -e "${RED}✗${NC} $1" >&2; }
die() { error "$1"; exit 1; }

rpc_call() {
    local url="${1:-$XDC_RPC_URL}"
    local method="$2"
    local params="${3:-[]}"
    
    curl -s -m 10 -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        "$url" 2>/dev/null || echo '{}'
}

hex_to_dec() {
    local hex="${1#0x}"
    printf "%d\n" "0x${hex}" 2>/dev/null || echo "0"
}

#==============================================================================
# Peer Map
#==============================================================================

generate_peer_map() {
    echo -e "${BOLD}━━━ Peer Geographic Distribution ━━━${NC}"
    echo ""
    
    local response
    response=$(rpc_call "$XDC_RPC_URL" "admin_peers")
    
    local peer_count
    peer_count=$(echo "$response" | jq '.result | length')
    
    if [[ "$peer_count" == "0" || "$peer_count" == "null" ]]; then
        warn "No peers connected or admin_peers not available"
        return 1
    fi
    
    info "Analyzing $peer_count peers..."
    echo ""
    
    # Temporary file for country counts
    local country_counts
    country_counts=$(mktemp)
    
    # Array for peer details
    declare -A countries
    declare -A cities
    
    local i=0
    while [[ $i -lt $peer_count ]]; do
        local peer
        peer=$(echo "$response" | jq -r ".result[$i]")
        
        local network
        network=$(echo "$peer" | jq -r '.network // {}')
        local remote_address
        remote_address=$(echo "$network" | jq -r '.remoteAddress // "unknown"')
        
        # Extract IP
        local ip
        ip=$(echo "$remote_address" | cut -d':' -f1)
        
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            # GeoIP lookup (rate limit friendly)
            local geo_data
            geo_data=$(curl -s -m 5 "${GEOIP_API}/${ip}" 2>/dev/null || echo '{}')
            
            local country
            country=$(echo "$geo_data" | jq -r '.country // "Unknown"')
            local city
            city=$(echo "$geo_data" | jq -r '.city // "Unknown"')
            local isp
            isp=$(echo "$geo_data" | jq -r '.isp // "Unknown"')
            
            echo "$country" >> "$country_counts"
            
            # Rate limit - don't hammer the API
            sleep 0.2
        fi
        
        i=$((i + 1))
        
        # Progress indicator
        printf "\r  Processed %d/%d peers..." "$i" "$peer_count"
    done
    
    printf "\r%-40s\n" ""
    echo ""
    
    # Count countries
    echo -e "${CYAN}Geographic Distribution:${NC}"
    echo ""
    
    sort "$country_counts" | uniq -c | sort -rn | while read -r count country; do
        local pct=$((count * 100 / peer_count))
        local bar_width=$((pct / 2))
        
        printf "  %-20s %3d (%2d%%) " "$country" "$count" "$pct"
        printf "%${bar_width}s\n" '' | tr ' ' '█'
    done
    
    rm -f "$country_counts"
    
    echo ""
    
    # Concentration risk warning
    local top_country_count
    top_country_count=$(sort "$country_counts" 2>/dev/null | uniq -c | sort -rn | head -1 | awk '{print $1}' || echo "0")
    local top_country_pct=$((top_country_count * 100 / peer_count))
    
    if [[ $top_country_pct -gt 66 ]]; then
        warn "High geographic concentration risk: ${top_country_pct}% of peers in one country"
        info "Consider adding peers from diverse regions"
    fi
    
    echo ""
}

#==============================================================================
# Upgrade Readiness
#==============================================================================

check_upgrade_readiness() {
    echo -e "${BOLD}━━━ Upgrade Readiness Check ━━━${NC}"
    echo ""
    
    local issues=0
    
    # Get current client version
    local version_response
    version_response=$(rpc_call "$XDC_RPC_URL" "web3_clientVersion")
    local current_version
    current_version=$(echo "$version_response" | jq -r '.result // "unknown"')
    
    echo -e "${CYAN}Client Version:${NC}"
    printf "  ${BOLD}%-20s${NC} %s\n" "Current:" "$current_version"
    
    # Query GitHub for latest release
    local github_response
    github_response=$(curl -s -m 10 "$GITHUB_API" 2>/dev/null || echo '{}')
    local latest_version
    latest_version=$(echo "$github_response" | jq -r '.tag_name // "unknown"')
    local release_date
    release_date=$(echo "$github_response" | jq -r '.published_at // "unknown"')
    
    printf "  ${BOLD}%-20s${NC} %s\n" "Latest Release:" "$latest_version"
    printf "  ${BOLD}%-20s${NC} %s\n" "Release Date:" "${release_date%%T*}"
    echo ""
    
    # Compare versions (simple check)
    if [[ "$current_version" == *"$latest_version"* ]]; then
        log "✓ Running latest version"
    else
        warn "Newer version available: $latest_version"
        ((issues++)) || true
    fi
    
    # Check hard fork readiness (XDPoS v2)
    echo ""
    echo -e "${CYAN}Hard Fork Readiness:${NC}"
    
    # Get current block
    local block_response
    block_response=$(rpc_call "$XDC_RPC_URL" "eth_blockNumber")
    local current_block
    current_block=$(hex_to_dec "$(echo "$block_response" | jq -r '.result // "0x0"')")
    
    # Known XDC hard fork blocks
    declare -A HARD_FORKS=(
        ["XDPoS_v2.0"]="55000000"
        ["XDPoS_v2.2"]="62600000"
    )
    
    for fork_name in "${!HARD_FORKS[@]}"; do
        local fork_block="${HARD_FORKS[$fork_name]}"
        printf "  ${BOLD}%-20s${NC} Block %s - " "$fork_name" "$fork_block"
        
        if [[ $current_block -gt $fork_block ]]; then
            echo -e "${GREEN}PASSED${NC}"
        else
            echo -e "${YELLOW}PENDING (current: $current_block)${NC}"
        fi
    done
    
    echo ""
    
    # Configuration checks
    echo -e "${CYAN}Configuration Checks:${NC}"
    
    # Check if RPC is configured correctly
    local chain_id_response
    chain_id_response=$(rpc_call "$XDC_RPC_URL" "eth_chainId")
    local chain_id
    chain_id=$(hex_to_dec "$(echo "$chain_id_response" | jq -r '.result // "0x0"')")
    
    printf "  ${BOLD}%-20s${NC} %d - " "Chain ID:" "$chain_id"
    if [[ "$chain_id" == "50" ]]; then
        echo -e "${GREEN}Mainnet${NC}"
    elif [[ "$chain_id" == "51" ]]; then
        echo -e "${GREEN}Testnet (Apothem)${NC}"
    else
        echo -e "${YELLOW}Unknown${NC}"
        ((issues++)) || true
    fi
    
    # Peer count check
    local peer_response
    peer_response=$(rpc_call "$XDC_RPC_URL" "net_peerCount")
    local peer_count
    peer_count=$(hex_to_dec "$(echo "$peer_response" | jq -r '.result // "0x0"')")
    
    printf "  ${BOLD}%-20s${NC} %d - " "Peer Count:" "$peer_count"
    if [[ $peer_count -ge 10 ]]; then
        echo -e "${GREEN}OK${NC}"
    elif [[ $peer_count -ge 3 ]]; then
        echo -e "${YELLOW}Low${NC}"
        ((issues++)) || true
    else
        echo -e "${RED}Critical${NC}"
        ((issues++)) || true
    fi
    
    # Sync status
    local sync_response
    sync_response=$(rpc_call "$XDC_RPC_URL" "eth_syncing")
    local is_syncing
    is_syncing=$(echo "$sync_response" | jq -r '.result')
    
    printf "  ${BOLD}%-20s${NC} " "Sync Status:"
    if [[ "$is_syncing" == "false" ]]; then
        echo -e "${GREEN}Synced${NC}"
    else
        echo -e "${YELLOW}Syncing${NC}"
        ((issues++)) || true
    fi
    
    echo ""
    
    # Final verdict
    echo -e "${CYAN}Upgrade Readiness:${NC}"
    if [[ $issues -eq 0 ]]; then
        echo -e "  ${GREEN}✓ READY${NC} - Node is ready for upgrades"
    else
        echo -e "  ${YELLOW}⚠ NOT READY${NC} - $issues issues found"
        info "Resolve issues before upgrading"
    fi
    
    echo ""
}

#==============================================================================
# Client Diversity
#==============================================================================

analyze_client_diversity() {
    echo -e "${BOLD}━━━ Client Diversity Analysis ━━━${NC}"
    echo ""
    
    local response
    response=$(rpc_call "$XDC_RPC_URL" "admin_peers")
    
    local peer_count
    peer_count=$(echo "$response" | jq '.result | length')
    
    if [[ "$peer_count" == "0" || "$peer_count" == "null" ]]; then
        warn "No peers connected or admin_peers not available"
        return 1
    fi
    
    # Count client types
    declare -A clients
    clients["XDPoSChain"]=0
    clients["Erigon-XDC"]=0
    clients["Other"]=0
    
    local i=0
    while [[ $i -lt $peer_count ]]; do
        local peer
        peer=$(echo "$response" | jq -r ".result[$i]")
        
        local client_name
        client_name=$(echo "$peer" | jq -r '.name // "unknown"')
        
        if [[ "$client_name" == *"XDC"* || "$client_name" == *"geth"* ]]; then
            clients["XDPoSChain"]=$((clients["XDPoSChain"] + 1))
        elif [[ "$client_name" == *"erigon"* || "$client_name" == *"Erigon"* ]]; then
            clients["Erigon-XDC"]=$((clients["Erigon-XDC"] + 1))
        else
            clients["Other"]=$((clients["Other"] + 1))
        fi
        
        i=$((i + 1))
    done
    
    echo -e "${CYAN}Client Distribution (from ${peer_count} peers):${NC}"
    echo ""
    
    for client in "${!clients[@]}"; do
        local count="${clients[$client]}"
        local pct=$((count * 100 / peer_count))
        local bar_width=$((pct / 2))
        
        # Color based on percentage
        local color="${GREEN}"
        if [[ $pct -gt 66 ]]; then
            color="${RED}"
        elif [[ $pct -gt 50 ]]; then
            color="${YELLOW}"
        fi
        
        printf "  ${BOLD}%-15s${NC} %3d (%2d%%) " "$client" "$count" "$pct"
        echo -e "${color}$(printf '%*s' "$bar_width" '' | tr ' ' '█')${NC}"
    done
    
    echo ""
    
    # Diversity warning
    local max_pct=0
    local dominant_client=""
    for client in "${!clients[@]}"; do
        local count="${clients[$client]}"
        local pct=$((count * 100 / peer_count))
        if [[ $pct -gt $max_pct ]]; then
            max_pct=$pct
            dominant_client="$client"
        fi
    done
    
    if [[ $max_pct -gt 66 ]]; then
        error "⚠ CENTRALIZATION RISK"
        warn "$dominant_client has ${max_pct}% of the network"
        echo ""
        info "Recommendation: The XDC network is healthier with diverse clients."
        info "Consider running Erigon-XDC: https://github.com/XinFinOrg/XDPoSChain"
    else
        log "✓ Client diversity is healthy"
    fi
    
    echo ""
}

#==============================================================================
# Network Health
#==============================================================================

check_network_health() {
    echo -e "${BOLD}━━━ Network Health ━━━${NC}"
    echo ""
    
    # Average block time (last 100 blocks)
    local latest_response
    latest_response=$(rpc_call "$XDC_RPC_URL" "eth_blockNumber")
    local latest_block
    latest_block=$(hex_to_dec "$(echo "$latest_response" | jq -r '.result // "0x0"')")
    
    local older_block=$((latest_block - 100))
    local older_block_hex
    older_block_hex=$(printf "0x%x" "$older_block")
    
    local latest_block_hex
    latest_block_hex=$(printf "0x%x" "$latest_block")
    
    # Get timestamps
    local latest_block_data
    latest_block_data=$(rpc_call "$XDC_RPC_URL" "eth_getBlockByNumber" '["'"$latest_block_hex"'", false]')
    local latest_timestamp
    latest_timestamp=$(hex_to_dec "$(echo "$latest_block_data" | jq -r '.result.timestamp // "0x0"')")
    
    local older_block_data
    older_block_data=$(rpc_call "$XDC_RPC_URL" "eth_getBlockByNumber" '["'"$older_block_hex"'", false]')
    local older_timestamp
    older_timestamp=$(hex_to_dec "$(echo "$older_block_data" | jq -r '.result.timestamp // "0x0"')")
    
    local time_diff=$((latest_timestamp - older_timestamp))
    local avg_block_time
    avg_block_time=$(echo "scale=2; $time_diff / 100" | bc)
    
    echo -e "${CYAN}Block Production:${NC}"
    printf "  ${BOLD}%-25s${NC} %d\n" "Current Block:" "$latest_block"
    printf "  ${BOLD}%-25s${NC} %ss\n" "Avg Block Time (100):" "$avg_block_time"
    
    # Expected is ~2 seconds
    if (( $(echo "$avg_block_time < 2.5" | bc -l) )); then
        printf "  ${BOLD}%-25s${NC} ${GREEN}Healthy${NC}\n" "Block Rate:"
    elif (( $(echo "$avg_block_time < 5" | bc -l) )); then
        printf "  ${BOLD}%-25s${NC} ${YELLOW}Slightly Slow${NC}\n" "Block Rate:"
    else
        printf "  ${BOLD}%-25s${NC} ${RED}Slow${NC}\n" "Block Rate:"
    fi
    
    echo ""
    
    # Epoch info
    local epoch=$((latest_block / 900))
    local round=$((latest_block % 900))
    
    echo -e "${CYAN}XDPoS Consensus:${NC}"
    printf "  ${BOLD}%-25s${NC} %d\n" "Current Epoch:" "$epoch"
    printf "  ${BOLD}%-25s${NC} %d / 900\n" "Round:" "$round"
    
    echo ""
    
    # Transaction pool
    local txpool_response
    txpool_response=$(rpc_call "$XDC_RPC_URL" "txpool_status")
    local pending
    pending=$(hex_to_dec "$(echo "$txpool_response" | jq -r '.result.pending // "0x0"')")
    local queued
    queued=$(hex_to_dec "$(echo "$txpool_response" | jq -r '.result.queued // "0x0"')")
    
    echo -e "${CYAN}Transaction Pool:${NC}"
    printf "  ${BOLD}%-25s${NC} %d\n" "Pending:" "$pending"
    printf "  ${BOLD}%-25s${NC} %d\n" "Queued:" "$queued"
    
    if [[ $pending -lt 1000 ]]; then
        printf "  ${BOLD}%-25s${NC} ${GREEN}Normal${NC}\n" "Congestion:"
    elif [[ $pending -lt 10000 ]]; then
        printf "  ${BOLD}%-25s${NC} ${YELLOW}Moderate${NC}\n" "Congestion:"
    else
        printf "  ${BOLD}%-25s${NC} ${RED}High${NC}\n" "Congestion:"
    fi
    
    echo ""
    
    # Check against multiple public RPCs
    echo -e "${CYAN}Public RPC Comparison:${NC}"
    
    declare -a public_rpcs=(
        "https://erpc.xinfin.network"
        "https://rpc.xinfin.network"
    )
    
    for rpc_url in "${public_rpcs[@]}"; do
        local remote_response
        remote_response=$(rpc_call "$rpc_url" "eth_blockNumber")
        local remote_block
        remote_block=$(hex_to_dec "$(echo "$remote_response" | jq -r '.result // "0x0"')")
        
        local diff=$((latest_block - remote_block))
        local abs_diff=${diff#-}  # Absolute value
        
        local rpc_name
        rpc_name=$(echo "$rpc_url" | cut -d'/' -f3)
        
        printf "  %-25s Block: %-10d " "$rpc_name" "$remote_block"
        
        if [[ $abs_diff -lt 5 ]]; then
            echo -e "${GREEN}[In sync]${NC}"
        elif [[ $abs_diff -lt 50 ]]; then
            echo -e "${YELLOW}[Diff: $diff]${NC}"
        else
            echo -e "${RED}[Diff: $diff]${NC}"
        fi
    done
    
    echo ""
}

#==============================================================================
# Help
#==============================================================================

show_help() {
    cat << EOF
XDC Network Intelligence

Usage: $(basename "$0") <command> [options]

Commands:
    peers                       Generate peer geographic map
    upgrade                     Check upgrade readiness
    diversity                   Analyze client diversity
    health                      Check network health
    all                         Run all checks

Options:
    --rpc URL                   RPC endpoint (default: $XDC_RPC_URL)
    --help, -h                  Show this help message

Examples:
    # Generate peer map
    $(basename "$0") peers

    # Check upgrade readiness
    $(basename "$0") upgrade

    # Analyze client diversity
    $(basename "$0") diversity

    # Full network health report
    $(basename "$0") health

    # Run all intelligence checks
    $(basename "$0") all

Description:
    Network intelligence tools for XDC node operators:
    - Geographic peer distribution mapping
    - Upgrade and hard fork readiness checking
    - Client diversity analysis (geth vs erigon)
    - Network health monitoring

Data Sources:
    - Local node RPC (admin_peers, eth_*, net_*)
    - ip-api.com for GeoIP lookups
    - GitHub API for version checking
    - Public XDC RPCs for comparison

EOF
}

#==============================================================================
# Main
#==============================================================================

main() {
    local command=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            peers|upgrade|diversity|health|all)
                command="$1"
                shift
                ;;
            --rpc)
                XDC_RPC_URL="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                if [[ -z "$command" ]]; then
                    command="$1"
                fi
                shift
                ;;
        esac
    done
    
    case "$command" in
        peers)
            generate_peer_map
            ;;
        upgrade)
            check_upgrade_readiness
            ;;
        diversity)
            analyze_client_diversity
            ;;
        health)
            check_network_health
            ;;
        all)
            check_network_health
            check_upgrade_readiness
            analyze_client_diversity
            generate_peer_map
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

main "$@"
