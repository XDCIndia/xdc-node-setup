#!/bin/bash
# Combined startup script for XDC Agent (Dashboard + SkyNet)

# Ensure log directory exists
mkdir -p /var/log/xdc

# Load SkyNet config if available (provides SKYNET_NODE_ID, SKYNET_API_KEY, etc.)
SKYNET_CONF="${SKYNET_CONF:-/etc/xdc-node/skynet.conf}"
# Docker may create skynet.conf as a directory if mount source was missing — fix it
if [ -d "$SKYNET_CONF" ]; then
  echo "WARNING: $SKYNET_CONF is a directory (Docker mount artifact). Replacing with file." | tee -a /var/log/xdc/dashboard.log
  rm -rf "$SKYNET_CONF"
  # Create minimal config — auto-registration will fill in the rest
  cat > "$SKYNET_CONF" <<EOCONF
SKYNET_API_URL=https://net.xdc.network/api
SKYNET_API_KEY=${SKYNET_API_KEY:-}
SKYNET_NODE_NAME=$(hostname)
SKYNET_ROLE=fullnode
EOCONF
fi
if [ -f "$SKYNET_CONF" ]; then
  echo "Loading SkyNet config from $SKYNET_CONF" | tee -a /var/log/xdc/dashboard.log
  set -a  # auto-export all vars
  source "$SKYNET_CONF"
  set +a

  # Load persisted node ID from /tmp fallback (if conf was read-only)
  if [ -z "$SKYNET_NODE_ID" ] && [ -f /tmp/skynet-node-id ]; then
    source /tmp/skynet-node-id
  fi

  # Auto-register with SkyNet if no NODE_ID yet
  if [ -z "$SKYNET_NODE_ID" ] && [ -n "$SKYNET_API_URL" ]; then
    echo "No SKYNET_NODE_ID found, auto-registering..." | tee -a /var/log/xdc/dashboard.log
    # Include INSTANCE_NAME (client type) in auto-generated name
    CLIENT_TAG="${INSTANCE_NAME:+${INSTANCE_NAME}-}"
    NODE_NAME="${SKYNET_NODE_NAME:-${CLIENT_TAG}$(hostname)-$(curl -s -m 3 https://api.ipify.org | tail -c 8)}"
    PUBLIC_IP=$(curl -s -m 5 https://api.ipify.org || echo "unknown")
    # Build curl args — auth header only if API key is set
    CURL_ARGS=(-s -m 10 -X POST "${SKYNET_API_URL}/v1/nodes/register" -H "Content-Type: application/json")
    [ -n "$SKYNET_API_KEY" ] && CURL_ARGS+=(-H "Authorization: Bearer ${SKYNET_API_KEY}")
    CURL_ARGS+=(-d "{\"name\":\"${NODE_NAME}\",\"host\":\"${PUBLIC_IP}\",\"role\":\"${SKYNET_ROLE:-fullnode}\"}")
    REG_RESPONSE=$(curl "${CURL_ARGS[@]}")
    echo "Registration response: $REG_RESPONSE" | tee -a /var/log/xdc/dashboard.log
    
    NEW_ID=$(echo "$REG_RESPONSE" | jq -r '.data.nodeId // .nodeId // empty' 2>/dev/null)
    if [ -n "$NEW_ID" ]; then
      # Persist node ID — update conf file or use /tmp fallback
      if [ -f "$SKYNET_CONF" ] && sed -i "s/^SKYNET_NODE_ID=.*/SKYNET_NODE_ID=$NEW_ID/" "$SKYNET_CONF" 2>/dev/null; then
        # Also store node name if it was auto-generated
        sed -i "s/^SKYNET_NODE_NAME=.*/SKYNET_NODE_NAME=$NODE_NAME/" "$SKYNET_CONF" 2>/dev/null || true
        echo "✅ Updated $SKYNET_CONF with node ID" | tee -a /var/log/xdc/dashboard.log
      else
        echo "SKYNET_NODE_ID=$NEW_ID" > /tmp/skynet-node-id
        echo "⚠️  Could not write to $SKYNET_CONF, using /tmp/skynet-node-id" | tee -a /var/log/xdc/dashboard.log
      fi
      export SKYNET_NODE_ID="$NEW_ID"
      export SKYNET_NODE_NAME="$NODE_NAME"
      echo "✅ Registered with SkyNet as $NODE_NAME (ID: $NEW_ID)" | tee -a /var/log/xdc/dashboard.log
    else
      echo "⚠️  SkyNet registration failed: $REG_RESPONSE" | tee -a /var/log/xdc/dashboard.log
    fi
  fi
else
  echo "No SkyNet config found at $SKYNET_CONF — heartbeats disabled" | tee -a /var/log/xdc/dashboard.log
fi

# Start SkyNet heartbeat in background
# Sends metrics directly to SkyNet API
echo "Starting SkyNet heartbeat loop..." | tee -a /var/log/xdc/dashboard.log
(
  sleep 10  # quick startup
  while true; do
    # Get metrics from XDC node
    RPC_URL="${RPC_URL:-${XDC_RPC_URL:-http://localhost:8545}}"
    BLOCK_HEX=$(curl -s -m 5 -X POST "$RPC_URL" -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
    PEER_HEX=$(curl -s -m 5 -X POST "$RPC_URL" -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null | grep -o '"result":"[^"]*"' | cut -d'"' -f4)
    SYNCING=$(curl -s -m 5 -X POST "$RPC_URL" -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' 2>/dev/null | grep -o '"result":[^,}]*' | cut -d: -f2)
    
    BLOCK_NUM=0
    if [ -n "$BLOCK_HEX" ] && [ "$BLOCK_HEX" != "null" ]; then
      BLOCK_NUM=$(printf "%d" "$BLOCK_HEX" 2>/dev/null || echo "0")
    fi
    
    PEER_COUNT=0
    if [ -n "$PEER_HEX" ] && [ "$PEER_HEX" != "null" ]; then
      PEER_COUNT=$(printf "%d" "$PEER_HEX" 2>/dev/null || echo "0")
    fi
    
    IS_SYNCING=false
    if [ "$SYNCING" != "false" ]; then
      IS_SYNCING=true
    fi
    
    # Send heartbeat directly to SkyNet
    if [ -n "$SKYNET_API_URL" ] && [ -n "$SKYNET_NODE_ID" ]; then
      CURL_ARGS=(-s -m 15 -X POST "${SKYNET_API_URL}/v1/nodes/${SKYNET_NODE_ID}/heartbeat" -H "Content-Type: application/json")
      [ -n "$SKYNET_API_KEY" ] && CURL_ARGS+=(-H "Authorization: Bearer ${SKYNET_API_KEY}")
      CURL_ARGS+=(-d "{\"blockHeight\":$BLOCK_NUM,\"peerCount\":$PEER_COUNT,\"isSyncing\":$IS_SYNCING,\"clientType\":\"${CLIENT_TYPE:-geth}\",\"version\":\"${CLIENT_VERSION:-unknown}\"}")
      
      RESPONSE=$(curl "${CURL_ARGS[@]}" 2>&1)
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] heartbeat sent: block=$BLOCK_NUM peers=$PEER_COUNT response=$RESPONSE" | tee -a /var/log/xdc/heartbeat.log
    else
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] heartbeat skipped: no SKYNET_API_URL or SKYNET_NODE_ID" | tee -a /var/log/xdc/heartbeat.log
    fi
    
    sleep 60
  done
) &

# Start LFG peer discovery in background — gentle, recurring
# Checks every 10 min, adds max 5 shuffled peers with 3s delays
LFG_MIN_PEERS=${LFG_MIN_PEERS:-3}
LFG_MAX_ADD=${LFG_MAX_ADD:-5}
LFG_CHECK_INTERVAL=${LFG_CHECK_INTERVAL:-600}
(
  sleep 120  # wait 2 minutes for node to initialize
  while true; do
    NODE_RPC="${RPC_URL:-http://localhost:8545}"
    PEER_HEX=$(curl -s -m 5 -X POST "$NODE_RPC" -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null | \
      grep -o '"result":"[^"]*"' | cut -d'"' -f4)
    PEER_COUNT=0
    if [ -n "$PEER_HEX" ] && [ "$PEER_HEX" != "null" ]; then
      PEER_COUNT=$(printf "%d" "$PEER_HEX" 2>/dev/null || echo "0")
    fi

    if [ "$PEER_COUNT" -lt "$LFG_MIN_PEERS" ]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] LFG: $PEER_COUNT peers < $LFG_MIN_PEERS, fetching from SkyNet..." | tee -a /var/log/xdc/lfg.log
      # Get enodes, shuffle, take max
      ALL_ENODES=$(curl -s -m 10 "https://net.xdc.network/api/v1/peers/healthy?format=text" 2>/dev/null)
      if [ -n "$ALL_ENODES" ]; then
        SHUFFLED=$(echo "$ALL_ENODES" | sort -R | head -n "$LFG_MAX_ADD")
        ADDED=0
        for enode in $SHUFFLED; do
          RES=$(curl -s -m 5 -X POST "$NODE_RPC" -H "Content-Type: application/json" \
            -d "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addPeer\",\"params\":[\"$enode\"],\"id\":1}" 2>/dev/null)
          ADDED=$((ADDED+1))
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] LFG: +peer ${enode:0:40}... ($ADDED/$LFG_MAX_ADD)" | tee -a /var/log/xdc/lfg.log
          sleep 3
        done
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] LFG: added $ADDED peers, next check in ${LFG_CHECK_INTERVAL}s" | tee -a /var/log/xdc/lfg.log
      else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] LFG: SkyNet API returned no peers" | tee -a /var/log/xdc/lfg.log
      fi
    else
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] LFG: $PEER_COUNT peers OK (min $LFG_MIN_PEERS)" | tee -a /var/log/xdc/lfg.log
    fi

    sleep "$LFG_CHECK_INTERVAL"
  done
) &

# Start Next.js dashboard
echo "Starting SkyOne Dashboard on port 3000..." | tee -a /var/log/xdc/dashboard.log
cd /app && exec npx next start -p 3000
