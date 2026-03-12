#!/usr/bin/env bash
#==============================================================================
# Genesis Hash Verification for XDC Network
#
# Usage:
#   source scripts/lib/genesis-verify.sh
#   verify_genesis "$RPC_URL" "$EXPECTED_NETWORK"
#
# Known genesis hashes:
#   mainnet: 0x4a9d748bd78a8d0385b67788c2435dcdb914f98a96250b68863a1f8b7642d6b1
#   apothem: 0xbdea512b4f12ff1135ec92c00dc047ffb93890c2ea1aa0eefe9b013d80640075
#==============================================================================

# Known genesis hashes
readonly XDC_MAINNET_GENESIS="0x4a9d748bd78a8d0385b67788c2435dcdb914f98a96250b68863a1f8b7642d6b1"
readonly XDC_APOTHEM_GENESIS="0xbdea512b4f12ff1135ec92c00dc047ffb93890c2ea1aa0eefe9b013d80640075"

# Identify network from genesis hash
# Returns: mainnet, apothem, or unknown
identify_network_from_genesis() {
    local genesis_hash="$1"
    case "$genesis_hash" in
        "$XDC_MAINNET_GENESIS") echo "mainnet" ;;
        "$XDC_APOTHEM_GENESIS") echo "apothem" ;;
        *) echo "unknown" ;;
    esac
}

# Fetch genesis hash from RPC
# Args: $1 = RPC URL (default: http://127.0.0.1:8545)
# Returns: genesis block hash or empty string
fetch_genesis_hash() {
    local rpc_url="${1:-http://127.0.0.1:8545}"
    local resp
    resp=$(curl -s -m 10 -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x0",false],"id":1}' \
        "$rpc_url" 2>/dev/null)
    echo "$resp" | jq -r '.result.hash // ""' 2>/dev/null || echo ""
}

# Verify genesis matches expected network
# Args: $1 = RPC URL, $2 = expected network (mainnet|apothem)
# Returns: 0 if match, 1 if mismatch, 2 if unable to check
verify_genesis() {
    local rpc_url="${1:-http://127.0.0.1:8545}"
    local expected_network="${2:-}"
    local max_retries=5
    local retry_delay=3
    
    if [[ -z "$expected_network" ]]; then
        echo "[genesis-verify] No expected network specified, skipping verification"
        return 0
    fi
    
    local genesis_hash=""
    local attempt=0
    
    # Retry loop — node may need time to start
    while [[ $attempt -lt $max_retries ]]; do
        genesis_hash=$(fetch_genesis_hash "$rpc_url")
        if [[ -n "$genesis_hash" ]]; then
            break
        fi
        attempt=$((attempt + 1))
        echo "[genesis-verify] Waiting for RPC... (attempt $attempt/$max_retries)"
        sleep "$retry_delay"
    done
    
    if [[ -z "$genesis_hash" ]]; then
        echo "[genesis-verify] ⚠️  Unable to fetch genesis hash from $rpc_url after $max_retries attempts"
        return 2
    fi
    
    local actual_network
    actual_network=$(identify_network_from_genesis "$genesis_hash")
    
    if [[ "$actual_network" == "$expected_network" ]]; then
        echo "[genesis-verify] ✅ Genesis verified: $expected_network ($genesis_hash)"
        return 0
    else
        echo "[genesis-verify] ❌ GENESIS MISMATCH!"
        echo "[genesis-verify]    Expected: $expected_network"
        echo "[genesis-verify]    Actual:   $actual_network (hash: $genesis_hash)"
        if [[ "$expected_network" == "apothem" ]]; then
            echo "[genesis-verify]    Expected hash: $XDC_APOTHEM_GENESIS"
        elif [[ "$expected_network" == "mainnet" ]]; then
            echo "[genesis-verify]    Expected hash: $XDC_MAINNET_GENESIS"
        fi
        echo "[genesis-verify]    Fix: Check your chainspec/genesis config. For Nethermind use --config=xdc-testnet (apothem) or --config=xdc (mainnet)."
        return 1
    fi
}
