FROM alpine:3.20

RUN apk add --no-cache bash curl jq

COPY combined-start.sh /start.sh
RUN chmod +x /start.sh

ENTRYPOINT ["bash", "/start.sh"]
