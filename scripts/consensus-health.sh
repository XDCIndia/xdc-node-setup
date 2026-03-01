#!/bin/bash
# Comprehensive consensus health check for XDC masternodes

set -euo pipefail

RPC_ENDPOINT="${RPC_ENDPOINT:-http://localhost:8545}"
HEALTH_LOG="/var/log/xdc/consensus-health.log"
METRICS_FILE="/var/lib/xdc/consensus-metrics.prom"

# Thresholds
MIN_PEER_COUNT=3
QC_TIMEOUT_THRESHOLD=5
MAX_TIMEOUT_CERTIFICATES=2

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Ensure log directory exists
mkdir -p "$(dirname "$HEALTH_LOG")"
mkdir -p "$(dirname "$METRICS_FILE")"

log() {
    echo "[$(date -Iseconds)] $1" | tee -a "$HEALTH_LOG"
}

json_rpc() {
    local method=$1
    local params=${2:-'[]'}
    curl -s -X POST "$RPC_ENDPOINT" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}"
}

check_vote_participation() {
    log "Checking vote participation..."
    
    local current_block_hex=$(json_rpc "eth_blockNumber" | jq -r '.result')
    if [[ -z "$current_block_hex" || "$current_block_hex" == "null" ]]; then
        log "${RED}ERROR${NC} Failed to get current block"
        return 1
    fi
    
    local current_block=$((16#${current_block_hex#0x}))
    
    # Calculate epoch position
    local epoch_length=900
    local epoch_number=$((current_block / epoch_length))
    local epoch_position=$((current_block % epoch_length))
    local blocks_until_epoch_end=$((epoch_length - epoch_position))
    
    log "Current block: $current_block"
    log "Epoch: $epoch_number (position: $epoch_position/$epoch_length)"
    log "Blocks until epoch end: $blocks_until_epoch_end"
    
    # Check if in gap period (last 450 blocks of epoch)
    if [[ $blocks_until_epoch_end -le 450 ]]; then
        log "${YELLOW}WARN${NC} Currently in gap period - voting disabled"
    fi
    
    # Try to get vote statistics (this requires XDPoS-specific RPC method)
    local vote_stats=$(json_rpc "XDPoS_getVoteStats" "[\"$current_block_hex\"]" 2>/dev/null || echo '{"result":null}')
    local node_votes=$(echo "$vote_stats" | jq -r '.result.nodeVotes // 0')
    
    if [[ $node_votes -gt 0 ]]; then
        log "${GREEN}OK${NC} Node has cast $node_votes votes in current epoch"
        return 0
    else
        log "${YELLOW}WARN${NC} Node has not cast any votes in current epoch (may not be a masternode)"
        return 1
    fi
}

check_qc_formation() {
    log "Checking QC formation..."
    
    # Try to get latest QCs (requires XDPoS-specific RPC)
    local latest_qcs=$(json_rpc "XDPoS_getLatestQCs" 2>/dev/null || echo '{"result":[]}')
    local qc_count=$(echo "$latest_qcs" | jq '.result | length')
    
    if [[ $qc_count -eq 0 ]]; then
        log "${YELLOW}WARN${NC} No QCs found (may not be implemented in client)"
        return 1
    fi
    
    log "${GREEN}OK${NC} Found $qc_count recent QCs"
    
    # Check QC timestamps
    local now=$(date +%s)
    local oldest_qc_time=$(echo "$latest_qcs" | jq -r '.result[-1].timestamp // 0')
    
    if [[ $oldest_qc_time -gt 0 ]]; then
        local qc_age=$((now - oldest_qc_time))
        
        if [[ $qc_age -gt $((QC_TIMEOUT_THRESHOLD * 60)) ]]; then
            log "${YELLOW}WARN${NC} Oldest QC is ${qc_age}s old (threshold: ${QC_TIMEOUT_THRESHOLD}m)"
            return 1
        else
            log "${GREEN}OK${NC} QCs are recent (oldest: ${qc_age}s)"
            return 0
        fi
    fi
    
    return 0
}

check_timeout_certificates() {
    log "Checking timeout certificates..."
    
    local timeout_certs=$(json_rpc "XDPoS_getTimeoutCerts" 2>/dev/null || echo '{"result":[]}')
    local tc_count=$(echo "$timeout_certs" | jq '.result | length')
    
    log "Found $tc_count timeout certificates"
    
    if [[ $tc_count -gt $MAX_TIMEOUT_CERTIFICATES ]]; then
        log "${YELLOW}WARN${NC} High number of timeout certificates detected"
        return 1
    else
        log "${GREEN}OK${NC} Timeout certificate count is within normal range"
        return 0
    fi
}

check_peer_connectivity() {
    log "Checking peer connectivity..."
    
    local peers=$(json_rpc "admin_peers" 2>/dev/null || json_rpc "net_peerCount")
    
    # Handle both admin_peers and net_peerCount responses
    local peer_count
    if echo "$peers" | jq -e '.result | type == "array"' >/dev/null 2>&1; then
        peer_count=$(echo "$peers" | jq '.result | length')
    else
        local peer_hex=$(echo "$peers" | jq -r '.result')
        peer_count=$((16#${peer_hex#0x}))
    fi
    
    log "Connected peers: $peer_count"
    
    if [[ $peer_count -lt $MIN_PEER_COUNT ]]; then
        log "${RED}WARN${NC} Low peer count ($peer_count < $MIN_PEER_COUNT)"
        return 1
    else
        log "${GREEN}OK${NC} Peer count is healthy"
        return 0
    fi
}

check_block_proposal_eligibility() {
    log "Checking block proposal eligibility..."
    
    # Get masternode info (requires XDPoS-specific RPC)
    local masternode_info=$(json_rpc "XDPoS_getMasternodes" 2>/dev/null || echo '{"result":[]}')
    local is_masternode=$(echo "$masternode_info" | jq '.result | map(select(.isSelf == true)) | length')
    
    if [[ $is_masternode -eq 0 ]]; then
        log "${YELLOW}INFO${NC} Node is not a masternode"
        return 0
    fi
    
    local current_block_hex=$(json_rpc "eth_blockNumber" | jq -r '.result')
    local round_info=$(json_rpc "XDPoS_getRoundInfo" "[\"$current_block_hex\"]" 2>/dev/null || echo '{"result":{}}')
    local is_proposer=$(echo "$round_info" | jq -r '.result.isProposer // false')
    
    if [[ "$is_proposer" == "true" ]]; then
        log "${GREEN}OK${NC} Node is current round proposer"
    else
        log "${YELLOW}INFO${NC} Node is not current proposer"
    fi
    
    return 0
}

export_metrics() {
    local vote_ok=${1:-0}
    local qc_ok=${2:-0}
    local tc_ok=${3:-0}
    local peer_ok=${4:-0}
    
    cat > "$METRICS_FILE" << EOF
# HELP xdc_consensus_vote_participation Whether node is voting
# TYPE xdc_consensus_vote_participation gauge
xdc_consensus_vote_participation $vote_ok

# HELP xdc_consensus_qc_healthy Whether QC formation is healthy
# TYPE xdc_consensus_qc_healthy gauge
xdc_consensus_qc_healthy $qc_ok

# HELP xdc_consensus_timeout_certs_healthy Whether timeout cert count is normal
# TYPE xdc_consensus_timeout_certs_healthy gauge
xdc_consensus_timeout_certs_healthy $tc_ok

# HELP xdc_consensus_peer_healthy Whether peer count is healthy
# TYPE xdc_consensus_peer_healthy gauge
xdc_consensus_peer_healthy $peer_ok
EOF
}

# Main execution
main() {
    log "========================================="
    log "Starting consensus health check"
    log "========================================="
    
    local overall_status=0
    local vote_ok=0
    local qc_ok=0
    local tc_ok=0
    local peer_ok=0
    
    if check_vote_participation; then vote_ok=1; else overall_status=1; fi
    if check_qc_formation; then qc_ok=1; else overall_status=1; fi
    if check_timeout_certificates; then tc_ok=1; else overall_status=1; fi
    if check_peer_connectivity; then peer_ok=1; else overall_status=1; fi
    check_block_proposal_eligibility || overall_status=1
    
    export_metrics $vote_ok $qc_ok $tc_ok $peer_ok
    
    log "========================================="
    if [[ $overall_status -eq 0 ]]; then
        log "${GREEN}Consensus health check PASSED${NC}"
    else
        log "${YELLOW}Consensus health check FAILED - review warnings above${NC}"
    fi
    log "========================================="
    
    return $overall_status
}

main "$@"
