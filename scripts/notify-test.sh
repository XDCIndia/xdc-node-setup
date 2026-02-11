#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDC Node Notification Test Script
# Tests all configured notification channels
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#==============================================================================
# Helper Functions
#==============================================================================
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

#==============================================================================
# Print Banner
#==============================================================================
print_banner() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           XDC Node Notification Test                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

#==============================================================================
# Check Prerequisites
#==============================================================================
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if notify.sh library exists
    if [[ ! -f "${LIB_DIR}/notify.sh" ]]; then
        error "Notification library not found: ${LIB_DIR}/notify.sh"
        exit 1
    fi
    
    # Check for jq
    if ! command -v jq &>/dev/null; then
        error "jq is required but not installed. Run: apt-get install jq"
        exit 1
    fi
    
    # Check for curl
    if ! command -v curl &>/dev/null; then
        error "curl is required but not installed."
        exit 1
    fi
    
    log "✓ Prerequisites check passed"
}

#==============================================================================
# Load Configuration
#==============================================================================
load_configuration() {
    info "Loading notification configuration..."
    
    # Source the notification library
    # shellcheck source=/dev/null
    source "${LIB_DIR}/notify.sh"
    
    echo ""
    echo "Current Configuration:"
    echo "  Config File: ${NOTIFY_CONFIG_FILE}"
    echo "  Channels: ${NOTIFY_CHANNELS}"
    echo "  Node Host: ${NOTIFY_NODE_HOST}"
    echo "  Quiet Hours: ${NOTIFY_QUIET_START} - ${NOTIFY_QUIET_END}"
    echo "  Digest Mode: ${NOTIFY_DIGEST_ENABLED}"
    echo ""
    
    # Show channel-specific config
    echo "Channel Details:"
    
    # Check Platform API
    if [[ -n "$NOTIFY_PLATFORM_API_KEY" ]]; then
        echo "  ✓ Platform API: Configured (API key set)"
    else
        echo "  ✗ Platform API: Not configured (no API key)"
    fi
    
    # Check Telegram
    if [[ -n "$NOTIFY_TELEGRAM_BOT_TOKEN" && -n "$NOTIFY_TELEGRAM_CHAT_ID" ]]; then
        echo "  ✓ Telegram: Configured (bot token and chat ID set)"
    else
        echo "  ✗ Telegram: Not configured"
    fi
    
    # Check Email
    if [[ "$NOTIFY_EMAIL_ENABLED" == "true" ]]; then
        if [[ -n "$NOTIFY_EMAIL_TO" ]]; then
            echo "  ✓ Email: Enabled (recipient: $NOTIFY_EMAIL_TO)"
        else
            echo "  ⚠ Email: Enabled but no recipient configured"
        fi
    else
        echo "  ✗ Email: Disabled"
    fi
    
    echo ""
}

#==============================================================================
# Test Platform API
#==============================================================================
test_platform_api() {
    echo "═══════════════════════════════════════════════════════════════"
    echo "Testing Platform API"
    echo "═══════════════════════════════════════════════════════════════"
    
    if [[ -z "$NOTIFY_PLATFORM_API_KEY" ]]; then
        warn "Platform API key not configured, skipping test"
        return 1
    fi
    
    info "Sending test notification via Platform API..."
    info "URL: $NOTIFY_PLATFORM_URL"
    
    if notify_platform "info" "XDC Node Test" "This is a test notification from your XDC node at $NOTIFY_NODE_HOST" "test"; then
        log "✓ Platform API test PASSED"
        return 0
    else
        error "✗ Platform API test FAILED"
        return 1
    fi
}

#==============================================================================
# Test Telegram
#==============================================================================
test_telegram() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Testing Telegram"
    echo "═══════════════════════════════════════════════════════════════"
    
    if [[ -z "$NOTIFY_TELEGRAM_BOT_TOKEN" || -z "$NOTIFY_TELEGRAM_CHAT_ID" ]]; then
        warn "Telegram not configured, skipping test"
        info "To configure Telegram:"
        info "  1. Create a bot via @BotFather (https://t.me/BotFather)"
        info "  2. Get your chat ID from @userinfobot (https://t.me/userinfobot)"
        info "  3. Set NOTIFY_TELEGRAM_BOT_TOKEN and NOTIFY_TELEGRAM_CHAT_ID"
        return 1
    fi
    
    info "Sending test notification via Telegram..."
    
    if notify_telegram "info" "XDC Node Test" "This is a test notification from your XDC node 🚀"; then
        log "✓ Telegram test PASSED"
        return 0
    else
        error "✗ Telegram test FAILED"
        return 1
    fi
}

#==============================================================================
# Test Email
#==============================================================================
test_email() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Testing Email"
    echo "═══════════════════════════════════════════════════════════════"
    
    if [[ "$NOTIFY_EMAIL_ENABLED" != "true" ]]; then
        warn "Email not enabled, skipping test"
        return 1
    fi
    
    if [[ -z "$NOTIFY_EMAIL_TO" ]]; then
        error "Email enabled but no recipient configured (NOTIFY_EMAIL_TO)"
        return 1
    fi
    
    info "Sending test notification via Email..."
    info "Recipient: $NOTIFY_EMAIL_TO"
    
    if notify_email "info" "XDC Node Test" "This is a test notification from your XDC node at $NOTIFY_NODE_HOST" "alert"; then
        log "✓ Email test PASSED"
        return 0
    else
        error "✗ Email test FAILED"
        return 1
    fi
}

#==============================================================================
# Test Different Alert Levels
#==============================================================================
test_alert_levels() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Testing Alert Levels"
    echo "═══════════════════════════════════════════════════════════════"
    
    local channels="${NOTIFY_CHANNELS// /}"
    IFS=',' read -ra CHANNEL_ARRAY <<< "$channels"
    
    for level in "info" "warning" "critical"; do
        info "Testing $level level alert..."
        
        local icon=""
        case "$level" in
            info) icon="🔵" ;;
            warning) icon="🟡" ;;
            critical) icon="🔴" ;;
        esac
        
        if notify "$level" "Test $level Alert" "This is a test $level level notification from your XDC node" "test_$level" "true"; then
            log "✓ $level level notification sent"
        else
            error "✗ $level level notification failed"
        fi
        
        # Small delay between tests
        sleep 1
    done
}

#==============================================================================
# Test Digest Mode
#==============================================================================
test_digest_mode() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Testing Digest Mode"
    echo "═══════════════════════════════════════════════════════════════"
    
    if [[ "$NOTIFY_DIGEST_ENABLED" != "true" ]]; then
        warn "Digest mode not enabled, skipping test"
        return 0
    fi
    
    info "Adding test alerts to digest queue..."
    
    # Add a few test alerts to digest
    _notify_add_to_digest "warning" "Test Digest Alert 1" "This is the first test alert for digest" "test_digest_1"
    _notify_add_to_digest "info" "Test Digest Alert 2" "This is the second test alert for digest" "test_digest_2"
    
    log "✓ Added 2 test alerts to digest queue"
    
    info "Current digest queue:"
    local alert_count
    alert_count=$(jq '.alerts | length' "$NOTIFY_DIGEST_FILE" 2>/dev/null || echo "0")
    echo "  Alerts in queue: $alert_count"
    
    info "Digest will be sent automatically during the next digest interval"
    info "  Digest Interval: ${NOTIFY_DIGEST_INTERVAL}s"
}

#==============================================================================
# Test Rate Limiting
#==============================================================================
test_rate_limiting() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Testing Rate Limiting"
    echo "═══════════════════════════════════════════════════════════════"
    
    info "Rate limit: $NOTIFY_RATE_LIMIT_PER_HOUR notifications per hour"
    info "Current rate count: $__NOTIFY_RATE_COUNT"
    
    # Try to trigger rate limit
    info "Sending multiple notifications to test rate limiting..."
    
    local sent=0
    local limited=0
    
    for i in {1..5}; do
        if notify "info" "Rate Limit Test $i" "Testing rate limiting" "rate_test_$i" "true"; then
            ((sent++)) || true
        else
            ((limited++)) || true
            info "Rate limit triggered at iteration $i"
            break
        fi
    done
    
    log "✓ Sent $sent notifications before rate limit"
    if [[ $limited -gt 0 ]]; then
        warn "Rate limiting is working correctly"
    fi
}

#==============================================================================
# Print Summary
#==============================================================================
print_summary() {
    local passed=$1
    local failed=$2
    local skipped=$3
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Test Summary                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Results:"
    echo "  ✓ Passed:  $passed"
    echo "  ✗ Failed:  $failed"
    echo "  ⚠ Skipped: $skipped"
    echo ""
    
    if [[ $failed -eq 0 ]]; then
        log "All configured channels are working! 🎉"
        echo ""
        echo "Next steps:"
        echo "  - Your notifications are configured correctly"
        echo "  - Alerts will be sent according to your settings"
        echo "  - Check your notification channels (Telegram/Email) for test messages"
    else
        warn "Some tests failed. Please check your configuration."
        echo ""
        echo "Troubleshooting:"
        echo "  1. Verify API keys and tokens are correct"
        echo "  2. Check network connectivity"
        echo "  3. Review logs at: $NOTIFY_LOG_FILE"
        echo "  4. Run with verbose mode to see detailed errors"
    fi
    echo ""
}

#==============================================================================
# Usage
#==============================================================================
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

XDC Node Notification Test - Verify your notification configuration

Options:
  --channels    Test specific channels only (platform,telegram,email)
  --levels      Test all alert levels (info, warning, critical)
  --digest      Test digest mode
  --rate-limit  Test rate limiting
  --all         Run all tests (default)
  --help        Show this help message

Examples:
  # Test all channels
  $(basename "$0")

  # Test only Platform API
  $(basename "$0") --channels platform

  # Test all alert levels
  $(basename "$0") --levels

EOF
}

#==============================================================================
# Main
#==============================================================================
main() {
    local test_channels=""
    local test_levels=false
    local test_digest=false
    local test_rate=false
    local run_all=true
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --channels)
                test_channels="$2"
                run_all=false
                shift 2
                ;;
            --levels)
                test_levels=true
                run_all=false
                shift
                ;;
            --digest)
                test_digest=true
                run_all=false
                shift
                ;;
            --rate-limit)
                test_rate=true
                run_all=false
                shift
                ;;
            --all)
                run_all=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    print_banner
    check_prerequisites
    load_configuration
    
    local passed=0
    local failed=0
    local skipped=0
    
    # Determine which tests to run
    if [[ "$run_all" == "true" ]]; then
        test_channels="$NOTIFY_CHANNELS"
        test_levels=true
        test_digest=true
    fi
    
    # Test specified channels
    if [[ -n "$test_channels" ]]; then
        IFS=',' read -ra CHANNEL_ARRAY <<< "$test_channels"
        for channel in "${CHANNEL_ARRAY[@]}"; do
            case "$channel" in
                platform)
                    if test_platform_api; then
                        ((passed++)) || true
                    else
                        ((failed++)) || true
                    fi
                    ;;
                telegram)
                    if test_telegram; then
                        ((passed++)) || true
                    else
                        ((failed++)) || true
                    fi
                    ;;
                email)
                    if test_email; then
                        ((passed++)) || true
                    else
                        ((failed++)) || true
                    fi
                    ;;
                *)
                    warn "Unknown channel: $channel"
                    ((skipped++)) || true
                    ;;
            esac
        done
    fi
    
    # Test alert levels
    if [[ "$test_levels" == "true" ]]; then
        test_alert_levels
    fi
    
    # Test digest mode
    if [[ "$test_digest" == "true" ]]; then
        test_digest_mode
    fi
    
    # Test rate limiting
    if [[ "$test_rate" == "true" ]]; then
        test_rate_limiting
    fi
    
    # Print summary
    print_summary $passed $failed $skipped
    
    # Exit with appropriate code
    if [[ $failed -gt 0 ]]; then
        exit 1
    fi
    
    exit 0
}

main "$@"
