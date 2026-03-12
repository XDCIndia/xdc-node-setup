# XDC vs Ethereum Storage Analysis

## Executive Summary

This document provides a detailed analysis of storage-related features and requirements in XDPoSChain compared to go-ethereum. Storage is one of the areas where XDC has significant technical debt due to its older codebase fork.

---

## 1. Database Backends

### Current Support Matrix

| Backend | XDPoSChain | go-ethereum | Notes |
|---------|-----------|-------------|-------|
| **LevelDB** | ✅ Full | ✅ Full | Default for both |
| **Pebble** | ❌ None | ✅ Full | Modern replacement |
| **MemoryDB** | ✅ Test only | ✅ Test only | In-memory |
| **PathDB** | ❌ None | ✅ Full | State storage |

### LevelDB Implementation (XDC)

```go
// ethdb/leveldb/leveldb.go
package leveldb

import (
    "github.com/syndtr/goleveldb/leveldb"
    "github.com/syndtr/goleveldb/leveldb/opt"
)

const (
    minCache   = 16  // MB
    minHandles = 16
)

type Database struct {
    fn string
    db *leveldb.DB
    // Metrics...
}
```

**Configuration:**
- Cache: Split 50/50 read/write
- Write buffer: 25% of cache
- Open files: Configurable (default 16+)

### Missing: Pebble Backend

**Why Pebble matters:**
- Written in Go (no CGO)
- Better concurrent write performance
- Improved LSM-tree compaction
- Lower memory footprint
- Active development by CockroachDB

**Impact on XDC:**
- ~20-30% worse write performance
- Higher memory usage
- Slower sync times

---

## 2. State Storage Architecture

### XDPoSChain: Hash-Based State

```go
// trie/database.go
type Database struct {
    diskdb ethdb.KeyValueStore    // Persistent storage
    cleans  *fastcache.Cache       // Clean node cache
    dirties map[common.Hash]*cachedNode  // Dirty nodes
    preimages map[common.Hash][]byte     // Preimages
    // ...
}
```

**Characteristics:**
- Merkle Patricia Trie with hash keys
- Reference counting for garbage collection
- Periodic flushing to disk
- Preimage storage (can be disabled)

### Ethereum: Path-Based State (PathDB)

```go
// go-ethereum/triedb/pathdb/database.go (reference)
type Database struct {
    // Layered structure
    // - Disk layer (persistent)
    // - Diff layers (in-memory changes)
    // - State snapshots
}
```

**Advantages over hash-based:**
- No reference counting needed
- Natural pruning via path keys
- ~50% storage reduction
- Faster state access
- Simpler architecture

### Comparison Table

| Feature | Hash-Based (XDC) | Path-Based (ETH) |
|---------|-----------------|------------------|
| Storage keys | Keccak256 hashes | Trie paths |
| Pruning | Complex GC | Natural via paths |
| Disk usage | Higher (~2x) | Lower |
| Memory usage | Higher | Lower |
| Implementation | Complex | Simpler |
| Sync speed | Slower | Faster |

---

## 3. State Pruning Strategies

### XDPoSChain: Limited Pruning

**Current state:**
```go
// trie/database.go
func (db *Database) Commit(node common.Hash, report bool) error {
    // Flush dirty nodes to disk
    // Limited garbage collection
}
```

**Limitations:**
- No online pruning
- Archive nodes keep everything
- Full nodes accumulate state
- Manual intervention required

### Ethereum: Full Pruning Support

| Mode | XDC | ETH | Description |
|------|-----|-----|-------------|
| Archive | ✅ | ✅ | Keep all history |
| Full | ✅ | ✅ | Keep recent + archive old |
| Full + Pruning | ❌ | ✅ | Automatic cleanup |
| Snap sync | ⚠️ | ✅ | Fast initial sync |

### Pruning Gap Analysis

**Missing in XDC:**
1. **Online state pruning**
   - Automatic removal of old state
   - Reduces disk usage over time
   
2. **Snapshot-based pruning**
   - Efficient state diffing
   - Fast cleanup

3. **Flat database layout**
   - Direct account/storage access
   - No trie traversal needed

---

## 4. State Snapshots

### XDPoSChain Implementation

```go
// core/state/snapshot (partial implementation)
// Recent commits show snapshot work:
// 45d89bd4d 2025-06-17 trie: faster snapshot generation
// 1f05c3e5f 2025-06-17 trie: reuse dirty data for snapshot
```

**Status:** Partial implementation
- Snapshot generation exists
- Limited integration
- No snapshot-based sync

### Ethereum Snapshots

- Full snapshot system
- Snap sync protocol
- Snapshot-based state healing
- Async generation

---

## 5. Sync Modes & Storage Impact

### XDPoSChain Sync Options

```go
// From cmd/XDC/main.go and ethconfig/config.go
const (
    FullSync  = iota  // Full block processing
    FastSync          // Download state, then process
    SnapSync          // Snapshot-based (limited)
    LightSync         // Removed/deprecated
)
```

### Storage Requirements by Mode

| Mode | XDC (Est.) | ETH (Est.) | Notes |
|------|-----------|-----------|-------|
| Archive | 2-3 TB | 15+ TB | All history |
| Full | 500 GB | 1 TB | Recent state |
| Snap | 300 GB | 500 GB | Minimal start |
| Light | N/A | N/A | Not supported |

### Snap Sync Status

**XDPoSChain:**
- Partial implementation
- Recent trie improvements (June 2025)
- No dedicated snap protocol

**Ethereum:**
- Full snap protocol
- Dedicated `eth/protocols/snap` package
- Efficient state healing

---

## 6. Trie Implementation Details

### XDC Trie Structure

```go
// trie/trie.go
type Trie struct {
    root  node
    db    *Database
    // ...
}

// Node types
type (
    fullNode struct {
        Children [17]node
        flags    nodeFlag
    }
    shortNode struct {
        Key   []byte
        Val   node
        flags nodeFlag
    }
    hashNode  []byte
    valueNode []byte
)
```

### Secure Trie (State Trie)

```go
// trie/secure_trie.go
type SecureTrie struct {
    trie             Trie
    db               DatabaseReader
    secKeyCache      map[string][]byte
    secKeyCacheOwner *SecureTrie
}
```

**Features:**
- Keccak256 key hashing
- Preimage storage (optional)
- Cache for recent lookups

### Stack Trie (For Block Building)

```go
// trie/stacktrie.go
type StackTrie struct {
    root       *stNode
    writer     func(owner common.Hash, path []byte, hash common.Hash, blob []byte)
    // ...
}
```

Used for:
- Efficient block state root calculation
- Lower memory during block processing

---

## 7. Storage Metrics & Monitoring

### XDC Metrics

```go
// trie/database.go
var (
    memcacheCleanHitMeter   = metrics.NewRegisteredMeter("trie/memcache/clean/hit", nil)
    memcacheCleanMissMeter  = metrics.NewRegisteredMeter("trie/memcache/clean/miss", nil)
    memcacheDirtyHitMeter   = metrics.NewRegisteredMeter("trie/memcache/dirty/hit", nil)
    memcacheFlushTimeTimer  = metrics.NewRegisteredResettingTimer("trie/memcache/flush/time", nil)
    // ...
)
```

**Available metrics:**
- Cache hit/miss rates
- Flush times
- GC statistics
- Node counts

### Missing Metrics

Compared to go-ethereum:
- PathDB-specific metrics
- Pebble performance metrics
- State healing metrics
- Snap sync progress

---

## 8. Optimization Recommendations

### Priority 1: Path-Based State Storage

**Implementation effort:** High (3-6 months)

**Benefits:**
- 40-50% storage reduction
- Faster state operations
- Simpler pruning
- Better performance

**Migration path:**
1. Implement pathdb package
2. Add migration tool
3. Dual-mode operation period
4. Full migration

### Priority 2: Pebble Database Backend

**Implementation effort:** Medium (1-2 months)

**Benefits:**
- 20-30% write performance improvement
- Lower memory usage
- Better concurrency
- Native Go (no CGO)

**Implementation:**
```go
// ethdb/pebble/pebble.go (to be created)
package pebble

import "github.com/cockroachdb/pebble"

type Database struct {
    db *pebble.DB
    // ...
}
```

### Priority 3: Online State Pruning

**Implementation effort:** High (2-4 months)

**Benefits:**
- Automatic storage management
- Reduced operational costs
- No manual intervention

### Priority 4: Flat Database Layout

**Implementation effort:** Medium (2-3 months)

**Benefits:**
- Direct state access
- Faster reads
- Reduced trie overhead

---

## 9. Storage Cost Analysis

### Current XDC Node Costs (Estimated)

| Node Type | Storage | Monthly Cost (AWS) |
|-----------|---------|-------------------|
| Archive | 3 TB | $300-400 |
| Full | 500 GB | $50-75 |
| Validator | 500 GB | $50-75 |

### With Optimizations

| Node Type | Current | Optimized | Savings |
|-----------|---------|-----------|---------|
| Archive | 3 TB | 1.5 TB | 50% |
| Full | 500 GB | 300 GB | 40% |
| Validator | 500 GB | 300 GB | 40% |

**Annual savings for 108 masternodes:**
- Current: ~$80,000/year
- Optimized: ~$48,000/year
- **Savings: ~$32,000/year**

---

## 10. Conclusion

### Current State

XDPoSChain uses an older hash-based state storage architecture with LevelDB only. This results in:
- Higher storage requirements
- Slower sync times
- No automatic pruning
- Limited optimization options

### Critical Gaps

1. **No path-based state** - Major architectural limitation
2. **No Pebble support** - Missing modern database backend
3. **Limited pruning** - Manual storage management required
4. **Incomplete snap sync** - Slower initial sync

### Recommended Roadmap

| Quarter | Priority | Feature | Impact |
|---------|----------|---------|--------|
| Q1 2025 | P0 | Blob transactions | Critical for L2s |
| Q2 2025 | P1 | Pebble backend | Performance |
| Q3 2025 | P1 | Path-based state | Storage reduction |
| Q4 2025 | P2 | Online pruning | Operations |
| Q1 2026 | P2 | Flat layout | Performance |

---

*Document generated: February 2026*
