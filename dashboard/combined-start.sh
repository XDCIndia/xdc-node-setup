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

# Start LFG peer discovery in background
(
  sleep 300  # wait 5 minutes for node to initialize
  echo "Checking peer count for LFG..."
  PEERS=$(curl -s -X POST http://localhost:8545 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null | jq -r '.result' 2>/dev/null)
  # Convert hex to decimal if needed
  if [[ "$PEERS" == 0x* ]]; then
    PEERS=$(printf "%d" "$PEERS" 2>/dev/null || echo "0")
  fi
  if [ "$PEERS" = "0" ] || [ "$PEERS" = "" ] || [ "$PEERS" = "null" ]; then
    echo "No peers found after 5 minutes, running LFG to fetch healthy peers..."
    ENODES=$(curl -s "https://net.xdc.network/api/v1/peers/healthy?format=text" 2>/dev/null)
    if [ -n "$ENODES" ]; then
      echo "Found $(echo "$ENODES" | wc -w) peers from SkyNet LFG"
      for enode in $ENODES; do
        curl -s -X POST http://localhost:8545 -H "Content-Type: application/json" \
          -d "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addPeer\",\"params\":[\"$enode\"],\"id\":1}" 2>/dev/null
        echo "Added peer: ${enode:0:50}..."
      done
    else
      echo "LFG API returned no peers"
    fi
  else
    echo "Node has $PEERS peers, LFG not needed"
  fi
) &

# Start Dashboard in production mode
# Use PORT env var if set, otherwise default to 3000
DASHBOARD_PORT=${PORT:-3000}
echo "Starting XDC Dashboard on port $DASHBOARD_PORT (production mode)..."
cd /app
exec npm start -- -p "$DASHBOARD_PORT" -H 0.0.0.0
