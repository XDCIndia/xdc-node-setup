#!/usr/bin/env bash
#==============================================================================
# NM Peer Injector (Issue #577, #579)
# Ensures NM nodes always have peers from the fleet
#==============================================================================

# Known NM peers
NM_PEERS=(
  "enode://cb205eecce121059caf7f223ee431f82628f9173c3d29d4632ad2cd88bc04989787ec4a0990b41b7cb9fac25764a69c2f33733b829baf94a38f5f94f3372a8f9@167.235.13.113:30305"
  "enode://1a99c7423d5c02bc74d55900cb3bab95e50a3a197f72a3642690f099a5468f3e35904b2f5f7a0371969f4e5b6885167ad3ac725d40f1e7fa34ce992a58def482@65.21.27.213:30305"
)

RPC_URL="${1:-http://127.0.0.1:8547}"

PEERS=$(curl -sf -m 3 -X POST "$RPC_URL" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' 2>/dev/null | \
  grep -o '"result":"0x[^"]*"' | cut -d'"' -f4)
COUNT=$(printf "%d" "${PEERS:-0x0}" 2>/dev/null)

if [ "$COUNT" -lt 2 ]; then
  for peer in "${NM_PEERS[@]}"; do
    curl -sf -m 3 -X POST "$RPC_URL" \
      -H "Content-Type: application/json" \
      -d "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addPeer\",\"params\":[\"$peer\"],\"id\":1}" >/dev/null 2>&1
  done
fi
