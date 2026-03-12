# XDPoS 2.0 Validation Guide

## Overview

This document provides comprehensive guidance for validating XDPoS 2.0 consensus implementation in XDC Network nodes.

## XDPoS 2.0 Consensus Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Epoch Length | 900 blocks | Duration of each consensus epoch |
| Masternode Count | 108 | Total number of consensus participants |
| QC Threshold | 73 signatures | 2/3 + 1 of masternodes required |
| Block Time | 2 seconds | Target time between blocks |
| Gap Blocks | Variable | Blocks between epochs for handover |

## Quorum Certificate (QC) Validation

### QC Structure

```go
type QuorumCertificate struct {
    Epoch      uint64
    Round      uint64
    BlockHash  common.Hash
    Signatures []Signature
}
```

### Validation Steps

1. **Signature Count**: Verify at least 73 valid signatures
2. **Epoch/Round**: Check QC epoch/round matches current state
3. **Signer Validity**: Ensure all signers are valid masternodes
4. **Block Hash**: Verify QC references correct block
5. **No Duplicates**: Reject QCs with duplicate signatures

### Implementation Example

```go
func ValidateQC(qc *QuorumCertificate, epoch uint64, masternodes []common.Address) error {
    if len(qc.Signatures) < 73 {
        return fmt.Errorf("insufficient signatures: %d < 73", len(qc.Signatures))
    }
    
    if qc.Epoch != epoch {
        return fmt.Errorf("epoch mismatch: QC=%d, current=%d", qc.Epoch, epoch)
    }
    
    signers := make(map[common.Address]bool)
    for _, sig := range qc.Signatures {
        signer := recoverSigner(sig, qc.BlockHash)
        if !isValidMasternode(signer, masternodes) {
            return fmt.Errorf("invalid signer: %s", signer.Hex())
        }
        if signers[signer] {
            return fmt.Errorf("duplicate signature from: %s", signer.Hex())
        }
        signers[signer] = true
    }
    
    return nil
}
```

## Gap Block Handling

Gap blocks are special blocks that occur between epochs for masternode handover.

### Characteristics

- No transactions processed
- No rewards distributed
- Used for epoch state transition
- Must be handled correctly in sync

### Validation

```go
func ValidateGapBlock(block *types.Block, epoch uint64) error {
    if block.NumberU64()%900 != 0 {
        return fmt.Errorf("gap block must be at epoch boundary")
    }
    
    if len(block.Transactions()) > 0 {
        return fmt.Errorf("gap block must not contain transactions")
    }
    
    // Verify masternode list transition
    expectedMasternodes := getMasternodesForEpoch(epoch + 1)
    if !verifyMasternodeTransition(block, expectedMasternodes) {
        return fmt.Errorf("invalid masternode transition")
    }
    
    return nil
}
```

## Timeout Certificate Validation

Timeout certificates are used when consensus cannot be reached within the round time.

### Structure

```go
type TimeoutCertificate struct {
    Epoch      uint64
    Round      uint64
    HighQC     *QuorumCertificate
    Signatures []TimeoutSignature
}
```

### Validation

1. Verify timeout signatures from 2/3+ masternodes
2. Check HighQC is valid
3. Ensure round number is correct
4. Validate against current epoch

## Epoch Transition Monitoring

### Key Events

1. **Epoch Start** (block % 900 == 1)
   - New masternode list active
   - New epoch parameters apply
   - QC counter resets

2. **Epoch End** (block % 900 == 0)
   - Gap block processing
   - Masternode rewards distribution
   - Next epoch preparation

3. **Gap Block** (block % 900 == 0)
   - Handover block
   - No transactions
   - State transition

### Monitoring Checklist

- [ ] Epoch transitions occur every 900 blocks
- [ ] QC formation rate > 95%
- [ ] Timeout rate < 5%
- [ ] Gap blocks processed correctly
- [ ] Masternode list updates properly

## Vote/Timeout Race Conditions

### Scenarios

1. **Vote Arrives After Timeout**
   - Node has already moved to next round
   - Vote should be discarded
   - Log for debugging

2. **Timeout Arrives After QC**
   - QC already formed for round
   - Timeout is stale
   - Update timeout tracking

3. **Concurrent QC Formation**
   - Multiple QCs for same round
   - Select QC with most signatures
   - Alert on conflicting QCs

### Handling

```go
func HandleVote(vote *Vote, currentRound uint64) error {
    if vote.Round < currentRound {
        // Stale vote, ignore
        return nil
    }
    
    if vote.Round > currentRound {
        // Future vote, buffer or reject
        return fmt.Errorf("future vote for round %d", vote.Round)
    }
    
    // Process vote for current round
    return processVote(vote)
}
```

## Testing Scenarios

### Unit Tests

1. Valid QC with 73 signatures
2. Invalid QC with 72 signatures (should fail)
3. QC with duplicate signatures (should fail)
4. QC from invalid masternode (should fail)
5. Gap block with transactions (should fail)

### Integration Tests

1. Full epoch transition (900 blocks)
2. Network partition recovery
3. Masternode join/leave during epoch
4. Multiple client consensus participation

### Testnet Validation

1. Run validator on testnet for 10+ epochs
2. Monitor QC formation rates
3. Track timeout events
4. Verify reward distribution

## Common Issues

### Issue: QC Formation Fails

**Symptoms**: Blocks not being finalized

**Causes**:
- Network connectivity issues
- Masternode not voting
- Clock skew between nodes

**Resolution**:
1. Check network connectivity
2. Verify masternode registration
3. Synchronize system clocks

### Issue: Epoch Transition Stuck

**Symptoms**: Node stuck at epoch boundary

**Causes**:
- Gap block validation failure
- Masternode list mismatch
- State corruption

**Resolution**:
1. Check gap block processing
2. Verify masternode contract state
3. Resync from snapshot if needed

### Issue: Timeout Storm

**Symptoms**: Excessive timeout certificates

**Causes**:
- Network latency
- Slow block propagation
- Masternode performance issues

**Resolution**:
1. Optimize network configuration
2. Check peer connections
3. Monitor masternode performance

## References

- [XDPoS 2.0 Specification](https://github.com/XinFinOrg/XDPoSChain/wiki/XDPoS-2.0)
- [XDC Network Whitepaper](https://www.xinfin.org/whitepaper)
- [Consensus Implementation](https://github.com/XinFinOrg/XDPoSChain/tree/master/consensus/XDPoS)

---

*Document Version: 1.0*  
*Last Updated: March 2, 2026*
