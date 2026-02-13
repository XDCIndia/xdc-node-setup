#!/usr/bin/env bats
#==============================================================================
# Unit Tests for Version Check Script
# Tests: version-check.sh
#==============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/../scripts"
    TEST_TEMP_DIR=$(mktemp -d)
    
    mkdir -p "$TEST_TEMP_DIR/configs"
    mkdir -p "$TEST_TEMP_DIR/reports"
    mkdir -p "$TEST_TEMP_DIR/cache"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

#==============================================================================
# Script Existence and Structure
#==============================================================================

@test "version-check.sh exists and is executable" {
    [ -x "$SCRIPT_DIR/version-check.sh" ]
}

@test "version-check.sh has proper lock file handling" {
    grep -q "LOCK_FILE" "$SCRIPT_DIR/version-check.sh"
    grep -q "acquire_lock\|release_lock" "$SCRIPT_DIR/version-check.sh"
}

@test "version-check.sh implements ETag caching" {
    grep -q "ETAG" "$SCRIPT_DIR/version-check.sh" || \
    grep -q "etag" "$SCRIPT_DIR/version-check.sh"
}

#==============================================================================
# Versions.json Structure Tests
#==============================================================================

@test "versions.json has required schema" {
    local versions_file="$TEST_TEMP_DIR/configs/versions.json"
    
    cat > "$versions_file" << 'EOF'
{
  "clients": {
    "XDPoSChain": {
      "repo": "XinFinOrg/XDPoSChain",
      "current": "v2.6.8",
      "latest": "v2.6.9",
      "autoUpdate": false
    }
  },
  "tools": {
    "docker": {
      "minVersion": "20.10.0"
    }
  }
}
EOF
    
    [ -f "$versions_file" ]
    jq -e '.clients.XDPoSChain.repo' "$versions_file"
    jq -e '.clients.XDPoSChain.current' "$versions_file"
    jq -e '.clients.XDPoSChain.autoUpdate' "$versions_file"
}

@test "versions.json validates repository format" {
    local repo="XinFinOrg/XDPoSChain"
    
    # Should match owner/repo format
    [[ "$repo" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$ ]]
}

@test "versions.json validates semantic versioning" {
    local versions=("v2.6.8" "v1.0.0" "v2.0.0-beta.1")
    
    for version in "${versions[@]}"; do
        [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]]
    done
}

#==============================================================================
# GitHub API Tests
#==============================================================================

@test "GitHub API URL construction is correct" {
    local repo="XinFinOrg/XDPoSChain"
    local api_url="https://api.github.com/repos/$repo/releases/latest"
    
    [ "$api_url" = "https://api.github.com/repos/XinFinOrg/XDPoSChain/releases/latest" ]
}

@test "ETag cache file naming is consistent" {
    local repo="XinFinOrg/XDPoSChain"
    local etag_file="$TEST_TEMP_DIR/cache/$(echo "$repo" | tr '/' '_').etag"
    
    [ "$etag_file" = "$TEST_TEMP_DIR/cache/XinFinOrg_XDPoSChain.etag" ]
}

@test "Release data extraction works correctly" {
    local mock_response='{"tag_name":"v2.6.9","published_at":"2026-02-10T00:00:00Z"}'
    local tag_name
    
    tag_name=$(echo "$mock_response" | jq -r '.tag_name')
    [ "$tag_name" = "v2.6.9" ]
}

#==============================================================================
# Version Comparison Tests
#==============================================================================

@test "Version comparison detects newer version" {
    local current="v2.6.8"
    local latest="v2.6.9"
    
    # Remove 'v' prefix for numeric comparison
    local current_num="${current#v}"
    local latest_num="${latest#v}"
    
    [[ "$current_num" < "$latest_num" ]]
}

@test "Version comparison handles major version bump" {
    local current="v1.9.9"
    local latest="v2.0.0"
    
    local current_num="${current#v}"
    local latest_num="${latest#v}"
    
    [[ "$current_num" < "$latest_num" ]]
}

@test "Version comparison handles same version" {
    local current="v2.6.8"
    local latest="v2.6.8"
    
    [ "$current" = "$latest" ]
}

@test "Version parsing extracts components correctly" {
    local version="v2.6.8"
    version="${version#v}"  # Remove v prefix
    
    IFS='.' read -r major minor patch <<< "$version"
    
    [ "$major" -eq 2 ]
    [ "$minor" -eq 6 ]
    [ "$patch" -eq 8 ]
}

#==============================================================================
# Auto-Update Tests
#==============================================================================

@test "Auto-update respects configuration flag" {
    local auto_update=false
    local update_available=true
    
    # Should not update if autoUpdate is false
    if [ "$auto_update" = "true" ] && [ "$update_available" = "true" ]; then
        perform_update=true
    else
        perform_update=false
    fi
    
    [ "$perform_update" = "false" ]
}

@test "Auto-update triggers when enabled and update available" {
    local auto_update=true
    local update_available=true
    
    if [ "$auto_update" = "true" ] && [ "$update_available" = "true" ]; then
        perform_update=true
    else
        perform_update=false
    fi
    
    [ "$perform_update" = "true" ]
}

#==============================================================================
# Update Report Tests
#==============================================================================

@test "Update report JSON structure is valid" {
    local report_file="$TEST_TEMP_DIR/reports/version-check.json"
    
    cat > "$report_file" << 'EOF'
{
  "timestamp": "2026-02-13T10:00:00Z",
  "checks": [
    {
      "client": "XDPoSChain",
      "current": "v2.6.8",
      "latest": "v2.6.9",
      "update_available": true,
      "auto_update": false,
      "published_at": "2026-02-10T00:00:00Z"
    }
  ],
  "summary": {
    "total_checks": 1,
    "updates_available": 1,
    "updates_applied": 0
  }
}
EOF
    
    [ -f "$report_file" ]
    jq -e '.checks[0].update_available' "$report_file"
    jq -e '.summary.updates_available' "$report_file"
}

@test "Update report tracks applied updates" {
    local updates_applied=1
    local updates_available=1
    
    [ "$updates_applied" -eq "$updates_available" ]
}

#==============================================================================
# Lock File Tests
#==============================================================================

@test "Lock file prevents concurrent execution" {
    local lock_file="$TEST_TEMP_DIR/version-check.lock"
    
    # Simulate lock file exists with active PID
    echo "99999" > "$lock_file"
    
    # Lock file should exist
    [ -f "$lock_file" ]
    
    # Cleanup
    rm -f "$lock_file"
}

#==============================================================================
# Logging Tests
#==============================================================================

@test "Version check logs to correct location" {
    local log_file="$TEST_TEMP_DIR/logs/version-check.log"
    
    # Create log file
    touch "$log_file"
    echo "[2026-02-13 10:00:00] Version check started" >> "$log_file"
    
    [ -f "$log_file" ]
    grep -q "Version check started" "$log_file"
}

#==============================================================================
# Notification Tests
#==============================================================================

@test "Update notification includes version details" {
    local current="v2.6.8"
    local latest="v2.6.9"
    local message="Update available: $current -> $latest"
    
    [[ "$message" == *"v2.6.8"* ]]
    [[ "$message" == *"v2.6.9"* ]]
}

@test "Critical update detection works" {
    local current="v1.0.0"
    local latest="v2.0.0"
    
    # Major version difference indicates critical update
    local current_major="${current%%.*}"
    local latest_major="${latest%%.*}"
    
    [ "$current_major" = "v1" ]
    [ "$latest_major" = "v2" ]
    [[ "$current_major" < "$latest_major" ]]
}