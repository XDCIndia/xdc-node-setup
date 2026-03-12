#!/bin/bash

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }
# XDC SkyNet Heartbeat — macOS Installer
# XDC SkyNet Heartbeat — macOS Installer
# Run: bash <(curl -s https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/scripts/macos-heartbeat.sh)

NODE_ID="755f82db-a541-4224-9447-a385d11321b8"
API_URL="https://net.xdc.network/api/v1/nodes"
API_KEY="xdc-netown-key-2026-prod"
RPC_URL="${XDC_RPC_URL:-http://127.0.0.1:8545}"

SCRIPT_DIR="$HOME/.xdc-node"
mkdir -p "$SCRIPT_DIR"

cat > "$SCRIPT_DIR/heartbeat.sh" << 'HEARTBEAT'
#!/bin/bash
NODE_ID="755f82db-a541-4224-9447-a385d11321b8"
API_URL="https://net.xdc.network/api/v1/nodes"
API_KEY="xdc-netown-key-2026-prod"
RPC_URL="${XDC_RPC_URL:-http://127.0.0.1:8545}"
MAINNET_HEAD_RPC="https://rpc.xdc.org"

# Block height
BLOCK_HEX=$(curl -s -m 5 -X POST "$RPC_URL" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('result','0x0'))" 2>/dev/null)
BLOCK_HEX=${BLOCK_HEX:-0x0}
BLOCK=$((16#${BLOCK_HEX#0x}))

# Peers
PEERS_HEX=$(curl -s -m 5 -X POST "$RPC_URL" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('result','0x0'))" 2>/dev/null)
PEERS_HEX=${PEERS_HEX:-0x0}
PEERS=$((16#${PEERS_HEX#0x}))

# Mainnet head for sync %
HEAD_HEX=$(curl -s -m 5 -X POST "$MAINNET_HEAD_RPC" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('result','0x0'))" 2>/dev/null)
HEAD_HEX=${HEAD_HEX:-0x0}
HEAD=$((16#${HEAD_HEX#0x}))
if [ "$HEAD" -gt 0 ] && [ "$BLOCK" -gt 0 ]; then
  SYNC_PCT=$(python3 -c "print(f'{($BLOCK / $HEAD) * 100:.2f}')")
  IS_SYNCING=$([ "$BLOCK" -lt "$((HEAD - 100))" ] && echo "true" || echo "false")
else
  SYNC_PCT=0
  IS_SYNCING="true"
fi

# System stats (macOS compatible)
CPU=$(ps -A -o %cpu | awk '{s+=$1} END {printf "%.1f", s/4}')
MEM=$(python3 -c "import subprocess,re; vm=subprocess.check_output(['vm_stat']).decode(); pages={k.strip():int(v) for k,v in re.findall(r'\"(.+?)\":\s+(\d+)',vm)}; used=(pages.get('Pages active',0)+pages.get('Pages wired down',0))*4096; total=int(subprocess.check_output(['sysctl','-n','hw.memsize']).strip()); print(f'{used/total*100:.1f}')" 2>/dev/null || echo "0")
DISK_PCT=$(df / | awk 'NR==2{print $5}' | tr -d '%')
DISK_USED=$(df -g / | awk 'NR==2{print $3}')
DISK_TOTAL=$(df -g / | awk 'NR==2{print $2}')

# OS info
OS_TYPE=$(uname -s)
OS_RELEASE=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
OS_ARCH=$(uname -m)
OS_KERNEL=$(uname -r)

# Storage (Docker volume)
CONTAINER=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i xdc | head -1)
if [ -n "$CONTAINER" ]; then
  CHAINDATA_GB=$(docker exec "$CONTAINER" du -sm /work/xdcchain 2>/dev/null | awk '{printf "%.1f", $1/1024}')
  DATABASE_GB=$(docker exec "$CONTAINER" du -sm /work 2>/dev/null | awk '{printf "%.1f", $1/1024}')
  CLIENT_VERSION=$(curl -s -m 3 -X POST "$RPC_URL" -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' | python3 -c "import sys,json; print(json.load(sys.stdin).get('result','XDC/unknown'))" 2>/dev/null)
else
  CHAINDATA_GB=0
  DATABASE_GB=0
  CLIENT_VERSION="XDC/unknown"
fi
CHAINDATA_GB=${CHAINDATA_GB:-0}
DATABASE_GB=${DATABASE_GB:-0}

# Peer list
PEERS_JSON=$(curl -s -m 5 -X POST "$RPC_URL" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"admin_peers","params":[],"id":1}' | \
  python3 -c "
import sys,json
try:
  data = json.load(sys.stdin)
  peers = data.get('result',[])
  out = []
  for p in peers:
    eid = p.get('id','')
    addr = p.get('network',{}).get('remoteAddress','')
    enode = f'enode://{eid}@{addr}' if eid and addr else p.get('enode','')
    out.append({'enode':enode,'name':p.get('name','')})
  print(json.dumps(out))
except: print('[]')
" 2>/dev/null || echo "[]")

# Build payload
PAYLOAD=$(python3 -c "
import json
print(json.dumps({
  'nodeId': '$NODE_ID',
  'blockHeight': $BLOCK,
  'syncing': $IS_SYNCING,
  'syncProgress': $SYNC_PCT,
  'peerCount': $PEERS,
  'clientType': 'geth',
  'clientVersion': '$CLIENT_VERSION',
  'nodeType': 'fullnode',
  'syncMode': 'full',
  'ipv4': '$(curl -s -m 3 https://api.ipify.org)',
  'os': {'type': '$OS_TYPE', 'release': 'macOS $OS_RELEASE', 'arch': '$OS_ARCH', 'kernel': '$OS_KERNEL'},
  'system': {'cpuPercent': $CPU, 'memoryPercent': $MEM, 'diskPercent': $DISK_PCT, 'diskUsedGb': $DISK_USED, 'diskTotalGb': $DISK_TOTAL},
  'rpcLatencyMs': 5,
  'chainDataSize': $CHAINDATA_GB,
  'databaseSize': $DATABASE_GB,
  'peers': $PEERS_JSON
}))
")

RESPONSE=$(curl -s -m 10 -X POST "$API_URL/heartbeat" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d "$PAYLOAD")

if echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('success') or d.get('ok') else 1)" 2>/dev/null; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ block=$BLOCK/$HEAD (${SYNC_PCT}%) peers=$PEERS storage=${CHAINDATA_GB}GB"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $(echo $RESPONSE | python3 -c 'import sys,json; print(json.load(sys.stdin).get("error","Unknown"))' 2>/dev/null)"
fi
HEARTBEAT

chmod +x "$SCRIPT_DIR/heartbeat.sh"

# Install launchd plist (macOS cron equivalent)
PLIST="$HOME/Library/LaunchAgents/com.xdc.skynet.heartbeat.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.xdc.skynet.heartbeat</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_DIR/heartbeat.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>60</integer>
    <key>StandardOutPath</key>
    <string>$SCRIPT_DIR/heartbeat.log</string>
    <key>StandardErrorPath</key>
    <string>$SCRIPT_DIR/heartbeat-error.log</string>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

# Load the agent
launchctl unload "$PLIST" 2>/dev/null
launchctl load "$PLIST"

echo ""
echo "✅ XDC SkyNet Heartbeat installed!"
echo "   Script: $SCRIPT_DIR/heartbeat.sh"
echo "   Log:    $SCRIPT_DIR/heartbeat.log"
echo "   Node:   xdc-macos-mumbai"
echo ""
echo "Test manually: bash $SCRIPT_DIR/heartbeat.sh"
echo "Stop:  launchctl unload $PLIST"
echo "Start: launchctl load $PLIST"
