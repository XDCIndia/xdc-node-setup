#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDC Node Cron Setup Script
# Implements scheduled tasks from XDC-NODE-STANDARDS.md
# Features: Health checks, version checks, backups, log rotation
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="/opt/xdc-node/scripts"
LOG_DIR="/var/log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

#==============================================================================
# Check Root
#==============================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
}

#==============================================================================
# Install Cron Jobs
#==============================================================================
install_cron_jobs() {
    log "Installing XDC Node cron jobs..."
    
    # Create cron.d file with all scheduled tasks
    cat > /etc/cron.d/xdc-node << 'EOF'
#==============================================================================
# XDC Node Scheduled Tasks
# Installed by setup-crons.sh
# Implements Section 5 (Cron Setup) of XDC-NODE-STANDARDS.md
#==============================================================================

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=""

#------------------------------------------------------------------------------
# Health Monitoring
#------------------------------------------------------------------------------

# Health check every 15 minutes
*/15 * * * * root /opt/xdc-node/scripts/node-health-check.sh >> /var/log/xdc-health-check.log 2>&1

# Full health report with security check at 6:00 AM daily
0 6 * * * root /opt/xdc-node/scripts/node-health-check.sh --full --notify >> /var/log/xdc-health-check.log 2>&1

#------------------------------------------------------------------------------
# Version Management
#------------------------------------------------------------------------------

# Version check every 6 hours (at 17 minutes past to avoid peak times)
17 */6 * * * root /opt/xdc-node/scripts/version-check.sh >> /var/log/xdc-version-check.log 2>&1

#------------------------------------------------------------------------------
# Backups
#------------------------------------------------------------------------------

# Daily backup at 3:00 AM
0 3 * * * root /opt/xdc-node/scripts/backup.sh >> /var/log/xdc-backup.log 2>&1

# Weekly full backup Sunday at 2:00 AM
0 2 * * 0 root WEEKLY_BACKUP=true /opt/xdc-node/scripts/backup.sh >> /var/log/xdc-backup.log 2>&1

#------------------------------------------------------------------------------
# Maintenance
#------------------------------------------------------------------------------

# Log rotation check (Sunday at midnight)
0 0 * * 0 root /usr/sbin/logrotate -f /etc/logrotate.d/xdc-node 2>/dev/null || true

# Clean up old reports (keep last 30 days)
0 4 * * * root find /opt/xdc-node/reports -name "*.json" -mtime +30 -delete 2>/dev/null || true

# Clean up old backups per retention policy
0 5 * * * root find /backup/xdc-node/daily -mtime +7 -delete 2>/dev/null || true

# Docker system prune (monthly, first Sunday)
0 1 1-7 * 0 root docker system prune -f --volumes >> /var/log/docker-prune.log 2>&1 || true

EOF
    
    chmod 644 /etc/cron.d/xdc-node
    
    log "✓ Cron jobs installed at /etc/cron.d/xdc-node"
}

#==============================================================================
# Setup Log Rotation
#==============================================================================
setup_logrotate() {
    log "Setting up log rotation for XDC logs..."
    
    cat > /etc/logrotate.d/xdc-node << 'EOF'
# XDC Node Log Rotation
# Implements log retention from XDC-NODE-STANDARDS.md

# Main XDC logs
/var/log/xdc-*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        systemctl reload rsyslog 2>/dev/null || true
    endscript
}

# Docker container logs
/var/lib/docker/containers/*/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
}

# Report files
/opt/xdc-node/reports/*.json {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 root root
}

# Security audit logs (longer retention)
/opt/xdc-node/reports/security-*.txt {
    weekly
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 0640 root root
}

# Backup logs
/var/log/xdc-backup.log {
    weekly
    missingok
    rotate 12
    compress
    delaycompress
    notifempty
    create 0640 root root
}
EOF
    
    chmod 644 /etc/logrotate.d/xdc-node
    
    log "✓ Log rotation configured at /etc/logrotate.d/xdc-node"
}

#==============================================================================
# Create Log Files
#==============================================================================
create_log_files() {
    log "Creating log files..."
    
    local logs=(
        "xdc-health-check.log"
        "xdc-version-check.log"
        "xdc-backup.log"
        "xdc-security-harden.log"
        "xdc-node-setup.log"
    )
    
    for logfile in "${logs[@]}"; do
        touch "/var/log/$logfile"
        chmod 640 "/var/log/$logfile"
    done
    
    log "✓ Log files created"
}

#==============================================================================
# Setup Systemd Timers (Alternative to Cron)
#==============================================================================
setup_systemd_timers() {
    log "Setting up systemd timers..."
    
    # Health check timer
    cat > /etc/systemd/system/xdc-health-check.service << 'EOF'
[Unit]
Description=XDC Node Health Check
After=docker.service

[Service]
Type=oneshot
ExecStart=/opt/xdc-node/scripts/node-health-check.sh
StandardOutput=append:/var/log/xdc-health-check.log
StandardError=append:/var/log/xdc-health-check.log

[Install]
WantedBy=multi-user.target
EOF
    
    cat > /etc/systemd/system/xdc-health-check.timer << 'EOF'
[Unit]
Description=XDC Node Health Check Timer

[Timer]
OnCalendar=*:0/15
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Version check timer
    cat > /etc/systemd/system/xdc-version-check.service << 'EOF'
[Unit]
Description=XDC Node Version Check
After=docker.service network-online.target

[Service]
Type=oneshot
ExecStart=/opt/xdc-node/scripts/version-check.sh
StandardOutput=append:/var/log/xdc-version-check.log
StandardError=append:/var/log/xdc-version-check.log

[Install]
WantedBy=multi-user.target
EOF
    
    cat > /etc/systemd/system/xdc-version-check.timer << 'EOF'
[Unit]
Description=XDC Node Version Check Timer

[Timer]
OnCalendar=*-*-* 00/6:17:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Daily backup timer
    cat > /etc/systemd/system/xdc-backup.service << 'EOF'
[Unit]
Description=XDC Node Backup
After=docker.service

[Service]
Type=oneshot
ExecStart=/opt/xdc-node/scripts/backup.sh
StandardOutput=append:/var/log/xdc-backup.log
StandardError=append:/var/log/xdc-backup.log

[Install]
WantedBy=multi-user.target
EOF
    
    cat > /etc/systemd/system/xdc-backup.timer << 'EOF'
[Unit]
Description=XDC Node Daily Backup Timer

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Reload systemd
    systemctl daemon-reload
    
    log "✓ Systemd timers created (not enabled by default, using cron)"
}

#==============================================================================
# Enable Systemd Timers (optional)
#==============================================================================
enable_systemd_timers() {
    log "Enabling systemd timers (alternative to cron)..."
    
    systemctl enable xdc-health-check.timer
    systemctl enable xdc-version-check.timer
    systemctl enable xdc-backup.timer
    
    systemctl start xdc-health-check.timer
    systemctl start xdc-version-check.timer
    systemctl start xdc-backup.timer
    
    log "✓ Systemd timers enabled"
}

#==============================================================================
# Verify Installation
#==============================================================================
verify_installation() {
    log ""
    log "========================================"
    log "Cron Jobs Verification"
    log "========================================"
    
    echo ""
    echo "Installed cron jobs (/etc/cron.d/xdc-node):"
    echo "============================================="
    grep -v "^#" /etc/cron.d/xdc-node | grep -v "^$" | head -20
    echo ""
    
    echo "Log rotation config (/etc/logrotate.d/xdc-node):"
    echo "================================================="
    head -20 /etc/logrotate.d/xdc-node
    echo ""
    
    echo "Systemd timers available:"
    echo "========================="
    systemctl list-timers --all 2>/dev/null | grep xdc || echo "No XDC systemd timers active"
    echo ""
}

#==============================================================================
# Print Schedule Summary
#==============================================================================
print_schedule_summary() {
    log ""
    log "========================================"
    log "XDC Node Scheduled Tasks Summary"
    log "========================================"
    log ""
    log "📋 Health Monitoring:"
    log "   • Every 15 minutes: Quick health check"
    log "   • Daily at 6:00 AM: Full report with security score"
    log ""
    log "📦 Version Management:"
    log "   • Every 6 hours: Check for new versions"
    log ""
    log "💾 Backups:"
    log "   • Daily at 3:00 AM: Incremental backup"
    log "   • Weekly (Sunday 2:00 AM): Full backup"
    log ""
    log "🔄 Maintenance:"
    log "   • Weekly: Log rotation"
    log "   • Daily: Clean old reports (>30 days)"
    log "   • Daily: Apply backup retention policy"
    log ""
    log "📁 Log Files:"
    log "   • /var/log/xdc-health-check.log"
    log "   • /var/log/xdc-version-check.log"
    log "   • /var/log/xdc-backup.log"
    log "   • /var/log/xdc-security-harden.log"
    log ""
}

#==============================================================================
# Main
#==============================================================================
main() {
    log "========================================"
    log "XDC Node Cron Setup Starting"
    log "========================================"
    
    check_root
    
    # Create directories
    mkdir -p /opt/xdc-node/reports
    mkdir -p /backup/xdc-node/{daily,weekly,monthly,config,logs}
    
    # Create log files first
    create_log_files
    
    # Install cron jobs
    install_cron_jobs
    
    # Setup log rotation
    setup_logrotate
    
    # Setup systemd timers (optional alternative)
    setup_systemd_timers
    
    # Verify
    verify_installation
    
    # Print summary
    print_schedule_summary
    
    log "========================================"
    log "Cron Setup Complete!"
    log "========================================"
}

main "$@"
