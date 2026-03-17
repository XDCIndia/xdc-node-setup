#!/usr/bin/env bash
#==============================================================================
# Platform Detection Library (Issue #555, #556, #148, #306)
# Cross-platform support for macOS, Linux, ARM64, x86_64
#==============================================================================

# Detect OS
detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "macos" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)       echo "unknown" ;;
    esac
}

# Detect architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)   echo "amd64" ;;
        aarch64|arm64)  echo "arm64" ;;
        armv7l|armhf)   echo "armv7" ;;
        *)              echo "$(uname -m)" ;;
    esac
}

# Issue #555: Get CPU count (works on both Linux and macOS)
get_cpu_count() {
    if [[ "$(detect_os)" == "macos" ]]; then
        sysctl -n hw.ncpu 2>/dev/null || echo "1"
    elif [[ -f /proc/cpuinfo ]]; then
        grep -c '^processor' /proc/cpuinfo 2>/dev/null || nproc 2>/dev/null || echo "1"
    else
        nproc 2>/dev/null || echo "1"
    fi
}

# Issue #555: Get total memory in bytes (works on both Linux and macOS)
get_memory_bytes() {
    if [[ "$(detect_os)" == "macos" ]]; then
        sysctl -n hw.memsize 2>/dev/null || echo "0"
    elif [[ -f /proc/meminfo ]]; then
        awk '/MemTotal/ {print $2 * 1024}' /proc/meminfo 2>/dev/null || echo "0"
    else
        free -b 2>/dev/null | awk '/Mem:/ {print $2}' || echo "0"
    fi
}

# Get memory in human-readable format
get_memory_human() {
    local bytes
    bytes=$(get_memory_bytes)
    if [[ "$bytes" -gt 0 ]]; then
        echo "$((bytes / 1024 / 1024 / 1024))GB"
    else
        echo "unknown"
    fi
}

# Issue #555: Get disk usage (works on both Linux and macOS)
get_disk_usage() {
    local path="${1:-/}"
    if [[ "$(detect_os)" == "macos" ]]; then
        df -h "$path" 2>/dev/null | awk 'NR==2 {print $4 " free (" $5 " used)"}'
    else
        df -h "$path" 2>/dev/null | awk 'NR==2 {print $4 " free (" $5 " used)"}'
    fi
}

# Issue #556: Get docker platform flag for ARM64
get_docker_platform() {
    local arch
    arch=$(detect_arch)
    case "$arch" in
        arm64) echo "linux/amd64" ;;  # XDC images are x86 only
        *)     echo "" ;;  # No platform override needed
    esac
}

# Issue #556: Add platform to docker-compose if needed
inject_docker_platform() {
    local compose_file="$1"
    local arch
    arch=$(detect_arch)
    
    if [[ "$arch" == "arm64" ]]; then
        # Check if platform already set
        if ! grep -q "platform:" "$compose_file" 2>/dev/null; then
            echo "⚠️  ARM64 detected. XDC Docker images require x86 emulation."
            echo "   Adding 'platform: linux/amd64' to compose services..."
            
            # Use sed to add platform after each 'image:' line
            if [[ "$(detect_os)" == "macos" ]]; then
                sed -i '' '/^\s*image:/a\
    platform: linux/amd64' "$compose_file"
            else
                sed -i '/^\s*image:/a\    platform: linux/amd64' "$compose_file"
            fi
            echo "✅ Platform override added to $compose_file"
        fi
    fi
}

# Issue #555: Get load average (cross-platform)
get_load_average() {
    if [[ "$(detect_os)" == "macos" ]]; then
        sysctl -n vm.loadavg 2>/dev/null | awk '{print $2, $3, $4}' || echo "0 0 0"
    elif [[ -f /proc/loadavg ]]; then
        awk '{print $1, $2, $3}' /proc/loadavg
    else
        uptime | awk -F'load average:' '{print $2}' | tr -d ' '
    fi
}

# Docker compose command (v1 vs v2)
docker_compose_cmd() {
    if command -v "docker-compose" >/dev/null 2>&1; then
        echo "docker-compose"
    elif docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    else
        echo ""
    fi
}

# Print platform info summary
platform_info() {
    echo "Platform: $(detect_os)/$(detect_arch)"
    echo "CPU: $(get_cpu_count) cores"
    echo "Memory: $(get_memory_human)"
    echo "Disk: $(get_disk_usage /)"
    echo "Docker: $(docker_compose_cmd 2>/dev/null || echo 'not found')"
    
    local platform
    platform=$(get_docker_platform)
    if [[ -n "$platform" ]]; then
        echo "⚠️  ARM64: Docker images need platform: $platform"
    fi
}

# Auto-print if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    platform_info
fi
