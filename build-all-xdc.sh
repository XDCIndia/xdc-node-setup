#!/bin/bash
# Master build script for all XDC clients on Mac
# Usage: ./build-all-xdc.sh

set -e

echo "=========================================="
echo "Building XDC Client Docker Images"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to build image
build_image() {
    local name=$1
    local dockerfile=$2
    local tag=$3
    
    echo -e "${BLUE}Building ${name}...${NC}"
    docker build -f ${dockerfile} -t ${tag}:stable -t ${tag}:latest .
    echo -e "${GREEN}✅ ${name} built successfully${NC}"
    echo "   Tags: ${tag}:stable, ${tag}:latest"
    echo ""
}

# Build Geth (gx)
echo -e "${BLUE}1/3: Building XDC Geth (gx)${NC}"
build_image "XDC Geth" "Dockerfile.gx" "anilchinchawale/gx"

# Build Nethermind (nmx)
echo -e "${BLUE}2/3: Building XDC Nethermind (nmx)${NC}"
build_image "XDC Nethermind" "Dockerfile.nmx" "anilchinchawale/nmx"

# Build Erigon (erix)
echo -e "${BLUE}3/3: Building XDC Erigon (erix)${NC}"
build_image "XDC Erigon" "Dockerfile.erix" "anilchinchawale/erix"

echo "=========================================="
echo -e "${GREEN}All images built successfully!${NC}"
echo "=========================================="
echo ""
echo "Built images:"
echo "  • anilchinchawale/gx:stable (XDC Geth)"
echo "  • anilchinchawale/nmx:stable (XDC Nethermind)"
echo "  • anilchinchawale/erix:stable (XDC Erigon)"
echo ""
echo "To push to registry:"
echo "  docker push anilchinchawale/gx:stable"
echo "  docker push anilchinchawale/nmx:stable"
echo "  docker push anilchinchawale/erix:stable"
echo ""
echo "To test locally:"
echo "  docker run --rm anilchinchawale/gx:stable --version"
echo "  docker run --rm anilchinchawale/nmx:stable --version"
echo "  docker run --rm anilchinchawale/erix:stable --version"
