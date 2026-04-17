#!/usr/bin/env bash
# =============================================================================
# snapshot.sh — XDC Node Snapshot Management (PBSS/HBSS aware)
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/84
#
# Usage:
#   snapshot.sh detect [datadir]
#   snapshot.sh download <client> <network>
#   snapshot.sh restore  <client> <network> <file>
#   snapshot.sh create   <client> <network>
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIGS_DIR="$PROJECT_DIR/configs"
SNAPSHOTS_URL="https://xdc.network/snapshots/"

# Source chaindata auto-detection library
source "${SCRIPT_DIR}/lib/chaindata.sh" 2>/dev/null || true

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
    mainnet|main)              echo "mainnet" ;;
    testnet|apothem|apothem)   echo "apothem" ;;
    devnet|dev)                echo "devnet"  ;;
    *)                         echo "$n"      ;;
  esac
}

# Return the default data directory for a client+network combo
datadir_for() {
  local client="$1" network="$2"
  case "$client" in
    gp5)         echo "$PROJECT_DIR/$network/xdcchain" ;;
    erigon)      echo "$PROJECT_DIR/$network/xdcchain-erigon" ;;
    reth)        echo "$PROJECT_DIR/$network/xdcchain-reth" ;;
    nethermind)  echo "$PROJECT_DIR/$network/xdcchain-nm" ;;
    *)           echo "$PROJECT_DIR/$network/xdcchain" ;;
  esac
}

# Container name for a client+network combo
container_for() {
  local client="$1" network="$2"
  case "$client" in
    gp5)         echo "xdc-gp5-$network"         ;;
    erigon)      echo "xdc-erigon-$network"      ;;
    reth)        echo "xdc-reth-$network"         ;;
    nethermind)  echo "xdc-nethermind-$network"  ;;
    *)           echo "xdc-$client-$network"      ;;
  esac
}

# =============================================================================
# CMD: detect — determine state scheme (PBSS vs HBSS)
# =============================================================================
cmd_detect() {
  local datadir="${1:-}"

  if [[ -z "$datadir" ]]; then
    # Try to guess from common locations
    for candidate in \
        "$PROJECT_DIR/mainnet/xdcchain" \
        "$PROJECT_DIR/apothem/xdcchain" \
        /data/xdcchain /opt/xdc/data; do
      if [[ -d "$candidate" ]]; then
        datadir="$candidate"
        break
      fi
    done
  fi

  if [[ -z "$datadir" || ! -d "$datadir" ]]; then
    die "Cannot find data directory. Pass it as: snapshot.sh detect <datadir>"
  fi

  info "Inspecting: $datadir"
  echo ""

  # 1) Explicit marker file (written by this script on restore/create)
  if [[ -f "$datadir/.state-scheme" ]]; then
    local scheme
    scheme="$(cat "$datadir/.state-scheme")"
    ok "State scheme (from marker): ${BOLD}${scheme}${NC}"
    _print_scheme_info "$scheme"
    return 0
  fi

  # 2) Heuristic: PBSS uses path-based keys → triehash file absent, trie dir differs
  #    HBSS uses XDC/chaindata/ancient/ directory
  local scheme="UNKNOWN"
  local subdir
  subdir=$(find_chaindata_subdir_or_default "$datadir" 2>/dev/null || echo "")
  local chaindata_base="$datadir${subdir:+/$subdir}"

  if [[ -d "$chaindata_base/chaindata/ancient" ]]; then
    scheme="HBSS"
  fi

  # PBSS (path-based state scheme) — go-ethereum ≥1.13 uses triedb/path/
  if [[ -d "$chaindata_base/chaindata/triedb" ]]; then
    scheme="PBSS"
  fi

  # Erigon uses MDBX and has a different layout (no chaindata/ancient)
  if [[ -f "$datadir/mdbx.dat" ]] || \
     [[ -d "$datadir/chaindata" && ! -d "$datadir/chaindata/ancient" ]]; then
    scheme="ERIGON-MDBX"
  fi

  echo -e "State scheme: ${BOLD}${scheme}${NC}"
  _print_scheme_info "$scheme"
}

_print_scheme_info() {
  local scheme="$1"
  echo ""
  case "$scheme" in
    PBSS)
      echo -e "${GREEN}PBSS (Path-Based State Scheme)${NC}"
      echo "  ✓ Requires go-ethereum ≥ 1.13 / GP5 ≥ 2.4.0"
      echo "  ✓ More efficient state storage (pruned on-the-fly)"
      echo "  ✗ NOT compatible with HBSS snapshots"
      ;;
    HBSS)
      echo -e "${YELLOW}HBSS (Hash-Based State Scheme)${NC}"
      echo "  ✓ Traditional Ethereum state format"
      echo "  ✓ Compatible with all older GP5 / v2.6.8 clients"
      echo "  ✗ NOT compatible with PBSS snapshots"
      ;;
    ERIGON-MDBX)
      echo -e "${CYAN}Erigon MDBX format${NC}"
      echo "  ✓ Erigon uses its own efficient state layout"
      echo "  ✗ Cannot import GP5/Nethermind snapshots directly"
      ;;
    *)
      echo -e "${RED}Unknown or empty data directory${NC}"
      echo "  Run after initial sync or after a restore."
      ;;
  esac
}

# =============================================================================
# CMD: download — fetch snapshot from xdc.network
# =============================================================================
cmd_download() {
  local client="${1:-}" network="${2:-}"
  [[ -z "$client" || -z "$network" ]] && die "Usage: snapshot.sh download <client> <network>"
  client="$(normalise_client "$client")"
  network="$(normalise_network "$network")"

  info "Snapshot download for ${BOLD}$client${NC} on ${BOLD}$network${NC}"
  echo ""
  warn "XDC Network does not currently host public snapshots."
  echo "  Check: ${CYAN}${SNAPSHOTS_URL}${NC}"
  echo ""

  # Check configs/snapshots.json for any known URLs
  local cfg="$CONFIGS_DIR/snapshots.json"
  if [[ -f "$cfg" ]] && command -v jq &>/dev/null; then
    local url
    url="$(jq -r --arg net "$network" '.[$net].full.url // "N/A"' "$cfg" 2>/dev/null || echo "N/A")"
    if [[ "$url" != "N/A" && "$url" != "null" ]]; then
      info "Found snapshot URL: $url"
      local dest="/tmp/xdc-snapshot-${client}-${network}.tar.gz"
      info "Downloading to $dest …"
      # Verify scheme compatibility before downloading
      local datadir
      datadir="$(datadir_for "$client" "$network")"
      if [[ -f "$datadir/.state-scheme" ]]; then
        local existing_scheme
        existing_scheme="$(cat "$datadir/.state-scheme")"
        warn "Existing data uses ${existing_scheme}."
        warn "Ensure the downloaded snapshot matches that scheme!"
      fi
      wget --show-progress -O "$dest" "$url" || curl -L --progress-bar -o "$dest" "$url"
      ok "Downloaded: $dest"
      echo ""
      info "To restore: snapshot.sh restore $client $network $dest"
      return 0
    fi
  fi

  echo "No public snapshot available yet."
  echo ""
  echo "Alternatives:"
  echo "  1. Sync from genesis (slow but trustless)"
  echo "  2. Get a peer-shared snapshot from the XDC community"
  echo "  3. Create one yourself: snapshot.sh create $client $network"
  echo ""
  warn "PBSS ↔ HBSS incompatibility: always verify scheme before restoring."
}

# =============================================================================
# CMD: restore — extract snapshot to correct datadir
# =============================================================================
cmd_restore() {
  local client="${1:-}" network="${2:-}" file="${3:-}"
  [[ -z "$client" || -z "$network" || -z "$file" ]] && \
    die "Usage: snapshot.sh restore <client> <network> <file>"
  client="$(normalise_client "$client")"
  network="$(normalise_network "$network")"

  [[ -f "$file" ]] || die "Snapshot file not found: $file"

  local datadir
  datadir="$(datadir_for "$client" "$network")"
  local container
  container="$(container_for "$client" "$network")"

  info "Restoring ${BOLD}$file${NC} → ${BOLD}$datadir${NC}"
  echo ""

  # Detect scheme of archive vs existing data
  local snap_scheme="UNKNOWN"
  if echo "$file" | grep -qi "pbss"; then snap_scheme="PBSS"; fi
  if echo "$file" | grep -qi "hbss"; then snap_scheme="HBSS"; fi

  if [[ -f "$datadir/.state-scheme" ]]; then
    local existing_scheme
    existing_scheme="$(cat "$datadir/.state-scheme")"
    if [[ "$snap_scheme" != "UNKNOWN" && "$snap_scheme" != "$existing_scheme" ]]; then
      error "Scheme mismatch! Existing data is ${existing_scheme} but snapshot appears to be ${snap_scheme}."
      error "Remove existing data first, or use a matching snapshot."
      die "Aborting to prevent data corruption."
    fi
  fi

  # Ensure container is stopped
  if docker inspect "$container" &>/dev/null 2>&1; then
    info "Stopping container: $container"
    docker stop "$container" || true
  fi

  # Backup existing data (optional, quick rename)
  if [[ -d "$datadir" && "$(ls -A "$datadir" 2>/dev/null)" ]]; then
    local backup_dir="${datadir}.bak.$(date +%Y%m%d%H%M%S)"
    warn "Renaming existing datadir to: $backup_dir"
    mv "$datadir" "$backup_dir"
  fi

  mkdir -p "$datadir"

  info "Extracting archive …"
  case "$file" in
    *.tar.gz|*.tgz)   tar -xzf "$file" -C "$datadir" --strip-components=1 ;;
    *.tar.zst)        tar --zstd -xf "$file" -C "$datadir" --strip-components=1 ;;
    *.tar.bz2)        tar -xjf "$file" -C "$datadir" --strip-components=1 ;;
    *.tar)            tar -xf  "$file" -C "$datadir" --strip-components=1 ;;
    *.lz4)
      command -v lz4 &>/dev/null || die "lz4 not installed. Run: apt install lz4"
      lz4 -d "$file" | tar -xf - -C "$datadir" --strip-components=1
      ;;
    *)  die "Unsupported archive format: $file" ;;
  esac

  # Fix permissions
  info "Fixing permissions …"
  case "$client" in
    erigon)
      # Erigon requires uid 1000 for MDBX files
      chown -R 1000:1000 "$datadir" 2>/dev/null || \
        warn "Could not chown (run as root for full fix)"
      ;;
    gp5|nethermind|reth)
      chmod -R 755 "$datadir"
      ;;
  esac

  # Write state-scheme marker
  if [[ "$snap_scheme" != "UNKNOWN" ]]; then
    echo "$snap_scheme" > "$datadir/.state-scheme"
    ok "Wrote state scheme marker: $snap_scheme"
  else
    info "Could not auto-detect scheme from filename. Run: snapshot.sh detect $datadir"
  fi

  ok "Restore complete: $datadir"
  echo ""
  info "Start node: docker compose up -d $container"
}

# =============================================================================
# CMD: create — create snapshot from running node
# =============================================================================
cmd_create() {
  local client="${1:-}" network="${2:-}"
  [[ -z "$client" || -z "$network" ]] && die "Usage: snapshot.sh create <client> <network>"
  client="$(normalise_client "$client")"
  network="$(normalise_network "$network")"

  local datadir
  datadir="$(datadir_for "$client" "$network")"
  local container
  container="$(container_for "$client" "$network")"

  [[ -d "$datadir" ]] || die "Data directory does not exist: $datadir"

  # Detect scheme
  local scheme="UNKNOWN"
  if [[ -f "$datadir/.state-scheme" ]]; then
    scheme="$(cat "$datadir/.state-scheme")"
  else
    local subdir
    subdir=$(find_chaindata_subdir_or_default "$datadir" 2>/dev/null || echo "")
    local chaindata_base="$datadir${subdir:+/$subdir}"
    [[ -d "$chaindata_base/chaindata/ancient" ]] && scheme="HBSS"
    [[ -d "$chaindata_base/chaindata/triedb"  ]] && scheme="PBSS"
    [[ -f "$datadir/mdbx.dat" ]]              && scheme="ERIGON-MDBX"
  fi

  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local outfile="/var/backups/xdc/${client}-${network}-${scheme,,}-${ts}.tar.zst"
  mkdir -p /var/backups/xdc

  info "Creating snapshot: ${BOLD}$outfile${NC}"
  info "State scheme: ${BOLD}$scheme${NC}"
  echo ""

  # Stop container
  if docker inspect "$container" &>/dev/null 2>&1; then
    info "Stopping container: $container (clean shutdown for consistent snapshot)"
    docker stop "$container"
  fi

  info "Compressing $datadir …"
  if command -v zstd &>/dev/null; then
    tar -cf - -C "$(dirname "$datadir")" "$(basename "$datadir")" | \
      zstd -T0 -3 -o "$outfile"
  else
    outfile="${outfile%.zst}.gz"
    tar -czf "$outfile" -C "$(dirname "$datadir")" "$(basename "$datadir")"
  fi

  ok "Snapshot created: $outfile"
  echo "  Size: $(du -sh "$outfile" | cut -f1)"
  echo "  Scheme: $scheme"
  echo ""

  # Restart container
  if docker inspect "$container" &>/dev/null 2>&1; then
    info "Restarting container: $container"
    docker start "$container"
  fi

  ok "Done. Share $outfile with peers (include scheme=$scheme in filename)."
}

# =============================================================================
# Entry point
# =============================================================================
usage() {
  cat <<EOF
${BOLD}snapshot.sh${NC} — XDC Snapshot Management

Usage:
  snapshot.sh detect [datadir]                   Detect PBSS/HBSS state scheme
  snapshot.sh download <client> <network>        Download snapshot from xdc.network
  snapshot.sh restore  <client> <network> <file> Restore snapshot to datadir
  snapshot.sh create   <client> <network>        Create snapshot from running node

Clients:  gp5 | erigon | reth | nethermind
Networks: mainnet | apothem | devnet

${YELLOW}⚠ PBSS and HBSS snapshots are NOT interchangeable.${NC}
  Always verify the scheme matches your client configuration.
EOF
}

case "${1:-help}" in
  detect)   shift; cmd_detect   "$@" ;;
  download) shift; cmd_download "$@" ;;
  restore)  shift; cmd_restore  "$@" ;;
  create)   shift; cmd_create   "$@" ;;
  help|--help|-h) usage ;;
  *) error "Unknown command: $1"; usage; exit 1 ;;
esac
