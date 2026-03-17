#!/usr/bin/env bash
#==============================================================================
# Memory Profiling for Multi-Client Setup (Issue #482)
#==============================================================================
set -euo pipefail

echo "🧠 XDC Node Memory Profile"
echo ""

# System memory
TOTAL_MEM=$(free -h 2>/dev/null | awk '/Mem:/{print $2}' || sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0fG", $1/1024/1024/1024}')
echo "System Memory: $TOTAL_MEM"
echo ""

# Per-container memory usage
echo "Container Memory Usage:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.PIDs}}" 2>/dev/null | \
    grep -E "xdc|gp5|erigon|nm|reth|skyone" || echo "No XDC containers found"

echo ""
echo "Memory Recommendations:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• GP5 (Geth):      4-8 GB  (--cache 4096)"
echo "• Erigon:           8-16 GB (state-heavy)"
echo "• Nethermind:       8-16 GB (--Memory.Max 8000)"
echo "• Reth:             4-8 GB  (efficient)"
echo "• SkyOne Agent:     256 MB  (Next.js dashboard)"
echo ""

# Check for memory pressure
SWAP_USED=$(free -b 2>/dev/null | awk '/Swap:/{print $3}' || echo "0")
if [[ "${SWAP_USED:-0}" -gt 1073741824 ]]; then
    echo "⚠️  WARNING: ${SWAP_USED} bytes of swap used — consider adding RAM"
fi

# Check for OOM kills
if [[ -f /var/log/kern.log ]]; then
    OOM_COUNT=$(grep -c "Out of memory" /var/log/kern.log 2>/dev/null || echo "0")
    if [[ "$OOM_COUNT" -gt 0 ]]; then
        echo "❌ WARNING: $OOM_COUNT OOM kills detected!"
        grep "Out of memory" /var/log/kern.log 2>/dev/null | tail -3
    fi
fi
