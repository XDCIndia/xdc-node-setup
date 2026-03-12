#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDPoS 2.0 Gap Block Monitor
# Detects gap blocks when a masternode misses its turn
# Issue: #485
#==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source common utilities
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || source "/opt/xdc-node/scripts/lib/common.sh" || true
source "${SCRIPT_DIR}/lib/xdc-contracts.sh" 2>/dev/null || source "/opt/xdc-node/scripts/lib/xdc-contracts.sh" || true
source "${SCRIPT_DIR}/lib/notify.sh" 2>/dev/null || source "/opt/xdc-node/scripts/lib/notify.sh" || true

# Configuration
readonly XDC_RPC_URL="${XDC_RPC_URL:-http://localhost:8545}"
readonly SKYNET_API="${SKYNET_API_URL:-https://net.xdc.network/api/v1}"
readonly EPOCH_LENGTH=900
readonly BLOCK_TIME=2
readonly POLL_INTERVAL="${XDPOS2_GAP_POLL_INTERVAL:-10}"
readonly STATE_DIR="${XDC_STATE_DIR:-/root/xdcchain/.state}"
readonly STATE_FILE="${STATE_DIR}/xdpos2-gap-state.json"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# State tracking
declare -A EPOCH_VALIDATORS
declare -i LAST_CHECKED_BLOCK=0

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

# Get block by number
get_block_by_number() {
    local block_num=$1
    local hex_block
    hex_block=$(printf "0x%x" "$block_num")
    
    curl -s -m 15 "$XDC_RPC_URL" \
        -X POST \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$hex_block\",false],\"id\":1}" 2>/dev/null || echo '{}'
}

# Extract validator address from block extraData
# XDPoS 2.0 extraData structure:
# - Bytes 0-31: Vanity
# - Bytes 32+: Validator info, signatures, QC data
extract_validator_from_block() {
    local block_data="$1"
    
    # Get miner/signer field which contains the validator address
    local miner
    miner=$(echo "$block_data" | jq -r '.result.miner // "0x0000000000000000000000000000000000000000"')
    
    # Normalize to xdc prefix
    if [[ "$miner" == 0x* ]]; then
        miner="xdc${miner:2}"
    fi
    
    echo "$miner"
}

# Get expected validator for a given block number
# In XDPoS 2.0, validators rotate deterministically based on epoch and round
get_expected_validator() {
    local block_num=$1
    local epoch=$((block_num / EPOCH_LENGTH))
    local round=$((block_num % EPOCH_LENGTH))
    
    # Get validator set for current epoch
    local validators
    validators=$(get_epoch_validators "$epoch" 2>/dev/null || echo '[]')
    
    if [[ "$validators" == "[]" ]] || [[ -z "$validators" ]]; then
        # Fallback to getMasternodes if epoch validators not available
        validators=$(get_masternodes 2>/dev/null || echo '[]')
    fi
    
    local validator_count
    validator_count=$(echo "$validators" | jq 'length')
    
    if [[ "$validator_count" -eq 0 ]]; then
        echo "unknown"
        return 1
    fi
    
    # Calculate which validator should produce this block
    # XDPoS 2.0 uses round-robin rotation within each round
    local cycle=$((round / 90))
    local validator_index=$(( (epoch * 10 + cycle) % validator_count ))
    
    echo "$validators" | jq -r ".[$validator_index] // \"unknown\""
}

# Get list of validators for an epoch from the epoch contract
get_epoch_validators() {
    local epoch="${1:-current}"
    
    # Call XDPoS_getMasternodesByNumber RPC method
    local response
    response=$(curl -s -m 15 "$XDC_RPC_URL" \
        -X POST \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"XDPoS_getMasternodesByNumber","params":["latest"],"id":1}' 2>/dev/null || echo '{}')
    
    # Parse masternode addresses
    local masternodes
    masternodes=$(echo "$response" | jq -r '.result // []')
    
    if [[ "$masternodes" == "[]" ]] || [[ -z "$masternodes" ]]; then
        # Fallback: try eth_call to validator contract
        local validator_set="0x0000000000000000000000000000000000000089"
        local call_data="0x" # getValidators() selector
        
        response=$(curl -s -m 15 "$XDC_RPC_URL" \
            -X POST \
            -H "Content-Type: application/json" \
            --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"$validator_set\",\"data\":\"$call_data\"},\"latest\"],\"id\":1}" 2>/dev/null || echo '{}')
        
        # Return empty array if still can't get validators
        echo '[]'
    else
        echo "$masternodes" | jq '[.[] | if startswith("0x") then "xdc" + .[2:] else . end]'
    fi
}

#==============================================================================
# Gap Block Detection
#==============================================================================

# Check if a block is a gap block (validator mismatch)
check_gap_block() {
    local block_num=$1
    local block_data
    block_data=$(get_block_by_number "$block_num")
    
    if [[ -z "$block_data" ]] || [[ "$block_data" == "{}" ]]; then
        log_error "Failed to fetch block $block_num"
        return 1
    fi
    
    # Check if block exists
    local block_hash
    block_hash=$(echo "$block_data" | jq -r '.result.hash // "null"')
    if [[ "$block_hash" == "null" ]] || [[ -z "$block_hash" ]]; then
        log_warn "Block $block_num not found or empty"
        return 1
    fi
    
    local actual_validator
    actual_validator=$(extract_validator_from_block "$block_data")
    
    local expected_validator
    expected_validator=$(get_expected_validator "$block_num")
    
    # Normalize addresses for comparison
    local actual_normalized="${actual_validator,,}"
    local expected_normalized="${expected_validator,,}"
    
    if [[ "$expected_validator" == "unknown" ]]; then
        log_warn "Could not determine expected validator for block $block_num"
        return 1
    fi
    
    # Check for gap block (validator mismatch)
    if [[ "$actual_normalized" != "$expected_normalized" ]]; then
        log_error "🚨 GAP BLOCK DETECTED: Block $block_num"
        log_error "   Expected: $expected_validator"
        log_error "   Actual:   $actual_validator"
        
        # Report to SkyNet
        report_gap_block "$block_num" "$expected_validator" "$actual_validator"
        
        return 0  # Gap block found
    else
        log_success "Block $block_num: Validator match ($actual_validator)"
        return 1  # No gap block
    fi
}

# Report gap block to SkyNet API
report_gap_block() {
    local block_num=$1
    local expected=$2
    local actual=$3
    local epoch=$((block_num / EPOCH_LENGTH))
    local round=$((block_num % EPOCH_LENGTH))
    
    local payload
    payload=$(jq -n \
        --arg block "$block_num" \
        --arg epoch "$epoch" \
        --arg round "$round" \
        --arg expected "$expected" \
        --arg actual "$actual" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg node "$(hostname)" \
        '{
            type: "gap_block",
            severity: "warning",
            title: "XDPoS 2.0 Gap Block Detected",
            message: "Masternode missed its turn producing block \($block)",
            details: {
                blockNumber: ($block | tonumber),
                epoch: ($epoch | tonumber),
                round: ($round | tonumber),
                expectedValidator: $expected,
                actualValidator: $actual,
                timestamp: $timestamp,
                reporterNode: $node
            }
        }')
    
    log_info "Reporting gap block to SkyNet..."
    
    local response
    response=$(curl -s -m 30 -X POST "${SKYNET_API}/issues/report" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null || echo '{"error": "connection_failed"}')
    
    if echo "$response" | jq -e '.success // .id // .issueId' >/dev/null 2>&1; then
        log_success "Gap block reported to SkyNet: $(echo "$response" | jq -r '.id // .issueId // "unknown"')"
    else
        log_error "Failed to report gap block: $(echo "$response" | jq -r '.error // "unknown error"')"
    fi
    
    # Also send notification if notify library is available
    if command -v notify_alert &>/dev/null; then
        notify_alert "warning" "🚨 Gap Block Detected" \
            "Block $block_num: Expected $expected, got $actual" \
            "gap_block"
    fi
}

#==============================================================================
# State Management
#==============================================================================

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        LAST_CHECKED_BLOCK=$(jq -r '.lastCheckedBlock // 0' "$STATE_FILE" 2>/dev/null || echo "0")
        log_info "Loaded state: last checked block = $LAST_CHECKED_BLOCK"
    else
        mkdir -p "$STATE_DIR"
        echo '{"lastCheckedBlock": 0, "gapBlocks": []}' > "$STATE_FILE"
    fi
}

save_state() {
    local block_num=$1
    local tmp_file="${STATE_FILE}.tmp"
    
    jq ".lastCheckedBlock = $block_num" "$STATE_FILE" > "$tmp_file" 2>/dev/null && \
        mv "$tmp_file" "$STATE_FILE" || true
}

record_gap_block() {
    local block_num=$1
    local expected=$2
    local actual=$3
    local tmp_file="${STATE_FILE}.tmp"
    
    local entry
    entry=$(jq -n \
        --arg block "$block_num" \
        --arg expected "$expected" \
        --arg actual "$actual" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{block: ($block | tonumber), expected: $expected, actual: $actual, timestamp: $timestamp}')
    
    jq --argjson entry "$entry" '.gapBlocks += [$entry]' "$STATE_FILE" > "$tmp_file" 2>/dev/null && \
        mv "$tmp_file" "$STATE_FILE" || true
}

#==============================================================================
# Main Monitoring Loop
#==============================================================================

run_monitor() {
    log_info "Starting XDPoS 2.0 Gap Block Monitor"
    log_info "RPC: $XDC_RPC_URL"
    log_info "SkyNet API: $SKYNET_API"
    log_info "Poll interval: ${POLL_INTERVAL}s"
    
    load_state
    
    while true; do
        local current_block
        current_block=$(get_block_number)
        
        if [[ "$current_block" -eq 0 ]]; then
            log_error "Failed to get current block number, retrying in ${POLL_INTERVAL}s..."
            sleep "$POLL_INTERVAL"
            continue
        fi
        
        log_info "Current block: $current_block, Last checked: $LAST_CHECKED_BLOCK"
        
        # Check blocks since last check
        if [[ $LAST_CHECKED_BLOCK -eq 0 ]]; then
            # First run - just check the current block
            LAST_CHECKED_BLOCK=$((current_block - 1))
        fi
        
        # Check all blocks since last check (with a limit)
        local blocks_to_check=$((current_block - LAST_CHECKED_BLOCK))
        if [[ $blocks_to_check -gt 100 ]]; then
            log_warn "Large block gap detected ($blocks_to_check blocks), limiting to last 100"
            LAST_CHECKED_BLOCK=$((current_block - 100))
            blocks_to_check=100
        fi
        
        local gap_count=0
        for ((block=LAST_CHECKED_BLOCK+1; block<=current_block; block++)); do
            if check_gap_block "$block"; then
                ((gap_count++))
                local block_data
                block_data=$(get_block_by_number "$block")
                local actual=$(extract_validator_from_block "$block_data")
                local expected=$(get_expected_validator "$block")
                record_gap_block "$block" "$expected" "$actual"
            fi
        done
        
        if [[ $gap_count -gt 0 ]]; then
            log_warn "Found $gap_count gap block(s) in this poll"
        else
            log_info "No gap blocks detected in range $((LAST_CHECKED_BLOCK+1))-$current_block"
        fi
        
        LAST_CHECKED_BLOCK=$current_block
        save_state "$current_block"
        
        log_info "Sleeping for ${POLL_INTERVAL}s..."
        sleep "$POLL_INTERVAL"
    done
}

#==============================================================================
# Single Check Mode
#==============================================================================

run_single_check() {
    local block_num=$1
    
    log_info "Running single gap block check for block $block_num"
    
    if check_gap_block "$block_num"; then
        log_error "Gap block confirmed at block $block_num"
        exit 1
    else
        log_success "No gap block at block $block_num"
        exit 0
    fi
}

#==============================================================================
# Help
#==============================================================================

show_help() {
    cat << EOF
XDPoS 2.0 Gap Block Monitor - Detects missed masternode turns

Usage: $(basename "$0") [options] [block_number]

Options:
    --daemon, -d            Run in continuous monitoring mode (default)
    --check <block>         Check a specific block number
    --interval <seconds>    Set poll interval (default: 10s)
    --help, -h              Show this help message

Environment Variables:
    XDC_RPC_URL             RPC endpoint (default: http://localhost:8545)
    SKYNET_API_URL          SkyNet API endpoint
    XDPOS2_GAP_POLL_INTERVAL  Poll interval in seconds (default: 10)
    XDC_STATE_DIR           State directory for persistence

Examples:
    # Run continuous monitoring
    $(basename "$0") --daemon

    # Check specific block
    $(basename "$0") --check 12345678

    # Run with custom interval
    $(basename "$0") --interval 5

Description:
    Monitors XDPoS 2.0 consensus for gap blocks - blocks where the expected
    masternode failed to produce a block. Reports detected gaps to SkyNet API.

EOF
}

#==============================================================================
# Main
#==============================================================================

main() {
    local mode="daemon"
    local check_block=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --daemon|-d)
                mode="daemon"
                shift
                ;;
            --check)
                mode="single"
                check_block="$2"
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
                # Block number provided as positional arg
                mode="single"
                check_block="$1"
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
            run_monitor
            ;;
        single)
            if [[ -z "$check_block" ]]; then
                # Get current block
                check_block=$(get_block_number)
                log_info "No block specified, checking current block: $check_block"
            fi
            run_single_check "$check_block"
            ;;
        *)
            log_error "Unknown mode: $mode"
            exit 1
            ;;
    esac
}

main "$@"
