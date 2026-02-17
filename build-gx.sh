#!/bin/bash
# Build script for XDC Geth (gx)
# Repository: https://github.com/AnilChinchawale/go-ethereum/tree/feature/xdpos-consensus

set -e

echo "Building XDC Geth (gx) Docker image..."

# Clone if not exists
if [ ! -d "go-ethereum" ]; then
    git clone -b feature/xdpos-consensus https://github.com/AnilChinchawale/go-ethereum.git
fi

cd go-ethereum

# Build Docker image
docker build -t anilchinchawale/gx:stable -t anilchinchawale/gx:latest -f Dockerfile .

echo "✅ Built: anilchinchawale/gx:stable"
echo "✅ Built: anilchinchawale/gx:latest"
echo ""
echo "To push: docker push anilchinchawale/gx:stable"
