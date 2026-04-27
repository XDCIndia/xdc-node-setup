FROM alpine:3.20

# Phase 2: Add bc for floating point math calculations (sync rate, trends)
RUN apk add --no-cache bash curl jq docker-cli bc

COPY --chmod=0755 combined-start.sh /start.sh

ENTRYPOINT ["bash", "/start.sh"]
