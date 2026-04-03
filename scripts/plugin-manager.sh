#!/bin/bash
#===============================================================================
# XDC Node Setup - Plugin Manager (#134)
# Manages XDC monitoring plugins: install, list, run, remove.
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="${SCRIPT_DIR}/../plugins"
source "${SCRIPT_DIR}/common-lib.sh"

#-------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [args...]

Commands:
  install <path|url>    Install a plugin from a local path or URL (tar.gz / directory)
  list                  List all installed plugins
  run <name> [port]     Run a plugin (XDC_RPC_PORT defaults to 8545)
  remove <name>         Remove an installed plugin

Options:
  -h, --help            Show this help

Environment variables (passed to plugins):
  XDC_RPC_PORT    RPC port (default: 8545)
  XDC_CLIENT      Client name hint
  XDC_TIMEOUT     RPC timeout in seconds (default: 5)
  XDC_DATA_DIR    Node data directory (default: /opt/xdc-node/data)

Examples:
  $(basename "$0") list
  $(basename "$0") run sync-check 7070
  $(basename "$0") run peer-check
  $(basename "$0") install ./my-plugin/
  $(basename "$0") install https://example.com/plugins/my-plugin.tar.gz
  $(basename "$0") remove my-plugin

Plugin interface:
  See ${PLUGINS_DIR}/README.md
EOF
}

#-------------------------------------------------------------------------------
cmd_list() {
    info "Installed plugins in: ${PLUGINS_DIR}"
    printf "\n"
    printf "%-20s %-10s %s\n" "NAME" "VERSION" "DESCRIPTION"
    printf '%s\n' "$(printf '─%.0s' {1..60})"
    
    local count=0
    for plugin_dir in "${PLUGINS_DIR}"/*/; do
        [[ -d "$plugin_dir" ]] || continue
        local name
        name="$(basename "$plugin_dir")"
        
        # Skip README as a plugin
        [[ "$name" == "README*" ]] && continue
        
        local check_sh="${plugin_dir}/check.sh"
        if [[ ! -f "$check_sh" ]]; then
            continue
        fi
        
        local version="1.0.0"
        local description="(no description)"
        
        # Read plugin.json if present
        if [[ -f "${plugin_dir}/plugin.json" ]]; then
            version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "${plugin_dir}/plugin.json" | cut -d'"' -f4) || version="1.0.0"
            description=$(grep -o '"description"[[:space:]]*:[[:space:]]*"[^"]*"' "${plugin_dir}/plugin.json" | cut -d'"' -f4) || description="(no description)"
        fi
        
        printf "%-20s %-10s %s\n" "$name" "$version" "$description"
        ((count++))
    done
    
    printf "\n"
    log "${count} plugin(s) installed"
}

#-------------------------------------------------------------------------------
cmd_run() {
    local plugin_name="${1:-}"
    local port="${2:-${XDC_RPC_PORT:-8545}}"
    
    if [[ -z "$plugin_name" ]]; then
        error "Usage: $(basename "$0") run <plugin-name> [port]"
        exit 1
    fi
    
    local plugin_dir="${PLUGINS_DIR}/${plugin_name}"
    local check_sh="${plugin_dir}/check.sh"
    
    if [[ ! -d "$plugin_dir" ]]; then
        die "Plugin '${plugin_name}' not found in ${PLUGINS_DIR}"
    fi
    
    if [[ ! -f "$check_sh" ]]; then
        die "Plugin '${plugin_name}' has no check.sh"
    fi
    
    if [[ ! -x "$check_sh" ]]; then
        chmod +x "$check_sh"
    fi
    
    info "Running plugin: ${plugin_name} (port=${port})"
    
    XDC_RPC_PORT="$port" \
    XDC_CLIENT="${XDC_CLIENT:-}" \
    XDC_TIMEOUT="${XDC_TIMEOUT:-5}" \
    XDC_DATA_DIR="${XDC_DATA_DIR:-/opt/xdc-node/data}" \
    bash "${check_sh}"
}

#-------------------------------------------------------------------------------
cmd_run_all() {
    local port="${1:-${XDC_RPC_PORT:-8545}}"
    
    info "Running all plugins on port ${port}"
    
    for plugin_dir in "${PLUGINS_DIR}"/*/; do
        [[ -d "$plugin_dir" ]] || continue
        local name
        name="$(basename "$plugin_dir")"
        [[ -f "${plugin_dir}/check.sh" ]] || continue
        
        local output
        output=$(cmd_run "$name" "$port" 2>/dev/null) || output='{"error":"plugin_failed"}'
        echo "$output"
    done
}

#-------------------------------------------------------------------------------
cmd_install() {
    local source="${1:-}"
    
    if [[ -z "$source" ]]; then
        error "Usage: $(basename "$0") install <path|url>"
        exit 1
    fi
    
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap "rm -rf ${tmp_dir}" EXIT
    
    # Download if URL
    if [[ "$source" == http* ]]; then
        info "Downloading plugin from: ${source}"
        curl -fL --progress-bar -o "${tmp_dir}/plugin.tar.gz" "$source" || die "Download failed"
        
        info "Extracting..."
        tar -xzf "${tmp_dir}/plugin.tar.gz" -C "${tmp_dir}" || die "Extraction failed"
        
        # Find extracted directory
        source="${tmp_dir}"
    fi
    
    # Find check.sh
    local check_sh
    check_sh=$(find "$source" -name "check.sh" | head -1)
    if [[ -z "$check_sh" ]]; then
        die "No check.sh found in ${source}"
    fi
    
    local plugin_src_dir
    plugin_src_dir="$(dirname "$check_sh")"
    local plugin_name
    plugin_name="$(basename "$plugin_src_dir")"
    
    local dest="${PLUGINS_DIR}/${plugin_name}"
    
    if [[ -d "$dest" ]]; then
        warn "Plugin '${plugin_name}' already installed — replacing"
        rm -rf "$dest"
    fi
    
    cp -r "$plugin_src_dir" "$dest"
    chmod +x "${dest}/check.sh"
    
    log "Plugin '${plugin_name}' installed at ${dest}"
}

#-------------------------------------------------------------------------------
cmd_remove() {
    local plugin_name="${1:-}"
    
    if [[ -z "$plugin_name" ]]; then
        error "Usage: $(basename "$0") remove <plugin-name>"
        exit 1
    fi
    
    local plugin_dir="${PLUGINS_DIR}/${plugin_name}"
    
    if [[ ! -d "$plugin_dir" ]]; then
        die "Plugin '${plugin_name}' not found"
    fi
    
    # Safety: don't remove README
    if [[ "$plugin_name" == "README"* ]]; then
        die "Cannot remove README"
    fi
    
    rm -rf "$plugin_dir"
    log "Plugin '${plugin_name}' removed"
}

#-------------------------------------------------------------------------------
main() {
    local cmd="${1:-help}"
    shift || true
    
    case "$cmd" in
        install)   cmd_install "$@" ;;
        list|ls)   cmd_list ;;
        run)       cmd_run "$@" ;;
        run-all)   cmd_run_all "$@" ;;
        remove|rm) cmd_remove "$@" ;;
        -h|--help|help) usage; exit 0 ;;
        *)
            error "Unknown command: ${cmd}"
            usage
            exit 1
            ;;
    esac
}

main "$@"
