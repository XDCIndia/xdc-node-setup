#!/bin/bash
# Interactive TUI Dashboard — live node status with ANSI colors
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/101
REFRESH=${1:-5}

get_block() {
  local result=$(curl -s -m 2 -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "http://localhost:$1" 2>/dev/null)
  local hex=$(echo "$result" | jq -r '.result // "0x0"' 2>/dev/null)
  printf '%d' "$((16#${hex#0x}))" 2>/dev/null || echo 0
}
get_peers() {
  local result=$(curl -s -m 2 -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' "http://localhost:$1" 2>/dev/null)
  local hex=$(echo "$result" | jq -r '.result // "0x0"' 2>/dev/null)
  printf '%d' "$((16#${hex#0x}))" 2>/dev/null || echo 0
}

while true; do
  clear
  echo -e "\033[1;36m╔══════════════════════════════════════════════════════════════╗\033[0m"
  echo -e "\033[1;36m║           XDC Multi-Client Dashboard — $(date '+%H:%M:%S')            ║\033[0m"
  echo -e "\033[1;36m╠══════════════════════════════════════════════════════════════╣\033[0m"
  printf "\033[1;36m║\033[0m %-10s │ %12s │ %5s │ %-8s │ %-10s \033[1;36m║\033[0m\n" "Client" "Block" "Peers" "Status" "Container"
  echo -e "\033[1;36m╠══════════════════════════════════════════════════════════════╣\033[0m"

  MAX_BLOCK=0
  for port in 8545 8547 8548 8558 8550; do
    b=$(get_block $port)
    [ "$b" -gt "$MAX_BLOCK" ] && MAX_BLOCK=$b
  done

  for port in 8545 8547 8548 8558 8550; do
    case $port in 8545) name="GP5"; cname="gp5-mainnet" ;; 8547) name="Erigon"; cname="erigon-mainnet" ;; 8548) name="Reth"; cname="reth-mainnet" ;; 8558) name="NM"; cname="nm-mainnet" ;; 8550) name="v268"; cname="v268-mainnet-ref" ;; esac
    block=$(get_block $port); peers=$(get_peers $port)
    cstatus=$(docker inspect -f '{{.State.Status}}' "$cname" 2>/dev/null || echo "off")

    if [ "$block" -gt 0 ]; then
      gap=$((MAX_BLOCK - block))
      if [ "$gap" -lt 100 ]; then status="\033[1;32mAT HEAD\033[0m"
      elif [ "$gap" -lt 10000 ]; then status="\033[1;33mSYNCING\033[0m"
      else status="\033[1;31mBEHIND\033[0m"; fi
    else status="\033[1;31mOFFLINE\033[0m"; fi

    printf "\033[1;36m║\033[0m %-10s │ %12s │ %5s │ %-19s │ %-10s \033[1;36m║\033[0m\n" "$name" "$(printf '%'\''d' $block)" "$peers" "$status" "$cstatus"
  done

  echo -e "\033[1;36m╠══════════════════════════════════════════════════════════════╣\033[0m"
  DISK=$(df /root/.openclaw/workspace/XDC-Node-Setup/data 2>/dev/null | awk 'NR==2{printf "%s/%s (%s)", $3, $2, $5}')
  echo -e "\033[1;36m║\033[0m 💿 Disk: $DISK"
  echo -e "\033[1;36m║\033[0m 🔝 Fleet max: $(printf '%'\''d' $MAX_BLOCK)"
  echo -e "\033[1;36m╚══════════════════════════════════════════════════════════════╝\033[0m"
  echo "  Refresh: ${REFRESH}s | Ctrl+C to exit"
  sleep "$REFRESH"
done
