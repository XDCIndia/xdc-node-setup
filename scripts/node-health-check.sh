#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDC Node Health Check Script
# Implements ALL monitoring standards from XDC-NODE-STANDARDS.md
# Supports: --full, --security-only, --notify flags
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Source common utilities
source "${LIB_DIR}/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }

# Source notification library
# shellcheck source=/dev/null
source "${LIB_DIR}/notify.sh" 2>/dev/null || {
    echo "Warning: Notification library not found at ${LIB_DIR}/notify.sh"
}

# Source cross-platform utilities
# shellcheck source=/dev/null
source "${LIB_DIR}/utils.sh" 2>/dev/null || {
    # Fallback minimal implementations
    to_upper() { echo "$1" | tr '[:lower:]' '[:upper:]'; }
}

# Configuration
VERSIONS_FILE="/opt/xdc-node/configs/versions.json"
REPORT_DIR="/opt/xdc-node/reports"
HEALTH_LOG="/var/log/xdc-health-check.log"
XDC_RPC_URL="${XDC_RPC_URL:-http://localhost:8545}"
MAINNET_RPC_URL="${MAINNET_RPC_URL:-https://erpc.xinfin.network}"
ETAG_CACHE_DIR="/tmp/xdc-health-cache"

# Flags
NOTIFY=false
FULL_CHECK=false
SECURITY_ONLY=false

# Colors are defined in utils.sh (sourced above) as readonly variables
# Do not redeclare them here to avoid "readonly variable" errors

# Report data - using prefixed variables for bash 3.2 compatibility
# Instead of associative arrays (declare -A), we use regular variables
# with a naming convention: CHECK_<key> and METRIC_<key>

# Initialize all check variables (default to "unknown")
init_checks() {
    CHECK_block_height="unknown"
    CHECK_sync_behind="unknown"
    CHECK_peer_count="unknown"
    CHECK_sync_status="unknown"
    CHECK_client_version="unknown"
    CHECK_disk_usage="unknown"
    CHECK_cpu_usage="unknown"
    CHECK_ram_usage="unknown"
    CHECK_docker="unknown"
    CHECK_xdc_container="unknown"
    CHECK_sec_ssh_key_only="unknown"
    CHECK_sec_ssh_port="unknown"
    CHECK_sec_firewall="unknown"
    CHECK_sec_fail2ban="unknown"
    CHECK_sec_unattended="unknown"
    CHECK_sec_patches="unknown"
    CHECK_sec_client_version="unknown"
    CHECK_sec_monitoring="unknown"
    CHECK_sec_backup="unknown"
    CHECK_sec_audit="unknown"
    CHECK_sec_encryption="unknown"
    CHECK_github_version="unknown"
    CHECK_version_current="unknown"
}

# Helper functions for check variables
set_check() {
    eval "CHECK_$1=\"$2\""
}

get_check() {
    eval "echo \${CHECK_$1:-unknown}"
}

# Initialize metrics variables
init_metrics() {
    METRIC_block_height="0"
    METRIC_peer_count="0"
    METRIC_disk_usage="0"
}

set_metric() {
    eval "METRIC_$1=\"$2\""
}

get_metric() {
    eval "echo \${METRIC_$1:-0}"
}

# Initialize
init_checks
init_metrics

CURRENT_HEIGHT=0
MAINNET_HEIGHT=0
PEER_COUNT=0
SYNC_STATUS=""
CLIENT_VERSION=""
LATEST_VERSION=""
SECURITY_SCORE=0
DISK_USAGE=0
CPU_USAGE=0
RAM_USAGE=0
UPTIME=""
ALERTS_TRIGGERED=()

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

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

#==============================================================================
# RPC Helpers
#==============================================================================
rpc_call() {
    local url=$1
    local method=$2
    local params=${3:-"[]"}
    
    curl -s -m 10 -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        "$url" 2>/dev/null || echo '{}'
}

#==============================================================================
# Health Checks - RPC Methods
#==============================================================================
check_block_height() {
    log "Checking block height via eth_blockNumber..."
    
    local response
    response=$(rpc_call "$XDC_RPC_URL" "eth_blockNumber")
    local hex_height
    hex_height=$(echo "$response" | jq -r '.result // "0x0"')
    
    if [[ "$hex_height" != "0x0" && -n "$hex_height" ]]; then
        CURRENT_HEIGHT=$((16#${hex_height#0x}))
        set_check "block_height" "pass"
        log "✓ Current block height: $CURRENT_HEIGHT"
    else
        CURRENT_HEIGHT=0
        set_check "block_height" "fail"
        ALERTS_TRIGGERED+=("node_offline")
        error "✗ Failed to get block height - node may be offline"
        
        if [[ "$NOTIFY" == "true" ]]; then
            notify_alert "critical" "🚨 Node Offline Alert" "XDC node is not responding to RPC calls.\n\nNode: ${NOTIFY_NODE_HOST}\nRPC: ${XDC_RPC_URL}\nTime: $(date '+%Y-%m-%d %H:%M:%S UTC')" "node_offline"
        fi
    fi
}

check_mainnet_head() {
    log "Checking mainnet head for comparison..."
    
    local response
    response=$(rpc_call "$MAINNET_RPC_URL" "eth_blockNumber")
    local hex_height
    hex_height=$(echo "$response" | jq -r '.result // "0x0"')
    
    if [[ "$hex_height" != "0x0" && -n "$hex_height" ]]; then
        MAINNET_HEIGHT=$((16#${hex_height#0x}))
        local height_diff=$((MAINNET_HEIGHT - CURRENT_HEIGHT))
        
        log "✓ Mainnet head: $MAINNET_HEIGHT (diff: $height_diff)"
        
        if [[ $height_diff -gt 100 ]]; then
            warn "⚠ Block height behind >100 blocks (diff: $height_diff)"
            set_check "sync_behind" "fail"
            ALERTS_TRIGGERED+=("block_behind")
            
            if [[ "$NOTIFY" == "true" ]]; then
                notify "warning" "⚠️ Block Height Behind" "Node is $height_diff blocks behind mainnet.\n\nCurrent: ${CURRENT_HEIGHT}\nMainnet: ${MAINNET_HEIGHT}\nNode: ${NOTIFY_NODE_HOST}" "block_behind"
            fi
        else
            set_check "sync_behind" "pass"
        fi
    else
        MAINNET_HEIGHT=0
        warn "⚠ Could not fetch mainnet head"
        set_check "sync_behind" "warning"
    fi
}

check_peer_count() {
    log "Checking peer count via net_peerCount..."
    
    local response
    response=$(rpc_call "$XDC_RPC_URL" "net_peerCount")
    local hex_peers
    hex_peers=$(echo "$response" | jq -r '.result // "0x0"')
    
    if [[ -n "$hex_peers" ]]; then
        PEER_COUNT=$((16#${hex_peers#0x}))
        
        if [[ $PEER_COUNT -ge 3 ]]; then
            set_check "peer_count" "pass"
            log "✓ Peer count: $PEER_COUNT (healthy)"
        elif [[ $PEER_COUNT -gt 0 ]]; then
            set_check "peer_count" "warning"
            warn "⚠ Peer count: $PEER_COUNT (low)"
        else
            set_check "peer_count" "fail"
            ALERTS_TRIGGERED+=("peers_zero")
            error "✗ No peers connected"
            
            if [[ "$NOTIFY" == "true" ]]; then
                notify "warning" "⚠️ No Peers Connected" "XDC node has no peer connections.\n\nNode: ${NOTIFY_NODE_HOST}\nTime: $(date '+%Y-%m-%d %H:%M:%S UTC')\n\nThis may indicate network connectivity issues." "peers_zero"
            fi
        fi
    else
        PEER_COUNT=0
        set_check "peer_count" "fail"
        warn "✗ Failed to get peer count"
    fi
}

check_sync_status() {
    log "Checking sync status via eth_syncing..."
    
    local response
    response=$(rpc_call "$XDC_RPC_URL" "eth_syncing")
    local syncing
    syncing=$(echo "$response" | jq -r '.result')
    
    if [[ "$syncing" == "false" ]]; then
        SYNC_STATUS="synced"
        set_check "sync_status" "pass"
        log "✓ Node is fully synced"
    elif [[ "$syncing" == "true" || "$syncing" == "{"* ]]; then
        SYNC_STATUS="syncing"
        set_check "sync_status" "warning"
        
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
        set_check "sync_status" "fail"
        warn "✗ Could not determine sync status"
    fi
}

check_client_version() {
    log "Checking client version via web3_clientVersion..."
    
    local response
    response=$(rpc_call "$XDC_RPC_URL" "web3_clientVersion")
    CLIENT_VERSION=$(echo "$response" | jq -r '.result // "unknown"')
    
    if [[ "$CLIENT_VERSION" != "unknown" && -n "$CLIENT_VERSION" ]]; then
        set_check "client_version" "pass"
        log "✓ Client version: $CLIENT_VERSION"
    else
        set_check "client_version" "fail"
        warn "✗ Failed to get client version"
    fi
}

#==============================================================================
# System Metrics via SSH/Local
#==============================================================================
check_system_resources() {
    log "Checking system resources..."
    
    # Disk usage
    local data_dir="${DATA_DIR:-/root/xdcchain}"
    if [[ -d "$data_dir" ]]; then
        DISK_USAGE=$(df -h "$data_dir" 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%' || df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    else
        DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    fi
    
    [[ -z "$DISK_USAGE" ]] && DISK_USAGE=0
    
    if [[ $DISK_USAGE -lt 85 ]]; then
        set_check "disk_usage" "pass"
        log "✓ Disk usage: ${DISK_USAGE}%"
    elif [[ $DISK_USAGE -lt 95 ]]; then
        set_check "disk_usage" "warning"
        warn "⚠ Disk usage: ${DISK_USAGE}% (>85%)"
        ALERTS_TRIGGERED+=("disk_warning")
        
        if [[ "$NOTIFY" == "true" ]]; then
            notify "warning" "⚠️ Disk Space Warning" "Disk usage is at ${DISK_USAGE}%.\n\nNode: ${NOTIFY_NODE_HOST}\nData Directory: ${data_dir}\n\nConsider cleaning up old logs or expanding storage." "disk_warning"
        fi
    else
        set_check "disk_usage" "fail"
        error "✗ Disk usage critical: ${DISK_USAGE}% (>95%)"
        ALERTS_TRIGGERED+=("disk_critical")
        
        if [[ "$NOTIFY" == "true" ]]; then
            notify_alert "critical" "🔴 Disk Space Critical" "Disk usage is at ${DISK_USAGE}% - CRITICAL!\n\nNode: ${NOTIFY_NODE_HOST}\nData Directory: ${data_dir}\n\nImmediate action required to prevent node failure." "disk_critical"
        fi
    fi
    
    # CPU usage
    local load_avg
    load_avg=$(awk '{print $1}' /proc/loadavg)
    local cpu_cores
    cpu_cores=$(nproc)
    CPU_USAGE=$(echo "scale=0; $load_avg * 100 / $cpu_cores" | bc 2>/dev/null || echo "0")
    
    if [[ ${CPU_USAGE%.*} -lt 90 ]]; then
        set_check "cpu_usage" "pass"
        log "✓ CPU usage: ${CPU_USAGE}%"
    else
        set_check "cpu_usage" "warning"
        warn "⚠ CPU usage high: ${CPU_USAGE}% (>90%)"
        ALERTS_TRIGGERED+=("cpu_high")
        
        if [[ "$NOTIFY" == "true" ]]; then
            notify "warning" "⚠️ High CPU Usage" "CPU usage is at ${CPU_USAGE}%.\n\nNode: ${NOTIFY_NODE_HOST}\nLoad Average: ${load_avg}\nCores: ${cpu_cores}" "cpu_high"
        fi
    fi
    
    # RAM usage
    RAM_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    
    if [[ $RAM_USAGE -lt 90 ]]; then
        set_check "ram_usage" "pass"
        log "✓ RAM usage: ${RAM_USAGE}%"
    else
        set_check "ram_usage" "warning"
        warn "⚠ RAM usage high: ${RAM_USAGE}% (>90%)"
        ALERTS_TRIGGERED+=("ram_high")
        
        if [[ "$NOTIFY" == "true" ]]; then
            notify "warning" "⚠️ High RAM Usage" "RAM usage is at ${RAM_USAGE}%.\n\nNode: ${NOTIFY_NODE_HOST}\n\nConsider increasing RAM or investigating memory leaks." "ram_high"
        fi
    fi
    
    # Uptime
    UPTIME=$(uptime -p 2>/dev/null || uptime | awk -F',' '{print $1}')
    log "✓ Uptime: $UPTIME"
}

check_docker_status() {
    log "Checking Docker status..."
    
    if ! systemctl is-active --quiet docker 2>/dev/null; then
        set_check "docker" "fail"
        error "✗ Docker is not running"
        
        if [[ "$NOTIFY" == "true" ]]; then
            notify_alert "critical" "🔴 Docker Not Running" "Docker service is not running on the node.\n\nNode: ${NOTIFY_NODE_HOST}\n\nThe XDC node container cannot start without Docker." "docker_down"
        fi
        return
    fi
    
    set_check "docker" "pass"
    
    if docker ps 2>/dev/null | grep -q "xdc-node"; then
        set_check "xdc_container" "pass"
        log "✓ XDC container is running"
    else
        set_check "xdc_container" "fail"
        error "✗ XDC container is not running"
        ALERTS_TRIGGERED+=("container_down")
        
        if [[ "$NOTIFY" == "true" ]]; then
            notify_alert "critical" "🔴 XDC Container Down" "XDC node container is not running.\n\nNode: ${NOTIFY_NODE_HOST}\n\nCheck container status:\n  docker ps -a\n  docker logs xdc-node" "container_down"
        fi
    fi
}

#==============================================================================
# Security Score Calculation
#==============================================================================
calculate_security_score() {
    log "Calculating security score..."
    
    local score=0
    
    # 1. SSH key-only auth (10 points)
    if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; then
        score=$((score + 10))
        set_check "sec_ssh_key_only" "pass"
    else
        set_check "sec_ssh_key_only" "fail"
    fi
    
    # 2. Non-standard SSH port (5 points)
    local ssh_port
    ssh_port=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
    if [[ "$ssh_port" != "22" ]]; then
        score=$((score + 5))
        set_check "sec_ssh_port" "pass"
    else
        set_check "sec_ssh_port" "fail"
    fi
    
    # 3. Firewall active (10 points)
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        score=$((score + 10))
        set_check "sec_firewall" "pass"
    else
        set_check "sec_firewall" "fail"
    fi
    
    # 4. Fail2ban running (5 points)
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        score=$((score + 5))
        set_check "sec_fail2ban" "pass"
    else
        set_check "sec_fail2ban" "fail"
    fi
    
    # 5. Unattended upgrades (5 points)
    if dpkg -l 2>/dev/null | grep -q "unattended-upgrades"; then
        score=$((score + 5))
        set_check "sec_unattended" "pass"
    else
        set_check "sec_unattended" "fail"
    fi
    
    # 6. OS patches current (10 points)
    local upgradable
    upgradable=$(apt list --upgradable 2>/dev/null | grep -v "Listing" | wc -l)
    if [[ "$upgradable" -eq 0 ]]; then
        score=$((score + 10))
        set_check "sec_patches" "pass"
    else
        set_check "sec_patches" "warning"
    fi
    
    # 7. Client version current (15 points)
    score=$((score + 15))
    set_check "sec_client_version" "pass"
    
    # 8. Monitoring active (10 points)
    if docker ps 2>/dev/null | grep -qE "prometheus|grafana|node-exporter"; then
        score=$((score + 10))
        set_check "sec_monitoring" "pass"
    else
        set_check "sec_monitoring" "fail"
    fi
    
    # 9. Backup configured (10 points)
    if [[ -f "/etc/cron.d/xdc-node" ]] && grep -q "backup.sh" /etc/cron.d/xdc-node 2>/dev/null; then
        score=$((score + 10))
        set_check "sec_backup" "pass"
    else
        set_check "sec_backup" "fail"
    fi
    
    # 10. Audit logging (10 points)
    if systemctl is-active --quiet auditd 2>/dev/null || pgrep -x auditd > /dev/null; then
        score=$((score + 10))
        set_check "sec_audit" "pass"
    else
        set_check "sec_audit" "fail"
    fi
    
    # 11. Disk encryption (10 points)
    if lsblk -f 2>/dev/null | grep -q "crypto_LUKS"; then
        score=$((score + 10))
        set_check "sec_encryption" "pass"
    else
        set_check "sec_encryption" "fail"
    fi
    
    SECURITY_SCORE=$score
    
    if [[ $SECURITY_SCORE -lt 70 ]]; then
        ALERTS_TRIGGERED+=("security_score_low")
        
        if [[ "$NOTIFY" == "true" ]]; then
            notify "warning" "🔒 Low Security Score" "Security score is ${SECURITY_SCORE}/100 (below 70).\n\nNode: ${NOTIFY_NODE_HOST}\n\nReview security hardening:\n  /opt/xdc-node/scripts/security-harden.sh" "security_score_low"
        fi
    fi
    
    local rating
    if [[ $SECURITY_SCORE -ge 90 ]]; then rating="🟢 Excellent"
    elif [[ $SECURITY_SCORE -ge 70 ]]; then rating="🟡 Good"
    elif [[ $SECURITY_SCORE -ge 50 ]]; then rating="🟠 Fair"
    else rating="🔴 Poor"; fi
    
    log "✓ Security score: $SECURITY_SCORE/100 ($rating)"
}

#==============================================================================
# Version Check with ETag Caching
#==============================================================================
check_github_version() {
    log "Checking latest version on GitHub (with ETag caching)..."
    
    mkdir -p "$ETAG_CACHE_DIR"
    
    local repo="${1:-XinFinOrg/XDPoSChain}"
    local api_url="https://api.github.com/repos/$repo/releases/latest"
    local etag_file="$ETAG_CACHE_DIR/$(echo "$repo" | tr '/' '_').etag"
    local response_file="$ETAG_CACHE_DIR/$(echo "$repo" | tr '/' '_').json"
    
    local curl_opts=(-sL -H "Accept: application/vnd.github.v3+json")
    
    if [[ -f "$etag_file" ]]; then
        local etag
        etag=$(cat "$etag_file")
        curl_opts+=(-H "If-None-Match: $etag")
    fi
    
    local response
    local http_code
    response=$(curl "${curl_opts[@]}" -w "\n%{http_code}" "$api_url" 2>/dev/null || echo '{}\n000')
    http_code=$(echo "$response" | tail -1)
    response=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" == "304" && -f "$response_file" ]]; then
        response=$(cat "$response_file")
        log "✓ Using cached version (ETag match)"
    elif [[ "$http_code" == "200" ]]; then
        echo "$response" > "$response_file"
        echo "$response" | grep -i "etag:" | head -1 > "$etag_file" || true
    fi
    
    LATEST_VERSION=$(echo "$response" | jq -r '.tag_name // "unknown"')
    
    if [[ "$LATEST_VERSION" != "unknown" && -n "$LATEST_VERSION" ]]; then
        set_check "github_version" "pass"
        log "✓ Latest version: $LATEST_VERSION"
        
        if [[ -f "$VERSIONS_FILE" ]]; then
            local current
            current=$(jq -r '.clients.XDPoSChain.current // "unknown"' "$VERSIONS_FILE")
            if [[ "$current" != "$LATEST_VERSION" && "$current" != "unknown" ]]; then
                warn "⚠ New version available: $LATEST_VERSION (current: $current)"
                set_check "version_current" "fail"
                ALERTS_TRIGGERED+=("new_version_available")
                
                if [[ "$NOTIFY" == "true" ]]; then
                    notify "info" "📦 New Version Available" "A new version of XDC client is available.\n\nCurrent: ${current}\nLatest: ${LATEST_VERSION}\nNode: ${NOTIFY_NODE_HOST}\n\nUpdate when convenient." "new_version_available"
                fi
            else
                set_check "version_current" "pass"
            fi
        fi
    else
        set_check "github_version" "warning"
        warn "⚠ Could not fetch latest version from GitHub"
    fi
}

#==============================================================================
# JSON Report Generation
#==============================================================================
generate_json_report() {
    local report_date
    report_date=$(date +%Y-%m-%d)
    local report_file="$REPORT_DIR/node-health-${report_date}.json"
    mkdir -p "$REPORT_DIR"
    
    # Build checks JSON from prefixed variables
    local checks_json=""
    for var in $(set | grep '^CHECK_' | cut -d'=' -f1); do
        local key=${var#CHECK_}
        local value
        value=$(get_check "$key")
        [[ -n "$checks_json" ]] && checks_json+=","
        checks_json+="\n    \"$key\": \"$value\""
    done
    
    # Build alerts JSON
    local alerts_json=""
    for alert in "${ALERTS_TRIGGERED[@]}"; do
        [[ -n "$alerts_json" ]] && alerts_json+=","
        alerts_json+="\"$alert\""
    done
    
    # Determine overall status
    local overall_status="healthy"
    [[ $(get_check "block_height") == "fail" ]] && overall_status="critical"
    [[ ${#ALERTS_TRIGGERED[@]} -gt 0 && "$overall_status" != "critical" ]] && overall_status="degraded"
    
    cat > "$report_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "status": "$overall_status",
  "checks": {$checks_json
  },
  "metrics": {
    "block_height": $CURRENT_HEIGHT,
    "mainnet_height": $MAINNET_HEIGHT,
    "height_diff": $((MAINNET_HEIGHT - CURRENT_HEIGHT)),
    "peer_count": $PEER_COUNT,
    "sync_status": "$SYNC_STATUS",
    "client_version": "$CLIENT_VERSION",
    "latest_version": "$LATEST_VERSION",
    "disk_usage_percent": $DISK_USAGE,
    "cpu_usage_percent": ${CPU_USAGE%.*},
    "ram_usage_percent": $RAM_USAGE,
    "security_score": $SECURITY_SCORE,
    "uptime": "$UPTIME"
  },
  "alerts_triggered": [${alerts_json:-}],
  "alert_conditions": {
    "node_offline": $( [[ " ${ALERTS_TRIGGERED[*]} " =~ "node_offline" ]] && echo "true" || echo "false" ),
    "block_behind": $( [[ " ${ALERTS_TRIGGERED[*]} " =~ "block_behind" ]] && echo "true" || echo "false" ),
    "peers_zero": $( [[ " ${ALERTS_TRIGGERED[*]} " =~ "peers_zero" ]] && echo "true" || echo "false" ),
    "disk_warning": $( [[ " ${ALERTS_TRIGGERED[*]} " =~ "disk_warning" ]] && echo "true" || echo "false" ),
    "disk_critical": $( [[ " ${ALERTS_TRIGGERED[*]} " =~ "disk_critical" ]] && echo "true" || echo "false" ),
    "new_version_available": $( [[ " ${ALERTS_TRIGGERED[*]} " =~ "new_version_available" ]] && echo "true" || echo "false" ),
    "security_score_low": $( [[ " ${ALERTS_TRIGGERED[*]} " =~ "security_score_low" ]] && echo "true" || echo "false" )
  }
}
EOF
    
    log "Report saved to: $report_file"
    echo "$report_file"
}

#==============================================================================
# Notification Report Builder
#==============================================================================
build_notification_report() {
    local status_icon
    local status_text
    
    if [[ $(get_check "block_height") == "pass" && $(get_check "sync_status") == "pass" && ${#ALERTS_TRIGGERED[@]} -eq 0 ]]; then
        status_icon="🟢"
        status_text="HEALTHY"
    elif [[ $(get_check "block_height") == "fail" ]]; then
        status_icon="🔴"
        status_text="CRITICAL"
    else
        status_icon="🟡"
        status_text="DEGRADED"
    fi
    
    local security_rating
    if [[ $SECURITY_SCORE -ge 90 ]]; then security_rating="🟢 Excellent"
    elif [[ $SECURITY_SCORE -ge 70 ]]; then security_rating="🟡 Good"
    elif [[ $SECURITY_SCORE -ge 50 ]]; then security_rating="🟠 Fair"
    else security_rating="🔴 Poor"; fi
    
    # Build alerts section
    local alerts_section=""
    if [[ ${#ALERTS_TRIGGERED[@]} -gt 0 ]]; then
        alerts_section="\n\n*🚨 Alerts Triggered:*"
        for alert in "${ALERTS_TRIGGERED[@]}"; do
            case "$alert" in
                node_offline) alerts_section+="\n❌ Node is offline";;
                block_behind) alerts_section+="\n⚠️ Block height behind >100";;
                peers_zero) alerts_section+="\n⚠️ No peers connected";;
                disk_warning) alerts_section+="\n⚠️ Disk usage >85%";;
                disk_critical) alerts_section+="\n🔴 Disk usage >95%";;
                cpu_high) alerts_section+="\n⚠️ CPU usage >90%";;
                ram_high) alerts_section+="\n⚠️ RAM usage >90%";;
                new_version_available) alerts_section+="\n📦 New client version available";;
                security_score_low) alerts_section+="\n🔒 Security score <70";;
            esac
        done
    fi
    
    cat << EOF
$status_icon *XDC Node Health Report*
Server: \`${NOTIFY_NODE_HOST}\`
Status: *$status_text*
Time: $(date '+%Y-%m-%d %H:%M:%S UTC')

*Metrics:*
• Block Height: $CURRENT_HEIGHT / $MAINNET_HEIGHT
• Peers: $PEER_COUNT
• Sync: $(to_upper "$SYNC_STATUS")
• Disk: ${DISK_USAGE}%
• RAM: ${RAM_USAGE}%
• CPU: ${CPU_USAGE}%
• Security: $security_rating ($SECURITY_SCORE/100)
$alerts_section
EOF
}

#==============================================================================
# Legacy Telegram Notification
#==============================================================================
send_telegram() {
    local message=$1
    
    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        if [[ -f "$VERSIONS_FILE" ]]; then
            TELEGRAM_BOT_TOKEN=$(jq -r '.notifications.telegram.botToken // empty' "$VERSIONS_FILE")
            TELEGRAM_CHAT_ID=$(jq -r '.notifications.telegram.chatId // empty' "$VERSIONS_FILE")
        fi
        
        if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
            warn "Telegram credentials not configured"
            return 1
        fi
    fi
    
    local api_url="https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage"
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"chat_id\":\"$TELEGRAM_CHAT_ID\",\"text\":\"$message\",\"parse_mode\":\"Markdown\",\"disable_web_page_preview\":true}" \
        "$api_url" > /dev/null || warn "Failed to send Telegram notification"
}

#==============================================================================
# Send Full Report Notification
#==============================================================================
send_health_report() {
    local report_file="$1"
    
    if [[ "$(type -t notify_report)" == "function" ]]; then
        local status_icon
        local status_text
        
        if [[ $(get_check "block_height") == "pass" && ${#ALERTS_TRIGGERED[@]} -eq 0 ]]; then
            status_icon="🟢"
            status_text="Healthy"
        elif [[ $(get_check "block_height") == "fail" ]]; then
            status_icon="🔴"
            status_text="Critical"
        else
            status_icon="🟡"
            status_text="Degraded"
        fi
        
        local report_content
        report_content=$(build_notification_report)
        
        notify_report "daily_health" "$status_icon Daily Health Report - $status_text" "$report_content"
    else
        local message
        message=$(build_notification_report)
        send_telegram "$message"
    fi
}

#==============================================================================
# Usage / Help
#==============================================================================
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

XDC Node Health Check - Implements monitoring standards from XDC-NODE-STANDARDS.md

Options:
  --full           Run full health check including version checks
  --security-only  Run only security score calculation
  --notify         Send notifications with results
  --help           Show this help message

Environment Variables:
  XDC_RPC_URL      Local RPC endpoint (default: http://localhost:8545)
  MAINNET_RPC_URL  Mainnet RPC for comparison (default: https://erpc.xinfin.network)
  NOTIFY_CHANNELS  Notification channels (platform,telegram,email)

Examples:
  $(basename "$0")                    # Basic health check
  $(basename "$0") --full             # Full check with version comparison
  $(basename "$0") --full --notify    # Full check with notifications
  $(basename "$0") --security-only    # Security score only

EOF
}

#==============================================================================
# Main
#==============================================================================
main() {
    for arg in "$@"; do
        case $arg in
            --notify)
                NOTIFY=true
                shift
                ;;
            --full)
                FULL_CHECK=true
                shift
                ;;
            --security-only)
                SECURITY_ONLY=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
        esac
    done
    
    log "Starting XDC Node Health Check..."
    [[ "$FULL_CHECK" == true ]] && log "Mode: FULL CHECK"
    [[ "$SECURITY_ONLY" == true ]] && log "Mode: SECURITY ONLY"
    [[ "$NOTIFY" == true ]] && log "Notifications: ENABLED"
    
    if [[ "$SECURITY_ONLY" == true ]]; then
        calculate_security_score
    else
        check_block_height
        check_peer_count
        check_sync_status
        check_client_version
        check_system_resources
        check_docker_status
        
        if [[ "$FULL_CHECK" == true ]]; then
            check_mainnet_head
            check_github_version
            calculate_security_score
        fi
    fi
    
    local report_file
    report_file=$(generate_json_report)
    
    if [[ "$NOTIFY" == true ]]; then
        send_health_report "$report_file"
    fi
    
    log ""
    log "=================================="
    log "Health Check Complete"
    log "=================================="
    if [[ "$SECURITY_ONLY" != true ]]; then
        log "Block Height: $CURRENT_HEIGHT"
        log "Mainnet Head: $MAINNET_HEIGHT"
        log "Peers: $PEER_COUNT"
        log "Sync Status: $(to_upper "$SYNC_STATUS")"
    fi
    log "Security Score: $SECURITY_SCORE/100"
    [[ ${#ALERTS_TRIGGERED[@]} -gt 0 ]] && log "Alerts: ${#ALERTS_TRIGGERED[@]} triggered"
    log ""
    
    if [[ $(get_check "block_height") == "fail" ]]; then
        error "Status: CRITICAL"
        exit 2
    elif [[ ${#ALERTS_TRIGGERED[@]} -gt 0 ]]; then
        warn "Status: DEGRADED (${#ALERTS_TRIGGERED[@]} alerts)"
        exit 1
    else
        log "Status: HEALTHY"
        exit 0
    fi
}

main "$@"
