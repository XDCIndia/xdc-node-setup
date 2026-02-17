#==============================================================================
# XDC Nethermind Client Dockerfile
# Builds Nethermind with XDC eth/100 protocol support
# Based on .NET 9.0 runtime
#==============================================================================

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS builder

# Build arguments
ARG NETHERMIND_BRANCH=build/xdc-net9-stable
ARG NETHERMIND_REPO=https://github.com/AnilChinchawale/nethermind.git

# Install build dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Clone and build Nethermind
WORKDIR /build
RUN git clone --depth 1 --branch ${NETHERMIND_BRANCH} ${NETHERMIND_REPO} nethermind-src

WORKDIR /build/nethermind-src

# Restore and build
RUN dotnet restore src/Nethermind/Nethermind.Runner/Nethermind.Runner.csproj
RUN dotnet publish src/Nethermind/Nethermind.Runner/Nethermind.Runner.csproj \
    -c Release \
    -o /nethermind \
    --self-contained false \
    -p:PublishSingleFile=false

# Runtime image
FROM mcr.microsoft.com/dotnet/aspnet:9.0

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    jq \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Create nethermind user
RUN groupadd -r nethermind && useradd -r -g nethermind nethermind

# Copy built binaries from builder
COPY --from=builder /nethermind /nethermind

# Copy default XDC chainspec and runner config (can be overridden by volume mounts)
COPY xdc-chainspec.json /nethermind/chainspec/xdc.json
COPY xdc-runner.json /nethermind/configs/xdc.json

# Create data directory
RUN mkdir -p /nethermind/data /nethermind/configs /nethermind/chainspec /nethermind/logs \
    && chown -R nethermind:nethermind /nethermind

WORKDIR /nethermind

# Expose ports
# 8545 - JSON-RPC
# 30303 - P2P
EXPOSE 8545 30303 30303/udp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -sf http://localhost:8545 -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' || exit 1

# Switch to non-root user
USER nethermind

# Default entrypoint
ENTRYPOINT ["/bin/bash", "/start.sh"]
