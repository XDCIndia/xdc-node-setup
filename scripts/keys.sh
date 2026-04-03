#!/usr/bin/env bash
# keys.sh — Validator Key Management (#132)
# Usage: keys.sh generate [network] [client]
#        keys.sh import <file> [network] [client]
#        keys.sh export <client> [network]
#        keys.sh rotate <client> [network]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/../data"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  generate [network] [client]       Generate new encrypted keystore
  import <file> [network] [client]  Import an existing keystore file
  export <client> [network]         Export keystore for a client
  rotate <client> [network]         Hot-swap validator key (rotate)

Defaults:
  network = mainnet
  client  = geth

Environment:
  KEY_PASSPHRASE   Passphrase for encryption (prompted if not set)
EOF
  exit 1
}

get_keystore_dir() {
  local network="${1:-mainnet}"
  local client="${2:-geth}"
  echo "${DATA_DIR}/${network}/${client}/keystore"
}

require_passphrase() {
  if [[ -z "${KEY_PASSPHRASE:-}" ]]; then
    read -r -s -p "Enter keystore passphrase: " KEY_PASSPHRASE
    echo
    read -r -s -p "Confirm passphrase: " KEY_PASSPHRASE2
    echo
    if [[ "$KEY_PASSPHRASE" != "$KEY_PASSPHRASE2" ]]; then
      echo "ERROR: Passphrases do not match" >&2; exit 1
    fi
  fi
}

cmd_generate() {
  local network="${1:-mainnet}"
  local client="${2:-geth}"
  local ks_dir
  ks_dir="$(get_keystore_dir "$network" "$client")"
  mkdir -p "$ks_dir"

  require_passphrase

  # Generate private key
  local privkey
  privkey="$(openssl rand -hex 32)"
  local pubkey
  pubkey="$(echo -n "$privkey" | openssl dgst -sha256 | awk '{print $2}')"
  local timestamp
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  local keyfile="${ks_dir}/UTC--${timestamp}--${pubkey:0:40}"

  # Encrypt with openssl AES-256-CBC
  local encrypted
  encrypted="$(echo -n "$privkey" | openssl enc -aes-256-cbc -pbkdf2 -iter 100000 \
    -pass pass:"$KEY_PASSPHRASE" -base64 -A)"

  # Write keystore JSON
  cat > "$keyfile" <<JSON
{
  "version": 3,
  "id": "$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)",
  "address": "${pubkey:0:40}",
  "crypto": {
    "cipher": "aes-256-cbc",
    "ciphertext": "${encrypted}",
    "kdf": "pbkdf2",
    "kdfparams": {
      "dklen": 32,
      "c": 100000,
      "prf": "hmac-sha256",
      "salt": "$(openssl rand -hex 16)"
    },
    "mac": "$(echo -n "${encrypted}${privkey}" | openssl dgst -sha256 | awk '{print $2}')"
  },
  "network": "${network}",
  "client": "${client}",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON

  chmod 600 "$keyfile"
  echo "✅ Generated keystore: $keyfile"
  echo "   Address: 0x${pubkey:0:40}"
}

cmd_import() {
  local file="${1:?ERROR: import requires <file>}"
  local network="${2:-mainnet}"
  local client="${3:-geth}"
  local ks_dir
  ks_dir="$(get_keystore_dir "$network" "$client")"
  mkdir -p "$ks_dir"

  [[ -f "$file" ]] || { echo "ERROR: File not found: $file" >&2; exit 1; }

  local basename
  basename="$(basename "$file")"
  cp "$file" "${ks_dir}/${basename}"
  chmod 600 "${ks_dir}/${basename}"
  echo "✅ Imported keystore: ${ks_dir}/${basename}"
}

cmd_export() {
  local client="${1:?ERROR: export requires <client>}"
  local network="${2:-mainnet}"
  local ks_dir
  ks_dir="$(get_keystore_dir "$network" "$client")"

  [[ -d "$ks_dir" ]] || { echo "ERROR: No keystore found at $ks_dir" >&2; exit 1; }

  local export_dir="./keystore-export-$(date +%Y%m%d%H%M%S)"
  mkdir -p "$export_dir"
  cp -r "$ks_dir"/. "$export_dir/"
  chmod 700 "$export_dir"
  echo "✅ Exported keystore to: $export_dir"
}

cmd_rotate() {
  local client="${1:?ERROR: rotate requires <client>}"
  local network="${2:-mainnet}"
  local ks_dir
  ks_dir="$(get_keystore_dir "$network" "$client")"

  echo "🔄 Rotating validator key for ${client} on ${network}..."

  # Backup existing keys
  local backup_dir="${ks_dir}.backup.$(date +%Y%m%d%H%M%S)"
  if [[ -d "$ks_dir" ]]; then
    cp -r "$ks_dir" "$backup_dir"
    echo "   Backed up existing keys to: $backup_dir"
  fi

  # Generate new key
  cmd_generate "$network" "$client"

  # Signal client to reload (send SIGHUP or restart container)
  local container_name="xdc-${client}"
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
    echo "   Hot-swapping key in container ${container_name}..."
    docker kill --signal=SIGHUP "$container_name" 2>/dev/null || true
    echo "✅ Key rotated and client signaled to reload"
  else
    echo "✅ Key rotated. Restart client to apply new key."
  fi
}

CMD="${1:-}"
shift || true

case "$CMD" in
  generate) cmd_generate "$@" ;;
  import)   cmd_import   "$@" ;;
  export)   cmd_export   "$@" ;;
  rotate)   cmd_rotate   "$@" ;;
  *)        usage ;;
esac
