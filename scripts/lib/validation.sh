#!/bin/bash
# Input Validation Library for XDC Node Setup
# Fixes #392 - Security Hardening: Input Validation and Command Sanitization

# Validate port number
validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
        log_error "Invalid port: $port (must be 1024-65535)"
        return 1
    fi
    return 0
}

# Validate path (prevent directory traversal)
validate_path() {
    local path="$1"
    
    # Prevent directory traversal
    if [[ "$path" =~ \.\. ]]; then
        log_error "Path contains invalid characters: $path"
        return 1
    fi
    
    # Resolve to absolute path
    if ! realpath -m "$path" > /dev/null 2>&1; then
        log_error "Invalid path: $path"
        return 1
    fi
    
    return 0
}

# Validate URL
validate_url() {
    local url="$1"
    
    # Check if URL starts with http:// or https://
    if ! [[ "$url" =~ ^https?:// ]]; then
        log_error "Invalid URL: $url (must start with http:// or https://)"
        return 1
    fi
    
    # Basic URL validation
    if ! [[ "$url" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$ ]]; then
        log_error "Malformed URL: $url"
        return 1
    fi
    
    return 0
}

# Validate IP address
validate_ip() {
    local ip="$1"
    
    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_error "Invalid IP address: $ip"
        return 1
    fi
    
    # Check each octet
    IFS='.' read -ra OCTETS <<< "$ip"
    for octet in "${OCTETS[@]}"; do
        if [ "$octet" -gt 255 ]; then
            log_error "Invalid IP address: $ip (octet > 255)"
            return 1
        fi
    done
    
    return 0
}

# Validate node ID (UUID format)
validate_node_id() {
    local node_id="$1"
    
    if ! [[ "$node_id" =~ ^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$ ]]; then
        log_error "Invalid node ID: $node_id (must be UUID format)"
        return 1
    fi
    
    return 0
}

# Validate Ethereum address
validate_eth_address() {
    local address="$1"
    
    if ! [[ "$address" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        log_error "Invalid Ethereum address: $address"
        return 1
    fi
    
    return 0
}

# Validate network choice
validate_network() {
    local network="$1"
    local valid_networks=("mainnet" "testnet" "devnet" "apothem")
    
    for valid in "${valid_networks[@]}"; do
        if [[ "$network" == "$valid" ]]; then
            return 0
        fi
    done
    
    log_error "Invalid network: $network (must be one of: ${valid_networks[*]})"
    return 1
}

# Validate client type
validate_client() {
    local client="$1"
    local valid_clients=("geth" "geth-pr5" "erigon" "nethermind" "reth")
    
    for valid in "${valid_clients[@]}"; do
        if [[ "$client" == "$valid" ]]; then
            return 0
        fi
    done
    
    log_error "Invalid client: $client (must be one of: ${valid_clients[*]})"
    return 1
}

# Sanitize input string (remove dangerous characters)
sanitize_input() {
    local input="$1"
    
    # Remove shell meta-characters
    input="${input//[;&|<>$`\\]/}"
    
    # Remove quotes
    input="${input//[\"\\']/}"
    
    echo "$input"
}

# Validate numeric range
validate_range() {
    local value="$1"
    local min="$2"
    local max="$3"
    local name="${4:-value}"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        log_error "$name must be a number: $value"
        return 1
    fi
    
    if [ "$value" -lt "$min" ] || [ "$value" -gt "$max" ]; then
        log_error "$name out of range: $value (must be $min-$max)"
        return 1
    fi
    
    return 0
}

# Logging function (if not already defined)
if ! type log_error &>/dev/null; then
    log_error() {
        echo "❌ ERROR: $*" >&2
    }
fi
