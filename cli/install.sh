#!/usr/bin/env bash
set -euo pipefail

# XDC CLI Installer
# Installs the 'xdc' command globally

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Installing XDC CLI..."

# Install main binary
cp "$SCRIPT_DIR/xdc" "$INSTALL_DIR/xdc"
chmod +x "$INSTALL_DIR/xdc"

# Install bash completions
if [ -d /etc/bash_completion.d ]; then
    cp "$SCRIPT_DIR/completions/xdc.bash" /etc/bash_completion.d/xdc 2>/dev/null || true
fi

# Install zsh completions
if [ -d /usr/local/share/zsh/site-functions ]; then
    cp "$SCRIPT_DIR/completions/xdc.zsh" /usr/local/share/zsh/site-functions/_xdc 2>/dev/null || true
fi

echo "✅ XDC CLI installed: $(xdc --version 2>/dev/null || echo 'v1.0.0')"
echo ""
echo "Usage:"
echo "  xdc status        — Show node status"
echo "  xdc start         — Start XDC node"
echo "  xdc stop          — Stop XDC node"
echo "  xdc logs          — View node logs"
echo "  xdc peers         — Show connected peers"
echo "  xdc sync          — Show sync progress"
echo "  xdc health        — Full health check"
echo "  xdc help          — Show all commands"
