#!/usr/bin/env bash
# hw-profile.sh — Hardware-Aware Config (#122)
# Detect hardware specs, suggest optimal config per client.
set -euo pipefail

log() { echo "$*"; }

detect_cpu() {
  local cores
  cores="$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 4)"
  local model
  model="$(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo 'Unknown')"
  echo "$cores|$model"
}

detect_ram() {
  local total_kb
  total_kb="$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 8388608)"
  echo $((total_kb / 1024))  # MB
}

detect_disk() {
  local data_path="${1:-/}"
  local disk_type="HDD"
  local size_gb=0

  # Detect SSD vs HDD via rotational flag
  local device
  device="$(df "$data_path" 2>/dev/null | tail -1 | awk '{print $1}' | sed 's|/dev/||' | sed 's/[0-9]*$//')"
  if [[ -f "/sys/block/${device}/queue/rotational" ]]; then
    local rot
    rot="$(cat "/sys/block/${device}/queue/rotational" 2>/dev/null)"
    [[ "$rot" == "0" ]] && disk_type="SSD/NVMe"
  fi

  size_gb="$(df -BG "$data_path" 2>/dev/null | tail -1 | awk '{gsub("G",""); print $2}' || echo 100)"
  echo "${disk_type}|${size_gb}"
}

detect_network_speed() {
  # Quick bandwidth estimate via download test
  local speed_mbps=100  # default assumption
  if command -v curl &>/dev/null; then
    local bytes_downloaded
    local elapsed
    local start end
    start="$(date +%s%N)"
    bytes_downloaded="$(curl -sf --max-time 5 -o /dev/null -w '%{size_download}' \
      https://speed.cloudflare.com/__down?bytes=1000000 2>/dev/null || echo 0)"
    end="$(date +%s%N)"
    elapsed=$(( (end - start) / 1000000 ))  # ms
    if [[ $elapsed -gt 0 && $bytes_downloaded -gt 0 ]]; then
      speed_mbps=$(( bytes_downloaded * 8 / elapsed / 1000 ))  # Mbps
    fi
  fi
  echo "$speed_mbps"
}

suggest_config() {
  local client="$1"
  local cpu_cores="$2"
  local ram_mb="$3"
  local disk_type="$4"
  local net_mbps="$5"

  local maxpeers cache workers gcmode

  # Base calculations
  maxpeers=$(( cpu_cores * 5 ))
  [[ $maxpeers -gt 100 ]] && maxpeers=100
  [[ $maxpeers -lt 20 ]] && maxpeers=20

  # Cache: ~25% of RAM, min 512MB, max 16384MB
  cache=$(( ram_mb / 4 ))
  [[ $cache -lt 512 ]] && cache=512
  [[ $cache -gt 16384 ]] && cache=16384

  workers=$cpu_cores

  # Disk type adjustments
  if [[ "$disk_type" == "SSD/NVMe" ]]; then
    cache=$(( cache * 3 / 2 ))  # +50% cache for SSD
    maxpeers=$(( maxpeers + 10 ))
  fi

  # Network adjustments
  if [[ $net_mbps -lt 50 ]]; then
    maxpeers=$(( maxpeers / 2 ))
  elif [[ $net_mbps -gt 500 ]]; then
    maxpeers=$(( maxpeers + 20 ))
  fi

  # Client-specific tuning
  case "$client" in
    geth)
      gcmode="full"
      [[ "$disk_type" == "SSD/NVMe" ]] && gcmode="archive"
      cat <<CONF
## Geth Recommended Config
--maxpeers ${maxpeers}
--cache ${cache}
--txpool.globalslots $(( cache * 4 ))
--gcmode ${gcmode}

# docker-compose env:
GETH_MAXPEERS=${maxpeers}
GETH_CACHE=${cache}
GETH_GCMODE=${gcmode}
CONF
      ;;
    erigon)
      cat <<CONF
## Erigon Recommended Config
--maxpeers ${maxpeers}
--batchSize ${cache}MB
--etl.bufferSize ${cache}MB
--p2p.allowed-ports 30303

# docker-compose env:
ERIGON_MAXPEERS=${maxpeers}
ERIGON_BATCHSIZE=${cache}
CONF
      ;;
    nethermind)
      cat <<CONF
## Nethermind Recommended Config
Network.MaxActivePeers=${maxpeers}
Sync.AncientBodiesBarrier=11052984
Init.MemoryHint=$(( ram_mb * 1024 * 1024 / 2 ))

# docker-compose env:
NM_MAXPEERS=${maxpeers}
NM_MEMORY_HINT=$(( ram_mb / 2 ))MB
CONF
      ;;
    reth)
      cat <<CONF
## Reth Recommended Config
--max-outbound-peers ${maxpeers}
--max-inbound-peers $(( maxpeers / 2 ))
--db.max-size $(( cache * 4 ))MB

# docker-compose env:
RETH_MAX_PEERS=${maxpeers}
RETH_DB_MAX_SIZE=$(( cache * 4 ))
CONF
      ;;
  esac
}

main() {
  echo "=== Hardware Profile ==="

  IFS='|' read -r cpu_cores cpu_model <<< "$(detect_cpu)"
  ram_mb="$(detect_ram)"
  IFS='|' read -r disk_type disk_gb <<< "$(detect_disk)"
  echo "  Detecting network speed (may take a few seconds)..."
  net_mbps="$(detect_network_speed)"

  echo ""
  echo "📋 Hardware Summary:"
  echo "  CPU: ${cpu_cores} cores — ${cpu_model}"
  echo "  RAM: ${ram_mb} MB ($(( ram_mb / 1024 )) GB)"
  echo "  Disk: ${disk_type}, ${disk_gb} GB available"
  echo "  Network: ~${net_mbps} Mbps"
  echo ""

  local profile_tier
  if [[ $ram_mb -lt 4096 ]]; then
    profile_tier="Low-end (< 4GB RAM)"
  elif [[ $ram_mb -lt 16384 ]]; then
    profile_tier="Mid-range (4–16 GB RAM)"
  elif [[ $ram_mb -lt 65536 ]]; then
    profile_tier="High-end (16–64 GB RAM)"
  else
    profile_tier="Server-grade (> 64 GB RAM)"
  fi
  echo "🏷️  Profile tier: ${profile_tier}"
  echo ""

  echo "=== Recommended Configs ==="
  for client in geth erigon nethermind reth; do
    echo ""
    suggest_config "$client" "$cpu_cores" "$ram_mb" "$disk_type" "$net_mbps"
  done
}

main "$@"
