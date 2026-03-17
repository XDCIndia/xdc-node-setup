#!/bin/sh
#==============================================================================
# Universal XDC Entrypoint (Issue #516)
# Handles binary naming differences between XDC versions
#==============================================================================

# Find the correct binary
if command -v XDC >/dev/null 2>&1; then
    BINARY="XDC"
elif command -v XDC-mainnet >/dev/null 2>&1; then
    # v2.6.8 uses XDC-mainnet
    ln -sf "$(command -v XDC-mainnet)" /usr/local/bin/XDC 2>/dev/null || true
    BINARY="XDC-mainnet"
elif command -v geth >/dev/null 2>&1; then
    BINARY="geth"
else
    echo "ERROR: No XDC/geth binary found!"
    exit 1
fi

echo "Using binary: $BINARY"

# If first arg starts with - or is a known command, prepend binary
case "${1:-}" in
    -*)  exec "$BINARY" "$@" ;;
    init|account|attach|console|dump|export|import|version)
         exec "$BINARY" "$@" ;;
    *)   exec "$@" ;;
esac
