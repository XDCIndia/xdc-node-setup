# Phase 1: XDC GP5 Validation Harness Design

## Objective
Build `cmd/xdc-replay` — a bit-for-bit replay tool comparing GP5 block processing against v2.6.8 archive data over the V2 switch window.

## Scope
Blocks: 56,828,250 → 56,831,400 (Apothem V2 switch ± 3 epochs)

## Comparison Points
1. Block hash (must match exactly)
2. State root (bypass expected for chainId 50/51 — document but don't fail)
3. Receipts root
4. Bloom filter
5. Author/signer result
6. Snapshot bytes at gap blocks
7. Masternode list at epoch boundaries

## Architecture

```
cmd/xdc-replay/
├── main.go              — CLI entrypoint
├── replay.go            — Core replay loop
├── comparator.go        — Diff engine
├── archive.go           — v2.6.8 archive RPC client
├── fixtures/            — Test data (small, checked in)
│   └── apothem-switch-window.json
└── ci_test.go           — CI golden fixture test
```

## CLI Design

```bash
# Full replay against live archive node
xdc-replay --network apothem --from 56828250 --to 56831400 --archive http://archive-node:8545

# Compare specific block
xdc-replay --network apothem --block 56828700 --archive http://archive-node:8545

# CI mode (uses embedded fixture, no external dependency)
xdc-replay --ci --fixture apothem-switch-window

# Output formats
xdc-replay ... --format json   # Machine-readable diff report
xdc-replay ... --format md     # Human-readable markdown report
```

## Implementation Plan

### Step 1: Archive Client (Day 1)
- RPC client for v2.6.8 archive node
- Fetch block by number/hash
- Fetch receipts
- Fetch snapshot at gap block

### Step 2: GP5 Block Processor (Day 1-2)
- Import block into ephemeral in-memory chain
- Run consensus verification (verifyHeader)
- Extract post-process state
- DO NOT write to disk — pure memory

### Step 3: Comparator (Day 2)
- Field-by-field diff
- Configurable tolerance (state root bypass for XDC)
- Structured output

### Step 4: Fixture + CI (Day 3)
- Extract 100-block fixture from archive
- Embed in binary
- CI test asserts zero diffs on fixture

### Step 5: Integration (Day 4-5)
- Makefile target: `make test-replay`
- GitHub Actions workflow
- Run on every PR to `xdc-network`

## Definition of Done
- [ ] `make test-replay` passes with embedded fixture
- [ ] Running against current `xdc-network` HEAD produces DIFFS (harness must be red before fixes land)
- [ ] CI workflow runs on PRs
- [ ] Documentation in `cmd/xdc-replay/README.md`
