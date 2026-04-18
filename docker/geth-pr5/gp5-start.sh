#!/bin/sh
# GP5 (XDC Geth) startup with genesis init guard
# Auto-detects state.scheme from marker file or datadir structure

DATADIR="${DATADIR:-/root/.XDC}"
GENESIS_FILE="$DATADIR/genesis.json"
GENESIS_URL="https://raw.githubusercontent.com/XinFinOrg/XinFin-Node/master/mainnet/genesis.json"
EXPECTED_HASH="4a9d748bd78a8d0385b67788c2435dcdb914f98a96250b68863a1f8b7642d6b1"

# ── State scheme auto-detection ──────────────────────────────────────────────
STATE_SCHEME="${STATE_SCHEME:-auto}"

detect_scheme() {
    local dir="$1"
    # 1) Check explicit marker file
    if [ -f "$dir/.state-scheme" ]; then
        cat "$dir/.state-scheme"
        return
    fi
    # 2) PBSS (path) uses triedb/ directory
    if [ -d "$dir/triedb" ] || [ -d "$dir/geth/triedb" ] || [ -d "$dir/chaindata/triedb" ]; then
        echo "path"
        return
    fi
    # 3) HBSS (hash) uses ancient/ directory without triedb
    if [ -d "$dir/ancient" ] || [ -d "$dir/geth/chaindata/ancient" ] || [ -d "$dir/chaindata/ancient" ]; then
        echo "hash"
        return
    fi
    # 4) Fresh datadir — default to hash for maximum compatibility
    echo "hash"
}

if [ "$STATE_SCHEME" = "auto" ]; then
    STATE_SCHEME=$(detect_scheme "$DATADIR")
    echo "[GP5-INIT] Auto-detected state.scheme=$STATE_SCHEME"
else
    echo "[GP5-INIT] Using explicit state.scheme=$STATE_SCHEME"
fi

# Save detected scheme back to marker for next boot
echo "$STATE_SCHEME" > "$DATADIR/.state-scheme"

echo "[GP5-INIT] XDC Mainnet GP5 genesis guard (state.scheme=$STATE_SCHEME)"
echo "[GP5-INIT] Expected genesis: 0x${EXPECTED_HASH}"

# Step 1: Download official genesis
echo "[GP5-INIT] Fetching official genesis from XinFin-Node..."
wget -q "$GENESIS_URL" -O "$GENESIS_FILE" 2>/dev/null || \
  curl -sL "$GENESIS_URL" -o "$GENESIS_FILE" 2>/dev/null
echo "[GP5-INIT] genesis.json downloaded"

# Step 2: Init with detected scheme
INIT_OUT=$(XDC --datadir "$DATADIR" --state.scheme "$STATE_SCHEME" init "$GENESIS_FILE" 2>&1)
INIT_STATUS=$?

echo "$INIT_OUT" | grep -E "genesis|wrote|error|incompatible|scheme" || true

if echo "$INIT_OUT" | grep -q "incompatible genesis"; then
    echo "[GP5-INIT] !! WRONG GENESIS — wiping and reinitializing"
    rm -rf "$DATADIR/geth"
    mkdir -p "$DATADIR/geth"
    XDC --datadir "$DATADIR" --state.scheme "$STATE_SCHEME" init "$GENESIS_FILE" 2>&1 | grep -E "wrote|hash|error"
    echo "[GP5-INIT] Reinitialized with correct genesis 0x${EXPECTED_HASH}"
elif echo "$INIT_OUT" | grep -q "incompatible state scheme"; then
    echo "[GP5-INIT] !! STATE SCHEME MISMATCH — re-detecting from datadir"
    rm -f "$DATADIR/.state-scheme"
    STATE_SCHEME=$(detect_scheme "$DATADIR")
    echo "$STATE_SCHEME" > "$DATADIR/.state-scheme"
    echo "[GP5-INIT] Re-detected scheme: $STATE_SCHEME — retrying init"
    XDC --datadir "$DATADIR" --state.scheme "$STATE_SCHEME" init "$GENESIS_FILE" 2>&1 | grep -E "wrote|hash|error|scheme"
    echo "[GP5-INIT] Retried init with scheme=$STATE_SCHEME"
elif echo "$INIT_OUT" | grep -q "wrote genesis\|already contains"; then
    echo "[GP5-INIT] Genesis OK: 0x${EXPECTED_HASH}"
else
    echo "[GP5-INIT] Init complete (status=$INIT_STATUS)"
fi

echo "[GP5-INIT] Starting XDC node..."
exec XDC "$@"
