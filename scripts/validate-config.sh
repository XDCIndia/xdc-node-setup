#!/usr/bin/env bash
#==============================================================================
# Configuration Schema Validator (Issue #387)
# Validates node configuration before startup
#==============================================================================
set -euo pipefail

CONFIG_DIR="${1:-.}"
ERRORS=0
WARNINGS=0

echo "🔍 Validating XDC node configuration..."
echo ""

# Check genesis.json
check_genesis() {
    local genesis="$CONFIG_DIR/genesis.json"
    if [[ ! -f "$genesis" ]]; then
        genesis="$CONFIG_DIR/mainnet/genesis.json"
    fi
    
    if [[ ! -f "$genesis" ]]; then
        echo "❌ genesis.json not found"
        ((ERRORS++))
        return
    fi
    
    # Validate JSON
    if ! jq empty "$genesis" 2>/dev/null; then
        echo "❌ genesis.json is not valid JSON"
        ((ERRORS++))
        return
    fi
    
    # Check required fields
    local chain_id=$(jq -r '.config.chainId // empty' "$genesis")
    if [[ -z "$chain_id" ]]; then
        echo "❌ genesis.json missing config.chainId"
        ((ERRORS++))
    elif [[ "$chain_id" != "50" && "$chain_id" != "51" ]]; then
        echo "⚠️  genesis.json chainId=$chain_id (expected 50=mainnet or 51=apothem)"
        ((WARNINGS++))
    else
        echo "✅ genesis.json: chainId=$chain_id"
    fi
    
    # Check XDPoS config
    local xdpos=$(jq -r '.config.xdpos // empty' "$genesis")
    if [[ -z "$xdpos" ]]; then
        echo "❌ genesis.json missing config.xdpos consensus config"
        ((ERRORS++))
    else
        echo "✅ genesis.json: XDPoS config present"
    fi
}

# Check docker-compose files
check_compose() {
    for f in "$CONFIG_DIR"/docker-compose*.yml "$CONFIG_DIR"/docker/docker-compose*.yml; do
        [[ -f "$f" ]] || continue
        echo "Checking: $f"
        
        # Check for deprecated docker-compose v1 syntax
        if grep -q "^version:" "$f"; then
            echo "⚠️  $f uses deprecated 'version:' key (docker-compose v2+ ignores it)"
            ((WARNINGS++))
        fi
        
        # Check for required volume mounts
        if grep -q "genesis.json" "$f"; then
            echo "✅ Genesis volume mount found"
        fi
    done
}

# Check port conflicts
check_ports() {
    local ports=(8545 8546 8547 8548 8549 8550 30303 30304 30305 30306)
    echo ""
    echo "Port availability:"
    for port in "${ports[@]}"; do
        if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
            local proc=$(ss -tlnp 2>/dev/null | grep ":${port} " | awk '{print $NF}')
            echo "⚠️  Port $port in use: $proc"
            ((WARNINGS++))
        fi
    done
}

# Check bootnodes
check_bootnodes() {
    local bnfile="$CONFIG_DIR/bootnodes.list"
    if [[ ! -f "$bnfile" ]]; then
        bnfile="$CONFIG_DIR/mainnet/bootnodes.list"
    fi
    
    if [[ -f "$bnfile" ]]; then
        local count=$(grep -c '^enode://' "$bnfile" 2>/dev/null || echo "0")
        echo "✅ Bootnodes: $count entries"
    else
        echo "⚠️  No bootnodes.list found (will rely on built-in bootnodes)"
        ((WARNINGS++))
    fi
}

check_genesis
check_compose
check_bootnodes
check_ports

echo ""
echo "================================"
if [[ $ERRORS -gt 0 ]]; then
    echo "❌ Validation FAILED: $ERRORS error(s), $WARNINGS warning(s)"
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    echo "⚠️  Validation passed with $WARNINGS warning(s)"
    exit 0
else
    echo "✅ All configuration checks passed"
    exit 0
fi
