#!/bin/bash
set -euo pipefail
# Initialize data directories for all clients
# Usage: ./scripts/data-init.sh [mainnet|apothem|all]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
NETWORK="${1:-all}"

init_client_dir() {
  local net="$1" client="$2"
  local dir="$ROOT_DIR/data/$net/$client"
  
  mkdir -p "$dir"
  
  # Generate nodekey if missing
  [ ! -f "$dir/nodekey" ] && openssl rand -hex 32 > "$dir/nodekey" && echo "  Generated nodekey"
  
  # Generate jwt.hex if missing (needed for Reth + GP5 authrpc)
  [ ! -f "$dir/jwt.hex" ] && openssl rand -hex 32 > "$dir/jwt.hex" && echo "  Generated jwt.hex"
  
  # Create static-nodes.json as FILE (not directory!)
  [ ! -f "$dir/static-nodes.json" ] && echo "[]" > "$dir/static-nodes.json" && echo "  Created static-nodes.json"
  
  # Fix permissions for Erigon (runs as uid 1000)
  if [ "$client" = "erigon" ]; then
    chown -R 1000:1000 "$dir/" 2>/dev/null || true
    echo "  Fixed Erigon permissions (1000:1000)"
  fi
  
  echo "  ✅ $net/$client initialized"
}

init_network() {
  local net="$1"
  echo "Initializing $net..."
  for client in gp5 erigon nethermind reth v268; do
    init_client_dir "$net" "$client"
  done
}

case "$NETWORK" in
  mainnet) init_network mainnet ;;
  apothem) init_network apothem ;;
  all) init_network mainnet; init_network apothem ;;
  *) echo "Usage: $0 [mainnet|apothem|all]"; exit 1 ;;
esac

echo ""
echo "✅ Data directories initialized. Run 'docker compose --env-file docker/shared/.env.mainnet -f docker/mainnet/all-clients.yml up -d' to start."
