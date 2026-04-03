#!/bin/bash
set -euo pipefail
# xdc doctor v2 — comprehensive node health check with auto-fix
# Issue: https://github.com/XDCIndia/xdc-node-setup/issues/100
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
FIX=${1:-""}; PASSED=0; WARNED=0; FAILED=0

pass() { echo "  ✅ $1"; ((PASSED++)); }
warn() { echo "  ⚠️  $1"; ((WARNED++)); }
fail() { echo "  ❌ $1"; ((FAILED++)); }

echo "🏥 XDC Node Doctor v2"
echo "====================="

# 1. Port conflicts
echo ""; echo "📡 Port Checks:"
source "$ROOT_DIR/configs/ports.env" 2>/dev/null || true
for port in 8545 8547 8548 8558 8550; do
  count=$(ss -tlnp "sport = :$port" 2>/dev/null | grep -c LISTEN || echo 0)
  [ "$count" -le 1 ] && pass "Port $port: OK" || fail "Port $port: $count listeners (conflict!)"
done

# 2. Volume checks
echo ""; echo "💾 Volume Checks:"
for client in gp5 erigon nethermind reth v268; do
  dir="$ROOT_DIR/data/mainnet/$client"
  if [ -d "$dir" ]; then
    [ -f "$dir/static-nodes.json" ] && pass "$client: static-nodes.json is file" || { fail "$client: static-nodes.json missing or is directory"; [ "$FIX" = "--fix" ] && echo '[]' > "$dir/static-nodes.json" && echo "    → Fixed"; }
    [ "$client" = "erigon" ] && { owner=$(stat -c '%u' "$dir" 2>/dev/null); [ "$owner" = "1000" ] && pass "erigon: uid 1000 OK" || { fail "erigon: uid=$owner (need 1000)"; [ "$FIX" = "--fix" ] && chown -R 1000:1000 "$dir" && echo "    → Fixed"; }; }
  else
    warn "$client: data dir missing ($dir)"
    [ "$FIX" = "--fix" ] && mkdir -p "$dir" && echo "    → Created"
  fi
done

# 3. Docker checks
echo ""; echo "🐳 Docker Checks:"
docker info >/dev/null 2>&1 && pass "Docker daemon running" || fail "Docker daemon not running"
for name in gp5-mainnet erigon-mainnet reth-mainnet nm-mainnet v268-mainnet-ref; do
  status=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo "missing")
  case "$status" in
    running) pass "$name: running" ;;
    exited|dead) fail "$name: $status"; [ "$FIX" = "--fix" ] && docker start "$name" 2>/dev/null && echo "    → Restarted" ;;
    *) warn "$name: not deployed" ;;
  esac
done

# 4. Sync checks
echo ""; echo "📊 Sync Checks:"
for port in 8545 8547 8548 8558 8550; do
  name="?"; case $port in 8545) name="GP5" ;; 8547) name="Erigon" ;; 8548) name="Reth" ;; 8558) name="NM" ;; 8550) name="v268" ;; esac
  block=$(curl -s -m 2 -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://localhost:$port 2>/dev/null | jq -r '.result // "0x0"' 2>/dev/null)
  blockDec=$((16#${block#0x} )) 2>/dev/null || blockDec=0
  peers=$(curl -s -m 2 -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' http://localhost:$port 2>/dev/null | jq -r '.result // "0x0"' 2>/dev/null)
  peerDec=$((16#${peers#0x} )) 2>/dev/null || peerDec=0
  [ "$blockDec" -gt 0 ] && pass "$name: block $blockDec, $peerDec peers" || warn "$name: not responding"
done

# 5. Disk
echo ""; echo "💿 Disk Check:"
usage=$(df "$ROOT_DIR" 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
[ "${usage:-0}" -lt 80 ] && pass "Disk: ${usage}% used" || { [ "${usage:-0}" -lt 95 ] && warn "Disk: ${usage}% used" || fail "Disk: ${usage}% CRITICAL"; }

echo ""; echo "═══════════════════════"
echo "Results: $PASSED passed, $WARNED warnings, $FAILED failed"
[ "$FAILED" -gt 0 ] && echo "Run with --fix to auto-remediate" && exit 1
[ "$WARNED" -gt 0 ] && exit 0
echo "🎉 All checks passed!" && exit 0
