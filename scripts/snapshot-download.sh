#!/usr/bin/env bash
#==============================================================================
# Automated Snapshot Download with Resume (Issue #489, #473)
# Downloads and verifies XDC chain snapshots for fast sync
#==============================================================================
set -euo pipefail

SNAPSHOT_BASE_URL="${SNAPSHOT_URL:-https://download.xinfin.network/snapshots}"
NETWORK="${1:-mainnet}"
CLIENT="${2:-gp5}"
DATADIR="${3:-/mnt/data/${NETWORK}/${CLIENT}/xdcchain}"

echo "📥 XDC Snapshot Downloader"
echo "Network: $NETWORK | Client: $CLIENT"
echo "Datadir: $DATADIR"
echo ""

# Determine snapshot URL
SNAPSHOT_FILE="${NETWORK}-${CLIENT}-latest.tar.gz"
SNAPSHOT_URL="${SNAPSHOT_BASE_URL}/${SNAPSHOT_FILE}"
CHECKSUM_URL="${SNAPSHOT_URL}.sha256"

# Download location
DOWNLOAD_DIR="/tmp/xdc-snapshots"
mkdir -p "$DOWNLOAD_DIR"
DOWNLOAD_FILE="$DOWNLOAD_DIR/$SNAPSHOT_FILE"

# Check disk space
REQUIRED_GB=500  # Approximate
AVAILABLE_GB=$(df -BG "$DOWNLOAD_DIR" 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G')
if [[ "${AVAILABLE_GB:-0}" -lt "$REQUIRED_GB" ]]; then
    echo "⚠️  Warning: Only ${AVAILABLE_GB}GB free (recommended: ${REQUIRED_GB}GB)"
    read -p "Continue? [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi

# Download with resume support
echo "Downloading snapshot..."
if command -v aria2c >/dev/null 2>&1; then
    # Prefer aria2c for multi-connection download
    aria2c -x 16 -s 16 --continue=true \
        --max-tries=10 --retry-wait=30 \
        -d "$DOWNLOAD_DIR" -o "$SNAPSHOT_FILE" \
        "$SNAPSHOT_URL"
elif command -v wget >/dev/null 2>&1; then
    wget --continue --progress=bar:force \
        --tries=10 --retry-connrefused \
        -O "$DOWNLOAD_FILE" "$SNAPSHOT_URL"
else
    curl -fL --retry 10 --retry-delay 30 \
        -C - -o "$DOWNLOAD_FILE" "$SNAPSHOT_URL"
fi

# Issue #473: Verify checksum
echo ""
echo "🔍 Verifying snapshot integrity..."
EXPECTED_HASH=$(curl -sf "$CHECKSUM_URL" 2>/dev/null | awk '{print $1}')

if [[ -n "$EXPECTED_HASH" ]]; then
    ACTUAL_HASH=$(sha256sum "$DOWNLOAD_FILE" | awk '{print $1}')
    if [[ "$ACTUAL_HASH" == "$EXPECTED_HASH" ]]; then
        echo "✅ Checksum verified"
    else
        echo "❌ Checksum MISMATCH!"
        echo "  Expected: $EXPECTED_HASH"
        echo "  Got:      $ACTUAL_HASH"
        echo "  Snapshot may be corrupted. Re-download?"
        exit 1
    fi
else
    echo "⚠️  No checksum available, performing basic integrity check..."
    # Issue #473: Basic corruption detection
    if ! tar tzf "$DOWNLOAD_FILE" >/dev/null 2>&1; then
        echo "❌ Archive is corrupted (tar integrity check failed)"
        exit 1
    fi
    echo "✅ Archive integrity OK"
fi

# Extract
echo ""
echo "📦 Extracting snapshot to $DATADIR..."
mkdir -p "$DATADIR"

# Stop node if running
if docker ps --format '{{.Names}}' | grep -q "xdc-${NETWORK}-${CLIENT}"; then
    echo "Stopping node before extraction..."
    docker stop "xdc-${NETWORK}-${CLIENT}" 2>/dev/null || true
fi

tar xzf "$DOWNLOAD_FILE" -C "$DATADIR" --strip-components=1

echo ""
echo "✅ Snapshot extracted successfully"
echo "   Datadir: $DATADIR"
echo "   Start your node to begin syncing from the snapshot"

# Cleanup option
read -p "Delete downloaded snapshot to free space? [Y/n] " -n 1 -r
echo
[[ ! $REPLY =~ ^[Nn]$ ]] && rm -f "$DOWNLOAD_FILE"
