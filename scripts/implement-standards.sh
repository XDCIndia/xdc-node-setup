#!/usr/bin/env bash
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }

#==============================================================================
# XDC Node Standards Implementation Script
# Master script that implements ALL standards on a server
# Runs: security hardening, monitoring, cron jobs, backups, health checks
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/xdc-node"
LOG_FILE="/var/log/xdc-implement-standards.log"
COMPLIANCE_REPORT="$INSTALL_DIR/reports/compliance-$(date +%Y%m%d-%H%M%S).json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Track implementation status - using prefixed variables for bash 3.2 compatibility
# declare -A IMPL_STATUS
TOTAL_STEPS=10
COMPLETED_STEPS=0
FINAL_SECURITY_SCORE=0

# Helper functions for IMPL_STATUS
set_impl_status() {
    local key="$1"
    local value="$2"
    eval "IMPL_STATUS_$key=\"$value\""
}

get_impl_status() {
    local key="$1"
    eval "echo \${IMPL_STATUS_$key:-unknown}"
}

#==============================================================================
# Logging
#==============================================================================
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE" 2>/dev/null || true
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE" 2>/dev/null || true
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >> "$LOG_FILE" 2>/dev/null || true
}

step() {
    echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] STEP: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP: $1" >> "$LOG_FILE" 2>/dev/null || true
}

#==============================================================================
# Pre-flight Checks
#==============================================================================
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Must be root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot determine OS version"
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        error "This script only supports Ubuntu. Detected: $ID"
        exit 1
    fi
    
    # Check for required directories
    mkdir -p "$INSTALL_DIR"/{scripts,configs,reports,monitoring,docker}
    mkdir -p /backup/xdc-node/{daily,weekly,monthly}
    mkdir -p /var/log
    
    log "✓ Prerequisites check passed"
}

#==============================================================================
# Step 1: Security Hardening
#==============================================================================
run_security_hardening() {
    step "Step 1/$TOTAL_STEPS: Running Security Hardening"
    
    local script="$INSTALL_DIR/scripts/security-harden.sh"
    
    if [[ -f "$script" ]]; then
        chmod +x "$script"
        if "$script" 2>> "$LOG_FILE"; then
            IMPL_STATUS["security_hardening"]="pass"
            ((COMPLETED_STEPS++)) || true
            log "✓ Security hardening completed"
        else
            IMPL_STATUS["security_hardening"]="partial"
            warn "Security hardening completed with warnings"
        fi
    else
        IMPL_STATUS["security_hardening"]="fail"
        error "security-harden.sh not found at $script"
    fi
}

#==============================================================================
# Step 2: Setup Monitoring Stack
#==============================================================================
setup_monitoring() {
    step "Step 2/$TOTAL_STEPS: Setting up Monitoring Stack"
    
    local compose_file="$INSTALL_DIR/docker/docker-compose.yml"
    
    if [[ -f "$compose_file" ]]; then
        # Ensure monitoring directories exist
        mkdir -p "$INSTALL_DIR/monitoring/grafana/dashboards"
        mkdir -p "$INSTALL_DIR/monitoring/grafana/datasources"
        
        # Check if Docker is running
        if systemctl is-active --quiet docker; then
            cd "$INSTALL_DIR/docker"
            
            # Pull images
            log "Pulling monitoring images..."
            docker compose pull prometheus grafana node-exporter cadvisor 2>> "$LOG_FILE" || true
            
            # Start monitoring stack
            log "Starting monitoring stack..."
            if docker compose up -d prometheus grafana node-exporter cadvisor 2>> "$LOG_FILE"; then
                IMPL_STATUS["monitoring"]="pass"
                ((COMPLETED_STEPS++)) || true
                log "✓ Monitoring stack started"
            else
                IMPL_STATUS["monitoring"]="partial"
                warn "Monitoring stack may not have started fully"
            fi
        else
            IMPL_STATUS["monitoring"]="fail"
            error "Docker is not running"
        fi
    else
        IMPL_STATUS["monitoring"]="fail"
        error "docker-compose.yml not found"
    fi
}

#==============================================================================
# Step 3: Install Cron Jobs
#==============================================================================
install_cron_jobs() {
    step "Step 3/$TOTAL_STEPS: Installing Cron Jobs"
    
    local script="$INSTALL_DIR/../cron/setup-crons.sh"
    
    # Try multiple locations
    if [[ ! -f "$script" ]]; then
        script="$(dirname "$SCRIPT_DIR")/cron/setup-crons.sh"
    fi
    if [[ ! -f "$script" ]]; then
        script="/opt/xdc-node/setup-crons.sh"
    fi
    
    if [[ -f "$script" ]]; then
        chmod +x "$script"
        if "$script" 2>> "$LOG_FILE"; then
            IMPL_STATUS["cron_jobs"]="pass"
            ((COMPLETED_STEPS++)) || true
            log "✓ Cron jobs installed"
        else
            IMPL_STATUS["cron_jobs"]="partial"
            warn "Cron jobs installation had warnings"
        fi
    else
        # Fallback: create basic cron jobs
        log "Creating basic cron jobs..."
        cat > /etc/cron.d/xdc-node << 'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/15 * * * * root /opt/xdc-node/scripts/node-health-check.sh >> /var/log/xdc-health-check.log 2>&1
17 */6 * * * root /opt/xdc-node/scripts/version-check.sh >> /var/log/xdc-version-check.log 2>&1
0 3 * * * root /opt/xdc-node/scripts/backup.sh >> /var/log/xdc-backup.log 2>&1
0 2 * * 0 root /opt/xdc-node/scripts/backup.sh >> /var/log/xdc-backup.log 2>&1
0 6 * * * root /opt/xdc-node/scripts/node-health-check.sh --full >> /var/log/xdc-health-check.log 2>&1
EOF
        chmod 644 /etc/cron.d/xdc-node
        IMPL_STATUS["cron_jobs"]="pass"
        ((COMPLETED_STEPS++)) || true
        log "✓ Basic cron jobs created"
    fi
}

#==============================================================================
# Step 4: Configure Backups
#==============================================================================
configure_backups() {
    step "Step 4/$TOTAL_STEPS: Configuring Backups"
    
    # Create backup configuration
    if [[ ! -f /root/.xdc-backup.conf ]]; then
        cat > /root/.xdc-backup.conf << 'EOF'
# XDC Node Backup Configuration
# Created by implement-standards.sh

# Directories
BACKUP_DIR=/backup/xdc-node
# Detect network for network-aware directory structure
detect_network() {
    local network="${NETWORK:-}"
    if [[ -z "$network" && -f "$(pwd)/config.toml" ]]; then
        network=$(grep -E '^\s*name\s*=' "$(pwd)/config.toml" 2>/dev/null | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -1)
    fi
    if [[ -z "$network" && -f "/opt/xdc-node/config.toml" ]]; then
        network=$(grep -E '^\s*name\s*=' "/opt/xdc-node/config.toml" 2>/dev/null | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -1)
    fi
    echo "${network:-mainnet}"
}
XDC_NETWORK="${XDC_NETWORK:-$(detect_network)}"
DATA_DIR="${DATA_DIR:-$(pwd)/${XDC_NETWORK}/xdcchain}"
CONFIG_DIR=/opt/xdc-node

# Retention (days)
RETENTION_DAILY=7
RETENTION_WEEKLY=4
RETENTION_MONTHLY=12

# Encryption (optional - set GPG recipient or passphrase)
# GPG_RECIPIENT=your-gpg-key-id
# ENCRYPTION_KEY=your-passphrase

# Remote storage (optional)
# S3_BUCKET=your-bucket
# S3_ENDPOINT=
# FTP_HOST=
# FTP_USER=
# FTP_PASS=
EOF
        chmod 600 /root/.xdc-backup.conf
        log "✓ Backup configuration created at /root/.xdc-backup.conf"
    else
        log "✓ Backup configuration already exists"
    fi
    
    # Ensure backup script is executable
    local backup_script="$INSTALL_DIR/scripts/backup.sh"
    if [[ -f "$backup_script" ]]; then
        chmod +x "$backup_script"
        IMPL_STATUS["backups"]="pass"
        ((COMPLETED_STEPS++)) || true
        log "✓ Backup system configured"
    else
        IMPL_STATUS["backups"]="fail"
        error "backup.sh not found"
    fi
}

#==============================================================================
# Step 5: Setup Alertmanager
#==============================================================================
setup_alertmanager() {
    step "Step 5/$TOTAL_STEPS: Setting up Alertmanager"
    
    local alertmanager_config="$INSTALL_DIR/configs/alertmanager.yml"
    
    if [[ -f "$alertmanager_config" ]]; then
        log "✓ Alertmanager configuration exists"
        
        # Check if Telegram is configured
        if grep -q '\${TELEGRAM_BOT_TOKEN}' "$alertmanager_config"; then
            warn "Telegram credentials not configured in alertmanager.yml"
            info "Set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID environment variables"
        fi
        
        IMPL_STATUS["alertmanager"]="pass"
        ((COMPLETED_STEPS++)) || true
    else
        IMPL_STATUS["alertmanager"]="fail"
        error "alertmanager.yml not found"
    fi
}

#==============================================================================
# Step 6: Configure Prometheus Alerts
#==============================================================================
configure_alerts() {
    step "Step 6/$TOTAL_STEPS: Configuring Prometheus Alerts"
    
    local alerts_file="$INSTALL_DIR/monitoring/alerts.yml"
    
    if [[ -f "$alerts_file" ]]; then
        # Check if Prometheus can load the rules
        if docker exec xdc-prometheus promtool check rules /etc/prometheus/alerts.yml 2>/dev/null; then
            log "✓ Alert rules validated"
        else
            info "Alert rules not yet validated (Prometheus may not be running)"
        fi
        
        IMPL_STATUS["alerts"]="pass"
        ((COMPLETED_STEPS++)) || true
        log "✓ Prometheus alerts configured"
    else
        IMPL_STATUS["alerts"]="fail"
        error "alerts.yml not found"
    fi
}

#==============================================================================
# Step 7: Run Initial Health Check
#==============================================================================
run_health_check() {
    step "Step 7/$TOTAL_STEPS: Running Initial Health Check"
    
    local script="$INSTALL_DIR/scripts/node-health-check.sh"
    
    if [[ -f "$script" ]]; then
        chmod +x "$script"
        
        # Run health check (don't fail if node isn't running yet)
        if "$script" --full 2>> "$LOG_FILE"; then
            IMPL_STATUS["health_check"]="pass"
            log "✓ Health check passed"
        else
            IMPL_STATUS["health_check"]="warning"
            warn "Health check completed with warnings (node may not be fully synced)"
        fi
        ((COMPLETED_STEPS++)) || true
    else
        IMPL_STATUS["health_check"]="fail"
        error "node-health-check.sh not found"
    fi
}

#==============================================================================
# Step 8: Verify Version Check
#==============================================================================
verify_version_check() {
    step "Step 8/$TOTAL_STEPS: Verifying Version Check"
    
    local script="$INSTALL_DIR/scripts/version-check.sh"
    local versions_file="$INSTALL_DIR/configs/versions.json"
    
    if [[ -f "$script" && -f "$versions_file" ]]; then
        chmod +x "$script"
        
        # Run version check
        if "$script" 2>> "$LOG_FILE"; then
            IMPL_STATUS["version_check"]="pass"
            log "✓ Version check completed"
        else
            IMPL_STATUS["version_check"]="warning"
            warn "Version check completed with warnings"
        fi
        ((COMPLETED_STEPS++)) || true
    else
        IMPL_STATUS["version_check"]="fail"
        error "version-check.sh or versions.json not found"
    fi
}

#==============================================================================
# Step 9: Get Security Score
#==============================================================================
get_security_score() {
    step "Step 9/$TOTAL_STEPS: Getting Security Score"
    
    local score_file="$INSTALL_DIR/reports/security-score.json"
    
    if [[ -f "$score_file" ]]; then
        FINAL_SECURITY_SCORE=$(jq -r '.percentage // 0' "$score_file")
        log "✓ Security Score: $FINAL_SECURITY_SCORE/100"
        IMPL_STATUS["security_score"]="pass"
        ((COMPLETED_STEPS++)) || true
    else
        # Run security check to generate score
        local script="$INSTALL_DIR/scripts/node-health-check.sh"
        if [[ -f "$script" ]]; then
            "$script" --security-only 2>> "$LOG_FILE" || true
            
            if [[ -f "$score_file" ]]; then
                FINAL_SECURITY_SCORE=$(jq -r '.percentage // 0' "$score_file")
            fi
        fi
        
        IMPL_STATUS["security_score"]="warning"
        warn "Security score: $FINAL_SECURITY_SCORE (may be incomplete)"
        ((COMPLETED_STEPS++)) || true
    fi
}

#==============================================================================
# Step 10: Generate Compliance Report
#==============================================================================
generate_compliance_report() {
    step "Step 10/$TOTAL_STEPS: Generating Compliance Report"
    
    mkdir -p "$(dirname "$COMPLIANCE_REPORT")"
    
    # Build status JSON
    local status_json=""
    for key in "${!IMPL_STATUS[@]}"; do
        [[ -n "$status_json" ]] && status_json+=","
        status_json+="\n    \"$key\": \"${IMPL_STATUS[$key]}\""
    done
    
    cat > "$COMPLIANCE_REPORT" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "ip": "$(hostname -I | awk '{print $1}')",
  "os": "$(source /etc/os-release && echo "$PRETTY_NAME")",
  "summary": {
    "totalSteps": $TOTAL_STEPS,
    "completedSteps": $COMPLETED_STEPS,
    "securityScore": $FINAL_SECURITY_SCORE
  },
  "implementation": {$status_json
  },
  "standards_version": "1.0",
  "compliance_level": "$(
    if [[ $COMPLETED_STEPS -eq $TOTAL_STEPS && $FINAL_SECURITY_SCORE -ge 70 ]]; then
      echo "COMPLIANT"
    elif [[ $COMPLETED_STEPS -ge $((TOTAL_STEPS * 7 / 10)) ]]; then
      echo "PARTIALLY_COMPLIANT"
    else
      echo "NON_COMPLIANT"
    fi
  )"
}
EOF
    
    IMPL_STATUS["compliance_report"]="pass"
    ((COMPLETED_STEPS++)) || true
    log "✓ Compliance report generated: $COMPLIANCE_REPORT"
}

#==============================================================================
# Print Final Summary
#==============================================================================
print_summary() {
    local compliance_level
    if [[ $COMPLETED_STEPS -eq $TOTAL_STEPS && $FINAL_SECURITY_SCORE -ge 70 ]]; then
        compliance_level="🟢 COMPLIANT"
    elif [[ $COMPLETED_STEPS -ge $((TOTAL_STEPS * 7 / 10)) ]]; then
        compliance_level="🟡 PARTIALLY COMPLIANT"
    else
        compliance_level="🔴 NON-COMPLIANT"
    fi
    
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          XDC NODE STANDARDS IMPLEMENTATION COMPLETE            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BLUE}Server:${NC}           $(hostname)"
    echo -e "  ${BLUE}IP:${NC}               $(hostname -I | awk '{print $1}')"
    echo -e "  ${BLUE}Date:${NC}             $(date)"
    echo ""
    echo -e "  ${BLUE}Steps Completed:${NC}  $COMPLETED_STEPS / $TOTAL_STEPS"
    echo -e "  ${BLUE}Security Score:${NC}   $FINAL_SECURITY_SCORE / 100"
    echo -e "  ${BLUE}Compliance:${NC}       $compliance_level"
    echo ""
    echo "  Implementation Status:"
    echo "  ─────────────────────"
    for key in "${!IMPL_STATUS[@]}"; do
        local status_icon="✓"
        local color="$GREEN"
        case "${IMPL_STATUS[$key]}" in
            fail) status_icon="✗"; color="$RED" ;;
            partial|warning) status_icon="⚠"; color="$YELLOW" ;;
        esac
        printf "    ${color}${status_icon}${NC} %-20s ${IMPL_STATUS[$key]}\n" "$key"
    done
    echo ""
    echo "  Reports:"
    echo "  ────────"
    echo "    • Compliance: $COMPLIANCE_REPORT"
    echo "    • Security:   $INSTALL_DIR/reports/security-score.json"
    echo "    • Health:     $INSTALL_DIR/reports/node-health-*.json"
    echo ""
    echo "  Dashboards:"
    echo "  ───────────"
    echo "    • Grafana:    http://localhost:3000 (admin/admin)"
    echo "    • Prometheus: http://localhost:9090"
    echo ""
    echo "  Next Steps:"
    echo "  ───────────"
    echo "    1. Change Grafana default password"
    echo "    2. Configure Telegram notifications in alertmanager.yml"
    echo "    3. Review security score and address any gaps"
    echo "    4. Set up remote backup storage (S3/FTP)"
    echo "    5. Monitor node sync progress"
    echo ""
    echo "  SSH Connection (new port):"
    echo "  ──────────────────────────"
    echo "    ssh -p 12141 root@$(hostname -I | awk '{print $1}')"
    echo ""
}

#==============================================================================
# Main
#==============================================================================
main() {
    # Initialize log
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        XDC NODE INFRASTRUCTURE STANDARDS IMPLEMENTATION        ║${NC}"
    echo -e "${CYAN}║                                                                ║${NC}"
    echo -e "${CYAN}║  This script implements ALL standards from                     ║${NC}"
    echo -e "${CYAN}║  XDC-NODE-STANDARDS.md on this server                          ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log "Starting XDC Node Standards Implementation..."
    log "Log file: $LOG_FILE"
    
    check_prerequisites
    
    run_security_hardening
    setup_monitoring
    install_cron_jobs
    configure_backups
    setup_alertmanager
    configure_alerts
    run_health_check
    verify_version_check
    get_security_score
    generate_compliance_report
    
    print_summary
    
    log "Implementation complete!"
    
    # Exit with appropriate code
    if [[ $COMPLETED_STEPS -eq $TOTAL_STEPS ]]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
