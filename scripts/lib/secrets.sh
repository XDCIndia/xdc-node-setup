#!/usr/bin/env bash
#==============================================================================
# Secrets Management Script for XDC Nodes
# Supports: Docker Secrets, Environment Variables, File-based Secrets
# Features: Secret rotation, encryption, validation
#==============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="${SCRIPT_DIR}/lib"

# Source libraries
# shellcheck source=/dev/null
source "${LIB_DIR}/logging.sh" 2>/dev/null || {
    log_info() { echo "[INFO] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
}

# Default paths
readonly SECRETS_DIR="${SECRETS_DIR:-/run/secrets}"
readonly CONFIG_SECRETS_DIR="${CONFIG_SECRETS_DIR:-/opt/xdc-node/secrets}"
readonly ENV_FILE="${ENV_FILE:-/opt/xdc-node/.env}"

#==============================================================================
# Secret Resolution Functions
#==============================================================================

# Resolve a secret from various sources in priority order:
# 1. Docker Secrets (/run/secrets/)
# 2. Environment variable
# 3. File-based secret
# Usage: resolve_secret "SECRET_NAME" [default_value]
resolve_secret() {
    local secret_name="$1"
    local default_value="${2:-}"
    local value=""

    # Try Docker Secrets first
    if [[ -f "${SECRETS_DIR}/${secret_name}" ]]; then
        value=$(cat "${SECRETS_DIR}/${secret_name}")
        log_info "Resolved secret from Docker Secrets" "{\"secret\":\"${secret_name}\"}"
        echo "$value"
        return 0
    fi

    # Try environment variable
    if [[ -n "${!secret_name:-}" ]]; then
        value="${!secret_name}"
        log_info "Resolved secret from environment" "{\"secret\":\"${secret_name}\"}"
        echo "$value"
        return 0
    fi

    # Try file-based secret
    if [[ -f "${CONFIG_SECRETS_DIR}/${secret_name}" ]]; then
        value=$(cat "${CONFIG_SECRETS_DIR}/${secret_name}")
        log_info "Resolved secret from file" "{\"secret\":\"${secret_name}\"}"
        echo "$value"
        return 0
    fi

    # Return default value if provided
    if [[ -n "$default_value" ]]; then
        log_info "Using default value for secret" "{\"secret\":\"${secret_name}\"}"
        echo "$default_value"
        return 0
    fi

    log_error "Secret not found" "{\"secret\":\"${secret_name}\"}"
    return 1
}

# Check if a secret exists in any source
# Usage: secret_exists "SECRET_NAME"
secret_exists() {
    local secret_name="$1"

    if [[ -f "${SECRETS_DIR}/${secret_name}" ]]; then
        return 0
    fi

    if [[ -n "${!secret_name:-}" ]]; then
        return 0
    fi

    if [[ -f "${CONFIG_SECRETS_DIR}/${secret_name}" ]]; then
        return 0
    fi

    return 1
}

# Get the source of a secret
# Usage: get_secret_source "SECRET_NAME"
get_secret_source() {
    local secret_name="$1"

    if [[ -f "${SECRETS_DIR}/${secret_name}" ]]; then
        echo "docker-secret"
        return 0
    fi

    if [[ -n "${!secret_name:-}" ]]; then
        echo "environment"
        return 0
    fi

    if [[ -f "${CONFIG_SECRETS_DIR}/${secret_name}" ]]; then
        echo "file"
        return 0
    fi

    echo "not-found"
    return 1
}

#==============================================================================
# Secret Management Functions
#==============================================================================

# Create a Docker Secret (requires swarm mode or external secret provider)
# Usage: create_docker_secret "SECRET_NAME" "secret_value"
create_docker_secret() {
    local secret_name="$1"
    local secret_value="$2"

    if ! command -v docker &>/dev/null; then
        log_error "Docker not found"
        return 1
    fi

    # Check if secret already exists
    if docker secret inspect "$secret_name" >/dev/null 2>&1; then
        log_info "Docker secret already exists, removing old version" "{\"secret\":\"${secret_name}\"}"
        docker secret rm "$secret_name" >/dev/null 2>&1 || true
    fi

    # Create new secret
    echo "$secret_value" | docker secret create "$secret_name" - >/dev/null
    log_info "Created Docker secret" "{\"secret\":\"${secret_name}\"}"
}

# Create a file-based secret
# Usage: create_file_secret "SECRET_NAME" "secret_value"
create_file_secret() {
    local secret_name="$1"
    local secret_value="$2"

    # Ensure secrets directory exists
    mkdir -p "$CONFIG_SECRETS_DIR"
    chmod 700 "$CONFIG_SECRETS_DIR"

    local secret_file="${CONFIG_SECRETS_DIR}/${secret_name}"

    # Write secret with restricted permissions
    echo -n "$secret_value" > "$secret_file"
    chmod 600 "$secret_file"

    log_info "Created file secret" "{\"secret\":\"${secret_name}\",\"path\":\"${secret_file}\"}"
}

# Encrypt a secret using age encryption
# Usage: encrypt_secret "secret_value" "recipient_public_key"
encrypt_secret() {
    local secret_value="$1"
    local recipient_key="$2"

    if ! command -v age &>/dev/null; then
        log_error "age encryption tool not found"
        return 1
    fi

    echo "$secret_value" | age -r "$recipient_key" 2>/dev/null
}

# Decrypt a secret using age
# Usage: decrypt_secret "encrypted_value" [identity_file]
decrypt_secret() {
    local encrypted_value="$1"
    local identity_file="${2:-${CONFIG_SECRETS_DIR}/age.key}"

    if ! command -v age &>/dev/null; then
        log_error "age encryption tool not found"
        return 1
    fi

    if [[ ! -f "$identity_file" ]]; then
        log_error "Age identity file not found" "{\"path\":\"${identity_file}\"}"
        return 1
    fi

    echo "$encrypted_value" | age -d -i "$identity_file" 2>/dev/null
}

# Generate a new age key pair for secret encryption
generate_age_keypair() {
    local key_dir="${1:-$CONFIG_SECRETS_DIR}"

    mkdir -p "$key_dir"
    chmod 700 "$key_dir"

    local identity_file="${key_dir}/age.key"
    local public_key_file="${key_dir}/age.pub"

    if ! command -v age-keygen &>/dev/null; then
        log_error "age-keygen not found"
        return 1
    fi

    age-keygen -o "$identity_file" 2>&1 | grep "public key" | cut -d: -f2 | tr -d ' ' > "$public_key_file"
    chmod 600 "$identity_file"
    chmod 644 "$public_key_file"

    log_info "Generated age keypair" "{\"identity\":\"${identity_file}\",\"public_key\":\"${public_key_file}\"}"
}

#==============================================================================
# Secret Rotation Functions
#==============================================================================

# Rotate a secret
# Usage: rotate_secret "SECRET_NAME" "new_value" [source_type]
rotate_secret() {
    local secret_name="$1"
    local new_value="$2"
    local source_type="${3:-file}"

    local old_source
    old_source=$(get_secret_source "$secret_name")

    log_info "Rotating secret" "{\"secret\":\"${secret_name}\",\"old_source\":\"${old_source}\",\"new_source\":\"${source_type}\"}"

    case "$source_type" in
        docker)
            create_docker_secret "$secret_name" "$new_value"
            ;;
        file)
            create_file_secret "$secret_name" "$new_value"
            ;;
        env)
            log_error "Cannot rotate environment secrets - please update manually"
            return 1
            ;;
        *)
            log_error "Unknown source type: $source_type"
            return 1
            ;;
    esac

    log_info "Secret rotated successfully" "{\"secret\":\"${secret_name}\"}"
}

# Rotate all secrets (batch operation)
# Usage: rotate_all_secrets "rotation_config.json"
rotate_all_secrets() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        log_error "Rotation config file not found" "{\"path\":\"${config_file}\"}"
        return 1
    fi

    local secrets
    secrets=$(jq -c '.secrets[]' "$config_file")

    while IFS= read -r secret_config; do
        local name
        local value
        local source_type

        name=$(echo "$secret_config" | jq -r '.name')
        value=$(echo "$secret_config" | jq -r '.value')
        source_type=$(echo "$secret_config" | jq -r '.source // "file"')

        rotate_secret "$name" "$value" "$source_type"
    done <<< "$secrets"
}

#==============================================================================
# Validation Functions
#==============================================================================

# Validate all required secrets are present
# Usage: validate_secrets "secret1" "secret2" ...
validate_secrets() {
    local missing=()

    for secret_name in "$@"; do
        if ! secret_exists "$secret_name"; then
            missing+=("$secret_name")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required secrets" "{\"secrets\":[$(printf '"%s",' "${missing[@]}" | sed 's/,$//')]}"
        return 1
    fi

    log_info "All required secrets validated"
    return 0
}

# Check secret permissions
# Usage: check_secret_permissions
check_secret_permissions() {
    local issues=()

    # Check Docker secrets
    if [[ -d "$SECRETS_DIR" ]]; then
        while IFS= read -r -d '' file; do
            local perms
            perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%Lp" "$file")
            if [[ "$perms" != "600" && "$perms" != "400" ]]; then
                issues+=("Docker secret $file has permissions $perms (should be 600 or 400)")
            fi
        done < <(find "$SECRETS_DIR" -type f -print0 2>/dev/null)
    fi

    # Check file secrets
    if [[ -d "$CONFIG_SECRETS_DIR" ]]; then
        while IFS= read -r -d '' file; do
            local perms
            perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%Lp" "$file")
            if [[ "$perms" != "600" ]]; then
                issues+=("File secret $file has permissions $perms (should be 600)")
            fi
        done < <(find "$CONFIG_SECRETS_DIR" -type f ! -name "*.pub" -print0 2>/dev/null)
    fi

    if [[ ${#issues[@]} -gt 0 ]]; then
        log_error "Secret permission issues found"
        printf '%s\n' "${issues[@]}" >&2
        return 1
    fi

    log_info "All secret permissions are correct"
    return 0
}

#==============================================================================
# Export Functions
#==============================================================================

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f resolve_secret
    export -f secret_exists
    export -f get_secret_source
    export -f create_docker_secret
    export -f create_file_secret
    export -f encrypt_secret
    export -f decrypt_secret
    export -f generate_age_keypair
    export -f rotate_secret
    export -f rotate_all_secrets
    export -f validate_secrets
    export -f check_secret_permissions
fi
