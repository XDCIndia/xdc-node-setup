#!/bin/bash
# Send FCU to Reth after restart
# Usage: ./docker/shared/reth-fcu.sh [mainnet|apothem]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/.env.${1:-mainnet}"

GENESIS="0x4a9d748bd78a8d0385b67788c2435dcdb914f98a96250b68863a1f8b7642d6b1"
JWT_FILE="$(dirname "$SCRIPT_DIR")/../data/${1:-mainnet}/reth/jwt.hex"
JWT=$(cat "$JWT_FILE" 2>/dev/null || echo "")
[ -z "$JWT" ] && echo "No jwt.hex found" && exit 1

HEADER=$(echo -n '{"alg":"HS256","typ":"JWT"}' | base64 -w0 | tr '+/' '-_' | tr -d '=')
NOW=$(date +%s)
PAYLOAD=$(echo -n "{\"iat\":$NOW}" | base64 -w0 | tr '+/' '-_' | tr -d '=')
SIGN_INPUT="$HEADER.$PAYLOAD"
SIG=$(echo -n "$SIGN_INPUT" | openssl dgst -sha256 -hmac "$(echo -n "$JWT" | xxd -r -p)" -binary | base64 -w0 | tr '+/' '-_' | tr -d '=')
TOKEN="$SIGN_INPUT.$SIG"

curl -s -m 5 -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"engine_forkchoiceUpdatedV1\",\"params\":[{\"headBlockHash\":\"$GENESIS\",\"safeBlockHash\":\"$GENESIS\",\"finalizedBlockHash\":\"$GENESIS\"},null],\"id\":1}" \
  "http://localhost:$RETH_AUTHRPC"
echo ""
