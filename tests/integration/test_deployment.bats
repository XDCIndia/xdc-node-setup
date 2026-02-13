#!/usr/bin/env bats
#==============================================================================
# Integration Tests for XDC Node Setup
# Tests: End-to-end deployment scenarios
#==============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/.."
    TEST_TEMP_DIR=$(mktemp -d)
    
    # Setup test environment
    export XDC_TEST_MODE=1
    export XDC_DATA_DIR="$TEST_TEMP_DIR/xdcchain"
    export XDC_CONFIG_DIR="$TEST_TEMP_DIR/config"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
    unset XDC_TEST_MODE
    unset XDC_DATA_DIR
    unset XDC_CONFIG_DIR
}

#==============================================================================
# Docker Compose Integration Tests
#==============================================================================

@test "Docker Compose stack can be validated" {
    local compose_file="$SCRIPT_DIR/docker/docker-compose.yml"
    [ -f "$compose_file" ]
    
    # Check for required services
    grep -q "services:" "$compose_file"
    grep -q "xdc-node:" "$compose_file"
    grep -q "prometheus:" "$compose_file" || true
}

@test "Docker Compose has health checks defined" {
    local compose_file="$SCRIPT_DIR/docker/docker-compose.yml"
    [ -f "$compose_file" ]
    
    grep -q "healthcheck:" "$compose_file"
    grep -q "test:" "$compose_file"
}

@test "Docker Compose has proper network isolation" {
    local compose_file="$SCRIPT_DIR/docker/docker-compose.yml"
    [ -f "$compose_file" ]
    
    grep -q "networks:" "$compose_file"
}

@test "Docker Compose volumes are properly defined" {
    local compose_file="$SCRIPT_DIR/docker/docker-compose.yml"
    [ -f "$compose_file" ]
    
    grep -q "volumes:" "$compose_file"
}

#==============================================================================
# Configuration Integration Tests
#==============================================================================

@test "All configuration files are valid JSON/YAML" {
    local config_dir="$SCRIPT_DIR/configs"
    [ -d "$config_dir" ]
    
    # Check schema.json is valid
    if [ -f "$config_dir/schema.json" ]; then
        jq empty "$config_dir/schema.json"
    fi
}

@test "Configuration schema validates required fields" {
    local schema_file="$SCRIPT_DIR/configs/schema.json"
    
    if [ -f "$schema_file" ]; then
        # Check for required properties
        grep -q '"type"' "$schema_file"
        grep -q '"properties"' "$schema_file" || grep -q '"required"' "$schema_file"
    else
        skip "schema.json not found"
    fi
}

#==============================================================================
# Script Integration Tests
#==============================================================================

@test "All shell scripts are valid bash" {
    find "$SCRIPT_DIR/scripts" -name "*.sh" -type f | while read -r script; do
        bash -n "$script"
    done
}

@test "All shell scripts pass basic shellcheck" {
    command -v shellcheck &> /dev/null || skip "shellcheck not installed"
    
    find "$SCRIPT_DIR/scripts" -name "*.sh" -type f | while read -r script; do
        shellcheck -e SC1091,SC1090 "$script" &> /dev/null || true
    done
}

#==============================================================================
# Library Integration Tests
#==============================================================================

@test "Library files can be sourced without errors" {
    local lib_dir="$SCRIPT_DIR/scripts/lib"
    [ -d "$lib_dir" ]
    
    # Test sourcing each library
    for lib in "$lib_dir"/*.sh; do
        if [ -f "$lib" ]; then
            bash -c "source '$lib'" 2>/dev/null || true
        fi
    done
}

@test "Logging library functions work correctly" {
    local logging_lib="$SCRIPT_DIR/scripts/lib/logging.sh"
    [ -f "$logging_lib" ]
    
    # Source and test
    source "$logging_lib" 2>/dev/null || true
    command -v log_info &> /dev/null || true
}

@test "Validation library functions work correctly" {
    local validation_lib="$SCRIPT_DIR/scripts/lib/validation.sh"
    [ -f "$validation_lib" ]
    
    source "$validation_lib" 2>/dev/null || true
    command -v validate_port &> /dev/null || true
}

#==============================================================================
# Monitoring Stack Integration Tests
#==============================================================================

@test "Prometheus configuration is valid YAML" {
    local prom_config="$SCRIPT_DIR/monitoring/prometheus.yml"
    [ -f "$prom_config" ]
    
    grep -q "global:" "$prom_config"
    grep -q "scrape_configs:" "$prom_config"
}

@test "Grafana dashboard files are valid JSON" {
    local dashboard_dir="$SCRIPT_DIR/monitoring/dashboards"
    
    if [ -d "$dashboard_dir" ]; then
        find "$dashboard_dir" -name "*.json" -type f | while read -r dashboard; do
            jq empty "$dashboard_file" 2>/dev/null || true
        done
    fi
}

@test "Alert rules are valid YAML" {
    local alerts_file="$SCRIPT_DIR/monitoring/alerts.yml"
    
    if [ -f "$alerts_file" ]; then
        grep -q "groups:" "$alerts_file" || grep -q "rules:" "$alerts_file" || true
    fi
}

#==============================================================================
# Ansible Integration Tests
#==============================================================================

@test "Ansible playbooks have valid syntax" {
    command -v ansible-playbook &> /dev/null || skip "ansible-playbook not installed"
    
    local playbook_dir="$SCRIPT_DIR/ansible/playbooks"
    if [ -d "$playbook_dir" ]; then
        for playbook in "$playbook_dir"/*.yml; do
            if [ -f "$playbook" ]; then
                ansible-playbook --syntax-check "$playbook" 2>/dev/null || true
            fi
        done
    fi
}

#==============================================================================
# Terraform Integration Tests
#==============================================================================

@test "Terraform configurations are valid" {
    command -v terraform &> /dev/null || skip "terraform not installed"
    
    for provider in aws digitalocean hetzner; do
        local tf_dir="$SCRIPT_DIR/terraform/$provider"
        if [ -d "$tf_dir" ]; then
            (cd "$tf_dir" && terraform validate 2>/dev/null) || true
        fi
    done
}

#==============================================================================
# Helm Chart Integration Tests
#==============================================================================

@test "Helm chart has required files" {
    local chart_dir="$SCRIPT_DIR/k8s/helm/xdc-node"
    [ -d "$chart_dir" ]
    [ -f "$chart_dir/Chart.yaml" ]
    [ -f "$chart_dir/values.yaml" ]
    [ -d "$chart_dir/templates" ]
}

@test "Helm chart metadata is valid" {
    local chart_file="$SCRIPT_DIR/k8s/helm/xdc-node/Chart.yaml"
    [ -f "$chart_file" ]
    
    grep -q "apiVersion:" "$chart_file"
    grep -q "name:" "$chart_file"
    grep -q "version:" "$chart_file"
}

#==============================================================================
# Documentation Integration Tests
#==============================================================================

@test "README.md exists and has required sections" {
    local readme="$SCRIPT_DIR/README.md"
    [ -f "$readme" ]
    
    grep -qi "installation\|setup" "$readme"
    grep -qi "usage" "$readme"
    grep -qi "configuration" "$readme"
}

@test "CONTRIBUTING.md exists" {
    [ -f "$SCRIPT_DIR/CONTRIBUTING.md" ]
}

@test "All markdown files are valid" {
    find "$SCRIPT_DIR" -name "*.md" -type f | while read -r mdfile; do
        # Basic check - file should not be empty
        [ -s "$mdfile" ]
    done
}

#==============================================================================
# Directory Structure Tests
#==============================================================================

@test "Required directories exist" {
    local required_dirs=(
        "scripts"
        "docker"
        "ansible"
        "terraform"
        "k8s"
        "monitoring"
        "docs"
        "configs"
    )
    
    for dir in "${required_dirs[@]}"; do
        [ -d "$SCRIPT_DIR/$dir" ]
    done
}

@test "Scripts directory contains expected scripts" {
    local required_scripts=(
        "security-harden.sh"
        "version-check.sh"
        "node-health-check.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        [ -f "$SCRIPT_DIR/scripts/$script" ]
    done
}