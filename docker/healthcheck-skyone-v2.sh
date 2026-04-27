#!/bin/bash
set -eo pipefail

# Check Nginx
if ! curl -sf http://localhost:${DASHBOARD_PORT:-7070}/health > /dev/null 2>&1; then
    echo "FAIL: Dashboard not responding"
    exit 1
fi

# Check Dashboard API
if ! curl -sf http://localhost:3000/api/health > /dev/null 2>&1; then
    echo "FAIL: Dashboard API not responding"
    exit 1
fi

# Check SkyNet (if enabled)
if [ "${SKYNET_ENABLED}" = "true" ] && [ -n "${SKYNET_API_KEY}" ]; then
    if ! pgrep -f "skynet-agent" > /dev/null 2>&1; then
        echo "WARN: SkyNet agent not running"
    fi
fi

# Check XDC node (if running)
if [ "${START_XDC_NODE}" = "true" ]; then
    if ! curl -sf -X POST http://localhost:8545 \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' > /dev/null 2>&1; then
        echo "WARN: XDC node RPC not responding"
    fi
fi

echo "OK"
exit 0
