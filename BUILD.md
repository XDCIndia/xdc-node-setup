# GP5 Build Guide

Multi-architecture Docker builds for GP5 (Geth 1.17 fork + XDPoS).

## Quick Start

**This Dockerfile copies a pre-built binary.** Build the binary first from the go-ethereum fork:

```bash
# Build binary (on go-ethereum fork repo)
make all

# Copy binary to this repo
cp build/bin/XDC xdc-node-setup/build/XDC

# Then build image
cd xdc-node-setup
docker build -f docker/Dockerfile.gp5 \
  --platform linux/amd64 \
  --build-arg BINARY_PATH=./build/XDC \
  -t xdcindia/gp5:v$(cat VERSION)-amd64 .
```

### AMD64 (production servers)

```bash
docker build -f docker/Dockerfile.gp5 \
  --platform linux/amd64 \
  --build-arg BINARY_PATH=./build/XDC \
  -t xdcindia/gp5:v$(cat VERSION)-amd64 .
```

### ARM64 (Apple Silicon, Graviton)

```bash
docker build -f docker/Dockerfile.gp5 \
  --platform linux/arm64 \
  --build-arg BINARY_PATH=./build/XDC \
  -t xdcindia/gp5:v$(cat VERSION)-arm64 .
```

### Multi-arch manifest (push both)

**Requires separate per-arch binaries:**

```bash
# Build binaries for each arch first (on respective machines or with cross-compilation)
# Then:
docker buildx create --use --name gp5-builder || true
docker buildx build -f docker/Dockerfile.gp5 \
  --platform linux/amd64 \
  --build-arg BINARY_PATH=./build/XDC-amd64 \
  -t xdcindia/gp5:v$(cat VERSION)-amd64 \
  --push .

docker buildx build -f docker/Dockerfile.gp5 \
  --platform linux/arm64 \
  --build-arg BINARY_PATH=./build/XDC-arm64 \
  -t xdcindia/gp5:v$(cat VERSION)-arm64 \
  --push .

# Create manifest
docker manifest create xdcindia/gp5:v$(cat VERSION) \
  xdcindia/gp5:v$(cat VERSION)-amd64 \
  xdcindia/gp5:v$(cat VERSION)-arm64
docker manifest push xdcindia/gp5:v$(cat VERSION)
```

## Key Differences from Old Dockerfiles

| Aspect | Old (Alpine) | New (Ubuntu) |
|--------|-------------|--------------|
| Base image | `alpine:latest` | `ubuntu:24.04` |
| libc | musl | glibc |
| Binary compatibility | Broken for glibc-linked Go binaries | Correct |
| Image size | ~158MB | ~180MB |
| Build deps | `apk add` | `apt-get install` |

## Troubleshooting

### `exec format error`
Binary architecture doesn't match container platform. Use `--platform` flag.

### `no such file or directory`
Binary is glibc-linked but container uses musl (Alpine). Use the Ubuntu-based Dockerfile.

### Cross-compilation on Apple Silicon
```bash
# Ensure Docker Desktop has Rosetta enabled for AMD64 emulation
# Or build natively for ARM64 and push both architectures
```

## CI/CD

See `.github/workflows/docker-build.yml` for automated multi-arch builds on release.
