#!/usr/bin/env bash
#
# XDC Node Notification Library
# Provides unified notification capabilities via Platform API, Telegram, and Email
#
# Usage:
#   source /opt/xdc-node/scripts/lib/notify.sh
#   notify_alert "critical" "Node Offline" "XDC node is not responding to RPC calls"
#   notify_report "daily_health" "Daily Health Report" "$report_content"
#

set -euo pipefail

#==============================================================================
# Configuration Paths
#==============================================================================
readonly NOTIFY_CONFIG_DIR="/etc/xdc-node"
readonly NOTIFY_CONFIG_FILE="${NOTIFY_CONFIG_DIR}/notify.conf"
readonly NOTIFY_STATE_DIR="/var/lib/xdc-node"
readonly NOTIFY_STATE_FILE="${NOTIFY_STATE_DIR}/alert-state.json"
readonly NOTIFY_LOG_DIR="/var/log/xdc-node"
readonly NOTIFY_LOG_FILE="${NOTIFY_LOG_DIR}/notifications.log"
readonly NOTIFY_DIGEST_FILE="${NOTIFY_STATE_DIR}/digest.json"
readonly NOTIFY_TEMPLATE_DIR="/opt/xdc-node/templates/email"

#==============================================================================
# Default Configuration
#==============================================================================
NOTIFY_CHANNELS="${NOTIFY_CHANNELS:-platform}"
NOTIFY_PLATFORM_URL="${NOTIFY_PLATFORM_URL:-https://cloud.xdcrpc.com/api/v1/notifications}"
NOTIFY_PLATFORM_API_KEY="${NOTIFY_PLATFORM_API_KEY:-}"
NOTIFY_TELEGRAM_BOT_TOKEN="${NOTIFY_TELEGRAM_BOT_TOKEN:-}"
NOTIFY_TELEGRAM_CHAT_ID="${NOTIFY_TELEGRAM_CHAT_ID:-}"
NOTIFY_EMAIL_ENABLED="${NOTIFY_EMAIL_ENABLED:-false}"
NOTIFY_EMAIL_TO="${NOTIFY_EMAIL_TO:-}"
NOTIFY_EMAIL_FROM="${NOTIFY_EMAIL_FROM:-alerts@xdc.network}"
NOTIFY_EMAIL_SMTP_HOST="${NOTIFY_EMAIL_SMTP_HOST:-smtp.gmail.com}"
NOTIFY_EMAIL_SMTP_PORT="${NOTIFY_EMAIL_SMTP_PORT:-587}"
NOTIFY_EMAIL_SMTP_USER="${NOTIFY_EMAIL_SMTP_USER:-}"
NOTIFY_EMAIL_SMTP_PASS="${NOTIFY_EMAIL_SMTP_PASS:-}"
NOTIFY_ALERT_INTERVAL="${NOTIFY_ALERT_INTERVAL:-300}"
NOTIFY_REPORT_INTERVAL="${NOTIFY_REPORT_INTERVAL:-86400}"
NOTIFY_DIGEST_ENABLED="${NOTIFY_DIGEST_ENABLED:-true}"
NOTIFY_DIGEST_INTERVAL="${NOTIFY_DIGEST_INTERVAL:-3600}"
NOTIFY_QUIET_START="${NOTIFY_QUIET_START:-23:00}"
NOTIFY_QUIET_END="${NOTIFY_QUIET_END:-07:00}"
NOTIFY_RATE_LIMIT_PER_HOUR="${NOTIFY_RATE_LIMIT_PER_HOUR:-10}"
NOTIFY_RETRY_MAX="${NOTIFY_RETRY_MAX:-3}"
NOTIFY_NODE_HOST="${NOTIFY_NODE_HOST:-$(hostname -I 2>/dev/null | awk '{print $1}' || hostname)}"

#==============================================================================
# Internal State
#==============================================================================
__NOTIFY_LOADED=false
__NOTIFY_RATE_COUNT=0
__NOTIFY_RATE_WINDOW=$(date +%s)

#==============================================================================
# Logging
#==============================================================================
_notify_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date -Iseconds)
    
    # Ensure log directory exists
    mkdir -p "$NOTIFY_LOG_DIR" 2>/dev/null || true
    
    # Write to log file
    echo "[$timestamp] [$level] $message" >> "$NOTIFY_LOG_FILE" 2>/dev/null || true
    
    # Also log to stderr for critical errors
    if [[ "$level" == "ERROR" ]]; then
        echo "[$timestamp] [$level] $message" >&2
    fi
}

#==============================================================================
# Configuration Loading
#==============================================================================
notify_load_config() {
    if [[ -f "$NOTIFY_CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$NOTIFY_CONFIG_FILE"
        _notify_log "INFO" "Loaded configuration from $NOTIFY_CONFIG_FILE"
    fi
    
    # Ensure state directory exists
    mkdir -p "$NOTIFY_STATE_DIR" 2>/dev/null || true
    
    # Initialize state file if not exists
    if [[ ! -f "$NOTIFY_STATE_FILE" ]]; then
        echo '{}' > "$NOTIFY_STATE_FILE"
    fi
    
    # Initialize digest file if not exists
    if [[ ! -f "$NOTIFY_DIGEST_FILE" ]]; then
        echo '{"alerts": [], "last_sent": 0}' > "$NOTIFY_DIGEST_FILE"
    fi
    
    __NOTIFY_LOADED=true
}

#==============================================================================
# State Management
#==============================================================================
_notify_get_state() {
    local key="$1"
    local default="${2:-}"
    
    if [[ -f "$NOTIFY_STATE_FILE" ]]; then
        jq -r ".${key} // \"$default\"" "$NOTIFY_STATE_FILE" 2>/dev/null || echo "$default"
    else
        echo "$default"
    fi
}

_notify_set_state() {
    local key="$1"
    local value="$2"
    
    local tmp_file="${NOTIFY_STATE_FILE}.tmp"
    jq ".${key} = \"$value\"" "$NOTIFY_STATE_FILE" > "$tmp_file" 2>/dev/null && \
        mv "$tmp_file" "$NOTIFY_STATE_FILE" || true
}

_notify_get_alert_last_sent() {
    local alert_type="$1"
    _notify_get_state "alerts.${alert_type}.last_sent" "0"
}

_notify_set_alert_sent() {
    local alert_type="$1"
    local timestamp
    timestamp=$(date +%s)
    
    local tmp_file="${NOTIFY_STATE_FILE}.tmp"
    jq ".alerts.\"${alert_type}\".last_sent = $timestamp" "$NOTIFY_STATE_FILE" > "$tmp_file" 2>/dev/null && \
        mv "$tmp_file" "$NOTIFY_STATE_FILE" || true
}

#==============================================================================
# Rate Limiting
#==============================================================================
_notify_check_rate_limit() {
    local now
    now=$(date +%s)
    local window_start=$((now - 3600))
    
    # Reset counter if window has passed
    if [[ $__NOTIFY_RATE_WINDOW -lt $window_start ]]; then
        __NOTIFY_RATE_COUNT=0
        __NOTIFY_RATE_WINDOW=$now
    fi
    
    # Check if limit exceeded
    if [[ $__NOTIFY_RATE_COUNT -ge $NOTIFY_RATE_LIMIT_PER_HOUR ]]; then
        _notify_log "WARN" "Rate limit exceeded ($NOTIFY_RATE_LIMIT_PER_HOUR per hour)"
        return 1
    fi
    
    ((__NOTIFY_RATE_COUNT++)) || true
    return 0
}

#==============================================================================
# Quiet Hours Check
#==============================================================================
_notify_is_quiet_hours() {
    local current_time
    current_time=$(date +%H:%M)
    
    # Parse quiet hours
    local quiet_start="${NOTIFY_QUIET_START:-23:00}"
    local quiet_end="${NOTIFY_QUIET_END:-07:00}"
    
    # Convert to minutes since midnight for comparison
    local current_minutes
    local start_minutes
    local end_minutes
    
    current_minutes=$(echo "$current_time" | awk -F: '{print $1*60 + $2}')
    start_minutes=$(echo "$quiet_start" | awk -F: '{print $1*60 + $2}')
    end_minutes=$(echo "$quiet_end" | awk -F: '{print $1*60 + $2}')
    
    # Handle overnight quiet period (e.g., 23:00 to 07:00)
    if [[ $start_minutes -gt $end_minutes ]]; then
        # Quiet period spans midnight
        if [[ $current_minutes -ge $start_minutes || $current_minutes -lt $end_minutes ]]; then
            return 0  # In quiet hours
        fi
    else
        # Quiet period within same day
        if [[ $current_minutes -ge $start_minutes && $current_minutes -lt $end_minutes ]]; then
            return 0  # In quiet hours
        fi
    fi
    
    return 1  # Not in quiet hours
}

#==============================================================================
# Deduplication Check
#==============================================================================
_notify_should_send_alert() {
    local alert_type="$1"
    local level="$2"
    
    # Critical alerts always send
    if [[ "$level" == "critical" ]]; then
        return 0
    fi
    
    # Check if enough time has passed since last alert
    local last_sent
    last_sent=$(_notify_get_alert_last_sent "$alert_type")
    local now
    now=$(date +%s)
    local elapsed=$((now - last_sent))
    
    if [[ $elapsed -lt $NOTIFY_ALERT_INTERVAL ]]; then
        _notify_log "INFO" "Alert '$alert_type' deduplicated (${elapsed}s < ${NOTIFY_ALERT_INTERVAL}s)"
        return 1
    fi
    
    return 0
}

#==============================================================================
# Retry Logic
#==============================================================================
_notify_with_retry() {
    local cmd="$1"
    local description="${2:-command}"
    local max_retries="${NOTIFY_RETRY_MAX:-3}"
    
    local attempt=1
    local delay=2
    
    while [[ $attempt -le $max_retries ]]; do
        if eval "$cmd" 2>/dev/null; then
            _notify_log "INFO" "$description succeeded on attempt $attempt"
            return 0
        fi
        
        if [[ $attempt -lt $max_retries ]]; then
            _notify_log "WARN" "$description failed (attempt $attempt/$max_retries), retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        ((attempt++)) || true
    done
    
    _notify_log "ERROR" "$description failed after $max_retries attempts"
    return 1
}

#==============================================================================
# Platform API Notification
#==============================================================================
notify_platform() {
    local level="$1"
    local title="$2"
    local message="$3"
    local alert_type="${4:-general}"
    local channels="${5:-telegram,email}"
    
    # Check if platform API is configured
    if [[ -z "$NOTIFY_PLATFORM_API_KEY" ]]; then
        _notify_log "DEBUG" "Platform API key not configured, skipping platform notification"
        return 1
    fi
    
    # Build JSON payload
    local payload
    payload=$(jq -n \
        --arg type "alert" \
        --arg level "$level" \
        --arg title "$title" \
        --arg message "$message" \
        --argjson channels "[$(echo "$channels" | tr ',' '\n' | jq -R . | jq -s . | jq -c .[] | paste -sd, -)]" \
        --arg nodeHost "$NOTIFY_NODE_HOST" \
        --arg alertType "$alert_type" \
        '{
            type: $type,
            level: $level,
            title: $title,
            message: $message,
            channels: $channels,
            metadata: {
                nodeHost: $nodeHost,
                alertType: $alertType,
                timestamp: now | todate
            }
        }'
    )
    
    local curl_cmd="curl -s -X POST \"${NOTIFY_PLATFORM_URL}\" \
        -H \"Content-Type: application/json\" \
        -H \"Authorization: Bearer ${NOTIFY_PLATFORM_API_KEY}\" \
        -d '${payload}'"
    
    if _notify_with_retry "$curl_cmd" "Platform API notification"; then
        _notify_log "INFO" "Platform notification sent: $title"
        return 0
    else
        _notify_log "ERROR" "Platform notification failed: $title"
        return 1
    fi
}

#==============================================================================
# Telegram Notification
#==============================================================================
notify_telegram() {
    local level="$1"
    local title="$2"
    local message="$3"
    
    # Check if Telegram is configured
    if [[ -z "$NOTIFY_TELEGRAM_BOT_TOKEN" || -z "$NOTIFY_TELEGRAM_CHAT_ID" ]]; then
        _notify_log "DEBUG" "Telegram not configured, skipping"
        return 1
    fi
    
    # Build message with level indicator
    local level_icon
    case "$level" in
        critical) level_icon="🔴" ;;
        warning)  level_icon="🟡" ;;
        info)     level_icon="🔵" ;;
        *)        level_icon="⚪" ;;
    esac
    
    local full_message="${level_icon} *${title}*

${message}

📍 Node: \`${NOTIFY_NODE_HOST}\`
⏰ $(date '+%Y-%m-%d %H:%M:%S UTC')"
    
    # Escape for JSON
    full_message=$(echo "$full_message" | sed 's/\\/\\\\/g; s/"/\\"/g')
    
    local api_url="https://api.telegram.org/bot${NOTIFY_TELEGRAM_BOT_TOKEN}/sendMessage"
    local curl_cmd="curl -s -X POST \"${api_url}\" \
        -H \"Content-Type: application/json\" \
        -d \"{\\\"chat_id\\\":\\\"${NOTIFY_TELEGRAM_CHAT_ID}\\\",\\\"text\\\":\\\"${full_message}\\\",\\\"parse_mode\\\":\\\"Markdown\\\"}\""
    
    if _notify_with_retry "$curl_cmd" "Telegram notification"; then
        _notify_log "INFO" "Telegram notification sent: $title"
        return 0
    else
        _notify_log "ERROR" "Telegram notification failed: $title"
        return 1
    fi
}

#==============================================================================
# Email Notification
#==============================================================================
notify_email() {
    local level="$1"
    local title="$2"
    local message="$3"
    local template="${4:-alert}"
    
    # Check if email is enabled and configured
    if [[ "$NOTIFY_EMAIL_ENABLED" != "true" ]]; then
        _notify_log "DEBUG" "Email not enabled, skipping"
        return 1
    fi
    
    if [[ -z "$NOTIFY_EMAIL_TO" ]]; then
        _notify_log "WARN" "Email enabled but no recipient configured"
        return 1
    fi
    
    # Determine which send method to use
    if [[ -n "$NOTIFY_PLATFORM_API_KEY" ]]; then
        # Use platform API to send email
        notify_platform "$level" "$title" "$message" "email" "email"
        return $?
    elif [[ -n "$NOTIFY_EMAIL_SMTP_HOST" && -n "$NOTIFY_EMAIL_SMTP_USER" ]]; then
        # Use direct SMTP
        _notify_email_smtp "$level" "$title" "$message" "$template"
        return $?
    else
        # Try sendmail as fallback
        _notify_email_sendmail "$level" "$title" "$message"
        return $?
    fi
}

_notify_email_smtp() {
    local level="$1"
    local title="$2"
    local message="$3"
    local template="$4"
    
    # Generate HTML email content
    local html_content
    html_content=$(_notify_generate_email_html "$level" "$title" "$message" "$template")
    
    # Create email headers and content
    local boundary="----=_NextPart_$(date +%s)_$$"
    local subject="[XDC Node] $title"
    
    # Use curl with smtps or send via msmtp if available
    if command -v msmtp &>/dev/null; then
        # Configure msmtp
        local msmtp_config="/tmp/msmtp-$$.conf"
        cat > "$msmtp_config" << EOF
account default
host $NOTIFY_EMAIL_SMTP_HOST
port $NOTIFY_EMAIL_SMTP_PORT
from $NOTIFY_EMAIL_FROM
user $NOTIFY_EMAIL_SMTP_USER
password $NOTIFY_EMAIL_SMTP_PASS
auth on
tls on
tls_starttls on
EOF
        
        # Send email
        {
            echo "Subject: $subject"
            echo "To: $NOTIFY_EMAIL_TO"
            echo "From: $NOTIFY_EMAIL_FROM"
            echo "Content-Type: text/html; charset=UTF-8"
            echo ""
            echo "$html_content"
        } | msmtp --file="$msmtp_config" "$NOTIFY_EMAIL_TO" 2>/dev/null
        
        local result=$?
        rm -f "$msmtp_config"
        
        if [[ $result -eq 0 ]]; then
            _notify_log "INFO" "Email sent via msmtp: $title"
            return 0
        fi
    fi
    
    # Fallback to curl with SMTP
    local email_data
    email_data=$(cat << EOF
Subject: $subject
To: $NOTIFY_EMAIL_TO
From: $NOTIFY_EMAIL_FROM
Content-Type: text/html; charset=UTF-8

$html_content
EOF
)
    
    # URL encode the email data for curl
    local encoded_data
    encoded_data=$(echo "$email_data" | curl -Gso /dev/null -w %{url_effective} --data-urlencode @- "") 2>/dev/null || true
    
    _notify_log "WARN" "SMTP email not fully implemented, would send: $subject"
    return 1
}

_notify_email_sendmail() {
    local level="$1"
    local title="$2"
    local message="$3"
    
    if ! command -v sendmail &>/dev/null; then
        _notify_log "DEBUG" "sendmail not available"
        return 1
    fi
    
    local subject="[XDC Node] $title"
    
    {
        echo "Subject: $subject"
        echo "To: $NOTIFY_EMAIL_TO"
        echo "From: $NOTIFY_EMAIL_FROM"
        echo ""
        echo "$message"
    } | sendmail "$NOTIFY_EMAIL_TO" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        _notify_log "INFO" "Email sent via sendmail: $title"
        return 0
    else
        _notify_log "ERROR" "sendmail failed"
        return 1
    fi
}

_notify_generate_email_html() {
    local level="$1"
    local title="$2"
    local message="$3"
    local template="${4:-alert}"
    
    # Determine colors based on level
    local header_color="#1F4CED"  # XDC Blue default
    local header_bg="#1a1a2e"
    
    case "$level" in
        critical)
            header_color="#dc3545"
            header_bg="#2d1b1b"
            ;;
        warning)
            header_color="#ffc107"
            header_bg="#2d2a1b"
            ;;
        info)
            header_color="#17a2b8"
            header_bg="#1b2d2d"
            ;;
    esac
    
    # Try to load template if exists
    local template_file="${NOTIFY_TEMPLATE_DIR}/${template}.html"
    if [[ -f "$template_file" ]]; then
        # Simple template substitution
        local content
        content=$(cat "$template_file")
        content="${content//\{\{TITLE\}\}/$title}"
        content="${content//\{\{MESSAGE\}\}/$message}"
        content="${content//\{\{LEVEL\}\}/$level}"
        content="${content//\{\{NODE_HOST\}\}/$NOTIFY_NODE_HOST}"
        content="${content//\{\{TIMESTAMP\}\}/$(date '+%Y-%m-%d %H:%M:%S UTC')}"
        content="${content//\{\{HEADER_COLOR\}\}/$header_color}"
        content="${content//\{\{HEADER_BG\}\}/$header_bg}"
        echo "$content"
    else
        # Fallback to simple HTML
        cat << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>${title}</title>
</head>
<body style="font-family: Arial, sans-serif; background: #0a0a0f; color: #e0e0e0; margin: 0; padding: 20px;">
    <div style="max-width: 600px; margin: 0 auto; background: #12121a; border-radius: 8px; overflow: hidden;">
        <div style="background: $header_bg; padding: 20px; border-left: 4px solid $header_color;">
            <h1 style="color: $header_color; margin: 0; font-size: 24px;">$title</h1>
        </div>
        <div style="padding: 20px; line-height: 1.6;">
            <p style="white-space: pre-wrap;">$message</p>
            <hr style="border: none; border-top: 1px solid #2a2a3a; margin: 20px 0;">
            <p style="color: #888; font-size: 12px;">
                Node: $NOTIFY_NODE_HOST<br>
                Time: $(date '+%Y-%m-%d %H:%M:%S UTC')
            </p>
        </div>
    </div>
</body>
</html>
EOF
    fi
}

#==============================================================================
# Digest Management
#==============================================================================
_notify_add_to_digest() {
    local level="$1"
    local title="$2"
    local message="$3"
    local alert_type="$4"
    
    local timestamp
    timestamp=$(date +%s)
    
    local entry
    entry=$(jq -n \
        --arg level "$level" \
        --arg title "$title" \
        --arg message "$message" \
        --arg alertType "$alert_type" \
        --argjson timestamp "$timestamp" \
        '{level: $level, title: $title, message: $message, alertType: $alertType, timestamp: $timestamp}'
    )
    
    local tmp_file="${NOTIFY_DIGEST_FILE}.tmp"
    jq ".alerts += [$entry]" "$NOTIFY_DIGEST_FILE" > "$tmp_file" 2>/dev/null && \
        mv "$tmp_file" "$NOTIFY_DIGEST_FILE" || true
    
    _notify_log "INFO" "Added to digest: $title"
}

_notify_send_digest() {
    if [[ "$NOTIFY_DIGEST_ENABLED" != "true" ]]; then
        return 0
    fi
    
    local now
    now=$(date +%s)
    local last_sent
    last_sent=$(jq -r '.last_sent // 0' "$NOTIFY_DIGEST_FILE" 2>/dev/null || echo "0")
    local elapsed=$((now - last_sent))
    
    if [[ $elapsed -lt $NOTIFY_DIGEST_INTERVAL ]]; then
        return 0  # Not time to send digest yet
    fi
    
    local alert_count
    alert_count=$(jq '.alerts | length' "$NOTIFY_DIGEST_FILE" 2>/dev/null || echo "0")
    
    if [[ $alert_count -eq 0 ]]; then
        return 0  # No alerts to send
    fi
    
    # Build digest message
    local digest_title="XDC Node Alert Digest ($(date '+%Y-%m-%d %H:%M'))"
    local digest_message
    digest_message=$(jq -r '.alerts | map("• [\(.level | ascii_upcase)] \(.title): \(.message | split("\n")[0])") | join("\n")' "$NOTIFY_DIGEST_FILE" 2>/dev/null)
    
    # Send digest to all channels
    local channels="${NOTIFY_CHANNELS// /}"
    IFS=',' read -ra CHANNEL_ARRAY <<< "$channels"
    
    for channel in "${CHANNEL_ARRAY[@]}"; do
        case "$channel" in
            platform)
                notify_platform "info" "$digest_title" "$digest_message" "digest"
                ;;
            telegram)
                notify_telegram "info" "$digest_title" "$digest_message"
                ;;
            email)
                notify_email "info" "$digest_title" "$digest_message" "digest"
                ;;
        esac
    done
    
    # Clear digest
    echo '{"alerts": [], "last_sent": '$(date +%s)'}' > "$NOTIFY_DIGEST_FILE"
    _notify_log "INFO" "Digest sent with $alert_count alerts"
}

#==============================================================================
# Main Notification Functions
#==============================================================================
notify() {
    local level="${1:-info}"
    local title="$2"
    local message="$3"
    local alert_type="${4:-general}"
    local force="${5:-false}"
    
    # Load config if not already loaded
    if [[ "$__NOTIFY_LOADED" != "true" ]]; then
        notify_load_config
    fi
    
    # Check rate limiting
    if ! _notify_check_rate_limit; then
        return 1
    fi
    
    # Check deduplication (unless forced)
    if [[ "$force" != "true" ]]; then
        if ! _notify_should_send_alert "$alert_type" "$level"; then
            return 0
        fi
    fi
    
    # Check quiet hours for non-critical alerts
    if [[ "$level" != "critical" ]] && _notify_is_quiet_hours; then
        if [[ "$NOTIFY_DIGEST_ENABLED" == "true" ]]; then
            _notify_add_to_digest "$level" "$title" "$message" "$alert_type"
            _notify_log "INFO" "Alert queued for digest (quiet hours): $title"
        else
            _notify_log "INFO" "Alert suppressed (quiet hours): $title"
        fi
        return 0
    fi
    
    # Update alert state
    _notify_set_alert_sent "$alert_type"
    
    # Send to configured channels
    local channels="${NOTIFY_CHANNELS// /}"
    IFS=',' read -ra CHANNEL_ARRAY <<< "$channels"
    local success_count=0
    
    for channel in "${CHANNEL_ARRAY[@]}"; do
        case "$channel" in
            platform)
                if notify_platform "$level" "$title" "$message" "$alert_type"; then
                    ((success_count++)) || true
                fi
                ;;
            telegram)
                if notify_telegram "$level" "$title" "$message"; then
                    ((success_count++)) || true
                fi
                ;;
            email)
                if notify_email "$level" "$title" "$message" "alert"; then
                    ((success_count++)) || true
                fi
                ;;
        esac
    done
    
    # Check if any channel succeeded
    if [[ $success_count -eq 0 && ${#CHANNEL_ARRAY[@]} -gt 0 ]]; then
        _notify_log "ERROR" "All notification channels failed for: $title"
        return 1
    fi
    
    _notify_log "INFO" "Notification sent successfully: $title"
    return 0
}

notify_alert() {
    local level="${1:-warning}"
    local title="$2"
    local message="$3"
    local alert_type="${4:-general}"
    
    notify "$level" "$title" "$message" "$alert_type" "true"
}

notify_report() {
    local report_type="$1"
    local title="$2"
    local content="$3"
    local template="${4:-report}"
    
    # Load config if not already loaded
    if [[ "$__NOTIFY_LOADED" != "true" ]]; then
        notify_load_config
    fi
    
    # Check report interval
    local last_report
    last_report=$(_notify_get_state "reports.${report_type}.last_sent" "0")
    local now
    now=$(date +%s)
    local elapsed=$((now - last_report))
    
    if [[ $elapsed -lt $NOTIFY_REPORT_INTERVAL ]]; then
        _notify_log "DEBUG" "Report '$report_type' skipped (${elapsed}s < ${NOTIFY_REPORT_INTERVAL}s)"
        return 0
    fi
    
    # Update report state
    _notify_set_state "reports.${report_type}.last_sent" "$now"
    
    # Send report to all channels
    local channels="${NOTIFY_CHANNELS// /}"
    IFS=',' read -ra CHANNEL_ARRAY <<< "$channels"
    
    for channel in "${CHANNEL_ARRAY[@]}"; do
        case "$channel" in
            platform)
                notify_platform "info" "$title" "$content" "$report_type"
                ;;
            telegram)
                notify_telegram "info" "$title" "$content"
                ;;
            email)
                notify_email "info" "$title" "$content" "$template"
                ;;
        esac
    done
    
    _notify_log "INFO" "Report sent: $title"
}

notify_test() {
    # Load config if not already loaded
    if [[ "$__NOTIFY_LOADED" != "true" ]]; then
        notify_load_config
    fi
    
    echo "XDC Node Notification Test"
    echo "=========================="
    echo ""
    echo "Configuration:"
    echo "  Channels: $NOTIFY_CHANNELS"
    echo "  Node Host: $NOTIFY_NODE_HOST"
    echo "  Quiet Hours: $NOTIFY_QUIET_START - $NOTIFY_QUIET_END"
    echo "  Digest Enabled: $NOTIFY_DIGEST_ENABLED"
    echo ""
    
    local channels="${NOTIFY_CHANNELS// /}"
    IFS=',' read -ra CHANNEL_ARRAY <<< "$channels"
    local results=()
    
    for channel in "${CHANNEL_ARRAY[@]}"; do
        echo -n "Testing $channel... "
        local result="SKIPPED"
        
        case "$channel" in
            platform)
                if [[ -n "$NOTIFY_PLATFORM_API_KEY" ]]; then
                    if notify_platform "info" "Test Notification" "This is a test notification from your XDC node at $NOTIFY_NODE_HOST" "test"; then
                        result="✓ OK"
                    else
                        result="✗ FAILED"
                    fi
                else
                    result="✗ NO API KEY"
                fi
                ;;
            telegram)
                if [[ -n "$NOTIFY_TELEGRAM_BOT_TOKEN" && -n "$NOTIFY_TELEGRAM_CHAT_ID" ]]; then
                    if notify_telegram "info" "Test Notification" "This is a test notification from your XDC node"; then
                        result="✓ OK"
                    else
                        result="✗ FAILED"
                    fi
                else
                    result="✗ NOT CONFIGURED"
                fi
                ;;
            email)
                if [[ "$NOTIFY_EMAIL_ENABLED" == "true" && -n "$NOTIFY_EMAIL_TO" ]]; then
                    if notify_email "info" "Test Notification" "This is a test notification from your XDC node at $NOTIFY_NODE_HOST" "alert"; then
                        result="✓ OK"
                    else
                        result="✗ FAILED"
                    fi
                else
                    result="✗ NOT CONFIGURED"
                fi
                ;;
            *)
                result="✗ UNKNOWN CHANNEL"
                ;;
        esac
        
        echo "$result"
        results+=("$channel: $result")
    done
    
    echo ""
    echo "Test complete!"
    
    # Return 0 if all configured channels worked
    for r in "${results[@]}"; do
        if [[ "$r" == *"✗ FAILED"* ]] || [[ "$r" == *"✗ NO"* ]]; then
            return 1
        fi
    done
    
    return 0
}

#==============================================================================
# Initialization
#==============================================================================
notify_load_config
