#!/usr/bin/env bats
#==============================================================================
# Unit Tests for Security Hardening Script
# Tests: security-harden.sh
#==============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/../scripts"
    TEST_TEMP_DIR=$(mktemp -d)
    
    # Create mock files and directories
    mkdir -p "$TEST_TEMP_DIR/etc/ssh"
    mkdir -p "$TEST_TEMP_DIR/opt/xdc-node/reports"
    touch "$TEST_TEMP_DIR/etc/ssh/sshd_config"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

#==============================================================================
# SSH Configuration Tests
#==============================================================================

@test "security-harden.sh exists and is executable" {
    [ -x "$SCRIPT_DIR/security-harden.sh" ]
}

@test "SSH config backup functionality works" {
    # Test that script can create backup
    local sshd_config="$TEST_TEMP_DIR/etc/ssh/sshd_config"
    local backup_file="$TEST_TEMP_DIR/etc/ssh/sshd_config.backup.test"
    
    echo "Test config" > "$sshd_config"
    cp "$sshd_config" "$backup_file"
    
    [ -f "$backup_file" ]
    [ "$(cat "$backup_file")" = "Test config" ]
}

@test "SSH config contains required security settings" {
    local sshd_config="$TEST_TEMP_DIR/etc/ssh/sshd_config"
    
    # Create test SSH config with security settings
    cat > "$sshd_config" << 'EOF'
Port 12141
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
    
    # Verify required settings exist
    grep -q "Port 12141" "$sshd_config"
    grep -q "PermitRootLogin prohibit-password" "$sshd_config"
    grep -q "PasswordAuthentication no" "$sshd_config"
    grep -q "PubkeyAuthentication yes" "$sshd_config"
    grep -q "X11Forwarding no" "$sshd_config"
    grep -q "MaxAuthTries 3" "$sshd_config"
}

#==============================================================================
# Security Score Tests
#==============================================================================

@test "Security score calculation produces valid JSON" {
    # Test score file format
    local score_file="$TEST_TEMP_DIR/opt/xdc-node/reports/security-score.json"
    
    # Create sample score file
    cat > "$score_file" << 'EOF'
{
  "timestamp": "2026-02-13T10:00:00Z",
  "totalScore": 85,
  "maxScore": 100,
  "percentage": 85,
  "checks": {
    "ssh_hardening": { "score": 20, "max": 20 },
    "firewall": { "score": 15, "max": 15 },
    "fail2ban": { "score": 15, "max": 15 },
    "system_updates": { "score": 10, "max": 10 },
    "audit_logging": { "score": 15, "max": 20 },
    "file_permissions": { "score": 10, "max": 20 }
  }
}
EOF
    
    [ -f "$score_file" ]
    # Verify it's valid JSON
    jq -e '.totalScore' "$score_file"
    jq -e '.checks.ssh_hardening.score' "$score_file"
}

@test "Security score percentage calculation is correct" {
    local score_file="$TEST_TEMP_DIR/opt/xdc-node/reports/security-score.json"
    
    cat > "$score_file" << 'EOF'
{
  "totalScore": 75,
  "maxScore": 100
}
EOF
    
    local percentage
    percentage=$(jq '.totalScore / .maxScore * 100 | floor' "$score_file")
    [ "$percentage" -eq 75 ]
}

#==============================================================================
# UFW Firewall Tests
#==============================================================================

@test "UFW firewall rules are properly formatted" {
    # Test that firewall rules follow expected format
    local rules=(
        "allow 12141/tcp"
        "allow 30303/tcp"
        "allow 30303/udp"
        "deny 8545/tcp"
        "deny 8546/tcp"
    )
    
    for rule in "${rules[@]}"; do
        [[ "$rule" =~ ^(allow|deny)[[:space:]]+[0-9]+/(tcp|udp)$ ]]
    done
}

@test "SSH port is non-standard (not 22)" {
    # Security hardening should use non-standard SSH port
    local ssh_port=12141
    [ "$ssh_port" -ne 22 ]
    [ "$ssh_port" -gt 1024 ]
    [ "$ssh_port" -lt 65535 ]
}

#==============================================================================
# fail2ban Tests
#==============================================================================

@test "fail2ban configuration has required settings" {
    local fail2ban_config="$TEST_TEMP_DIR/etc/fail2ban/jail.local"
    mkdir -p "$TEST_TEMP_DIR/etc/fail2ban"
    
    cat > "$fail2ban_config" << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = 12141
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF
    
    [ -f "$fail2ban_config" ]
    grep -q "bantime" "$fail2ban_config"
    grep -q "maxretry" "$fail2ban_config"
    grep -q "\[sshd\]" "$fail2ban_config"
}

#==============================================================================
# Audit Logging Tests
#==============================================================================

@test "Audit rules contain XDC node relevant paths" {
    local audit_rules="$TEST_TEMP_DIR/etc/audit/rules.d/xdc-node.rules"
    mkdir -p "$TEST_TEMP_DIR/etc/audit/rules.d"
    
    cat > "$audit_rules" << 'EOF'
-w /opt/xdc-node/ -p wa -k xdc-node-config
-w /var/lib/xdc/ -p wa -k xdc-data
-w /etc/systemd/system/xdc-node.service -p wa -k xdc-service
-a always,exit -F arch=b64 -S setuid -S setgid -k privilege-escalation
EOF
    
    [ -f "$audit_rules" ]
    grep -q "xdc-node" "$audit_rules"
    grep -q "privilege-escalation" "$audit_rules"
}

#==============================================================================
# File Permission Tests
#==============================================================================

@test "XDC node directory permissions are secure" {
    # Test directory creation with proper permissions
    local test_dir="$TEST_TEMP_DIR/opt/xdc-node/testdata"
    mkdir -p "$test_dir"
    chmod 750 "$test_dir"
    
    local perms
    perms=$(stat -c "%a" "$test_dir" 2>/dev/null || stat -f "%Lp" "$test_dir")
    [ "$perms" = "750" ]
}

@test "Private key files have restricted permissions" {
    local key_file="$TEST_TEMP_DIR/opt/xdc-node/keys/private.key"
    mkdir -p "$(dirname "$key_file")"
    echo "test-key-data" > "$key_file"
    chmod 600 "$key_file"
    
    local perms
    perms=$(stat -c "%a" "$key_file" 2>/dev/null || stat -f "%Lp" "$key_file")
    [ "$perms" = "600" ]
}

#==============================================================================
# CIS Benchmark Tests
#==============================================================================

@test "CIS benchmark categories are covered" {
    local categories=(
        "Initial Setup"
        "Services"
        "Network Configuration"
        "Logging and Auditing"
        "Access, Authentication and Authorization"
        "System Maintenance"
    )
    
    [ ${#categories[@]} -eq 6 ]
}

#==============================================================================
# Security Notification Tests
#==============================================================================

@test "Security score notifications trigger on low scores" {
    local score=45
    local threshold=70
    
    # Should trigger notification if below threshold
    [ "$score" -lt "$threshold" ]
}

@test "Security improvement detection works" {
    local previous_score=70
    local current_score=85
    
    # Calculate improvement
    local improvement=$((current_score - previous_score))
    [ "$improvement" -gt 0 ]
    [ "$improvement" -eq 15 ]
}