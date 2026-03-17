#!/usr/bin/env bash
#==============================================================================
# Node Doctor: Diagnostic & Auto-Repair (Issue #81)
#==============================================================================
set -euo pipefail

echo "🩺 XDC Node Doctor"
echo "═══════════════════════════════════════"
echo ""

SCORE=100
ISSUES=()

# Check 1: Docker running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running"
    ISSUES+=("Docker daemon not running")
    SCORE=$((SCORE - 30))
else
    echo "✅ Docker running"
fi

# Check 2: Node containers
RUNNING=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -c 'xdc' || echo "0")
TOTAL=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -c 'xdc' || echo "0")
echo "📦 Containers: $RUNNING running / $TOTAL total"
if [[ "$RUNNING" -lt "$TOTAL" ]]; then
    STOPPED=$((TOTAL - RUNNING))
    echo "⚠️  $STOPPED container(s) stopped"
    ISSUES+=("$STOPPED stopped containers")
    SCORE=$((SCORE - STOPPED * 5))
fi

# Check 3: Block sync progress
for port in 8545 8546 8547 8548; do
    BLOCK=$(curl -sf -m 3 -X POST "http://localhost:$port" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | \
        grep -o '"result":"0x[^"]*"' | cut -d'"' -f4 || echo "")
    if [[ -n "$BLOCK" ]]; then
        BLOCK_DEC=$(printf "%d" "$BLOCK" 2>/dev/null || echo "0")
        if [[ "$BLOCK_DEC" -eq 0 ]]; then
            echo "⚠️  Port $port: Block 0 (not syncing)"
            ISSUES+=("Port $port at block 0")
            SCORE=$((SCORE - 10))
        else
            echo "✅ Port $port: Block $BLOCK_DEC"
        fi
    fi
done

# Check 4: Disk space
DISK_FREE_GB=$(df -BG / 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G')
if [[ "${DISK_FREE_GB:-0}" -lt 50 ]]; then
    echo "❌ Disk critically low: ${DISK_FREE_GB}GB free"
    ISSUES+=("Disk space critical: ${DISK_FREE_GB}GB")
    SCORE=$((SCORE - 20))
elif [[ "${DISK_FREE_GB:-0}" -lt 100 ]]; then
    echo "⚠️  Disk warning: ${DISK_FREE_GB}GB free"
    ISSUES+=("Disk space low: ${DISK_FREE_GB}GB")
    SCORE=$((SCORE - 10))
else
    echo "✅ Disk: ${DISK_FREE_GB}GB free"
fi

# Check 5: Memory
MEM_USED_PCT=$(free 2>/dev/null | awk '/Mem:/{printf "%d", $3/$2*100}' || echo "0")
if [[ "${MEM_USED_PCT:-0}" -gt 90 ]]; then
    echo "⚠️  Memory high: ${MEM_USED_PCT}% used"
    ISSUES+=("Memory ${MEM_USED_PCT}%")
    SCORE=$((SCORE - 10))
else
    echo "✅ Memory: ${MEM_USED_PCT}% used"
fi

# Check 6: Peer connectivity  
for port in 8545 8546 8547 8548; do
    PEERS=$(curl -sf -m 3 -X POST "http://localhost:$port" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null | \
        grep -o '"result":"0x[^"]*"' | cut -d'"' -f4 || echo "")
    if [[ -n "$PEERS" ]]; then
        PEER_NUM=$(printf "%d" "$PEERS" 2>/dev/null || echo "0")
        if [[ "$PEER_NUM" -eq 0 ]]; then
            echo "❌ Port $port: 0 peers"
            ISSUES+=("Port $port: 0 peers")
            SCORE=$((SCORE - 15))
        fi
    fi
done

# Summary
echo ""
echo "═══════════════════════════════════════"
if [[ $SCORE -ge 80 ]]; then
    echo "🟢 Health Score: $SCORE/100 — GOOD"
elif [[ $SCORE -ge 50 ]]; then
    echo "🟡 Health Score: $SCORE/100 — DEGRADED"
else
    echo "🔴 Health Score: $SCORE/100 — CRITICAL"
fi

if [[ ${#ISSUES[@]} -gt 0 ]]; then
    echo ""
    echo "Issues found:"
    for issue in "${ISSUES[@]}"; do
        echo "  • $issue"
    done
fi
