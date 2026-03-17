#!/usr/bin/env bash
#==============================================================================
# Generate Static Nodes by Client Type (Issue #550)
# Prevents cross-client peering that causes "invalid ancestor" errors
#==============================================================================
set -euo pipefail

CLIENT_FILTER="${1:-all}"  # gp5, erigon, nm, reth, all

echo "🔗 Generating static-nodes.json for client: $CLIENT_FILTER"
echo ""

# Known fleet peers by client type
declare -A GP5_PEERS=(
    ["xdc08"]="enode://28645e5d8421f0bba710094648b5d558f4d44df87f4e23aeb5d8f14a1243d651c0ee5644da3e70991f18a419b5e57dda638b84f7a633413d37f038e3f0c57b83@65.21.27.213:30303"
    ["test"]="enode://e1744061a9b2400c56bd6d346b889adaf72a5318df12a6cd04866bbb3b26738fe599e297c32d56c75859ffea0abcc83c166c539464f64387e187afb655d8499e@95.217.56.168:30303"
)

declare -A ERIGON_PEERS=(
    ["xdc08"]="enode://ERIGON_KEY@65.21.27.213:30304"
)

# XDC mainnet public bootnodes (GP5 compatible ONLY)
MAINNET_BOOTNODES=(
    "enode://e1a69a7d766576e694adc3fc78d801a8a66926cbe8f4fe95b85f3b481444700a5d1b6d440b2715b5bb7cf4824df6a6702740afc8c52b20c72bc8c16f1ccde1f3@149.102.140.32:30303"
    "enode://874589626a2b4fd7c57202533315885815eba51dbc434db88bbbebcec9b22cf2a01eafad2fd61651306fe85321669a30b3f41112eca230137ded24b86e064ba8@5.189.144.192:30303"
    "enode://ccdef92053c8b9622180d02a63edffb3e143e7627737ea812b930eacea6c51f0c93a5da3397f59408c3d3d1a9a381f7e0b07440eae47314685b649a03408cfdd@37.60.243.5:30303"
)

output_file="${2:-static-nodes.json}"

echo "[" > "$output_file"
first=true

add_peer() {
    local enode="$1"
    if [[ "$first" == "true" ]]; then
        echo "  \"$enode\"" >> "$output_file"
        first=false
    else
        echo "  ,\"$enode\"" >> "$output_file"
    fi
}

case "$CLIENT_FILTER" in
    gp5|geth)
        echo "⚠️  GP5 nodes should ONLY peer with GP5 nodes"
        echo "   Cross-client peering causes 'invalid ancestor' errors"
        for key in "${!GP5_PEERS[@]}"; do
            add_peer "${GP5_PEERS[$key]}"
        done
        for bn in "${MAINNET_BOOTNODES[@]}"; do
            add_peer "$bn"
        done
        ;;
    erigon)
        echo "ℹ️  Erigon nodes peer with both Erigon and GP5 (eth/62,63,100)"
        for key in "${!ERIGON_PEERS[@]}"; do
            add_peer "${ERIGON_PEERS[$key]}"
        done
        for key in "${!GP5_PEERS[@]}"; do
            add_peer "${GP5_PEERS[$key]}"
        done
        ;;
    all)
        for key in "${!GP5_PEERS[@]}"; do
            add_peer "${GP5_PEERS[$key]}"
        done
        for bn in "${MAINNET_BOOTNODES[@]}"; do
            add_peer "$bn"
        done
        ;;
    *)
        echo "Usage: $0 [gp5|erigon|nm|reth|all] [output-file]"
        exit 1
        ;;
esac

echo "]" >> "$output_file"

peer_count=$(grep -c 'enode://' "$output_file")
echo ""
echo "✅ Generated $output_file with $peer_count peers"
echo "   Copy to your node's datadir: cp $output_file /path/to/xdcchain/XDC/"
