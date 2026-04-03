#!/bin/bash
set -euo pipefail
# Smart Peer Management — query SkyNet for healthy peers, inject best ones
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/103
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../configs/ports.env" 2>/dev/null || true
SKYNET_API="${SKYNET_API:-https://skynet.xdcindia.com/api}"
ACTION="${1:-status}"

rpc_call() { curl -s -m 3 -X POST -H "Content-Type: application/json" -d "$2" "http://localhost:$1" 2>/dev/null; }

get_healthy_peers() {
  curl -s -m 10 "$SKYNET_API/v1/peers/healthy?format=enode&limit=20" 2>/dev/null || echo ""
}

inject_peers() {
  local client="$1" port="$2"
  echo "Injecting peers for $client (port $port)..."
  local peers=$(get_healthy_peers)
  local count=0
  echo "$peers" | while IFS= read -r enode; do
    [ -z "$enode" ] && continue
    result=$(rpc_call "$port" "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addPeer\",\"params\":[\"$enode\"],\"id\":1}" | jq -r '.result // "false"')
    [ "$result" = "true" ] && ((count++)) || true
  done
  echo "  Injected peers for $client"
}

case "$ACTION" in
  status)
    echo "📡 Peer Status:"
    for port in 8545 8547 8548 8558; do
      case $port in 8545) name="GP5" ;; 8547) name="Erigon" ;; 8548) name="Reth" ;; 8558) name="NM" ;; esac
      peers=$(rpc_call "$port" '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' | jq -r '.result // "0x0"')
      printf "  %-10s: %d peers\n" "$name" "$((16#${peers#0x}))" 2>/dev/null
    done ;;
  inject)
    for port in 8545 8547 8548 8558; do
      case $port in 8545) name="GP5" ;; 8547) name="Erigon" ;; 8548) name="Reth" ;; 8558) name="NM" ;; esac
      inject_peers "$name" "$port"
    done ;;
  *) echo "Usage: $0 {status|inject}" ;;
esac
