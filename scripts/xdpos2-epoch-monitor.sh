#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDPoS 2.0 Epoch Transition Monitor
# Detects epoch switches and validates transition integrity
# Issue: #500
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
readonly POLL_INTERVAL="${XDPOS2_EPOCH_POLL_INTERVAL:-15}"
readonly STATE_DIR="${XDC_STATE_DIR:-/root/xdcchain/.state}"
readonly STATE_FILE="${STATE_DIR}/xdpos2-epoch-state.json"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# State tracking
declare -i LAST_BLOCK=0
declare -i LAST_EPOCH=0
declare -i EPOCH_TRANSITION_COUNT=0
declare -i FAILED_TRANSITIONS=0

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
    local full_tx="${2:-false}"
    local hex_block
    hex_block=$(printf "0x%x" "$block_num")
    
    curl -s -m 15 "$XDC_RPC_URL" \
        -X POST \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$hex_block\",$full_tx],\"id\":1}" 2>/dev/null || echo '{}'
}

# Get current epoch via RPC
get_current_epoch() {
    local response
    response=$(curl -s -m 10 "$XDC_RPC_URL" \
        -X POST \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"XDPoS_getEpochNumber","params":[],"id":1}' 2>/dev/null || echo '{}')
    
    hex_to_dec "$(echo "$response" | jq -r '.result // "0x0"')"
}

# Get validator set for an epoch
get_epoch_validators() {
    local epoch="${1:-current}"
    
    local response
    response=$(curl -s -m 15 "$XDC_RPC_URL" \
        -X POST \
        -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"XDPoS_getMasternodesByNumber","params":["latest"],"id":1}' 2>/dev/null || echo '{}')
    
    local validators
    validators=$(echo "$response" | jq -r '.result // []')
    
    if [[ "$validators" != "[]" ]] && [[ -n "$validators" ]]; then
        echo "$validators" | jq '[.[] | if startswith("0x") then "xdc" + .[2:] else . end]'
    else
        echo '[]'
    fi
}

# Calculate epoch from block number
calculate_epoch() {
    local block_num=$1
    echo $((block_num / EPOCH_LENGTH))
}

# Check if block is an epoch boundary (first block of epoch)
is_epoch_boundary() {
    local block_num=$1
    [[ $((block_num % EPOCH_LENGTH)) -eq 0 ]]
}

# Check if block is close to epoch boundary (within 5 blocks)
is_near_epoch_boundary() {
    local block_num=$1
    local remainder=$((block_num % EPOCH_LENGTH))
    [[ $remainder -ge 895 ]] || [[ $remainder -le 5 ]]
}

#==============================================================================
# Epoch Transition Validation
#==============================================================================

# Validate epoch transition at the given block
validate_epoch_transition() {
    local block_num=$1
    local epoch=$((block_num / EPOCH_LENGTH))
    local prev_epoch=$((epoch - 1))
    local prev_epoch_end=$((epoch * EPOCH_LENGTH - 1))
    
    log_info "Validating epoch transition at block $block_num (Epoch $epoch)"
    
    local failures=()
    local warnings=()
    
    # 1. Check that previous epoch's last block exists
    local prev_block_data
    prev_block_data=$(get_block_by_number "$prev_epoch_end")
    if [[ -z "$prev_block_data" ]] || [[ "$prev_block_data" == "{}" ]]; then
        failures+=("Previous epoch end block $prev_epoch_end not found")
        log_error "Previous epoch end block $prev_epoch_end not found"
    else
        log_success "Previous epoch end block $prev_epoch_end exists"
    fi
    
    # 2. Check that current block (first of new epoch) exists
    local block_data
    block_data=$(get_block_by_number "$block_num")
    if [[ -z "$block_data" ]] || [[ "$block_data" == "{}" ]]; then
        failures+=("Epoch start block $block_num not found - possible missed epoch block")
        log_error "🚨 MISSED EPOCH BLOCK: Block $block_num not found!"
    else
        log_success "Epoch start block $block_num exists"
    fi
    
    # 3. Validate new validator set loaded
    local validators
    validators=$(get_epoch_validators "$epoch")
    local validator_count
    validator_count=$(echo "$validators" | jq 'length')
    
    if [[ "$validator_count" -eq 0 ]]; then
        failures+=("No validators found for epoch $epoch")
        log_error "No validators found for epoch $epoch"
    else
        log_success "Validator set loaded: $validator_count validators for epoch $epoch"
    fi
    
    # 4. Check QC formation for first block of new epoch
    if [[ -n "$block_data" ]] && [[ "$block_data" != "{}" ]]; then
        local extra_data
        extra_data=$(echo "$block_data" | jq -r '.result.extraData // "0x"')
        extra_data="${extra_data#0x}"
        
        # Check for QC signatures in extraData
        # After vanity (64 hex chars), look for signature data
        if [[ ${#extra_data} -gt 200 ]]; then
            local sig_data="${extra_data:124}"  # After vanity+seal
            if [[ ${#sig_data} -ge 130 ]]; then
                log_success "QC signatures present in epoch start block"
            else
                warnings+=("Insufficient QC signatures in epoch start block")
                log_warn "Limited QC signatures in epoch start block"
            fi
        else
            warnings+=("No QC data found in epoch start block extraData")
            log_warn "No QC data in epoch start block"
        fi
    fi
    
    # 5. Check for gap blocks around epoch boundary
    local gap_blocks=()
    for ((b=prev_epoch_end-4; b<=block_num+4; b++)); do
        if [[ $b -lt 0 ]]; then continue; fi
        
        local b_data
        b_data=$(get_block_by_number "$b")
        if [[ -z "$b_data" ]] || [[ "$b_data" == "{}" ]]; then
            gap_blocks+=("$b")
        fi
    done
    
    if [[ ${#gap_blocks[@]} -gt 0 ]]; then
        warnings+=("Gap blocks detected around epoch boundary: ${gap_blocks[*]}")
        log_warn "Gap blocks around epoch boundary: ${gap_blocks[*]}"
    fi
    
    # Report results
    local transition_status="success"
    if [[ ${#failures[@]} -gt 0 ]]; then
        transition_status="failed"
        ((FAILED_TRANSITIONS++))
        
        log_error "🚨 EPOCH TRANSITION FAILED at block $block_num"
        for failure in "${failures[@]}"; do
            log_error "   - $failure"
        done
        
        # Report to SkyNet
        report_epoch_failure "$block_num" "$epoch" "$failures" "$warnings"
    else
        ((EPOCH_TRANSITION_COUNT++))
        log_success "✅ Epoch transition validated: Epoch $prev_epoch → $epoch at block $block_num"
        
        if [[ ${#warnings[@]} -gt 0 ]]; then
            for warning in "${warnings[@]}"; do
                log_warn "   - $warning"
            done
        fi
    fi
    
    # Save transition record
    record_transition "$block_num" "$epoch" "$transition_status" "$failures" "$warnings"
    
    return ${#failures[@]}
}

# Report epoch transition failure to SkyNet
report_epoch_failure() {
    local block_num=$1
    local epoch=$2
    local -n fail_arr=$3
    local -n warn_arr=$4
    
    # Convert arrays to JSON
    local failures_json
    failures_json=$(printf '%s\n' "${fail_arr[@]}" | jq -R . | jq -s .)
    local warnings_json
    warnings_json=$(printf '%s\n' "${warn_arr[@]}" | jq -R . | jq -s .)
    
    local payload
    payload=$(jq -n \
        --arg block "$block_num" \
        --arg epoch "$epoch" \
        --argjson failures "$failures_json" \
        --argjson warnings "$warnings_json" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg node "$(hostname)" \
        '{
            type: "epoch_transition_failure",
            severity: "critical",
            title: "XDPoS 2.0 Epoch Transition Failed",
            message: "Epoch transition failed at block \($block) (Epoch \($epoch))",
            details: {
                blockNumber: ($block | tonumber),
                epoch: ($epoch | tonumber),
                failures: $failures,
                warnings: $warnings,
                timestamp: $timestamp,
                reporterNode: $node
            }
        }')
    
    log_error "Reporting epoch transition failure to SkyNet..."
    
    local response
    response=$(curl -s -m 30 -X POST "${SKYNET_API}/issues/report" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null || echo '{"error": "connection_failed"}')
    
    if echo "$response" | jq -e '.success // .id // .issueId' >/dev/null 2>&1; then
        log_info "Epoch failure reported: $(echo "$response" | jq -r '.id // .issueId // "unknown"')"
    else
        log_error "Failed to report: $(echo "$response" | jq -r '.error // "unknown error"')"
    fi
    
    # Send critical notification
    if command -v notify_alert &>/dev/null; then
        notify_alert "critical" "🚨 Epoch Transition Failed" \
            "Epoch $epoch transition failed at block $block_num" \
            "epoch_failure"
    fi
}

#==============================================================================
# State Management
#==============================================================================

load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        LAST_BLOCK=$(jq -r '.lastBlock // 0' "$STATE_FILE" 2>/dev/null || echo "0")
        LAST_EPOCH=$(jq -r '.lastEpoch // 0' "$STATE_FILE" 2>/dev/null || echo "0")
        EPOCH_TRANSITION_COUNT=$(jq -r '.transitionCount // 0' "$STATE_FILE" 2>/dev/null || echo "0")
        FAILED_TRANSITIONS=$(jq -r '.failedTransitions // 0' "$STATE_FILE" 2>/dev/null || echo "0")
        log_info "Loaded state: last block=$LAST_BLOCK, last epoch=$LAST_EPOCH"
    else
        mkdir -p "$STATE_DIR"
        cat > "$STATE_FILE" <<'EOF'
{
    "lastBlock": 0,
    "lastEpoch": 0,
    "transitionCount": 0,
    "failedTransitions": 0,
    "transitions": []
}
EOF
    fi
}

save_state() {
    local tmp_file="${STATE_FILE}.tmp"
    
    jq --arg block "$LAST_BLOCK" \
       --arg epoch "$LAST_EPOCH" \
       --arg count "$EPOCH_TRANSITION_COUNT" \
       --arg failed "$FAILED_TRANSITIONS" \
       '.lastBlock = ($block | tonumber) | .lastEpoch = ($epoch | tonumber) | .transitionCount = ($count | tonumber) | .failedTransitions = ($failed | tonumber)' \
       "$STATE_FILE" > "$tmp_file" 2>/dev/null && \
        mv "$tmp_file" "$STATE_FILE" || true
}

record_transition() {
    local block_num=$1
    local epoch=$2
    local status=$3
    local -n fail_arr=$4
    local -n warn_arr=$5
    local tmp_file="${STATE_FILE}.tmp"
    
    local failures_json
    failures_json=$(printf '%s\n' "${fail_arr[@]}" | jq -R . | jq -s .)
    local warnings_json
    warnings_json=$(printf '%s\n' "${warn_arr[@]}" | jq -R . | jq -s .)
    
    local entry
    entry=$(jq -n \
        --arg block "$block_num" \
        --arg epoch "$epoch" \
        --arg status "$status" \
        --argjson failures "$failures_json" \
        --argjson warnings "$warnings_json" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            block: ($block | tonumber),
            epoch: ($epoch | tonumber),
            status: $status,
            failures: $failures,
            warnings: $warnings,
            timestamp: $timestamp
        }')
    
    jq --argjson entry "$entry" '.transitions += [$entry]' "$STATE_FILE" > "$tmp_file" 2>/dev/null && \
        mv "$tmp_file" "$STATE_FILE" || true
}

#==============================================================================
# Main Monitoring Loop
#==============================================================================

run_monitor() {
    log_info "Starting XDPoS 2.0 Epoch Transition Monitor"
    log_info "RPC: $XDC_RPC_URL"
    log_info "SkyNet API: $SKYNET_API"
    log_info "Poll interval: ${POLL_INTERVAL}s"
    log_info "Epoch length: $EPOCH_LENGTH blocks"
    
    load_state
    
    while true; do
        local current_block
        current_block=$(get_block_number)
        
        if [[ "$current_block" -eq 0 ]]; then
            log_error "Failed to get current block number, retrying..."
            sleep "$POLL_INTERVAL"
            continue
        fi
        
        local current_epoch
        current_epoch=$(calculate_epoch "$current_block")
        
        # Check for epoch transition
        if [[ $current_epoch -ne $LAST_EPOCH ]] && [[ $LAST_EPOCH -ne 0 ]]; then
            log_info "Epoch transition detected: Epoch $LAST_EPOCH → $current_epoch"
            
            # Validate the transition at the epoch boundary
            local epoch_start=$((current_epoch * EPOCH_LENGTH))
            validate_epoch_transition "$epoch_start"
        elif is_epoch_boundary "$current_block"; then
            # We are at an epoch boundary, validate it
            log_info "At epoch boundary block $current_block"
            validate_epoch_transition "$current_block"
        elif is_near_epoch_boundary "$current_block"; then
            log_info "Near epoch boundary: block $current_block, epoch $current_epoch"
        fi
        
        # Check for missed epoch block (if we skipped the boundary)
        if [[ $current_epoch -gt $LAST_Epoch ]] && [[ $LAST_EPOCH -gt 0 ]]; then
            local expected_start=$((current_epoch * EPOCH_LENGTH))
            if [[ $current_block -gt $expected_start ]]; then
                local block_at_boundary
                block_at_boundary=$(get_block_by_number "$expected_start")
                if [[ -z "$block_at_boundary" ]] || [[ "$block_at_boundary" == "{}" ]]; then
                    log_error "🚨 MISSED EPOCH BLOCK at $expected_start"
                    report_epoch_failure "$expected_start" "$current_epoch" \
                        "(["Epoch start block missing"])" "([])"
                fi
            fi
        fi
        
        LAST_BLOCK=$current_block
        LAST_EPOCH=$current_epoch
        save_state
        
        log_info "Block $current_block, Epoch $current_epoch - sleeping ${POLL_INTERVAL}s"
        sleep "$POLL_INTERVAL"
    done
}

#==============================================================================
# Single Check Mode
#==============================================================================

check_specific_epoch() {
    local epoch=$1
    local epoch_start=$((epoch * EPOCH_LENGTH))
    
    log_info "Checking epoch $epoch (starts at block $epoch_start)"
    validate_epoch_transition "$epoch_start"
}

#==============================================================================
# Help
#==============================================================================

show_help() {
    cat << EOF
XDPoS 2.0 Epoch Transition Monitor

Usage: $(basename "$0") [options] [epoch_number]

Options:
    --daemon, -d            Run in continuous monitoring mode (default)
    --check <epoch>         Check a specific epoch transition
    --interval <seconds>    Set poll interval (default: 15s)
    --help, -h              Show this help message

Environment Variables:
    XDC_RPC_URL             RPC endpoint (default: http://localhost:8545)
    SKYNET_API_URL          SkyNet API endpoint
    XDPOS2_EPOCH_POLL_INTERVAL  Poll interval in seconds (default: 15)
    XDC_STATE_DIR           State directory for persistence

Examples:
    # Run continuous monitoring
    $(basename "$0") --daemon

    # Check specific epoch
    $(basename "$0") --check 1000

Description:
    Monitors XDPoS 2.0 epoch transitions (every 900 blocks). Validates:
    - New validator set loaded correctly
    - No missed epoch blocks
    - QC formation for first block of new epoch
    
    Reports transition failures to SkyNet API.

EOF
}

#==============================================================================
# Main
#==============================================================================

main() {
    local mode="daemon"
    local check_epoch=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --daemon|-d)
                mode="daemon"
                shift
                ;;
            --check)
                mode="single"
                check_epoch="$2"
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
                check_epoch="$1"
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
            if [[ -z "$check_epoch" ]]; then
                # Get current epoch
                local current_block
                current_block=$(get_block_number)
                check_epoch=$(calculate_epoch "$current_block")
                log_info "No epoch specified, checking current epoch: $check_epoch"
            fi
            check_specific_epoch "$check_epoch"
            ;;
        *)
            log_error "Unknown mode: $mode"
            exit 1
            ;;
    esac
}

main "$@"
