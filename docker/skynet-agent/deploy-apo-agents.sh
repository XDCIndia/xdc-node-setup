#!/bin/bash
# Deploy per-client xdc-agent containers for APO Apothem testnet
# Usage: bash deploy-apo-agents.sh

SKYNET_API_URL="https://net.xdc.network/api"
SKYNET_API_KEY="xdc-netown-key-2026-prod"
HOST_IP="${HOST_IP:-185.180.220.183}"

declare -A NODES
NODES[stable]="f708698c-fbdb-439f-882a-c6e9db6e5870:8545:geth"
NODES[gp5]="2ffab63b-926a-4343-a3c9-96e90eb2c973:8555:geth-pr5"
NODES[erigon]="40259a1d-26e2-47a1-b44b-1e9858a27dc1:8547:erigon"
NODES[nm]="2beb3132-c268-43d1-b67f-9b9ea1ae014b:8557:nethermind"
NODES[reth]="3755a126-c335-4028-bbf6-87c517b99000:8588:reth"

docker rm -f agent-stable agent-gp5 agent-erigon agent-nm agent-reth 2>/dev/null || true

for client in stable gp5 erigon nm reth; do
  IFS=":" read -r NODE_ID RPC_PORT CLIENT_TYPE <<< "${NODES[$client]}"
  docker run -d --name "agent-$client" \
    --restart unless-stopped \
    --network host \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e SKYNET_NODE_ID="$NODE_ID" \
    -e SKYNET_API_KEY="$SKYNET_API_KEY" \
    -e SKYNET_API_URL="$SKYNET_API_URL" \
    -e SKYNET_NODE_NAME="apo-$client-183" \
    -e RPC_URL="http://127.0.0.1:$RPC_PORT" \
    -e NODE_RPC_PORT="$RPC_PORT" \
    -e HOST_IP="$HOST_IP" \
    -e CLIENT_TYPE="$CLIENT_TYPE" \
    -e NETWORK="apothem" \
    -e HEARTBEAT_INTERVAL="60" \
    anilchinchawale/xdc-agent:latest
  echo "✅ agent-$client (nodeId=$NODE_ID rpc=:$RPC_PORT)"
done
