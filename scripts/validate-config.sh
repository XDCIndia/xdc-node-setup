#!/bin/bash

# Source utility functions
source "$(dirname "$0")/lib/utils.sh" || { echo "Failed to load utils"; exit 1; }

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }
#==============================================================================
#==============================================================================
# Configuration Validator for XDC Node Setup
# Validates JSON configuration files against schema
# Dependencies: jq, python3 (for jsonschema)
#==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCHEMA_FILE="${SCRIPT_DIR}/../configs/schema.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'


success() {
    echo -e "${GREEN}✓ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Check dependencies
check_deps() {
    local missing=()
    
    if ! command -v jq >/dev/null 2>&1; then
        missing+=("jq")
    fi
    
    if ! python3 -c "import jsonschema" 2>/dev/null; then
        missing+=("python3-jsonschema")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing dependencies: ${missing[*]}"
        echo "Install with: sudo apt-get install jq python3-jsonschema"
        exit 1
    fi
}

# Validate JSON syntax
validate_json_syntax() {
    local file="$1"
    
    if ! jq empty "$file" 2>&1; then
        error "Invalid JSON syntax in $file"
        return 1
    fi
    
    return 0
}

# Validate against JSON Schema
validate_schema() {
    local file="$1"
    local schema="${2:-$SCHEMA_FILE}"
    
    if [[ ! -f "$schema" ]]; then
        error "Schema file not found: $schema"
        return 1
    fi
    
    python3 <<EOF
import json
import jsonschema
import sys

try:
    with open('$file', 'r') as f:
        config = json.load(f)
    
    with open('$schema', 'r') as f:
        schema = json.load(f)
    
    # Validate
    validator = jsonschema.Draft7Validator(schema)
    errors = list(validator.iter_errors(config))
    
    if errors:
        print(f"Validation failed with {len(errors)} error(s):")
        for error in errors:
            path = '/'.join(str(p) for p in error.path) or 'root'
            print(f"  - {path}: {error.message}")
        sys.exit(1)
    else:
        print("✓ Schema validation passed")
        sys.exit(0)
except Exception as e:
    print(f"Validation error: {e}")
    sys.exit(1)
EOF

    return $?
}

# Validate configuration values (semantic validation)
validate_semantics() {
    local file="$1"
    local errors=0
    
    # Extract values using jq
    local data_dir
    data_dir=$(jq -r '.node.dataDir // empty' "$file")
    
    if [[ -n "$data_dir" ]]; then
        if [[ "${data_dir:0:1}" != "/" ]]; then
            error "dataDir must be an absolute path"
            ((errors++))
        fi
        if [[ "$data_dir" == *".."* ]]; then
            error "dataDir cannot contain parent directory references"
            ((errors++))
        fi
    fi
    
    # Validate RPC port doesn't conflict with P2P port
    local rpc_port p2p_port
    rpc_port=$(jq -r '.rpc.port // 8545' "$file")
    p2p_port=$(jq -r '.p2p.port // 30303' "$file")
    
    if [[ "$rpc_port" == "$p2p_port" ]]; then
        error "RPC port and P2P port cannot be the same"
        ((errors++))
    fi
    
    # Validate retention policy makes sense
    local daily weekly monthly
    daily=$(jq -r '.backup.retention.daily // 7' "$file")
    weekly=$(jq -r '.backup.retention.weekly // 4' "$file")
    monthly=$(jq -r '.backup.retention.monthly // 12' "$file")
    
    local total_retention=$((daily + weekly * 7 + monthly * 30))
    if [[ $total_retention -gt 730 ]]; then
        warn "Backup retention period exceeds 2 years ($total_retention days)"
    fi
    
    return $errors
}

# Generate sample configuration
generate_sample() {
    cat <<'EOF'
{
  "network": "mainnet",
  "node": {
    "type": "full",
    "syncMode": "snap",
    "dataDir": "/opt/xdc-node/data",
    "cacheSize": 4096
  },
  "rpc": {
    "enabled": true,
    "host": "127.0.0.1",
    "port": 8545,
    "apis": ["eth", "net", "web3", "XDPoS"],
    "cors": ["*"],
    "authentication": {
      "enabled": false
    }
  },
  "p2p": {
    "port": 30303,
    "maxPeers": 50,
    "discovery": true
  },
  "monitoring": {
    "enabled": true,
    "prometheusPort": 6060,
    "metrics": ["system", "chain", "network"]
  },
  "logging": {
    "level": "info",
    "format": "json",
    "output": "both",
    "file": "/var/log/xdc-node/xdc-node.log",
    "maxSize": 100,
    "maxBackups": 5
  },
  "security": {
    "firewall": {
      "enabled": true,
      "allowedPorts": [22, 8545, 30303]
    },
    "fail2ban": {
      "enabled": true,
      "maxRetries": 5,
      "banTime": 3600
    }
  },
  "backup": {
    "enabled": true,
    "schedule": "0 3 * * *",
    "retention": {
      "daily": 7,
      "weekly": 4,
      "monthly": 12
    },
    "encryption": {
      "enabled": true
    }
  },
  "notifications": {
    "channels": ["telegram"],
    "alerts": {
      "nodeOffline": true,
      "syncBehind": true,
      "diskSpace": true
    }
  }
}
EOF
}

# Main validation function
main() {
    local command="${1:-validate}"
    local config_file="${2:-}"
    
    check_deps
    
    case "$command" in
        validate)
            if [[ -z "$config_file" ]]; then
                error "Usage: $0 validate <config-file>"
                exit 1
            fi
            
            if [[ ! -f "$config_file" ]]; then
                error "Config file not found: $config_file"
                exit 1
            fi
            
            echo "Validating $config_file..."
            
            if ! validate_json_syntax "$config_file"; then
                exit 1
            fi
            
            if ! validate_schema "$config_file"; then
                exit 1
            fi
            
            if ! validate_semantics "$config_file"; then
                exit 1
            fi
            
            success "Configuration is valid!"
            ;;
            
        sample)
            generate_sample
            ;;
            
        schema)
            if [[ -f "$SCHEMA_FILE" ]]; then
                cat "$SCHEMA_FILE"
            else
                error "Schema file not found: $SCHEMA_FILE"
                exit 1
            fi
            ;;
            
        *)
            echo "Usage: $0 {validate <file>|sample|schema}"
            exit 1
            ;;
    esac
}

main "$@"
