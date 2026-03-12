#!/bin/bash
# XDC Multi-Client Port Configuration Validator
# Issue #502: Standardize Port Configuration and Document P2P Compatibility

set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"

# Standard port allocation
declare -A STANDARD_PORTS=(
    ["geth_rpc"]=8545
    ["geth_ws"]=8546
    ["geth_p2p"]=30303
    ["erigon_rpc"]=8547
    ["erigon_ws"]=8548
    ["erigon_p2p"]=30304
    ["nethermind_rpc"]=8558
    ["nethermind_ws"]=8559
    ["nethermind_p2p"]=30306
    ["reth_rpc"]=7073
    ["reth_ws"]=7074
    ["reth_p2p"]=40303
)

# Protocol compatibility matrix
# Format: port|protocol|xdc_compatible|notes
PROTOCOL_MATRIX=(
    "30303|eth/63|yes|XDC Geth default"
    "30304|eth/63|yes|Erigon eth/63 compatible"
    "30306|eth/100|yes|Nethermind XDC protocol"
    "40303|eth/100|yes|Reth XDC protocol"
    "30311|eth/68|NO|Erigon eth/68 - NOT compatible with XDC"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" &&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" &&2; }
log_header() { echo -e "${BLUE}[*]${NC} $*"; }

# Show standard port allocation
show_port_matrix() {
    log_header "XDC Multi-Client Standard Port Allocation"
    echo ""
    printf "%-15s %-12s %-12s %-12s\n" "Client" "RPC Port" "WS Port" "P2P Port"
    printf "%-15s %-12s %-12s %-12s\n" "---------------" "----------" "----------" "----------"
    printf "%-15s %-12s %-12s %-12s\n" "XDC Geth" "${STANDARD_PORTS["geth_rpc"]}" "${STANDARD_PORTS["geth_ws"]}" "${STANDARD_PORTS["geth_p2p"]}"
    printf "%-15s %-12s %-12s %-12s\n" "Erigon" "${STANDARD_PORTS["erigon_rpc"]}" "${STANDARD_PORTS["erigon_ws"]}" "${STANDARD_PORTS["erigon_p2p"]}"
    printf "%-15s %-12s %-12s %-12s\n" "Nethermind" "${STANDARD_PORTS["nethermind_rpc"]}" "${STANDARD_PORTS["nethermind_ws"]}" "${STANDARD_PORTS["nethermind_p2p"]}"
    printf "%-15s %-12s %-12s %-12s\n" "Reth" "${STANDARD_PORTS["reth_rpc"]}" "${STANDARD_PORTS["reth_ws"]}" "${STANDARD_PORTS["reth_p2p"]}"
    echo ""
}

# Show protocol compatibility
show_protocol_matrix() {
    log_header "P2P Protocol Compatibility Matrix"
    echo ""
    printf "%-12s %-15s %-15s %-30s\n" "Port" "Protocol" "XDC Compatible" "Notes"
    printf "%-12s %-15s %-15s %-30s\n" "----------" "---------------" "---------------" "------------------------------"
    
    for entry in "${PROTOCOL_MATRIX[@]}"; do
        IFS='|' read -r port protocol compatible notes <<< "$entry"
        if [[ "$compatible" == "NO" ]]; then
            compatible="${RED}NO${NC}"
        else
            compatible="${GREEN}Yes${NC}"
        fi
        printf "%-12s %-15s %-15b %-30s\n" "$port" "$protocol" "$compatible" "$notes"
    done
    echo ""
}

# Validate P2P port compatibility
validate_p2p_port() {
    local client=$1
    local port=$2
    
    case "$client" in
        geth|xdc)
            if [[ "$port" != "30303" ]]; then
                log_warn "Non-standard P2P port for Geth: $port (standard: 30303)"
                return 1
            fi
            ;;
        erigon)
            if [[ "$port" == "30311" ]]; then
                log_error "CRITICAL: Port 30311 (eth/68) is NOT compatible with XDC Network!"
                log_error "Use port 30304 (eth/63) instead"
                return 2
            elif [[ "$port" != "30304" ]]; then
                log_warn "Non-standard P2P port for Erigon: $port (standard: 30304)"
                return 1
            fi
            ;;
        nethermind)
            if [[ "$port" != "30306" ]]; then
                log_warn "Non-standard P2P port for Nethermind: $port (standard: 30306)"
                return 1
            fi
            ;;
        reth)
            if [[ "$port" != "40303" ]]; then
                log_warn "Non-standard P2P port for Reth: $port (standard: 40303)"
                return 1
            fi
            ;;
        *)
            log_warn "Unknown client: $client"
            return 1
            ;;
    esac
    
    return 0
}

# Validate docker-compose file
validate_compose_file() {
    local file=$1
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    
    log_header "Validating: $file"
    
    local has_error=0
    
    # Check for Erigon on port 30311 (eth/68)
    if grep -q "30311:30311" "$file" 2>/dev/null || grep -q '"30311"' "$file" 2>/dev/null; then
        log_error "Found Erigon using port 30311 (eth/68) - NOT compatible with XDC!"
        has_error=1
    fi
    
    # Extract service names and their P2P ports
    # This is a simplified check - full validation would need yaml parsing
    local services
    services=$(grep -E "^\s+[a-zA-Z0-9_-]+:" "$file" | grep -v "^\s*ports:\|^\s*volumes:\|^\s*networks:\|^\s*environment:" | head -20)
    
    echo "Services found:"
    echo "$services" | sed 's/://g' | sed 's/^ */  - /'
    
    return $has_error
}

# Generate docker-compose snippet with standard ports
generate_compose_snippet() {
    local client=$1
    
    log_header "Docker Compose Configuration for $client"
    echo ""
    
    case "$client" in
        geth|xdc)
            cat << 'EOF'
  xdc-geth:
    image: xinfinorg/xdposchain:v2.6.8
    container_name: xdc-geth
    ports:
      - "8545:8545"    # RPC
      - "8546:8546"    # WebSocket
      - "0.0.0.0:30303:30303"     # P2P TCP (eth/63)
      - "0.0.0.0:30303:30303/udp" # P2P UDP
    environment:
      - RPC_PORT=8545
      - WS_PORT=8546
      - P2P_PORT=30303
EOF
            ;;
        erigon)
            cat << 'EOF'
  xdc-erigon:
    image: xinfinorg/xdc-erigon:latest
    container_name: xdc-erigon
    ports:
      - "8547:8547"    # RPC
      - "8548:8548"    # WebSocket
      - "0.0.0.0:30304:30304"     # P2P TCP (eth/63 - XDC compatible)
      - "0.0.0.0:30304:30304/udp" # P2P UDP
      # WARNING: Do NOT use port 30311 - it's eth/68 and NOT compatible with XDC!
    environment:
      - RPC_PORT=8547
      - WS_PORT=8548
      - P2P_PORT=30304
EOF
            ;;
        nethermind)
            cat << 'EOF'
  xdc-nethermind:
    image: nethermind/nethermind:latest
    container_name: xdc-nethermind
    ports:
      - "8558:8558"    # RPC
      - "8559:8559"    # WebSocket
      - "0.0.0.0:30306:30306"     # P2P TCP (eth/100)
      - "0.0.0.0:30306:30306/udp" # P2P UDP
    environment:
      - RPC_PORT=8558
      - WS_PORT=8559
      - P2P_PORT=30306
EOF
            ;;
        reth)
            cat << 'EOF'
  xdc-reth:
    image: xinfinorg/xdc-reth:latest
    container_name: xdc-reth
    ports:
      - "7073:7073"    # RPC
      - "7074:7074"    # WebSocket
      - "0.0.0.0:40303:40303"     # P2P TCP (eth/100)
      - "0.0.0.0:40303:40303/udp" # P2P UDP
    environment:
      - RPC_PORT=7073
      - WS_PORT=7074
      - P2P_PORT=40303
EOF
            ;;
        *)
            log_error "Unknown client: $client"
            return 1
            ;;
    esac
    echo ""
}

# Check if a port is in use
check_port_usage() {
    local port=$1
    
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i :"$port" >/dev/null 2>&1; then
            log_warn "Port $port is already in use"
            lsof -i :"$port" 2>/dev/null | grep -v COMMAND || true
            return 1
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":$port "; then
            log_warn "Port $port is already in use"
            return 1
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_warn "Port $port is already in use"
            return 1
        fi
    fi
    
    return 0
}

# Run full validation on the system
run_system_check() {
    log_header "Running System Port Check"
    echo ""
    
    local all_ports_free=true
    
    log_info "Checking standard XDC ports..."
    for key in "${!STANDARD_PORTS[@]}"; do
        local port="${STANDARD_PORTS[$key]}"
        if ! check_port_usage "$port"; then
            all_ports_free=false
        fi
    done
    
    echo ""
    if [[ "$all_ports_free" == true ]]; then
        log_info "All standard ports are available"
    else
        log_warn "Some standard ports are in use - review the configuration"
    fi
    
    return 0
}

# Show help
show_help() {
    echo "XDC Multi-Client Port Configuration Validator v$SCRIPT_VERSION"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  matrix                  Show standard port allocation matrix"
    echo "  protocols               Show P2P protocol compatibility matrix"
    echo "  validate <file>         Validate docker-compose file"
    echo "  generate <client>       Generate docker-compose snippet for client"
    echo "  check                   Run system port availability check"
    echo "  validate-p2p <client> <port>  Validate P2P port for client"
    echo ""
    echo "Clients: geth, erigon, nethermind, reth"
    echo ""
    echo "Examples:"
    echo "  $0 matrix"
    echo "  $0 validate docker-compose.yml"
    echo "  $0 generate erigon"
    echo "  $0 validate-p2p erigon 30304"
}

# CLI interface
case "${1:-}" in
    matrix)
        show_port_matrix
        ;;
    protocols)
        show_protocol_matrix
        ;;
    validate)
        if [[ -z "${2:-}" ]]; then
            log_error "Usage: $0 validate <docker-compose-file>"
            exit 1
        fi
        validate_compose_file "$2"
        ;;
    generate)
        if [[ -z "${2:-}" ]]; then
            log_error "Usage: $0 generate <client>"
            exit 1
        fi
        generate_compose_snippet "$2"
        ;;
    check)
        run_system_check
        ;;
    validate-p2p)
        if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]]; then
            log_error "Usage: $0 validate-p2p <client> <port>"
            exit 1
        fi
        if validate_p2p_port "$2" "$3"; then
            log_info "Port $3 is valid for $2"
        else
            exit 1
        fi
        ;;
    *)
        show_help
        exit 1
        ;;
esac
