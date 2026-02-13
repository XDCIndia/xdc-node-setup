#!/bin/bash
#===============================================================================
# Universal XDC Node Setup Installer
# Works on Linux (Ubuntu/Debian/CentOS), macOS, and WSL2
# Usage: curl -sSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/install.sh | bash
#===============================================================================

set -euo pipefail

# Script version
readonly INSTALLER_VERSION="1.0.0"
readonly REPO_URL="https://github.com/AnilChinchawale/xdc-node-setup"
readonly RAW_URL="https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main"

# Colors
if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly BOLD='\033[1m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly CYAN=''
    readonly BOLD=''
    readonly NC=''
fi

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

#==============================================================================
# Logging Functions
#==============================================================================
log() {
    echo -e "${GREEN}✓${NC} $1"
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1" >&2
}

#==============================================================================
# Banner
#==============================================================================
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
 __  ______   ____  _   _______________________ 
 \ \/ /  _ \ / __ \/ | / / ____/_  __/  _/ __ \
  \  / / / / / / /  |/ / __/   / /  / // /_/ /
  / / /_/ / /_/ / /|  / /___  / / _/ // ____/ 
 /_/_____/\____/_/ |_/_____/ /_/ /___/_/      
                                               
EOF
    echo -e "${NC}"
    echo -e "${BOLD}Universal XDC Node Installer v${INSTALLER_VERSION}${NC}"
    echo -e "${BLUE}One-line installer for Linux, macOS, and WSL2${NC}"
    echo ""
}

#==============================================================================
# OS Compatibility Check
#==============================================================================
check_os_compatibility() {
    case "$OS" in
        linux|wsl2)
            if [[ -f /etc/os-release ]]; then
                # shellcheck source=/dev/null
                . /etc/os-release
                case "$ID" in
                    ubuntu)
                        if [[ "${VERSION_ID%%.*}" -ge 20 ]]; then
                            log "Ubuntu $VERSION_ID detected (supported)"
                            return 0
                        fi
                        ;;
                    debian)
                        if [[ "${VERSION_ID%%.*}" -ge 11 ]]; then
                            log "Debian $VERSION_ID detected (supported)"
                            return 0
                        fi
                        ;;
                    centos|rhel|fedora|rocky|almalinux)
                        log "$NAME detected (experimental support)"
                        return 0
                        ;;
                esac
            fi
            error "Unsupported Linux distribution"
            info "Supported: Ubuntu 20.04+, Debian 11+, CentOS/RHEL 8+"
            return 1
            ;;
        macos)
            local mac_version
            mac_version=$(sw_vers -productVersion | cut -d. -f1-2)
            local major_version
            major_version=$(echo "$mac_version" | cut -d. -f1)
            if [[ "$major_version" -ge 13 ]]; then
                log "macOS $mac_version detected (supported)"
                return 0
            else
                error "macOS $mac_version is not supported"
                info "Requires macOS 13.0 (Ventura) or later"
                return 1
            fi
            ;;
        windows)
            error "Windows is not directly supported"
            info "Please use WSL2 with Docker Desktop"
            info "See: $REPO_URL/blob/main/docs/WINDOWS-SETUP.md"
            return 1
            ;;
        *)
            error "Unknown operating system"
            return 1
            ;;
    esac
}

#==============================================================================
# Check Prerequisites
#==============================================================================
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check architecture
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)  log "Architecture: x86_64 (Intel/AMD)" ;;
        arm64|aarch64) log "Architecture: ARM64 (Apple Silicon/ARM)" ;;
        *) warn "Architecture $arch may not be fully supported" ;;
    esac
    
    # Check for curl or wget
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        error "Neither curl nor wget found. Please install one of them."
        return 1
    fi
    
    log "Prerequisites check passed"
}

#==============================================================================
# Install Docker
#==============================================================================
install_docker_linux() {
    if command -v docker >/dev/null 2>&1; then
        log "Docker already installed"
        docker --version
        return 0
    fi
    
    info "Installing Docker..."
    
    # Install using official Docker script
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm /tmp/get-docker.sh
    
    # Start Docker
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl enable docker
        sudo systemctl start docker
    fi
    
    # Add user to docker group
    if [[ -n "${SUDO_USER:-}" ]]; then
        sudo usermod -aG docker "$SUDO_USER"
        warn "Please log out and back in for Docker permissions to take effect"
    fi
    
    log "Docker installed successfully"
}

install_docker_macos() {
    if command -v docker >/dev/null 2>&1; then
        log "Docker already installed"
        docker --version
        return 0
    fi
    
    if [[ -d "/Applications/Docker.app" ]]; then
        warn "Docker Desktop found but not in PATH"
        warn "Please start Docker Desktop from Applications"
        return 1
    fi
    
    info "Please install Docker Desktop for Mac:"
    info "  Apple Silicon: https://desktop.docker.com/mac/main/arm64/Docker.dmg"
    info "  Intel Macs:    https://desktop.docker.com/mac/main/amd64/Docker.dmg"
    info ""
    info "After installation, re-run this installer."
    exit 1
}

install_docker() {
    case "$OS" in
        linux|wsl2) install_docker_linux ;;
        macos)      install_docker_macos ;;
    esac
}

#==============================================================================
# Install Dependencies
#==============================================================================
install_dependencies_linux() {
    info "Installing dependencies..."
    
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq
        sudo apt-get install -y -qq curl wget jq git
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y curl wget jq git
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y curl wget jq git
    else
        warn "Could not install dependencies automatically"
        warn "Please install: curl, wget, jq, git"
    fi
}

install_dependencies_macos() {
    if ! command -v brew >/dev/null 2>&1; then
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    
    info "Installing dependencies..."
    brew update
    brew install curl wget jq git
}

install_dependencies() {
    case "$OS" in
        linux|wsl2) install_dependencies_linux ;;
        macos)      install_dependencies_macos ;;
    esac
}

#==============================================================================
# Download and Run Setup
#==============================================================================
run_setup() {
    info "Downloading XDC Node Setup..."
    
    local temp_dir
    temp_dir=$(mktemp -d)
    local download_ok=false
    
    # Try downloading setup script via curl/wget first (works for public repos)
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL "${RAW_URL}/setup.sh" -o "$temp_dir/setup.sh" 2>/dev/null; then
            download_ok=true
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q "${RAW_URL}/setup.sh" -O "$temp_dir/setup.sh" 2>/dev/null; then
            download_ok=true
        fi
    fi
    
    # If download failed (404 / private repo), fall back to git clone
    if [ "$download_ok" = false ]; then
        warn "Direct download failed (repo may be private). Falling back to git clone..."
        rm -rf "$temp_dir"
        temp_dir=$(mktemp -d)
        
        if command -v git >/dev/null 2>&1; then
            if git clone --depth 1 "${REPO_URL}.git" "$temp_dir/xdc-node-setup" 2>/dev/null; then
                cp "$temp_dir/xdc-node-setup/setup.sh" "$temp_dir/setup.sh"
                cp -r "$temp_dir/xdc-node-setup/scripts" "$temp_dir/scripts" 2>/dev/null || true
                cp -r "$temp_dir/xdc-node-setup/configs" "$temp_dir/configs" 2>/dev/null || true
                cp -r "$temp_dir/xdc-node-setup/cli" "$temp_dir/cli" 2>/dev/null || true
                cp -r "$temp_dir/xdc-node-setup/docker" "$temp_dir/docker" 2>/dev/null || true
                download_ok=true
                log "Cloned repository successfully"
            else
                # Try SSH if HTTPS fails
                if git clone --depth 1 "git@github.com:AnilChinchawale/xdc-node-setup.git" "$temp_dir/xdc-node-setup" 2>/dev/null; then
                    cp "$temp_dir/xdc-node-setup/setup.sh" "$temp_dir/setup.sh"
                    cp -r "$temp_dir/xdc-node-setup/scripts" "$temp_dir/scripts" 2>/dev/null || true
                    cp -r "$temp_dir/xdc-node-setup/configs" "$temp_dir/configs" 2>/dev/null || true
                    cp -r "$temp_dir/xdc-node-setup/cli" "$temp_dir/cli" 2>/dev/null || true
                    cp -r "$temp_dir/xdc-node-setup/docker" "$temp_dir/docker" 2>/dev/null || true
                    download_ok=true
                    log "Cloned repository via SSH"
                fi
            fi
        fi
    fi
    
    if [ "$download_ok" = false ]; then
        error "Failed to download XDC Node Setup. Please clone manually:\n  git clone ${REPO_URL}.git\n  cd xdc-node-setup && bash setup.sh"
    fi
    
    chmod +x "$temp_dir/setup.sh"
    
    log "Setup script ready"
    info "Running setup..."
    
    # Run setup with any additional arguments passed to this script
    "$temp_dir/setup.sh" "$@"
    
    # Cleanup
    rm -rf "$temp_dir"
}

#==============================================================================
# Print Post-Install Information
#==============================================================================
print_post_install() {
    echo ""
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}    XDC Node Setup Complete!${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo ""
    
    case "$OS" in
        linux|wsl2)
            echo "Your XDC node is running in Docker."
            echo ""
            echo "Useful commands:"
            echo "  docker ps              - Check node status"
            echo "  docker logs -f xdc-node - View logs"
            echo "  docker stop xdc-node   - Stop node"
            echo "  docker start xdc-node  - Start node"
            ;;
        macos)
            echo "Your XDC node is running in Docker Desktop."
            echo ""
            echo "Useful commands:"
            echo "  docker ps              - Check node status"
            echo "  docker logs -f xdc-node - View logs"
            echo "  open http://localhost:3000 - Open Grafana"
            ;;
    esac
    
    echo ""
    echo "RPC Endpoints:"
    echo "  HTTP:   http://localhost:8545"
    echo "  WebSocket: http://localhost:8546"
    echo ""
    echo "Documentation: $REPO_URL"
    echo ""
}

#==============================================================================
# Main
#==============================================================================
main() {
    show_banner
    
    # Check OS compatibility
    if ! check_os_compatibility; then
        exit 1
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Install Docker
    install_docker
    
    # Verify Docker is running
    if ! docker info >/dev/null 2>&1; then
        error "Docker is installed but not running"
        case "$OS" in
            macos)
                info "Please start Docker Desktop from Applications"
                ;;
            linux|wsl2)
                info "Try: sudo systemctl start docker"
                ;;
        esac
        exit 1
    fi
    
    # Install dependencies
    install_dependencies
    
    # Run setup
    run_setup "$@"
    
    # Print post-install info
    print_post_install
}

# Run main function
main "$@"
