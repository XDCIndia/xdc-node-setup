#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDPoS 2.0 Vote & QC Formation Monitor
# Tracks validator participation and QC formation
# Issue: #501
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
readonly POLL_INTERVAL="${XDPOS2_VOTE_POLL_INTERVAL:-20}"
readonly STATE_DIR="${XDC_STATE_DIR:-/root/xdcchain/.state}"
readonly STATE_FILE="${STATE_DIR}/xdpos2-vote-state.json"

# Alert thresholds
readonly QUORUM_THRESHOLD=66      # 66% participation required
readonly WARNING_THRESHOLD=70     # Warn if below 70%
readonly CRITICAL_THRESHOLD=60    # Critical if below 60%

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# State tracking
declare -i LAST_CHECKED_BLOCK=0
declare -a LOW_PARTICIPATION_EPOCHS=()

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

# Get validator set
get_validator_set() {
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

#==============================================================================
# Vote and QC Analysis
#==============================================================================

# Extract vote/QC data from block extraData
extract_vote_data() {
    local block_data="$1"
    
    local extra_data
    extra_data=$(echo "$block_data" | jq -r '.result.extraData // "0x"')
    extra_data="${extra_data#0x}"
    
    # XDPoS 2.0 extraData structure:
    # - Bytes 0-31 (64 hex): Vanity
    # - Bytes 32-61 (60 hex): Seal
    # - Bytes 62+: Signatures and QC data
    
    local vote_count=0
    local signer_bitmask=""
    local signatures=""
    
    if [[ ${#extra_data} -gt 124 ]]; then
        # Extract validator bitmask (after vanity)
        signer_bitmask="${extra_data:64:64}"
        
        # Extract signature data
        signatures="${extra_data:124}"
        
        # Count signatures (each is 65 bytes = 130 hex chars)
        local sig_length=${#signatures}
        if [[ $sig_length -ge 130 ]]; then
            vote_count=$((sig_length / 130))
        fi
    fi
    
    jq -n \
        --argjson count "$vote_count" \
        --arg bitmask "$signer_bitmask" \
        --arg sigs "$signatures" \
        --argjson extra_len "${#extra_data}" \
        '{
            voteCount: $count,
            validatorBitmask: $bitmask,
            signatures: $sigs,
            extraDataLength: $extra_len
        }'
}

# Count votes from bitmask
# Each bit represents one validator's vote
count_votes_from_bitmask() {
    local bitmask="$1"
    local validator_count=$2
    
    local vote_count=0
    
    # Parse each byte of the bitmask
    for ((i=0; i<validator_count && i<256; i++)); do
        local byte_offset=$((i / 8))
        local bit_offset=$((7 - (i % 8)))
        
        # Extract the byte containing this validator's bit
        local byte_hex="${bitmask:$((byte_offset*2)):2}"
        [[ -z "$byte_hex" ]] && break
        
        local byte_val=$((16#$byte_hex))
        local bit_val=$(( (byte_val >> bit_offset) & 1 ))
        
        if [[ $bit_val -eq 1 ]]; then
            ((vote_count++))
        fi
    done
    
    echo "$vote_count"
}

# Identify which validators voted based on bitmask
get_voting_validators() {
    local bitmask="$1"
    local validators_json="$2"
    
    local validator_count
    validator_count=$(echo "$validators_json" | jq 'length')
    
    local voted="[]"
    local missed="[]"
    
    for ((i=0; i<validator_count && i<256; i++)); do
        local byte_offset=$((i / 8))
        local bit_offset=$((7 - (i % 8)))
        
        local byte_hex="${bitmask:$((byte_offset*2)):2}"
        [[ -z "$byte_hex" ]] && break
        
        local byte_val=$((16#$byte_hex))
        local bit_val=$(( (byte_val >> bit_offset) & 1 ))
        
        local validator
        validator=$(echo "$validators_json" | jq -r ".[$i] // empty")
        
        if [[ $bit_val -eq 1 ]]; then
            voted=$(echo "$voted" | jq --arg v "$validator" '. + [$v]')
        else
            missed=$(echo "$missed" | jq --arg v "$validator" '. + [$v]')
        fi
    done
    
    jq -n \
        --argjson voted "$voted" \
        --argjson missed "$missed" \
        '{voted: $voted, missed: $missed}'
}

# Analyze votes for a block
analyze_block_votes() {
    local block_num=$1
    
    local block_data
    block_data=$(get_block_by_number "$block_num")
    
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
        log_warn "No validators found for vote analysis"
        return 1
    fi
    
    # Extract vote data
    local vote_data
    vote_data=$(extract_vote_data "$block_data")
    local vote_count
    vote_count=$(echo "$vote_data" | jq -r '.voteCount // 0')
    local bitmask
    bitmask=$(echo "$vote_data" | jq -r '.validatorBitmask // ""')
    
    # Count votes from bitmask for more accuracy
    if [[ -n "$bitmask" ]]; then
        local bitmask_votes
        bitmask_votes=$(count_votes_from_bitmask "$bitmask" "$validator_count")
        if [[ $bitmask_votes -gt $vote_count ]]; then
            vote_count=$bitmask_votes
        fi
    fi
    
    # Calculate participation percentage
    local participation_pct
    participation_pct=$(awk "BEGIN {printf \"%.2f\", ($vote_count / $validator_count) * 100}")
    
    # Get validator breakdown
    local validator_breakdown
    validator_breakdown=$(get_voting_validators "$bitmask" "$validators")
    
    jq -n \
        --arg block "$block_num" \
        --argjson votes "$vote_count" \
        --argjson total "$validator_count" \
        --arg pct "$participation_pct" \
        --argjson breakdown "$validator_breakdown" \
        --argjson vote_data "$vote_data" \
        '{
            blockNumber: $block,
            voteCount: $votes,
            totalValidators: $total,
            participationPercent: ($pct | tonumber),
            votedValidators: $breakdown.voted,
            missedValidators: $breakdown.missed,
            voteData: $vote_data
        }'
}

#==============================================================================
# Participation Monitoring
#==============================================================================

# Monitor participation for recent blocks
check_participation() {
    local blocks_to_check="${1:-10}"
    
    local current_block
    current_block=$(get_block_number)
    
    if [[ "$current_block" -eq 0 ]]; then
        log_error "Failed to get current block number"
        return 1
    fi
    
    log_info "Analyzing votes for last $blocks_to_check blocks (up to $current_block)"
    
    local total_participation=0
    local below_quorum_count=0
    local results="[]"
    
    for ((i=0; i<blocks_to_check; i++)); do
        local block_num=$((current_block - i))
        [[ $block_num -lt 0 ]] && break
        
        local analysis
        analysis=$(analyze_block_votes "$block_num")
        
        if [[ -n "$analysis" ]]; then
            local pct
            pct=$(echo "$analysis" | jq -r '.participationPercent // 0')
            total_participation=$(awk "BEGIN {print $total_participation + $pct}")
            
            # Check if below quorum
            if [[ $(echo "$pct < $QUORUM_THRESHOLD" | bc -l) -eq 1 ]]; then
                ((below_quorum_count++))
                
                local missed
                missed=$(echo "$analysis" | jq -r '.missedValidators | length')
                log_error "Block $block_num: Participation ${pct}% ($missed validators missing votes)"
                
                # Report low participation
                report_low_participation "$analysis"
            else
                local votes
                votes=$(echo "$analysis" | jq -r '.voteCount // 0')
                local total
                total=$(echo "$analysis" | jq -r '.totalValidators // 0')
                log_success "Block $block_num: ${pct}% participation ($votes/$total)"
            fi
            
            results=$(echo "$results" | jq --argjson entry "$analysis" '. + [$entry]')
        fi
    done
    
    # Calculate average
    local avg_participation
    avg_participation=$(awk "BEGIN {printf \"%.2f\", $total_participation / $blocks_to_check}")
    
    log_info "Average participation: ${avg_participation}%"
    
    if [[ $below_quorum_count -gt 0 ]]; then
        log_error "🚨 $below_quorum_count block(s) below ${QUORUM_THRESHOLD}% quorum threshold!"
        
        # Alert if participation is critically low
        if [[ $(echo "$avg_participation < $CRITICAL_THRESHOLD" | bc -l) -eq 1 ]]; then
            if command -v notify_alert &>/dev/null; then
                notify_alert "critical" "🚨 Critical Vote Participation" \
                    "Average participation ${avg_participation}% (below ${CRITICAL_THRESHOLD}%)" \
                    "low_participation"
            fi
        elif [[ $(echo "$avg_participation < $WARNING_THRESHOLD" | bc -l) -eq 1 ]]; then
            if command -v notify_alert &>/dev/null; then
                notify_alert "warning" "⚠️ Low Vote Participation" \
                    "Average participation ${avg_participation}% (below ${WARNING_THRESHOLD}%)" \
                    "low_participation"
            fi
        fi
    fi
    
    echo "$results"
}

# Report low participation to SkyNet
report_low_participation() {
    local analysis="$1"
    
    local block_num
    block_num=$(echo "$analysis" | jq -r '.blockNumber')
    local epoch=$((block_num / EPOCH_LENGTH))
    
    local payload
    payload=$(jq -n \
        --argjson analysis "$analysis" \
        --arg epoch "$epoch" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg node "$(hostname)" \
        --arg threshold "$QUORUM_THRESHOLD" \
        '{
            type: "low_participation",
            severity: "warning",
            title: "XDPoS 2.0 Vote Participation Below Quorum",
            message: "Block \($analysis.blockNumber) has \($analysis.participationPercent)% participation (below \($threshold)%)",
            details: {
                blockNumber: $analysis.blockNumber,
                epoch: ($epoch | tonumber),
                voteCount: $analysis.voteCount,
                totalValidators: $analysis.totalValidators,
                participationPercent: $analysis.participationPercent,
                quorumThreshold: ($threshold | tonumber),
                missedValidators: $analysis.missedValidators,
                timestamp: $timestamp,
                reporterNode: $node
            }
        }')
    
    local response
    response=$(curl -s -m 30 -X POST "${SKYNET_API}/issues/report" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>/dev/null || echo '{"error": "connection_failed"}')
    
    if echo "$response" | jq -e '.success // .id // .issueId' >/dev/null 2>&1; then
        log_info "Low participation reported: $(echo "$response" | jq -r '.id // .issueId // "unknown"')"
    fi
}

# Track specific validators missing votes
track_validator_participation() {
    local blocks_to_check="${1:-50}"
    
    local current_block
    current_block=$(get_block_number)
    
    log_info "Tracking validator participation over last $blocks_to_check blocks"
    
    local validators
    validators=$(get_validator_set)
    local validator_count
    validator_count=$(echo "$validators" | jq 'length')
    
    if [[ "$validator_count" -eq 0 ]]; then
        log_error "No validators found"
        return 1
    fi
    
    # Initialize participation counters
    declare -A PARTICIPATION_COUNT
    for ((i=0; i<validator_count; i++)); do
        local validator
        validator=$(echo "$validators" | jq -r ".[$i]")
        PARTICIPATION_COUNT[$validator]=0
    done
    
    # Count participation across blocks
    for ((i=0; i<blocks_to_check; i++)); do
        local block_num=$((current_block - i))
        [[ $block_num -lt 0 ]] && break
        
        local block_data
        block_data=$(get_block_by_number "$block_num")
        local extra_data
        extra_data=$(echo "$block_data" | jq -r '.result.extraData // "0x"')
        extra_data="${extra_data#0x}"
        local bitmask="${extra_data:64:64}"
        
        for ((v=0; v<validator_count && v<256; v++)); do
            local byte_offset=$((v / 8))
            local bit_offset=$((7 - (v % 8)))
            local byte_hex="${bitmask:$((byte_offset*2)):2}"
            [[ -z "$byte_hex" ]] && break
            
            local byte_val=$((16#$byte_hex))
            local bit_val=$(( (byte_val >> bit_offset) & 1 ))
            
            local validator
            validator=$(echo "$validators" | jq -r ".[$v] // empty")
            
            if [[ $bit_val -eq 1 ]] && [[ -n "$validator" ]]; then
                ((PARTICIPATION_COUNT[$validator]++))
            fi
        done
    done
    
    # Display results
    echo ""
    echo "Validator Participation Summary (last $blocks_to_check blocks):"
    echo "═══════════════════════════════════════════════════════════════"
    printf "%-50s %10s %10s\n" "Validator" "Voted" "Rate%"
    echo "───────────────────────────────────────────────────────────────"
    
    local low_participation=()
    
    for ((i=0; i<validator_count; i++)); do
        local validator
        validator=$(echo "$validators" | jq -r ".[$i]")
        local count=${PARTICIPATION_COUNT[$validator]:-0}
        local rate
        rate=$(awk "BEGIN {printf \"%.1f\", ($count / $blocks_to_check) * 100}")
        
        printf "%-50s %10d %10s%%\n" "$validator" "$count" "$rate"
        
        # Flag validators with low participation
        if [[ $(echo "$rate < $QUORUM_THRESHOLD" | bc -l) -eq 1 ]]; then
            low_participation+=("$validator:$rate")
        fi
    done
    
    echo "═══════════════════════════════════════════════════════════════"
    
    if [[ ${#low_participation[@]} -gt 0 ]]; then
        echo ""
        log_warn "Validators with low participation (<${QUORUM_THRESHOLD}%):"
        for entry in "${low_participation[@]}"; do
            log_warn "  - ${entry%:*} (${entry#*:}%)"
        done
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
        cat > "$STATE_FILE" <<'EOF'
{
    "lastCheckedBlock": 0,
    "lowParticipationBlocks": [],
    "validatorStats": {}
}
EOF
    fi
}

save_state() {
    local block_num=$1
    local tmp_file="${STATE_FILE}.tmp"
    
    jq ".lastCheckedBlock = $block_num" "$STATE_FILE" > "$tmp_file" 2>/dev/null && \
        mv "$tmp_file" "$STATE_FILE" || true
}

record_low_participation() {
    local block_num=$1
    local participation=$2
    local tmp_file="${STATE_FILE}.tmp"
    
    local entry
    entry=$(jq -n \
        --arg block "$block_num" \
        --arg pct "$participation" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            block: ($block | tonumber),
            participationPercent: ($pct | tonumber),
            timestamp: $timestamp
        }')
    
    jq --argjson entry "$entry" '.lowParticipationBlocks += [$entry]' "$STATE_FILE" > "$tmp_file" 2>/dev/null && \
        mv "$tmp_file" "$STATE_FILE" || true
}

#==============================================================================
# Main Monitoring Loop
#==============================================================================

run_monitor() {
    log_info "Starting XDPoS 2.0 Vote & QC Formation Monitor"
    log_info "RPC: $XDC_RPC_URL"
    log_info "SkyNet API: $SKYNET_API"
    log_info "Poll interval: ${POLL_INTERVAL}s"
    log_info "Quorum threshold: ${QUORUM_THRESHOLD}%"
    
    load_state
    
    while true; do
        local current_block
        current_block=$(get_block_number)
        
        if [[ "$current_block" -eq 0 ]]; then
            log_error "Failed to get current block number, retrying..."
            sleep "$POLL_INTERVAL"
            continue
        fi
        
        log_info "Checking participation for recent blocks..."
        check_participation 5
        
        LAST_CHECKED_BLOCK=$current_block
        save_state "$current_block"
        
        log_info "Sleeping for ${POLL_INTERVAL}s..."
        sleep "$POLL_INTERVAL"
    done
}

#==============================================================================
# Help
#==============================================================================

show_help() {
    cat << EOF
XDPoS 2.0 Vote & QC Formation Monitor

Usage: $(basename "$0") [options]

Options:
    --daemon, -d            Run in continuous monitoring mode (default)
    --check [blocks]        Check participation for recent blocks (default: 10)
    --track [blocks]        Track validator participation over blocks (default: 50)
    --interval <seconds>    Set poll interval (default: 20s)
    --help, -h              Show this help message

Environment Variables:
    XDC_RPC_URL             RPC endpoint (default: http://localhost:8545)
    SKYNET_API_URL          SkyNet API endpoint
    XDPOS2_VOTE_POLL_INTERVAL  Poll interval in seconds (default: 20)
    XDC_STATE_DIR           State directory for persistence

Examples:
    # Run continuous monitoring
    $(basename "$0") --daemon

    # Check participation for last 20 blocks
    $(basename "$0") --check 20

    # Track validator participation
    $(basename "$0") --track 100

Description:
    Monitors XDPoS 2.0 validator participation and QC formation:
    - Counts votes per block from QC data
    - Calculates participation percentage
    - Alerts if participation < ${QUORUM_THRESHOLD}% (quorum threshold)
    - Tracks which validators are missing votes

EOF
}

#==============================================================================
# Main
#==============================================================================

main() {
    local mode="daemon"
    local check_blocks=10
    local track_blocks=50
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --daemon|-d)
                mode="daemon"
                shift
                ;;
            --check)
                mode="check"
                if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    check_blocks="$2"
                    shift
                fi
                shift
                ;;
            --track)
                mode="track"
                if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    track_blocks="$2"
                    shift
                fi
                shift
                ;;
            --interval)
                POLL_INTERVAL="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
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
        check)
            check_participation "$check_blocks"
            ;;
        track)
            track_validator_participation "$track_blocks"
            ;;
        *)
            log_error "Unknown mode: $mode"
            exit 1
            ;;
    esac
}

main "$@"
