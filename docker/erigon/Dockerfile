FROM golang:1.22-alpine AS builder

RUN apk add --no-cache make gcc g++ musl-dev linux-headers git bash

WORKDIR /build

RUN git clone --branch feature/xdc-network https://github.com/AnilChinchawale/erigon-xdc.git . \
    && sed -i 's/set -eu/set -e/' node/silkworm/silkworm_compat_check.sh 2>/dev/null || true \
    && make erigon

FROM alpine:3.19

RUN apk add --no-cache ca-certificates libstdc++ libgcc wget

COPY --from=builder /build/build/bin/erigon /usr/local/bin/erigon

ENTRYPOINT ["erigon"]
