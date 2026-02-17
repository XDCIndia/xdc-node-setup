#!/bin/bash
# Master build script for all XDC clients - OS Agnostic
# Works on: Linux, macOS (Intel/ARM), Windows (WSL/Git Bash)

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

OS=$(uname -s)
ARCH=$(uname -m)

echo "=========================================="
echo "Building XDC Client Docker Images"
echo "=========================================="
echo "OS: ${OS}, Architecture: ${ARCH}"
echo ""

# Change to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Function to build with error handling
build_image() {
    local name=$1
    local script=$2
    
    echo -e "${BLUE}Building ${name}...${NC}"
    if bash "$script"; then
        echo -e "${GREEN}✅ ${name} built successfully${NC}"
    else
        echo -e "${YELLOW}⚠️ ${name} build failed${NC}"
        return 1
    fi
    echo ""
}

# Build Geth (gx)
echo -e "${BLUE}1/3: Building XDC Geth (gx)${NC}"
build_image "XDC Geth" "build-gx.sh"

# Build Nethermind (nmx)
echo -e "${BLUE}2/3: Building XDC Nethermind (nmx)${NC}"
build_image "XDC Nethermind" "build-nmx.sh"

# Build Erigon (erix)
echo -e "${BLUE}3/3: Building XDC Erigon (erix)${NC}"
build_image "XDC Erigon" "build-erix.sh"

echo "=========================================="
echo -e "${GREEN}Build process completed!${NC}"
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
echo "To run multi-client setup:"
echo "  docker-compose -f docker-compose.xdc-clients.yml up -d"
