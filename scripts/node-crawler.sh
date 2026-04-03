#!/usr/bin/env bash
# node-crawler.sh — Network Crawler (#111)
# Discover XDC nodes via admin_peers recursive crawl.
# Outputs unique enodes list and registers with SkyNet.
set -euo pipefail

SKYONE_URL="${SKYONE_URL:-http://localhost:7070}"
SEED_RPCS="${SEED_RPCS:-http://localhost:7070 http://localhost:7071 http://localhost:7072}"
MAX_DEPTH="${MAX_DEPTH:-3}"
MAX_PEERS="${MAX_PEERS:-500}"
OUTPUT_FILE="${OUTPUT_FILE:-/tmp/xdc-nodes-$(date +%Y%m%d).txt}"
TIMEOUT="${RPC_TIMEOUT:-5}"

declare -A VISITED_ENODES
declare -a DISCOVERED_ENODES

log() { echo "[$(date +%H:%M:%S)] $*" >&2; }

rpc_call() {
  local rpc_url="$1"
  local method="$2"
  curl -sf --max-time "$TIMEOUT" -X POST "$rpc_url" \
    -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":[],\"id\":1}" \
    2>/dev/null || echo '{}'
}

get_peers() {
  local rpc_url="$1"
  rpc_call "$rpc_url" "admin_peers" \
    | grep -o '"enode://[^"]*"' | tr -d '"' || true
}

get_node_info() {
  local rpc_url="$1"
  rpc_call "$rpc_url" "admin_nodeInfo" \
    | grep -o '"enode":"[^"]*"' | cut -d'"' -f4 || true
}

normalize_enode() {
  local enode="$1"
  # Strip query params and normalize
  echo "${enode%%\?*}" | tr -d ' '
}

enode_to_rpc_url() {
  local enode="$1"
  # Extract IP from enode://pubkey@ip:port
  local host_port="${enode##*@}"
  local ip="${host_port%%:*}"
  local p2p_port="${host_port##*:}"
  p2p_port="${p2p_port%%\?*}"

  # Guess RPC port: p2p port - 30303 + 8545 (standard offset)
  local rpc_port=$(( p2p_port - 30303 + 8545 ))
  [[ $rpc_port -lt 1024 || $rpc_port -gt 65535 ]] && rpc_port=8545
  echo "http://${ip}:${rpc_port}"
}

crawl() {
  local rpc_url="$1"
  local depth="$2"

  [[ $depth -le 0 ]] && return
  [[ ${#DISCOVERED_ENODES[@]} -ge $MAX_PEERS ]] && return

  log "  Crawling ${rpc_url} (depth=${depth})..."

  local peers
  peers="$(get_peers "$rpc_url")"

  local count=0
  while IFS= read -r raw_enode; do
    [[ -z "$raw_enode" ]] && continue
    local enode
    enode="$(normalize_enode "$raw_enode")"

    # Skip if already visited
    [[ -n "${VISITED_ENODES[$enode]:-}" ]] && continue
    VISITED_ENODES["$enode"]=1
    DISCOVERED_ENODES+=("$enode")
    ((count++))

    log "  Found: ${enode:0:60}..."
    [[ ${#DISCOVERED_ENODES[@]} -ge $MAX_PEERS ]] && break

    # Recursively crawl if depth allows
    if [[ $depth -gt 1 ]]; then
      local peer_rpc
      peer_rpc="$(enode_to_rpc_url "$enode")"
      crawl "$peer_rpc" $(( depth - 1 )) 2>/dev/null || true
    fi
  done <<< "$peers"

  log "  Discovered ${count} new peers from ${rpc_url}"
}

register_with_skyone() {
  local enodes_json="$1"
  local count="$2"
  log "Registering ${count} discoveries with SkyNet..."

  curl -sf -X POST "${SKYONE_URL}/api/v2/crawler/report" \
    -H 'Content-Type: application/json' \
    -d "{\"source\":\"node-crawler\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"count\":${count},\"enodes\":${enodes_json}}" \
    2>/dev/null && log "✅ Registered with SkyNet" || log "⚠️  SkyNet registration failed (non-fatal)"
}

main() {
  log "=== XDC Network Crawler ==="
  log "Max depth: ${MAX_DEPTH}, Max peers: ${MAX_PEERS}"
  log ""

  # Seed from local clients
  for rpc in $SEED_RPCS; do
    log "Seeding from: ${rpc}"
    local self_enode
    self_enode="$(get_node_info "$rpc" 2>/dev/null || true)"
    if [[ -n "$self_enode" ]]; then
      local norm
      norm="$(normalize_enode "$self_enode")"
      VISITED_ENODES["$norm"]=1
      log "  Self: ${norm:0:60}..."
    fi
    crawl "$rpc" "$MAX_DEPTH"
  done

  local total="${#DISCOVERED_ENODES[@]}"
  log ""
  log "=== Crawl Complete: ${total} unique nodes discovered ==="

  # Write output
  printf '%s\n' "${DISCOVERED_ENODES[@]}" | sort -u > "$OUTPUT_FILE"
  log "Saved to: ${OUTPUT_FILE}"

  # Print summary
  echo ""
  echo "Discovered ${total} XDC nodes:"
  printf '%s\n' "${DISCOVERED_ENODES[@]}" | head -20
  [[ $total -gt 20 ]] && echo "... and $(( total - 20 )) more. See ${OUTPUT_FILE}"

  # Build JSON array for SkyNet
  local enodes_json="["
  local first=true
  for e in "${DISCOVERED_ENODES[@]}"; do
    [[ "$first" == "true" ]] && first=false || enodes_json+=","
    enodes_json+="\"${e}\""
  done
  enodes_json+="]"

  register_with_skyone "$enodes_json" "$total"
}

main "$@"
