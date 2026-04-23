# XDC Docker Images - Adaptation from Official Sources

## Overview

All XDC client Dockerfiles are adapted from their respective official implementations to ensure best practices, security, and compatibility while adding XDC Network support.

---

## 1. XDC Geth (gx) - Adapted from `ethereum/client-go`

### Official Source
- **Repository:** https://github.com/ethereum/go-ethereum
- **Dockerfile:** https://github.com/ethereum/go-ethereum/blob/master/Dockerfile
- **Official Image:** `ethereum/client-go`

### Adaptations Made

| Aspect | Official | XDC Adaptation |
|--------|----------|----------------|
| Go Version | 1.24-alpine | 1.23-alpine (XDC fork requirement) |
| Clone Source | ethereum/go-ethereum | XDCIndia/go-ethereum (xdc-network) |
| Binary Name | `geth` | `XDC` (XDC naming) |
| Health Check | Basic grep | jq for JSON parsing |
| Additional Packages | ca-certificates only | ca-certificates + curl + jq |

### Official Practices Maintained
✅ Multi-stage build (builder + runtime)
✅ `go mod download` for dependency caching
✅ `go run build/ci.go install -static` for building
✅ Alpine Linux runtime base
✅ Metadata labels (commit, version, buildnum)
✅ Non-root user execution (UID 1000)
✅ EXPOSE declarations for all ports
✅ Minimal runtime image

### Build Process
```dockerfile
# From official:
RUN go run build/ci.go install -static ./cmd/geth

# XDC adaptation:
RUN git clone -b xdc-network https://github.com/XDCIndia/go-ethereum.git .
RUN go run build/ci.go install -static ./cmd/geth
COPY --from=builder /go-ethereum/build/bin/geth /usr/local/bin/XDC
```

---

## 2. XDC Nethermind (nmx) - Adapted from `nethermind/nethermind`

### Official Source
- **Repository:** https://github.com/NethermindEth/nethermind
- **Dockerfile:** https://github.com/NethermindEth/nethermind/blob/master/Dockerfile
- **Official Image:** `nethermind/nethermind`

### Adaptations Made

| Aspect | Official | XDC Adaptation |
|--------|----------|----------------|
| .NET Version | 10.0 SDK / 10.0 ASP.NET | 9.0 SDK / 9.0 ASP.NET (XDC fork) |
| Base Image | Ubuntu Noble | Alpine (smaller footprint) |
| Clone Source | NethermindEth/nethermind | Anilchinchawale/nethermind (build/xdc-unified) |
| Runtime | Ubuntu Noble | Alpine (security + size) |
| Additional Packages | - | curl + jq |

### Official Practices Maintained
✅ Multi-stage build with SDK + runtime
✅ `dotnet restore --locked-mode`
✅ `dotnet publish --no-self-contained`
✅ Architecture detection (x64 vs arm64)
✅ Volume declarations for keystore, logs, nethermind_db
✅ Non-root user with specific UID (1000)
✅ Proper layer caching
✅ WORKDIR set correctly

### Build Process
```dockerfile
# From official:
RUN arch=$([ "$TARGETARCH" = "amd64" ] && echo "x64" || echo "$TARGETARCH") && \
  dotnet restore --locked-mode && \
  dotnet publish -c $BUILD_CONFIG -a $arch -o /publish --no-restore --no-self-contained

# XDC adaptation:
RUN git clone -b build/xdc-unified https://github.com/AnilChinchawale/nethermind.git .
RUN arch=$([ "$TARGETARCH" = "amd64" ] && echo "x64" || echo "$TARGETARCH") && \
  dotnet restore --locked-mode && \
  dotnet publish -c $BUILD_CONFIG -a $arch -o /publish --no-restore --no-self-contained
```

---

## 3. XDC Erigon (erix) - Adapted from `erigontech/erigon`

### Official Source
- **Repository:** https://github.com/erigontech/erigon
- **Dockerfile:** https://github.com/erigontech/erigon/blob/main/Dockerfile
- **Official Image:** `erigontech/erigon`

### Adaptations Made

| Aspect | Official | XDC Adaptation |
|--------|----------|----------------|
| Go Version | 1.25-trixie | 1.22-alpine (XDC fork) |
| Runtime Base | Debian 13 Slim | Alpine 3.19 (smaller) |
| Clone Source | erigontech/erigon | AnilChinchawale/erigon-xdc (feature/xdc-network) |
| Build Tool | xx + complex Makefile | xx + simplified make |
| Silkworm Support | Optional | Disabled (not in XDC fork) |
| Additional Packages | - | curl + jq |

### Official Practices Maintained
✅ Uses `tonistiigi/xx` for cross-compilation
✅ `xx-go` for architecture-specific builds
✅ `STOPSIGNAL SIGINT` for graceful shutdown
✅ Specific UID/GID (1000:1000)
✅ `VOLUME` declaration for data directory
✅ Comprehensive OCI labels
✅ Multi-architecture support (AMD64v1, AMD64v2, ARM64)
✅ Build flags for optimization (GOAMD64_VERSION)
✅ Proper user/group creation

### Build Process
```dockerfile
# From official:
COPY --from=xx / /
RUN xx-go mod download
RUN make GO=xx-go CGO_ENABLED=1 GOARCH=${TARGETARCH} ${CPU_FLAGS} ${BINARIES} GOBIN=/build

# XDC adaptation:
RUN git clone -b feature/xdc-network https://github.com/AnilChinchawale/erigon-xdc.git .
COPY --from=xx / /
RUN xx-go mod download
RUN make GO=xx-go CGO_ENABLED=1 GOARCH=${TARGETARCH} ${CPU_FLAGS} erigon GOBIN=/build
```

---

## Common Security Practices (All Images)

### From Official Images
1. **Non-root users** - All run as UID 1000
2. **Minimal base images** - Alpine Linux where possible
3. **Multi-stage builds** - Separate build and runtime
4. **Layer caching** - Dependencies downloaded before source
5. **Health checks** - Built-in container health monitoring
6. **Signal handling** - Proper graceful shutdown (especially Erigon)
7. **Volume declarations** - Sensitive data in volumes

### XDC Additions
1. **XDC fork repositories** - Custom branches with XDPoS
2. **jq tool** - Better JSON parsing for health checks
3. **curl tool** - HTTP checks in minimal images
4. **Naming** - Binary names matching XDC conventions

---

## Multi-Architecture Support

All images support cross-compilation:

| Architecture | Geth | Nethermind | Erigon |
|--------------|------|------------|--------|
| linux/amd64 (x86_64) | ✅ | ✅ | ✅ |
| linux/arm64 (aarch64) | ✅ | ✅ | ✅ |
| macOS Intel | ✅ (via Docker) | ✅ | ✅ |
| macOS Apple Silicon | ✅ (via Docker) | ✅ | ✅ |

**Build method:**
- Erigon: `tonistiigi/xx` for cross-compilation
- Nethermind: `dotnet publish -a $arch`
- Geth: `GOARCH` environment variable

---

## Image Sizes Comparison

| Image | Base | Estimated Size |
|-------|------|----------------|
| ethereum/client-go | Alpine | ~50MB |
| anilchinchawale/gx | Alpine | ~55MB (XDC additions) |
| nethermind/nethermind | Ubuntu | ~300MB |
| anilchinchawale/nmx | Alpine | ~200MB (smaller base) |
| erigontech/erigon | Debian | ~150MB |
| anilchinchawale/erix | Alpine | ~80MB (smaller base) |

---

## Verification Commands

### Check image labels
```bash
docker inspect anilchinchawale/gx:stable --format='{{json .Config.Labels}}' | jq
docker inspect anilchinchawale/nmx:stable --format='{{json .Config.Labels}}' | jq
docker inspect anilchinchawale/erix:stable --format='{{json .Config.Labels}}' | jq
```

### Check user
```bash
docker run --rm anilchinchawale/gx:stable id
docker run --rm anilchinchawale/nmx:stable id
docker run --rm anilchinchawale/erix:stable id
```

### Check architecture
```bash
docker inspect anilchinchawale/gx:stable --format='{{.Os}}/{{.Architecture}}'
```

---

## References

### Official Docker Hub Pages
- Geth: https://hub.docker.com/r/ethereum/client-go
- Nethermind: https://hub.docker.com/r/nethermind/nethermind
- Erigon: https://hub.docker.com/r/erigontech/erigon

### Official GitHub Repositories
- Geth: https://github.com/ethereum/go-ethereum
- Nethermind: https://github.com/NethermindEth/nethermind
- Erigon: https://github.com/erigontech/erigon

### XDC Fork Repositories
- Geth: https://github.com/XDCIndia/go-ethereum/tree/xdc-network
- Nethermind: https://github.com/AnilChinchawale/nethermind/tree/build/xdc-unified
- Erigon: https://github.com/AnilChinchawale/erigon-xdc/tree/feature/xdc-network

---

## License Compliance

All adaptations maintain their original licenses:
- **Geth:** GPL-3.0-only
- **Nethermind:** LGPL-3.0-only
- **Erigon:** LGPL-3.0-only

Source code attribution maintained in fork repositories.
