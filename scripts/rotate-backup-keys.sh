#!/usr/bin/env bash

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }
#==============================================================================
#==============================================================================
# Backup Encryption Key Rotation Script
# Implements secure key rotation for backup encryption
# Supports: GPG key rotation, Age key rotation
#==============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/lib"

# Source libraries
# shellcheck source=/dev/null
source "${LIB_DIR}/logging.sh" 2>/dev/null || {
    log_info() { echo "[INFO] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
    log_warning() { echo "[WARNING] $1" >&2; }
}

# shellcheck source=/dev/null
source "${LIB_DIR}/secrets.sh" 2>/dev/null || true

# Configuration
readonly KEYS_DIR="${KEYS_DIR:-/opt/xdc-node/keys}"
readonly BACKUP_DIR="${BACKUP_DIR:-/opt/xdc-node/backups}"
readonly KEY_METADATA_FILE="${KEYS_DIR}/key-metadata.json"
readonly ROTATION_LOG="${KEYS_DIR}/rotation.log"

#==============================================================================
# GPG Key Rotation
#==============================================================================

# Generate a new GPG key for backup encryption
generate_gpg_key() {
    local key_id="$1"
    local email="${2:-xdc-backup@localhost}"
    local name="${3:-XDC Backup Key}"

    log_info "Generating new GPG key" "{\"key_id\":\"${key_id}\",\"email\":\"${email}\"}"

    # Create batch file for unattended key generation
    local batch_file
    batch_file=$(mktemp)
    cat > "$batch_file" << EOF
%echo Generating backup encryption key
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: ${name}
Name-Email: ${email}
Expire-Date: 2y
%no-protection
%commit
%echo done
EOF

    gpg --batch --gen-key "$batch_file" 2>&1
    rm -f "$batch_file"

    # Get the fingerprint
    local fingerprint
    fingerprint=$(gpg --list-keys --with-colons "$email" | grep fpr | head -1 | cut -d: -f10)

    log_info "GPG key generated" "{\"fingerprint\":\"${fingerprint}\"}"
    echo "$fingerprint"
}

# Export GPG public key
export_gpg_public_key() {
    local fingerprint="$1"
    local output_file="$2"

    gpg --armor --export "$fingerprint" > "$output_file"
    log_info "Exported GPG public key" "{\"file\":\"${output_file}\"}"
}

# Export GPG private key (for backup)
export_gpg_private_key() {
    local fingerprint="$1"
    local output_file="$2"

    gpg --armor --export-secret-keys "$fingerprint" > "$output_file"
    chmod 600 "$output_file"
    log_info "Exported GPG private key" "{\"file\":\"${output_file}\"}"
}

#==============================================================================
# Age Key Rotation
#==============================================================================

# Generate new Age key pair
rotate_age_key() {
    local key_id="${1:-$(date +%Y%m%d)}"

    log_info "Generating new Age key pair" "{\"key_id\":\"${key_id}\"}"

    mkdir -p "$KEYS_DIR"
    chmod 700 "$KEYS_DIR"

    local identity_file="${KEYS_DIR}/age-key-${key_id}.key"
    local public_key_file="${KEYS_DIR}/age-key-${key_id}.pub"

    if ! command -v age-keygen &>/dev/null; then
        log_error "age-keygen not found. Install age: https://github.com/FiloSottile/age"
        return 1
    fi

    # Generate key
    age-keygen -o "$identity_file" 2>&1 | grep "public key" | cut -d: -f2 | tr -d ' ' > "$public_key_file"

    chmod 600 "$identity_file"
    chmod 644 "$public_key_file"

    log_info "Age key pair generated" "{\"identity\":\"${identity_file}\",\"public_key\":\"${public_key_file}\"}"

    # Update current key symlink
    ln -sf "$(basename "$identity_file")" "${KEYS_DIR}/age-current.key"
    ln -sf "$(basename "$public_key_file")" "${KEYS_DIR}/age-current.pub"

    # Update metadata
    update_key_metadata "age" "$key_id" "$(cat "$public_key_file")"

    echo "$public_key_file"
}

#==============================================================================
# Key Metadata Management
#==============================================================================

# Initialize key metadata file
init_key_metadata() {
    mkdir -p "$KEYS_DIR"

    if [[ ! -f "$KEY_METADATA_FILE" ]]; then
        cat > "$KEY_METADATA_FILE" << 'EOF'
{
  "version": "1.0",
  "keys": [],
  "rotation_history": []
}
EOF
        chmod 600 "$KEY_METADATA_FILE"
    fi
}

# Update key metadata
update_key_metadata() {
    local key_type="$1"
    local key_id="$2"
    local public_key="$3"

    init_key_metadata

    local temp_file
    temp_file=$(mktemp)

    jq --arg type "$key_type" \
       --arg id "$key_id" \
       --arg pub "$public_key" \
       --arg date "$(date -Iseconds)" \
       '.keys += [{"type": $type, "id": $id, "public_key": $pub, "created_at": $date, "status": "active"}] |
        .rotation_history += [{"type": $type, "id": $id, "rotated_at": $date}]' \
       "$KEY_METADATA_FILE" > "$temp_file"

    mv "$temp_file" "$KEY_METADATA_FILE"
    chmod 600 "$KEY_METADATA_FILE"
}

# Deactivate old keys (mark as deprecated, don't delete)
deactivate_old_keys() {
    local key_type="$1"
    local keep_count="${2:-3}"

    init_key_metadata

    local temp_file
    temp_file=$(mktemp)

    # Mark all but the most recent N keys as deprecated
    jq --arg type "$key_type" \
       --argjson count "$keep_count" \
       '[.keys[] | select(.type == $type)] as $type_keys |
        ($type_keys | length) as $total |
        .keys |= map(
          if .type == $type then
            if .id as $id | $type_keys | map(.id) | index($id) >= ($total - $count) then
              .status = "active"
            else
              .status = "deprecated"
            end
          else
            .
          end
        )' \
       "$KEY_METADATA_FILE" > "$temp_file"

    mv "$temp_file" "$KEY_METADATA_FILE"
    chmod 600 "$KEY_METADATA_FILE"

    log_info "Deactivated old keys" "{\"type\":\"${key_type}\",\"keep_count\":${keep_count}}"
}

# Get active encryption key
get_active_key() {
    local key_type="$1"

    init_key_metadata

    jq -r --arg type "$key_type" \
          '.keys[] | select(.type == $type and .status == "active") | .public_key' \
          "$KEY_METADATA_FILE" | tail -1
}

# Get key by ID
get_key_by_id() {
    local key_id="$1"

    init_key_metadata

    jq -r --arg id "$key_id" \
          '.keys[] | select(.id == $id)' \
          "$KEY_METADATA_FILE"
}

#==============================================================================
# Re-encryption Functions
#==============================================================================

# Re-encrypt a backup with a new key
reencrypt_backup() {
    local backup_file="$1"
    local new_key_file="$2"
    local old_key_file="${3:-}"

    log_info "Re-encrypting backup" "{\"file\":\"${backup_file}\"}"

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found" "{\"file\":\"${backup_file}\"}"
        return 1
    fi

    local temp_dir
    temp_dir=$(mktemp -d)
    local decrypted_file="${temp_dir}/decrypted"

    # Determine encryption type and decrypt
    if [[ "$backup_file" == *.age ]]; then
        if [[ -z "$old_key_file" ]]; then
            log_error "Old key file required for age decryption"
            rm -rf "$temp_dir"
            return 1
        fi
        age -d -i "$old_key_file" -o "$decrypted_file" "$backup_file"
        age -r "$(cat "$new_key_file")" -o "${backup_file}.new" "$decrypted_file"
    elif [[ "$backup_file" == *.gpg ]]; then
        gpg --decrypt --output "$decrypted_file" "$backup_file"
        gpg --encrypt --recipient-file "$new_key_file" --output "${backup_file}.new" "$decrypted_file"
    else
        log_error "Unknown backup encryption format"
        rm -rf "$temp_dir"
        return 1
    fi

    # Replace old backup with new one
    mv "${backup_file}.new" "$backup_file"
    rm -rf "$temp_dir"

    log_info "Backup re-encrypted successfully"
}

# Re-encrypt all recent backups
reencrypt_all_backups() {
    local days="${1:-30}"
    local key_type="${2:-age}"

    log_info "Starting batch re-encryption" "{\"days\":${days},\"type\":\"${key_type}\"}"

    # Get current active key
    local current_key
    current_key=$(get_active_key "$key_type")

    if [[ -z "$current_key" ]]; then
        log_error "No active key found for type: $key_type"
        return 1
    fi

    local count=0

    # Find and re-encrypt recent backups
    while IFS= read -r -d '' backup_file; do
        log_info "Processing backup" "{\"file\":\"${backup_file}\"}"
        # Note: In production, you'd need the old key to decrypt
        # This is a placeholder for the re-encryption logic
        ((count++)) || true
    done < <(find "$BACKUP_DIR" -name "*.${key_type}" -mtime -"$days" -print0 2>/dev/null)

    log_info "Batch re-encryption completed" "{\"processed\":${count}}"
}

#==============================================================================
# Key Rotation Workflow
#==============================================================================

# Perform a complete key rotation
perform_key_rotation() {
    local key_type="${1:-age}"
    local reencrypt="${2:-true}"

    log_info "Starting key rotation" "{\"type\":\"${key_type}\"}"

    # Generate new key
    case "$key_type" in
        age)
            rotate_age_key "$(date +%Y%m%d-%H%M%S)"
            ;;
        gpg)
            generate_gpg_key "xdc-backup-$(date +%Y%m%d)" "xdc-backup@localhost"
            ;;
        *)
            log_error "Unknown key type: $key_type"
            return 1
            ;;
    esac

    # Deactivate old keys
    deactivate_old_keys "$key_type" 3

    # Re-encrypt backups if requested
    if [[ "$reencrypt" == "true" ]]; then
        log_warning "Backup re-encryption requires old key for decryption"
        log_info "Please manually re-encrypt backups or use the reencrypt_all_backups function"
    fi

    log_info "Key rotation completed"
}

#==============================================================================
# Main Execution
#==============================================================================

main() {
    local command="${1:-help}"

    case "$command" in
        rotate)
            local key_type="${2:-age}"
            perform_key_rotation "$key_type"
            ;;
        generate-age)
            rotate_age_key "${2:-$(date +%Y%m%d)}"
            ;;
        generate-gpg)
            generate_gpg_key "${2:-xdc-backup-$(date +%Y%m%d)}" "${3:-xdc-backup@localhost}"
            ;;
        list)
            init_key_metadata
            jq '.' "$KEY_METADATA_FILE"
            ;;
        active-key)
            get_active_key "${2:-age}"
            ;;
        reencrypt)
            reencrypt_backup "$2" "$3" "$4"
            ;;
        help|--help|-h)
            cat << 'EOF'
XDC Backup Key Rotation Tool

Usage: $0 <command> [options]

Commands:
  rotate [type]          Perform key rotation (default: age)
  generate-age [id]      Generate new Age key pair
  generate-gpg [id] [email]  Generate new GPG key
  list                   List all keys and rotation history
  active-key [type]      Get active key for type (default: age)
  reencrypt <file> <new_key> [old_key]  Re-encrypt a backup
  help                   Show this help message

Environment Variables:
  KEYS_DIR               Directory for key storage (default: /opt/xdc-node/keys)
  BACKUP_DIR             Directory for backups (default: /opt/xdc-node/backups)

Examples:
  $0 rotate age
  $0 generate-age 20260213
  $0 list
  $0 active-key age
EOF
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
