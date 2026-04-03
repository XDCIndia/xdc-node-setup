# Skill: Docker Troubleshooting

Common Docker and container issues for XDC node operations.

## Quick Diagnostics

```bash
# List all XDC containers and their status
docker ps -a --filter "name=xdc" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check container logs (last 50 lines)
docker logs --tail=50 xdc-geth 2>&1
docker logs --tail=50 xdc-erigon 2>&1
docker logs --tail=50 xdc-nethermind 2>&1

# Container resource usage (live)
docker stats xdc-geth xdc-erigon xdc-nethermind

# Inspect container for config issues
docker inspect xdc-geth | jq '.[0].HostConfig'
```

## Common Issues

---

### Container Exits Immediately

**Symptom:** `docker ps -a` shows container status `Exited (1)` or `Exited (137)`.

```bash
# Get exit code and last logs
docker inspect xdc-geth --format='{{.State.ExitCode}} {{.State.Error}}'
docker logs xdc-geth 2>&1 | tail -20
```

**Exit code 137** = OOM killed by kernel. Increase memory limit:
```yaml
# In docker-compose.yml:
deploy:
  resources:
    limits:
      memory: 16G
```

**Exit code 1** = Application error. Check logs for error message.

**Exit code 126/127** = Command not found or not executable. Check image and entrypoint.

---

### Port Already in Use

**Symptom:** `Error starting userland proxy: listen tcp 0.0.0.0:8545: bind: address already in use`

```bash
# Find what's using the port
ss -tlnp | grep 8545
lsof -i :8545

# Kill the conflicting process (if it's another XDC client)
docker ps | grep 8545  # Find container using port
docker stop <container>

# Or remap the port in docker-compose.yml
ports:
  - "18545:8545"  # Use a different host port
```

---

### Container Keeps Restarting (Restart Loop)

**Symptom:** `docker ps` shows container is `Restarting` repeatedly.

```bash
# Check restart count and logs
docker inspect xdc-geth | jq '.[0].RestartCount'
docker logs xdc-geth 2>&1 | tail -30

# Temporarily disable restart policy to debug
docker update --restart=no xdc-geth
docker start xdc-geth
# Now it won't auto-restart — observe what happens
```

---

### Volume / Data Directory Issues

**Symptom:** Container starts but can't access chaindata, or data isn't persisting.

```bash
# Check volume mounts
docker inspect xdc-geth | jq '.[0].Mounts'

# Verify host directory exists and has correct permissions
ls -la /data/geth/
# Should be owned by the uid running in the container (usually root or specific uid)

# Fix permissions if needed
docker exec xdc-geth id  # Get uid/gid inside container
chown -R 1000:1000 /data/geth/  # Adjust uid/gid as needed

# Check disk space on volume
df -h /data/
```

**Common mistake:** Docker Compose uses a named volume but host data is in a bind mount path.

```yaml
# Bind mount (explicit path) — preferred for blockchain data:
volumes:
  - /data/geth:/data

# Named volume (Docker-managed) — harder to inspect directly:
volumes:
  - geth_data:/data
```

---

### Networking Issues Between Containers

**Symptom:** Services can't reach each other (e.g., monitoring can't scrape node metrics).

```bash
# List Docker networks
docker network ls

# Check which network a container is on
docker inspect xdc-geth | jq '.[0].NetworkSettings.Networks'

# Test connectivity between containers
docker exec xdc-prometheus ping xdc-geth
docker exec xdc-prometheus curl -s http://xdc-geth:6060/debug/metrics

# If on different networks, connect them
docker network connect xdc-network xdc-prometheus
```

**Fix:** Ensure all XDC containers are on the same Docker network in `docker-compose.yml`:

```yaml
networks:
  xdc-network:
    driver: bridge

services:
  xdc-geth:
    networks:
      - xdc-network
  xdc-prometheus:
    networks:
      - xdc-network
```

---

### Docker Daemon Issues

**Symptom:** `docker: Cannot connect to the Docker daemon`

```bash
# Check daemon status
systemctl status docker

# Restart daemon
systemctl restart docker

# Check daemon logs
journalctl -u docker -n 50

# Check disk space (Docker daemon can fail if /var/lib/docker is full)
df -h /var/lib/docker
```

---

### Image Pull Failures

```bash
# Explicit pull
docker pull ghcr.io/xindia/xdc-go:latest

# If registry auth needed
docker login ghcr.io -u <username> -p <token>

# Check if image exists locally
docker images | grep xdc

# Use local build if registry unavailable
docker build -t xdc-geth:local -f docker/mainnet/geth/Dockerfile .
```

---

### Docker Compose Issues

```bash
# Validate compose file
docker-compose -f docker/mainnet/geth/docker-compose.yml config

# Check why a service didn't start
docker-compose -f docker/mainnet/geth/docker-compose.yml logs xdc-geth

# Force recreate containers (pick up config changes)
docker-compose -f docker/mainnet/geth/docker-compose.yml up -d --force-recreate

# Pull latest images and recreate
docker-compose -f docker/mainnet/geth/docker-compose.yml pull
docker-compose -f docker/mainnet/geth/docker-compose.yml up -d
```

---

### Disk Space Cleanup

**When disk is running low:**

```bash
# See what's taking space
docker system df

# Safe cleanup (remove unused images, stopped containers, dangling volumes)
docker system prune -f

# More aggressive (also removes unused images older than 48h)
docker system prune -f --filter "until=48h"

# Remove specific old images
docker images --filter "dangling=true" -q | xargs docker rmi 2>/dev/null || true

# Clean up old container logs
find /var/lib/docker/containers -name "*.log" -size +1G -exec truncate -s 0 {} \;
```

---

### Container Running But Unresponsive

```bash
# Check if process is actually running inside
docker top xdc-geth

# Get a shell inside the container (if it has bash/sh)
docker exec -it xdc-geth bash
docker exec -it xdc-geth sh

# Check process stats inside
docker exec xdc-geth top -bn1

# Kill and restart
docker kill xdc-geth && docker start xdc-geth
```

---

## Useful Docker One-Liners

```bash
# Stop all XDC containers
docker ps -q --filter "name=xdc" | xargs docker stop

# Remove all stopped XDC containers
docker ps -aq --filter "name=xdc" --filter "status=exited" | xargs docker rm

# Follow logs from multiple containers
docker logs -f xdc-geth &
docker logs -f xdc-erigon &
wait

# Watch resource usage for all XDC containers
watch -n 2 'docker stats --no-stream --filter "name=xdc"'

# Export container logs to file
docker logs xdc-erigon 2>&1 > /tmp/erigon-$(date +%Y%m%d).log
```

## Docker Compose File Locations

```
docker/mainnet/geth/docker-compose.yml
docker/mainnet/erigon/docker-compose.yml
docker/mainnet/nethermind/docker-compose.yml
docker/apothem/*/docker-compose.yml
```
