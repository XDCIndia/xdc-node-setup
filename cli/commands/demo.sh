#!/usr/bin/env bash
#==============================================================================
# xdc demo — Interactive Tutorial & Demo Mode
# Walks users through XDC node setup with guided, hands-on steps
#==============================================================================

set -euo pipefail

readonly DEMO_VERSION="1.0.0"

# Colors
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" != "true" ]]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    RED='\033[0;31m'
    RESET='\033[0m'
else
    BOLD='' DIM='' GREEN='' BLUE='' YELLOW='' CYAN='' RED='' RESET=''
fi

#------------------------------------------------------------------------------
# Helpers
#------------------------------------------------------------------------------
print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${BLUE}║${RESET}  ${BOLD}$1${RESET}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_step() {
    local step="$1" total="$2" desc="$3"
    echo -e "${CYAN}[${step}/${total}]${RESET} ${BOLD}${desc}${RESET}"
}

print_cmd() {
    echo -e "  ${DIM}\$${RESET} ${GREEN}$1${RESET}"
}

print_info() {
    echo -e "  ${DIM}ℹ${RESET}  $1"
}

print_success() {
    echo -e "  ${GREEN}✔${RESET}  $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${RESET}  $1"
}

wait_for_enter() {
    echo ""
    echo -e "  ${DIM}Press Enter to continue (or 'q' to quit)...${RESET}"
    read -r input
    if [[ "$input" == "q" || "$input" == "Q" ]]; then
        echo -e "\n${YELLOW}Demo exited.${RESET}"
        exit 0
    fi
}

run_demo_cmd() {
    local cmd="$1"
    print_cmd "$cmd"
    echo ""
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo -e "  ${DIM}(dry-run: command skipped)${RESET}"
    else
        eval "$cmd" 2>&1 | sed 's/^/  /' || true
    fi
    echo ""
}

#------------------------------------------------------------------------------
# Demo modules
#------------------------------------------------------------------------------
demo_getting_started() {
    local total=5

    print_header "🚀 Getting Started with XDC Node"

    print_step 1 $total "Check prerequisites"
    print_info "Let's verify your system is ready for XDC."
    run_demo_cmd "docker --version 2>/dev/null || echo 'Docker not found — please install Docker first'"
    run_demo_cmd "echo \"OS: \$(uname -s) | Arch: \$(uname -m) | Disk: \$(df -h / | tail -1 | awk '{print \$4}') free\""
    wait_for_enter

    print_step 2 $total "Install XDC Node"
    print_info "The install script sets up the CLI and dependencies."
    print_cmd "curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/install.sh | bash"
    print_info "(Skipping actual install in demo mode)"
    wait_for_enter

    print_step 3 $total "Configure your node"
    print_info "The setup wizard helps you pick network, client, and options."
    print_cmd "xdc setup"
    print_info "Options: mainnet | testnet | devnet"
    print_info "Clients: geth (default) | erigon"
    wait_for_enter

    print_step 4 $total "Start the node"
    print_info "One command to launch your XDC node."
    print_cmd "xdc start"
    wait_for_enter

    print_step 5 $total "Verify it's running"
    run_demo_cmd "xdc status 2>/dev/null || echo '(node not running — this is just a demo)'"
    run_demo_cmd "xdc health 2>/dev/null || echo '(health check skipped in demo)'"

    print_success "Tutorial complete! Your node would now be syncing with the XDC network."
    echo ""
    print_info "Next: run ${GREEN}xdc demo masternode${RESET} to learn about validator setup."
}

demo_masternode() {
    local total=4

    print_header "🏛️  Masternode (Validator) Setup"

    print_step 1 $total "Requirements"
    print_info "To run a masternode you need:"
    print_info "  • 10,000,000 XDC staked"
    print_info "  • Fully synced node"
    print_info "  • Static IP address"
    print_info "  • 99.9% uptime"
    wait_for_enter

    print_step 2 $total "Create & fund wallet"
    print_cmd "xdc wallet create"
    print_cmd "xdc wallet balance"
    wait_for_enter

    print_step 3 $total "Register as masternode"
    print_cmd "xdc masternode register --name \"My Node\" --coinbase 0x..."
    print_cmd "xdc setup --masternode"
    print_cmd "xdc restart"
    wait_for_enter

    print_step 4 $total "Verify masternode status"
    print_cmd "xdc masternode status"
    print_cmd "xdc masternode info"

    print_success "Masternode tutorial complete!"
    echo ""
    print_info "Full guide: docs/tutorials/masternode-setup.md"
}

demo_erigon() {
    local total=3

    print_header "⚡ Erigon Migration"

    print_step 1 $total "Why Erigon?"
    print_info "Erigon uses ~60% less disk and syncs ~2x faster than Geth."
    print_info "  Geth:   ~500 GB disk, 4-8h sync"
    print_info "  Erigon: ~200 GB disk, 2-4h sync"
    wait_for_enter

    print_step 2 $total "Migrate"
    print_cmd "xdc stop"
    print_cmd "xdc setup --client erigon"
    print_cmd "xdc start"
    wait_for_enter

    print_step 3 $total "Verify"
    print_cmd "xdc status --json | jq '.client'"
    print_cmd "xdc health"

    print_success "Erigon migration tutorial complete!"
    echo ""
    print_info "Full guide: docs/tutorials/erigon-migration.md"
}

demo_monitoring() {
    local total=3

    print_header "📊 Monitoring Setup"

    print_step 1 $total "Built-in monitoring"
    run_demo_cmd "xdc status 2>/dev/null || echo '(status: demo mode)'"
    print_cmd "xdc health --json"
    print_cmd "xdc logs --tail 10"
    wait_for_enter

    print_step 2 $total "Deploy Prometheus + Grafana"
    print_cmd "xdc monitoring start"
    print_info "Prometheus: http://localhost:9090"
    print_info "Grafana:    http://localhost:3000  (admin/admin)"
    wait_for_enter

    print_step 3 $total "Configure alerts"
    print_cmd "xdc config set alerts.slack.webhook 'https://hooks.slack.com/...'"
    print_info "Alerts: node down, sync lagging, low peers, disk full"

    print_success "Monitoring tutorial complete!"
    echo ""
    print_info "Full guide: docs/tutorials/monitoring.md"
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------
demo_usage() {
    echo -e "${BOLD}xdc demo${RESET} — Interactive tutorials for XDC Node Setup"
    echo ""
    echo "Usage: xdc demo [tutorial]"
    echo ""
    echo "Tutorials:"
    echo "  getting-started   First-time node setup (default)"
    echo "  masternode        Validator/masternode configuration"
    echo "  erigon            Migrate from Geth to Erigon"
    echo "  monitoring        Set up monitoring & alerts"
    echo "  all               Run all tutorials"
    echo ""
    echo "Options:"
    echo "  --dry-run         Show commands without executing"
    echo "  --help            Show this help"
    echo ""
    echo "Examples:"
    echo "  xdc demo"
    echo "  xdc demo masternode"
    echo "  xdc demo all --dry-run"
}

main() {
    local tutorial="${1:-getting-started}"

    # Parse flags
    for arg in "$@"; do
        case "$arg" in
            --dry-run) export DRY_RUN=true ;;
            --help|-h) demo_usage; exit 0 ;;
        esac
    done

    print_header "🎓 XDC Node Interactive Tutorial"
    echo -e "  Version: ${DIM}${DEMO_VERSION}${RESET}"
    echo -e "  Mode: ${DRY_RUN:+${YELLOW}dry-run${RESET}}${DRY_RUN:-${GREEN}interactive${RESET}}"
    echo ""

    case "$tutorial" in
        getting-started|start|"") demo_getting_started ;;
        masternode|mn|validator)   demo_masternode ;;
        erigon|migration)          demo_erigon ;;
        monitoring|monitor)        demo_monitoring ;;
        all)
            demo_getting_started
            demo_masternode
            demo_erigon
            demo_monitoring
            ;;
        *)
            echo -e "${RED}Unknown tutorial: $tutorial${RESET}"
            demo_usage
            exit 1
            ;;
    esac

    echo ""
    echo -e "${BOLD}${GREEN}🎉 Thanks for completing the tutorial!${RESET}"
    echo -e "  Docs: ${CYAN}https://github.com/AnilChinchawale/xdc-node-setup/tree/main/docs/tutorials${RESET}"
    echo ""
}

main "$@"
