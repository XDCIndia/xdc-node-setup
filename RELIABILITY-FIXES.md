# Reliability & Self-Healing Fixes

Fixes for issues #490, #553, and #550.

## Issue #490: Container-Native Health Checks

**Status**: ✅ Already implemented

All docker-compose files have comprehensive healthchecks using `eth_blockNumber` RPC.
Created `scripts/healthcheck.sh` as reusable script.

## Issue #553: Scripts exit on docker port conflict

**Status**: ✅ Fixed

- `scripts/fix-stuck-sync.sh` - Added port conflict recovery
- `scripts/auto-update.sh` - Enhanced stop/start with error handling

## Issue #550: GP5/Erigon 'invalid ancestor' error

**Status**: ✅ Fixed

- Created `scripts/generate-static-nodes.sh` for client-aware peer separation
- Added warnings to start scripts for GP5, Erigon, Nethermind

**Usage**:
```bash
./scripts/generate-static-nodes.sh gp5
./scripts/generate-static-nodes.sh erigon
./scripts/generate-static-nodes.sh nethermind
```
