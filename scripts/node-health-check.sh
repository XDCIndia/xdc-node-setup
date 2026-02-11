#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDC Node Health Check Script
# Monitors node health and reports via JSON and optional Telegram
#==============================================================================

# Configuration
VERSIONS_FILE="/opt/xdc-node/configs/versions.json"
REPORT_DIR="/opt/xdc-node/reports"
HEALTH_LOG="/var/log/xdc-health-check.log"
XDC_RPC_URL="http://localhost:8545"
XDC_WS_URL="ws://localhost:8546"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Report data
 declare -A CHECKS
 declare -A METRICS
 CURRENT_HEIGHT=0
 PEER_COUNT=0
 SYNC_STATUS=""
 CLIENT_VERSION=""
 LATEST_VERSION=""
 SECURITY_SCORE=0
 DISK_USAGE=0
 CPU_USAGE=0
 RAM_USAGE=0

#==============================================================================
# Logging
#==============================================================================
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$HEALTH_LOG" 2>/dev/null || true
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$HEALTH_LOG" 2>/dev/null || true
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$HEALTH_LOG" 2>/dev/null || true
}

#==============================================================================
# RPC Helpers
#==============================================================================
rpc_call() {
    local method=$1
    local params=${2:-"[]"}
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        "$XDC_RPC_URL" 2>/dev/null || echo '{}'
}

#==============================================================================
# Health Checks
#==============================================================================
check_block_height() {
    log "Checking block height..."
    
    local response
    response=$(rpc_call "eth_blockNumber")
    local hex_height
    hex_height=$(echo "$response" | jq -r '.result // "0x0"')
    
    if [[ "$hex_height" != "0x0" && -n "$hex_height" ]]; then
        CURRENT_HEIGHT=$((16#${hex_height#0x}))
        CHECKS["block_height"]="pass"
        log "✓ Current block height: $CURRENT_HEIGHT"
    else
        CURRENT_HEIGHT=0
        CHECKS["block_height"]="fail"
        warn "✗ Failed to get block height"
    fi
}

check_peer_count() {
    log "Checking peer count..."
    
    local response
    response=$(rpc_call "net_peerCount")
    local hex_peers
    hex_peers=$(echo "$response" | jq -r '.result // "0x0"')
    
    if [[ -n "$hex_peers" ]]; then
        PEER_COUNT=$((16#${hex_peers#0x}))
        
        if [[ $PEER_COUNT -ge 3 ]]; then
            CHECKS["peer_count"]="pass"
            log "✓ Peer count: $PEER_COUNT (healthy)"
        elif [[ $PEER_COUNT -gt 0 ]]; then
            CHECKS["peer_count"]="warning"
            warn "⚠ Peer count: $PEER_COUNT (low)"
        else
            CHECKS["peer_count"]="fail"
            error "✗ No peers connected"
        fi
    else
        PEER_COUNT=0
        CHECKS["peer_count"]="fail"
        warn "✗ Failed to get peer count"
    fi
}

check_sync_status() {
    log "Checking sync status..."
    
    local response
    response=$(rpc_call "eth_syncing")
    local syncing
    syncing=$(echo "$response" | jq -r '.result')
    
    if [[ "$syncing" == "false" ]]; then
        SYNC_STATUS="synced"
        CHECKS["sync_status"]="pass"
        log "✓ Node is fully synced"
    elif [[ "$syncing" == "true" || "$syncing" == "{"* ]]; then
        SYNC_STATUS="syncing"
        CHECKS["sync_status"]="warning"
        
        # Get sync progress details
        local current_block
        local highest_block
        current_block=$(echo "$response" | jq -r '.result.currentBlock // "0x0"')
        highest_block=$(echo "$response" | jq -r '.result.highestBlock // "0x0"')
        
        if [[ "$current_block" != "0x0" && "$highest_block" != "0x0" ]]; then
            local current=$((16#${current_block#0x}))
            local highest=$((16#${highest_block#0x}))
            local remaining=$((highest - current))
            local progress=$((current * 100 / highest))
            warn "⚠ Syncing: $progress% ($remaining blocks remaining)"
        else
            warn "⚠ Node is syncing"
        fi
    else
        SYNC_STATUS="unknown"
        CHECKS["sync_status"]="fail"
        warn "✗ Could not determine sync status"
    fi
}

check_client_version() {
    log "Checking client version..."
    
    local response
    response=$(rpc_call "web3_clientVersion")
    CLIENT_VERSION=$(echo "$response" | jq -r '.result // "unknown"')
    
    if [[ "$CLIENT_VERSION" != "unknown" && -n "$CLIENT_VERSION" ]]; then
        CHECKS["client_version"]="pass"
        log "✓ Client version: $CLIENT_VERSION"
    else
        CHECKS["client_version"]="fail"
        warn "✗ Failed to get client version"
    fi
}

check_github_version() {
    log "Checking latest version on GitHub..."
    
    local repo="XinFinOrg/XDPoSChain"
    local api_url="https://api.github.com/repos/$repo/releases/latest"
    
    local response
    response=$(curl -sL "$api_url" 2>/dev/null || echo '{}')
    LATEST_VERSION=$(echo "$response" | jq -r '.tag_name // "unknown"')
    
    if [[ "$LATEST_VERSION" != "unknown" && -n "$LATEST_VERSION" ]]; then
        CHECKS["github_version"]="pass"
        log "✓ Latest version: $LATEST_VERSION"
        
        # Compare versions
        if [[ -f "$VERSIONS_FILE" ]]; then
            local current
            current=$(jq -r '.clients.XDPoSChain.current // "unknown"' "$VERSIONS_FILE")
            if [[ "$current" != "$LATEST_VERSION" ]]; then
                warn "⚠ New version available: $LATEST_VERSION (current: $current)"
            fi
        fi
    else
        CHECKS["github_version"]="warning"
        warn "⚠ Could not fetch latest version from GitHub"
    fi
}

check_system_resources() {
    log "Checking system resources..."
    
    # Disk usage
    DISK_USAGE=$(df -h /root/xdcchain 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%' || df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    if [[ -z "$DISK_USAGE" ]]; then DISK_USAGE=0; fi
    
    if [[ $DISK_USAGE -lt 85 ]]; then
        CHECKS["disk_usage"]="pass"
        log "✓ Disk usage: ${DISK_USAGE}%"
    elif [[ $DISK_USAGE -lt 95 ]]; then
        CHECKS["disk_usage"]="warning"
        warn "⚠ Disk usage: ${DISK_USAGE}%"
    else
        CHECKS["disk_usage"]="fail"
        error "✗ Disk usage critical: ${DISK_USAGE}%"
    fi
    
    # CPU usage (average over 1 minute)
    CPU_USAGE=$(awk '{print $1}' /proc/loadavg)
    CPU_PERCENT=$(echo "$CPU_USAGE * 100 / $(nproc)" | bc 2>/dev/null || echo "0")
    CPU_USAGE=${CPU_PERCENT%.*}
    
    if [[ ${CPU_USAGE%.*} -lt 80 ]]; then
        CHECKS["cpu_usage"]="pass"
        log "✓ CPU usage: ${CPU_USAGE}%"
    else
        CHECKS["cpu_usage"]="warning"
        warn "⚠ CPU usage high: ${CPU_USAGE}%"
    fi
    
    # RAM usage
    RAM_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    
    if [[ $RAM_USAGE -lt 90 ]]; then
        CHECKS["ram_usage"]="pass"
        log "✓ RAM usage: ${RAM_USAGE}%"
    else
        CHECKS["ram_usage"]="warning"
        warn "⚠ RAM usage high: ${RAM_USAGE}%"
    fi
}

check_docker_status() {
    log "Checking Docker status..."
    
    if ! systemctl is-active --quiet docker; then
        CHECKS["docker"]="fail"
        error "✗ Docker is not running"
        return
    fi
    
    # Check if XDC container is running
    if docker ps | grep -q "xdc-node"; then
        CHECKS["xdc_container"]="pass"
        log "✓ XDC container is running"
    else
        CHECKS["xdc_container"]="fail"
        error "✗ XDC container is not running"
    fi
}

#==============================================================================
# Security Score
#==============================================================================
calculate_security_score() {
    log "Calculating security score..."
    
    local score=0
    
    # SSH key-only auth
    if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; then
        score=$((score + 10))
    fi
    
    # Non-standard SSH port
    local ssh_port
    ssh_port=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    if [[ "$ssh_port" != "22" ]]; then
        score=$((score + 5))
    fi
    
    # Firewall active
    if ufw status | grep -q "Status: active"; then
        score=$((score + 10))
    fi
    
    # Fail2ban running
    if systemctl is-active --quiet fail2ban; then
        score=$((score + 5))
    fi
    
    # Unattended upgrades
    if dpkg -l | grep -q "unattended-upgrades"; then
        score=$((score + 5))
    fi
    
    # OS patches current (simplified check)
    if apt list --upgradable 2>/dev/null | wc -l | grep -q "^0$"; then
        score=$((score + 10))
    fi
    
    # Client version current (placeholder - would check against latest)
    if [[ "${CHECKS["github_version"]:-}" == "pass" ]]; then
        score=$((score + 15))
    fi
    
    # Monitoring active
    if docker ps | grep -q "prometheus\|grafana"; then
        score=$((score + 10))
    fi
    
    # Backup configured
    if [[ -f "/etc/cron.d/xdc-node" ]]; then
        score=$((score + 10))
    fi
    
    # Audit logging
    if systemctl is-active --quiet auditd; then
        score=$((score + 10))
    fi
    
    # Disk encryption (check for LUKS)
    if lsblk -f 2>/dev/null | grep -q "crypto_LUKS"; then
        score=$((score + 10))
    fi
    
    SECURITY_SCORE=$score
    log "✓ Security score: $SECURITY_SCORE/100"
}

#==============================================================================
# Report Generation
#==============================================================================
generate_json_report() {
    local report_file="$REPORT_DIR/node-health-$(date +%Y%m%d-%H%M%S).json"
    mkdir -p "$REPORT_DIR"
    
    # Build checks JSON
    local checks_json=""
    for key in "${!CHECKS[@]}"; do
        if [[ -n "$checks_json" ]]; then checks_json+=","; fi
        checks_json+="\"$key\": \"${CHECKS[$key]}\""
    done
    
    cat > "$report_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "node_type": "$(jq -r '.clients.XDPoSChain.current // "unknown"' "$VERSIONS_FILE" 2>/dev/null || echo "unknown")",
  "checks": {
    $checks_json
  },
  "metrics": {
    "block_height": $CURRENT_HEIGHT,
    "peer_count": $PEER_COUNT,
    "sync_status": "$SYNC_STATUS",
    "client_version": "$CLIENT_VERSION",
    "latest_version": "$LATEST_VERSION",
    "disk_usage_percent": $DISK_USAGE,
    "cpu_usage_percent": ${CPU_USAGE%.*},
    "ram_usage_percent": $RAM_USAGE,
    "security_score": $SECURITY_SCORE
  },
  "status": "$(if [[ ${CHECKS["block_height"]:-} == "pass" && ${CHECKS["sync_status"]:-} == "pass" ]]; then echo "healthy"; elif [[ ${CHECKS["block_height"]:-} == "fail" ]]; then echo "critical"; else echo "degraded"; fi)"
}
EOF
    
    log "Report saved to: $report_file"
    echo "$report_file"
}

#==============================================================================
# Telegram Notification
#==============================================================================
send_telegram() {
    local message=$1
    
    # Check for Telegram credentials
    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        warn "Telegram credentials not configured"
        return 1
    fi
    
    local api_url="https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\":\"$TELEGRAM_CHAT_ID\",\"text\":\"$message\",\"parse_mode\":\"Markdown\"}" \
        "$api_url" > /dev/null || warn "Failed to send Telegram notification"
}

build_telegram_message() {
    local status_icon
    local status_text
    
    if [[ ${CHECKS["block_height"]:-} == "pass" && ${CHECKS["sync_status"]:-} == "pass" ]]; then
        status_icon="🟢"
        status_text="HEALTHY"
    elif [[ ${CHECKS["block_height"]:-} == "fail" ]]; then
        status_icon="🔴"
        status_text="CRITICAL"
    else
        status_icon="🟡"
        status_text="DEGRADED"
    fi
    
    local security_rating
    if [[ $SECURITY_SCORE -ge 90 ]]; then security_rating="🟢 Excellent"; 
    elif [[ $SECURITY_SCORE -ge 70 ]]; then security_rating="🟡 Good"; 
    elif [[ $SECURITY_SCORE -ge 50 ]]; then security_rating="🟠 Fair"; 
    else security_rating="🔴 Poor"; fi
    
    cat << EOF
$status_icon *XDC Node Health Report*
Server: \`$(hostname)\`
Status: *$status_text*
Time: $(date '+%Y-%m-%d %H:%M:%S UTC')

*Metrics:*
• Block Height: $CURRENT_HEIGHT
• Peers: $PEER_COUNT
• Sync: ${SYNC_STATUS^^}
• Disk: ${DISK_USAGE}%
• RAM: ${RAM_USAGE}%
• Security: $security_rating ($SECURITY_SCORE/100)

*Checks:*
$(for key in "${!CHECKS[@]}"; do
    local icon
    case "${CHECKS[$key]}" in
        pass) icon="✅" ;;
        warning) icon="⚠️" ;;
        fail) icon="❌" ;;
        *) icon="❓" ;;
    esac
    echo "• ${key//_/ }: $icon"
done | sort)
EOF
}

#==============================================================================
# Main
#==============================================================================
main() {
    local notify=false
    local full_check=false
    
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --notify)
                notify=true
                shift
                ;;
            --full)
                full_check=true
                shift
                ;;
        esac
    done
    
    log "Starting XDC Node Health Check..."
    
    # Run checks
    check_block_height
    check_peer_count
    check_sync_status
    check_client_version
    check_system_resources
    check_docker_status
    
    if [[ "$full_check" == true ]]; then
        check_github_version
        calculate_security_score
    fi
    
    # Generate report
    local report_file
    report_file=$(generate_json_report)
    
    # Send notification if requested
    if [[ "$notify" == true ]]; then
        local message
        message=$(build_telegram_message)
        send_telegram "$message"
    fi
    
    # Summary
    log ""
    log "=================================="
    log "Health Check Complete"
    log "=================================="
    log "Block Height: $CURRENT_HEIGHT"
    log "Peers: $PEER_COUNT"
    log "Sync Status: ${SYNC_STATUS^^}"
    log "Security Score: $SECURITY_SCORE/100"
    log ""
    
    # Exit with appropriate code
    if [[ ${CHECKS["block_height"]:-} == "pass" && ${CHECKS["sync_status"]:-} == "pass" ]]; then
        log "Status: HEALTHY"
        exit 0
    elif [[ ${CHECKS["block_height"]:-} == "fail" ]]; then
        error "Status: CRITICAL"
        exit 2
    else
        warn "Status: DEGRADED"
        exit 1
    fi
}

main "$@"
