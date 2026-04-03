#!/usr/bin/env bash
# =============================================================================
# backup.sh — XDC Node Backup & Disaster Recovery Pipeline
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/95
#
# Usage:
#   backup.sh create   <client> <network>   Stop, snapshot, restart
#   backup.sh schedule                      Install weekly cron
#   backup.sh list                          Show available backups
#   backup.sh restore  <file>               Restore from backup
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

BACKUP_DIR="/var/backups/xdc"
RETENTION_DAYS=30   # keep backups for 30 days

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

compress_dir() {
  local src="$1" dest="$2"
  if command -v zstd &>/dev/null; then
    tar -cf - -C "$(dirname "$src")" "$(basename "$src")" | \
      zstd -T0 -3 --long -o "$dest"
  else
    dest="${dest%.zst}.gz"
    tar -czf "$dest" -C "$(dirname "$src")" "$(basename "$src")"
  fi
  echo "$dest"
}

# =============================================================================
# CMD: create — stop container, snapshot data, restart
# =============================================================================
cmd_create() {
  local client="${1:-}" network="${2:-}"
  [[ -z "$client" || -z "$network" ]] && die "Usage: backup.sh create <client> <network>"
  client="$(normalise_client "$client")"
  network="$(normalise_network "$network")"

  local datadir
  datadir="$(datadir_for "$client" "$network")"
  local container
  container="$(container_for "$client" "$network")"

  [[ -d "$datadir" ]] || die "Data directory not found: $datadir"

  mkdir -p "$BACKUP_DIR"

  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local outbase="${BACKUP_DIR}/${client}-${network}-${ts}.tar.zst"

  info "Creating backup for ${BOLD}$client${NC} ($network)"
  info "  Source:      $datadir"
  info "  Destination: $outbase"
  echo ""

  # ── Stop container ─────────────────────────────────────────────────────────
  local was_running=false
  if docker inspect "$container" &>/dev/null 2>&1; then
    local state
    state="$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || echo "false")"
    if [[ "$state" == "true" ]]; then
      info "Stopping container for clean backup: $container"
      docker stop "$container"
      was_running=true
    fi
  fi

  # ── Compress ───────────────────────────────────────────────────────────────
  info "Compressing data directory…"
  local outfile
  outfile="$(compress_dir "$datadir" "$outbase")"
  local size
  size="$(du -sh "$outfile" | cut -f1)"

  ok "Backup created: $outfile ($size)"

  # Write metadata sidecar
  cat > "${outfile%.tar.*}.meta.json" <<EOF
{
  "client":    "$client",
  "network":   "$network",
  "datadir":   "$datadir",
  "timestamp": "$ts",
  "size":      "$size",
  "file":      "$(basename "$outfile")",
  "host":      "$(hostname -f 2>/dev/null || hostname)"
}
EOF

  # ── Restart container ──────────────────────────────────────────────────────
  if [[ "$was_running" == "true" ]]; then
    info "Restarting container: $container"
    docker start "$container"
    ok "Container restarted."
  fi

  # ── Cleanup old backups ───────────────────────────────────────────────────
  info "Cleaning up backups older than ${RETENTION_DAYS} days…"
  local deleted=0
  while IFS= read -r old; do
    rm -f "$old" "${old%.tar.*}.meta.json" 2>/dev/null || true
    ((deleted++))
  done < <(find "$BACKUP_DIR" -name "${client}-${network}-*.tar.*" \
             -mtime +${RETENTION_DAYS} 2>/dev/null || true)
  [[ $deleted -gt 0 ]] && info "Removed $deleted old backup(s)."

  echo ""
  ok "Backup complete: $outfile"
}

# =============================================================================
# CMD: schedule — install weekly cron
# =============================================================================
cmd_schedule() {
  local client="${1:-all}" network="${2:-mainnet}"

  local script_path
  script_path="$(realpath "${BASH_SOURCE[0]}")"

  local cron_file="/etc/cron.d/xdc-backup"
  local cron_line

  if [[ "$client" == "all" ]]; then
    cron_line="0 2 * * 0 root $script_path create gp5 mainnet >> /var/log/xdc-backup.log 2>&1"$'\n'
    cron_line+="30 2 * * 0 root $script_path create erigon mainnet >> /var/log/xdc-backup.log 2>&1"$'\n'
    cron_line+="0 3 * * 0 root $script_path create reth mainnet >> /var/log/xdc-backup.log 2>&1"$'\n'
    cron_line+="30 3 * * 0 root $script_path create nethermind mainnet >> /var/log/xdc-backup.log 2>&1"
  else
    client="$(normalise_client "$client")"
    network="$(normalise_network "$network")"
    cron_line="0 2 * * 0 root $script_path create $client $network >> /var/log/xdc-backup.log 2>&1"
  fi

  info "Installing weekly backup cron: $cron_file"
  cat > "$cron_file" <<EOF
# XDC Node Weekly Backup
# Generated by backup.sh schedule on $(date)
# Runs every Sunday at 02:00 (server time)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

${cron_line}
EOF

  chmod 644 "$cron_file"
  ok "Cron installed: $cron_file"
  echo ""
  cat "$cron_file"
  echo ""
  info "Logs: /var/log/xdc-backup.log"
  info "To remove: rm $cron_file"
}

# =============================================================================
# CMD: list — show available backups
# =============================================================================
cmd_list() {
  local filter="${1:-}"

  mkdir -p "$BACKUP_DIR"

  echo -e "${BOLD}XDC Backups in ${BACKUP_DIR}${NC}"
  echo ""

  local pattern="${filter:+*${filter}*}"
  pattern="${pattern:-*.tar.*}"

  local count=0
  while IFS= read -r f; do
    local size ts client network
    size="$(du -sh "$f" 2>/dev/null | cut -f1)"
    ts="$(stat -c '%y' "$f" 2>/dev/null | cut -d. -f1 || echo "?")"

    # Parse from filename: client-network-YYYYMMDD-HHMMSS.tar.*
    local fname
    fname="$(basename "$f")"
    client="$(echo "$fname" | cut -d- -f1)"
    network="$(echo "$fname" | cut -d- -f2)"

    # Check for metadata
    local meta="${f%.tar.*}.meta.json"
    if [[ -f "$meta" ]] && command -v jq &>/dev/null; then
      client="$(jq -r '.client' "$meta")"
      network="$(jq -r '.network' "$meta")"
      ts="$(jq -r '.timestamp' "$meta")"
    fi

    printf "  %-45s  %-12s  %-10s  %s\n" "$(basename "$f")" "$size" "$client/$network" "$ts"
    ((count++))
  done < <(find "$BACKUP_DIR" -maxdepth 1 -name "$pattern" -type f 2>/dev/null | sort -r)

  if [[ $count -eq 0 ]]; then
    echo "  No backups found."
    echo ""
    echo "  Create one with: backup.sh create <client> <network>"
  else
    echo ""
    echo "  Total: $count backup(s)"
  fi
}

# =============================================================================
# CMD: restore — restore data directory from backup
# =============================================================================
cmd_restore() {
  local file="${1:-}"
  [[ -z "$file" ]] && die "Usage: backup.sh restore <file>"
  [[ -f "$file" ]] || die "Backup file not found: $file"

  local meta="${file%.tar.*}.meta.json"

  # Detect client + network from metadata or filename
  local client network datadir container
  if [[ -f "$meta" ]] && command -v jq &>/dev/null; then
    client="$(jq -r '.client' "$meta")"
    network="$(jq -r '.network' "$meta")"
    datadir="$(jq -r '.datadir' "$meta")"
  else
    # Parse from filename
    local fname
    fname="$(basename "$file")"
    client="$(echo "$fname" | cut -d- -f1)"
    network="$(echo "$fname" | cut -d- -f2)"
    datadir="$(datadir_for "$client" "$network")"
  fi

  container="$(container_for "$client" "$network")"

  info "Restoring backup: $file"
  info "  Client:  $client"
  info "  Network: $network"
  info "  Target:  $datadir"
  echo ""

  warn "This will REPLACE the current data directory."
  read -rp "Continue? [y/N] " confirm
  [[ "${confirm,,}" == "y" ]] || die "Aborted by user."

  # Stop container
  local was_running=false
  if docker inspect "$container" &>/dev/null 2>&1; then
    local state
    state="$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || echo false)"
    if [[ "$state" == "true" ]]; then
      info "Stopping container: $container"
      docker stop "$container"
      was_running=true
    fi
  fi

  # Backup existing data
  if [[ -d "$datadir" ]]; then
    local old="${datadir}.pre-restore.$(date +%Y%m%d%H%M%S)"
    warn "Moving existing data to: $old"
    mv "$datadir" "$old"
  fi

  mkdir -p "$datadir"

  info "Extracting…"
  case "$file" in
    *.tar.zst) tar --zstd -xf "$file" -C "$datadir" --strip-components=1 ;;
    *.tar.gz)  tar -xzf "$file" -C "$datadir" --strip-components=1 ;;
    *.tar.bz2) tar -xjf "$file" -C "$datadir" --strip-components=1 ;;
    *.tar)     tar -xf  "$file" -C "$datadir" --strip-components=1 ;;
    *) die "Unsupported archive format: $file" ;;
  esac

  # Fix permissions for Erigon
  if [[ "$client" == "erigon" ]]; then
    info "Fixing Erigon uid/gid (1000:1000)…"
    chown -R 1000:1000 "$datadir" 2>/dev/null || warn "chown failed (run as root)"
  fi

  ok "Restore complete: $datadir"

  if [[ "$was_running" == "true" ]]; then
    info "Restarting container: $container"
    docker start "$container"
    ok "Container restarted."
  fi
}

# =============================================================================
# Entry point
# =============================================================================
usage() {
  cat <<EOF
${BOLD}backup.sh${NC} — XDC Node Backup & Disaster Recovery

Usage:
  backup.sh create   <client> <network>   Stop, backup, restart node
  backup.sh schedule [client] [network]   Install weekly cron job
  backup.sh list     [filter]             List available backups
  backup.sh restore  <file>               Restore node from backup

Clients:  gp5 | erigon | reth | nethermind
Networks: mainnet | apothem | devnet
Backup location: $BACKUP_DIR
Retention: $RETENTION_DAYS days
EOF
}

case "${1:-help}" in
  create)   shift; cmd_create   "$@" ;;
  schedule) shift; cmd_schedule "$@" ;;
  list)     shift; cmd_list     "$@" ;;
  restore)  shift; cmd_restore  "$@" ;;
  help|--help|-h) usage ;;
  *) error "Unknown command: $1"; usage; exit 1 ;;
esac
