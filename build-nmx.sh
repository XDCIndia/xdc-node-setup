#!/bin/bash
# Build script for XDC Nethermind (nmx)
# Repository: https://github.com/AnilChinchawale/nethermind/tree/build/xdc-net9-stable

set -e

echo "Building XDC Nethermind (nmx) Docker image..."

# Clone if not exists
if [ ! -d "nethermind" ]; then
    git clone -b build/xdc-net9-stable https://github.com/AnilChinchawale/nethermind.git
fi

cd nethermind

# Build Docker image
docker build -t anilchinchawale/nmx:stable -t anilchinchawale/nmx:latest -f Dockerfile .

echo "✅ Built: anilchinchawale/nmx:stable"
echo "✅ Built: anilchinchawale/nmx:latest"
echo ""
echo "To push: docker push anilchinchawale/nmx:stable"
