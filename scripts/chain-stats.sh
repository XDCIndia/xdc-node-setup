#!/usr/bin/env bash
# chain-stats.sh — Chain Data Breakdown (#113)
# Show per-client disk breakdown: headers, bodies, receipts, state, freezer/ancient.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="${DATA_DIR:-${REPO_ROOT}/data}"
NETWORK="${NETWORK:-mainnet}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [client|all] [network]

  client   geth | erigon | nethermind | reth | all (default: all)
  network  mainnet | testnet | apothem (default: mainnet)

Examples:
  $(basename "$0")
  $(basename "$0") geth mainnet
  $(basename "$0") all testnet
EOF
  exit 0
}

human_size() {
  local bytes="$1"
  awk -v b="$bytes" 'BEGIN {
    if (b >= 1099511627776) printf "%.2f TB", b/1099511627776
    else if (b >= 1073741824) printf "%.2f GB", b/1073741824
    else if (b >= 1048576) printf "%.2f MB", b/1048576
    else if (b >= 1024) printf "%.2f KB", b/1024
    else printf "%d B", b
  }'
}

dir_size_bytes() {
  local path="$1"
  [[ -d "$path" ]] || { echo 0; return; }
  du -sb "$path" 2>/dev/null | awk '{print $1}' || echo 0
}

print_row() {
  local label="$1"
  local path="$2"
  local bytes
  bytes="$(dir_size_bytes "$path")"
  local human
  human="$(human_size "$bytes")"
  printf "  %-25s %12s  %s\n" "$label" "$human" "${path/#$REPO_ROOT\//}"
}

stats_geth() {
  local base="${DATA_DIR}/${NETWORK}/geth"
  echo "┌─── Geth (XDC) ──────────────────────────────────────────┐"
  print_row "Headers"       "${base}/chaindata/ancient/headers"
  print_row "Bodies"        "${base}/chaindata/ancient/bodies"
  print_row "Receipts"      "${base}/chaindata/ancient/receipts"
  print_row "State (trie)"  "${base}/chaindata"
  print_row "Freezer/Ancient" "${base}/chaindata/ancient"
  print_row "LightChainData" "${base}/lightchaindata"
  print_row "Keystore"      "${base}/keystore"
  print_row "Total"         "${base}"
  echo "└─────────────────────────────────────────────────────────┘"
}

stats_erigon() {
  local base="${DATA_DIR}/${NETWORK}/erigon"
  echo "┌─── Erigon (XDC) ────────────────────────────────────────┐"
  print_row "Headers (MDBX)"  "${base}/chaindata"
  print_row "Bodies"          "${base}/snapshots/bodies"
  print_row "State"           "${base}/snapshots/state"
  print_row "Receipts"        "${base}/snapshots/receipts"
  print_row "Snapshots"       "${base}/snapshots"
  print_row "Temp/ETL"        "${base}/temp"
  print_row "Total"           "${base}"
  echo "└─────────────────────────────────────────────────────────┘"
}

stats_nethermind() {
  local base="${DATA_DIR}/${NETWORK}/nethermind"
  echo "┌─── Nethermind (XDC) ────────────────────────────────────┐"
  print_row "State (DB)"    "${base}/state"
  print_row "Receipts"      "${base}/receipts"
  print_row "Headers"       "${base}/headers"
  print_row "Blocks"        "${base}/blocks"
  print_row "Blooms"        "${base}/blooms"
  print_row "Metadata"      "${base}/metadata"
  print_row "Total"         "${base}"
  echo "└─────────────────────────────────────────────────────────┘"
}

stats_reth() {
  local base="${DATA_DIR}/${NETWORK}/reth"
  echo "┌─── Reth (XDC) ──────────────────────────────────────────┐"
  print_row "Headers"       "${base}/db/headers"
  print_row "Bodies"        "${base}/db/bodies"
  print_row "State"         "${base}/db/trie"
  print_row "Receipts"      "${base}/db/receipts"
  print_row "Static Files"  "${base}/static_files"
  print_row "Total"         "${base}"
  echo "└─────────────────────────────────────────────────────────┘"
}

summary() {
  echo ""
  echo "=== Summary: ${NETWORK} ==="
  local total=0
  for client in geth erigon nethermind reth; do
    local base="${DATA_DIR}/${NETWORK}/${client}"
    local bytes
    bytes="$(dir_size_bytes "$base")"
    local human
    human="$(human_size "$bytes")"
    printf "  %-15s %12s\n" "$client" "$human"
    total=$(( total + bytes ))
  done
  echo "  ─────────────────────────"
  printf "  %-15s %12s\n" "TOTAL" "$(human_size "$total")"

  echo ""
  echo "Disk free on data volume:"
  df -h "$DATA_DIR" 2>/dev/null | tail -1 | awk '{printf "  Available: %s / %s (%s used)\n", $4, $2, $5}'
}

CLIENT="${1:-all}"
NETWORK="${2:-${NETWORK}}"

[[ "$1" == "--help" || "$1" == "-h" ]] && usage

echo "=== XDC Chain Data Breakdown (${NETWORK}) ==="
echo ""

case "$CLIENT" in
  geth)        stats_geth ;;
  erigon)      stats_erigon ;;
  nethermind)  stats_nethermind ;;
  reth)        stats_reth ;;
  all)
    stats_geth; echo ""
    stats_erigon; echo ""
    stats_nethermind; echo ""
    stats_reth
    summary
    ;;
  *) usage ;;
esac
