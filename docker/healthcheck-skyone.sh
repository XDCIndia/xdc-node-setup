#!/bin/bash
# Health check for all services

# Check Nginx
if ! curl -sf http://localhost:7070/api/health > /dev/null; then
    echo "FAIL: Dashboard not responding"
    exit 1
fi

# Check SkyNet Agent (if configured)
if [ -f /etc/xdc-node/skynet.conf ]; then
    if ! pgrep -f "skynet-agent.sh" > /dev/null; then
        echo "WARN: SkyNet agent not running"
    fi
fi

echo "OK: All services healthy"
exit 0
