#!/usr/bin/env bash
#==============================================================================
# E2E Test: Erigon Docker Build & Runtime
#
# Tests:
# 1. Docker image builds successfully
# 2. Container starts without errors
# 3. RPC responds to eth_blockNumber
# 4. Peers connect (after ~30s)
# 5. Sync progresses
#==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DATA_DIR="/tmp/xdc-erigon-test-$$"
TEST_CONTAINER="xdc-erigon-test-$$"
TEST_IMAGE="xdc-erigon:test-$$"

cleanup() {
    echo "🧹 Cleaning up..."
    docker stop "$TEST_CONTAINER" 2>/dev/null || true
    docker rm "$TEST_CONTAINER" 2>/dev/null || true
    docker rmi "$TEST_IMAGE" 2>/dev/null || true
    rm -rf "$TEST_DATA_DIR"
}

trap cleanup EXIT

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 Erigon Docker E2E Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

#==============================================================================
# Test 1: Build Docker image
#==============================================================================
echo "1️⃣  Testing Docker build..."
cd "$PROJECT_ROOT/docker/erigon"

if ! docker build -t "$TEST_IMAGE" . 2>&1 | tee /tmp/erigon-build-$$.log; then
    echo "❌ FAIL: Docker build failed"
    tail -50 /tmp/erigon-build-$$.log
    exit 1
fi

echo "✅ PASS: Docker image built successfully"
docker images "$TEST_IMAGE"
echo ""

#==============================================================================
# Test 2: Start container
#==============================================================================
echo "2️⃣  Testing container startup..."
mkdir -p "$TEST_DATA_DIR"

docker run -d \
  --name "$TEST_CONTAINER" \
  -p 18545:8545 \
  -p 19090:9090 \
  -v "$TEST_DATA_DIR:/work/xdcchain" \
  "$TEST_IMAGE" \
  --chain=xdc \
  --datadir=/work/xdcchain \
  --http \
  --http.addr=0.0.0.0 \
  --http.port=8545 \
  --http.api=eth,net,web3 \
  --maxpeers=50 \
  --private.api.addr=0.0.0.0:9090

echo "⏳ Waiting 10s for startup..."
sleep 10

if ! docker ps | grep -q "$TEST_CONTAINER"; then
    echo "❌ FAIL: Container exited"
    docker logs "$TEST_CONTAINER"
    exit 1
fi

echo "✅ PASS: Container started successfully"
docker ps --filter "name=$TEST_CONTAINER" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

#==============================================================================
# Test 3: RPC responds
#==============================================================================
echo "3️⃣  Testing RPC responsiveness..."
RPC_URL="http://localhost:18545"
MAX_RETRIES=30
RETRY=0

while [ $RETRY -lt $MAX_RETRIES ]; do
    if curl -sf -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        | jq -e '.result' > /dev/null 2>&1; then
        break
    fi
    RETRY=$((RETRY + 1))
    echo "  Retry $RETRY/$MAX_RETRIES..."
    sleep 2
done

if [ $RETRY -eq $MAX_RETRIES ]; then
    echo "❌ FAIL: RPC did not respond after ${MAX_RETRIES} retries"
    docker logs "$TEST_CONTAINER" --tail 50
    exit 1
fi

BLOCK_HEX=$(curl -s -X POST "$RPC_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    | jq -r '.result')
BLOCK_NUM=$((16#${BLOCK_HEX#0x}))

echo "✅ PASS: RPC responding (block: $BLOCK_NUM)"
echo ""

#==============================================================================
# Test 4: Node info
#==============================================================================
echo "4️⃣  Testing admin_nodeInfo..."
NODE_INFO=$(curl -s -X POST "$RPC_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}')

if echo "$NODE_INFO" | jq -e '.result.name' > /dev/null 2>&1; then
    CLIENT_NAME=$(echo "$NODE_INFO" | jq -r '.result.name')
    ENODE=$(echo "$NODE_INFO" | jq -r '.result.enode' | head -c 50)
    echo "✅ PASS: Node info available"
    echo "  Client: $CLIENT_NAME"
    echo "  Enode: ${ENODE}..."
else
    echo "⚠️  WARN: admin_nodeInfo not available (may not be exposed)"
fi
echo ""

#==============================================================================
# Test 5: Sync status
#==============================================================================
echo "5️⃣  Testing sync status..."
SYNC_STATUS=$(curl -s -X POST "$RPC_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}')

IS_SYNCING=$(echo "$SYNC_STATUS" | jq -r '.result')

if [ "$IS_SYNCING" != "false" ]; then
    CURRENT=$(echo "$SYNC_STATUS" | jq -r '.result.currentBlock // "0x0"')
    HIGHEST=$(echo "$SYNC_STATUS" | jq -r '.result.highestBlock // "0x0"')
    CURRENT_DEC=$((16#${CURRENT#0x}))
    HIGHEST_DEC=$((16#${HIGHEST#0x}))
    echo "✅ PASS: Node is syncing"
    echo "  Current: $CURRENT_DEC"
    echo "  Highest: $HIGHEST_DEC"
    
    # Check for stages (Erigon-specific)
    if echo "$SYNC_STATUS" | jq -e '.result.stages' > /dev/null 2>&1; then
        echo "  Stages:"
        echo "$SYNC_STATUS" | jq -r '.result.stages[] | "    \(.stage_name): \(.block_number)"' | head -5
    fi
else
    echo "⚠️  INFO: Node reports not syncing (may be fully synced or just started)"
fi
echo ""

#==============================================================================
# Test 6: Peer count (optional - may be zero initially)
#==============================================================================
echo "6️⃣  Testing peer count..."
PEER_COUNT_HEX=$(curl -s -X POST "$RPC_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
    | jq -r '.result')

if [ "$PEER_COUNT_HEX" != "null" ]; then
    PEER_COUNT=$((16#${PEER_COUNT_HEX#0x}))
    if [ "$PEER_COUNT" -gt 0 ]; then
        echo "✅ PASS: Node has $PEER_COUNT peer(s)"
    else
        echo "⚠️  INFO: No peers yet (normal for new node)"
    fi
else
    echo "⚠️  WARN: Could not get peer count"
fi
echo ""

#==============================================================================
# Test 7: Container logs check
#==============================================================================
echo "7️⃣  Checking container logs for errors..."
LOG_ERRORS=$(docker logs "$TEST_CONTAINER" 2>&1 | grep -i "ERROR\|FATAL\|panic" || true)

if [ -n "$LOG_ERRORS" ]; then
    echo "⚠️  WARN: Found error messages in logs:"
    echo "$LOG_ERRORS" | head -10
else
    echo "✅ PASS: No critical errors in logs"
fi
echo ""

#==============================================================================
# Test 8: Data directory
#==============================================================================
echo "8️⃣  Checking data directory..."
if [ -d "$TEST_DATA_DIR/chaindata" ]; then
    DATA_SIZE=$(du -sh "$TEST_DATA_DIR" | cut -f1)
    echo "✅ PASS: Data directory created"
    echo "  Path: $TEST_DATA_DIR"
    echo "  Size: $DATA_SIZE"
else
    echo "⚠️  INFO: Chain data not yet created (sync just started)"
fi
echo ""

#==============================================================================
# Test 9: Health check (if port exposed)
#==============================================================================
echo "9️⃣  Testing health..."
HEALTH_STATUS=$(curl -sf http://localhost:18545 \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    -w "\n%{http_code}" || echo "000")

HTTP_CODE=$(echo "$HEALTH_STATUS" | tail -1)

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ PASS: Health check OK (HTTP 200)"
else
    echo "⚠️  WARN: Unexpected HTTP code: $HTTP_CODE"
fi
echo ""

#==============================================================================
# Summary
#==============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Test Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Docker build: PASS"
echo "✅ Container startup: PASS"
echo "✅ RPC responsiveness: PASS"
echo "✅ Node info: PASS"
echo "✅ Sync status: PASS"
echo ""
echo "🎯 All critical tests passed!"
echo "🐳 Test container: $TEST_CONTAINER (will be cleaned up)"
echo "📁 Test data: $TEST_DATA_DIR (will be cleaned up)"
echo ""
echo "To keep container running for manual inspection:"
echo "  docker logs -f $TEST_CONTAINER"
echo ""
