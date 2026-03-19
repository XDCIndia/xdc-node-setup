# XDC Sync Fixes Documentation

## Overview

This document describes the XDCSync fixes implemented for Nethermind XDC client to enable proper synchronization with the XDC network, particularly at critical checkpoint blocks.

## XDCSync Fixes

### 1. Checkpoint Auth Bypass (Priority P2)

**Purpose**: Skip authentication validation during sync for known checkpoint blocks to enable V1/V2 transition sync.

**Implementation**: `Nethermind.Xdc/XDPoS/XDPoSConsensus.cs`

**Known Checkpoint Blocks**:
- **Block 1800**: First epoch checkpoint (XDPoS V1)
- **Block 62101**: Early network checkpoint
- **Block 3000000**: V1/V2 transition checkpoint

**Environment Variables**:
```bash
# Enable checkpoint auth bypass for sync
XDC_CHECKPOINT_AUTH_BYPASS=true

# Enable state root bypass at checkpoints
XDC_BYPASS_STATE_ROOT=true
```

**Configuration**:
```yaml
# docker-compose.nethermind.yml
environment:
  - XDC_BYPASS_STATE_ROOT=${XDC_BYPASS_STATE_ROOT:-true}
  - XDC_CHECKPOINT_AUTH_BYPASS=${XDC_CHECKPOINT_AUTH_BYPASS:-true}
  - XDC_SYNC_LOG_LEVEL=${XDC_SYNC_LOG_LEVEL:-Info}
```

### 2. PR54 State Root Cache Enhancement

**Purpose**: Improve inbound sync handling and reduce state root mismatch issues.

**Implementation**: `Nethermind.Consensus.Processing/XdcStateRootCache.cs`

**Key Enhancements**:

#### Inbound Sync Tracking
```csharp
// Update sync state for better inbound handling
XdcStateRootCache.UpdateSyncState(currentBlock, targetBlock, isFastSync);

// Check if in inbound sync mode
bool isInbound = XdcStateRootCache.IsInInboundSync(blockNumber);
```

#### Checkpoint-Aware State Root Handling
```csharp
// Check if block is a checkpoint
bool isCheckpoint = XdcStateRootCache.IsCheckpointBlock(blockNumber);
// Returns true for: 1800, 62101, 3000000
```

#### Batch Processing for Sync Mode
```csharp
// Efficient batch insert during historical sync
XdcStateRootCache.SetComputedStateRootsBatch(entries);
```

#### State Root Mismatch Detection & Recovery
```csharp
// Validate consistency
bool valid = XdcStateRootCache.ValidateStateRootConsistency(blockNumber, claimedRoot);

// Handle mismatch - clears cache from block onwards
XdcStateRootCache.HandleStateRootMismatch(blockNumber);
```

#### Outbound State Root Swapping
```csharp
// Swap state roots for outbound P2P messages
XdcStateRootCache.SwapOutboundStateRoots(headers);

// Swap single header
BlockHeader swapped = XdcStateRootCache.SwapStateRootForOutbound(header);
```

### 3. Configuration Updates

#### Docker Compose Configuration

File: `xdc-node-setup/docker/docker-compose.nethermind.yml`

```yaml
services:
  xdc-node:
    environment:
      # Enable state root bypass for checkpoint blocks during sync
      - XDC_BYPASS_STATE_ROOT=${XDC_BYPASS_STATE_ROOT:-true}
      
      # Enable checkpoint auth bypass for V1/V2 transition
      - XDC_CHECKPOINT_AUTH_BYPASS=${XDC_CHECKPOINT_AUTH_BYPASS:-true}
      
      # Sync log level for debugging
      - XDC_SYNC_LOG_LEVEL=${XDC_SYNC_LOG_LEVEL:-Info}
```

#### Environment File (.env)

```bash
# XDCSync Configuration
# ====================

# Enable state root bypass at known checkpoints (1800, 62101, 3000000)
# This allows Nethermind to sync past blocks where state roots diverge from geth
XDC_BYPASS_STATE_ROOT=true

# Enable auth bypass at checkpoints during historical sync
# Required for V1/V2 transition at block 3000000
XDC_CHECKPOINT_AUTH_BYPASS=true

# Sync logging level (Debug/Info/Warn/Error)
XDC_SYNC_LOG_LEVEL=Info
```

## Usage

### Starting Nethermind with XDCSync Fixes

```bash
# Using docker-compose with environment variables
export XDC_BYPASS_STATE_ROOT=true
export XDC_CHECKPOINT_AUTH_BYPASS=true

docker compose -f docker-compose.yml -f docker-compose.nethermind.yml up -d

# Or using the xdc-node-setup CLI
cd xdc-node-setup
./setup.sh --client nethermind --enable-sync-fixes
```

### Verifying XDCSync is Active

Check logs for XDCSync messages:

```bash
docker logs xdc-node-nethermind | grep -i "XDPoS\|XDCSync\|state root"
```

Expected output:
```
[XDPoS] Checkpoint 1800 auth validation bypassed during sync
[XDPoS] Checkpoint 3000000: XDPoS V2 (V1/V2 Transition)
XdcStateRootCache: Loaded 15000 mappings from disk
```

### Troubleshooting

#### State Root Mismatch at Checkpoint

If you see errors like:
```
State root mismatch at block 1800: expected=0x..., computed=0x...
```

Solution:
1. Enable bypass: `XDC_BYPASS_STATE_ROOT=true`
2. Restart the node
3. The cache will automatically handle the divergence

#### Stuck at Block 3000000 (V1/V2 Transition)

If sync stops at block 3000000:

1. Enable checkpoint bypass:
   ```bash
   export XDC_CHECKPOINT_AUTH_BYPASS=true
   export XDC_BYPASS_STATE_ROOT=true
   ```

2. Restart the node:
   ```bash
   docker compose restart xdc-node
   ```

3. Monitor progress:
   ```bash
   watch -n 5 'curl -s -X POST http://localhost:8556 \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
   ```

## Technical Details

### XDPoS Consensus Versions

| Version | Activation Block | Description |
|---------|-----------------|-------------|
| V1 | 0 - 2,999,999 | Original XDPoS consensus |
| V2 | 3,000,000+ | Enhanced consensus with timeout certificates |

### Checkpoint Significance

| Block | Type | Significance |
|-------|------|--------------|
| 1800 | Epoch | First checkpoint, establishes initial validator set |
| 62101 | Network | Early network stabilization point |
| 3000000 | Transition | XDPoS V1 to V2 consensus upgrade |

### State Root Divergence

XDC state roots diverge from geth at checkpoint blocks because:
1. Different EVM state transition implementations
2. Divergent gas accounting at specific transactions
3. Checkpoint contract state differences

The `XdcStateRootCache` maintains a mapping:
- `remote (geth) root → local (nethermind) root`
- This allows the node to find local state when loading headers with geth state roots

## References

- Issue: XDCSync Implementation
- PR54: State Root Cache Enhancement
- Files Modified:
  - `Nethermind.Xdc/XDPoS/XDPoSConsensus.cs` (new)
  - `Nethermind.Consensus.Processing/XdcStateRootCache.cs` (enhanced)
  - `xdc-node-setup/docker/docker-compose.nethermind.yml` (updated)
