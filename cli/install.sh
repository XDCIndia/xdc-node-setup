#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# xdc-node CLI Installer
# Installs the xdc-node CLI tool and shell completions
#==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CLI_SCRIPT="${SCRIPT_DIR}/xdc-node"
readonly COMPLETIONS_DIR="${SCRIPT_DIR}/completions"

# Installation paths
readonly INSTALL_BIN="/usr/local/bin"
readonly BASH_COMPLETION_DIR="/etc/bash_completion.d"
readonly ZSH_COMPLETION_DIR="/usr/local/share/zsh/site-functions"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

die() {
    error "$1"
    exit 1
}

print_banner() {
    cat << 'EOF'

    ██╗  ██╗██████╗  ██████╗    ███╗   ██╗ ██████╗ ██████╗ ███████╗
    ╚██╗██╔╝██╔══██╗██╔════╝    ████╗  ██║██╔═══██╗██╔══██╗██╔════╝
     ╚███╔╝ ██║  ██║██║         ██╔██╗ ██║██║   ██║██║  ██║█████╗  
     ██╔██╗ ██║  ██║██║         ██║╚██╗██║██║   ██║██║  ██║██╔══╝  
    ██╔╝ ██╗██████╔╝╚██████╗    ██║ ╚████║╚██████╔╝██████╔╝███████╗
    ╚═╝  ╚═╝╚═════╝  ╚═════╝    ╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝

                    CLI Installer

EOF
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This installer must be run as root. Please run with sudo."
    fi
}

check_dependencies() {
    info "Checking dependencies..."
    
    local missing=()
    
    # Required dependencies
    local deps=(bash curl jq)
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing dependencies: ${missing[*]}"
        info "Installing missing dependencies..."
        
        if command -v apt-get &>/dev/null; then
            apt-get update -qq
            apt-get install -y -qq "${missing[@]}"
        elif command -v yum &>/dev/null; then
            yum install -y -q "${missing[@]}"
        else
            die "Cannot install dependencies. Please install manually: ${missing[*]}"
        fi
    fi
    
    log "All dependencies satisfied"
}

install_cli() {
    info "Installing xdc-node CLI..."
    
    if [[ ! -f "$CLI_SCRIPT" ]]; then
        die "CLI script not found at $CLI_SCRIPT"
    fi
    
    # Make script executable
    chmod +x "$CLI_SCRIPT"
    
    # Create symlink or copy
    if [[ -L "${INSTALL_BIN}/xdc-node" ]]; then
        rm "${INSTALL_BIN}/xdc-node"
    fi
    
    ln -sf "$CLI_SCRIPT" "${INSTALL_BIN}/xdc-node"
    
    log "Installed xdc-node to ${INSTALL_BIN}/xdc-node"
}

install_bash_completion() {
    info "Installing bash completion..."
    
    local completion_file="${COMPLETIONS_DIR}/xdc-node.bash"
    
    if [[ ! -f "$completion_file" ]]; then
        warn "Bash completion file not found, skipping"
        return
    fi
    
    # Create completion directory if needed
    mkdir -p "$BASH_COMPLETION_DIR"
    
    # Install completion
    cp "$completion_file" "${BASH_COMPLETION_DIR}/xdc-node"
    
    log "Installed bash completion to ${BASH_COMPLETION_DIR}/xdc-node"
}

install_zsh_completion() {
    info "Installing zsh completion..."
    
    local completion_file="${COMPLETIONS_DIR}/xdc-node.zsh"
    
    if [[ ! -f "$completion_file" ]]; then
        warn "Zsh completion file not found, skipping"
        return
    fi
    
    # Create completion directory if needed
    mkdir -p "$ZSH_COMPLETION_DIR"
    
    # Install completion (zsh uses _name convention)
    cp "$completion_file" "${ZSH_COMPLETION_DIR}/_xdc-node"
    
    log "Installed zsh completion to ${ZSH_COMPLETION_DIR}/_xdc-node"
}

verify_installation() {
    info "Verifying installation..."
    
    if command -v xdc-node &>/dev/null; then
        log "xdc-node command is available"
        
        # Test version command
        if xdc-node version --quiet &>/dev/null 2>&1 || xdc-node version &>/dev/null 2>&1; then
            log "CLI is working correctly"
        else
            warn "CLI installed but may have issues"
        fi
    else
        die "Installation failed - xdc-node command not found"
    fi
}

print_post_install() {
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Installation Complete!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  The xdc-node CLI has been installed successfully."
    echo ""
    echo "  Quick start:"
    echo "    xdc-node help        Show all commands"
    echo "    xdc-node init        Set up your node"
    echo "    xdc-node status      Check node status"
    echo ""
    echo "  To enable shell completions, restart your shell or run:"
    echo "    source ~/.bashrc     (for bash)"
    echo "    source ~/.zshrc      (for zsh)"
    echo ""
    echo "  Documentation: https://github.com/XinFinOrg/XDC-Node-Setup"
    echo ""
}

uninstall() {
    info "Uninstalling xdc-node CLI..."
    
    # Remove CLI
    if [[ -L "${INSTALL_BIN}/xdc-node" ]] || [[ -f "${INSTALL_BIN}/xdc-node" ]]; then
        rm -f "${INSTALL_BIN}/xdc-node"
        log "Removed ${INSTALL_BIN}/xdc-node"
    fi
    
    # Remove bash completion
    if [[ -f "${BASH_COMPLETION_DIR}/xdc-node" ]]; then
        rm -f "${BASH_COMPLETION_DIR}/xdc-node"
        log "Removed bash completion"
    fi
    
    # Remove zsh completion
    if [[ -f "${ZSH_COMPLETION_DIR}/_xdc-node" ]]; then
        rm -f "${ZSH_COMPLETION_DIR}/_xdc-node"
        log "Removed zsh completion"
    fi
    
    echo ""
    log "xdc-node CLI has been uninstalled"
}

usage() {
    cat << EOF
xdc-node CLI Installer

Usage: $0 [command]

Commands:
    install     Install xdc-node CLI (default)
    uninstall   Remove xdc-node CLI
    help        Show this help

Examples:
    sudo $0             # Install CLI
    sudo $0 install     # Install CLI
    sudo $0 uninstall   # Remove CLI

EOF
}

main() {
    local command="${1:-install}"
    
    case "$command" in
        install)
            print_banner
            check_root
            check_dependencies
            install_cli
            install_bash_completion
            install_zsh_completion
            verify_installation
            print_post_install
            ;;
        uninstall)
            check_root
            uninstall
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
