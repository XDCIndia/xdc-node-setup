#!/usr/bin/env bash
set -euo pipefail

# XDC CLI Installer
# Installs the 'xdc' command globally and man pages

INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
MAN_DIR="${MAN_DIR:-/usr/local/share/man/man1}"
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

# Install man pages
if [ -d "$PROJECT_DIR/docs/man" ]; then
    echo "Installing man pages..."
    mkdir -p "$MAN_DIR"
    
    for manpage in "$PROJECT_DIR/docs/man"/*.1; do
        if [ -f "$manpage" ]; then
            cp "$manpage" "$MAN_DIR/"
            chmod 644 "$MAN_DIR/$(basename "$manpage")"
            echo "  Installed: $(basename "$manpage")"
        fi
    done
    
    # Update man database
    if command -v mandb &> /dev/null; then
        mandb -q 2>/dev/null || true
    fi
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
echo ""
echo "Manual pages:"
echo "  man xdc           — Main CLI documentation"
echo "  man xdc-setup     — Setup command details"
echo "  man xdc-status    — Status command details"
echo "  man xdc-security  — Security command details"
