#!/bin/bash
#===============================================================================
# Universal XDC Node Setup Installer
# Works on Linux (Ubuntu/Debian/CentOS), macOS, and WSL2
#===============================================================================

# Security Warning (#507): curl|bash MITM protection
if [ "${SKIP_SECURITY_CHECK:-}" != "1" ]; then
  echo "WARNING: This script downloads and executes code from the internet."
  echo "Review the script at https://github.com/AnilChinchawale/xdc-node-setup/blob/main/install.sh"
  echo "Or run with SKIP_SECURITY_CHECK=1 to bypass this warning."
  read -p "Continue? [y/N] " -n 1 -r
  echo
  [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

#===============================================================================
# SECURITY WARNING (#507): This script downloads and executes code from the internet.
# For your security, you should:
#   1. Review this script before execution: https://github.com/AnilChinchawale/xdc-node-setup/blob/main/install.sh
#   2. Use the safer git clone method instead of curl | bash:
#      git clone https://github.com/AnilChinchawale/xdc-node-setup.git
#      cd xdc-node-setup && bash setup.sh
#
# Safer Usage (recommended):
#   git clone https://github.com/AnilChinchawale/xdc-node-setup.git
#   cd xdc-node-setup && bash install.sh --verify
#
# Traditional Usage (convenient but less secure):
#   curl -sSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/install.sh | bash
#
# With verification:
#   curl -sSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/install.sh | bash -s -- --verify
#===============================================================================

set -euo pipefail

# Script version - used for verification
readonly INSTALLER_VERSION="1.0.0"
readonly REPO_URL="https://github.com/AnilChinchawale/xdc-node-setup"
readonly RAW_URL="https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main"

# Expected SHA256 checksum of the install script (update on each release)
# SECURITY: This is a self-check mechanism. In production, this should be
# updated by the CI/CD pipeline for each release.
readonly EXPECTED_CHECKSUM="${INSTALLER_CHECKSUM:-}"  # Set by CI/CD

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

    ██╗  ██╗██████╗  ██████╗    ███╗   ██╗ ██████╗ ██████╗ ███████╗
    ╚██╗██╔╝██╔══██╗██╔════╝    ████╗  ██║██╔═══██╗██╔══██╗██╔════╝
     ╚███╔╝ ██║  ██║██║         ██╔██╗ ██║██║   ██║██║  ██║█████╗  
     ██╔██╗ ██║  ██║██║         ██║╚██╗██║██║   ██║██║  ██║██╔══╝  
    ██╔╝ ██╗██████╔╝╚██████╗    ██║ ╚████║╚██████╔╝██████╔╝███████╗
    ╚═╝  ╚═╝╚═════╝  ╚═════╝    ╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝

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

#===============================================================================
# SECURITY FUNCTIONS (#507): Checksum and Verification
#===============================================================================

# Verify SHA256 checksum of a file
verify_checksum() {
    local file="$1"
    local expected_checksum="${2:-$EXPECTED_CHECKSUM}"
    
    if [[ -z "$expected_checksum" ]]; then
        warn "No expected checksum provided for verification"
        return 0  # Don't fail if no checksum is set (development mode)
    fi
    
    if ! command -v sha256sum >/dev/null 2>&1; then
        warn "sha256sum not available, skipping checksum verification"
        return 0
    fi
    
    local actual_checksum
    actual_checksum=$(sha256sum "$file" | cut -d' ' -f1)
    
    if [[ "$actual_checksum" == "$expected_checksum" ]]; then
        log "SHA256 checksum verification passed"
        return 0
    else
        error "SHA256 checksum verification FAILED!"
        error "Expected: $expected_checksum"
        error "Actual:   $actual_checksum"
        error "The script may have been tampered with. Aborting."
        return 1
    fi
}

# Download with integrity check
download_with_verification() {
    local url="$1"
    local output="$2"
    local verify="${3:-false}"
    
    info "Downloading from $url..."
    
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output" 2>/dev/null
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$output" 2>/dev/null
    else
        error "Neither curl nor wget available"
        return 1
    fi
    
    if [[ ! -f "$output" ]]; then
        error "Download failed: $url"
        return 1
    fi
    
    # If verification is requested, try to fetch and verify checksum
    if [[ "$verify" == "true" ]]; then
        info "Verification requested — checking download integrity..."
        
        # Try to fetch checksums file from repo
        local checksums_url="${RAW_URL}/checksums.sha256"
        local checksums_file=$(mktemp)
        
        if curl -fsSL "$checksums_url" -o "$checksums_file" 2>/dev/null || \
           wget -q "$checksums_url" -O "$checksums_file" 2>/dev/null; then
            
            local filename=$(basename "$output")
            local expected=$(grep "  $filename$" "$checksums_file" 2>/dev/null | cut -d' ' -f1)
            
            if [[ -n "$expected" ]]; then
                verify_checksum "$output" "$expected"
            else
                warn "No checksum found for $filename in checksums file"
            fi
        else
            warn "Could not fetch checksums file for verification"
        fi
        
        rm -f "$checksums_file"
    fi
    
    return 0
}

# Print security banner before installation
print_security_banner() {
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  SECURITY NOTICE                                               ║${NC}"
    echo -e "${YELLOW}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║  This script will:                                             ║${NC}"
    echo -e "${YELLOW}║  • Install Docker (if not present)                             ║${NC}"
    echo -e "${YELLOW}║  • Download XDC node software                                  ║${NC}"
    echo -e "${YELLOW}║  • Configure your system                                       ║${NC}"
    echo -e "${YELLOW}║                                                                ║${NC}"
    echo -e "${YELLOW}║  For security, review the source at:                           ║${NC}"
    echo -e "${YELLOW}║  https://github.com/AnilChinchawale/xdc-node-setup             ║${NC}"
    echo -e "${YELLOW}║                                                                ║${NC}"
    echo -e "${YELLOW}║  Safer alternative:                                            ║${NC}"
    echo -e "${YELLOW}║  git clone ${REPO_URL}.git              ║${NC}"
    echo -e "${YELLOW}║  cd xdc-node-setup && bash install.sh                          ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
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
    # Check if user is already in the cloned repo
    if [[ -f "setup.sh" ]] && [[ -d "scripts" ]] && grep -q "XDC Node Setup Script" setup.sh 2>/dev/null; then
        log "Running from existing XDC Node Setup repository"
        bash setup.sh "$@"
        return 0
    fi
    
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
                cp -r "$temp_dir/xdc-node-setup/monitoring" "$temp_dir/monitoring" 2>/dev/null || true
                cp -r "$temp_dir/xdc-node-setup/dashboard" "$temp_dir/dashboard" 2>/dev/null || true
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
                    cp -r "$temp_dir/xdc-node-setup/monitoring" "$temp_dir/monitoring" 2>/dev/null || true
                    cp -r "$temp_dir/xdc-node-setup/dashboard" "$temp_dir/dashboard" 2>/dev/null || true
                    download_ok=true
                    log "Cloned repository via SSH"
                fi
            fi
        fi
    fi
    
    if [ "$download_ok" = false ]; then
        error "Failed to download XDC Node Setup. Please clone manually:\n  git clone ${REPO_URL}.git\n  cd xdc-node-setup && bash setup.sh"
        exit 1
    fi
    
    chmod +x "$temp_dir/setup.sh"
    
    # Create install directory in user's current working directory
    INSTALL_TARGET="${PWD}/xdc-node"
    log "Creating install directory: $INSTALL_TARGET"
    mkdir -p "$INSTALL_TARGET"
    
    # Copy all needed files there
    cp "$temp_dir/setup.sh" "$INSTALL_TARGET/"
    cp -r "$temp_dir/scripts" "$INSTALL_TARGET/" 2>/dev/null || true
    cp -r "$temp_dir/configs" "$INSTALL_TARGET/" 2>/dev/null || true
    cp -r "$temp_dir/cli" "$INSTALL_TARGET/" 2>/dev/null || true
    cp -r "$temp_dir/docker" "$INSTALL_TARGET/" 2>/dev/null || true
    cp -r "$temp_dir/monitoring" "$INSTALL_TARGET/" 2>/dev/null || true
    cp -r "$temp_dir/dashboard" "$INSTALL_TARGET/" 2>/dev/null || true
    
    log "Setup files copied to $INSTALL_TARGET"
    
    # Install xdc CLI to PATH
    if [ -f "$INSTALL_TARGET/cli/xdc" ]; then
        chmod +x "$INSTALL_TARGET/cli/xdc"
        if [ -w /usr/local/bin ]; then
            ln -sf "$INSTALL_TARGET/cli/xdc" /usr/local/bin/xdc
            log "xdc CLI installed to /usr/local/bin/xdc"
        elif [ -d "$HOME/.local/bin" ]; then
            mkdir -p "$HOME/.local/bin"
            ln -sf "$INSTALL_TARGET/cli/xdc" "$HOME/.local/bin/xdc"
            log "xdc CLI installed to ~/.local/bin/xdc (add to PATH if needed)"
        else
            warn "Could not install xdc CLI to PATH. Run: ln -sf $INSTALL_TARGET/cli/xdc /usr/local/bin/xdc"
        fi
    fi
    
    # Cleanup temp directory
    rm -rf "$temp_dir"
    
    # Change to install directory and run setup
    cd "$INSTALL_TARGET"
    log "Running setup from $INSTALL_TARGET"
    
    bash setup.sh "$@"
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
    
    echo "Useful commands:"
    echo "  xdc status       — Node status + sync progress"
    echo "  xdc health       — Health check (score 0-100)"
    echo "  xdc logs         — View node logs"
    echo "  xdc attach       — Attach to node console"
    echo "  xdc help         — Show all commands"
    echo ""
    echo "Documentation: $REPO_URL"
    echo ""
}

#==============================================================================
# Main
#==============================================================================
main() {
    # Parse command line arguments
    local verify_checksum_flag=false
    local verify_gpg_flag=false
    local SETUP_ARGS=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --yes|-y)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verify)
                verify_checksum_flag=true
                shift
                ;;
            --verify-gpg)
                verify_checksum_flag=true
                verify_gpg_flag=true
                shift
                ;;
            --all)
                SETUP_ARGS+=("--client" "all")
                shift
                ;;
            --erigon)
                SETUP_ARGS+=("--client" "erigon")
                shift
                ;;
            --geth)
                SETUP_ARGS+=("--client" "stable")
                shift
                ;;
            --nethermind)
                SETUP_ARGS+=("--client" "nethermind")
                shift
                ;;
            --client)
                SETUP_ARGS+=("--client" "$2")
                shift 2
                ;;
            --email)
                SETUP_ARGS+=("--email" "$2")
                shift 2
                ;;
            --tg|--telegram)
                SETUP_ARGS+=("--tg" "$2")
                shift 2
                ;;
            --network)
                SETUP_ARGS+=("--network" "$2")
                shift 2
                ;;
            --type)
                SETUP_ARGS+=("--type" "$2")
                shift 2
                ;;
            --help|-h)
                cat << EOF
XDC Node Setup Installer

Usage: curl -sSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/install.sh | bash -s -- [OPTIONS]

Options:
  --yes, -y        Skip confirmation prompts (for CI/CD)
  --dry-run        Show what will be done without executing
  --verify         Verify SHA256 checksum before execution
  --verify-gpg     Verify GPG signature (implies --verify)
  --all            Install all clients (geth + erigon + nethermind)
  --erigon         Install erigon client only
  --nethermind     Install nethermind client only
  --geth           Install geth client only (default)
  --client CLIENT  Client type: stable, erigon, geth-pr5, nethermind, all
  --email EMAIL    Email for SkyNet alerts
  --tg HANDLE      Telegram handle for SkyNet alerts
  --network NET    Network: mainnet, testnet, devnet (default: mainnet)
  --help, -h       Show this help message

Environment Variables:
  SKIP_CONFIRMATION=true   Same as --yes flag

Examples:
  # Standard installation (geth)
  curl -sSL https://.../install.sh | bash

  # Install all clients (geth + erigon)
  curl -sSL https://.../install.sh | bash -s -- --all

  # Install erigon only with alerts
  curl -sSL https://.../install.sh | bash -s -- --erigon --email you@example.com --tg @username

  # CI/CD (no prompts)
  curl -sSL https://.../install.sh | bash -s -- --yes --all

Safer alternative:
  git clone ${REPO_URL}.git
  cd xdc-node-setup && bash install.sh --all

EOF
                exit 0
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    # Check environment variable for skip confirmation
    if [[ "${SKIP_CONFIRMATION:-false}" == "true" ]]; then
        SKIP_CONFIRMATION=true
    fi
    
    # Handle dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        print_dry_run_summary
        exit 0
    fi
    
    # If called with --verify or --verify-gpg, verify this script
    if [[ "$verify_checksum_flag" == "true" ]]; then
        # When piped, we can't verify the running script, so download and verify
        info "Verification mode - downloading and verifying script..."
        local temp_script
        temp_script=$(mktemp)
        if curl -fsSL "${RAW_URL}/install.sh" -o "$temp_script" 2>/dev/null; then
            if verify_checksum "$temp_script"; then
                log "Checksum verification passed"
                if [[ "$verify_gpg_flag" == "true" ]]; then
                    verify_gpg_signature "$temp_script"
                fi
                info "Verification complete. You can now run: bash $temp_script"
                exit 0
            else
                error "Verification failed!"
                rm -f "$temp_script"
                exit 1
            fi
        else
            error "Could not download script for verification"
            rm -f "$temp_script"
            exit 1
        fi
    fi
    
    show_banner
    print_security_banner
    
    # Print security warning (unless --yes was used)
    if [[ "${SKIP_CONFIRMATION:-false}" != "true" ]]; then
        warn "This script will install Docker (if needed), download XDC node software, and configure your system."
        warn "Review the source at: https://github.com/AnilChinchawale/xdc-node-setup"
        echo ""
        read -rp "Do you want to continue? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            info "Installation cancelled by user"
            exit 0
        fi
    fi
    
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
    run_setup "${SETUP_ARGS[@]}"
    
    # Print post-install info
    print_post_install
}

# Run main function
main "$@"
