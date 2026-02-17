#!/bin/bash
# OS Agnostic build script for XDC Nethermind (nmx)
# Works on: Linux, macOS (Intel/ARM), Windows (WSL/Git Bash)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

OS=$(uname -s)
ARCH=$(uname -m)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Building XDC Nethermind (nmx) Docker Image${NC}"
echo -e "${BLUE}OS: ${OS}, Arch: ${ARCH}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

case "$ARCH" in
    x86_64|amd64)
        PLATFORM="linux/amd64"
        ;;
    arm64|aarch64)
        PLATFORM="linux/arm64"
        ;;
    *)
        PLATFORM="linux/amd64"
        ;;
esac

if docker buildx version > /dev/null 2>&1; then
    BUILDER="docker buildx build"
    docker buildx use default > /dev/null 2>&1 || docker buildx create --name xdc-builder --use > /dev/null 2>&1 || true
else
    BUILDER="docker build"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BLUE}Building with platform: ${PLATFORM}${NC}"
echo ""

if [ "$BUILDER" = "docker buildx build" ]; then
    $BUILDER \
        --platform "${PLATFORM}" \
        --tag anilchinchawale/nmx:stable \
        --tag anilchinchawale/nmx:latest \
        -f Dockerfile.nmx \
        --load \
        .
else
    docker build \
        --tag anilchinchawale/nmx:stable \
        --tag anilchinchawale/nmx:latest \
        -f Dockerfile.nmx \
        .
fi

echo ""
echo -e "${GREEN}✅ XDC Nethermind built successfully!${NC}"
echo -e "${GREEN}   Tags: anilchinchawale/nmx:stable, anilchinchawale/nmx:latest${NC}"
echo ""
echo "To test: docker run --rm anilchinchawale/nmx:stable --version"
echo "To push: docker push anilchinchawale/nmx:stable"
