#!/usr/bin/env bash
# =============================================================================
# peers.sh — XDC Node Peer Management
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/85
#
# Usage:
#   peers.sh inject <client> [network]          Inject static peers
#   peers.sh list   <client> [network]          List connected peers
#   peers.sh count  <client> [network]          Show peer count
#   peers.sh add    <client> <enode> [network]  Add a single peer
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIGS_DIR="$PROJECT_DIR/configs"

# Load port definitions
if [[ -f "$CONFIGS_DIR/ports.env" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIGS_DIR/ports.env"
fi

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
die()   { error "$*"; exit 1; }

# ── helpers ───────────────────────────────────────────────────────────────────
normalise_client() {
  local c="${1,,}"
  case "$c" in
    gp5|go-xdc|geth)     echo "gp5"         ;;
    erigon|erigon-xdc)   echo "erigon"      ;;
    reth|rust-xdc)       echo "reth"        ;;
    nethermind|nm)       echo "nethermind"  ;;
    *)                   echo "$c"          ;;
  esac
}

normalise_network() {
  local n="${1,,}"
  case "$n" in
    mainnet|main)          echo "mainnet" ;;
    testnet|apothem)       echo "apothem" ;;
    devnet|dev)            echo "devnet"  ;;
    *)                     echo "$n"      ;;
  esac
}

# Return the RPC port for a client+network
rpc_port_for() {
  local client="$1" network="$2"
  local NET="${network^^}"   # MAINNET / APOTHEM
  local CLI

  case "$client" in
    gp5)         CLI="GP5"         ;;
    erigon)      CLI="ERIGON"      ;;
    reth)        CLI="RETH"        ;;
    nethermind)  CLI="NM"          ;;
    *)           CLI="${client^^}" ;;
  esac

  local var="${CLI}_${NET}_RPC"
  echo "${!var:-8545}"
}

# Erigon uses host networking — RPC is always on localhost
# Reth uses Erigon for peer information (it relies on Erigon's peer pool)
rpc_url_for() {
  local client="$1" network="$2"
  local port
  port="$(rpc_port_for "$client" "$network")"

  case "$client" in
    erigon)
      # Erigon runs with --network.host, so always on 127.0.0.1
      echo "http://127.0.0.1:${port}"
      ;;
    reth)
      # Reth for XDC needs Erigon for peer management (not GP5)
      warn "Reth peer management should go through Erigon's admin RPC, not GP5."
      local erigon_port
      erigon_port="$(rpc_port_for "erigon" "$network")"
      echo "http://127.0.0.1:${erigon_port}"
      ;;
    *)
      echo "http://127.0.0.1:${port}"
      ;;
  esac
}

# JSON-RPC helper
rpc_call() {
  local url="$1" method="$2" params="${3:-[]}"
  curl -sf --max-time 10 \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":${params},\"id\":1}" \
    "$url"
}

# Find the static-nodes.json for a client+network
static_nodes_file() {
  local client="$1" network="$2"

  # Check client-specific location first
  local f="$CONFIGS_DIR/${network}/${client}/static-nodes.json"
  [[ -f "$f" ]] && echo "$f" && return

  # Fallback: bootnodes JSON in configs
  f="$CONFIGS_DIR/bootnodes-${network}.json"
  [[ -f "$f" ]] && echo "$f" && return

  # Generic
  f="$CONFIGS_DIR/static-nodes.json"
  [[ -f "$f" ]] && echo "$f" && return

  echo ""
}

# =============================================================================
# CMD: inject — add all static peers via admin_addPeer
# =============================================================================
cmd_inject() {
  local client="${1:-}" network="${2:-mainnet}"
  [[ -z "$client" ]] && die "Usage: peers.sh inject <client> [network]"
  client="$(normalise_client "$client")"
  network="$(normalise_network "$network")"

  local rpc_url
  rpc_url="$(rpc_url_for "$client" "$network")"

  # Reth: inject into Erigon's admin (shared peer pool)
  if [[ "$client" == "reth" ]]; then
    warn "Reth shares Erigon's peer pool. Injecting into Erigon admin RPC."
    client="erigon"
    rpc_url="$(rpc_url_for "$client" "$network")"
  fi

  local nodes_file
  nodes_file="$(static_nodes_file "$client" "$network")"

  if [[ -z "$nodes_file" ]]; then
    die "No static-nodes.json found. Checked: $CONFIGS_DIR/$network/$client/ and $CONFIGS_DIR/"
  fi

  info "Loading peers from: $nodes_file"
  info "RPC endpoint: $rpc_url"
  echo ""

  # Parse enodes — support both array of strings and array of {enode, ...} objects
  local enodes
  if command -v jq &>/dev/null; then
    # Try plain array of strings first
    enodes="$(jq -r '.[] | if type == "string" then . else .enode // .url // empty end' "$nodes_file" 2>/dev/null || true)"
    if [[ -z "$enodes" ]]; then
      # Maybe it's wrapped in a key
      enodes="$(jq -r '.nodes[]? | if type == "string" then . else .enode // .url // empty end' "$nodes_file" 2>/dev/null || true)"
    fi
  else
    # Fallback: grep for enode:// strings
    enodes="$(grep -oP 'enode://[^"]+' "$nodes_file" || true)"
  fi

  if [[ -z "$enodes" ]]; then
    die "No enode entries found in $nodes_file"
  fi

  local added=0 failed=0
  while IFS= read -r enode; do
    [[ -z "$enode" || "$enode" == null ]] && continue
    local result
    result="$(rpc_call "$rpc_url" "admin_addPeer" "[\"$enode\"]" 2>/dev/null || echo '{"error":"rpc_failed"}')"
    if echo "$result" | grep -q '"result":true'; then
      ok "Added: ${enode:0:60}…"
      ((added++))
    else
      local err
      err="$(echo "$result" | grep -oP '"message":"\K[^"]+' || echo "unknown")"
      warn "Failed: ${enode:0:60}… ($err)"
      ((failed++))
    fi
  done <<< "$enodes"

  echo ""
  info "Injected ${added} peer(s). Failed: ${failed}."
}

# =============================================================================
# CMD: list — show connected peers
# =============================================================================
cmd_list() {
  local client="${1:-}" network="${2:-mainnet}"
  [[ -z "$client" ]] && die "Usage: peers.sh list <client> [network]"
  client="$(normalise_client "$client")"
  network="$(normalise_network "$network")"

  local rpc_url
  rpc_url="$(rpc_url_for "$client" "$network")"

  # Reth: query via Erigon
  if [[ "$client" == "reth" ]]; then
    warn "Reth: querying Erigon admin RPC for peer list."
    rpc_url="$(rpc_url_for "erigon" "$network")"
  fi

  info "Peers for ${BOLD}$client${NC} ($network) via $rpc_url"
  echo ""

  local result
  result="$(rpc_call "$rpc_url" "admin_peers" "[]" 2>/dev/null)" || \
    die "RPC call failed. Is the node running and accessible at $rpc_url?"

  if command -v jq &>/dev/null; then
    echo "$result" | jq -r '.result[]? | "  \(.id[0:16])… \(.name // "unknown") [\(.network.remoteAddress // "?")]"' 2>/dev/null || \
      echo "$result" | jq '.result'
  else
    echo "$result"
  fi
}

# =============================================================================
# CMD: count — just the peer count
# =============================================================================
cmd_count() {
  local client="${1:-}" network="${2:-mainnet}"
  [[ -z "$client" ]] && die "Usage: peers.sh count <client> [network]"
  client="$(normalise_client "$client")"
  network="$(normalise_network "$network")"

  local rpc_url
  rpc_url="$(rpc_url_for "$client" "$network")"

  if [[ "$client" == "reth" ]]; then
    rpc_url="$(rpc_url_for "erigon" "$network")"
  fi

  local result count
  result="$(rpc_call "$rpc_url" "admin_peers" "[]" 2>/dev/null)" || \
    die "RPC call failed at $rpc_url"

  if command -v jq &>/dev/null; then
    count="$(echo "$result" | jq -r '.result | length')"
  else
    count="$(echo "$result" | grep -o '"id"' | wc -l)"
  fi

  echo "$count"
}

# =============================================================================
# CMD: add — add a single peer by enode URL
# =============================================================================
cmd_add() {
  local client="${1:-}" enode="${2:-}" network="${3:-mainnet}"
  [[ -z "$client" || -z "$enode" ]] && die "Usage: peers.sh add <client> <enode> [network]"
  client="$(normalise_client "$client")"
  network="$(normalise_network "$network")"

  # Validate enode format
  if ! echo "$enode" | grep -qP '^enode://[a-fA-F0-9]{128}@'; then
    die "Invalid enode URL format. Expected: enode://<pubkey>@<ip>:<port>"
  fi

  local rpc_url
  rpc_url="$(rpc_url_for "$client" "$network")"

  if [[ "$client" == "reth" ]]; then
    warn "Reth: adding peer via Erigon admin RPC."
    rpc_url="$(rpc_url_for "erigon" "$network")"
  fi

  info "Adding peer: ${enode:0:70}…"
  info "RPC: $rpc_url"

  local result
  result="$(rpc_call "$rpc_url" "admin_addPeer" "[\"$enode\"]")" || \
    die "RPC call failed at $rpc_url"

  if echo "$result" | grep -q '"result":true'; then
    ok "Peer added successfully."
  else
    local err
    err="$(echo "$result" | grep -oP '"message":"\K[^"]+' || echo "check node logs")"
    die "Failed to add peer: $err"
  fi
}

# =============================================================================
# Entry point
# =============================================================================
usage() {
  cat <<EOF
${BOLD}peers.sh${NC} — XDC Node Peer Management

Usage:
  peers.sh inject <client> [network]           Inject static peers from configs/static-nodes.json
  peers.sh list   <client> [network]           List connected peers via admin_peers RPC
  peers.sh count  <client> [network]           Show connected peer count
  peers.sh add    <client> <enode> [network]   Add a single peer by enode URL

Clients:  gp5 | erigon | reth | nethermind
Networks: mainnet (default) | apothem | devnet

Notes:
  - Ports are sourced from configs/ports.env
  - Erigon runs on host network (always 127.0.0.1)
  - Reth peers are managed via Erigon's admin RPC (not GP5)
EOF
}

case "${1:-help}" in
  inject) shift; cmd_inject "$@" ;;
  list)   shift; cmd_list   "$@" ;;
  count)  shift; cmd_count  "$@" ;;
  add)    shift; cmd_add    "$@" ;;
  help|--help|-h) usage ;;
  *) error "Unknown command: $1"; usage; exit 1 ;;
esac
