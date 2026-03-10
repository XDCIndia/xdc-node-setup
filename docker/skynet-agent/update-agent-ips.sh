#!/bin/bash
# Refresh SkyOne agent RPC URLs when node container IPs change after restart.
# Run via cron: */5 * * * * /path/to/update-agent-ips.sh >> /var/log/skyone-refresh.log 2>&1
#
# Internal ports (container-side, NOT host-mapped):
#   gp5=8545, erigon=8545, nm=8545, reth=7073

CONF_DIR="${CONF_DIR:-/mnt/data/mainnet/.xdc-node}"

declare -A INTERNAL_PORTS=(
  [gp5]=8545
  [erigon]=8545
  [nm]=8545
  [reth]=7073
)

get_container_ip() {
  docker inspect "$1" 2>/dev/null | python3 -c \
    'import json,sys; nets=json.load(sys.stdin)[0]["NetworkSettings"]["Networks"]; print(list(nets.values())[0]["IPAddress"])' 2>/dev/null
}

CHANGED=0

for CLIENT in gp5 erigon nm reth; do
  WANT_PORT="${INTERNAL_PORTS[$CLIENT]}"
  CONF="${CONF_DIR}/skynet-${CLIENT}.conf"

  # Get current node container IP
  CURR_IP=$(get_container_ip "xdc-mainnet-${CLIENT}")
  [ -z "$CURR_IP" ] && continue

  # Read what's currently in the conf
  CONF_IP=$(grep "RPC_URL" "$CONF" 2>/dev/null | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}')
  CONF_PORT=$(grep "RPC_URL" "$CONF" 2>/dev/null | grep -oE ':[0-9]+$' | tr -d ':')

  if [ "$CURR_IP" != "$CONF_IP" ] || [ "$CONF_PORT" != "$WANT_PORT" ]; then
    NEW_RPC="http://${CURR_IP}:${WANT_PORT}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${CLIENT}: updating ${CONF_IP}:${CONF_PORT} -> ${CURR_IP}:${WANT_PORT}"

    # Update conf
    sed -i "s|RPC_URL=.*|RPC_URL=${NEW_RPC}|g" "$CONF"

    # Restart SkyOne agent to pick up new IP
    docker restart "skyone-mainnet-${CLIENT}" 2>/dev/null && \
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${CLIENT}: restarted skyone-mainnet-${CLIENT}" || \
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${CLIENT}: WARNING — could not restart skyone-mainnet-${CLIENT}"

    CHANGED=1
  fi
done

[ "$CHANGED" -eq 0 ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] All SkyOne IPs current — no changes"
