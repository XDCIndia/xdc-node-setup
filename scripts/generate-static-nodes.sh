#!/bin/bash
#==============================================================================
# XDC Client-Aware Static Nodes Generator
# Fixes Issue #550: GP5 syncing from Erigon gets 'invalid ancestor' error
#==============================================================================
# Usage: ./generate-static-nodes.sh [gp5|erigon|nethermind]
#
# This script separates peer lists by client type to prevent cross-client
# consensus incompatibilities. GP5 should ONLY peer with GP5, Erigon with
# Erigon, etc.
#==============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly NETWORK_DIR="${SCRIPT_DIR}/../docker/mainnet"

# Known client-specific peers (examples - update with real enodes)
readonly GP5_PEERS=(
    "enode://EXAMPLE_GP5_PEER_1@ip:port"
    "enode://EXAMPLE_GP5_PEER_2@ip:port"
)

readonly ERIGON_PEERS=(
    "enode://EXAMPLE_ERIGON_PEER_1@ip:port"
    "enode://EXAMPLE_ERIGON_PEER_2@ip:port"
)

readonly NETHERMIND_PEERS=(
    "enode://EXAMPLE_NETHERMIND_PEER_1@ip:port"
    "enode://EXAMPLE_NETHERMIND_PEER_2@ip:port"
)

# Colors
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m'

usage() {
    cat << EOF
Usage: $0 [CLIENT_TYPE]

CLIENT_TYPE:
    gp5         - Generate static-nodes.json for Geth-PR5 (GP5) client
    erigon      - Generate static-nodes.json for Erigon client
    nethermind  - Generate static-nodes.json for Nethermind client

Examples:
    $0 gp5
    $0 erigon

WARNING: Cross-client peering can cause consensus errors like 'invalid ancestor'.
Always use client-specific peer lists!
EOF
    exit 1
}

generate_static_nodes() {
    local client=$1
    local output_file="${NETWORK_DIR}/static-nodes.${client}.json"
    local peers_ref="${client^^}_PEERS[@]"
    
    echo -e "${YELLOW}⚠️  WARNING: Cross-client peering detected!${NC}"
    echo -e "   GP5 nodes syncing from Erigon may encounter 'invalid ancestor' errors."
    echo -e "   Generating client-specific static-nodes for: ${GREEN}${client}${NC}"
    echo ""
    
    # Create JSON array
    local json_content="[\n"
    local peers=("${!peers_ref}")
    
    if [ ${#peers[@]} -eq 0 ]; then
        echo -e "${RED}ERROR: No peers defined for ${client}${NC}"
        echo "Please update this script with real enode URLs for your network."
        exit 1
    fi
    
    for i in "${!peers[@]}"; do
        json_content+="  \"${peers[$i]}\""
        if [ $i -lt $((${#peers[@]} - 1)) ]; then
            json_content+=","
        fi
        json_content+="\n"
    done
    
    json_content+="]"
    
    # Write to file
    echo -e "$json_content" > "$output_file"
    
    echo -e "${GREEN}✓ Generated: ${output_file}${NC}"
    echo "  Peer count: ${#peers[@]}"
    echo ""
    echo "Next steps:"
    echo "  1. Review and edit $output_file with real enode URLs"
    echo "  2. Copy to your node's data directory:"
    echo "     cp $output_file /path/to/xdcchain/static-nodes.json"
    echo "  3. Restart your $client node"
    echo ""
    echo -e "${YELLOW}IMPORTANT:${NC} Only use peers running the SAME client type!"
}

# Main
if [ $# -eq 0 ]; then
    usage
fi

CLIENT_TYPE="${1,,}"  # Convert to lowercase

case "$CLIENT_TYPE" in
    gp5|geth-pr5)
        generate_static_nodes "gp5"
        ;;
    erigon)
        generate_static_nodes "erigon"
        ;;
    nethermind)
        generate_static_nodes "nethermind"
        ;;
    *)
        echo -e "${RED}ERROR: Unknown client type: $CLIENT_TYPE${NC}"
        usage
        ;;
esac
