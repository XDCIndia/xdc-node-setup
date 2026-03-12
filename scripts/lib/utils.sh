#!/bin/bash
#===============================================================================
# Cross-Platform Utilities Library for XDC Node Setup
# Provides portable alternatives to GNU/BSD specific commands
# Supports: Linux (GNU), macOS (BSD), WSL2
#===============================================================================

# Prevent multiple sourcing
[[ -n "${XDC_UTILS_SOURCED:-}" ]] && return 0
XDC_UTILS_SOURCED=1

#==============================================================================
# OS Detection
#==============================================================================
detect_os() {
    case "$(uname -s)" in
        Linux*)     
            if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl2"
            else
                echo "linux"
            fi
            ;;
        Darwin*)    echo "macos";;
        MINGW*|CYGWIN*|MSYS*) echo "windows";;
        *)          echo "unknown";;
    esac
}

readonly OS=$(detect_os)

is_macos() { [[ "$OS" == "macos" ]]; }
is_linux() { [[ "$OS" == "linux" ]]; }
is_wsl2() { [[ "$OS" == "wsl2" ]]; }
is_windows() { [[ "$OS" == "windows" ]]; }

#==============================================================================
# Portable readlink -f (macOS doesn't have -f flag)
#==============================================================================
portable_readlink_f() {
    local file="$1"
    
    # If GNU readlink is available, use it
    if readlink -f "$file" 2>/dev/null; then
        return 0
    fi
    
    # macOS/BSD fallback
    local dir
    local name
    dir=$(dirname "$file")
    name=$(basename "$file")
    
    # Resolve symlinks
    while [[ -L "$file" ]]; do
        file=$(readlink "$file")
        [[ "$file" == /* ]] || file="$dir/$file"
        dir=$(dirname "$file")
        name=$(basename "$file")
    done
    
    # Resolve absolute path
    dir=$(cd "$dir" && pwd 2>/dev/null)
    echo "${dir:-$(pwd)}/$name"
}

#==============================================================================
# Portable sed -i (GNU vs BSD differences)
# Usage: sed_inplace "pattern" "file"
#==============================================================================
sed_inplace() {
    local pattern="$1"
    local file="$2"
    
    if is_macos; then
        sed -i '' "$pattern" "$file"
    else
        sed -i "$pattern" "$file"
    fi
}

#==============================================================================
# Portable stat (GNU stat -c vs BSD stat -f)
#==============================================================================
portable_stat() {
    local format="$1"
    local file="$2"
    
    case "$format" in
        "%a")  # File permissions in octal
            if is_macos; then
                stat -f "%Lp" "$file" 2>/dev/null
            else
                stat -c "%a" "$file" 2>/dev/null
            fi
            ;;
        "%U")  # Owner username
            if is_macos; then
                stat -f "%Su" "$file" 2>/dev/null
            else
                stat -c "%U" "$file" 2>/dev/null
            fi
            ;;
        "%G")  # Group name
            if is_macos; then
                stat -f "%Sg" "$file" 2>/dev/null
            else
                stat -c "%G" "$file" 2>/dev/null
            fi
            ;;
        "%s")  # File size in bytes
            if is_macos; then
                stat -f "%z" "$file" 2>/dev/null
            else
                stat -c "%s" "$file" 2>/dev/null
            fi
            ;;
        "%Y")  # Last modification time (seconds since epoch)
            if is_macos; then
                stat -f "%m" "$file" 2>/dev/null
            else
                stat -c "%Y" "$file" 2>/dev/null
            fi
            ;;
        *)
            echo "Unknown format: $format" >&2
            return 1
            ;;
    esac
}

#==============================================================================
# Portable date (GNU date -d vs BSD date -v)
#==============================================================================
portable_date() {
    local format="${1:-}"
    local date_str="${2:-}"
    
    if [[ -z "$date_str" ]]; then
        # Just formatting current date
        if is_macos; then
            date "+${format:-%Y-%m-%d %H:%M:%S}"
        else
            date "+${format:-%Y-%m-%d %H:%M:%S}"
        fi
    else
        # Converting a date string
        if is_macos; then
            # BSD date - convert common formats
            date -j -f "%Y-%m-%d %H:%M:%S" "$date_str" "+${format:-%Y-%m-%d %H:%M:%S}" 2>/dev/null || \
            date -j -f "%Y-%m-%d" "$date_str" "+${format:-%Y-%m-%d}" 2>/dev/null || \
            date -r "$date_str" "+${format:-%Y-%m-%d %H:%M:%S}" 2>/dev/null
        else
            date -d "$date_str" "+${format:-%Y-%m-%d %H:%M:%S}"
        fi
    fi
}

#==============================================================================
# Portable uppercase/lowercase conversion
# bash 3.2 (macOS) doesn't support ${VAR^^} or ${VAR,,}
#==============================================================================
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

to_lower() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

#==============================================================================
# Portable realpath (for macOS < 12 which doesn't have realpath)
#==============================================================================
portable_realpath() {
    local path="$1"
    
    if command -v realpath &>/dev/null; then
        realpath "$path" 2>/dev/null
    else
        portable_readlink_f "$path"
    fi
}

#==============================================================================
# Check if associative arrays are supported (bash 4+)
#==============================================================================
associative_arrays_supported() {
    [[ "${BASH_VERSINFO[0]}" -ge 4 ]]
}

#==============================================================================
# Get number of CPU cores (cross-platform)
#==============================================================================
get_cpu_cores() {
    if is_macos; then
        sysctl -n hw.ncpu
    else
        nproc
    fi
}

#==============================================================================
# Get total RAM in GB (cross-platform)
#==============================================================================
get_ram_gb() {
    if is_macos; then
        echo $(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))
    else
        free -g | awk '/^Mem:/{print $2}'
    fi
}

#==============================================================================
# Get available disk space in GB (cross-platform)
#==============================================================================
get_disk_gb() {
    local path="${1:-/}"
    if is_macos; then
        df -g "$path" | awk 'NR==2 {print $4}'
    else
        df -BG "$path" | awk 'NR==2 {print $4}' | tr -d 'G'
    fi
}

#==============================================================================
# Check if running in Docker Desktop (macOS/Windows)
#==============================================================================
is_docker_desktop() {
    if [[ "$OS" == "macos" ]] || [[ "$OS" == "wsl2" ]] || [[ "$OS" == "windows" ]]; then
        return 0
    fi
    return 1
}

#==============================================================================
# Get Docker network mode recommendation
# Docker Desktop doesn't support --network host
#==============================================================================
get_docker_network_mode() {
    if is_docker_desktop; then
        echo "bridge"
    else
        echo "host"
    fi
}

#==============================================================================
# Check if a command exists (portable)
#==============================================================================
command_exists() {
    command -v "$1" &>/dev/null
}

#==============================================================================
# Get package manager for current OS
#==============================================================================
get_package_manager() {
    case "$OS" in
        linux|wsl2)
            if command_exists apt-get; then
                echo "apt"
            elif command_exists yum; then
                echo "yum"
            elif command_exists dnf; then
                echo "dnf"
            elif command_exists pacman; then
                echo "pacman"
            else
                echo "unknown"
            fi
            ;;
        macos)
            if command_exists brew; then
                echo "brew"
            else
                echo "unknown"
            fi
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

#==============================================================================
# Install package (cross-platform wrapper)
#==============================================================================
install_package() {
    local pkg="$1"
    local pkg_manager
    pkg_manager=$(get_package_manager)
    
    case "$pkg_manager" in
        apt)
            apt-get update -qq && apt-get install -y -qq "$pkg"
            ;;
        yum)
            yum install -y "$pkg"
            ;;
        dnf)
            dnf install -y "$pkg"
            ;;
        brew)
            brew install "$pkg" 2>/dev/null || true
            ;;
        *)
            echo "Unknown package manager. Please install $pkg manually." >&2
            return 1
            ;;
    esac
}

#==============================================================================
# Colors (check if terminal supports colors)
#==============================================================================
init_colors() {
    if [[ -t 1 ]]; then
        readonly RED='\033[0;31m'
        readonly GREEN='\033[0;32m'
        readonly YELLOW='\033[1;33m'
        readonly BLUE='\033[0;34m'
        readonly CYAN='\033[0;36m'
        readonly MAGENTA='\033[0;35m'
        readonly BOLD='\033[1m'
        readonly NC='\033[0m'
    else
        readonly RED=''
        readonly GREEN=''
        readonly YELLOW=''
        readonly BLUE=''
        readonly CYAN=''
        readonly MAGENTA=''
        readonly BOLD=''
        readonly NC=''
    fi
}

# Initialize colors by default
init_colors

#==============================================================================
# Export functions for use in other scripts
#==============================================================================
export -f detect_os is_macos is_linux is_wsl2 is_windows 2>/dev/null || true
export -f portable_readlink_f sed_inplace portable_stat portable_date 2>/dev/null || true
export -f to_upper to_lower portable_realpath 2>/dev/null || true
export -f get_cpu_cores get_ram_gb get_disk_gb 2>/dev/null || true
export -f is_docker_desktop get_docker_network_mode 2>/dev/null || true
export -f command_exists get_package_manager install_package 2>/dev/null || true
