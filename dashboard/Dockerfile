FROM node:20-alpine
WORKDIR /app

# Install SkyNet Agent dependencies
RUN apk add --no-cache bash curl jq bc procps

# Install ALL dependencies (including devDeps for tailwind/postcss)
COPY package*.json ./
RUN npm ci --include=dev

# Copy source code
COPY . .

# Copy startup script
COPY combined-start.sh /combined-start.sh
RUN chmod +x /combined-start.sh

EXPOSE 3000

CMD ["/bin/bash", "/combined-start.sh"]
