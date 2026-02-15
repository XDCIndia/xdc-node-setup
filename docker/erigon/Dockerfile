## XDC Erigon Dockerfile
## Based on official Erigon Dockerfile with XDC-specific modifications
##
## Build:
##   docker build -t xdc-erigon .
##
## Build with Silkworm (x86_64 only):
##   docker build --build-arg BUILD_SILKWORM=true -t xdc-erigon .

ARG BUILDER_IMAGE="golang:1.24-bookworm"
ARG TARGET_BASE_IMAGE="debian:12-slim"
ARG UID_ERIGON=1000
ARG GID_ERIGON=1000
ARG BUILD_SILKWORM="false"
ARG EXPOSED_PORTS="8545 8551 8546 30303 30303/udp 30304 30304/udp 30311 30311/udp 42069 42069/udp 8080 9090 6060"

## Use xx - Dockerfile cross-compilation helpers
FROM --platform=$BUILDPLATFORM tonistiigi/xx AS xx

### Builder section
FROM --platform=$BUILDPLATFORM ${BUILDER_IMAGE} AS builder
ARG TARGETARCH
ARG TARGETVARIANT
ARG TARGETPLATFORM
ARG BUILD_SILKWORM

SHELL ["/bin/bash", "-c"]

WORKDIR /erigon

## Copy cross-compilation helpers
COPY --from=xx / /

## Clone XDC erigon fork
RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    git clone --branch feature/xdc-network --depth 1 https://github.com/AnilChinchawale/erigon-xdc.git . && \
    rm -rf .git

## Install dependencies
RUN xx-apt-get install -y libc6-dev g++ && \
    xx-go mod download && \
    xx-go mod tidy

## Fix silkworm compatibility check script (XDC-specific)
RUN sed -i 's/set -eu/set -e/' node/silkworm/silkworm_compat_check.sh 2>/dev/null || true

## Build erigon binary with proper flags
RUN echo "Building XDC Erigon on ${TARGETARCH}${TARGETVARIANT}" && \
    if [ "x${TARGETARCH}" == "xamd64" ] && [ "x${TARGETVARIANT}" == "x" ]; then \
        echo "Architecture: AMD64v1"; \
        export CPU_FLAGS="GOAMD64_VERSION=v1 GOARCH=amd64"; \
    elif [ "x${TARGETARCH}" == "xamd64" ] && [ "x${TARGETVARIANT}" == "xv2" ]; then \
        echo "Architecture: AMD64v2"; \
        export CPU_FLAGS="GOAMD64_VERSION=v2 GOARCH=amd64"; \
    elif [ "x${TARGETARCH}" == "xarm64" ]; then \
        echo "Architecture: ARM64"; \
        export CPU_FLAGS="GOARCH=arm64"; \
    fi && \
    if [ "x${BUILD_SILKWORM}" != "xtrue" ] || [ "x${TARGETARCH}" == "xarm64" ]; then \
        echo "Disabling Silkworm (not supported or ARM64)"; \
        export FLAG_SILKWORM=",nosilkworm"; \
    fi && \
    make GO=xx-go CGO_ENABLED=1 GOARCH=${TARGETARCH} ${CPU_FLAGS} erigon GOBIN=/build BUILD_TAGS=nosqlite,noboltdb${FLAG_SILKWORM} && \
    if [ "x${BUILD_SILKWORM}" == "xtrue" ] && [ "x${TARGETARCH}" == "xamd64" ]; then \
        echo "Installing libsilkworm_capi.so library"; \
        find $(go env GOMODCACHE)/github.com/erigontech -name libsilkworm_capi.so -exec install {} /build \; ;\
    fi && \
    ls -lh /build/erigon

### Runtime section
FROM ${TARGET_BASE_IMAGE} AS erigon
ARG USER=erigon
ARG GROUP=erigon
ARG UID_ERIGON
ARG GID_ERIGON
ARG BUILD_SILKWORM
ARG TARGETARCH
ARG EXPOSED_PORTS
ARG BUILD_DATE="Not defined"
ARG VCS_REF="Not defined"

LABEL \
    org.opencontainers.image.authors="XDC Network & Erigon contributors" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.revision="${VCS_REF}" \
    org.opencontainers.image.description="XDC Network implementation on Erigon - high-performance Ethereum client" \
    org.opencontainers.image.source="https://github.com/AnilChinchawale/erigon-xdc" \
    org.opencontainers.image.url="https://github.com/AnilChinchawale/xdc-node-setup"

STOPSIGNAL SIGTERM

SHELL ["/bin/bash", "-c"]

## Install runtime dependencies and setup user
RUN --mount=type=bind,from=builder,source=/build,target=/tmp/build \
    echo "Installing on ${TARGETARCH}" && \
    groupadd --gid ${GID_ERIGON} ${GROUP} && \
    useradd --system --uid ${UID_ERIGON} -g ${GROUP} --home /home/${USER} --shell /bin/bash ${USER} && \
    apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates libstdc++6 libc6 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    if [ "x${TARGETARCH}" == "xamd64" ] && [ "x${BUILD_SILKWORM}" != "xfalse" ]; then \
        echo "Installing libsilkworm_capi.so library"; \
        find /tmp/build -name libsilkworm_capi.so -type f | xargs -I % install -m a=r -v % /lib/x86_64-linux-gnu/; \
    fi && \
    install -d -o ${USER} -g ${GROUP} /home/${USER}/.local /home/${USER}/.local/share /home/${USER}/.local/share/erigon && \
    install -d -o ${USER} -g ${GROUP} /work/xdcchain && \
    echo "Installing erigon binary:" && \
    install -v -o root -g root /tmp/build/erigon /usr/local/bin/ && \
    ls -lh /usr/local/bin/erigon

VOLUME ["/work/xdcchain"]
WORKDIR /work/xdcchain

USER ${USER}

EXPOSE ${EXPOSED_PORTS}

ENTRYPOINT ["/usr/local/bin/erigon"]
