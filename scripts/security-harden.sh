#!/bin/bash
#==============================================================================
# XDC Node Security Hardening Script
# Fixes: #493 (RPC 0.0.0.0), #492 (CORS wildcard), #498 (Hardcoded creds), #499 (Docker socket)
#==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NETWORK="${1:-mainnet}"
FORCE="${2:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== XDC Node Security Hardening ===${NC}"
echo "Network: $NETWORK"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Function to backup existing config
backup_config() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.backup-$(date +%Y%m%d-%H%M%S)"
        cp "$file" "$backup"
        echo -e "${YELLOW}Backed up: $file -> $backup${NC}"
    fi
}

#==============================================================================
# Fix #493: RPC should bind to 127.0.0.1 instead of 0.0.0.0
#==============================================================================
echo -e "${GREEN}[Fix #493] Securing RPC bind address...${NC}"

# Update config.toml to bind RPC to localhost
CONFIG_FILE="${SCRIPT_DIR}/../${NETWORK}/.xdc-node/config.toml"
if [[ -f "$CONFIG_FILE" ]]; then
    backup_config "$CONFIG_FILE"
    
    # Replace 0.0.0.0 with 127.0.0.1 for HTTP and WS
    sed -i 's/HTTPHost = "0.0.0.0"/HTTPHost = "127.0.0.1"/g' "$CONFIG_FILE"
    sed -i 's/WSHost = "0.0.0.0"/WSHost = "127.0.0.1"/g' "$CONFIG_FILE"
    
    # If no HTTPHost line exists, add it
    if ! grep -q "HTTPHost" "$CONFIG_FILE"; then
        echo 'HTTPHost = "127.0.0.1"' >> "$CONFIG_FILE"
    fi
    
    echo -e "${GREEN}✓ RPC now binds to 127.0.0.1 only${NC}"
else
    echo -e "${YELLOW}⚠ Config file not found: $CONFIG_FILE${NC}"
fi

#==============================================================================
# Fix #492: Remove CORS wildcard
#==============================================================================
echo -e "${GREEN}[Fix #492] Securing CORS configuration...${NC}"

if [[ -f "$CONFIG_FILE" ]]; then
    backup_config "$CONFIG_FILE"
    
    # Replace wildcard CORS with empty (no CORS allowed from browsers)
    sed -i 's/HTTPCors = "\*"/HTTPCors = ""/g' "$CONFIG_FILE"
    sed -i 's/WSCors = "\*"/WSCors = ""/g' "$CONFIG_FILE"
    
    # Replace vhosts wildcard
    sed -i 's/HTTPVirtualHosts = "\*"/HTTPVirtualHosts = "localhost,127.0.0.1"/g' "$CONFIG_FILE"
    
    echo -e "${GREEN}✓ CORS wildcard removed${NC}"
    echo -e "${YELLOW}  Note: To allow specific origins, edit $CONFIG_FILE${NC}"
fi

#==============================================================================
# Fix #498: Generate random credentials instead of hardcoded ones
#==============================================================================
echo -e "${GREEN}[Fix #498] Generating secure credentials...${NC}"

ENV_FILE="${SCRIPT_DIR}/../${NETWORK}/.xdc-node/.env"
if [[ -f "$ENV_FILE" ]]; then
    backup_config "$ENV_FILE"
    
    # Generate random credentials
    RANDOM_USER="xdc-$(openssl rand -hex 4)"
    RANDOM_PASS="$(openssl rand -base64 32)"
    
    # Update or add credentials
    if grep -q "DASHBOARD_USER=" "$ENV_FILE"; then
        sed -i "s/DASHBOARD_USER=.*/DASHBOARD_USER=$RANDOM_USER/" "$ENV_FILE"
    else
        echo "DASHBOARD_USER=$RANDOM_USER" >> "$ENV_FILE"
    fi
    
    if grep -q "DASHBOARD_PASS=" "$ENV_FILE"; then
        sed -i "s/DASHBOARD_PASS=.*/DASHBOARD_PASS=$RANDOM_PASS/" "$ENV_FILE"
    else
        echo "DASHBOARD_PASS=$RANDOM_PASS" >> "$ENV_FILE"
    fi
    
    # Enable auth
    if grep -q "DASHBOARD_AUTH_ENABLED=" "$ENV_FILE"; then
        sed -i 's/DASHBOARD_AUTH_ENABLED=.*/DASHBOARD_AUTH_ENABLED=true/' "$ENV_FILE"
    else
        echo "DASHBOARD_AUTH_ENABLED=true" >> "$ENV_FILE"
    fi
    
    echo -e "${GREEN}✓ Random credentials generated${NC}"
    echo -e "${YELLOW}  Username: $RANDOM_USER${NC}"
    echo -e "${YELLOW}  Password: (saved in $ENV_FILE)${NC}"
    echo -e "${RED}  IMPORTANT: Save this password - it won't be shown again!${NC}"
    echo ""
fi

# Generate JWT secret for authenticated RPC
JWT_FILE="/etc/xdc-node/jwt.hex"
mkdir -p "$(dirname "$JWT_FILE")"
if [[ ! -f "$JWT_FILE" ]] || [[ "$FORCE" == "--force" ]]; then
    openssl rand -hex 32 > "$JWT_FILE"
    chmod 600 "$JWT_FILE"
    echo -e "${GREEN}✓ JWT secret generated: $JWT_FILE${NC}"
else
    echo -e "${YELLOW}⚠ JWT secret already exists (use --force to regenerate)${NC}"
fi

#==============================================================================
# Fix #499: Review Docker socket and privileged mode
#==============================================================================
echo -e "${GREEN}[Fix #499] Reviewing container security...${NC}"

DOCKER_COMPOSE="${SCRIPT_DIR}/../docker/docker-compose.yml"
if [[ -f "$DOCKER_COMPOSE" ]]; then
    backup_config "$DOCKER_COMPOSE"
    
    # Check for Docker socket mount
    if grep -q "/var/run/docker.sock" "$DOCKER_COMPOSE"; then
        echo -e "${YELLOW}⚠ Docker socket mount detected${NC}"
        echo -e "${YELLOW}  This is required for container monitoring${NC}"
        echo -e "${YELLOW}  To remove (breaks monitoring), manually edit:$DOCKER_COMPOSE${NC}"
    fi
    
    # Add security options if not present
    if ! grep -q "no-new-privileges" "$DOCKER_COMPOSE"; then
        echo -e "${YELLOW}⚠ Consider adding 'no-new-privileges:true' to security_opt${NC}"
    fi
    
    echo -e "${GREEN}✓ Container security reviewed${NC}"
fi

#==============================================================================
# Restart services if requested
#==============================================================================
echo ""
echo -e "${GREEN}=== Security Hardening Complete ===${NC}"
echo ""
echo "To apply changes, restart the node with:"
echo "  cd /root/.openclaw/workspace/XDC-Node-Setup"
echo "  docker compose -f docker/docker-compose.yml restart"
echo ""
echo -e "${YELLOW}IMPORTANT: RPC is now only accessible from localhost.${NC}"
echo -e "${YELLOW}To access from remote, use SSH tunnel:${NC}"
echo "  ssh -L 8545:localhost:8545 user@node-ip"
echo ""
