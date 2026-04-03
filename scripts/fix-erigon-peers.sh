#!/usr/bin/env bash
# fix-erigon-peers.sh — SkyOne peer connector Erigon fix (#115)
# Erigon's admin_addPeer needs enode format without ?discport=0 query params.
# Strips query params from enode URLs before injection.
set -euo pipefail

ERIGON_RPC="${ERIGON_RPC:-http://localhost:8545}"
SKYONE_URL="${SKYONE_URL:-http://localhost:7071}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [enode...]

Options:
  --rpc URL    Erigon JSON-RPC URL (default: ${ERIGON_RPC})
  --from-sky   Fetch peer list from SkyNet and inject all
  --dry-run    Show what would be injected without actually doing it
  <enode>      One or more enode URLs to add (positional args)

Examples:
  $(basename "$0") enode://abc123@1.2.3.4:30303?discport=0
  $(basename "$0") --from-sky
  $(basename "$0") --dry-run enode://abc123@1.2.3.4:30303?discport=0
EOF
  exit 1
}

log() { echo "[$(date +%H:%M:%S)] $*"; }

strip_query_params() {
  local enode="$1"
  # Remove everything after ? in the enode URL
  # enode://pubkey@host:port?discport=0 → enode://pubkey@host:port
  echo "${enode%%\?*}"
}

validate_enode() {
  local enode="$1"
  if [[ ! "$enode" =~ ^enode://[0-9a-fA-F]{128}@[^:]+:[0-9]+$ ]]; then
    log "WARN: Non-standard enode format: ${enode}"
    return 1
  fi
  return 0
}

rpc_call() {
  local method="$1"
  local params="$2"
  curl -sf --max-time 10 -X POST "$ERIGON_RPC" \
    -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"${method}\",\"params\":[${params}],\"id\":1}" \
    2>/dev/null
}

add_peer() {
  local raw_enode="$1"
  local dry_run="${2:-false}"

  local clean_enode
  clean_enode="$(strip_query_params "$raw_enode")"

  if [[ "$raw_enode" != "$clean_enode" ]]; then
    log "  Stripped query params: ${raw_enode}"
    log "  Clean enode:           ${clean_enode}"
  fi

  if [[ "$dry_run" == "true" ]]; then
    log "  [DRY RUN] Would add: ${clean_enode}"
    return 0
  fi

  local response
  response="$(rpc_call "admin_addPeer" "\"${clean_enode}\"")"

  local result
  result="$(echo "$response" | grep -o '"result":[^,}]*' | cut -d: -f2 | tr -d ' ')"
  local error
  error="$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)"

  if [[ "$result" == "true" ]]; then
    log "  ✅ Added: ${clean_enode}"
  elif [[ -n "$error" ]]; then
    log "  ❌ Error: ${error} — ${clean_enode}"
  else
    log "  ⚠️  Unknown response: ${response}"
  fi
}

fetch_peers_from_skyone() {
  log "Fetching peers from SkyNet: ${SKYONE_URL}"
  curl -sf --max-time 10 "${SKYONE_URL}/api/v2/peers/enodes" 2>/dev/null \
    | grep -o '"enode://[^"]*"' | tr -d '"' || true
}

main() {
  local dry_run=false
  local from_sky=false
  local enodes=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --rpc)      ERIGON_RPC="$2"; shift ;;
      --from-sky) from_sky=true ;;
      --dry-run)  dry_run=true ;;
      --help|-h)  usage ;;
      enode://*)  enodes+=("$1") ;;
      *)          log "Unknown argument: $1"; usage ;;
    esac
    shift
  done

  log "=== Erigon Peer Injector (query-param fix) ==="
  log "  Erigon RPC: ${ERIGON_RPC}"
  [[ "$dry_run" == "true" ]] && log "  Mode: DRY RUN"

  # Fetch from SkyNet if requested
  if [[ "$from_sky" == "true" ]]; then
    while IFS= read -r enode; do
      [[ -n "$enode" ]] && enodes+=("$enode")
    done < <(fetch_peers_from_skyone)
    log "  Fetched ${#enodes[@]} peers from SkyNet"
  fi

  # Also check admin_peers on Erigon itself for any corrupted entries
  log "  Checking existing peers for query-param issues..."
  local existing_peers
  existing_peers="$(rpc_call "admin_peers" "" 2>/dev/null | grep -o '"enode://[^"]*"' | tr -d '"' || true)"
  while IFS= read -r enode; do
    if [[ "$enode" == *"?"* ]]; then
      log "  Found corrupted peer (has query params): ${enode}"
      enodes+=("$enode")
    fi
  done <<< "$existing_peers"

  if [[ ${#enodes[@]} -eq 0 ]]; then
    log "No enodes to process. Use --from-sky or pass enode URLs as arguments."
    exit 0
  fi

  log "Processing ${#enodes[@]} enodes..."
  for enode in "${enodes[@]}"; do
    add_peer "$enode" "$dry_run"
  done

  log "Done."
}

main "$@"
