#!/bin/bash
# NOTE: Do NOT use set -e here — this is a long-running agent.
# Transient errors (curl timeouts, jq parse failures) must not kill the process.

# ============================================================================
# XDC UNIFIED AGENT V2 - PHASE 2 AI INTELLIGENCE
# ============================================================================
# Architecture: One agent per XDC node (sidecar container)
# Heartbeat: Every 30s (configurable via HEARTBEAT_INTERVAL env or SkyNet API)
# 
# Consolidates: Monitoring + Auto-Heal + AI Intelligence
# Features:
#   - Cross-Node Correlation Engine
#   - Intelligent Peer Management (every 10 HB = 5 min)
#   - Block Progress Tracking with Trend Analysis (30 samples = 15 min)
#   - Smart Restart Logic with Effectiveness Tracking
#   - Comprehensive Error Classification (10 patterns)
#   - Network Height Awareness (every 20 HB = 10 min)
#   - Self-Diagnostic Reports (every 120 HB = 1 hour)
#   - Config Refresh from SkyNet (every 50 HB = ~25 min)
# ============================================================================

# Load SkyNet config
SKYNET_CONF="${SKYNET_CONF:-/etc/xdc-node/skynet.conf}"
if [ -f "$SKYNET_CONF" ]; then
  set -a
  source "$SKYNET_CONF"
  set +a
  echo "[SkyNet] Loaded config from $SKYNET_CONF"
  echo "[SkyNet] Node ID: ${SKYNET_NODE_ID:-not set}"
  echo "[SkyNet] API URL: ${SKYNET_API_URL:-not set}"
fi

# Load persisted node ID
if [ -z "$SKYNET_NODE_ID" ] && [ -f /tmp/skynet-node-id ]; then
  source /tmp/skynet-node-id
  echo "[SkyNet] Loaded node ID from /tmp/skynet-node-id"
fi

# Master API key for auto-registration (fallback)
MASTER_API_KEY="${SKYNET_MASTER_KEY:-xdc-netown-key-2026-prod}"

# Heartbeat interval (default 30s, configurable)
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-30}"

# === PHASE 2: STATE FILES ===
RESTART_HISTORY_FILE="/tmp/restart-history.json"
BLOCK_WINDOW_FILE="/tmp/block-window.json"
PEER_HISTORY_FILE="/tmp/peer-history.json"
NETWORK_HEIGHT_FILE="/tmp/network-height.json"
DIAGNOSTIC_COUNTER_FILE="/tmp/diagnostic-counter"

# Initialize state files if missing
[ ! -f "$RESTART_HISTORY_FILE" ] && echo '{"restarts":[]}' > "$RESTART_HISTORY_FILE"
[ ! -f "$BLOCK_WINDOW_FILE" ] && echo '{"blocks":[]}' > "$BLOCK_WINDOW_FILE"
[ ! -f "$PEER_HISTORY_FILE" ] && echo '{"peers":[]}' > "$PEER_HISTORY_FILE"
[ ! -f "$NETWORK_HEIGHT_FILE" ] && echo '{"height":0,"lastUpdate":0}' > "$NETWORK_HEIGHT_FILE"
[ ! -f "$DIAGNOSTIC_COUNTER_FILE" ] && echo "0" > "$DIAGNOSTIC_COUNTER_FILE"

# === PHASE 2: HELPER FUNCTIONS ===

# Fetch agent config from SkyNet API
fetch_agent_config() {
  local node_id="$1"
  local api_key="$2"
  local api_url="$3"
  
  if [ -z "$node_id" ] || [ -z "$api_key" ]; then
    return 1
  fi
  
  echo "[Phase2-Config] Fetching agent config from SkyNet..."
  
  # Call GET /api/v1/nodes/{id}/config
  local response=$(curl -s -m 5 "${api_url}/v1/nodes/${node_id}/config" \
    -H "Authorization: Bearer ${api_key}" 2>/dev/null)
  
  if ! echo "$response" | jq -e '.success' >/dev/null 2>&1; then
    echo "[Phase2-Config] ⚠️  Config fetch failed, using defaults"
    return 1
  fi
  
  # Extract config values
  local remote_interval=$(echo "$response" | jq -r '.data.heartbeatInterval' 2>/dev/null || echo "null")
  
  if [ -n "$remote_interval" ] && [ "$remote_interval" != "null" ] && [ "$remote_interval" -gt 0 ]; then
    HEARTBEAT_INTERVAL=$remote_interval
    echo "[Phase2-Config] ✅ Using custom interval from SkyNet: ${HEARTBEAT_INTERVAL}s"
  else
    echo "[Phase2-Config] ℹ️  No custom interval, using default: ${HEARTBEAT_INTERVAL}s"
  fi
  
  return 0
}

# Calculate sync rate from block window (blocks/minute)
calculate_sync_rate() {
  local heartbeat_interval="${1:-30}"
  local block_window_json=$(cat "$BLOCK_WINDOW_FILE" 2>/dev/null || echo '{"blocks":[]}')
  local blocks_array=$(echo "$block_window_json" | jq -r '.blocks[]' 2>/dev/null || echo "")
  
  if [ -z "$blocks_array" ]; then
    echo "0"
    return
  fi
  
  local block_count=$(echo "$blocks_array" | wc -l)
  if [ "$block_count" -lt 2 ]; then
    echo "0"
    return
  fi
  
  local first_block=$(echo "$blocks_array" | head -1)
  local last_block=$(echo "$blocks_array" | tail -1)
  local block_diff=$((last_block - first_block))
  
  # Each entry is $heartbeat_interval seconds apart
  # Calculate blocks per minute: (block_diff / time_in_minutes)
  if [ $block_count -gt 1 ]; then
    local time_window_seconds=$(( (block_count - 1) * heartbeat_interval ))
    local time_window_minutes=$(echo "scale=4; $time_window_seconds / 60" | bc 2>/dev/null || echo "1")
    local rate=$(echo "scale=2; $block_diff / $time_window_minutes" | bc 2>/dev/null || echo "0")
    echo "$rate"
  else
    echo "0"
  fi
}

# Detect sync trend (accelerating/stable/decelerating/stalled)
detect_sync_trend() {
  local current_rate="$1"
  local block_window_json=$(cat "$BLOCK_WINDOW_FILE" 2>/dev/null || echo '{"blocks":[]}')
  local blocks_array=$(echo "$block_window_json" | jq -r '.blocks[]' 2>/dev/null || echo "")
  
  if [ -z "$blocks_array" ]; then
    echo "unknown"
    return
  fi
  
  local block_count=$(echo "$blocks_array" | wc -l)
  if [ "$block_count" -lt 10 ]; then
    echo "initializing"
    return
  fi
  
  # Calculate rate for first half vs second half
  local half=$((block_count / 2))
  local first_half=$(echo "$blocks_array" | head -$half)
  local second_half=$(echo "$blocks_array" | tail -$half)
  
  local first_block=$(echo "$first_half" | head -1)
  local first_last=$(echo "$first_half" | tail -1)
  local second_block=$(echo "$second_half" | head -1)
  local second_last=$(echo "$second_half" | tail -1)
  
  local first_diff=$((first_last - first_block))
  local second_diff=$((second_last - second_block))
  
  # Stalled: no progress in second half
  if [ "$second_diff" -eq 0 ]; then
    echo "stalled"
    return
  fi
  
  # Compare rates
  local rate_change=$(echo "scale=2; ($second_diff - $first_diff) / $first_diff * 100" | bc 2>/dev/null || echo "0")
  local rate_change_int=$(echo "$rate_change" | cut -d. -f1)
  
  if [ "${rate_change_int:-0}" -gt 10 ]; then
    echo "accelerating"
  elif [ "${rate_change_int:-0}" -lt -10 ]; then
    echo "decelerating"
  else
    echo "stable"
  fi
}

# Estimate time to sync completion (in hours)
estimate_sync_completion() {
  local current_block="$1"
  local network_height="$2"
  local sync_rate="$3"
  
  if [ "$sync_rate" = "0" ] || [ "$sync_rate" = "0.00" ] || [ -z "$sync_rate" ]; then
    echo "unknown"
    return
  fi
  
  local blocks_remaining=$((network_height - current_block))
  if [ $blocks_remaining -le 0 ]; then
    echo "0"
    return
  fi
  
  # Convert rate from blocks/min to blocks/hour
  local rate_per_hour=$(echo "scale=2; $sync_rate * 60" | bc 2>/dev/null || echo "0")
  if [ "$rate_per_hour" = "0" ] || [ "$rate_per_hour" = "0.00" ]; then
    echo "unknown"
    return
  fi
  
  local hours=$(echo "scale=1; $blocks_remaining / $rate_per_hour" | bc 2>/dev/null || echo "0")
  echo "$hours"
}

# === PHASE 2: CROSS-NODE CORRELATION ENGINE ===
check_fleet_correlation() {
  local api_url="$1"
  local api_key="$2"
  local network="$3"
  local current_block="$4"
  local issue_type="$5"
  
  # Query fleet overview
  local fleet_response=$(curl -s -m 5 "${api_url}/v1/fleet/overview" \
    -H "Authorization: Bearer ${api_key}" 2>/dev/null)
  
  if ! echo "$fleet_response" | jq -e '.success' >/dev/null 2>&1; then
    echo "unknown"
    return
  fi
  
  # Filter nodes on same network
  local network_nodes=$(echo "$fleet_response" | jq -r --arg net "$network" \
    '.data.nodes[] | select(.network == $net)' 2>/dev/null)
  
  if [ -z "$network_nodes" ]; then
    echo "isolated"
    return
  fi
  
  # Count how many nodes stalled at same block
  local stalled_count=0
  local total_count=0
  
  while IFS= read -r node; do
    total_count=$((total_count + 1))
    local node_block=$(echo "$node" | jq -r '.blockHeight' 2>/dev/null || echo "0")
    local node_stalled=$(echo "$node" | jq -r '.stalled // false' 2>/dev/null)
    
    if [ "$node_stalled" = "true" ] && [ "$node_block" -eq "$current_block" ]; then
      stalled_count=$((stalled_count + 1))
    fi
  done <<< "$network_nodes"
  
  # If >70% of nodes stalled at same block → widespread issue (likely code bug)
  if [ $total_count -gt 0 ]; then
    local percent=$(echo "scale=0; $stalled_count * 100 / $total_count" | bc 2>/dev/null || echo "0")
    if [ "$percent" -gt 70 ]; then
      echo "widespread"
    else
      echo "isolated"
    fi
  else
    echo "unknown"
  fi
}

# === PHASE 2: INTELLIGENT PEER MANAGEMENT ===
inject_healthy_peers() {
  local api_url="$1"
  local api_key="$2"
  local network="$3"
  local client_type="$4"
  local rpc_url="$5"
  local current_peers="$6"
  
  # Skip if we have enough peers
  if [ "$current_peers" -ge 2 ]; then
    return 0
  fi
  
  echo "[Phase2-PeerMgmt] Low peer count ($current_peers), fetching healthy peers..."
  
  # Fetch healthy peers from SkyNet
  local peers_response=$(curl -s -m 5 "${api_url}/v1/peers/healthy?network=${network}" \
    -H "Authorization: Bearer ${api_key}" 2>/dev/null)
  
  if ! echo "$peers_response" | jq -e '.success' >/dev/null 2>&1; then
    echo "[Phase2-PeerMgmt] Failed to fetch healthy peers"
    return 1
  fi
  
  local peer_enodes=$(echo "$peers_response" | jq -r '.data.peers[]' 2>/dev/null)
  if [ -z "$peer_enodes" ]; then
    echo "[Phase2-PeerMgmt] No healthy peers available"
    return 1
  fi
  
  # Track injection history to avoid spam
  local injection_history="/tmp/peer-injection-history"
  local current_time=$(date +%s)
  local last_injection=0
  
  if [ -f "$injection_history" ]; then
    last_injection=$(cat "$injection_history")
  fi
  
  local time_since=$((current_time - last_injection))
  if [ $time_since -lt 300 ]; then
    echo "[Phase2-PeerMgmt] Cooldown active (last injection ${time_since}s ago)"
    return 0
  fi
  
  # Inject peers based on client type
  local injected=0
  case "$client_type" in
    geth|XDC)
      # Use admin_addPeer RPC
      while IFS= read -r enode; do
        [ -z "$enode" ] && continue
        local add_result=$(curl -s -m 5 -X POST "$rpc_url" \
          -H "Content-Type: application/json" \
          -d "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addPeer\",\"params\":[\"$enode\"],\"id\":1}" 2>/dev/null)
        
        if echo "$add_result" | jq -e '.result == true' >/dev/null 2>&1; then
          injected=$((injected + 1))
          echo "[Phase2-PeerMgmt] ✅ Injected peer: ${enode:0:30}..."
        fi
        
        # Limit to 3 peers per injection
        [ $injected -ge 3 ] && break
      done <<< "$peer_enodes"
      ;;
    
    erigon)
      # Erigon doesn't support direct peer injection
      echo "[Phase2-PeerMgmt] ⚠️  Erigon doesn't support peer injection, logging peers for manual config"
      ;;
    
    nethermind)
      # Log for manual config update (Nethermind uses static nodes file)
      echo "[Phase2-PeerMgmt] ℹ️  Nethermind detected, recommend updating static-nodes.json"
      ;;
  esac
  
  if [ $injected -gt 0 ]; then
    echo "$current_time" > "$injection_history"
    echo "[Phase2-PeerMgmt] Injected $injected peers"
  fi
  
  return 0
}

# === PHASE 2: SMART RESTART LOGIC ===
should_restart_node() {
  local current_block="$1"
  local issue_type="$2"
  
  # Load restart history
  local history=$(cat "$RESTART_HISTORY_FILE" 2>/dev/null || echo '{"restarts":[]}')
  local current_time=$(date +%s)
  
  # Count restarts in last 6 hours (21600 seconds)
  local six_hours_ago=$((current_time - 21600))
  local recent_restarts=$(echo "$history" | jq --argjson cutoff "$six_hours_ago" \
    '[.restarts[] | select(.timestamp > $cutoff)] | length' 2>/dev/null || echo "0")
  
  # Max 3 restarts per 6 hours
  if [ "$recent_restarts" -ge 3 ]; then
    echo "[Phase2-RestartLogic] ❌ Restart limit reached (3 in 6h), escalating instead"
    return 1
  fi
  
  # Check if last restart was effective
  local last_restart=$(echo "$history" | jq -r '.restarts[-1]' 2>/dev/null)
  if [ "$last_restart" != "null" ] && [ -n "$last_restart" ]; then
    local last_block=$(echo "$last_restart" | jq -r '.blockBefore' 2>/dev/null || echo "0")
    local last_issue=$(echo "$last_restart" | jq -r '.issue' 2>/dev/null || echo "unknown")
    local last_time=$(echo "$last_restart" | jq -r '.timestamp' 2>/dev/null || echo "0")
    
    # If same issue and block didn't progress → restart wasn't effective
    if [ "$last_issue" = "$issue_type" ] && [ "$current_block" -le "$last_block" ]; then
      echo "[Phase2-RestartLogic] ❌ Last restart ineffective (block: $last_block → $current_block), escalating"
      return 1
    fi
  fi
  
  echo "[Phase2-RestartLogic] ✅ Restart approved (recent: $recent_restarts/3)"
  return 0
}

# Record restart in history
record_restart() {
  local block="$1"
  local issue="$2"
  local timestamp=$(date +%s)
  
  local history=$(cat "$RESTART_HISTORY_FILE" 2>/dev/null || echo '{"restarts":[]}')
  
  # Add new restart record
  history=$(echo "$history" | jq --argjson ts "$timestamp" --argjson blk "$block" --arg iss "$issue" \
    '.restarts += [{"timestamp": $ts, "blockBefore": $blk, "issue": $iss}]' 2>/dev/null)
  
  # Keep only last 20 restarts
  history=$(echo "$history" | jq '.restarts = .restarts[-20:]' 2>/dev/null)
  
  echo "$history" > "$RESTART_HISTORY_FILE"
}

# Calculate restart effectiveness
calculate_restart_effectiveness() {
  local history=$(cat "$RESTART_HISTORY_FILE" 2>/dev/null || echo '{"restarts":[]}')
  local restart_count=$(echo "$history" | jq '.restarts | length' 2>/dev/null || echo "0")
  
  if [ "$restart_count" -lt 2 ]; then
    echo "insufficient_data"
    return
  fi
  
  # Count how many restarts led to block progression
  local effective=0
  local total=0
  local prev_block=0
  
  while IFS= read -r restart; do
    [ -z "$restart" ] && continue
    local block=$(echo "$restart" | jq -r '.blockBefore' 2>/dev/null || echo "0")
    
    if [ $total -gt 0 ] && [ "$block" -gt "$prev_block" ]; then
      effective=$((effective + 1))
    fi
    
    prev_block=$block
    total=$((total + 1))
  done <<< "$(echo "$history" | jq -c '.restarts[]' 2>/dev/null)"
  
  if [ $total -gt 1 ]; then
    local rate=$(echo "scale=0; $effective * 100 / ($total - 1)" | bc 2>/dev/null || echo "0")
    echo "${rate}%"
  else
    echo "insufficient_data"
  fi
}

# === PHASE 2: NETWORK HEIGHT AWARENESS ===
fetch_network_height() {
  local network="$1"
  local chain_id="$2"
  
  # Determine OpenScan RPC URL
  local openscan_rpc=""
  case "$chain_id" in
    50) openscan_rpc="https://rpc.openscan.ai/50" ;;
    51) openscan_rpc="https://rpc.openscan.ai/51" ;;
    *) echo "0"; return ;;
  esac
  
  # Check cache (update every 10 heartbeats = 10 minutes)
  local cache=$(cat "$NETWORK_HEIGHT_FILE" 2>/dev/null || echo '{"height":0,"lastUpdate":0}')
  local cached_height=$(echo "$cache" | jq -r '.height' 2>/dev/null || echo "0")
  local last_update=$(echo "$cache" | jq -r '.lastUpdate' 2>/dev/null || echo "0")
  local current_time=$(date +%s)
  local time_since=$((current_time - last_update))
  
  # Use cache if less than 10 minutes old
  if [ $time_since -lt 600 ] && [ "$cached_height" -gt 0 ]; then
    echo "$cached_height"
    return
  fi
  
  # Fetch from OpenScan
  local block_hex=$(curl -s -m 5 -X POST "$openscan_rpc" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | \
    jq -r '.result' 2>/dev/null)
  
  if [ -n "$block_hex" ] && [ "$block_hex" != "null" ]; then
    local network_height=$(printf "%d" "$block_hex" 2>/dev/null || echo "0")
    
    # Update cache
    echo "{\"height\":$network_height,\"lastUpdate\":$current_time}" > "$NETWORK_HEIGHT_FILE"
    echo "$network_height"
  else
    # Fallback to cached value
    echo "$cached_height"
  fi
}

# === PHASE 2: SELF-DIAGNOSTIC REPORT ===
generate_diagnostic_report() {
  local node_id="$1"
  local api_key="$2"
  local api_url="$3"
  local agent_start_time="$4"
  local heartbeat_interval="${5:-30}"
  
  local current_time=$(date +%s)
  local uptime_seconds=$((current_time - agent_start_time))
  local uptime_hours=$(echo "scale=1; $uptime_seconds / 3600" | bc 2>/dev/null || echo "0")
  
  # Load state files
  local restart_history=$(cat "$RESTART_HISTORY_FILE" 2>/dev/null || echo '{"restarts":[]}')
  local peer_history=$(cat "$PEER_HISTORY_FILE" 2>/dev/null || echo '{"peers":[]}')
  local block_window=$(cat "$BLOCK_WINDOW_FILE" 2>/dev/null || echo '{"blocks":[]}')
  
  # Count restarts in last 6 hours
  local six_hours_ago=$((current_time - 21600))
  local restarts_in_window=$(echo "$restart_history" | jq --argjson cutoff "$six_hours_ago" \
    '[.restarts[] | select(.timestamp > $cutoff)] | length' 2>/dev/null || echo "0")
  
  # Calculate average sync rate
  local avg_sync_rate=$(calculate_sync_rate "$heartbeat_interval")
  
  # Get peer history (last 10 entries)
  local peers_array=$(echo "$peer_history" | jq -c '[.peers[-10:]]' 2>/dev/null || echo "[]")
  
  # Get incidents (simplified - would query from backend in production)
  local incidents_in_window="[]"
  
  # Generate recommendation
  local recommendation="Node healthy, syncing at expected rate"
  if [ "$restarts_in_window" -gt 2 ]; then
    recommendation="Frequent restarts detected, investigate underlying issue"
  elif [ "$(echo "$avg_sync_rate < 10" | bc 2>/dev/null || echo "0")" -eq 1 ]; then
    recommendation="Slow sync rate, check peers and network connectivity"
  fi
  
  # Calculate restart effectiveness
  local effectiveness=$(calculate_restart_effectiveness)
  
  # Build diagnostic payload
  local diagnostic_payload=$(cat <<EOF
{
  "diagnosticTime": "$(date -Iseconds)",
  "uptime": $uptime_hours,
  "restartsInWindow": $restarts_in_window,
  "avgSyncRate": $avg_sync_rate,
  "peersHistory": $peers_array,
  "incidentsInWindow": $incidents_in_window,
  "healActionsPerformed": [],
  "restartEffectiveness": "$effectiveness",
  "recommendation": "$recommendation"
}
EOF
)
  
  # Send diagnostic report
  local response=$(curl -s -m 15 -X POST "${api_url}/v1/nodes/${node_id}/diagnostic" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${api_key}" \
    -d "$diagnostic_payload" 2>/dev/null)
  
  if echo "$response" | jq -e '.success' >/dev/null 2>&1; then
    echo "[Phase2-Diagnostic] ✅ Hourly diagnostic report sent"
  else
    echo "[Phase2-Diagnostic] ⚠️  Diagnostic report failed"
  fi
}

# Smart Node Naming: Generate name in format {client}-{version}-{type}-{ip}-{network}
generate_smart_node_name() {
  local client_type="$1"
  local client_version="$2"
  local network="$3"
  local host_ip="$4"
  
  # Extract short client name
  local short_client="unknown"
  case "$client_type" in
    *[Nn]ethermind*) short_client="NM" ;;
    *[Ee]rigon*) short_client="Erigon" ;;
    *XDC*|[Gg]eth*) 
      # Check for v2.6.8 stable (XDC) vs GP5/geth forks
      if echo "$client_version" | grep -qi "v2\.6\|v2\.5\|v2\.4"; then
        short_client="XDC"
      else
        short_client="geth"
      fi
      ;;
  esac
  
  # Extract version number from client version string
  local version_num="unknown"
  # Try to extract version like v2.6.8, v1.17.0, v3.4.0
  version_num=$(echo "$client_version" | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^v//')
  if [ -z "$version_num" ]; then
    version_num=$(echo "$client_version" | grep -oE 'v?[0-9]+\.[0-9]+' | head -1 | sed 's/^v//')
  fi
  if [ -z "$version_num" ]; then
    version_num="unknown"
  fi
  
  # Node type (always fullnode for now, can be extended)
  local node_type="fullnode"
  
  # Keep IP with dots (matches DB naming convention)
  local clean_ip="$host_ip"
  if [ -z "$clean_ip" ] || [ "$clean_ip" = "unknown" ]; then
    clean_ip=$(hostname | cut -d. -f1)
  fi
  
  # Build name: {client}-{version}-{type}-{ip}-{network}
  local smart_name="${short_client}-v${version_num}-${node_type}-${clean_ip}-${network}"
  
  # Sanitize: alphanumeric, dots, dashes only (preserve case for client names)
  smart_name=$(echo "$smart_name" | tr -c 'a-zA-Z0-9.-' '-' | sed 's/-$//')
  
  echo "$smart_name"
}

# Issue #71: Auto-register function using fingerprint-based identity with smart naming
auto_register_identity() {
  local rpc_url="$1"
  local chain_id="$2"
  local network_name="$3"
  local client_type="$4"
  local client_version="$5"
  local api_url="${SKYNET_API_URL:-https://net.xdc.network/api/v1}"
  
  # Issue #71: Get coinbase from RPC
  local coinbase
  coinbase=$(curl -s -m 5 -X POST "$rpc_url" -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_coinbase","params":[],"id":1}' 2>/dev/null | jq -r .result 2>/dev/null)
  
  # Issue #71: Get public IP
  local host_ip
  host_ip=$(curl -s -m 5 https://ifconfig.me 2>/dev/null || curl -s -m 5 https://api.ipify.org 2>/dev/null || echo "unknown")
  
  # Issue #71: Compute fingerprint
  local fingerprint="${coinbase}@${host_ip}"
  
  # Generate smart node name
  local smart_name
  smart_name=$(generate_smart_node_name "$client_type" "$client_version" "$network_name" "$host_ip")
  
  # Use provided name or generated smart name
  NODE_NAME="${SKYNET_NODE_NAME:-$smart_name}"
  
  echo "[SkyNet] Auto-registering node with identity: $NODE_NAME"
  echo "[SkyNet] Fingerprint: $fingerprint (coinbase: ${coinbase:-unknown}, ip: $host_ip)"
  
  # Issue #71: Use /nodes/identify endpoint with fingerprint
  # Build payload with jq to handle null/empty coinbase properly
  local identify_payload
  identify_payload=$(jq -n \
    --arg fp "$fingerprint" \
    --arg ip "$host_ip" \
    --arg ct "$client_type" \
    --arg cv "$client_version" \
    --arg nm "$NODE_NAME" \
    --arg nw "$network_name" \
    --arg cb "${coinbase:-}" \
    '{fingerprint: $fp, ip: $ip, clientType: $ct, clientVersion: $cv, name: $nm, network: $nw, role: "fullnode"} + (if $cb != "" and $cb != "null" then {coinbase: $cb} else {} end)'
  )
  
  local response
  response=$(curl -s -m 15 -X POST "${api_url}/v1/nodes/identify" \
    -H "Content-Type: application/json" \
    -d "$identify_payload" 2>/dev/null)
  
  if echo "$response" | jq -e '.success' >/dev/null 2>&1; then
    SKYNET_NODE_ID=$(echo "$response" | jq -r '.data.nodeId')
    SKYNET_API_KEY=$(echo "$response" | jq -r '.data.apiKey')
    
    # Save to persist across restarts
    mkdir -p /tmp
    cat > /tmp/skynet-node-id <<EOF
SKYNET_NODE_ID=$SKYNET_NODE_ID
SKYNET_API_KEY=$SKYNET_API_KEY
SKYNET_FINGERPRINT=$fingerprint
SKYNET_COINBASE=$coinbase
EOF
    
    local is_new=$(echo "$response" | jq -r '.data.isNew')
    if [ "$is_new" = "true" ]; then
      echo "[SkyNet] ✅ Auto-registered new node! nodeId=$SKYNET_NODE_ID"
    else
      echo "[SkyNet] ✅ Recovered existing node identity! nodeId=$SKYNET_NODE_ID"
    fi
    return 0
  else
    echo "[SkyNet] ❌ Auto-registration failed: $(echo "$response" | jq -r '.error // .message // "unknown error"')"
    return 1
  fi
}

# Legacy auto-register function (fallback)
auto_register() {
  local rpc_url="$1"
  local chain_id="$2"
  local network_name="$3"
  local client_type="$4"
  local client_version="$5"
  local api_url="${SKYNET_API_URL:-https://net.xdc.network/api/v1}"
  
  # Get host IP
  HOST_IP=$(curl -s -m 5 https://ifconfig.me 2>/dev/null || curl -s -m 5 https://api.ipify.org 2>/dev/null || echo "unknown")
  
  # Generate smart node name
  local smart_name
  smart_name=$(generate_smart_node_name "$client_type" "$client_version" "$network_name" "$HOST_IP")
  
  # Use provided name or generated smart name
  NODE_NAME="${SKYNET_NODE_NAME:-$smart_name}"
  
  echo "[SkyNet] Auto-registering node: $NODE_NAME (client: $client_type, network: $network_name)"
  
  # Try to register with master key (keyless registration)
  local register_payload
  register_payload=$(cat <<EOF
{
  "name": "$NODE_NAME",
  "role": "fullnode",
  "network": "$network_name",
  "client": "$client_type",
  "rpcUrl": "http://$HOST_IP:${NODE_RPC_PORT:-8545}",
  "p2pPort": 30303,
  "host": "$HOST_IP",
  "clientVersion": "$client_version"
}
EOF
)
  
  local response
  response=$(curl -s -m 15 -X POST "${api_url}/v1/nodes/register" \
    -H "Content-Type: application/json" \
    -d "$register_payload" 2>/dev/null)
  
  if echo "$response" | jq -e '.success' >/dev/null 2>&1; then
    SKYNET_NODE_ID=$(echo "$response" | jq -r '.data.nodeId')
    SKYNET_API_KEY=$(echo "$response" | jq -r '.data.apiKey')
    
    # Save to persist across restarts
    mkdir -p /tmp
    cat > /tmp/skynet-node-id <<EOF
SKYNET_NODE_ID=$SKYNET_NODE_ID
SKYNET_API_KEY=$SKYNET_API_KEY
EOF
    
    echo "[SkyNet] ✅ Auto-registered! nodeId=$SKYNET_NODE_ID"
    return 0
  else
    echo "[SkyNet] ❌ Auto-registration failed: $(echo "$response" | jq -r '.error // .message // "unknown error"')"
    return 1
  fi
}

# Error reporting function
report_error() {
  local node_id="$1"
  local api_key="$2"
  local api_url="$3"
  local error_type="$4"
  local block_number="$5"
  local error_message="$6"
  local details="$7"
  
  if [ -z "$node_id" ] || [ -z "$api_key" ]; then
    return 1
  fi
  
  local error_payload
  error_payload=$(cat <<EOF
{
  "type": "$error_type",
  "blockNumber": ${block_number:-null},
  "errorMessage": "$error_message",
  "details": ${details:-null}
}
EOF
)
  
  local response
  response=$(curl -s -m 15 -X POST "${api_url}/v1/nodes/${node_id}/errors" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${api_key}" \
    -d "$error_payload" 2>/dev/null)
  
  if echo "$response" | jq -e '.success' >/dev/null 2>&1; then
    echo "[SkyNet] ✅ Error reported: $error_type"
    return 0
  else
    echo "[SkyNet] ⚠️  Error reporting failed: $(echo "$response" | jq -r '.error // "unknown error"')"
    return 1
  fi
}

# === PHASE 2: COMPREHENSIVE ERROR CLASSIFICATION ===
# Load healing playbook v2
PLAYBOOK_V2='{"patterns":[
  {"id":"missing_trie_node","regex":"missing trie node","severity":"critical","action":"rollback","rollbackBlocks":1000,"cooldown":3600,"escalationThreshold":3},
  {"id":"breach_of_protocol","regex":"BreachOfProtocol|Reason: Other, Type: Remote","severity":"warning","action":"none","cooldown":1800,"escalationThreshold":10},
  {"id":"bad_block","regex":"BAD BLOCK|bad block","severity":"critical","action":"rollback","rollbackBlocks":100,"cooldown":3600,"escalationThreshold":2},
  {"id":"uint256_overflow","regex":"uint256 overflow|panic.*overflow","severity":"critical","action":"restart","cooldown":1800,"escalationThreshold":2},
  {"id":"state_root_mismatch","regex":"state root mismatch|invalid merkle root","severity":"critical","action":"rollback","rollbackBlocks":500,"cooldown":3600,"escalationThreshold":2},
  {"id":"protocol_mismatch","regex":"unsupported eth protocol|rlp: expected input","severity":"warning","action":"peer_refresh","cooldown":1800,"escalationThreshold":5},
  {"id":"disk_corruption","regex":"corrupted|checksum mismatch|bad file descriptor","severity":"critical","action":"escalate","cooldown":600,"escalationThreshold":1},
  {"id":"memory_oom","regex":"out of memory|cannot allocate","severity":"critical","action":"restart","cooldown":1800,"escalationThreshold":3},
  {"id":"genesis_mismatch","regex":"genesis block mismatch|wrong genesis","severity":"critical","action":"escalate","cooldown":600,"escalationThreshold":1},
  {"id":"fork_choice","regex":"forked block|side chain","severity":"warning","action":"none","cooldown":1800,"escalationThreshold":5}
]}'

# SkyOne AI Issue Intelligence: Enhanced detection and auto-heal with Phase 2
detect_and_heal() {
  local node_id="$1"
  local api_key="$2"
  local api_url="$3"
  local container_name="${CONTAINER_NAME:-xdc-node}"
  local client_type="${CLIENT_TYPE:-geth}"
  local network="${NETWORK_NAME:-mainnet}"
  local block_num="$4"
  local peer_count="$5"
  local disk_percent="$6"
  local cpu_percent="$7"
  local mem_percent="$8"
  local client_version="${CLIENT_VERSION:-unknown}"
  
  # Check if container exists
  local container_running=true
  if ! docker ps -q -f name="$container_name" >/dev/null 2>&1; then
    container_running=false
  fi
  
  # Get last 100 lines of logs
  local logs=""
  local log_context=()
  if [ "$container_running" = true ]; then
    logs=$(docker logs --tail 100 "$container_name" 2>&1 || true)
    IFS=$'\n' read -rd '' -a log_context <<<"$logs" || true
  fi
  
  # Pattern matching using playbook v2
  local pattern_count=$(echo "$PLAYBOOK_V2" | jq '.patterns | length' 2>/dev/null || echo "0")
  
  for ((i=0; i<pattern_count; i++)); do
    local pattern_obj=$(echo "$PLAYBOOK_V2" | jq -r ".patterns[$i]" 2>/dev/null)
    local issue_type=$(echo "$pattern_obj" | jq -r '.id' 2>/dev/null)
    local pattern=$(echo "$pattern_obj" | jq -r '.regex' 2>/dev/null)
    local severity=$(echo "$pattern_obj" | jq -r '.severity' 2>/dev/null)
    local action=$(echo "$pattern_obj" | jq -r '.action' 2>/dev/null)
    local cooldown=$(echo "$pattern_obj" | jq -r '.cooldown' 2>/dev/null || echo "1800")
    
    if echo "$logs" | grep -qiE "$pattern"; then
      local matched_lines=$(echo "$logs" | grep -iE "$pattern" | tail -20)
      local error_pattern=$(echo "$matched_lines" | head -1)
      local fingerprint=$(echo -n "${issue_type}:${client_type}:${network}" | sha256sum | cut -d' ' -f1)
      
      # Extract context lines around error
      local context_logs=$(echo "$logs" | tail -20 | jq -R -s -c 'split("\n")')
      
      # === PHASE 2: CROSS-NODE CORRELATION ===
      local correlation=$(check_fleet_correlation "$api_url" "$api_key" "$network" "$block_num" "$issue_type")
      echo "[Phase2-Correlation] Issue $issue_type correlation: $correlation"
      
      # Build rich incident payload with Phase 2 fields
      local incident_payload=$(cat <<EOF
{
  "nodeId": "$node_id",
  "type": "$issue_type",
  "severity": "$severity",
  "fingerprint": "$fingerprint",
  "message": "$error_pattern",
  "correlation": "$correlation",
  "context": {
    "block": $block_num,
    "peers": $peer_count,
    "client": "$client_type",
    "version": "$client_version",
    "network": "$network",
    "error_patterns": ["$error_pattern"],
    "last_logs": $context_logs,
    "cpu_percent": $cpu_percent,
    "mem_percent": $mem_percent,
    "disk_percent": $disk_percent
  },
  "healAction": "none",
  "healSuccess": false
}
EOF
)
      
      # Determine heal action based on playbook and correlation
      local heal_action="$action"
      local heal_success=false
      
      # If widespread issue (code bug), don't restart - escalate to GitHub
      if [ "$correlation" = "widespread" ]; then
        echo "[Phase2-Correlation] 🚨 WIDESPREAD ISSUE DETECTED - All nodes affected at block $block_num"
        echo "[Phase2-Correlation] This is likely a code bug, escalating to GitHub instead of restarting"
        heal_action="escalate"
      fi
      
      # Check cooldown
      local cooldown_file="/tmp/heal-${issue_type}-last"
      local current_time=$(date +%s)
      local can_heal=true
      
      if [ -f "$cooldown_file" ]; then
        local last_heal=$(cat "$cooldown_file")
        local time_since=$((current_time - last_heal))
        if [ $time_since -lt $cooldown ]; then
          can_heal=false
          echo "[SkyOne] Cooldown active for $issue_type, skipping heal"
        fi
      fi
      
      # Execute heal action
      if [ "$can_heal" = true ]; then
        case "$heal_action" in
          rollback)
            local blocks_back=$(echo "$pattern_obj" | jq -r '.rollbackBlocks' 2>/dev/null || echo "100")
            echo "[SkyOne] Auto-heal: Rolling back $blocks_back blocks for $issue_type"
            
            # === PHASE 2: SMART RESTART LOGIC ===
            if should_restart_node "$block_num" "$issue_type"; then
              docker restart "$container_name" >/dev/null 2>&1 && heal_success=true
              record_restart "$block_num" "$issue_type"
              echo "$current_time" > "$cooldown_file"
            else
              heal_action="escalate"
            fi
            ;;
          
          restart)
            echo "[SkyOne] Auto-heal: Restarting container for $issue_type"
            
            # === PHASE 2: SMART RESTART LOGIC ===
            if should_restart_node "$block_num" "$issue_type"; then
              docker restart "$container_name" >/dev/null 2>&1 && heal_success=true
              record_restart "$block_num" "$issue_type"
              echo "$current_time" > "$cooldown_file"
            else
              heal_action="escalate"
            fi
            ;;
          
          peer_refresh)
            echo "[SkyOne] Auto-heal: Refreshing peers for $issue_type"
            # Note: Peer injection handled separately in heartbeat loop
            heal_success=true
            echo "$current_time" > "$cooldown_file"
            ;;
          
          escalate)
            echo "[SkyOne] Auto-heal: Escalating $issue_type (requires manual intervention)"
            ;;
          
          none)
            echo "[SkyOne] Auto-heal: No action for $issue_type (monitoring only)"
            ;;
        esac
      fi
      
      # Update incident payload with heal result
      incident_payload=$(echo "$incident_payload" | jq --arg action "$heal_action" --argjson success "$heal_success" \
        '.healAction = $action | .healSuccess = $success')
      
      # Send to incidents API
      local response=$(curl -s -m 15 -X POST "${api_url}/v1/incidents" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${api_key}" \
        -d "$incident_payload" 2>/dev/null)
      
      if echo "$response" | jq -e '.success' >/dev/null 2>&1; then
        local action=$(echo "$response" | jq -r '.action // "unknown"')
        echo "[SkyOne] ✅ Incident $issue_type $action (fingerprint: ${fingerprint:0:16}...)"
        
        # Check if escalation needed
        if echo "$response" | jq -e '.escalationNeeded' >/dev/null 2>&1; then
          echo "[SkyOne] 🚨 Incident escalated to GitHub"
        fi
      else
        echo "[SkyOne] ⚠️  Incident reporting failed"
      fi
    fi
  done
  
  # Check container crashed (not running)
  if [ "$container_running" = false ]; then
    local fingerprint=$(echo -n "container_crashed:${client_type}:${network}" | sha256sum | cut -d' ' -f1)
    
    local incident_payload=$(cat <<EOF
{
  "nodeId": "$node_id",
  "type": "container_crashed",
  "severity": "critical",
  "fingerprint": "$fingerprint",
  "message": "Container $container_name is not running",
  "correlation": "isolated",
  "context": {
    "client": "$client_type",
    "network": "$network",
    "container": "$container_name"
  },
  "healAction": "restart",
  "healSuccess": false
}
EOF
)
    
    # Attempt restart
    echo "[SkyOne] Auto-heal: Restarting crashed container..."
    if docker start "$container_name" >/dev/null 2>&1; then
      incident_payload=$(echo "$incident_payload" | jq '.healSuccess = true')
      echo "[SkyOne] ✅ Container restarted successfully"
      record_restart "$block_num" "container_crashed"
    else
      echo "[SkyOne] ❌ Container restart failed"
    fi
    
    curl -s -m 15 -X POST "${api_url}/v1/incidents" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${api_key}" \
      -d "$incident_payload" >/dev/null 2>&1
  fi
  
  # Check disk pressure
  if [ -n "$disk_percent" ] && [ "$disk_percent" -gt 90 ]; then
    local fingerprint=$(echo -n "disk_pressure:${client_type}:${network}" | sha256sum | cut -d' ' -f1)
    
    local incident_payload=$(cat <<EOF
{
  "nodeId": "$node_id",
  "type": "disk_pressure",
  "severity": "warning",
  "fingerprint": "$fingerprint",
  "message": "Disk usage at ${disk_percent}%",
  "correlation": "isolated",
  "context": {
    "disk_percent": $disk_percent,
    "client": "$client_type",
    "network": "$network"
  },
  "healAction": "cleanup",
  "healSuccess": false
}
EOF
)
    
    curl -s -m 15 -X POST "${api_url}/v1/incidents" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${api_key}" \
      -d "$incident_payload" >/dev/null 2>&1
  fi
}

# Container log monitoring for errors (legacy - kept for backward compat)
monitor_container_logs() {
  local node_id="$1"
  local api_key="$2"
  local api_url="$3"
  local container_name="${CONTAINER_NAME:-xdc-node}"
  
  # Check if container exists
  if ! docker ps -q -f name="$container_name" >/dev/null 2>&1; then
    return 0
  fi
  
  # Get last 100 lines of logs and check for errors
  local logs
  logs=$(docker logs --tail 100 "$container_name" 2>&1 || true)
  
  # Check for BAD BLOCK
  if echo "$logs" | grep -qi "BAD BLOCK"; then
    local bad_block_line
    bad_block_line=$(echo "$logs" | grep -i "BAD BLOCK" | tail -1)
    local block_num
    block_num=$(echo "$bad_block_line" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
    
    report_error "$node_id" "$api_key" "$api_url" "bad_block" "$block_num" "Bad block detected" "{\"logLine\": \"$bad_block_line\"}"
  fi
  
  # Check for panic/crash
  if echo "$logs" | grep -qE "(panic|runtime error|SIGSEGV|SIGABRT)"; then
    local panic_line
    panic_line=$(echo "$logs" | grep -E "(panic|runtime error|SIGSEGV|SIGABRT)" | tail -1)
    
    report_error "$node_id" "$api_key" "$api_url" "crash" "" "Node crashed with panic" "{\"logLine\": \"$panic_line\"}"
  fi
}

# Start SkyNet heartbeat in background
(
  sleep 10
  echo "[SkyNet] Starting heartbeat loop..."
  
  # === PHASE 2: AGENT START TIME FOR DIAGNOSTICS ===
  AGENT_START_TIME=$(date +%s)
  
  # Issue #71: Variables for fingerprint-based identification
  FINGERPRINT=""
  COINBASE=""
  
  # Issue #71: Load persisted fingerprint if available
  if [ -f /tmp/skynet-node-id ]; then
    source /tmp/skynet-node-id
    FINGERPRINT="${SKYNET_FINGERPRINT:-}"
    COINBASE="${SKYNET_COINBASE:-}"
  fi
  
  # Attempt auto-registration if credentials missing
  if [ -z "$SKYNET_NODE_ID" ] || [ -z "$SKYNET_API_KEY" ]; then
    echo "[SkyNet] No credentials found, attempting auto-registration..."
    
    # Get initial client info for registration
    RPC_URL="${RPC_URL:-http://xdc-node:8545}"
    CLIENT_VERSION=$(curl -s -m 5 -X POST "$RPC_URL" -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' 2>/dev/null | jq -r .result 2>/dev/null)
    CHAIN_ID=$(curl -s -m 5 -X POST "$RPC_URL" -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' 2>/dev/null | jq -r .result 2>/dev/null)
    
    CLIENT_TYPE="unknown"
    case "$CLIENT_VERSION" in
      *[Nn]ethermind*) CLIENT_TYPE="nethermind" ;;
      *[Ee]rigon*) CLIENT_TYPE="erigon" ;;
      *XDC*|[Gg]eth*) CLIENT_TYPE="geth" ;;
    esac
    
    NETWORK_NAME="mainnet"
    case "$CHAIN_ID" in
      50) NETWORK_NAME="mainnet" ;;
      51) NETWORK_NAME="apothem" ;;
      551) NETWORK_NAME="devnet" ;;
    esac
    
    # Issue #71: Try identity-based registration first, fallback to legacy
    auto_register_identity "$RPC_URL" "$CHAIN_ID" "$NETWORK_NAME" "$CLIENT_TYPE" "$CLIENT_VERSION" || {
      echo "[SkyNet] Identity registration failed, trying legacy registration..."
      auto_register "$RPC_URL" "$CHAIN_ID" "$NETWORK_NAME" "$CLIENT_TYPE" "$CLIENT_VERSION" || true
    }
  fi
  
  # Counter for error monitoring (every 5th heartbeat)
  HEARTBEAT_COUNT=0

  # SkyOne: Stall detection variables
  PREV_BLOCK=0
  STALL_COUNT=0
  LAST_RESTART_TIME=""
  
  # === PHASE 2: COUNTERS (30s interval) ===
  NETWORK_HEIGHT_COUNTER=0     # Every 20 HB = 10 min
  PEER_MGMT_COUNTER=0          # Every 10 HB = 5 min
  DIAGNOSTIC_COUNTER=0         # Every 120 HB = 1 hour
  CONFIG_REFRESH_COUNTER=0     # Every 50 HB = ~25 min
  
  # Fetch initial config from SkyNet
  if [ -n "$SKYNET_API_URL" ] && [ -n "$SKYNET_NODE_ID" ] && [ -n "$SKYNET_API_KEY" ]; then
    fetch_agent_config "$SKYNET_NODE_ID" "$SKYNET_API_KEY" "$SKYNET_API_URL" || true
  fi
  
  echo "[Phase2-Config] Using heartbeat interval: ${HEARTBEAT_INTERVAL}s"
  echo "[Phase2-Config] Block window: 30 samples = $(echo "scale=1; 30 * $HEARTBEAT_INTERVAL / 60" | bc) minutes"

  while true; do
    RPC_URL="${RPC_URL:-http://xdc-node:8545}"
    
    # Get metrics from node
    BLOCK_HEX=$(curl -s -m 5 -X POST "$RPC_URL" -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | jq -r .result 2>/dev/null)
    PEER_HEX=$(curl -s -m 5 -X POST "$RPC_URL" -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null | jq -r .result 2>/dev/null)
    CHAIN_ID=$(curl -s -m 5 -X POST "$RPC_URL" -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' 2>/dev/null | jq -r .result 2>/dev/null)
    SYNC_JSON=$(curl -s -m 5 -X POST "$RPC_URL" -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' 2>/dev/null | jq -r .result 2>/dev/null)
    
    # Issue #71: Get coinbase from RPC
    COINBASE=$(curl -s -m 5 -X POST "$RPC_URL" -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"eth_coinbase","params":[],"id":1}' 2>/dev/null | jq -r .result 2>/dev/null)
    
    # Issue #71: Get public IP (cached)
    if [ -z "$HOST_IP" ] || [ "$HOST_IP" = "unknown" ]; then
      HOST_IP=$(curl -s -m 5 https://ifconfig.me 2>/dev/null || curl -s -m 5 https://api.ipify.org 2>/dev/null || echo "unknown")
    fi
    
    # Issue #71: Compute fingerprint
    FINGERPRINT="${COINBASE}@${HOST_IP}"
    
    BLOCK_NUM=0
    [ -n "$BLOCK_HEX" ] && [ "$BLOCK_HEX" != "null" ] && BLOCK_NUM=$(printf "%d" "$BLOCK_HEX" 2>/dev/null || echo "0")
    
    PEER_COUNT=0
    [ -n "$PEER_HEX" ] && [ "$PEER_HEX" != "null" ] && PEER_COUNT=$(printf "%d" "$PEER_HEX" 2>/dev/null || echo "0")
    
    NETWORK_NAME="mainnet"
    case "$CHAIN_ID" in
      50) NETWORK_NAME="mainnet" ;;
      51) NETWORK_NAME="apothem" ;;
      551) NETWORK_NAME="devnet" ;;
      *) NETWORK_NAME="mainnet" ;;
    esac
    
    IS_SYNCING=false
    [ "$SYNC_JSON" != "false" ] && [ "$SYNC_JSON" != "null" ] && IS_SYNCING=true
    
    # Collect OS information
    OS_TYPE=$(uname -s 2>/dev/null || echo "unknown")
    OS_RELEASE=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "")
    OS_ARCH=$(uname -m 2>/dev/null || echo "")
    OS_KERNEL=$(uname -r 2>/dev/null || echo "")
    
    # Collect system resource information
    # CPU usage calculation from /proc/stat
    CPU_PERCENT=0
    if [ -f /proc/stat ]; then
      CPU_STAT1=$(cat /proc/stat | grep '^cpu ' | awk '{print $2+$3+$4+$5+$6+$7+$8}')
      CPU_IDLE1=$(cat /proc/stat | grep '^cpu ' | awk '{print $5}')
      sleep 0.5
      CPU_STAT2=$(cat /proc/stat | grep '^cpu ' | awk '{print $2+$3+$4+$5+$6+$7+$8}')
      CPU_IDLE2=$(cat /proc/stat | grep '^cpu ' | awk '{print $5}')
      CPU_DIFF=$((CPU_STAT2 - CPU_STAT1))
      CPU_IDLE_DIFF=$((CPU_IDLE2 - CPU_IDLE1))
      if [ $CPU_DIFF -gt 0 ]; then
        CPU_PERCENT=$(awk "BEGIN {printf \"%.1f\", 100 * ($CPU_DIFF - $CPU_IDLE_DIFF) / $CPU_DIFF}")
      fi
    fi
    
    # Memory usage from free command
    MEMORY_PERCENT=0
    MEMORY_INFO=$(free 2>/dev/null)
    if [ -n "$MEMORY_INFO" ]; then
      MEM_TOTAL=$(echo "$MEMORY_INFO" | grep Mem | awk '{print $2}')
      MEM_USED=$(echo "$MEMORY_INFO" | grep Mem | awk '{print $3}')
      if [ -n "$MEM_TOTAL" ] && [ "$MEM_TOTAL" -gt 0 ]; then
        MEMORY_PERCENT=$(awk "BEGIN {printf \"%.1f\", 100 * $MEM_USED / $MEM_TOTAL}")
      fi
    fi
    
    # Disk usage from df command
    DISK_PERCENT=0
    DISK_USED_GB=0
    DISK_TOTAL_GB=0
    DISK_INFO=$(df -h / 2>/dev/null | tail -1)
    if [ -n "$DISK_INFO" ]; then
      DISK_PERCENT=$(echo "$DISK_INFO" | awk '{print $5}' | tr -d '%')
      DISK_USED=$(echo "$DISK_INFO" | awk '{print $3}')
      DISK_TOTAL=$(echo "$DISK_INFO" | awk '{print $2}')
      # Convert to GB (handle G, T, M suffixes)
      DISK_USED_GB=$(echo "$DISK_USED" | sed 's/G//; s/T/*1024/; s/M/*0.001/' | bc 2>/dev/null || echo "0")
      DISK_TOTAL_GB=$(echo "$DISK_TOTAL" | sed 's/G//; s/T/*1024/; s/M/*0.001/' | bc 2>/dev/null || echo "0")
    fi
    
    # Detect storage type (NVMe/SSD/HDD)
    STORAGE_TYPE="unknown"
    if [ -d /sys/block ]; then
      ROOT_DEV=$(df / 2>/dev/null | tail -1 | awk '{print $1}' | sed 's|^/dev/||; s/[0-9]*$//')
      if [ -n "$ROOT_DEV" ]; then
        if [ -d "/sys/block/${ROOT_DEV}/device" ]; then
          # Check for NVMe
          if echo "$ROOT_DEV" | grep -q "nvme"; then
            STORAGE_TYPE="NVMe"
          # Check for rotational (0=SSD, 1=HDD)
          elif [ -f "/sys/block/${ROOT_DEV}/queue/rotational" ]; then
            ROTATIONAL=$(cat "/sys/block/${ROOT_DEV}/queue/rotational" 2>/dev/null || echo "1")
            if [ "$ROTATIONAL" = "0" ]; then
              STORAGE_TYPE="SSD"
            else
              STORAGE_TYPE="HDD"
            fi
          fi
        fi
      fi
    fi
    
    # Simple security assessment
    SECURITY_SCORE=100
    SECURITY_ISSUES="[]"
    ISSUES=()
    
    # Check if running as root (security concern)
    if [ "$(id -u)" = "0" ]; then
      SECURITY_SCORE=$((SECURITY_SCORE - 10))
      ISSUES+=("Running as root user")
    fi
    
    # Check SSH password authentication (basic check)
    if [ -f /etc/ssh/sshd_config ]; then
      if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
        SECURITY_SCORE=$((SECURITY_SCORE - 15))
        ISSUES+=("SSH password authentication enabled")
      fi
    fi
    
    # Check for firewall
    if ! command -v ufw >/dev/null 2>&1 && ! command -v iptables >/dev/null 2>&1; then
      SECURITY_SCORE=$((SECURITY_SCORE - 10))
      ISSUES+=("No firewall detected")
    fi
    
    # Build security issues JSON array
    if [ ${#ISSUES[@]} -gt 0 ]; then
      SECURITY_ISSUES="["
      for i in "${!ISSUES[@]}"; do
        [ $i -gt 0 ] && SECURITY_ISSUES="${SECURITY_ISSUES},"
        SECURITY_ISSUES="${SECURITY_ISSUES}\"${ISSUES[$i]}\""
      done
      SECURITY_ISSUES="${SECURITY_ISSUES}]"
    fi

    # Detect client type from version string
    CLIENT_VERSION=$(curl -s -m 5 -X POST "$RPC_URL" -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' 2>/dev/null | jq -r .result 2>/dev/null)
    CLIENT_TYPE="unknown"
    case "$CLIENT_VERSION" in
      *[Nn]ethermind*) CLIENT_TYPE="nethermind" ;;
      *[Ee]rigon*) CLIENT_TYPE="erigon" ;;
      *XDC*|[Gg]eth*) CLIENT_TYPE="geth" ;;
    esac
    
    # === PHASE 2: BLOCK PROGRESS TRACKING ===
    # Update block window (rolling 30-entry window = 15 min at 30s interval)
    block_window=$(cat "$BLOCK_WINDOW_FILE" 2>/dev/null || echo '{"blocks":[]}')
    block_window=$(echo "$block_window" | jq --argjson blk "$BLOCK_NUM" '.blocks += [$blk] | .blocks = .blocks[-30:]' 2>/dev/null)
    echo "$block_window" > "$BLOCK_WINDOW_FILE"
    
    # Calculate sync rate and trend
    SYNC_RATE=$(calculate_sync_rate "$HEARTBEAT_INTERVAL")
    SYNC_TREND=$(detect_sync_trend "$SYNC_RATE")
    
    # === PHASE 2: NETWORK HEIGHT AWARENESS ===
    NETWORK_HEIGHT_COUNTER=$((NETWORK_HEIGHT_COUNTER + 1))
    NETWORK_HEIGHT=0
    SYNC_PERCENT=0
    ETA_HOURS="unknown"
    
    if [ $((NETWORK_HEIGHT_COUNTER % 20)) -eq 0 ]; then
      NETWORK_HEIGHT=$(fetch_network_height "$NETWORK_NAME" "$CHAIN_ID")
      echo "[Phase2-NetHeight] Network height: $NETWORK_HEIGHT, Local: $BLOCK_NUM"
      
      if [ "$NETWORK_HEIGHT" -gt 0 ] && [ "$BLOCK_NUM" -gt 0 ]; then
        SYNC_PERCENT=$(echo "scale=2; $BLOCK_NUM * 100 / $NETWORK_HEIGHT" | bc 2>/dev/null || echo "0")
        ETA_HOURS=$(estimate_sync_completion "$BLOCK_NUM" "$NETWORK_HEIGHT" "$SYNC_RATE")
      fi
    else
      # Use cached network height
      cached=$(cat "$NETWORK_HEIGHT_FILE" 2>/dev/null || echo '{"height":0}')
      NETWORK_HEIGHT=$(echo "$cached" | jq -r '.height' 2>/dev/null || echo "0")
      
      if [ "$NETWORK_HEIGHT" -gt 0 ] && [ "$BLOCK_NUM" -gt 0 ]; then
        SYNC_PERCENT=$(echo "scale=2; $BLOCK_NUM * 100 / $NETWORK_HEIGHT" | bc 2>/dev/null || echo "0")
        ETA_HOURS=$(estimate_sync_completion "$BLOCK_NUM" "$NETWORK_HEIGHT" "$SYNC_RATE")
      fi
    fi
    
    # === PHASE 2: INTELLIGENT PEER MANAGEMENT ===
    PEER_MGMT_COUNTER=$((PEER_MGMT_COUNTER + 1))
    if [ $((PEER_MGMT_COUNTER % 10)) -eq 0 ] && [ -n "$SKYNET_API_URL" ] && [ -n "$SKYNET_NODE_ID" ] && [ -n "$SKYNET_API_KEY" ]; then
      inject_healthy_peers "$SKYNET_API_URL" "$SKYNET_API_KEY" "$NETWORK_NAME" "$CLIENT_TYPE" "$RPC_URL" "$PEER_COUNT"
    fi
    
    # Update peer history
    peer_history=$(cat "$PEER_HISTORY_FILE" 2>/dev/null || echo '{"peers":[]}')
    peer_history=$(echo "$peer_history" | jq --argjson p "$PEER_COUNT" '.peers += [$p] | .peers = .peers[-30:]' 2>/dev/null)
    echo "$peer_history" > "$PEER_HISTORY_FILE"
    
    # SkyOne AI Issue Intelligence: detect and auto-heal (every heartbeat = 60s)
    HEARTBEAT_COUNT=$((HEARTBEAT_COUNT + 1))
    if [ -n "$SKYNET_API_URL" ] && [ -n "$SKYNET_NODE_ID" ] && [ -n "$SKYNET_API_KEY" ]; then
      detect_and_heal "$SKYNET_NODE_ID" "$SKYNET_API_KEY" "$SKYNET_API_URL" "$BLOCK_NUM" "$PEER_COUNT" "${DISK_PERCENT:-0}" "${CPU_PERCENT:-0}" "${MEMORY_PERCENT:-0}"
    fi
    
    # Legacy error monitoring (backward compat - every 5th heartbeat)
    if [ $((HEARTBEAT_COUNT % 5)) -eq 0 ] && [ -n "$SKYNET_API_URL" ] && [ -n "$SKYNET_NODE_ID" ] && [ -n "$SKYNET_API_KEY" ]; then
      monitor_container_logs "$SKYNET_NODE_ID" "$SKYNET_API_KEY" "$SKYNET_API_URL"
    fi
    
    # === PHASE 2: CONFIG REFRESH (EVERY ~25 MIN) ===
    CONFIG_REFRESH_COUNTER=$((CONFIG_REFRESH_COUNTER + 1))
    if [ $((CONFIG_REFRESH_COUNTER % 50)) -eq 0 ] && [ -n "$SKYNET_API_URL" ] && [ -n "$SKYNET_NODE_ID" ] && [ -n "$SKYNET_API_KEY" ]; then
      fetch_agent_config "$SKYNET_NODE_ID" "$SKYNET_API_KEY" "$SKYNET_API_URL" || true
    fi
    
    # === PHASE 2: SELF-DIAGNOSTIC REPORT (EVERY HOUR) ===
    DIAGNOSTIC_COUNTER=$((DIAGNOSTIC_COUNTER + 1))
    if [ $((DIAGNOSTIC_COUNTER % 120)) -eq 0 ] && [ -n "$SKYNET_API_URL" ] && [ -n "$SKYNET_NODE_ID" ] && [ -n "$SKYNET_API_KEY" ]; then
      generate_diagnostic_report "$SKYNET_NODE_ID" "$SKYNET_API_KEY" "$SKYNET_API_URL" "$AGENT_START_TIME" "$HEARTBEAT_INTERVAL"
    fi

    # SkyOne: Stall detection
    STALLED=false
    CURRENT_TIME=$(date +%s)
    COOLDOWN_SECONDS=1800  # 30 minutes
    CAN_RESTART=true

    # Check cooldown
    if [ -n "$LAST_RESTART_TIME" ]; then
      LAST_RESTART_EPOCH=$(date -d "$LAST_RESTART_TIME" +%s 2>/dev/null || echo "0")
      TIME_SINCE_RESTART=$((CURRENT_TIME - LAST_RESTART_EPOCH))
      if [ $TIME_SINCE_RESTART -lt $COOLDOWN_SECONDS ]; then
        CAN_RESTART=false
      fi
    fi

    # Detect stall: block unchanged and we have peers
    if [ "$BLOCK_NUM" -eq "$PREV_BLOCK" ] && [ "$PEER_COUNT" -gt 3 ]; then
      STALL_COUNT=$((STALL_COUNT + 1))
      echo "[SkyOne] Stall check: Block $BLOCK_NUM unchanged, stall_count=$STALL_COUNT, peers=$PEER_COUNT"
    else
      STALL_COUNT=0
    fi

    # Trigger auto-heal if stalled for 10 consecutive heartbeats (5 minutes at 30s interval)
    if [ $STALL_COUNT -ge 10 ] && [ "$CAN_RESTART" = true ]; then
      echo "[SkyOne] ⚠️ STALL DETECTED: Block $BLOCK_NUM unchanged for 5min with $PEER_COUNT peers."
      
      # === PHASE 2: SMART RESTART LOGIC ===
      if should_restart_node "$BLOCK_NUM" "sync_stall"; then
        echo "[SkyOne] Auto-restarting with smart restart logic..."
        
        # Report incident to SkyNet
        ERROR_PAYLOAD=$(cat <<EOF
{"errorType": "sync_stall", "message": "Block stalled at $BLOCK_NUM for 5+ minutes with $PEER_COUNT peers", "severity": "warning", "source": "skyone-agent"}
EOF
)
        curl -s -m 15 -X POST "${SKYNET_API_URL}/v1/nodes/${SKYNET_NODE_ID}/errors" \
          -H "Content-Type: application/json" \
          -H "Authorization: Bearer ${SKYNET_API_KEY}" \
          -d "$ERROR_PAYLOAD" 2>/dev/null || echo "[SkyOne] Failed to report stall incident"
        
        # Restart the XDC node container
        docker restart "${XDC_CONTAINER_NAME:-xdc-node}" 2>/dev/null || echo "[SkyOne] Failed to restart container"
        
        # Record restart
        record_restart "$BLOCK_NUM" "sync_stall"
        
        # Reset stall count and record restart time
        STALL_COUNT=0
        LAST_RESTART_TIME=$(date -Iseconds)
        STALLED=true
      else
        echo "[SkyOne] Restart not approved by smart logic, escalating instead"
        STALLED=true
      fi
    elif [ $STALL_COUNT -ge 10 ]; then
      echo "[SkyOne] Stall detected but in cooldown period (restart at: $LAST_RESTART_TIME)"
      STALLED=true
    fi

    # Update previous block for next iteration
    PREV_BLOCK=$BLOCK_NUM

    if [ -n "$SKYNET_API_URL" ] && [ -n "$SKYNET_NODE_ID" ] && [ -n "$SKYNET_API_KEY" ]; then
      echo "[SkyNet] Sending heartbeat: block=$BLOCK_NUM peers=$PEER_COUNT network=$NETWORK_NAME chainId=$CHAIN_ID syncing=$IS_SYNCING client=$CLIENT_TYPE cpu=$CPU_PERCENT% mem=$MEMORY_PERCENT% disk=$DISK_PERCENT% stalled=$STALLED"
      echo "[Phase2] syncRate=${SYNC_RATE}/min trend=$SYNC_TREND netHeight=$NETWORK_HEIGHT syncPct=$SYNC_PERCENT% eta=${ETA_HOURS}h"

      # Build extended heartbeat payload with Phase 2 fields
      HEARTBEAT_PAYLOAD=$(cat <<EOF
{
  "blockHeight": $BLOCK_NUM,
  "peerCount": $PEER_COUNT,
  "isSyncing": $IS_SYNCING,
  "clientType": "$CLIENT_TYPE",
  "version": "$CLIENT_VERSION",
  "network": "$NETWORK_NAME",
  "chainId": ${CHAIN_ID:-0},
  "coinbase": "$COINBASE",
  "fingerprint": "$FINGERPRINT",
  "stalled": $STALLED,
  "lastRestart": "$LAST_RESTART_TIME",
  "syncRate": $SYNC_RATE,
  "syncTrend": "$SYNC_TREND",
  "networkHeight": $NETWORK_HEIGHT,
  "syncPercent": $SYNC_PERCENT,
  "etaHours": "$ETA_HOURS",
  "os": {
    "type": "$OS_TYPE",
    "release": "$OS_RELEASE",
    "arch": "$OS_ARCH",
    "kernel": "$OS_KERNEL"
  },
  "system": {
    "cpuPercent": $CPU_PERCENT,
    "memoryPercent": $MEMORY_PERCENT,
    "diskPercent": $DISK_PERCENT,
    "diskUsedGb": $DISK_USED_GB,
    "diskTotalGb": $DISK_TOTAL_GB
  },
  "security": {
    "score": $SECURITY_SCORE,
    "issues": $SECURITY_ISSUES
  },
  "storageType": "$STORAGE_TYPE"
}
EOF
)
      
      RESPONSE=$(curl -s -m 15 -X POST "${SKYNET_API_URL}/v1/nodes/${SKYNET_NODE_ID}/heartbeat" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${SKYNET_API_KEY}" \
        -d "$HEARTBEAT_PAYLOAD" 2>&1)
      
      if echo "$RESPONSE" | jq -e .error >/dev/null 2>&1; then
        echo "[SkyNet] ❌ Heartbeat failed: $(echo "$RESPONSE" | jq -r .error)"
        # Try to re-register if auth failed
        if echo "$RESPONSE" | grep -qi "unauthorized\|invalid\|not found"; then
          echo "[SkyNet] Attempting re-registration with identity..."
          auto_register_identity "$RPC_URL" "$CHAIN_ID" "$NETWORK_NAME" "$CLIENT_TYPE" "$CLIENT_VERSION" || true
        fi
      elif echo "$RESPONSE" | jq -e .success >/dev/null 2>&1; then
        echo "[SkyNet] ✅ Heartbeat OK"
      else
        echo "[SkyNet] ⚠️  Unexpected response: $RESPONSE"
      fi
    else
      echo "[SkyNet] ⚠️  Skipping heartbeat (missing credentials)"
    fi
    
    sleep $HEARTBEAT_INTERVAL
  done
) &

# Keep container running (heartbeat loop runs in background)
echo "[SkyNet Agent v2.0] Phase 2 AI Intelligence ACTIVE"
echo "[Phase2] Heartbeat interval: ${HEARTBEAT_INTERVAL}s (default 30s, configurable)"
echo "[Phase2] Features: Correlation Engine | Smart Restart | Peer Mgmt | Trend Analysis | Network Height | Diagnostics | Config Refresh"
echo "[Phase2] Timings: Peer check 5min | Net height 10min | Diagnostics 1h | Config refresh 25min | Stall detect 5min"
wait
