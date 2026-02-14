# Build stage
FROM node:20-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache python3 make g++

# Install ALL dependencies (including devDeps for build)
COPY package*.json ./
RUN npm ci --production=false

# Copy source code
COPY . .

# Build for production
ENV NODE_ENV=production
RUN npm run build

# Production stage
FROM node:20-alpine

WORKDIR /app

# Install SkyNet Agent dependencies
RUN apk add --no-cache bash curl jq bc procps

# Install production dependencies only
COPY package*.json ./
RUN npm ci --production=true

# Copy built application from builder stage
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public

# Copy startup script
COPY combined-start.sh /combined-start.sh
RUN chmod +x /combined-start.sh

# Set production environment
ENV NODE_ENV=production

# Runtime env vars via server-side API routes (not baked at build time)
# DO NOT add env: {} to next.config.mjs

EXPOSE 3000

CMD ["/bin/bash", "/combined-start.sh"]
