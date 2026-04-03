#!/bin/bash
# Quick Start — Get XDC node running in 60 seconds
# Works on macOS and Linux. Requires: git, docker, docker compose
set -e

NETWORK="${1:-mainnet}"
echo "🚀 XDC Node Quick Start — $NETWORK"
echo "======================================"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 1. Create required directories
echo "📁 Creating directories..."
mkdir -p "$NETWORK/xdcchain"
mkdir -p "$NETWORK/.xdc-node/logs"

# 2. Generate wallet password if missing
if [ ! -f "docker/$NETWORK/.pwd" ]; then
    echo "🔑 Generating wallet password..."
    mkdir -p "docker/$NETWORK"
    openssl rand -hex 16 > "docker/$NETWORK/.pwd" 2>/dev/null || echo "xdc-node-password-$(date +%s)" > "docker/$NETWORK/.pwd"
fi

# 3. Create .env if missing
if [ ! -f "$NETWORK/.xdc-node/.env" ]; then
    echo "📝 Creating .env..."
    cat > "$NETWORK/.xdc-node/.env" << 'EOF'
NETWORK=mainnet
SYNC_MODE=full
GC_MODE=full
RPC_PORT=8545
WS_PORT=8546
P2P_PORT=30303
INSTANCE_NAME=xdc-node
EOF
fi

# 4. Create config.toml if missing
if [ ! -f "$NETWORK/.xdc-node/config.toml" ]; then
    echo "📝 Creating config.toml..."
    if [ -f "configs/config.toml.template" ]; then
        cp "configs/config.toml.template" "$NETWORK/.xdc-node/config.toml"
        # Replace placeholders with defaults
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' 's|{{DATA_DIR}}|/work/xdcchain|g; s|{{CHAIN_ID}}|50|g; s|{{SYNC_MODE}}|full|g; s|{{P2P_PORT}}|30303|g; s|{{MAX_PEERS}}|25|g; s|{{RPC_PORT}}|8545|g; s|{{WS_PORT}}|8546|g; s|{{BOOTNODES}}||g; s|{{RPC_API}}|eth,net,web3,xdpos|g; s|{{LOG_LEVEL}}|3|g; s|{{VERBOSITY}}|3|g' "$NETWORK/.xdc-node/config.toml"
        else
            sed -i 's|{{DATA_DIR}}|/work/xdcchain|g; s|{{CHAIN_ID}}|50|g; s|{{SYNC_MODE}}|full|g; s|{{P2P_PORT}}|30303|g; s|{{MAX_PEERS}}|25|g; s|{{RPC_PORT}}|8545|g; s|{{WS_PORT}}|8546|g; s|{{BOOTNODES}}||g; s|{{RPC_API}}|eth,net,web3,xdpos|g; s|{{LOG_LEVEL}}|3|g; s|{{VERBOSITY}}|3|g' "$NETWORK/.xdc-node/config.toml"
        fi
    else
        touch "$NETWORK/.xdc-node/config.toml"
    fi
fi

# 5. Create skynet.conf if missing
if [ ! -f "$NETWORK/.xdc-node/skynet.conf" ]; then
    echo "📝 Creating skynet.conf..."
    cat > "$NETWORK/.xdc-node/skynet.conf" << 'EOF'
# SkyNet Node Monitoring Configuration
SKYNET_ENABLED=false
SKYNET_API_URL=https://skynet.xdcindia.com/api/v1
SKYNET_API_KEY=
SKYNET_NODE_ID=
EOF
fi

# 6. Copy skynet-agent.sh to docker/ if missing
if [ ! -f "docker/skynet-agent.sh" ]; then
    if [ -f "scripts/skynet-agent.sh" ]; then
        cp "scripts/skynet-agent.sh" "docker/skynet-agent.sh"
    else
        echo '#!/bin/bash' > "docker/skynet-agent.sh"
        echo 'echo "SkyNet agent not configured"' >> "docker/skynet-agent.sh"
    fi
    chmod +x "docker/skynet-agent.sh"
fi

# 7. Validate
echo ""
echo "✅ Checking required files..."
MISSING=0
for f in "docker/entrypoint.sh" "docker/$NETWORK/genesis.json" "docker/$NETWORK/start-node.sh" "docker/$NETWORK/bootnodes.list" "docker/$NETWORK/.pwd" "docker/skynet-agent.sh" "$NETWORK/.xdc-node/.env" "$NETWORK/.xdc-node/config.toml" "$NETWORK/.xdc-node/skynet.conf"; do
    if [ -f "$f" ]; then
        echo "  ✅ $f"
    else
        echo "  ❌ $f MISSING"
        MISSING=$((MISSING + 1))
    fi
done

if [ $MISSING -gt 0 ]; then
    echo ""
    echo "❌ $MISSING files missing. Please check the errors above."
    exit 1
fi

echo ""
echo "🎉 All files ready!"
echo ""
echo "Now run:"
echo "  cd docker"
echo "  docker compose up -d"
echo ""
echo "Monitor with:"
echo "  docker logs -f xdc-node"
echo ""
echo "Dashboard at: http://localhost:7070"
