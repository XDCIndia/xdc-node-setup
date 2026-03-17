#!/usr/bin/env bash
#==============================================================================
# SkyOne Agent Environment Validator (Issue #551)
# Source this before running skynet-agent.sh to validate required env vars
#==============================================================================

validate_skyone_env() {
    local errors=0
    local warnings=0
    
    echo "🔍 Validating SkyOne agent environment..."
    
    # Critical: RPC URL
    if [[ -z "${XDC_RPC_URL:-}" && -z "${RPC_URL:-}" ]]; then
        echo "⚠️  WARNING: XDC_RPC_URL not set, defaulting to http://127.0.0.1:8545"
        export XDC_RPC_URL="http://127.0.0.1:8545"
        ((warnings++))
    fi
    
    # Critical: SkyNet API URL
    if [[ -z "${SKYNET_API_URL:-}" ]]; then
        echo "⚠️  WARNING: SKYNET_API_URL not set, defaulting to https://net.xdc.network/api"
        export SKYNET_API_URL="https://net.xdc.network/api"
        ((warnings++))
    fi
    
    # Important: API Key (required for registration, optional for keyless heartbeat)
    if [[ -z "${SKYNET_API_KEY:-}" ]]; then
        echo "⚠️  WARNING: SKYNET_API_KEY not set"
        echo "   Registration will fail. Keyless heartbeats may still work if nodeId is set."
        ((warnings++))
    fi
    
    # Important: Node ID (required for heartbeat-only mode)
    if [[ -z "${SKYNET_NODE_ID:-}" ]]; then
        echo "⚠️  WARNING: SKYNET_NODE_ID not set"
        echo "   Agent will attempt auto-registration (requires SKYNET_API_KEY)"
        ((warnings++))
    fi
    
    # Node Name
    if [[ -z "${NODE_NAME:-}" ]]; then
        export NODE_NAME="$(hostname)-$(date +%s | tail -c 5)"
        echo "ℹ️  NODE_NAME auto-generated: $NODE_NAME"
    fi
    
    # Connectivity checks
    local rpc_url="${XDC_RPC_URL:-${RPC_URL:-http://127.0.0.1:8545}}"
    if ! curl -sf -m 3 -X POST "$rpc_url" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' >/dev/null 2>&1; then
        echo "❌ ERROR: Cannot connect to RPC at $rpc_url"
        echo "   Ensure the XDC node is running and RPC is accessible"
        ((errors++))
    else
        echo "✅ RPC connection OK: $rpc_url"
    fi
    
    # SkyNet API connectivity
    if ! curl -sf -m 5 "${SKYNET_API_URL:-https://net.xdc.network/api}/health" >/dev/null 2>&1; then
        if ! curl -sf -m 5 "${SKYNET_API_URL:-https://net.xdc.network/api}/v1/nodes" >/dev/null 2>&1; then
            echo "⚠️  WARNING: Cannot reach SkyNet API at ${SKYNET_API_URL:-https://net.xdc.network/api}"
            ((warnings++))
        fi
    else
        echo "✅ SkyNet API reachable"
    fi
    
    echo ""
    if [[ $errors -gt 0 ]]; then
        echo "❌ Validation failed: $errors error(s), $warnings warning(s)"
        echo "   Fix errors above before starting the agent"
        return 1
    elif [[ $warnings -gt 0 ]]; then
        echo "⚠️  Validation passed with $warnings warning(s)"
        echo "   Agent will start but some features may not work"
        return 0
    else
        echo "✅ All checks passed"
        return 0
    fi
}

# Auto-run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_skyone_env
fi
