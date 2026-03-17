#!/usr/bin/env bash
# Non-Root Container Setup (Issue #399)
set -euo pipefail
XDC_UID="${XDC_UID:-1000}"
XDC_GID="${XDC_GID:-1000}"
echo "🔒 Setting up non-root execution (UID:$XDC_UID GID:$XDC_GID)..."
if ! getent group xdc >/dev/null 2>&1; then groupadd -g "$XDC_GID" xdc; fi
if ! id xdc >/dev/null 2>&1; then useradd -u "$XDC_UID" -g "$XDC_GID" -m -s /bin/bash xdc; fi
echo "✅ Non-root user created"
