#!/bin/bash
set -euo pipefail
# A/B Testing Framework — run two configs simultaneously, compare metrics
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/119
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ACTION="${1:-help}"
CLIENT="${2:-gp5}"
DURATION="${3:-300}"  # 5 min default

get_block() {
  curl -s -m 2 -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "http://localhost:$1" 2>/dev/null | \
    jq -r '.result // "0x0"' | xargs printf '%d' 2>/dev/null || echo 0
}

case "$ACTION" in
  start)
    echo "🧪 Starting A/B test for $CLIENT"
    echo "  A = production (current config)"
    echo "  B = canary (port +1000)"
    
    # Get production port
    case "$CLIENT" in
      gp5) PROD_PORT=8545; CANARY_PORT=9545 ;;
      erigon) PROD_PORT=8547; CANARY_PORT=9547 ;;
      reth) PROD_PORT=8548; CANARY_PORT=9548 ;;
      nm) PROD_PORT=8558; CANARY_PORT=9558 ;;
      *) echo "Unknown client: $CLIENT"; exit 1 ;;
    esac
    
    echo "  Production: port $PROD_PORT"
    echo "  Canary: port $CANARY_PORT"
    echo "  Duration: ${DURATION}s"
    echo ""
    
    # Sample start
    A_START=$(get_block $PROD_PORT)
    B_START=$(get_block $CANARY_PORT)
    
    [ "$B_START" -eq 0 ] && echo "❌ Canary not running on port $CANARY_PORT. Deploy with: scripts/canary.sh deploy $CLIENT <image>" && exit 1
    
    echo "Sampling for ${DURATION}s..."
    sleep "$DURATION"
    
    A_END=$(get_block $PROD_PORT)
    B_END=$(get_block $CANARY_PORT)
    
    A_BLOCKS=$((A_END - A_START))
    B_BLOCKS=$((B_END - B_START))
    A_BPS=$(echo "scale=2; $A_BLOCKS / $DURATION" | bc)
    B_BPS=$(echo "scale=2; $B_BLOCKS / $DURATION" | bc)
    
    echo ""
    echo "📊 A/B Test Results:"
    printf "  %-12s │ %10s │ %8s\n" "Variant" "Blocks" "Blk/sec"
    echo "  ─────────────┼────────────┼─────────"
    printf "  %-12s │ %10d │ %8s\n" "A (prod)" "$A_BLOCKS" "$A_BPS"
    printf "  %-12s │ %10d │ %8s\n" "B (canary)" "$B_BLOCKS" "$B_BPS"
    echo ""
    
    if [ "$B_BLOCKS" -gt "$A_BLOCKS" ]; then
      DELTA=$(echo "scale=1; ($B_BLOCKS - $A_BLOCKS) * 100 / ($A_BLOCKS + 1)" | bc)
      echo "🏆 Winner: B (canary) — ${DELTA}% faster"
      echo "  Promote with: scripts/canary.sh promote $CLIENT"
    elif [ "$A_BLOCKS" -gt "$B_BLOCKS" ]; then
      DELTA=$(echo "scale=1; ($A_BLOCKS - $B_BLOCKS) * 100 / ($B_BLOCKS + 1)" | bc)
      echo "🏆 Winner: A (production) — ${DELTA}% faster"
      echo "  Rollback canary: scripts/canary.sh rollback $CLIENT"
    else
      echo "🤝 Tie — no significant difference"
    fi
    
    # Save result
    mkdir -p "$ROOT_DIR/data/ab-tests"
    echo "{\"timestamp\":\"$(date -Iseconds)\",\"client\":\"$CLIENT\",\"duration\":$DURATION,\"a\":{\"blocks\":$A_BLOCKS,\"bps\":$A_BPS},\"b\":{\"blocks\":$B_BLOCKS,\"bps\":$B_BPS}}" > "$ROOT_DIR/data/ab-tests/$(date +%Y%m%d_%H%M%S).json"
    ;;
  *)
    echo "Usage: $0 {start} <client> [duration_seconds]"
    echo "  $0 start gp5 300    # 5-min A/B test on GP5"
    echo ""
    echo "Prerequisites:"
    echo "  1. Production running on standard port"
    echo "  2. Canary running on port+1000 (via scripts/canary.sh deploy)"
    ;;
esac
