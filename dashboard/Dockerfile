FROM node:20-alpine

WORKDIR /app

# Install SkyNet Agent dependencies
RUN apk add --no-cache bash curl jq bc procps

# Install ALL dependencies (including devDeps for build)
COPY package*.json ./
RUN npm ci --production=false

# Copy source code
COPY . .

# Build for production
RUN npm run build

# Copy startup script
COPY combined-start.sh /combined-start.sh
RUN chmod +x /combined-start.sh

# Runtime env vars via server-side API routes (not baked at build time)
# DO NOT add env: {} to next.config.mjs

EXPOSE 3000

CMD ["/bin/bash", "/combined-start.sh"]
