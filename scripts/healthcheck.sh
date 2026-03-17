#!/bin/bash
# XDC Node Health Check - used by Docker HEALTHCHECK
# Usage: RPC_PORT=8545 ./healthcheck.sh

set -euo pipefail

PORT=${RPC_PORT:-8545}

# Try curl first
if command -v curl >/dev/null 2>&1; then
    RESULT=$(curl -sf http://localhost:$PORT \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        2>/dev/null || true)
    
    [ -n "$RESULT" ] && echo "$RESULT" | grep -q "result" && exit 0
fi

# Fallback to wget
if command -v wget >/dev/null 2>&1; then
    RESULT=$(wget -qO- http://localhost:$PORT \
        --post-data='{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        --header='Content-Type: application/json' \
        2>/dev/null || true)
    
    [ -n "$RESULT" ] && echo "$RESULT" | grep -q "result" && exit 0
fi

exit 1
