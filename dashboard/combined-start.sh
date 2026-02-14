#!/bin/bash
# Combined startup script for XDC Agent (Dashboard + SkyNet)

# Load SkyNet config if available (provides SKYNET_NODE_ID, SKYNET_API_KEY, etc.)
SKYNET_CONF="${SKYNET_CONF:-/etc/xdc-node/skynet.conf}"
# Docker may create skynet.conf as a directory if mount source was missing — fix it
if [ -d "$SKYNET_CONF" ]; then
  echo "WARNING: $SKYNET_CONF is a directory (Docker mount artifact). Replacing with file."
  rm -rf "$SKYNET_CONF"
  # Create minimal config — auto-registration will fill in the rest
  cat > "$SKYNET_CONF" <<EOCONF
SKYNET_API_URL=https://net.xdc.network/api/v1
SKYNET_API_KEY=${SKYNET_API_KEY:-}
SKYNET_NODE_NAME=$(hostname)
SKYNET_ROLE=fullnode
EOCONF
fi
if [ -f "$SKYNET_CONF" ]; then
  echo "Loading SkyNet config from $SKYNET_CONF"
  set -a  # auto-export all vars
  source "$SKYNET_CONF"
  set +a

  # Auto-register with SkyNet if no NODE_ID yet
  if [ -z "$SKYNET_NODE_ID" ] && [ -n "$SKYNET_API_KEY" ] && [ -n "$SKYNET_API_URL" ]; then
    echo "No SKYNET_NODE_ID found, auto-registering..."
    NODE_NAME="${SKYNET_NODE_NAME:-$(hostname)-$(curl -s -m 3 https://api.ipify.org | tail -c 8)}"
    PUBLIC_IP=$(curl -s -m 5 https://api.ipify.org || echo "unknown")
    REG_RESPONSE=$(curl -s -m 10 -X POST "${SKYNET_API_URL}/nodes/register" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${SKYNET_API_KEY}" \
      -d "{\"name\":\"${NODE_NAME}\",\"host\":\"${PUBLIC_IP}\",\"role\":\"${SKYNET_ROLE:-fullnode}\"}")
    
    NEW_ID=$(echo "$REG_RESPONSE" | jq -r '.data.nodeId // empty' 2>/dev/null)
    if [ -n "$NEW_ID" ]; then
      echo "SKYNET_NODE_ID=$NEW_ID" >> "$SKYNET_CONF"
      export SKYNET_NODE_ID="$NEW_ID"
      echo "✅ Registered with SkyNet as $NODE_NAME (ID: $NEW_ID)"
    else
      echo "⚠️  SkyNet registration failed: $REG_RESPONSE"
    fi
  fi
else
  echo "No SkyNet config found at $SKYNET_CONF — heartbeats disabled"
fi

# Start SkyNet Agent in background (legacy bash agent)
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
