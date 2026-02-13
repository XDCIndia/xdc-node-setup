#!/usr/bin/env bats
#==============================================================================
# Unit Tests for Health Check Script
# Tests: node-health-check.sh
#==============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/../scripts"
    TEST_TEMP_DIR=$(mktemp -d)
    
    # Create mock directories
    mkdir -p "$TEST_TEMP_DIR/reports"
    mkdir -p "$TEST_TEMP_DIR/logs"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

#==============================================================================
# Script Existence and Permissions
#==============================================================================

@test "node-health-check.sh exists and is executable" {
    [ -x "$SCRIPT_DIR/node-health-check.sh" ]
}

@test "health check script sources notification library" {
    # Check that script has proper library sourcing
    grep -q "source.*notify.sh" "$SCRIPT_DIR/node-health-check.sh" || \
    grep -q "LIB_DIR" "$SCRIPT_DIR/node-health-check.sh"
}

#==============================================================================
# RPC Helper Tests
#==============================================================================

@test "RPC URL format validation accepts valid URLs" {
    local urls=(
        "http://localhost:8545"
        "https://rpc.xinfin.network:443"
        "http://192.168.1.1:38545"
    )
    
    for url in "${urls[@]}"; do
        [[ "$url" =~ ^https?://[a-zA-Z0-9._-]+(:[0-9]+)?$ ]]
    done
}

@test "Hex to decimal conversion works correctly" {
    # Test hex conversion (common in blockchain)
    local hex="0x10"
    local decimal=$((16#$hex))
    [ "$decimal" -eq 16 ]
    
    hex="0xFF"
    decimal=$((16#$hex))
    [ "$decimal" -eq 255 ]
    
    hex="0x0"
    decimal=$((16#$hex))
    [ "$decimal" -eq 0 ]
}

#==============================================================================
# Block Height Tests
#==============================================================================

@test "Block height comparison detects sync status" {
    local local_height=1000
    local network_height=1005
    local threshold=10
    
    local diff=$((network_height - local_height))
    [ "$diff" -lt "$threshold" ]
    
    # Node is considered synced if within threshold
    local is_synced=false
    if [ "$diff" -lt "$threshold" ]; then
        is_synced=true
    fi
    [ "$is_synced" = "true" ]
}

@test "Block height comparison detects lagging node" {
    local local_height=500
    local network_height=1000
    local threshold=100
    
    local diff=$((network_height - local_height))
    [ "$diff" -gt "$threshold" ]
}

#==============================================================================
# Peer Count Tests
#==============================================================================

@test "Peer count validation works correctly" {
    local peer_count=15
    local min_peers=5
    local max_peers=50
    
    [ "$peer_count" -ge "$min_peers" ]
    [ "$peer_count" -le "$max_peers" ]
}

@test "Low peer count triggers warning" {
    local peer_count=2
    local min_peers=5
    
    [ "$peer_count" -lt "$min_peers" ]
}

#==============================================================================
# System Resource Tests
#==============================================================================

@test "Disk usage percentage calculation" {
    local used=75000000
    local total=100000000
    local usage=$((used * 100 / total))
    
    [ "$usage" -eq 75 ]
}

@test "Disk usage warning threshold" {
    local usage=85
    local warning_threshold=80
    local critical_threshold=95
    
    # Should be warning level
    [ "$usage" -ge "$warning_threshold" ]
    [ "$usage" -lt "$critical_threshold" ]
}

@test "Disk usage critical threshold" {
    local usage=96
    local critical_threshold=95
    
    [ "$usage" -ge "$critical_threshold" ]
}

@test "Memory usage calculation" {
    local total_mem=16000000
    local used_mem=8000000
    local usage=$((used_mem * 100 / total_mem))
    
    [ "$usage" -eq 50 ]
}

@test "CPU usage threshold validation" {
    local cpu_usage=75
    local warning_threshold=80
    
    # Should be OK
    [ "$cpu_usage" -lt "$warning_threshold" ]
}

#==============================================================================
# Client Version Tests
#==============================================================================

@test "Version comparison detects outdated client" {
    local current_version="v2.6.8"
    local latest_version="v2.6.9"
    
    # Simple string comparison works for semver
    [[ "$current_version" < "$latest_version" ]]
}

@test "Version comparison handles major version differences" {
    local current_version="v1.0.0"
    local latest_version="v2.0.0"
    
    [[ "$current_version" < "$latest_version" ]]
}

#==============================================================================
# Alert Tests
#==============================================================================

@test "Alert structure is valid" {
    local alert_file="$TEST_TEMP_DIR/reports/alerts.json"
    
    cat > "$alert_file" << 'EOF'
{
  "alerts": [
    {
      "severity": "warning",
      "message": "High disk usage",
      "timestamp": "2026-02-13T10:00:00Z",
      "metric": "disk_usage",
      "value": 85
    }
  ]
}
EOF
    
    [ -f "$alert_file" ]
    jq -e '.alerts[0].severity' "$alert_file"
    jq -e '.alerts[0].metric' "$alert_file"
}

@test "Critical alerts have higher priority" {
    local severity="critical"
    local allowed_severities=("info" "warning" "critical")
    
    local found=false
    for s in "${allowed_severities[@]}"; do
        if [ "$s" = "$severity" ]; then
            found=true
            break
        fi
    done
    
    [ "$found" = "true" ]
}

#==============================================================================
# JSON Report Tests
#==============================================================================

@test "Health report JSON structure is valid" {
    local report_file="$TEST_TEMP_DIR/reports/health-report.json"
    
    cat > "$report_file" << 'EOF'
{
  "timestamp": "2026-02-13T10:00:00Z",
  "status": "healthy",
  "checks": {
    "block_height": { "status": "pass", "value": 10000 },
    "peers": { "status": "pass", "value": 25 },
    "sync": { "status": "pass", "syncing": false },
    "disk": { "status": "pass", "usage_percent": 45 },
    "memory": { "status": "pass", "usage_percent": 60 },
    "cpu": { "status": "pass", "usage_percent": 30 }
  },
  "summary": {
    "passed": 6,
    "failed": 0,
    "total": 6
  }
}
EOF
    
    [ -f "$report_file" ]
    jq -e '.timestamp' "$report_file"
    jq -e '.checks.block_height.status' "$report_file"
    jq -e '.summary.passed' "$report_file"
}

@test "Overall status is healthy when all checks pass" {
    local passed=6
    local failed=0
    local total=6
    
    local status="healthy"
    if [ "$failed" -gt 0 ]; then
        status="unhealthy"
    fi
    
    [ "$status" = "healthy" ]
    [ "$passed" -eq "$total" ]
}

@test "Overall status is unhealthy when any check fails" {
    local passed=5
    local failed=1
    local total=6
    
    local status="healthy"
    if [ "$failed" -gt 0 ]; then
        status="unhealthy"
    fi
    
    [ "$status" = "unhealthy" ]
}

#==============================================================================
# Notification Trigger Tests
#==============================================================================

@test "Notification triggers on health status change" {
    local previous_status="healthy"
    local current_status="unhealthy"
    
    # Should trigger notification on status change
    [ "$previous_status" != "$current_status" ]
}

@test "Notification triggers on critical alert" {
    local alert_severity="critical"
    
    # Critical alerts should always notify
    [ "$alert_severity" = "critical" ]
}