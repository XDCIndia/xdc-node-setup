#!/usr/bin/env bash

# Source common utilities
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || source "$(dirname "$0")/lib/common.sh" 2>/dev/null || { echo "ERROR: Cannot source common.sh"; exit 1; }
set -euo pipefail

#===============================================================================
# Enterprise CIS Benchmark Security Audit Script for XDC Nodes
# Based on CIS Ubuntu Server Benchmark v2.0.0
#
# Features:
#   - 60+ security checks across 6 categories
#   - Scoring system (100 points)
#   - JSON and HTML reports
#   - Auto-remediation with --remediate
#   - Category filtering with --category
#
# Usage:
#   ./cis-benchmark.sh                    # Run all checks
#   ./cis-benchmark.sh --category auth    # Run specific category
#   ./cis-benchmark.sh --remediate        # Auto-fix issues
#   ./cis-benchmark.sh --json             # Output JSON report
#   ./cis-benchmark.sh --html             # Output HTML report
#
# Categories: filesystem, services, network, logging, auth, permissions
#===============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Counters
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TOTAL_COUNT=0
TOTAL_SCORE=0
MAX_SCORE=0

# Options
REMEDIATE=false
JSON_OUTPUT=false
HTML_OUTPUT=false
CATEGORY=""
REPORT_FILE=""
QUIET=false

# Results array for JSON
declare -a RESULTS=()

# Category weights (total = 100)
declare -A CATEGORY_WEIGHTS=(
    [filesystem]=15
    [services]=10
    [network]=20
    [logging]=15
    [auth]=25
    [permissions]=15
)

#===============================================================================
# Helper Functions
#===============================================================================

usage() {
    cat << EOF
Enterprise CIS Benchmark Security Audit for XDC Nodes

Usage: $0 [OPTIONS]

Options:
    --remediate         Auto-fix issues where possible
    --category <cat>    Run only specific category
                        (filesystem, services, network, logging, auth, permissions)
    --json              Output JSON report
    --html              Output HTML report
    --output <file>     Specify output file for report
    --quiet             Suppress console output
    -h, --help          Show this help message

Examples:
    $0                          # Run all checks
    $0 --category auth          # Run auth checks only
    $0 --remediate              # Run and auto-fix
    $0 --json --output report.json
    $0 --html --output report.html

EOF
    exit 0
}

log_pass() {
    local check_id="$1"
    local description="$2"
    local weight="${3:-1}"
    ((PASS_COUNT++))
    ((TOTAL_COUNT++))
    ((TOTAL_SCORE+=weight))
    ((MAX_SCORE+=weight))
    [[ "$QUIET" == "false" ]] && echo -e "${GREEN}[PASS]${NC} $check_id: $description"
    RESULTS+=("{\"id\":\"$check_id\",\"description\":\"$description\",\"status\":\"PASS\",\"weight\":$weight}")
}

log_fail() {
    local check_id="$1"
    local description="$2"
    local details="${3:-}"
    local weight="${4:-1}"
    ((FAIL_COUNT++))
    ((TOTAL_COUNT++))
    ((MAX_SCORE+=weight))
    [[ "$QUIET" == "false" ]] && echo -e "${RED}[FAIL]${NC} $check_id: $description"
    [[ -n "$details" && "$QUIET" == "false" ]] && echo -e "       ${YELLOW}→ $details${NC}"
    RESULTS+=("{\"id\":\"$check_id\",\"description\":\"$description\",\"status\":\"FAIL\",\"details\":\"$details\",\"weight\":$weight}")
}

log_skip() {
    local check_id="$1"
    local description="$2"
    local reason="${3:-Not applicable}"
    ((SKIP_COUNT++))
    ((TOTAL_COUNT++))
    [[ "$QUIET" == "false" ]] && echo -e "${YELLOW}[SKIP]${NC} $check_id: $description ($reason)"
    RESULTS+=("{\"id\":\"$check_id\",\"description\":\"$description\",\"status\":\"SKIP\",\"reason\":\"$reason\"}")
}

log_info() {
    [[ "$QUIET" == "false" ]] && echo -e "${BLUE}[INFO]${NC} $1"
}

log_section() {
    [[ "$QUIET" == "false" ]] && echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    [[ "$QUIET" == "false" ]] && echo -e "${CYAN}║${NC} $1"
    [[ "$QUIET" == "false" ]] && echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
}

#===============================================================================
# Category 1: Filesystem Configuration (15 points)
#===============================================================================

check_filesystem() {
    log_section "Category 1: Filesystem Configuration"
    
    # 1.1 Ensure /tmp is on separate partition
    if mount | grep -q "on /tmp "; then
        log_pass "1.1" "/tmp is on separate partition" 2
        
        # Check mount options
        local opts
        opts=$(mount | grep "on /tmp " | awk '{print $6}' | tr ',' '\n')
        if echo "$opts" | grep -q "nodev" && echo "$opts" | grep -q "nosuid" && echo "$opts" | grep -q "noexec"; then
            log_pass "1.1.1" "/tmp has nodev,nosuid,noexec" 1
        else
            log_fail "1.1.1" "/tmp missing mount options" "Expected: nodev,nosuid,noexec" 1
            if [[ "$REMEDIATE" == "true" ]]; then
                log_info "Remediating: Update /etc/fstab for /tmp options"
            fi
        fi
    else
        log_fail "1.1" "/tmp not on separate partition" "Security risk: /tmp shares partition with /" 2
    fi
    
    # 1.2 Ensure /var is on separate partition
    if mount | grep -q "on /var "; then
        log_pass "1.2" "/var is on separate partition" 2
    else
        log_fail "1.2" "/var not on separate partition" 2
    fi
    
    # 1.3 Ensure /var/log is on separate partition
    if mount | grep -q "on /var/log "; then
        log_pass "1.3" "/var/log is on separate partition" 1
    else
        log_fail "1.3" "/var/log not on separate partition" 1
    fi
    
    # 1.4 Ensure /var/log/audit is on separate partition
    if mount | grep -q "on /var/log/audit "; then
        log_pass "1.4" "/var/log/audit is on separate partition" 1
    else
        log_fail "1.4" "/var/log/audit not on separate partition" 1
    fi
    
    # 1.5 Ensure sticky bit on world-writable directories
    local ww_dirs
    ww_dirs=$(df --local -P | awk '{if (NR!=1) print $6}' | xargs -I '{}' find '{}' -xdev -type d -perm -0002 2>/dev/null | grep -v "/proc\|/sys")
    if [[ -z "$ww_dirs" ]]; then
        log_pass "1.5" "No world-writable directories without sticky bit" 2
    else
        log_fail "1.5" "Found world-writable directories without sticky bit" "$ww_dirs" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            echo "$ww_dirs" | xargs chmod a+t
            log_info "Remediated: Applied sticky bit to world-writable directories"
        fi
    fi
    
    # 1.6 Disable automounting
    if systemctl is-enabled autofs 2>/dev/null | grep -q "enabled"; then
        log_fail "1.6" "Automounting is enabled" "autofs service is running" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            systemctl stop autofs
            systemctl disable autofs
            log_info "Remediated: Disabled autofs"
        fi
    else
        log_pass "1.6" "Automounting is disabled" 2
    fi
    
    # 1.7 Disable USB storage
    if modprobe -n -v usb-storage 2>/dev/null | grep -q "install /bin/true"; then
        log_pass "1.7" "USB storage is disabled" 2
    else
        log_fail "1.7" "USB storage is not disabled" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            echo "install usb-storage /bin/true" > /etc/modprobe.d/usb-storage.conf
            rmmod usb-storage 2>/dev/null || true
            log_info "Remediated: Disabled USB storage"
        fi
    fi
    
    # 1.8 Ensure nodev on /home
    if mount | grep -q "on /home "; then
        if mount | grep "on /home " | grep -q "nodev"; then
            log_pass "1.8" "/home has nodev option" 1
        else
            log_fail "1.8" "/home missing nodev option" 1
        fi
    else
        log_skip "1.8" "/home nodev check" "/home not a separate partition"
    fi
    
    # 1.9 Ensure noexec on /dev/shm
    if mount | grep -q "on /dev/shm "; then
        if mount | grep "on /dev/shm " | grep -q "noexec"; then
            log_pass "1.9" "/dev/shm has noexec option" 1
        else
            log_fail "1.9" "/dev/shm missing noexec option" 1
        fi
    else
        log_fail "1.9" "/dev/shm not mounted" 1
    fi
}

#===============================================================================
# Category 2: Services (10 points)
#===============================================================================

check_services() {
    log_section "Category 2: Services"
    
    # 2.1 Ensure xinetd is not installed
    if dpkg -l xinetd 2>/dev/null | grep -q "^ii"; then
        log_fail "2.1" "xinetd is installed" 1
        if [[ "$REMEDIATE" == "true" ]]; then
            apt-get remove -y xinetd
            log_info "Remediated: Removed xinetd"
        fi
    else
        log_pass "2.1" "xinetd is not installed" 1
    fi
    
    # 2.2 Ensure openbsd-inetd is not installed
    if dpkg -l openbsd-inetd 2>/dev/null | grep -q "^ii"; then
        log_fail "2.2" "openbsd-inetd is installed" 1
        if [[ "$REMEDIATE" == "true" ]]; then
            apt-get remove -y openbsd-inetd
            log_info "Remediated: Removed openbsd-inetd"
        fi
    else
        log_pass "2.2" "openbsd-inetd is not installed" 1
    fi
    
    # 2.3 Ensure NIS is not installed
    if dpkg -l nis 2>/dev/null | grep -q "^ii"; then
        log_fail "2.3" "NIS is installed" 1
        if [[ "$REMEDIATE" == "true" ]]; then
            apt-get remove -y nis
            log_info "Remediated: Removed NIS"
        fi
    else
        log_pass "2.3" "NIS is not installed" 1
    fi
    
    # 2.4 Ensure rsh is not installed
    if dpkg -l rsh-client rsh-redone-client 2>/dev/null | grep -q "^ii"; then
        log_fail "2.4" "rsh client is installed" 1
        if [[ "$REMEDIATE" == "true" ]]; then
            apt-get remove -y rsh-client rsh-redone-client
            log_info "Remediated: Removed rsh client"
        fi
    else
        log_pass "2.4" "rsh client is not installed" 1
    fi
    
    # 2.5 Ensure talk is not installed
    if dpkg -l talk talkd 2>/dev/null | grep -q "^ii"; then
        log_fail "2.5" "talk is installed" 1
        if [[ "$REMEDIATE" == "true" ]]; then
            apt-get remove -y talk talkd
            log_info "Remediated: Removed talk"
        fi
    else
        log_pass "2.5" "talk is not installed" 1
    fi
    
    # 2.6 Ensure telnet is not installed
    if dpkg -l telnet 2>/dev/null | grep -q "^ii"; then
        log_fail "2.6" "telnet is installed" 1
        if [[ "$REMEDIATE" == "true" ]]; then
            apt-get remove -y telnet
            log_info "Remediated: Removed telnet"
        fi
    else
        log_pass "2.6" "telnet is not installed" 1
    fi
    
    # 2.7 Ensure LDAP client is not installed
    if dpkg -l ldap-utils 2>/dev/null | grep -q "^ii"; then
        log_fail "2.7" "LDAP client is installed" 1
        if [[ "$REMEDIATE" == "true" ]]; then
            apt-get remove -y ldap-utils
            log_info "Remediated: Removed LDAP client"
        fi
    else
        log_pass "2.7" "LDAP client is not installed" 1
    fi
    
    # 2.8 Ensure time synchronization is configured
    if systemctl is-active systemd-timesyncd chronyd ntp 2>/dev/null | grep -q "active"; then
        log_pass "2.8" "Time synchronization is active" 2
    else
        log_fail "2.8" "Time synchronization is not configured" "Install chrony or systemd-timesyncd" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            apt-get install -y systemd-timesyncd
            systemctl enable systemd-timesyncd
            systemctl start systemd-timesyncd
            log_info "Remediated: Installed and enabled systemd-timesyncd"
        fi
    fi
}

#===============================================================================
# Category 3: Network Configuration (20 points)
#===============================================================================

check_network() {
    log_section "Category 3: Network Configuration"
    
    # 3.1 Ensure IP forwarding is disabled
    if sysctl net.ipv4.ip_forward 2>/dev/null | grep -q "= 0"; then
        log_pass "3.1" "IP forwarding is disabled" 2
    else
        log_fail "3.1" "IP forwarding is enabled" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            sysctl -w net.ipv4.ip_forward=0
            echo "net.ipv4.ip_forward = 0" >> /etc/sysctl.conf
            log_info "Remediated: Disabled IP forwarding"
        fi
    fi
    
    # 3.2 Ensure ICMP redirects are not accepted
    local icmp_ok=true
    for i in $(sysctl -a 2>/dev/null | grep "accept_redirects" | grep "ipv4" | cut -d= -f2 | xargs); do
        if [[ "$i" != "0" ]]; then
            icmp_ok=false
            break
        fi
    done
    if [[ "$icmp_ok" == "true" ]]; then
        log_pass "3.2" "ICMP redirects are not accepted" 2
    else
        log_fail "3.2" "ICMP redirects are accepted" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            sysctl -w net.ipv4.conf.all.accept_redirects=0
            sysctl -w net.ipv4.conf.default.accept_redirects=0
            echo "net.ipv4.conf.all.accept_redirects = 0" >> /etc/sysctl.conf
            echo "net.ipv4.conf.default.accept_redirects = 0" >> /etc/sysctl.conf
            log_info "Remediated: Disabled ICMP redirects"
        fi
    fi
    
    # 3.3 Ensure source routed packets are not accepted
    local srcroute_ok=true
    for i in $(sysctl -a 2>/dev/null | grep "accept_source_route" | grep "ipv4" | cut -d= -f2 | xargs); do
        if [[ "$i" != "0" ]]; then
            srcroute_ok=false
            break
        fi
    done
    if [[ "$srcroute_ok" == "true" ]]; then
        log_pass "3.3" "Source routed packets are not accepted" 2
    else
        log_fail "3.3" "Source routed packets are accepted" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            sysctl -w net.ipv4.conf.all.accept_source_route=0
            sysctl -w net.ipv4.conf.default.accept_source_route=0
            echo "net.ipv4.conf.all.accept_source_route = 0" >> /etc/sysctl.conf
            echo "net.ipv4.conf.default.accept_source_route = 0" >> /etc/sysctl.conf
            log_info "Remediated: Disabled source routing"
        fi
    fi
    
    # 3.4 Ensure suspicious packets are logged
    if sysctl net.ipv4.conf.all.log_martians 2>/dev/null | grep -q "= 1"; then
        log_pass "3.4" "Suspicious packets are logged" 1
    else
        log_fail "3.4" "Suspicious packets are not logged" 1
        if [[ "$REMEDIATE" == "true" ]]; then
            sysctl -w net.ipv4.conf.all.log_martians=1
            sysctl -w net.ipv4.conf.default.log_martians=1
            echo "net.ipv4.conf.all.log_martians = 1" >> /etc/sysctl.conf
            log_info "Remediated: Enabled martian packet logging"
        fi
    fi
    
    # 3.5 Ensure TCP SYN cookies are enabled
    if sysctl net.ipv4.tcp_syncookies 2>/dev/null | grep -q "= 1"; then
        log_pass "3.5" "TCP SYN cookies are enabled" 2
    else
        log_fail "3.5" "TCP SYN cookies are disabled" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            sysctl -w net.ipv4.tcp_syncookies=1
            echo "net.ipv4.tcp_syncookies = 1" >> /etc/sysctl.conf
            log_info "Remediated: Enabled TCP SYN cookies"
        fi
    fi
    
    # 3.6 Ensure IPv6 router advertisements are not accepted
    if sysctl net.ipv6.conf.all.accept_ra 2>/dev/null | grep -q "= 0"; then
        log_pass "3.6" "IPv6 router advertisements are not accepted" 1
    else
        log_fail "3.6" "IPv6 router advertisements are accepted" 1
    fi
    
    # 3.7 Ensure DCCP is disabled
    if modprobe -n -v dccp 2>/dev/null | grep -q "install /bin/true"; then
        log_pass "3.7" "DCCP is disabled" 1
    else
        log_fail "3.7" "DCCP is not disabled" 1
        if [[ "$REMEDIATE" == "true" ]]; then
            echo "install dccp /bin/true" >> /etc/modprobe.d/dccp.conf
            log_info "Remediated: Disabled DCCP"
        fi
    fi
    
    # 3.8 Ensure SCTP is disabled
    if modprobe -n -v sctp 2>/dev/null | grep -q "install /bin/true"; then
        log_pass "3.8" "SCTP is disabled" 1
    else
        log_fail "3.8" "SCTP is not disabled" 1
        if [[ "$REMEDIATE" == "true" ]]; then
            echo "install sctp /bin/true" >> /etc/modprobe.d/sctp.conf
            log_info "Remediated: Disabled SCTP"
        fi
    fi
    
    # 3.9 Ensure RDS is disabled
    if modprobe -n -v rds 2>/dev/null | grep -q "install /bin/true"; then
        log_pass "3.9" "RDS is disabled" 1
    else
        log_fail "3.9" "RDS is not disabled" 1
    fi
    
    # 3.10 Ensure TIPC is disabled
    if modprobe -n -v tipc 2>/dev/null | grep -q "install /bin/true"; then
        log_pass "3.10" "TIPC is disabled" 1
    else
        log_fail "3.10" "TIPC is not disabled" 1
    fi
    
    # 3.11 Ensure firewall is active
    if systemctl is-active ufw 2>/dev/null | grep -q "active" || \
       systemctl is-active firewalld 2>/dev/null | grep -q "active" || \
       systemctl is-active nftables 2>/dev/null | grep -q "active"; then
        log_pass "3.11" "Firewall is active" 2
    else
        log_fail "3.11" "No active firewall detected" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            apt-get install -y ufw
            ufw --force enable
            log_info "Remediated: Enabled UFW firewall"
        fi
    fi
    
    # 3.12 Ensure default deny firewall policy
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        if ufw status verbose 2>/dev/null | grep -q "Default: deny (incoming)"; then
            log_pass "3.12" "Default deny policy is set" 2
        else
            log_fail "3.12" "Default deny policy not set" 2
        fi
    else
        log_skip "3.12" "Default deny policy check" "UFW not active"
    fi
}

#===============================================================================
# Category 4: Logging & Auditing (15 points)
#===============================================================================

check_logging() {
    log_section "Category 4: Logging & Auditing"
    
    # 4.1 Ensure rsyslog is installed and running
    if dpkg -l rsyslog 2>/dev/null | grep -q "^ii"; then
        if systemctl is-active rsyslog 2>/dev/null | grep -q "active"; then
            log_pass "4.1" "rsyslog is installed and running" 2
        else
            log_fail "4.1" "rsyslog is installed but not running" 2
            if [[ "$REMEDIATE" == "true" ]]; then
                systemctl enable rsyslog
                systemctl start rsyslog
            fi
        fi
    else
        log_fail "4.1" "rsyslog is not installed" 2
    fi
    
    # 4.2 Ensure remote log host is configured (if applicable)
    if grep -q "^*.*@" /etc/rsyslog.conf 2>/dev/null || grep -q "^*.*@" /etc/rsyslog.d/*.conf 2>/dev/null; then
        log_pass "4.2" "Remote log host is configured" 1
    else
        log_skip "4.2" "Remote log host check" "No remote logging configured (optional)"
    fi
    
    # 4.3 Ensure auditd is installed and running
    if dpkg -l auditd 2>/dev/null | grep -q "^ii"; then
        if systemctl is-active auditd 2>/dev/null | grep -q "active"; then
            log_pass "4.3" "auditd is installed and running" 2
        else
            log_fail "4.3" "auditd is installed but not running" 2
            if [[ "$REMEDIATE" == "true" ]]; then
                systemctl enable auditd
                systemctl start auditd
            fi
        fi
    else
        log_fail "4.3" "auditd is not installed" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            apt-get install -y auditd audispd-plugins
            systemctl enable auditd
            systemctl start auditd
            log_info "Remediated: Installed and enabled auditd"
        fi
    fi
    
    # 4.4 Ensure audit log storage size is configured
    if grep -q "^max_log_file\s" /etc/audit/auditd.conf 2>/dev/null; then
        log_pass "4.4" "Audit log storage size is configured" 1
    else
        log_fail "4.4" "Audit log storage size not configured" 1
    fi
    
    # 4.5 Ensure login/logout events are collected
    if grep -q "logins\|utmp\|wtmp" /etc/audit/rules.d/*.rules 2>/dev/null; then
        log_pass "4.5" "Login/logout events are collected" 1
    else
        log_fail "4.5" "Login/logout events not collected" 1
        if [[ "$REMEDIATE" == "true" ]]; then
            cat >> /etc/audit/rules.d/audit.rules << 'EOF'
-w /var/log/wtmp -p wa -k logins
-w /var/log/btmp -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/run/utmp -p wa -k logins
EOF
            log_info "Remediated: Added login/logout audit rules"
        fi
    fi
    
    # 4.6 Ensure session initiation information is collected
    if grep -q "session\|USER_START\|USER_END" /etc/audit/rules.d/*.rules 2>/dev/null; then
        log_pass "4.6" "Session initiation is collected" 1
    else
        log_fail "4.6" "Session initiation not collected" 1
    fi
    
    # 4.7 Ensure permission changes are collected
    if grep -q "chmod\|chown\|setxattr" /etc/audit/rules.d/*.rules 2>/dev/null; then
        log_pass "4.7" "Permission changes are collected" 1
    else
        log_fail "4.7" "Permission changes not collected" 1
    fi
    
    # 4.8 Ensure unauthorized access attempts are collected
    if grep -q "access\|permission" /etc/audit/rules.d/*.rules 2>/dev/null; then
        log_pass "4.8" "Unauthorized access attempts are collected" 1
    else
        log_fail "4.8" "Unauthorized access attempts not collected" 1
    fi
    
    # 4.9 Ensure admin scope changes are collected
    if grep -q "sudo\|sudoers" /etc/audit/rules.d/*.rules 2>/dev/null; then
        log_pass "4.9" "Admin scope changes are collected" 1
    else
        log_fail "4.9" "Admin scope changes not collected" 1
    fi
    
    # 4.10 Ensure kernel module loading is collected
    if grep -q "init_module\|delete_module" /etc/audit/rules.d/*.rules 2>/dev/null; then
        log_pass "4.10" "Kernel module loading is collected" 1
    else
        log_fail "4.10" "Kernel module loading not collected" 1
        if [[ "$REMEDIATE" == "true" ]]; then
            cat >> /etc/audit/rules.d/audit.rules << 'EOF'
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S init_module -S delete_module -k modules
EOF
            log_info "Remediated: Added kernel module audit rules"
        fi
    fi
}

#===============================================================================
# Category 5: Access & Authentication (25 points)
#===============================================================================

check_auth() {
    log_section "Category 5: Access & Authentication"
    
    # 5.1 Ensure password minimum length is 14+
    local minlen
    minlen=$(grep "^minlen" /etc/security/pwquality.conf 2>/dev/null | awk '{print $3}' || echo "0")
    if [[ "$minlen" -ge 14 ]]; then
        log_pass "5.1" "Password minimum length is >= 14" 2
    else
        log_fail "5.1" "Password minimum length is < 14" "Current: $minlen" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            sed -i 's/^#\?minlen.*/minlen = 14/' /etc/security/pwquality.conf
            echo "minlen = 14" >> /etc/security/pwquality.conf
            log_info "Remediated: Set password minimum length to 14"
        fi
    fi
    
    # 5.2 Ensure password complexity is configured
    if grep -q "^minclass\s*=" /etc/security/pwquality.conf 2>/dev/null || \
       grep -q "^lcredit\|ucredit\|dcredit\|ocredit" /etc/security/pwquality.conf 2>/dev/null; then
        log_pass "5.2" "Password complexity is configured" 2
    else
        log_fail "5.2" "Password complexity not configured" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            cat >> /etc/security/pwquality.conf << 'EOF'
minclass = 4
lcredit = -1
ucredit = -1
dcredit = -1
ocredit = -1
EOF
            log_info "Remediated: Configured password complexity"
        fi
    fi
    
    # 5.3 Ensure password expiration is 365 days or less
    local maxdays
    maxdays=$(grep "^PASS_MAX_DAYS" /etc/login.defs 2>/dev/null | awk '{print $2}' || echo "99999")
    if [[ "$maxdays" -le 365 && "$maxdays" -gt 0 ]]; then
        log_pass "5.3" "Password expiration is <= 365 days" 2
    else
        log_fail "5.3" "Password expiration is > 365 days" "Current: $maxdays" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS 90/' /etc/login.defs
            log_info "Remediated: Set password expiration to 90 days"
        fi
    fi
    
    # 5.4 Ensure password minimum age is 1 day or more
    local mindays
    mindays=$(grep "^PASS_MIN_DAYS" /etc/login.defs 2>/dev/null | awk '{print $2}' || echo "0")
    if [[ "$mindays" -ge 1 ]]; then
        log_pass "5.4" "Password minimum age is >= 1 day" 1
    else
        log_fail "5.4" "Password minimum age is < 1 day" "Current: $mindays" 1
        if [[ "$REMEDIATE" == "true" ]]; then
            sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS 1/' /etc/login.defs
            log_info "Remediated: Set password minimum age to 1 day"
        fi
    fi
    
    # 5.5 Ensure failed login lockout is configured
    if grep -q "pam_tally2\|pam_faillock" /etc/pam.d/common-auth 2>/dev/null; then
        log_pass "5.5" "Failed login lockout is configured" 2
    else
        log_fail "5.5" "Failed login lockout not configured" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            apt-get install -y libpam-tally2
            log_info "Remediated: Installed fail lockout (manual configuration required)"
        fi
    fi
    
    # 5.6 Ensure inactive accounts are locked after 30 days
    local inactive
    inactive=$(useradd -D 2>/dev/null | grep INACTIVE | cut -d= -f2 || echo "-1")
    if [[ "$inactive" -le 30 && "$inactive" -ge 0 ]]; then
        log_pass "5.6" "Inactive accounts locked after <= 30 days" 1
    else
        log_fail "5.6" "Inactive account lockout not configured" "Current: $inactive" 1
        if [[ "$REMEDIATE" == "true" ]]; then
            useradd -D -f 30
            log_info "Remediated: Set inactive account lockout to 30 days"
        fi
    fi
    
    # 5.7 Ensure root login is restricted to console
    if grep -q "^console" /etc/securetty 2>/dev/null | head -1; then
        log_pass "5.7" "Root login is restricted to console" 2
    else
        log_fail "5.7" "Root login not restricted to console" 2
    fi
    
    # 5.8 Ensure su is restricted to wheel/sudo group
    if grep -q "auth required pam_wheel.so" /etc/pam.d/su 2>/dev/null; then
        log_pass "5.8" "su is restricted to wheel group" 2
    else
        log_fail "5.8" "su not restricted to wheel group" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            echo "auth required pam_wheel.so use_uid" >> /etc/pam.d/su
            log_info "Remediated: Restricted su to wheel group"
        fi
    fi
    
    # 5.9 Ensure SSH Protocol is 2
    if grep -q "^Protocol 2" /etc/ssh/sshd_config 2>/dev/null; then
        log_pass "5.9" "SSH Protocol 2 is enabled" 1
    else
        log_fail "5.9" "SSH Protocol 2 not explicitly set" 1
        if [[ "$REMEDIATE" == "true" ]]; then
            echo "Protocol 2" >> /etc/ssh/sshd_config
            systemctl restart sshd
            log_info "Remediated: Set SSH Protocol 2"
        fi
    fi
    
    # 5.10 Ensure SSH LogLevel is INFO or VERBOSE
    if grep -E "^LogLevel\s+(INFO|VERBOSE)" /etc/ssh/sshd_config 2>/dev/null; then
        log_pass "5.10" "SSH LogLevel is INFO or VERBOSE" 1
    else
        log_fail "5.10" "SSH LogLevel not set to INFO/VERBOSE" 1
        if [[ "$REMEDIATE" == "true" ]]; then
            sed -i 's/^#\?LogLevel.*/LogLevel VERBOSE/' /etc/ssh/sshd_config
            systemctl restart sshd
            log_info "Remediated: Set SSH LogLevel to VERBOSE"
        fi
    fi
    
    # 5.11 Ensure SSH MaxAuthTries is 4 or less
    local maxtries
    maxtries=$(grep "^MaxAuthTries" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "6")
    if [[ "$maxtries" -le 4 ]]; then
        log_pass "5.11" "SSH MaxAuthTries is <= 4" 2
    else
        log_fail "5.11" "SSH MaxAuthTries is > 4" "Current: $maxtries" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            sed -i 's/^#\?MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
            systemctl restart sshd
            log_info "Remediated: Set SSH MaxAuthTries to 3"
        fi
    fi
    
    # 5.12 Ensure SSH PermitRootLogin is without-password/prohibit-password
    if grep -E "^PermitRootLogin\s+(no|without-password|prohibit-password)" /etc/ssh/sshd_config 2>/dev/null; then
        log_pass "5.12" "SSH PermitRootLogin is secure" 2
    else
        log_fail "5.12" "SSH PermitRootLogin allows password" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
            systemctl restart sshd
            log_info "Remediated: Set SSH PermitRootLogin to prohibit-password"
        fi
    fi
}

#===============================================================================
# Category 6: File Permissions (15 points)
#===============================================================================

check_permissions() {
    log_section "Category 6: File Permissions"
    
    # 6.1 Ensure /etc/passwd permissions are 644
    local perms
    perms=$(stat -c "%a" /etc/passwd 2>/dev/null || echo "000")
    if [[ "$perms" == "644" ]]; then
        log_pass "6.1" "/etc/passwd permissions are 644" 2
    else
        log_fail "6.1" "/etc/passwd permissions are not 644" "Current: $perms" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            chmod 644 /etc/passwd
            log_info "Remediated: Set /etc/passwd permissions to 644"
        fi
    fi
    
    # 6.2 Ensure /etc/shadow permissions are 640
    perms=$(stat -c "%a" /etc/shadow 2>/dev/null || echo "000")
    if [[ "$perms" == "640" || "$perms" == "600" ]]; then
        log_pass "6.2" "/etc/shadow permissions are 640/600" 2
    else
        log_fail "6.2" "/etc/shadow permissions are not 640" "Current: $perms" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            chmod 640 /etc/shadow
            log_info "Remediated: Set /etc/shadow permissions to 640"
        fi
    fi
    
    # 6.3 Ensure /etc/group permissions are 644
    perms=$(stat -c "%a" /etc/group 2>/dev/null || echo "000")
    if [[ "$perms" == "644" ]]; then
        log_pass "6.3" "/etc/group permissions are 644" 2
    else
        log_fail "6.3" "/etc/group permissions are not 644" "Current: $perms" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            chmod 644 /etc/group
            log_info "Remediated: Set /etc/group permissions to 644"
        fi
    fi
    
    # 6.4 Ensure /etc/passwd- permissions are 600
    if [[ -f /etc/passwd- ]]; then
        perms=$(stat -c "%a" /etc/passwd- 2>/dev/null || echo "000")
        if [[ "$perms" == "600" ]]; then
            log_pass "6.4" "/etc/passwd- permissions are 600" 1
        else
            log_fail "6.4" "/etc/passwd- permissions are not 600" "Current: $perms" 1
            if [[ "$REMEDIATE" == "true" ]]; then
                chmod 600 /etc/passwd-
                log_info "Remediated: Set /etc/passwd- permissions to 600"
            fi
        fi
    else
        log_skip "6.4" "/etc/passwd- permissions" "File does not exist"
    fi
    
    # 6.5 Ensure /etc/shadow- permissions are 600
    if [[ -f /etc/shadow- ]]; then
        perms=$(stat -c "%a" /etc/shadow- 2>/dev/null || echo "000")
        if [[ "$perms" == "600" ]]; then
            log_pass "6.5" "/etc/shadow- permissions are 600" 1
        else
            log_fail "6.5" "/etc/shadow- permissions are not 600" "Current: $perms" 1
            if [[ "$REMEDIATE" == "true" ]]; then
                chmod 600 /etc/shadow-
                log_info "Remediated: Set /etc/shadow- permissions to 600"
            fi
        fi
    else
        log_skip "6.5" "/etc/shadow- permissions" "File does not exist"
    fi
    
    # 6.6 Ensure no world-writable files exist
    local ww_files
    ww_files=$(find / -xdev -type f -perm -0002 2>/dev/null | grep -v "/proc\|/sys" | head -5)
    if [[ -z "$ww_files" ]]; then
        log_pass "6.6" "No world-writable files found" 2
    else
        log_fail "6.6" "World-writable files found" "$ww_files" 2
        if [[ "$REMEDIATE" == "true" ]]; then
            find / -xdev -type f -perm -0002 -exec chmod o-w {} \; 2>/dev/null || true
            log_info "Remediated: Removed world-write permissions from files"
        fi
    fi
    
    # 6.7 Ensure no unowned files or directories exist
    local unowned
    unowned=$(find / -xdev \( -nouser -o -nogroup \) 2>/dev/null | grep -v "/proc\|/sys" | head -5)
    if [[ -z "$unowned" ]]; then
        log_pass "6.7" "No unowned files or directories found" 2
    else
        log_fail "6.7" "Unowned files or directories found" "$unowned" 2
    fi
    
    # 6.8 Ensure no SUID/SGID files in non-standard locations
    local suid_files
    suid_files=$(find / -xdev -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | \
                 grep -v -E "^/(bin|sbin|usr/bin|usr/sbin|usr/lib)/" | head -5)
    if [[ -z "$suid_files" ]]; then
        log_pass "6.8" "No SUID/SGID files in non-standard locations" 2
    else
        log_fail "6.8" "SUID/SGID files in non-standard locations" "$suid_files" 2
    fi
}

#===============================================================================
# Report Generation
#===============================================================================

generate_json_report() {
    local output_file="${REPORT_FILE:-/tmp/cis-benchmark-$(date +%Y%m%d-%H%M%S).json}"
    local score_percent=0
    if [[ $MAX_SCORE -gt 0 ]]; then
        score_percent=$((TOTAL_SCORE * 100 / MAX_SCORE))
    fi
    
    cat > "$output_file" << EOF
{
  "scan_info": {
    "timestamp": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "os": "$(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)",
    "script_version": "2.0.0"
  },
  "summary": {
    "total_checks": $TOTAL_COUNT,
    "passed": $PASS_COUNT,
    "failed": $FAIL_COUNT,
    "skipped": $SKIP_COUNT,
    "score": $TOTAL_SCORE,
    "max_score": $MAX_SCORE,
    "score_percent": $score_percent,
    "rating": "$([[ $score_percent -ge 90 ]] && echo "EXCELLENT" || ([[ $score_percent -ge 70 ]] && echo "GOOD" || ([[ $score_percent -ge 50 ]] && echo "FAIR" || echo "POOR")))"
  },
  "results": [
$(printf '%s\n' "${RESULTS[@]}" | sed '$!s/$/,/')
  ]
}
EOF
    echo -e "\n${GREEN}JSON report saved to: $output_file${NC}"
}

generate_html_report() {
    local output_file="${REPORT_FILE:-/tmp/cis-benchmark-$(date +%Y%m%d-%H%M%S).html}"
    local score_percent=0
    if [[ $MAX_SCORE -gt 0 ]]; then
        score_percent=$((TOTAL_SCORE * 100 / MAX_SCORE))
    fi
    
    local rating_color
    if [[ $score_percent -ge 90 ]]; then
        rating_color="#28a745"
    elif [[ $score_percent -ge 70 ]]; then
        rating_color="#ffc107"
    elif [[ $score_percent -ge 50 ]]; then
        rating_color="#fd7e14"
    else
        rating_color="#dc3545"
    fi
    
    cat > "$output_file" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CIS Benchmark Report - $(hostname)</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #007bff; padding-bottom: 10px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 30px 0; }
        .card { background: #f8f9fa; padding: 20px; border-radius: 8px; text-align: center; }
        .card h3 { margin: 0 0 10px 0; color: #666; font-size: 14px; text-transform: uppercase; }
        .card .value { font-size: 32px; font-weight: bold; color: #333; }
        .score { background: ${rating_color}; color: white; }
        .score .value { color: white; }
        .passed { color: #28a745; }
        .failed { color: #dc3545; }
        .skipped { color: #ffc107; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #dee2e6; }
        th { background: #f8f9fa; font-weight: 600; }
        tr:hover { background: #f8f9fa; }
        .status-pass { color: #28a745; font-weight: bold; }
        .status-fail { color: #dc3545; font-weight: bold; }
        .status-skip { color: #ffc107; font-weight: bold; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #dee2e6; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔒 CIS Benchmark Security Audit Report</h1>
        
        <div class="summary">
            <div class="card score">
                <h3>Security Score</h3>
                <div class="value">${score_percent}%</div>
            </div>
            <div class="card">
                <h3>Total Checks</h3>
                <div class="value">${TOTAL_COUNT}</div>
            </div>
            <div class="card passed">
                <h3>Passed</h3>
                <div class="value">${PASS_COUNT}</div>
            </div>
            <div class="card failed">
                <h3>Failed</h3>
                <div class="value">${FAIL_COUNT}</div>
            </div>
            <div class="card skipped">
                <h3>Skipped</h3>
                <div class="value">${SKIP_COUNT}</div>
            </div>
        </div>
        
        <h2>Scan Information</h2>
        <table>
            <tr><th>Property</th><th>Value</th></tr>
            <tr><td>Hostname</td><td>$(hostname)</td></tr>
            <tr><td>Timestamp</td><td>$(date)</td></tr>
            <tr><td>OS</td><td>$(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)</td></tr>
            <tr><td>Rating</td><td><strong>$([[ $score_percent -ge 90 ]] && echo "🟢 EXCELLENT" || ([[ $score_percent -ge 70 ]] && echo "🟡 GOOD" || ([[ $score_percent -ge 50 ]] && echo "🟠 FAIR" || echo "🔴 POOR")))</strong></td></tr>
        </table>
        
        <div class="footer">
            Generated by CIS Benchmark Script v2.0.0 for XDC Nodes
        </div>
    </div>
</body>
</html>
EOF
    echo -e "${GREEN}HTML report saved to: $output_file${NC}"
}

print_summary() {
    local score_percent=0
    if [[ $MAX_SCORE -gt 0 ]]; then
        score_percent=$((TOTAL_SCORE * 100 / MAX_SCORE))
    fi
    
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    CIS Benchmark Summary                       ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "  Total Checks:    ${TOTAL_COUNT}"
    echo -e "  ${GREEN}Passed:${NC}          ${PASS_COUNT}"
    echo -e "  ${RED}Failed:${NC}          ${FAIL_COUNT}"
    echo -e "  ${YELLOW}Skipped:${NC}         ${SKIP_COUNT}"
    echo -e "  Score:           ${TOTAL_SCORE}/${MAX_SCORE} (${score_percent}%)"
    
    echo -e "\n  Rating: $([[ $score_percent -ge 90 ]] && echo "${GREEN}🟢 EXCELLENT${NC}" || ([[ $score_percent -ge 70 ]] && echo "${YELLOW}🟡 GOOD${NC}" || ([[ $score_percent -ge 50 ]] && echo "${RED}🟠 FAIR${NC}" || echo "${RED}🔴 POOR${NC}")))"
    
    echo -e "\n  Score Interpretation:"
    echo -e "    ${GREEN}90-100${NC} - Excellent (Production Ready)"
    echo -e "    ${YELLOW}70-89${NC}  - Good (Minor improvements needed)"
    echo -e "    ${RED}50-69${NC}  - Fair (Significant gaps)"
    echo -e "    ${RED}<50${NC}    - Poor (Not suitable for production)"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
}

#===============================================================================
# Main
#===============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --remediate)
                REMEDIATE=true
                shift
                ;;
            --category)
                CATEGORY="$2"
                shift 2
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --html)
                HTML_OUTPUT=true
                shift
                ;;
            --output)
                REPORT_FILE="$2"
                shift 2
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done
    
    # Check if running as root for remediation
    if [[ "$REMEDIATE" == "true" && $EUID -ne 0 ]]; then
        echo "Error: Remediation requires root privileges"
        exit 1
    fi
    
    [[ "$QUIET" == "false" ]] && echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    [[ "$QUIET" == "false" ]] && echo -e "${CYAN}║         CIS Benchmark Security Audit for XDC Nodes             ║${NC}"
    [[ "$QUIET" == "false" ]] && echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    [[ "$QUIET" == "false" ]] && echo ""
    
    if [[ "$REMEDIATE" == "true" ]]; then
        [[ "$QUIET" == "false" ]] && echo -e "${YELLOW}⚠️  REMEDIATION MODE ENABLED - Issues will be auto-fixed${NC}\n"
    fi
    
    # Run checks based on category filter
    if [[ -z "$CATEGORY" || "$CATEGORY" == "filesystem" ]]; then
        check_filesystem
    fi
    
    if [[ -z "$CATEGORY" || "$CATEGORY" == "services" ]]; then
        check_services
    fi
    
    if [[ -z "$CATEGORY" || "$CATEGORY" == "network" ]]; then
        check_network
    fi
    
    if [[ -z "$CATEGORY" || "$CATEGORY" == "logging" ]]; then
        check_logging
    fi
    
    if [[ -z "$CATEGORY" || "$CATEGORY" == "auth" ]]; then
        check_auth
    fi
    
    if [[ -z "$CATEGORY" || "$CATEGORY" == "permissions" ]]; then
        check_permissions
    fi
    
    # Generate reports
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        generate_json_report
    fi
    
    if [[ "$HTML_OUTPUT" == "true" ]]; then
        generate_html_report
    fi
    
    # Print summary to console
    print_summary
    
    # Exit with appropriate code
    if [[ $FAIL_COUNT -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
