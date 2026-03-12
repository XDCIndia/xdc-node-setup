#!/bin/bash
# XDC Container Health Check with XDPoS 2.0 Awareness
# Issue #490: Container-Native Health Checks & Self-Healing

set -euo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly HEALTH_STATE_FILE="${HEALTH_STATE_FILE:-/tmp/xdc-health.state}"
readonly MAX_SYNC_STALL_BLOCKS="${MAX_SYNC_STALL_BLOCKS:-10}"
readonly MAX_PEER_DROP_THRESHOLD="${MAX_PEER_DROP_THRESHOLD:-5}"
readonly CONSENSUS_TIMEOUT_SECONDS="${CONSENSUS_TIMEOUT_SECONDS:-60}"

# RPC configuration
RPC_URL="${RPC_URL:-http://localhost:8545}"

# Logging
log() { echo "[$(date -Iseconds)] $*"; }
info() { log "INFO: $*"; }
warn() { log "WARN: $*" &&2; }
error() { log "ERROR: $*" &&2; }

# Initialize state file
init_state() {
    if [[ ! -f "$HEALTH_STATE_FILE" ]]; then
        echo '{"lastBlock":0,"lastCheck":0,"syncStallCount":0,"peerDropCount":0,"lastPeers":0,"consecutiveFailures":0}' > "$HEALTH_STATE_FILE"
    fi
}

# Read state
read_state() {
    cat "$HEALTH_STATE_FILE" 2>/dev/null || echo '{}'
}

# Write state
write_state() {
    echo "$1" > "$HEALTH_STATE_FILE.tmp" && mv "$HEALTH_STATE_FILE.tmp" "$HEALTH_STATE_FILE"
}

# RPC call helper
rpc_call() {
    local method=$1
    local params=${2:-'[]'}
    
    curl -sf -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params,\"id\":1}" \
        2>/dev/null || echo '{}'
}

# Check basic RPC connectivity
check_rpc() {
    local result
    result=$(rpc_call "eth_blockNumber")
    
    if [[ -z "$result" ]] || [[ "$result" == "{}" ]]; then
        error "RPC not responding"
        return 1
    fi
    
    local block_hex
    block_hex=$(echo "$result" | jq -r '.result // "0x0"')
    
    if [[ "$block_hex" == "0x0" ]] || [[ -z "$block_hex" ]]; then
        error "Cannot get block number"
        return 1
    fi
    
    printf '%d' "${block_hex}" 2>/dev/null || echo 0
    return 0
}

# Check sync status
check_sync() {
    local result
    result=$(rpc_call "eth_syncing")
    
    local syncing
    syncing=$(echo "$result" | jq -r '.result')
    
    if [[ "$syncing" == "false" ]]; then
        echo "synced"
        return 0
    elif [[ "$syncing" == "{}" ]] || [[ -z "$syncing" ]]; then
        echo "unknown"
        return 1
    else
        # Calculate sync percentage
        local current highest
        current=$(echo "$result" | jq -r '.result.currentBlock // "0x0"')
        highest=$(echo "$result" | jq -r '.result.highestBlock // "0x0"')
        
        local current_dec highest_dec
        current_dec=$(printf '%d' "$current" 2>/dev/null || echo 0)
        highest_dec=$(printf '%d' "$highest" 2>/dev/null || echo 1)
        
        if [[ $highest_dec -gt 0 ]]; then
            local percent=$((current_dec * 100 / highest_dec))
            echo "syncing:$percent"
        else
            echo "syncing:unknown"
        fi
        return 0
    fi
}

# Check peer connectivity
check_peers() {
    local result
    result=$(rpc_call "net_peerCount")
    
    local peer_hex
    peer_hex=$(echo "$result" | jq -r '.result // "0x0"')
    printf '%d' "$peer_hex" 2>/dev/null || echo 0
}

# Check XDPoS consensus participation
check_consensus() {
    # Get masternode info
    local result
    result=$(rpc_call "XDPoS_getMasternodesByNumber" '["latest"]')
    
    if [[ -z "$result" ]] || [[ "$result" == "{}" ]]; then
        echo "unavailable"
        return 1
    fi
    
    local masternodes_count
    masternodes_count=$(echo "$result" | jq -r '.result.Masternodes | length // 0')
    
    if [[ "$masternodes_count" -lt "10" ]]; then
        echo "degraded:$masternodes_count"
        return 1
    fi
    
    echo "healthy:$masternodes_count"
    return 0
}

# Check for sync stall
check_sync_stall() {
    local current_block=$1
    local state
    state=$(read_state)
    
    local last_block last_check
    last_block=$(echo "$state" | jq -r '.lastBlock // 0')
    last_check=$(echo "$state" | jq -r '.lastCheck // 0')
    
    local now
    now=$(date +%s)
    
    # Update state
    local new_state
    new_state=$(echo "$state" | jq --arg cb "$current_block" --arg now "$now" \
        '.lastBlock = ($cb | tonumber) | .lastCheck = ($now | tonumber)')
    
    if [[ "$current_block" -le "$last_block" ]]; then
        # Block hasn't progressed
        local stall_count
        stall_count=$(echo "$state" | jq -r '.syncStallCount // 0')
        stall_count=$((stall_count + 1))
        
        new_state=$(echo "$new_state" | jq --arg sc "$stall_count" '.syncStallCount = ($sc | tonumber)')
        write_state "$new_state"
        
        if [[ $stall_count -ge $MAX_SYNC_STALL_BLOCKS ]]; then
            echo "stalled:$stall_count"
            return 1
        fi
        
        echo "slow:$stall_count"
        return 0
    else
        # Reset stall count
        new_state=$(echo "$new_state" | jq '.syncStallCount = 0')
        write_state "$new_state"
        echo "progressing"
        return 0
    fi
}

# Check for peer drops
check_peer_drops() {
    local current_peers=$1
    local state
    state=$(read_state)
    
    local last_peers
    last_peers=$(echo "$state" | jq -r '.lastPeers // 0')
    
    if [[ $current_peers -lt $last_peers ]]; then
        local drop=$((last_peers - current_peers))
        local drop_count
        drop_count=$(echo "$state" | jq -r '.peerDropCount // 0')
        drop_count=$((drop_count + drop))
        
        local new_state
        new_state=$(echo "$state" | jq --arg pc "$current_peers" --arg dc "$drop_count" \
            '.lastPeers = ($pc | tonumber) | .peerDropCount = ($dc | tonumber)')
        write_state "$new_state"
        
        if [[ $drop_count -ge $MAX_PEER_DROP_THRESHOLD ]]; then
            echo "critical:$drop_count"
            return 1
        fi
        
        echo "dropping:$drop_count"
        return 0
    else
        local new_state
        new_state=$(echo "$state" | jq --arg pc "$current_peers" '.lastPeers = ($pc | tonumber) | .peerDropCount = 0')
        write_state "$new_state"
        echo "stable"
        return 0
    fi
}

# Main health check
main() {
    init_state
    
    local exit_code=0
    local health_report=""
    
    # 1. Check RPC connectivity
    local current_block
    if ! current_block=$(check_rpc); then
        echo "UNHEALTHY: RPC failure"
        exit 1
    fi
    health_report="block:$current_block"
    
    # 2. Check sync status
    local sync_status
    sync_status=$(check_sync)
    health_report="$health_report,sync:$sync_status"
    
    # 3. Check peers
    local peer_count
    peer_count=$(check_peers)
    health_report="$health_report,peers:$peer_count"
    
    # 4. Check for peer drops
    local peer_drop_status
    peer_drop_status=$(check_peer_drops "$peer_count")
    if [[ "$peer_drop_status" == critical* ]]; then
        echo "UNHEALTHY: Critical peer drops - $health_report,$peer_drop_status"
        exit 1
    fi
    
    # 5. Check for sync stall
    local sync_stall_status
    sync_stall_status=$(check_sync_stall "$current_block")
    if [[ "$sync_stall_status" == stalled* ]]; then
        echo "UNHEALTHY: Sync stalled - $health_report,sync:$sync_stall_status"
        exit 1
    fi
    
    # 6. Check consensus (only if synced)
    if [[ "$sync_status" == "synced" ]]; then
        local consensus_status
        consensus_status=$(check_consensus)
        health_report="$health_report,consensus:$consensus_status"
        
        if [[ "$consensus_status" == degraded* ]]; then
            echo "DEGRADED: Low masternode count - $health_report"
            exit 1
        fi
    fi
    
    echo "HEALTHY: $health_report"
    exit 0
}

# Run with optional verbose output
if [[ "${1:-}" == "--verbose" ]] || [[ "${1:-}" == "-v" ]]; then
    main
else
    main > /dev/null 2>&1
    exit $?
fi
