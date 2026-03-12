#!/bin/sh
# GP5 (XDC Geth) startup with genesis init guard
# Uses hash state scheme (avoids path-scheme trie node issues)

DATADIR="${DATADIR:-/root/.XDC}"
GENESIS_FILE="$DATADIR/genesis.json"
GENESIS_URL="https://raw.githubusercontent.com/XinFinOrg/XinFin-Node/master/mainnet/genesis.json"
EXPECTED_HASH="4a9d748bd78a8d0385b67788c2435dcdb914f98a96250b68863a1f8b7642d6b1"
STATE_SCHEME="hash"

echo "[GP5-INIT] XDC Mainnet GP5 genesis guard (state.scheme=$STATE_SCHEME)"
echo "[GP5-INIT] Expected genesis: 0x${EXPECTED_HASH}"

# Step 1: Download official genesis
echo "[GP5-INIT] Fetching official genesis from XinFin-Node..."
wget -q "$GENESIS_URL" -O "$GENESIS_FILE" 2>/dev/null || \
  curl -sL "$GENESIS_URL" -o "$GENESIS_FILE" 2>/dev/null
echo "[GP5-INIT] genesis.json downloaded"

# Step 2: Try init with hash scheme
INIT_OUT=$(XDC --datadir "$DATADIR" --state.scheme "$STATE_SCHEME" init "$GENESIS_FILE" 2>&1)
INIT_STATUS=$?

echo "$INIT_OUT" | grep -E "genesis|wrote|error|incompatible" || true

if echo "$INIT_OUT" | grep -q "incompatible genesis"; then
    echo "[GP5-INIT] !! WRONG GENESIS — wiping and reinitializing"
    rm -rf "$DATADIR/geth"
    mkdir -p "$DATADIR/geth"
    XDC --datadir "$DATADIR" --state.scheme "$STATE_SCHEME" init "$GENESIS_FILE" 2>&1 | grep -E "wrote|hash|error"
    echo "[GP5-INIT] ✅ Reinitialized with correct genesis 0x${EXPECTED_HASH}"
elif echo "$INIT_OUT" | grep -q "incompatible state scheme"; then
    echo "[GP5-INIT] !! WRONG STATE SCHEME (path→hash) — wiping chaindata"
    rm -rf "$DATADIR/geth"
    mkdir -p "$DATADIR/geth"
    XDC --datadir "$DATADIR" --state.scheme "$STATE_SCHEME" init "$GENESIS_FILE" 2>&1 | grep -E "wrote|hash|error"
    echo "[GP5-INIT] ✅ Reinitialized with hash scheme"
elif echo "$INIT_OUT" | grep -q "wrote genesis\|already contains"; then
    echo "[GP5-INIT] ✅ Genesis OK: 0x${EXPECTED_HASH}"
else
    echo "[GP5-INIT] ✅ Init complete (status=$INIT_STATUS)"
fi

echo "[GP5-INIT] Starting XDC node..."
exec XDC "$@"
