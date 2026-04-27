FROM node:20-alpine

WORKDIR /app

# Install dependencies for SkyNet agent + healthcheck
RUN apk add --no-cache bash curl wget jq bc procps python3 make g++

# Create non-root user (node user already exists in base image)
RUN mkdir -p /app /data && chown -R node:node /app /data

# Switch to non-root user
USER node

# Install all dependencies
COPY --chown=node:node package*.json ./
RUN npm ci

# Copy source code
COPY --chown=node:node . .

# Build Next.js application
RUN npm run build

# Copy startup script
COPY --chown=node:node --chmod=0755 combined-start.sh /combined-start.sh

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries-3 \
    CMD curl -sf http://localhost:3000/api/health > /dev/null || exit 1

CMD ["/bin/bash", "/combined-start.sh"]
