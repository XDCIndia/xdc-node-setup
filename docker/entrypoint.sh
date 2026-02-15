#!/bin/sh
# Ensure XDC binary is available (image may have XDC-mainnet instead of XDC)
# Strategy: find the binary, then either copy it or create a wrapper script

mkdir -p /run/xdc 2>/dev/null || true
export PATH="/run/xdc:/usr/local/bin:/var/tmp:/tmp:$PATH"

if ! command -v XDC >/dev/null 2>&1; then
    FOUND=""
    for bin in XDC-mainnet XDC-testnet XDC-devnet XDC-local; do
        BINPATH=$(which "$bin" 2>/dev/null)
        if [ -n "$BINPATH" ]; then
            FOUND="$BINPATH"
            break
        fi
    done

    if [ -n "$FOUND" ]; then
        COPIED=false
        # Try copying to writable+exec locations
        for dest in /run/xdc/XDC /usr/local/bin/XDC /tmp/XDC /var/tmp/XDC; do
            if cp "$FOUND" "$dest" 2>/dev/null && chmod +x "$dest" 2>/dev/null; then
                echo "Copied $(basename $FOUND) → $dest"
                COPIED=true
                break
            fi
        done

        # If copy failed everywhere, create a shell wrapper script instead
        if [ "$COPIED" = false ]; then
            for dest in /run/xdc/XDC /tmp/XDC /var/tmp/XDC; do
                cat > "$dest" 2>/dev/null <<WRAPPER
#!/bin/sh
exec "$FOUND" "\$@"
WRAPPER
                if chmod +x "$dest" 2>/dev/null; then
                    echo "Created wrapper $dest → $FOUND"
                    COPIED=true
                    break
                fi
            done
        fi

        # Last resort: symlink (may fail on read-only fs but worth trying)
        if [ "$COPIED" = false ]; then
            for dest in /run/xdc/XDC /tmp/XDC /var/tmp/XDC; do
                if ln -sf "$FOUND" "$dest" 2>/dev/null; then
                    echo "Linked $(basename $FOUND) → $dest"
                    COPIED=true
                    break
                fi
            done
        fi

        # Nuclear option: just exec the found binary directly via start.sh modification
        if [ "$COPIED" = false ]; then
            echo "WARNING: Could not copy/link binary. Using XDC_BIN env var."
            export XDC_BIN="$FOUND"
            # Patch start.sh to use $XDC_BIN if XDC not in PATH
            if [ -f /work/start.sh ]; then
                sed -i "s|XDC |${FOUND} |g" /work/start.sh 2>/dev/null || true
                echo "Patched start.sh to use $FOUND directly"
            fi
        fi
    fi
fi

if ! command -v XDC >/dev/null 2>&1 && [ -z "$XDC_BIN" ]; then
    echo "FATAL: No XDC binary found in image!"
    echo "Searched: XDC, XDC-mainnet, XDC-testnet, XDC-devnet, XDC-local"
    echo "PATH=$PATH"
    echo "Filesystem check:"
    ls -la /usr/bin/XDC* /run/xdc/ /tmp/XDC /var/tmp/XDC 2>/dev/null
    mount | grep -E 'tmp|run' 2>/dev/null
    exit 1
fi

echo "Using XDC binary: $(command -v XDC 2>/dev/null || echo $XDC_BIN)"
exec /work/start.sh "$@"
