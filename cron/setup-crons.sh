#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDC Node Cron Setup Script
# Sets up all scheduled tasks for node maintenance
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="/opt/xdc-node/scripts"
LOG_DIR="/var/log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

#==============================================================================
# Install Cron Jobs
#==============================================================================
install_cron_jobs() {
    log "Installing cron jobs..."
    
    # Create cron.d file
    cat > /etc/cron.d/xdc-node << 'EOF'
# XDC Node Scheduled Tasks
# Installed by setup-crons.sh
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Health check every 15 minutes
*/15 * * * * root /opt/xdc-node/scripts/node-health-check.sh >> /var/log/xdc-health-check.log 2>&1

# Version check every 6 hours (at minutes 0, with offset to avoid peak times)
17 */6 * * * root /opt/xdc-node/scripts/version-check.sh >> /var/log/xdc-version-check.log 2>&1

# Daily backup at 3:00 AM
0 3 * * * root /opt/xdc-node/scripts/backup.sh >> /var/log/xdc-backup.log 2>&1

# Weekly log rotation (Sunday at midnight)
0 0 * * 0 root /usr/sbin/logrotate -f /etc/logrotate.d/xdc-node 2>/dev/null || true

# Daily security check at 6:00 AM
0 6 * * * root /opt/xdc-node/scripts/node-health-check.sh --full >> /var/log/xdc-health-check.log 2>&1
EOF
    
    chmod 644 /etc/cron.d/xdc-node
    
    log "✓ Cron jobs installed at /etc/cron.d/xdc-node"
}

#==============================================================================
# Setup Log Rotation
#==============================================================================
setup_logrotate() {
    log "Setting up log rotation..."
    
    cat > /etc/logrotate.d/xdc-node << 'EOF'
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

/opt/xdc-node/reports/*.json {
    daily
    missingok
    rotate 30
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
# Setup Systemd Timers (Alternative to Cron)
#==============================================================================
setup_systemd_timers() {
    log "Setting up systemd timers..."
    
    # Copy systemd files if they exist
    if [[ -d "$SCRIPT_DIR/../systemd" ]]; then
        cp "$SCRIPT_DIR/../systemd/"*.service /etc/systemd/system/ 2>/dev/null || true
        cp "$SCRIPT_DIR/../systemd/"*.timer /etc/systemd/system/ 2>/dev/null || true
    fi
    
    # Reload systemd
    systemctl daemon-reload
    
    # Enable health check timer
    if [[ -f "/etc/systemd/system/xdc-health-check.timer" ]]; then
        systemctl enable xdc-health-check.timer
        systemctl start xdc-health-check.timer
        log "✓ Health check timer enabled"
    fi
    
    log "✓ Systemd timers configured"
}

#==============================================================================
# Verify Installation
#==============================================================================
verify_installation() {
    log "Verifying cron installation..."
    
    echo ""
    echo "Installed cron jobs:"
    echo "===================="
    cat /etc/cron.d/xdc-node
    echo ""
    
    echo "Log rotation config:"
    echo "===================="
    cat /etc/logrotate.d/xdc-node
    echo ""
    
    echo "Systemd timers:"
    echo "==============="
    systemctl list-timers --all | grep xdc || echo "No systemd timers found"
    echo ""
}

#==============================================================================
# Main
#==============================================================================
main() {
    log "Starting cron setup..."
    
    # Check root
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi
    
    # Create log files
    touch /var/log/xdc-health-check.log
    touch /var/log/xdc-version-check.log
    touch /var/log/xdc-backup.log
    chmod 640 /var/log/xdc-*.log
    
    # Install cron jobs
    install_cron_jobs
    
    # Setup log rotation
    setup_logrotate
    
    # Setup systemd timers
    setup_systemd_timers
    
    # Verify
    verify_installation
    
    log ""
    log "=================================="
    log "Cron Setup Complete!"
    log "=================================="
    log ""
    log "Scheduled tasks:"
    log "  • Health check: Every 15 minutes"
    log "  • Version check: Every 6 hours"
    log "  • Backup: Daily at 3:00 AM"
    log "  • Log rotation: Weekly"
    log ""
    log "Logs:"
    log "  • /var/log/xdc-health-check.log"
    log "  • /var/log/xdc-version-check.log"
    log "  • /var/log/xdc-backup.log"
}

main "$@"
