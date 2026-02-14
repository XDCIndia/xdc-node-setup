#!/bin/bash
# Combined startup script for XDC Agent (Dashboard + SkyNet)

# Start SkyNet Agent in background
echo "Starting SkyNet Agent..."
(
  sleep 10  # wait for node to be ready
  while true; do
    /agent.sh 2>/dev/null
    sleep 60
  done
) &

# Start Dashboard (dev mode = no build step, fast startup)
echo "Starting XDC Dashboard on port 3000..."
cd /app
exec npx next dev -p 3000 -H 0.0.0.0
