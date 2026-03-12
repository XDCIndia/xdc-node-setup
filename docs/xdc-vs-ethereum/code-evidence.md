# XDPoSChain Codebase Evidence

This document contains concrete code evidence from the XDPoSChain repository supporting the analysis in the comparison documents.

---

## 1. EIP-4844 Blob Transaction Gap

### Evidence: Missing BlobTxType

**File:** `core/types/transaction.go`

```go
// Transaction types.
const (
	LegacyTxType = iota      // 0
	AccessListTxType         // 1 - EIP-2930
	DynamicFeeTxType         // 2 - EIP-1559
	// BlobTxType = 3        // MISSING! EIP-4844
)
```

### Evidence: decodeTyped missing blob support

```go
func (tx *Transaction) decodeTyped(b []byte) (TxData, error) {
	if len(b) <= 1 {
		return nil, errShortTypedTx
	}
	switch b[0] {
	case AccessListTxType:
		var inner AccessListTx
		err := rlp.DecodeBytes(b[1:], &inner)
		return &inner, err
	case DynamicFeeTxType:
		var inner DynamicFeeTx
		err := rlp.DecodeBytes(b[1:], &inner)
		return &inner, err
	default:
		return nil, ErrTxTypeNotSupported  // BlobTxType falls here!
	}
}
```

### Evidence: KZG4844 exists but unused for transactions

**File:** `crypto/kzg4844/kzg4844.go`

```go
// Package kzg4844 implements the KZG crypto for EIP-4844.
package kzg4844

// Blob represents a 4844 data blob.
type Blob [4096 * 32]byte

// Commitment is a KZG commitment to a blob.
type Commitment [48]byte

// Proof is a KZG proof.
type Proof [48]byte
```

The KZG crypto library is present but **not integrated into transaction processing**.

---

## 2. EIP-1559 Implementation Status

### Evidence: Mainnet not scheduled

**File:** `common/constants.mainnet.go`

```go
var MaintnetConstant = constant{
	// ...
	berlinBlock:            big.NewInt(76321000), // Target 19th June 2024
	londonBlock:            big.NewInt(76321000), // Target 19th June 2024
	mergeBlock:             big.NewInt(76321000), // Target 19th June 2024
	shanghaiBlock:          big.NewInt(76321000), // Target 19th June 2024
	// ...
	eip1559Block:           big.NewInt(9999999999), // NOT SCHEDULED
	cancunBlock:            big.NewInt(9999999999), // NOT SCHEDULED
	// ...
}
```

### Evidence: Testnet scheduled

**File:** `common/constants.testnet.go`

```go
var TestnetConstant = constant{
	// ...
	eip1559Block:           big.NewInt(71550000), // Target 14th Feb 2025
	cancunBlock:            big.NewInt(71551800), // Target Feb 2025
	// ...
}
```

### Evidence: EIP-1559 verification exists

**File:** `consensus/misc/eip1559/eip1559.go`

```go
// VerifyEip1559Header verifies some header attributes which were changed in EIP-1559
func VerifyEip1559Header(config *params.ChainConfig, header *types.Header) error {
	if !config.IsEIP1559(header.Number) {
		return nil
	}
	// Verify base fee
	// ...
}
```

---

## 3. Cancun Opcodes Implemented

### Evidence: Cancun instruction set

**File:** `core/vm/jump_table.go`

```go
func newCancunInstructionSet() JumpTable {
	instructionSet := newEip1559InstructionSet()
	enable4844(&instructionSet)  // EIP-4844 (BLOBHASH opcode)
	enable7516(&instructionSet)  // EIP-7516 (BLOBBASEFEE opcode)
	enable1153(&instructionSet)  // EIP-1153 (Transient Storage)
	enable5656(&instructionSet)  // EIP-5656 (MCOPY opcode)
	enable6780(&instructionSet)  // EIP-6780 (SELFDESTRUCT only in same tx)
	return validate(instructionSet)
}
```

### Evidence: BLOBHASH opcode

```go
func enable4844(jt *JumpTable) {
	jt[BLOBHASH] = &operation{
		execute:     opBlobHash,
		constantGas: GasFastestStep,
		dynamicGas:  gasBlobHash,
		minStack:    minStack(1, 1),
		maxStack:    maxStack(1, 1),
	}
}
```

---

## 4. Database Backend Limitations

### Evidence: Only LevelDB supported

**File:** `ethdb/leveldb/leveldb.go`

```go
// Package leveldb implements the key-value database layer based on LevelDB.
package leveldb

import (
	"github.com/syndtr/goleveldb/leveldb"
	"github.com/syndtr/goleveldb/leveldb/opt"
	"github.com/syndtr/goleveldb/leveldb/filter"
)
```

**No Pebble package exists:**
```bash
$ ls ethdb/
batch.go  database.go  dbtest  iterator.go  leveldb  memorydb
# No pebble/ directory!
```

### Evidence: No path-based state

**File:** `trie/database.go`

```go
type Database struct {
	diskdb ethdb.KeyValueStore // Persistent storage
	cleans  *fastcache.Cache    // GC friendly memory cache
	dirties map[common.Hash]*cachedNode // Dirty trie nodes
	// ...
}
```

Uses `common.Hash` keys (hash-based), not path-based.

---

## 5. XDPoS Consensus Implementation

### Evidence: Dual engine architecture

**File:** `consensus/XDPoS/XDPoS.go`

```go
type XDPoS struct {
	config *params.XDPoSConfig
	db     ethdb.Database
	
	// The exact consensus engine with different versions
	EngineV1 *engine_v1.XDPoS_v1
	EngineV2 *engine_v2.XDPoS_v2
	
	// ...
}

func New(chainConfig *params.ChainConfig, db ethdb.Database) *XDPoS {
	// ...
	return &XDPoS{
		EngineV1: engine_v1.New(chainConfig, db),
		EngineV2: engine_v2.New(chainConfig, db, minePeriodCh, newRoundCh),
	}
}
```

### Evidence: V2 configuration

```go
type V2Config struct {
	MaxMasternodes       int     // 108 max validators
	CertThreshold        float64 // 0.667 = 66.7%
	TimeoutPeriod        int     // 30 seconds
	MinePeriod           int     // 2 seconds
	// ...
}
```

---

## 6. Precompiled Contracts

### Evidence: XDC-specific precompiles

**File:** `core/vm/contracts.go`

```go
var PrecompiledContractsIstanbul = map[common.Address]PrecompiledContract{
	// Standard precompiles 1-9...
	common.BytesToAddress([]byte{1}):  &ecrecover{},
	common.BytesToAddress([]byte{2}):  &sha256hash{},
	// ...
	common.BytesToAddress([]byte{9}):  &blake2F{},
	
	// XDC-specific precompiles
	common.BytesToAddress([]byte{30}): &ringSignatureVerifier{},
	common.BytesToAddress([]byte{40}): &bulletproofVerifier{},
	common.BytesToAddress([]byte{41}): &XDCxLastPrice{},
	common.BytesToAddress([]byte{42}): &XDCxEpochPrice{},
}
```

---

## 7. Recent Development Activity

### Evidence: Active Cancun development

From git log analysis:

```
42defdb58 2025-03-11 Merge pull request #905 from JukLee0ira/support_cancun
91cbe818e 2025-04-01 common, params: define cancun block for testnet
30195e88e 2025-02-11 core/vm: enable cancun instruction set
1b9bae9a9 2025-02-17 Merge pull request #843 from gzliudan/eip4844
511a372f1 2025-02-10 core/vm: BLOBHASH opcode 0x49
af4a3b0f9 2025-02-10 core/vm: implement BLOBBASEFEE opcode 0x4a
240de8428 2025-02-05 core/vm: define cancun + enable 1153 (tstore/tload)
```

### Evidence: Trie improvements

```
416c5cb7d 2025-06-25 trie: upgrade for snap protocol #21482
937b3d75e 2025-06-21 core, eth, trie: prepare trie sync for path based operation
45d89bd4d 2025-06-17 trie: faster snapshot generation
```

---

## 8. Missing Features Evidence

### Evidence: No GraphQL

```bash
$ find . -name "*.go" | xargs grep -l "graphql" 2>/dev/null
# No results
```

### Evidence: No pathdb

```bash
$ ls trie/
committer.go  database.go  encoding.go  errors.go  hasher.go  
iterator.go  node.go  proof.go  secure_trie.go  stacktrie.go  
sync.go  trie.go
# No pathdb/ directory!
```

### Evidence: No Pebble

```bash
$ find . -name "*pebble*" 2>/dev/null
# No results
```

---

*Document generated from XDPoSChain commit 0b257ecb0*
