FROM golang:1.24-alpine AS builder

RUN apk add --no-cache make gcc musl-dev linux-headers git

WORKDIR /build

RUN git clone -b feature/xdpos-consensus https://github.com/AnilChinchawale/go-ethereum.git . && make geth

FROM alpine:3.19

RUN apk add --no-cache ca-certificates wget bash curl

COPY --from=builder /build/build/bin/geth /usr/local/bin/XDC

# Create symlink for compatibility
RUN ln -s /usr/local/bin/XDC /usr/local/bin/geth

ENTRYPOINT ["XDC"]
