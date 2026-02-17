#!/bin/bash
# Build script for XDC Erigon (erix)
# Repository: https://github.com/AnilChinchawale/erigon-xdc/tree/feature/xdc-network

set -e

echo "Building XDC Erigon (erix) Docker image..."

# Clone if not exists
if [ ! -d "erigon-xdc" ]; then
    git clone -b feature/xdc-network https://github.com/AnilChinchawale/erigon-xdc.git
fi

cd erigon-xdc

# Build Docker image
docker build -t anilchinchawale/erix:stable -t anilchinchawale/erix:latest -f Dockerfile .

echo "✅ Built: anilchinchawale/erix:stable"
echo "✅ Built: anilchinchawale/erix:latest"
echo ""
echo "To push: docker push anilchinchawale/erix:stable"
