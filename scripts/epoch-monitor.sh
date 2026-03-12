#!/bin/bash
set -euo pipefail

# Enhanced Epoch Boundary Monitoring
# Issue #522: Implement comprehensive monitoring and alerting for XDPoS 2.0 epoch boundaries

readonly SCRIPT_VERSION="1.0.0"
readonly CONFIG_DIR="${XDC_CONFIG_DIR:-$HOME/.xdc-node}"
readonly LOG_FILE="${XDC_LOG_DIR:-/var/log/xdc}/epoch-monitor.log"
readonly STATE_FILE="$CONFIG_DIR/epoch-state.json"

# XDPoS 2.0 Configuration
EPOCH_BLOCKS="${XDPOS_EPOCH_BLOCKS:-900}"
ALERT_BLOCKS_100="${EPOCH_ALERT_100:-100}"
ALERT_BLOCKS_50="${EPOCH_ALERT_50:-50}"
ALERT_BLOCKS_10="${EPOCH_ALERT_10:-10}"

# RPC endpoint
RPC_URL="${RPC_URL:-http://localhost:8545}"

# Webhook/notification settings
WEBHOOK_URL="${EPOCH_WEBHOOK_URL:-}"
TELEGRAM_BOT_TOKEN="${EPOCH_TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_ID="${EPOCH_TELEGRAM_CHAT:-}"

# Logging
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
info() { log "INFO: $*"; }
warn() { log "WARN: $*" >&2; }
error() { log "ERROR: $*" >&2; }

# Initialize
init() {
    mkdir -p "$CONFIG_DIR" "$(dirname "$LOG_FILE")"
    
    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{"lastEpoch":0,"lastAlert100":false,"lastAlert50":false,"lastAlert10":false}' > "$STATE_FILE"
    fi
}

# RPC call helper
rpc_call() {
    local method=$1
    local params=${2:-'[]'}
    
    curl -sf -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        2>/dev/null || echo '{}'
}

# Get current epoch info
get_epoch_info() {
    local result
    result=$(rpc_call "XDPoS_getEpochInfo" '["latest"]')
    
    local epoch_number
    epoch_number=$(echo "$result" | jq -r '.result.EpochNumber // 0')
    local current_round
    current_round=$(echo "$result" | jq -r '.result.CurrentRound // 0')
    local masternodes
    masternodes=$(echo "$result" | jq -r '.result.Masternodes | length // 0')
    
    echo "$epoch_number $current_round $masternodes"
}

# Get current block number
get_block_number() {
    local result
    result=$(rpc_call "eth_blockNumber")
    printf '%d' "$(echo "$result" | jq -r '.result // "0x0"')" 2>/dev/null || echo 0
}

# Calculate blocks until next epoch
calculate_epoch_progress() {
    local current_block=$1
    local epoch_blocks=$2
    
    local current_epoch_start=$(( (current_block / epoch_blocks) * epoch_blocks ))
    local next_epoch_start=$((current_epoch_start + epoch_blocks))
    local blocks_until_epoch=$((next_epoch_start - current_block))
    local progress=$(( (current_block - current_epoch_start) * 100 / epoch_blocks ))
    
    echo "$blocks_until_epoch $next_epoch_start $progress"
}

# Send notification
send_notification() {
    local level=$1
    local message=$2
    
    log "[$level] $message"
    
    # Webhook notification
    if [[ -n "$WEBHOOK_URL" ]]; then
        local payload
        payload=$(jq -n --arg level "$level" --arg msg "$message" --arg ts "$(date -Iseconds)" \
            '{level: $level, message: $msg, timestamp: $ts, source: "epoch-monitor"}')
        
        curl -sf -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "$payload" 2>/dev/null || warn "Failed to send webhook notification"
    fi
    
    # Telegram notification
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
        local tg_message="🔄 *Epoch Monitor*%0A%0A$message"
        curl -sf "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            -d "chat_id=$TELEGRAM_CHAT_ID" \
            -d "text=$tg_message" \
            -d "parse_mode=Markdown" 2>/dev/null || warn "Failed to send Telegram notification"
    fi
}

# Reset alert state for new epoch
reset_alert_state() {
    echo '{"lastAlert100":false,"lastAlert50":false,"lastAlert10":false}' > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# Update alert state
update_alert_state() {
    local alert_type=$1
    local state
    state=$(cat "$STATE_FILE")
    
    case $alert_type in
        100) state=$(echo "$state" | jq '.lastAlert100 = true') ;;
        50) state=$(echo "$state" | jq '.lastAlert50 = true') ;;
        10) state=$(echo "$state" | jq '.lastAlert10 = true') ;;
    esac
    
    echo "$state" > "$STATE_FILE"
}

# Check if alert was already sent for this epoch
was_alert_sent() {
    local alert_type=$1
    local state
    state=$(cat "$STATE_FILE")
    
    case $alert_type in
        100) echo "$state" | jq -r '.lastAlert100 // false' ;;
        50) echo "$state" | jq -r '.lastAlert50 // false' ;;
        10) echo "$state" | jq -r '.lastAlert10 // false' ;;
        *) echo "false" ;;
    esac
}

# Check for pre-epoch alerts
check_pre_epoch_alerts() {
    local blocks_until=$1
    local epoch_number=$2
    
    # 100 blocks alert
    if [[ $blocks_until -le $ALERT_BLOCKS_100 && $blocks_until -gt $ALERT_BLOCKS_50 ]]; then
        if [[ "$(was_alert_sent 100)" == "false" ]]; then
            send_notification "INFO" "⏰ Epoch $((epoch_number + 1)) approaching in ~$blocks_until blocks (100 block alert)"
            update_alert_state 100
        fi
    fi
    
    # 50 blocks alert
    if [[ $blocks_until -le $ALERT_BLOCKS_50 && $blocks_until -gt $ALERT_BLOCKS_10 ]]; then
        if [[ "$(was_alert_sent 50)" == "false" ]]; then
            send_notification "WARNING" "⚠️ Epoch $((epoch_number + 1)) approaching in ~$blocks_until blocks (50 block alert)"
            update_alert_state 50
        fi
    fi
    
    # 10 blocks alert (critical)
    if [[ $blocks_until -le $ALERT_BLOCKS_10 && $blocks_until -gt 0 ]]; then
        if [[ "$(was_alert_sent 10)" == "false" ]]; then
            send_notification "CRITICAL" "🚨 Epoch $((epoch_number + 1)) imminent in ~$blocks_until blocks (10 block alert - CRITICAL)"
            update_alert_state 10
        fi
    fi
}

# Validate epoch transition
validate_epoch_transition() {
    local epoch_number=$1
    local masternodes=$2
    
    info "Validating epoch $epoch_number transition..."
    
    # Check if we have enough masternodes
    if [[ $masternodes -lt 10 ]]; then
        send_notification "ERROR" "❌ Epoch $epoch_number has only $masternodes masternodes (minimum: 10)"
        return 1
    fi
    
    # Get validator set
    local result
    result=$(rpc_call "XDPoS_getMasternodesByNumber" '["latest"]')
    
    # Check for consensus continuity
    local epoch_result
    epoch_result=$(rpc_call "XDPoS_getEpochInfo" '["latest"]')
    local current_epoch
    current_epoch=$(echo "$epoch_result" | jq -r '.result.EpochNumber // 0')
    
    if [[ "$current_epoch" == "$epoch_number" ]]; then
        send_notification "SUCCESS" "✅ Epoch $epoch_number transition validated successfully with $masternodes masternodes"
        return 0
    else
        send_notification "WARNING" "⚠️ Epoch transition may have failed. Expected: $epoch_number, Got: $current_epoch"
        return 1
    fi
}

# Monitor epoch boundaries
monitor_epochs() {
    local last_epoch=0
    local last_block=0
    
    info "Starting epoch boundary monitoring..."
    info "Epoch length: $EPOCH_BLOCKS blocks"
    
    while true; do
        # Get current status
        local block_num
        block_num=$(get_block_number)
        
        local epoch_info
        epoch_info=$(get_epoch_info)
        local epoch_number
        epoch_number=$(echo "$epoch_info" | awk '{print $1}')
        local current_round
        current_round=$(echo "$epoch_info" | awk '{print $2}')
        local masternodes
        masternodes=$(echo "$epoch_info" | awk '{print $3}')
        
        # Calculate progress
        local epoch_data
        epoch_data=$(calculate_epoch_progress "$block_num" "$EPOCH_BLOCKS")
        local blocks_until
        blocks_until=$(echo "$epoch_data" | awk '{print $1}')
        local next_epoch_start
        next_epoch_start=$(echo "$epoch_data" | awk '{print $2}')
        local progress
        progress=$(echo "$epoch_data" | awk '{print $3}')
        
        # Check for new epoch
        if [[ $epoch_number -gt $last_epoch && $last_epoch -gt 0 ]]; then
            info "New epoch detected: $epoch_number"
            validate_epoch_transition "$epoch_number" "$masternodes"
            reset_alert_state
        fi
        
        # Check for pre-epoch alerts
        check_pre_epoch_alerts "$blocks_until" "$epoch_number"
        
        # Check for missed blocks
        if [[ $last_block -gt 0 && $((block_num - last_block)) -gt 10 ]]; then
            warn "Block production gap detected: $((block_num - last_block)) blocks"
        fi
        
        # Update state
        last_epoch=$epoch_number
        last_block=$block_num
        
        # Save state
        jq -n \
            --arg epoch "$epoch_number" \
            --arg block "$block_num" \
            --arg progress "$progress" \
            '{lastEpoch: ($epoch | tonumber), lastBlock: ($block | tonumber), progress: ($progress | tonumber)}' > "$STATE_FILE.tmp"
        
        # Merge with alert state
        local alert_state
        alert_state=$(cat "$STATE_FILE" | jq '{lastAlert100, lastAlert50, lastAlert10}')
        jq --argjson alerts "$alert_state" '. + $alerts' "$STATE_FILE.tmp" > "$STATE_FILE"
        rm -f "$STATE_FILE.tmp"
        
        # Log status
        info "Epoch: $epoch_number | Round: $current_round | Block: $block_num | Progress: ${progress}% | Masternodes: $masternodes | Next epoch in: $blocks_until blocks"
        
        sleep 30
    done
}

# Get current epoch status
get_status() {
    local block_num
    block_num=$(get_block_number)
    
    local epoch_info
    epoch_info=$(get_epoch_info)
    local epoch_number
    epoch_number=$(echo "$epoch_info" | awk '{print $1}')
    local current_round
    current_round=$(echo "$epoch_info" | awk '{print $2}')
    local masternodes
    masternodes=$(echo "$epoch_info" | awk '{print $3}')
    
    local epoch_data
    epoch_data=$(calculate_epoch_progress "$block_num" "$EPOCH_BLOCKS")
    local blocks_until
    blocks_until=$(echo "$epoch_data" | awk '{print $1}')
    local progress
    progress=$(echo "$epoch_data" | awk '{print $3}')
    
    jq -n \
        --arg epoch "$epoch_number" \
        --arg round "$current_round" \
        --arg block "$block_num" \
        --arg progress "$progress" \
        --arg until "$blocks_until" \
        --arg masternodes "$masternodes" \
        '{
            epoch: ($epoch | tonumber),
            round: ($round | tonumber),
            blockNumber: ($block | tonumber),
            progress: ($progress | tonumber),
            blocksUntilNextEpoch: ($until | tonumber),
            masternodes: ($masternodes | tonumber),
            timestamp: now | todate
        }'
}

# Show usage
show_help() {
    cat <<'EOF'
XDPoS 2.0 Epoch Boundary Monitor v1.0.0

Usage: epoch-monitor.sh <command> [options]

Commands:
  monitor              Start continuous epoch monitoring (daemon mode)
  status               Get current epoch status
  check <epoch>        Check specific epoch validation

Environment Variables:
  RPC_URL              XDC node RPC endpoint
  XDPOS_EPOCH_BLOCKS   Epoch length in blocks (default: 900)
  EPOCH_ALERT_100      Alert threshold for 100 blocks before (default: 100)
  EPOCH_ALERT_50       Alert threshold for 50 blocks before (default: 50)
  EPOCH_ALERT_10       Alert threshold for 10 blocks before (default: 10)
  EPOCH_WEBHOOK_URL    Webhook URL for notifications
  EPOCH_TELEGRAM_TOKEN Telegram bot token
  EPOCH_TELEGRAM_CHAT  Telegram chat ID

Alert Levels:
  - 100 blocks: INFO notification
  - 50 blocks:  WARNING notification
  - 10 blocks:  CRITICAL notification

Examples:
  ./epoch-monitor.sh monitor           # Start monitoring daemon
  ./epoch-monitor.sh status            # Get current epoch status
  ./epoch-monitor.sh check 12345       # Validate specific epoch
EOF
}

# Main
main() {
    init
    
    case "${1:-}" in
        monitor)
            monitor_epochs
            ;;
        status)
            get_status
            ;;
        check)
            epoch="${2:-}"
            if [[ -z "$epoch" ]]; then
                error "Epoch number required"
                exit 1
            fi
            # Get current masternode info for validation
            local result
            result=$(rpc_call "XDPoS_getMasternodesByNumber" "[\"0x$(printf '%x' $epoch)\"]")
            local masternodes
            masternodes=$(echo "$result" | jq -r '.result.Masternodes | length // 0')
            validate_epoch_transition "$epoch" "$masternodes"
            ;;
        --help|-h)
            show_help
            ;;
        *)
            error "Unknown command: ${1:-}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
