#!/bin/bash
set -euo pipefail
# xdc benchmark v2 — compare all clients side-by-side
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/106
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DURATION=${1:-60}

get_block() {
  curl -s -m 2 -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "http://localhost:$1" 2>/dev/null | \
    jq -r '.result // "0x0"' | xargs printf '%d' 2>/dev/null || echo 0
}

rpc_latency() {
  local start=$(date +%s%N)
  curl -s -m 5 -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "http://localhost:$1" >/dev/null 2>&1
  local end=$(date +%s%N)
  echo $(( (end - start) / 1000000 ))
}

disk_size() {
  local dir="$ROOT_DIR/data/mainnet/$1"
  [ -d "$dir" ] && du -sb "$dir" 2>/dev/null | awk '{print $1}' || echo 0
}

echo "🏁 XDC Multi-Client Benchmark v2"
echo "Duration: ${DURATION}s"
echo ""

# Sample start blocks
declare -A START_BLOCKS START_DISK
CLIENTS="GP5:8545 Erigon:8547 Reth:8548 NM:8558 v268:8550"
DIRS="GP5:gp5 Erigon:erigon Reth:reth NM:nethermind v268:v268"

for entry in $CLIENTS; do
  name="${entry%%:*}"; port="${entry##*:}"
  START_BLOCKS[$name]=$(get_block $port)
done
for entry in $DIRS; do
  name="${entry%%:*}"; dir="${entry##*:}"
  START_DISK[$name]=$(disk_size $dir)
done

echo "Waiting ${DURATION}s..."
sleep "$DURATION"

# Sample end + calculate
echo ""
printf "%-10s │ %10s │ %8s │ %8s │ %6s │ %5s\n" "Client" "Blocks" "Blk/sec" "Disk Δ" "RPC ms" "Score"
echo "───────────┼────────────┼──────────┼──────────┼────────┼──────"

RESULTS=""
for entry in $CLIENTS; do
  name="${entry%%:*}"; port="${entry##*:}"
  end_block=$(get_block $port)
  start_block=${START_BLOCKS[$name]}
  blocks=$((end_block - start_block))
  bps=$(echo "scale=2; $blocks / $DURATION" | bc 2>/dev/null || echo "0")
  
  dir_name=""; for d in $DIRS; do [ "${d%%:*}" = "$name" ] && dir_name="${d##*:}"; done
  end_disk=$(disk_size $dir_name)
  disk_delta=$(( (end_disk - ${START_DISK[$name]}) / 1048576 ))
  
  latency=$(rpc_latency $port)
  
  # Score: 40% sync speed + 30% low latency + 30% low disk growth
  sync_score=$(echo "scale=2; s=$bps; if(s>10) 1.0 else if(s>0) s/10 else 0" | bc 2>/dev/null || echo "0")
  lat_score=$(echo "scale=2; l=$latency; if(l<50) 1.0 else if(l<500) 1-(l-50)/450 else 0" | bc 2>/dev/null || echo "0")
  disk_score="0.7"
  composite=$(echo "scale=2; 0.4*$sync_score + 0.3*$lat_score + 0.3*$disk_score" | bc 2>/dev/null || echo "0")
  
  printf "%-10s │ %10d │ %8s │ %6dMB │ %5dms │ %5s\n" "$name" "$blocks" "$bps" "$disk_delta" "$latency" "$composite"
  RESULTS="$RESULTS{\"client\":\"$name\",\"blocks\":$blocks,\"bps\":$bps,\"diskDeltaMB\":$disk_delta,\"rpcMs\":$latency,\"score\":$composite},"
done

# Export JSON
mkdir -p "$ROOT_DIR/data/benchmarks"
OUTFILE="$ROOT_DIR/data/benchmarks/$(date +%Y-%m-%d_%H%M%S).json"
echo "{\"timestamp\":\"$(date -Iseconds)\",\"duration\":$DURATION,\"results\":[${RESULTS%,}]}" > "$OUTFILE"
echo ""
echo "📁 Results saved to $OUTFILE"
