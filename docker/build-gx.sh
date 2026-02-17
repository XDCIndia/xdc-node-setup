#!/bin/bash
# OS Agnostic build script for XDC Geth (gx)
# Works on: Linux, macOS (Intel/ARM), Windows (WSL/Git Bash)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect OS
OS=$(uname -s)
ARCH=$(uname -m)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Building XDC Geth (gx) Docker Image${NC}"
echo -e "${BLUE}OS: ${OS}, Arch: ${ARCH}${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Set platform based on architecture
case "$ARCH" in
    x86_64|amd64)
        PLATFORM="linux/amd64"
        ;;
    arm64|aarch64)
        PLATFORM="linux/arm64"
        ;;
    *)
        echo -e "${YELLOW}Warning: Unknown architecture ${ARCH}, using default${NC}"
        PLATFORM="linux/amd64"
        ;;
esac

# Check if Docker Buildx is available
if docker buildx version > /dev/null 2>&1; then
    BUILDER="docker buildx build"
    # Try to use default builder or create one
    if ! docker buildx use default > /dev/null 2>&1; then
        echo -e "${YELLOW}Creating buildx builder...${NC}"
        docker buildx create --name xdc-builder --use > /dev/null 2>&1 || true
    fi
else
    BUILDER="docker build"
fi

# Change to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BLUE}Building with platform: ${PLATFORM}${NC}"
echo ""

# Build Docker image
if [ "$BUILDER" = "docker buildx build" ]; then
    $BUILDER \
        --platform "${PLATFORM}" \
        --tag anilchinchawale/gx:stable \
        --tag anilchinchawale/gx:latest \
        -f Dockerfile.gx \
        --load \
        .
else
    docker build \
        --tag anilchinchawale/gx:stable \
        --tag anilchinchawale/gx:latest \
        -f Dockerfile.gx \
        .
fi

echo ""
echo -e "${GREEN}✅ XDC Geth built successfully!${NC}"
echo -e "${GREEN}   Tags: anilchinchawale/gx:stable, anilchinchawale/gx:latest${NC}"
echo ""
echo "To test: docker run --rm anilchinchawale/gx:stable --version"
echo "To push: docker push anilchinchawale/gx:stable"
