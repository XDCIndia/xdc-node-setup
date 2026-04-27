#==============================================================================
# XDC Reth Client Dockerfile
# Builds Reth with XDC protocol support
# Based on Ubuntu 24.04 (Reth needs glibc)
#==============================================================================

FROM ubuntu:24.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    jq \
    procps \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create reth user
RUN groupadd -r reth && useradd -r -g reth reth

# Create directory structure
RUN mkdir -p /reth/bin /work/xdcchain /reth/logs \
    && chown -R reth:reth /reth /work

# Copy the pre-built xdc-reth binary
# Build the binary first with:
#   cd /path/to/reth-xdc && cargo build --release --bin xdc-reth
#   cp target/release/xdc-reth docker/reth/xdc-reth
# Or use the pre-built Docker Hub image directly:
#   anilchinchawale/rethx:apothem-latest (Apothem testnet)
#   anilchinchawale/rethx:latest         (Mainnet)
COPY --chmod=755 xdc-reth /reth/bin/xdc-reth

WORKDIR /reth

# Expose ports
# 7073 - HTTP RPC
# 40303 - P2P
# 40304 - Discovery UDP
EXPOSE 7073 40303 40303/udp 40304/udp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -sf http://localhost:7073 -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' || exit 1

# Switch to non-root user
USER reth

# Default entrypoint
ENTRYPOINT ["/bin/bash", "/start.sh"]
