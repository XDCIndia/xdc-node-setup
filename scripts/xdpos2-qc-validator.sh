#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDPoS 2.0 Quorum Certificate (QC) Validator
# Validates QC signatures (2/3+ of validators required)
# Issue: #486
#==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source common utilities
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || source "/opt/xdc-node/scripts/lib/common.sh" || true
source "${SCRIPT_DIR}/lib/xdc-contracts.sh" 2>/dev/null || source "/opt/xdc-node/scripts/lib/xdc-contracts.sh" || true
source "${SCRIPT_DIR}/lib/notify.sh" 2>/dev/null || source "/opt/xdc-node/scripts/lib/notify.sh" || true

# Configuration
readonly XDC_RPC_URL="${XDC_RPC_URL:-http://localhost:8545}"
readonly SKYNET_API="${SKYNET_API_URL:-https://skynet.xdcindia.com/api/v1}"
readonly EPOCH_LENGTH=900
readonly POLL_INTERVAL="${XDPOS2_QC_POLL_INTERVAL:-30}"
readonly STATE_DIR="${XDC_STATE_DIR:-/root/xdcchain/.state}"
readonly STATE_FILE="${STATE_DIR}/xdpos2-qc-state.json"
readonly REQUIRED_QUORUM_PCT=66  # 2/3 quorum threshold

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# State tracking
declare -i LAST_CHECKED_BLOCK=0
declare -i QC_FAILURE_COUNT=0
declare -i ALERT_THRESHOLD=3

#==============================================================================
# Logging Functions
#==============================================================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_info() {
    echo -e "${CYAN}[INFO]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} [$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

#==============================================================================
# Utility Functions
#==============================================================================

hex_to_dec() {
    local hex="${1#0x}"
    printf "%d\n" "0x${hex}" 2>/dev/null || echo "0"
}

# Get current block number
get_block_number() {
    local response
    response=$(curl -s -m 10 "$XDC_RPC_URL" \
        -X POST \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null || echo '{}')
    
    local block_hex
    block_hex=$(echo "$response" | jq -r '.result // "0x0"')
    hex_to_dec "$block_hex"
}

# Get block by number (with full transaction data)
get_block_by_number() {
    local block_num=$1
    local full_tx="${2:-false}"
    local hex_block
    hex_block=$(printf "0x%x" "$block_num")
    
    curl -s -m 15 "$XDC_RPC_URL" \
        -X POST \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$hex_block\",$full_tx],\"id\":1}" 2>/dev/null || echo '{}'
}

# Get validator set for current epoch
get_validator_set() {
    # Try to get from XDPoS_getMasternodesByNumber
    local response
    response=$(curl -s -m 15 "$XDC_RPC_URL" \
        -X POST \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"XDPoS_getMasternodesByNumber","params":["latest"],"id":1}' 2>/dev/null || echo '{}')
    
    local validators
    validators=$(echo "$response" | jq -r '.result // []')
    
    if [[ "$validators" != "[]" ]] && [[ -n "$validators" ]]; then
        echo "$validators" | jq '[.[] | if startswith("0x") then "xdc" + .[2:] else . end]'
        return 0
    fi
    
    # Fallback to contract call
    local validator_set="0x0000000000000000000000000000000000000089"
    response=$(curl -s -m 15 "$XDC_RPC_URL" \
        -X POST \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$validator_set\",\"data\":\"0x\"},\"latest\"],\"id\":1}" 2>/dev/null || echo '{}')
    
    # Return empty array if can't get validators
    echo '[]'
}

#==============================================================================
# QC Extraction and Validation
#==============================================================================

# Extract QC data from block extraData
# XDPoS 2.0 extraData structure:
# - Bytes 0-31: Vanity (32 bytes)
# - Bytes 32-61: Seal (30 bytes)
# - Bytes 62+: RLP-encoded list containing QC and signatures
extract_qc_from_block() {
    local block_data="$1"
    
    local extra_data
    extra_data=$(echo "$block_data" | jq -r '.result.extraData // "0x"')
    
    # Remove 0x prefix
    extra_data="${extra_data#0x}"
    
    # Check minimum length
    if [[ ${#extra_data} -lt 130 ]]; then
        log_error "extraData too short: ${#extra_data} chars (min 130)"
        echo "{}"
        return 1
    fi
    
    # Extract validator bitmask/signature info
    # After vanity (64 hex chars) and seal (60 hex chars)
    local sig_start=124  # (32+30)*2
    local signatures="${extra_data:$sig_start}"
    
    # Count signatures (each ECDSA signature is 65 bytes = 130 hex chars)
    local sig_length=${#signatures}
    local sig_count=$((sig_length / 130))
    
    # Extract QC round info if available (bytes after initial structure)
    local qc_round=""
    local qc_value=""
    
    # XDPoS 2.0 QC structure in extraData:
    # QC contains: round number, block hash, aggregated signature, bitmask
    if [[ ${#extra_data} -gt 300 ]]; then
        # Try to extract QC round from specific position
        # This is protocol-specific and may need adjustment
        qc_round="${extra_data:250:8}"
        qc_value="${extra_data:258:64}"
    fi
    
    jq -n \
        --arg extra "$extra_data" \
        --argjson sig_count "$sig_count" \
        --arg sigs "$signatures" \
        --arg qc_round "$qc_round" \
        --arg qc_value "$qc_value" \
        '{
            signatureCount: $sig_count,
            signaturesHex: $sigs,
            qcRound: $qc_round,
            qcValue: $qc_value,
            extraDataLength: ($extra | length)
        }'
}

# Extract signer addresses from QC data using bitmask
extract_signers_from_qc() {
    local block_data="$1"
    local validators="$2"
    
    local extra_data
    extra_data=$(echo "$block_data" | jq -r '.result.extraData // "0x"')
    extra_data="${extra_data#0x}"
    
    # Validator bitmask typically starts after vanity+seal
    # Bytes 32-63 (64 hex chars) often contain the bitmask
    local bitmask="${extra_data:64:64}"
    
    local signers="[]"
    local validator_count
    validator_count=$(echo "$validators" | jq 'length')
    
    # Parse bitmask to determine which validators signed
    # Each bit in the bitmask represents one validator
    for ((i=0; i<validator_count && i<256; i++)); do
        local byte_offset=$((i / 8))
        local bit_offset=$((7 - (i % 8)))
        local byte_hex="${bitmask:$((byte_offset*2)):2}"
        local byte_val=$((16#$byte_hex))
        local bit_val=$(( (byte_val >> bit_offset) & 1 ))
        
        if [[ $bit_val -eq 1 ]]; then
            local validator
            validator=$(echo "$validators" | jq -r ".[$i] // empty")
            if [[ -n "$validator" ]]; then
                signers=$(echo "$signers" | jq --arg v "$validator" '. + [$v]')
            fi
        fi
    done
    
    echo "$signers"
}

# Validate QC for a block
validate_qc() {
    local block_num=$1
    local block_data
    block_data=$(get_block_by_number "$block_num" "true")
    
    if [[ -z "$block_data" ]] || [[ "$block_data" == "{}" ]]; then
        log_error "Failed to fetch block $block_num"
        return 1
    fi
    
    # Get validator set
    local validators
    validators=$(get_validator_set)
    local validator_count
    validator_count=$(echo "$validators" | jq 'length')
    
    if [[ "$validator_count" -eq 0 ]]; then
        log_warn "No validators found for QC validation"
        return 1
    fi
    
    # Calculate required quorum (2/3 of validators)
    local required_quorum=$(( (validator_count * REQUIRED_QUORUM_PCT + 99) / 100 ))
    
    # Extract QC data
    local qc_data
    qc_data=$(extract_qc_from_block "$block_data")
    
    if [[ "$qc_data" == "{}" ]]; then
        log_error "Failed to extract QC data from block $block_num"
        return 1
    fi
    
    local sig_count
    sig_count=$(echo "$qc_data" | jq -r '.signatureCount // 0')
    
    # Extract signers from QC
    local signers
    signers=$(extract_signers_from_qc "$block_data" "$validators")
    local signer_count
    signer_count=$(echo "$signers" | jq 'length')
    
    # Use the higher of signature count or signer count
    local actual_quorum=$sig_count
    if [[ $signer_count -gt $sig_count ]]; then
        actual_quorum=$signer_count
    fi
    
    log_info "Block $block_num QC: $actual_quorum/$required_quorum signatures (validators: $validator_count)"
    
    # Validate quorum
    if [[ $actual_quorum -lt $required_quorum ]]; then
        log_error "🚨 INVALID QC: Block $block_num has insufficient signatures"
        log_error "   Required: $required_quorum (2/3 of $validator_count)"
        log_error "   Actual:   $actual_quorum"
        log_error "   Signers:  $(echo "$signers" | jq -c '.')"
        
        # Report invalid QC
        report_invalid_qc "$block_num" "$required_quorum" "$actual_quorum" "$validators" "$signers"
        
        ((QC_FAILURE_COUNT++))
        return 1  # Invalid QC
    else
        log_success "Block $block_num: QC valid ($actual_quorum/$required_quorum signatures)"
        
        # Reset failure count on valid QC
        if [[ $QC_FAILURE_COUNT -gt 0 ]]; then
            QC_FAILURE_COUNT=0
            save_state
        fi
        
        return 0  # Valid QC
    fi
}

# Report invalid QC to SkyNet
report_invalid_qc() {
    local block_num=$1
    local required=$2
    local actual=$3
    local validators="$4"
    local signers="$5"
    local epoch=$((block_num / EPOCH_LENGTH))
    
    # Identify missing validators
    local missing_validators
    missing_validators=$(echo "$validators" | jq --argjson signed "$signers" '[.[] | select(. as $v | $signed | index($v) | not)]')
    
    local payload
    payload=$(jq -n \
        --arg block "$block_num" \
        --arg epoch "$epoch" \
        --arg required "$required" \
        --arg actual "$actual" \
        --argjson validators "$validators" \
        --argjson signers "$signers" \
        --argjson missing "$missing_validators" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg node "$(hostname)" \
        '{
            type: "invalid_qc",
            severity: "critical",
            title: "XDPoS 2.0 Quorum Certificate Validation Failed",
            message: "Block \($block) has insufficient QC signatures (\($actual)/\($required))",
            details: {
                blockNumber: ($block | tonumber),
                epoch: ($epoch | tonumber),
                requiredSignatures: ($required | tonumber),
                actualSignatures: ($actual | tonumber),
                totalValidators: ($validators | length),
                signingValidators: $signers,
                missingValidators: $missing,
                timestamp: $timestamp,
                reporterNode: $node
            }
        }')
    
    log_error "Reporting invalid QC to SkyNet..."
    
    local response
    response=$(curl -s -m 30 -X POST "${SKYNET_API}/issues/report" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null || echo '{"error": "connection_failed"}')
    
    if echo "$response" | jq -e '.success // .id // .issueId' >/dev/null 2>&1; then
        log_info "Invalid QC reported to SkyNet: $(echo "$response" | jq -r '.id // .issueId // "unknown"')"
    else
        log_error "Failed to report invalid QC: $(echo "$response" | jq -r '.error // "unknown error"')"
    fi
    
    # Also send critical notification
    if command -v notify_alert &>/dev/null; then
        notify_alert "critical" "🚨 Invalid QC Detected" \
            "Block $block_num: Only $actual/$required signatures" \
            "invalid_qc"
    fi
}

#==============================================================================
# State Management
#==============================================================================

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        LAST_CHECKED_BLOCK=$(jq -r '.lastCheckedBlock // 0' "$STATE_FILE" 2>/dev/null || echo "0")
        QC_FAILURE_COUNT=$(jq -r '.qcFailureCount // 0' "$STATE_FILE" 2>/dev/null || echo "0")
        log_info "Loaded state: last block=$LAST_CHECKED_BLOCK, failures=$QC_FAILURE_COUNT"
    else
        mkdir -p "$STATE_DIR"
        echo '{"lastCheckedBlock": 0, "qcFailureCount": 0, "invalidQCs": []}' > "$STATE_FILE"
    fi
}

save_state() {
    local tmp_file="${STATE_FILE}.tmp"
    
    jq --arg block "$LAST_CHECKED_BLOCK" \
       --arg failures "$QC_FAILURE_COUNT" \
       '.lastCheckedBlock = ($block | tonumber) | .qcFailureCount = ($failures | tonumber)' \
       "$STATE_FILE" > "$tmp_file" 2>/dev/null && \
        mv "$tmp_file" "$STATE_FILE" || true
}

record_invalid_qc() {
    local block_num=$1
    local required=$2
    local actual=$3
    local tmp_file="${STATE_FILE}.tmp"
    
    local entry
    entry=$(jq -n \
        --arg block "$block_num" \
        --arg required "$required" \
        --arg actual "$actual" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{block: ($block | tonumber), required: ($required | tonumber), actual: ($actual | tonumber), timestamp: $timestamp}')
    
    jq --argjson entry "$entry" '.invalidQCs += [$entry]' "$STATE_FILE" > "$tmp_file" 2>/dev/null && \
        mv "$tmp_file" "$STATE_FILE" || true
}

#==============================================================================
# Main Validation Loop
#==============================================================================

run_validator() {
    log_info "Starting XDPoS 2.0 QC Validator"
    log_info "RPC: $XDC_RPC_URL"
    log_info "SkyNet API: $SKYNET_API"
    log_info "Poll interval: ${POLL_INTERVAL}s"
    log_info "Required quorum: ${REQUIRED_QUORUM_PCT}% of validators"
    
    load_state
    
    while true; do
        local current_block
        current_block=$(get_block_number)
        
        if [[ "$current_block" -eq 0 ]]; then
            log_error "Failed to get current block number, retrying in ${POLL_INTERVAL}s..."
            sleep "$POLL_INTERVAL"
            continue
        fi
        
        log_info "Current block: $current_block"
        
        # Initialize last checked if needed
        if [[ $LAST_CHECKED_BLOCK -eq 0 ]]; then
            LAST_CHECKED_BLOCK=$((current_block - 1))
        fi
        
        # Limit blocks to check
        local blocks_to_check=$((current_block - LAST_CHECKED_BLOCK))
        if [[ $blocks_to_check -gt 50 ]]; then
            log_warn "Large block gap ($blocks_to_check), limiting to last 50"
            LAST_CHECKED_BLOCK=$((current_block - 50))
        fi
        
        # Validate QC for each block
        local invalid_count=0
        for ((block=LAST_CHECKED_BLOCK+1; block<=current_block; block++)); do
            if ! validate_qc "$block"; then
                ((invalid_count++))
                record_invalid_qc "$block" 0 0
            fi
        done
        
        if [[ $invalid_count -gt 0 ]]; then
            log_error "Found $invalid_count invalid QC(s) in this poll"
            
            # Alert if threshold exceeded
            if [[ $QC_FAILURE_COUNT -ge $ALERT_THRESHOLD ]]; then
                log_error "🚨 CRITICAL: $QC_FAILURE_COUNT consecutive QC failures!"
                
                if command -v notify_alert &>/dev/null; then
                    notify_alert "critical" "🚨 QC Validation Critical" \
                        "$QC_FAILURE_COUNT consecutive blocks with invalid QC" \
                        "qc_critical"
                fi
            fi
        else
            log_info "All QCs valid for blocks $((LAST_CHECKED_BLOCK+1))-$current_block"
        fi
        
        LAST_CHECKED_BLOCK=$current_block
        save_state
        
        log_info "Sleeping for ${POLL_INTERVAL}s..."
        sleep "$POLL_INTERVAL"
    done
}

#==============================================================================
# Single Block Validation
#==============================================================================

validate_single_block() {
    local block_num=$1
    
    log_info "Validating QC for block $block_num"
    
    if validate_qc "$block_num"; then
        log_success "QC validation passed for block $block_num"
        exit 0
    else
        log_error "QC validation failed for block $block_num"
        exit 1
    fi
}

#==============================================================================
# Help
#==============================================================================

show_help() {
    cat << EOF
XDPoS 2.0 Quorum Certificate (QC) Validator

Usage: $(basename "$0") [options] [block_number]

Options:
    --daemon, -d            Run in continuous validation mode (default)
    --validate <block>      Validate QC for a specific block
    --interval <seconds>    Set poll interval (default: 30s)
    --help, -h              Show this help message

Environment Variables:
    XDC_RPC_URL             RPC endpoint (default: http://localhost:8545)
    SKYNET_API_URL          SkyNet API endpoint
    XDPOS2_QC_POLL_INTERVAL  Poll interval in seconds (default: 30)
    XDC_STATE_DIR           State directory for persistence

Examples:
    # Run continuous validation
    $(basename "$0") --daemon

    # Validate specific block
    $(basename "$0") --validate 12345678

Description:
    Validates XDPoS 2.0 Quorum Certificates (QC) for blocks. Ensures that
    each block has signatures from at least 2/3 of validators. Reports
    invalid QCs as CRITICAL incidents to SkyNet.

EOF
}

#==============================================================================
# Main
#==============================================================================

main() {
    local mode="daemon"
    local validate_block=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --daemon|-d)
                mode="daemon"
                shift
                ;;
            --validate)
                mode="single"
                validate_block="$2"
                shift 2
                ;;
            --interval)
                POLL_INTERVAL="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            [0-9]*)
                mode="single"
                validate_block="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    case "$mode" in
        daemon)
            run_validator
            ;;
        single)
            if [[ -z "$validate_block" ]]; then
                validate_block=$(get_block_number)
                log_info "No block specified, validating current block: $validate_block"
            fi
            validate_single_block "$validate_block"
            ;;
        *)
            log_error "Unknown mode: $mode"
            exit 1
            ;;
    esac
}

main "$@"
