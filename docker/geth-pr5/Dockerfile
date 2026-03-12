FROM golang:1.24-alpine AS builder

RUN apk add --no-cache make gcc musl-dev linux-headers git

WORKDIR /build

RUN git clone -b feature/xdpos-consensus https://github.com/AnilChinchawale/go-ethereum.git . && make geth

FROM alpine:3.19

RUN apk add --no-cache ca-certificates wget bash curl jq

COPY --from=builder /build/build/bin/geth /usr/local/bin/XDC

# Create symlink for compatibility
RUN ln -s /usr/local/bin/XDC /usr/local/bin/geth

# Create non-root user
RUN addgroup -r xdc && adduser -r -g xdc xdc

# Create data directory
RUN mkdir -p /data/xdcchain && chown -R xdc:xdc /data

USER xdc

WORKDIR /data

EXPOSE 8545 8546 30303 30303/udp

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD curl -sf -X POST http://localhost:8545 -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -e '.result' > /dev/null || exit 1

ENTRYPOINT ["XDC"]
