#!/bin/sh
# Ensure XDC binary is available (image may have XDC-mainnet instead)
mkdir -p /run/xdc 2>/dev/null || true
export PATH="/run/xdc:/usr/local/bin:/var/tmp:/tmp:$PATH"

if ! command -v XDC >/dev/null 2>&1; then
    for bin in XDC-mainnet XDC-testnet XDC-devnet XDC-local; do
        BINPATH=$(which "$bin" 2>/dev/null)
        if [ -n "$BINPATH" ]; then
            # Try writable+exec locations (/run/xdc is tmpfs, always works)
            for dest in /run/xdc/XDC /usr/local/bin/XDC /tmp/XDC /var/tmp/XDC; do
                if cp "$BINPATH" "$dest" 2>/dev/null && chmod +x "$dest" 2>/dev/null; then
                    echo "Copied $bin → $dest"
                    break
                fi
            done
            break
        fi
    done
fi

if ! command -v XDC >/dev/null 2>&1; then
    echo "FATAL: No XDC binary found in image!"
    echo "Searched: XDC, XDC-mainnet, XDC-testnet, XDC-devnet, XDC-local"
    echo "PATH=$PATH"
    ls -la /usr/bin/XDC* /tmp/XDC 2>/dev/null
    exit 1
fi

echo "Using XDC binary: $(which XDC)"
exec /work/start.sh "$@"
