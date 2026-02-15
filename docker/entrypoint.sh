#!/bin/sh
# Ensure XDC binary is available (image may have XDC-mainnet instead)
if ! command -v XDC >/dev/null 2>&1; then
    for bin in XDC-mainnet XDC-testnet XDC-devnet XDC-local; do
        if command -v "$bin" >/dev/null 2>&1; then
            ln -sf "$(which "$bin")" /tmp/XDC 2>/dev/null || ln -sf "$(which "$bin")" /usr/bin/XDC 2>/dev/null || true
            export PATH="/tmp:$PATH"
            echo "Linked $bin → XDC"
            break
        fi
    done
fi
if ! command -v XDC >/dev/null 2>&1; then
    echo "FATAL: No XDC binary found in image!"
    exit 1
fi
exec /work/start.sh "$@"
