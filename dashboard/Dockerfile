FROM node:20-alpine
WORKDIR /app

ENV NODE_ENV=production

# Install SkyNet Agent dependencies
RUN apk add --no-cache bash curl jq bc procps

# Install dependencies
COPY package*.json ./
RUN npm ci

# Copy source code
COPY . .

# Copy startup script
COPY combined-start.sh /combined-start.sh
RUN chmod +x /combined-start.sh

EXPOSE 3000

# Run in dev mode (fast startup, no build step)
CMD ["/bin/bash", "/combined-start.sh"]
