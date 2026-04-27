#!/bin/bash
#===============================================================================
# XNS Docker Run → Compose Migration Helper
# Migrates a node deployed with direct `docker run` to XNS docker-compose
#===============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

die() { echo -e "${RED}ERROR: $1${NC}" >&2; exit 1; }
info() { echo -e "${GREEN}INFO: $1${NC}"; }
warn() { echo -e "${YELLOW}WARN: $1${NC}"; }

# Parse arguments
CONTAINER_NAME="${1:-}"
TARGET_DIR="${2:-}"
COMPOSE_TEMPLATE="${3:-docker/apothem/gp5-pbss.yml}"

if [ -z "$CONTAINER_NAME" ] || [ -z "$TARGET_DIR" ]; then
    cat << 'USAGE'
Usage: migrate-to-compose.sh <container_name> <target_dir> [compose_template]

Example:
  ./migrate-to-compose.sh gp5-v103-apothem-125 /data/apothem/gp5-pbss-125
  ./migrate-to-compose.sh gp5-v103-apothem-125 /data/apothem/gp5-pbss-125 docker/mainnet/gp5-pbss.yml

This script:
  1. Inspects the running docker run container
  2. Extracts configuration (image, env vars, volumes, ports)
  3. Generates an XNS-compatible docker-compose.yml
  4. Creates .env file with extracted settings
  5. Provides migration commands (stop old, start new)
USAGE
    exit 1
fi

[ -d "$TARGET_DIR" ] || mkdir -p "$TARGET_DIR"
[ -f "$COMPOSE_TEMPLATE" ] || die "Compose template not found: $COMPOSE_TEMPLATE"

# Check if container exists
if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    die "Container '$CONTAINER_NAME' not found"
fi

info "Inspecting container: $CONTAINER_NAME"

# Extract container configuration (use printf for proper newlines)
IMAGE=$(docker inspect "$CONTAINER_NAME" --format '{{.Config.Image}}')
ENV_VARS=$(docker inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{printf "%s\n" .}}{{end}}')
PORTS=$(docker inspect "$CONTAINER_NAME" --format '{{range $p, $conf := .NetworkSettings.Ports}}{{if $conf}}{{range $conf}}{{printf "%s -> %s:%s\n" $p .HostIp .HostPort}}{{end}}{{end}}{{end}}')
VOLUMES=$(docker inspect "$CONTAINER_NAME" --format '{{range .Mounts}}{{printf "%s -> %s (%s)\n" .Source .Destination .Type}}{{end}}')
CMD=$(docker inspect "$CONTAINER_NAME" --format '{{join .Config.Cmd " "}}')
ENTRYPOINT=$(docker inspect "$CONTAINER_NAME" --format '{{join .Config.Entrypoint " "}}')
NETWORK_MODE=$(docker inspect "$CONTAINER_NAME" --format '{{.HostConfig.NetworkMode}}')
RESTART_POLICY=$(docker inspect "$CONTAINER_NAME" --format '{{.HostConfig.RestartPolicy.Name}}')

echo ""
echo "=== Container Configuration ==="
echo "Image: $IMAGE"
echo "Network: $NETWORK_MODE"
echo "Restart: $RESTART_POLICY"
echo ""
echo "=== Environment Variables ==="
echo "$ENV_VARS"
echo ""
echo "=== Port Mappings ==="
echo "$PORTS"
echo ""
echo "=== Volumes ==="
echo "$VOLUMES"
echo ""

# Helper: extract env var safely
get_env() {
    echo "$ENV_VARS" | grep "^${1}=" | cut -d= -f2- || true
}

# Parse key env vars
NETWORK_ID=$(get_env 'NETWORK_ID')
[ -z "$NETWORK_ID" ] && NETWORK_ID="51"

HTTP_PORT=$(get_env 'HTTP_PORT')
[ -z "$HTTP_PORT" ] && HTTP_PORT="9645"

P2P_PORT=$(get_env 'P2P_PORT')
[ -z "$P2P_PORT" ] && P2P_PORT="30322"

INSTANCE_NAME=$(get_env 'INSTANCE_NAME')
[ -z "$INSTANCE_NAME" ] && INSTANCE_NAME="$CONTAINER_NAME"

STATS_SERVER=$(get_env 'STATS_SERVER')
[ -z "$STATS_SERVER" ] && STATS_SERVER="stats.xdcindia.com:443"

STATS_SECRET=$(get_env 'STATS_SECRET')
[ -z "$STATS_SECRET" ] && STATS_SECRET="xdc_openscan_stats_2026"

WS_PORT=$(get_env 'WS_PORT')
[ -z "$WS_PORT" ] && WS_PORT="$((HTTP_PORT + 1))"

AUTHRPC_PORT=$(get_env 'AUTHRPC_PORT')
[ -z "$AUTHRPC_PORT" ] && AUTHRPC_PORT="$((HTTP_PORT + 100))"

# Determine network (51=apothem, 50=mainnet)
if [ "$NETWORK_ID" = "51" ]; then
    NETWORK="apothem"
else
    NETWORK="mainnet"
fi

# Generate .env file
info "Generating $TARGET_DIR/.env"
cat > "$TARGET_DIR/.env" << EOF
# XNS Node Configuration — Migrated from docker run
# Container: $CONTAINER_NAME
# Image: $IMAGE
# Migrated: $(date -Iseconds)

# Network
NETWORK=$NETWORK
NETWORK_ID=$NETWORK_ID

# Node Identity
INSTANCE_NAME=$INSTANCE_NAME

# Ports
HTTP_PORT=$HTTP_PORT
WS_PORT=$WS_PORT
P2P_PORT=$P2P_PORT
AUTHRPC_PORT=$AUTHRPC_PORT

# Paths
DATADIR=/work/xdcchain
PWD_FILE=/work/.pwd

# Stats
STATS_SERVER=$STATS_SERVER
STATS_SECRET=$STATS_SECRET
ETHSTATS_ENABLED=true

# Sync
SYNC_MODE=full
GC_MODE=full

# Peers (extracted from container)
# Add static/trusted nodes here or leave empty to use bootnodes
STATIC_NODES=
TRUSTED_NODES=
EOF

chmod 600 "$TARGET_DIR/.env"

# Copy compose template (values come from .env, no sed needed)
cp "$COMPOSE_TEMPLATE" "$TARGET_DIR/docker-compose.yml"

# Extract chaindata volume path
CHAINDATA_SRC=$(echo "$VOLUMES" | grep '/work/xdcchain' | head -1 | awk '{print $1}')
if [ -n "$CHAINDATA_SRC" ]; then
    warn "Chaindata volume found: $CHAINDATA_SRC"
    warn "Update docker-compose.yml volumes section to point to this path"
fi

# Generate migration script
info "Generating $TARGET_DIR/migrate.sh"

# Use a temp file to avoid sed delimiter issues with paths
MIGRATE_TMP=$(mktemp)
trap 'rm -f "$MIGRATE_TMP"' EXIT

cat > "$MIGRATE_TMP" << 'MIGRATE_EOF'
#!/bin/bash
# Migration script: Stop docker run container, start compose

set -e

CONTAINER="__CONTAINER__"
TARGET="__TARGET__"

echo "=== XNS Migration ==="
echo "This will:"
echo "  1. Stop the docker run container: $CONTAINER"
echo "  2. Start the XNS compose stack in: $TARGET"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted"
    exit 1
fi

echo "Stopping $CONTAINER..."
docker stop "$CONTAINER" || true
docker rename "$CONTAINER" "${CONTAINER}-old" || true

echo "Starting XNS compose..."
cd "$TARGET"
docker compose up -d

echo ""
echo "Migration complete!"
echo "Old container: ${CONTAINER}-old (stopped)"
echo "New stack:"
docker compose ps
echo ""
echo "Verify sync status: docker compose logs -f xdc-node"
echo ""
echo "Rollback if needed:"
echo "  docker stop $(docker compose ps -q)"
echo "  docker rename ${CONTAINER}-old $CONTAINER"
echo "  docker start $CONTAINER"
MIGRATE_EOF

# Replace placeholders using awk (safe with special chars)
awk -v c="$CONTAINER_NAME" -v t="$TARGET_DIR" '
    {gsub(/__CONTAINER__/, c); gsub(/__TARGET__/, t); print}
' "$MIGRATE_TMP" > "$TARGET_DIR/migrate.sh"

chmod +x "$TARGET_DIR/migrate.sh"

info "Migration package created in $TARGET_DIR"
echo ""
echo "=== Files Generated ==="
ls -la "$TARGET_DIR"
echo ""
echo "=== Next Steps ==="
echo "1. Review $TARGET_DIR/.env and adjust as needed"
echo "2. Update volume paths in $TARGET_DIR/docker-compose.yml"
echo "3. Run $TARGET_DIR/migrate.sh to switch over"
echo ""
warn "IMPORTANT: Ensure chaindata volume is accessible from new compose stack"
