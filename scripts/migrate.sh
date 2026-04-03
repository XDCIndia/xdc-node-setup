#!/bin/bash
set -euo pipefail
# xdc migrate — state scheme detection and migration
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/105
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CLIENT="${1:-}"; NETWORK="${2:-mainnet}"; ACTION="${3:-detect}"

detect_scheme() {
  local dir="$ROOT_DIR/data/$NETWORK/$CLIENT"
  [ ! -d "$dir" ] && echo "none" && return
  [ -f "$dir/.state-scheme" ] && cat "$dir/.state-scheme" && return
  [ -d "$dir/triedb" ] && echo "pbss" && return
  [ -d "$dir/ancient" ] || [ -d "$dir/chaindata/ancient" ] && echo "hbss" && return
  echo "unknown"
}

case "${ACTION}" in
  detect)
    if [ -n "$CLIENT" ]; then
      scheme=$(detect_scheme)
      echo "$CLIENT ($NETWORK): $scheme"
    else
      echo "State Scheme Detection:"
      for c in gp5 erigon nethermind reth v268; do
        CLIENT="$c"; scheme=$(detect_scheme)
        printf "  %-12s: %s\n" "$c" "$scheme"
      done
    fi ;;
  mark)
    [ -z "$CLIENT" ] && echo "Usage: $0 <client> <network> mark <pbss|hbss>" && exit 1
    SCHEME="${4:-pbss}"
    echo "$SCHEME" > "$ROOT_DIR/data/$NETWORK/$CLIENT/.state-scheme"
    echo "Marked $CLIENT ($NETWORK) as $SCHEME" ;;
  check)
    [ -z "$CLIENT" ] && echo "Usage: $0 <client> <network> check" && exit 1
    scheme=$(detect_scheme)
    echo "Current scheme: $scheme"
    case "$CLIENT" in
      gp5) echo "GP5 default: PBSS. Cannot mix with HBSS data." ;;
      erigon) echo "Erigon: Uses MDBX (no PBSS/HBSS distinction)." ;;
      nethermind) echo "NM: Uses flat DB (no PBSS/HBSS distinction)." ;;
      reth) echo "Reth: Uses MDBX (no PBSS/HBSS distinction)." ;;
      v268) echo "v268: HBSS only (legacy)." ;;
    esac ;;
  *) echo "Usage: $0 [client] [network] {detect|mark|check}"; echo "  $0                    # detect all"; echo "  $0 gp5 mainnet detect # detect one"; echo "  $0 gp5 mainnet mark pbss" ;;
esac
