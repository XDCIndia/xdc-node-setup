#!/usr/bin/env bash
#==============================================================================
# Automated Backup & Recovery (Issue #341)
#==============================================================================
set -euo pipefail

NETWORK="${1:-mainnet}"
CLIENT="${2:-gp5}"
BACKUP_DIR="${3:-/mnt/backup/xdc}"
DATADIR="/mnt/data/${NETWORK}/${CLIENT}/xdcchain"
CONTAINER="xdc-${NETWORK}-${CLIENT}"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="${NETWORK}-${CLIENT}-${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

echo "💾 XDC Node Backup"
echo "Source: $DATADIR"
echo "Backup: $BACKUP_PATH"

mkdir -p "$BACKUP_DIR"

# Option 1: Hot backup (node running)
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "📸 Hot backup (node running)..."
    
    # Get current block for reference
    BLOCK=$(curl -sf -m 5 -X POST "http://localhost:8545" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null | \
        grep -o '"result":"0x[^"]*"' | cut -d'"' -f4 || echo "0x0")
    echo "Block at backup: $(printf "%d" "$BLOCK" 2>/dev/null)"
    
    # Use rsync for incremental backup
    rsync -a --delete --info=progress2 "$DATADIR/" "$BACKUP_PATH/"
else
    # Cold backup (node stopped)
    echo "📦 Cold backup (node stopped)..."
    cp -a "$DATADIR" "$BACKUP_PATH"
fi

# Save metadata
cat > "${BACKUP_PATH}/backup-meta.json" << META
{
    "network": "$NETWORK",
    "client": "$CLIENT",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "block": "$(printf "%d" "${BLOCK:-0x0}" 2>/dev/null)",
    "source": "$DATADIR",
    "size": "$(du -sh "$BACKUP_PATH" | awk '{print $1}')"
}
META

echo "✅ Backup complete: $BACKUP_PATH"
echo "   Size: $(du -sh "$BACKUP_PATH" | awk '{print $1}')"

# Rotate old backups (keep last 3)
ls -dt "${BACKUP_DIR}/${NETWORK}-${CLIENT}-"* 2>/dev/null | tail -n +4 | while read -r old; do
    echo "🗑  Removing old backup: $(basename "$old")"
    rm -rf "$old"
done
