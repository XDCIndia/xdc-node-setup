# Docker Hub Automated Build

This directory contains instructions for setting up automated builds on Docker Hub for XDC Node images.

## Repository Setup

### 1. Create Docker Hub Repository

1. Log in to [Docker Hub](https://hub.docker.com)
2. Click "Create Repository"
3. Name: `xdc-node`
4. Visibility: Public
5. Enable "Automated Builds" (requires linked GitHub/Bitbucket account)

### 2. Link GitHub Repository

1. Go to Account Settings → Linked Accounts
2. Connect your GitHub account
3. Select repository: `AnilChinchawale/xdc-node-setup`

### 3. Configure Build Rules

Create the following build rules:

| Source Type | Source            | Docker Tag | Dockerfile Location | Build Context |
|-------------|-------------------|------------|---------------------|---------------|
| Branch      | `main`            | `latest`   | `/docker/Dockerfile`| `/docker`     |
| Branch      | `main`            | `v2.6.8`   | `/docker/Dockerfile`| `/docker`     |
| Tag         | `/^v[0-9.]+$/`    | `{{version}}` | `/docker/Dockerfile`| `/docker`     |
| Branch      | `develop`         | `develop`  | `/docker/Dockerfile`| `/docker`     |

### 4. Build Settings

- **Autobuild**: Enabled
- **Build Caching**: Enabled
- **Repository Links**: Enable to rebuild when base images update

### 5. Environment Variables (Optional)

Add any required build-time environment variables:

| Variable | Value | Description |
|----------|-------|-------------|
| `XDC_VERSION` | `v2.6.8` | Default XDC client version |
| `BUILD_DATE` | (auto) | Image build timestamp |
| `VCS_REF` | (auto) | Git commit hash |

## Dockerfile Requirements

Ensure your Dockerfile supports multi-stage builds for efficiency:

```dockerfile
# Build stage
FROM golang:1.21-alpine AS builder
WORKDIR /build
COPY . .
RUN go build -o xdc-node

# Runtime stage
FROM alpine:latest
RUN apk add --no-cache ca-certificates
COPY --from=builder /build/xdc-node /usr/local/bin/
EXPOSE 30303 8545 8546
ENTRYPOINT ["xdc-node"]
```

## Testing Builds Locally

```bash
# Build image locally
cd docker
docker build -t xdc-node:local .

# Test run
docker run -d \
  --name xdc-test \
  -p 30303:30303 \
  -p 8545:8545 \
  -v xdc-data:/xdcchain \
  xdc-node:local

# Check logs
docker logs -f xdc-test
```

## Multi-Architecture Builds

To support both AMD64 and ARM64:

```bash
# Create buildx builder
docker buildx create --name multiarch --use
docker buildx inspect --bootstrap

# Build and push multi-arch image
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t xdcnetwork/xdc-node:latest \
  --push .
```

## Image Labels

Include these labels in your Dockerfile for better traceability:

```dockerfile
LABEL org.opencontainers.image.title="XDC Node"
LABEL org.opencontainers.image.description="XDC Network blockchain node"
LABEL org.opencontainers.image.source="https://github.com/AnilChinchawale/xdc-node-setup"
LABEL org.opencontainers.image.licenses="MIT"
```

## Post-Push Webhooks

Configure webhooks to trigger deployments:

1. Go to Repository → Webhooks
2. Add webhook URL for your deployment pipeline
3. Choose events: Push, Build

Example webhook payload:
```json
{
  "callback_url": "https://registry.hub.docker.com/u/xdcnetwork/xdc-node/hook/...",
  "push_data": {
    "tag": "v2.6.8",
    "pushed_at": "2024-01-15T10:30:00Z"
  },
  "repository": {
    "name": "xdc-node",
    "namespace": "xdcnetwork"
  }
}
```

## Monitoring Builds

- View build history in Docker Hub UI
- Check build logs for errors
- Set up notifications for failed builds

## Security Scanning

Enable Docker Hub Security Scanning:

1. Repository → Settings
2. Enable "Scan results on push"
3. Review CVE reports after each build

## Related Documentation

- [Docker Hub Automated Builds](https://docs.docker.com/docker-hub/builds/)
- [BuildKit](https://docs.docker.com/build/buildkit/)
- [Multi-platform builds](https://docs.docker.com/build/building/multi-platform/)
