#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# XDC Governance - Governance Participation Tools
#==============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Source notification library
if [[ -f "${SCRIPT_DIR}/lib/notify.sh" ]]; then
    # shellcheck source=lib/notify.sh
    source "${SCRIPT_DIR}/lib/notify.sh"
fi

# Source XDC contracts library
if [[ -f "${SCRIPT_DIR}/lib/xdc-contracts.sh" ]]; then
    # shellcheck source=lib/xdc-contracts.sh
    source "${SCRIPT_DIR}/lib/xdc-contracts.sh"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
readonly XDC_RPC_URL="${XDC_RPC_URL:-http://localhost:8545}"
readonly GOVERNANCE_CONTRACT="${XDC_GOVERNANCE_CONTRACT:-0x0000000000000000000000000000000000000088}"
# Detect network for network-aware directory structure
detect_network() {
    local network="${NETWORK:-}"
    if [[ -z "$network" && -f "$(pwd)/config.toml" ]]; then
        network=$(grep -E '^\s*name\s*=' "$(pwd)/config.toml" 2>/dev/null | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -1)
    fi
    if [[ -z "$network" && -f "/opt/xdc-node/config.toml" ]]; then
        network=$(grep -E '^\s*name\s*=' "/opt/xdc-node/config.toml" 2>/dev/null | sed -E 's/.*=\s*"([^"]+)".*/\1/' | head -1)
    fi
    echo "${network:-mainnet}"
}
readonly XDC_NETWORK="${XDC_NETWORK:-$(detect_network)}"
readonly XDC_DATA="${XDC_DATA:-$(pwd)/${XDC_NETWORK}/xdcchain}"
readonly XDC_STATE_DIR="${XDC_STATE_DIR:-$(pwd)/${XDC_NETWORK}/.xdc-node}"

# State files
readonly VOTE_HISTORY="${XDC_STATE_DIR}/governance-votes.json"

#==============================================================================
# Utility Functions
#==============================================================================

log() { echo -e "${GREEN}✓${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1" >&2; }
error() { echo -e "${RED}✗${NC} $1" >&2; }
die() { error "$1"; exit 1; }

rpc_call() {
    local url="${1:-$XDC_RPC_URL}"
    local method="$2"
    local params="${3:-[]}"
    
    curl -s -m 15 -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        "$url" 2>/dev/null || echo '{}'
}

hex_to_dec() {
    local hex="${1#0x}"
    printf "%d\n" "0x${hex}" 2>/dev/null || echo "0"
}

#==============================================================================
# List Proposals
#==============================================================================

list_proposals() {
    echo -e "${BOLD}━━━ Active Governance Proposals ━━━${NC}"
    echo ""
    
    local proposals
    proposals=$(get_proposals 2>/dev/null || echo "[]")
    local proposal_count
    proposal_count=$(echo "$proposals" | jq 'length')
    
    if [[ "$proposal_count" -eq 0 ]]; then
        info "No active proposals found."
        echo ""
        info "Governance proposals are managed through the XDC Network governance portal."
        info "Visit: https://master.xinfin.network/governance"
        echo ""
        return 0
    fi
    
    echo -e "${CYAN}Found $proposal_count proposal(s):${NC}"
    echo ""
    
    printf "  ${BOLD}%-6s %-30s %-12s %-12s %-10s${NC}\n" "ID" "Title" "Status" "Votes" "Ends In"
    echo "─────────────────────────────────────────────────────────────────────────────────"
    
    local i
    for ((i = 0; i < proposal_count; i++)); do
        local proposal
        proposal=$(echo "$proposals" | jq -r ".[$i]")
        
        local id
        id=$(echo "$proposal" | jq -r '.id // "N/A"')
        local title
        title=$(echo "$proposal" | jq -r '.title // "Untitled"')
        local status
        status=$(echo "$proposal" | jq -r '.status // "unknown"')
        local yes_votes
        yes_votes=$(echo "$proposal" | jq -r '.yesVotes // 0')
        local no_votes
        no_votes=$(echo "$proposal" | jq -r '.noVotes // 0')
        local total_votes=$((yes_votes + no_votes))
        local end_time
        end_time=$(echo "$proposal" | jq -r '.endTime // 0')
        
        # Truncate title if too long
        if [[ ${#title} -gt 27 ]]; then
            title="${title:0:27}..."
        fi
        
        # Color status
        local status_color=""
        case "$status" in
            "active") status_color="${GREEN}" ;;
            "pending") status_color="${YELLOW}" ;;
            "passed") status_color="${CYAN}" ;;
            "rejected") status_color="${RED}" ;;
            *) status_color="${DIM}" ;;
        esac
        
        printf "  %-6s %-30s ${status_color}%-12s${NC} %-12d %s\n" \
            "$id" "$title" "$status" "$total_votes" "${end_time}h"
    done
    
    echo ""
}

#==============================================================================
# Cast Vote
#==============================================================================

cast_vote() {
    local proposal_id="$1"
    local vote_choice="$2"
    local voter_address="${3:-}"
    
    echo -e "${BOLD}━━━ Cast Governance Vote ━━━${NC}"
    echo ""
    
    # Validate vote choice
    if [[ "$vote_choice" != "yes" && "$vote_choice" != "no" ]]; then
        die "Invalid vote choice. Use 'yes' or 'no'."
    fi
    
    # If no address provided, try to get from coinbase
    if [[ -z "$voter_address" ]]; then
        local coinbase_file="${XDC_DATA}/.coinbase"
        if [[ -f "$coinbase_file" ]]; then
            voter_address=$(cat "$coinbase_file")
        fi
    fi
    
    if [[ -z "$voter_address" ]]; then
        die "Voter address required. Provide as argument or configure coinbase."
    fi
    
    info "Preparing vote transaction..."
    printf "  ${BOLD}%-20s${NC} %s\n" "Proposal ID:" "$proposal_id"
    printf "  ${BOLD}%-20s${NC} %s\n" "Vote:" "$vote_choice"
    printf "  ${BOLD}%-20s${NC} %s\n" "Voter:" "$voter_address"
    
    echo ""
    
    # In a real implementation, this would submit a transaction
    # For now, we simulate and provide instructions
    warn "This is a simulation. To actually vote, use the governance portal."
    echo ""
    
    echo "To cast your vote via the XDC governance system:"
    echo ""
    echo "1. Visit: https://master.xinfin.network/governance"
    echo "2. Connect your wallet (must be a masternode owner)"
    echo "3. Find Proposal #$proposal_id"
    echo "4. Click 'Vote ${vote_choice^^}'"
    echo "5. Confirm the transaction in your wallet"
    echo ""
    
    # Store vote in local history
    mkdir -p "$(dirname "$VOTE_HISTORY")"
    
    local vote_entry
    vote_entry=$(jq -n \
        --arg proposal_id "$proposal_id" \
        --arg vote "$vote_choice" \
        --arg voter "$voter_address" \
        --arg timestamp "$(date -Iseconds)" \
        '{proposalId: $proposal_id, vote: $vote, voter: $voter, timestamp: $timestamp, status: "pending"}')
    
    if [[ -f "$VOTE_HISTORY" ]]; then
        local tmp_file
        tmp_file=$(mktemp)
        jq --argjson entry "$vote_entry" '.votes = (.votes // []) + [$entry]' "$VOTE_HISTORY" > "$tmp_file"
        mv "$tmp_file" "$VOTE_HISTORY"
    else
        echo "{\"votes\": [$vote_entry]}" > "$VOTE_HISTORY"
    fi
    
    log "Vote recorded in local history: $VOTE_HISTORY"
    
    echo ""
}

#==============================================================================
# Analyze Impact
#==============================================================================

analyze_impact() {
    local proposal_id="$1"
    
    echo -e "${BOLD}━━━ Proposal Impact Analysis ━━━${NC}"
    echo ""
    
    info "Analyzing Proposal #$proposal_id..."
    echo ""
    
    # Fetch proposal details
    local proposals
    proposals=$(get_proposals 2>/dev/null || echo "[]")
    local proposal
    proposal=$(echo "$proposals" | jq -r ".[] | select(.id == \"$proposal_id\")")
    
    if [[ -z "$proposal" || "$proposal" == "null" ]]; then
        warn "Proposal #$proposal_id not found in active proposals."
        echo ""
        info "Note: Impact analysis requires access to the proposal details."
        info "For detailed analysis, visit: https://master.xinfin.network/governance"
        echo ""
        return 1
    fi
    
    local title
    title=$(echo "$proposal" | jq -r '.title // "Untitled"')
    local description
    description=$(echo "$proposal" | jq -r '.description // "No description available"')
    local proposal_type
    proposal_type=$(echo "$proposal" | jq -r '.type // "standard"')
    
    echo -e "${CYAN}Proposal Details:${NC}"
    printf "  ${BOLD}%-20s${NC} %s\n" "ID:" "$proposal_id"
    printf "  ${BOLD}%-20s${NC} %s\n" "Title:" "$title"
    printf "  ${BOLD}%-20s${NC} %s\n" "Type:" "$proposal_type"
    
    echo ""
    echo -e "${CYAN}Description:${NC}"
    echo "  $description"
    
    echo ""
    echo -e "${CYAN}Estimated Impact:${NC}"
    
    # Analyze impact based on proposal type
    case "$proposal_type" in
        "param_change")
            echo "  • Affects network parameters (block time, epoch length, etc.)"
            echo "  • Impact: Network-wide"
            echo "  • Risk Level: Medium"
            ;;
        "upgrade")
            echo "  • Proposes protocol upgrade"
            echo "  • Impact: All nodes must upgrade"
            echo "  • Risk Level: High"
            ;;
        "treasury")
            echo "  • Affects treasury fund allocation"
            echo "  • Impact: Economic"
            echo "  • Risk Level: Medium"
            ;;
        "slashing")
            echo "  • Modifies slashing conditions"
            echo "  • Impact: Validator operations"
            echo "  • Risk Level: Medium"
            ;;
        *)
            echo "  • Standard governance proposal"
            echo "  • Impact: Varies by implementation"
            echo "  • Risk Level: Low-Medium"
            ;;
    esac
    
    echo ""
    echo -e "${CYAN}Voting Recommendations:${NC}"
    echo "  • Review the full proposal on the governance portal"
    echo "  • Consider impact on your validator operations"
    echo "  • Check community sentiment on XDC forums"
    echo "  • Ensure you understand all technical changes"
    
    echo ""
}

#==============================================================================
# Vote History
#==============================================================================

show_history() {
    echo -e "${BOLD}━━━ Governance Vote History ━━━${NC}"
    echo ""
    
    if [[ ! -f "$VOTE_HISTORY" ]]; then
        info "No vote history found."
        echo ""
        return 0
    fi
    
    local votes
    votes=$(jq -r '.votes // []' "$VOTE_HISTORY")
    local vote_count
    vote_count=$(echo "$votes" | jq 'length')
    
    if [[ "$vote_count" -eq 0 ]]; then
        info "No votes recorded."
        echo ""
        return 0
    fi
    
    echo -e "${CYAN}Recorded Votes ($vote_count):${NC}"
    echo ""
    
    printf "  ${BOLD}%-6s %-10s %-45s %-20s${NC}\n" "ID" "Vote" "Voter" "Timestamp"
    echo "─────────────────────────────────────────────────────────────────────────────────"
    
    echo "$votes" | jq -r '.[] | @base64' | while read -r vote; do
        local decoded
        decoded=$(echo "$vote" | base64 -d)
        local proposal_id
        proposal_id=$(echo "$decoded" | jq -r '.proposalId // "N/A"')
        local vote_choice
        vote_choice=$(echo "$decoded" | jq -r '.vote // "unknown"')
        local voter
        voter=$(echo "$decoded" | jq -r '.voter // "unknown"')
        local timestamp
        timestamp=$(echo "$decoded" | jq -r '.timestamp // "unknown"')
        
        local vote_color=""
        if [[ "$vote_choice" == "yes" ]]; then
            vote_color="${GREEN}"
        else
            vote_color="${RED}"
        fi
        
        printf "  %-6s ${vote_color}%-10s${NC} %-45s %-20s\n" \
            "$proposal_id" "$vote_choice" "$voter" "$timestamp"
    done
    
    echo ""
}

#==============================================================================
# Help
#==============================================================================

show_help() {
    cat << EOF
XDC Governance - Governance Participation Tools

Usage: $(basename "$0") [command] [options]

Commands:
    proposals                      List active proposals
    vote <id> <yes/no> [address]   Cast vote on proposal
    impact <id>                    Analyze proposal impact
    history                        Show past votes

Options:
    --help, -h                     Show this help message

Examples:
    # List all active proposals
    $(basename "$0") proposals

    # Cast a vote
    $(basename "$0") vote 123 yes

    # Analyze proposal impact
    $(basename "$0") impact 123

    # View vote history
    $(basename "$0") history

Description:
    Participate in XDC Network governance:
    - View active governance proposals
    - Cast votes on proposals
    - Analyze proposal impact
    - Track your voting history

Governance Portal:
    https://master.xinfin.network/governance

Note:
    Only masternode owners can participate in governance.
    Ensure your validator is registered and active.

EOF
}

#==============================================================================
# Main
#==============================================================================

main() {
    local command="${1:-}"
    
    # Parse arguments
    case "$command" in
        proposals)
            list_proposals
            ;;
        vote)
            if [[ $# -lt 3 ]]; then
                error "Usage: $(basename "$0") vote <proposal_id> <yes/no> [address]"
                exit 1
            fi
            cast_vote "$2" "$3" "${4:-}"
            ;;
        impact)
            if [[ $# -lt 2 ]]; then
                error "Usage: $(basename "$0") impact <proposal_id>"
                exit 1
            fi
            analyze_impact "$2"
            ;;
        history)
            show_history
            ;;
        --help|-h|"")
            show_help
            exit 0
            ;;
        *)
            error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
