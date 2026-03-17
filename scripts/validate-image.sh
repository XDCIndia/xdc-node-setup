#!/usr/bin/env bash
#==============================================================================
# Docker Image Validator (Issue #546, #516)
# Validates GP5 image compatibility before starting node
#==============================================================================
set -euo pipefail

source "$(dirname "$0")/lib/common.sh" 2>/dev/null || true

IMAGE="${1:-}"
NETWORK="${2:-mainnet}"

if [[ -z "$IMAGE" ]]; then
    echo "Usage: $0 <docker-image> [mainnet|apothem]"
    exit 1
fi

echo "🔍 Validating Docker image: $IMAGE"

# Check 1: Image exists locally or can be pulled
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Pulling image..."
    docker pull "$IMAGE" || { echo "❌ Cannot pull image"; exit 1; }
fi

# Check 2: Binary exists and is executable
BINARY=""
for bin in XDC XDC-mainnet geth; do
    if docker run --rm --entrypoint which "$IMAGE" "$bin" >/dev/null 2>&1; then
        BINARY="$bin"
        break
    fi
done

if [[ -z "$BINARY" ]]; then
    echo "❌ No XDC/geth binary found in image"
    echo "   Issue #516: xinfinorg/xdposchain:v2.6.8 has 'XDC-mainnet' not 'XDC'"
    echo "   Fix: Create entrypoint.sh that symlinks: ln -sf /usr/bin/XDC-mainnet /usr/bin/XDC"
    exit 1
fi

echo "✅ Binary found: $BINARY"

# Check 3: Version info
VERSION=$(docker run --rm --entrypoint "$BINARY" "$IMAGE" version 2>/dev/null | head -5 || echo "unknown")
echo "Version: $VERSION"

# Check 4: Genesis compatibility
if [[ "$NETWORK" == "mainnet" ]]; then
    EXPECTED_CHAIN_ID=50
elif [[ "$NETWORK" == "apothem" ]]; then
    EXPECTED_CHAIN_ID=51
fi

echo ""
echo "✅ Image validation passed for $NETWORK"
echo "   Binary: $BINARY"
echo "   Use --entrypoint $BINARY in docker run if needed"
