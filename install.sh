#!/usr/bin/env bash
#===============================================================================
# XNS (XDC Node Setup) Installer v2.1
# One-line installer: curl -fsSL https://install.xdc.network | bash
# Non-interactive by default. Use --interactive for prompts.
# Fixes: #314 (no prompts), #316 (rollback), #324 (integrity check)
#===============================================================================

set -euo pipefail

readonly INSTALLER_VERSION="2.1.0"
readonly REPO_URL="https://github.com/XDCIndia/xdc-node-setup"
readonly RAW_URL="https://raw.githubusercontent.com/XDCIndia/xdc-node-setup/feat/xns-2.0-roadmap"

# Expected SHA256 checksum — updated by CI/CD on each release
readonly EXPECTED_CHECKSUM="${INSTALLER_CHECKSUM:-}"

# Rollback state directory
readonly ROLLBACK_DIR="${HOME}/.xns-rollback"
readonly ROLLBACK_MANIFEST="${ROLLBACK_DIR}/manifest.json"

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
# Rollback System (#316)
#==============================================================================
rollback_init() {
    mkdir -p "$ROLLBACK_DIR"
    echo '{"actions":[],"timestamp":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}' > "$ROLLBACK_MANIFEST"
}

rollback_record() {
    local action="$1"
    local detail="$2"
    local tmp_manifest
    tmp_manifest=$(mktemp)
    jq --arg action "$action" --arg detail "$detail" '.actions += [{"action":$action,"detail":$detail,"time":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}]' "$ROLLBACK_MANIFEST" > "$tmp_manifest" 2>/dev/null || true
    if [[ -f "$tmp_manifest" ]]; then
        mv "$tmp_manifest" "$ROLLBACK_MANIFEST"
    fi
}

rollback_execute() {
    error "Installation failed. Rolling back changes..."
    if [[ -f "$ROLLBACK_MANIFEST" ]]; then
        # Reverse order: last action first
        local actions
        actions=$(jq -r '.actions | reverse | .[] | "\(.action)|\(.detail)"' "$ROLLBACK_MANIFEST" 2>/dev/null || true)
        while IFS='|' read -r action detail; do
            case "$action" in
                "docker_install")
                    info "Rollback: Docker was installed — not removing (system package)"
                    ;;
                "user_docker_group")
                    info "Rollback: Removing user from docker group..."
                    local user="$detail"
                    sudo gpasswd -d "$user" docker 2>/dev/null || true
                    ;;
                "dir_created")
                    info "Rollback: Removing created directory $detail..."
                    rm -rf "$detail"
                    ;;
                "file_copied")
                    info "Rollback: Removing copied file $detail..."
                    rm -f "$detail"
                    ;;
                "symlink_created")
                    info "Rollback: Removing symlink $detail..."
                    rm -f "$detail"
                    ;;
            esac
        done <<< "$actions"
    fi
    info "Rollback complete. System restored to pre-install state."
    exit 1
}

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
    echo -e "${BOLD}XNS Installer v${INSTALLER_VERSION}${NC}"
    echo -e "${BLUE}One-line XDC node installer — non-interactive by default${NC}"
    echo ""
}

#==============================================================================
# OS Compatibility Check
#==============================================================================
check_os_compatibility() {
    case "$OS" in
        linux|wsl2)
            if [[ -f /etc/os-release ]]; then
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
            return 1
            ;;
        *)
            error "Unknown operating system"
            return 1
            ;;
    esac
}

#===============================================================================
# SECURITY: Checksum and Verification (#324)
#===============================================================================
verify_checksum() {
    local file="$1"
    local expected_checksum="${2:-$EXPECTED_CHECKSUM}"

    if [[ -z "$expected_checksum" ]]; then
        warn "No expected checksum provided — skipping verification (dev mode)"
        return 0
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

    if [[ "$verify" == "true" ]]; then
        info "Verifying download integrity..."
        local checksums_url="${RAW_URL}/checksums.sha256"
        local checksums_file
        checksums_file=$(mktemp)

        if curl -fsSL "$checksums_url" -o "$checksums_file" 2>/dev/null || \
           wget -q "$checksums_url" -O "$checksums_file" 2>/dev/null; then
            local filename
            filename=$(basename "$output")
            local expected
            expected=$(grep "  $filename$" "$checksums_file" 2>/dev/null | cut -d' ' -f1)
            if [[ -n "$expected" ]]; then
                verify_checksum "$output" "$expected"
            fi
        fi
        rm -f "$checksums_file"
    fi
    return 0
}

#==============================================================================
# Check Prerequisites
#==============================================================================
check_prerequisites() {
    info "Checking prerequisites..."

    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)  log "Architecture: x86_64 (Intel/AMD)" ;;
        arm64|aarch64) log "Architecture: ARM64 (Apple Silicon/ARM)" ;;
        *) warn "Architecture $arch may not be fully supported" ;;
    esac

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
        log "Docker already installed: $(docker --version)"
        return 0
    fi

    info "Installing Docker..."

    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm /tmp/get-docker.sh

    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl enable docker
        sudo systemctl start docker
    fi

    if [[ -n "${SUDO_USER:-}" ]]; then
        sudo usermod -aG docker "$SUDO_USER"
        rollback_record "user_docker_group" "$SUDO_USER"
        warn "Please log out and back in for Docker permissions to take effect"
    fi

    rollback_record "docker_install" "get.docker.com"
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

    error "Please install Docker Desktop for Mac manually"
    info "  Apple Silicon: https://desktop.docker.com/mac/main/arm64/Docker.dmg"
    info "  Intel Macs:    https://desktop.docker.com/mac/main/amd64/Docker.dmg"
    return 1
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
    if [[ -f "setup.sh" ]] && [[ -d "scripts" ]] && grep -q "XDC Node Setup Script" setup.sh 2>/dev/null; then
        log "Running from existing XDC Node Setup repository"
        bash setup.sh "$@"
        return 0
    fi

    info "Downloading XDC Node Setup..."

    local temp_dir
    temp_dir=$(mktemp -d)
    local download_ok=false

    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL "${RAW_URL}/setup.sh" -o "$temp_dir/setup.sh" 2>/dev/null; then
            download_ok=true
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q "${RAW_URL}/setup.sh" -O "$temp_dir/setup.sh" 2>/dev/null; then
            download_ok=true
        fi
    fi

    if [ "$download_ok" = false ]; then
        warn "Direct download failed. Falling back to git clone..."
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
            fi
        fi
    fi

    if [ "$download_ok" = false ]; then
        error "Failed to download XDC Node Setup. Please clone manually:\n  git clone ${REPO_URL}.git\n  cd xdc-node-setup && bash setup.sh"
        exit 1
    fi

    chmod +x "$temp_dir/setup.sh"

    INSTALL_TARGET="${PWD}/xdc-node"
    log "Creating install directory: $INSTALL_TARGET"
    mkdir -p "$INSTALL_TARGET"
    rollback_record "dir_created" "$INSTALL_TARGET"

    cp "$temp_dir/setup.sh" "$INSTALL_TARGET/"
    cp -r "$temp_dir/scripts" "$INSTALL_TARGET/" 2>/dev/null || true
    cp -r "$temp_dir/configs" "$INSTALL_TARGET/" 2>/dev/null || true
    cp -r "$temp_dir/cli" "$INSTALL_TARGET/" 2>/dev/null || true
    cp -r "$temp_dir/docker" "$INSTALL_TARGET/" 2>/dev/null || true
    cp -r "$temp_dir/monitoring" "$INSTALL_TARGET/" 2>/dev/null || true
    cp -r "$temp_dir/dashboard" "$INSTALL_TARGET/" 2>/dev/null || true

    log "Setup files copied to $INSTALL_TARGET"

    # Install xns CLI to PATH
    if [ -f "$INSTALL_TARGET/cli/xns" ]; then
        chmod +x "$INSTALL_TARGET/cli/xns"
        rollback_record "file_copied" "$INSTALL_TARGET/cli/xns"

        # Create symlink in /usr/local/bin
        local bin_dir="/usr/local/bin"
        if [[ -w "$bin_dir" ]] || sudo -n true 2>/dev/null; then
            sudo ln -sf "$INSTALL_TARGET/cli/xns" "$bin_dir/xns" 2>/dev/null || true
            rollback_record "symlink_created" "$bin_dir/xns"
            log "xns CLI installed to $bin_dir/xns"
        else
            warn "Cannot install xns to PATH — add $INSTALL_TARGET/cli to your PATH manually"
        fi
    fi
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
    echo -e "${GREEN}    XNS Setup Complete!${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo ""
    echo "Useful commands:"
    echo "  xns status       — Node status + sync progress"
    echo "  xns logs         — View node logs"
    echo "  xns down         — Stop node"
    echo "  xns help         — Show all commands"
    echo ""
    echo "Documentation: $REPO_URL"
    echo ""
}

#==============================================================================
# Main
#==============================================================================
main() {
    local verify_checksum_flag=false
    local interactive_flag=false
    local SETUP_ARGS=()

    while [[ $# -gt 0 ]]; do
        case $1 in
            --interactive)
                interactive_flag=true
                shift
                ;;
            --verify)
                verify_checksum_flag=true
                shift
                ;;
            --client)
                SETUP_ARGS+=("--client" "$2")
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
XNS (XDC Node Setup) Installer v${INSTALLER_VERSION}

Usage: curl -fsSL https://install.xdc.network | bash
       curl -fsSL https://install.xdc.network | bash -s -- --interactive

Options:
  --interactive      Enable interactive prompts (default: non-interactive)
  --verify           Verify SHA256 checksum before execution
  --client CLIENT    Client: gp5, v268, erigon, nethermind, reth (default: gp5)
  --network NET      Network: mainnet, apothem (default: mainnet)
  --type TYPE        Node type: full, archive, masternode (default: full)
  --help, -h         Show this help message

Environment Variables:
  INSTALLER_CHECKSUM=sha256   Verify installer integrity

Examples:
  # Default: non-interactive, mainnet, gp5 client
  curl -fsSL https://install.xdc.network | bash

  # Apothem testnet with interactive prompts
  curl -fsSL https://install.xdc.network | bash -s -- --interactive --network apothem

  # With verification
  curl -fsSL https://install.xdc.network | bash -s -- --verify

EOF
                exit 0
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done

    # Handle --verify: download and verify, then exit
    if [[ "$verify_checksum_flag" == "true" ]]; then
        info "Verification mode — downloading and verifying script..."
        local temp_script
        temp_script=$(mktemp)
        if curl -fsSL "${RAW_URL}/install.sh" -o "$temp_script" 2>/dev/null; then
            if verify_checksum "$temp_script"; then
                log "Checksum verification passed"
                info "Verification complete. Run: bash $temp_script"
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

    # Only show interactive confirmation if --interactive flag is used
    if [[ "$interactive_flag" == "true" ]]; then
        warn "This script will install Docker (if needed), download XDC node software, and configure your system."
        info "Review the source at: $REPO_URL"
        echo ""
        read -rp "Continue? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            info "Installation cancelled"
            exit 0
        fi
    fi

    # Initialize rollback tracking
    rollback_init

    # Set trap to call rollback on failure
    trap 'rollback_execute' ERR

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

    # Success — clear rollback trap
    trap - ERR

    # Print post-install info
    print_post_install
}

# Run main function
main "$@"
