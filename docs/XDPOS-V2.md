# XDPoS v2 Deep Dive Guide

> Comprehensive guide to XDC Network's XDPoS v2 consensus mechanism

**Author:** anilcinchawale \<anil24593@gmail.com\>  
**Version:** 2.1.0  
**Last Updated:** February 11, 2026

---

## Table of Contents

1. [How XDPoS v2 Works](#how-xdpos-v2-works)
2. [Masternode Requirements](#masternode-requirements)
3. [Rotation System](#rotation-system)
4. [Penalty System](#penalty-system)
5. [Governance Process](#governance-process)
6. [Block Structure](#block-structure)
7. [Monitoring Tools](#monitoring-tools)

---

## How XDPoS v2 Works

### Overview

XDPoS (XinFin Delegated Proof of Stake) v2 is the consensus mechanism powering the XDC Network. It combines delegated staking with a rotating validator set to achieve:

- **Fast finality**: ~2 second block times
- **High throughput**: 2000+ TPS
- **Energy efficiency**: No mining required
- **Byzantine fault tolerance**: Tolerates up to 1/3 malicious validators

### Key Concepts

#### Epochs

- **Duration**: 900 blocks (~30 minutes)
- **Purpose**: Validator set refresh and reward distribution
- **Calculation**: `epoch = block_number / 900`

```
Epoch 0:    Blocks 0-899
Epoch 1:    Blocks 900-1799
Epoch 2:    Blocks 1800-2699
...
```

#### Rounds

Each epoch is divided into 10 rounds (90 blocks each):

```
Round 0:    Blocks 0-89    (within epoch)
Round 1:    Blocks 90-179
...
Round 9:    Blocks 810-899
```

#### Voting Rounds

Within each round, validators take turns proposing blocks:
- Each masternode gets a turn to propose based on deterministic ordering
- Other validators vote on the proposed block
- Block is finalized after sufficient votes

### Consensus Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Round 0   │────►│   Round 1   │────►│   Round 2   │
│  (90 blks)  │     │  (90 blks)  │     │  (90 blks)  │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       ▼                   ▼                   ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ MN #1 Signs │     │ MN #2 Signs │     │ MN #3 Signs │
│ + 2/3 Votes │     │ + 2/3 Votes │     │ + 2/3 Votes │
└─────────────┘     └─────────────┘     └─────────────┘
```

### Checkpoint Mechanism

- Every epoch boundary (multiples of 900) is a **checkpoint**
- Checkpoints provide **absolute finality**
- Once a checkpoint is reached, blocks cannot be reverted without 1/3+ validators colluding

```bash
# Monitor checkpoint status
xdc consensus finality
```

---

## Masternode Requirements

### Minimum Requirements

| Requirement | Value | Notes |
|-------------|-------|-------|
| **Stake** | 10,000,000 XDC | Locked for masternode duration |
| **Hardware** | 16 CPU / 32 GB RAM / 1 TB SSD | Higher is better |
| **Uptime** | 99.9%+ | Critical for rewards |
| **Network** | 100 Mbps symmetric | Low latency preferred |

### Staking Process

1. **Acquire XDC**: Purchase 10M+ XDC from exchanges
2. **Setup Node**: Run full node with masternode configuration
3. **Submit KYC**: Complete masternode registration
4. **Lock Stake**: Deposit 10M XDC to masternode contract
5. **Wait Activation**: Join validator set at next epoch

### Registration Commands

```bash
# Check stake requirements
xdc masternode setup

# Register as candidate (requires 10M XDC)
xdc masternode register

# Check registration status
xdc masternode status
```

### Validator Set Size

- **Maximum**: 108 masternodes
- **Minimum**: 21 masternodes
- **Current**: Varies (check with `xdc consensus rotation`)

---

## Rotation System

### Deterministic Ordering

Masternode rotation uses a deterministic algorithm based on:
1. **Previous epoch's random seed** (from Randomize contract)
2. **Masternode list** (sorted by address)
3. **Epoch number** (for offset calculation)

```
rotation_order = shuffle(masternodes, seed=randomize_output)
```

### Rotation Schedule

Within each epoch, masternodes rotate every 90 blocks (10 rounds):

```
Epoch N:
  Round 0 (blocks 0-89):     MN #1, #2, #3...
  Round 1 (blocks 90-179):   MN #11, #12, #13...
  Round 2 (blocks 180-269):  MN #21, #22, #23...
  ...
  Round 9 (blocks 810-899):  MN #91, #92, #93...
```

### Monitoring Rotation

```bash
# Show current rotation schedule
xdc consensus rotation

# Watch rotation in real-time
xdc consensus --watch
```

**Output Example:**
```
Cycle 0 (Current):  xdcf2e2...89d1b [SIGNING NOW]
Cycle 1 (Next):     xdc1234...67890 [NEXT]
Cycle 2:            xdcabcd...efabcd [UPCOMING]
```

### Turn Frequency

Each masternode signs approximately:
- **Per epoch**: ~8-10 blocks (depends on total validators)
- **Per day**: ~400-500 blocks
- **Expected blocks/day**: 8-10

---

## Penalty System

### Penalty Types

| Code | Name | Trigger | Consequence |
|------|------|---------|-------------|
| 1 | **MissedBlocks** | Miss > threshold blocks | Reduced rewards |
| 2 | **ForkDetected** | Sign on fork | Slashing |
| 3 | **DoubleSign** | Sign two blocks at same height | Severe slashing |
| 4 | **Offline** | Extended downtime | Removal from set |

### Missed Block Thresholds

- **Warning**: 3+ missed blocks in epoch
- **Penalty**: 5+ missed blocks in epoch
- **Removal**: 50%+ blocks missed over multiple epochs

### Slashing Severity

```
Missed Blocks:    1-5% reward reduction
Fork Signing:     10% stake slashed + removal
Double Signing:   100% stake slashed + permanent ban
```

### Monitoring Penalties

```bash
# Check for penalties
xdc consensus penalties

# Monitor for slashing events
xdc rewards slashing

# Check missed blocks
xdc rewards missed
```

### Avoiding Penalties

1. **Maintain Uptime**: Use clustering for HA
2. **Sync Status**: Ensure node is fully synced
3. **Network Stability**: Redundant internet connections
4. **Clock Sync**: Keep system time accurate (NTP)
5. **Hardware**: Use reliable hardware with monitoring

---

## Governance Process

### Overview

XDC Network uses on-chain governance for protocol upgrades and parameter changes.

### Governance Parameters

| Parameter | Value |
|-----------|-------|
| **Proposal Threshold** | 10,000 XDC |
| **Voting Period** | 720 blocks (~24 hours) |
| **Execution Delay** | 48 hours after passing |
| **Quorum** | 51% of validators |

### Proposal Types

1. **Parameter Change**: Modify network parameters
2. **Protocol Upgrade**: Code upgrades and hard forks
3. **Treasury**: Fund allocation from treasury
4. **Slashing**: Modify slashing conditions

### Voting Process

```
1. Submit Proposal → 10K XDC deposit
       │
       ▼
2. Voting Period (720 blocks)
   ├── Validators vote YES/NO
   └── Track vote count
       │
       ▼
3. Quorum Check
   ├── ≥51% participation?
   └── Majority YES?
       │
       ▼
4. Execution Delay (48 hours)
   └── Time to prepare
       │
       ▼
5. Execution
   └── Changes applied
```

### Governance Commands

```bash
# List active proposals
xdc governance proposals

# View proposal details
xdc governance impact --id 123

# Cast vote (requires masternode)
xdc governance vote --id 123 --vote yes

# View voting history
xdc governance history
```

### Participation Requirements

- Only **active masternodes** can vote
- One vote per masternode
- Vote weight is equal (not stake-weighted)
- Abstention is allowed but counts against quorum

---

## Block Structure

### XDPoS v2 Block Header

```go
type Header struct {
    ParentHash   common.Hash    // Previous block hash
    UncleHash    common.Hash    // Empty in XDPoS
    Coinbase     common.Address // Block proposer
    Root         common.Hash    // State root
    TxHash       common.Hash    // Transaction root
    ReceiptHash  common.Hash    // Receipt root
    Bloom        Bloom          // Logs bloom
    Difficulty   *big.Int       // Always 1 in XDPoS
    Number       *big.Int       // Block number
    GasLimit     uint64         // Gas limit
    GasUsed      uint64         // Gas used
    Time         uint64         // Timestamp
    Extra        []byte         // XDPoS data (signatures, votes)
    MixDigest    common.Hash    // Unused
    Nonce        BlockNonce     // Unused
}
```

### Extra Data Format

The `Extra` field contains XDPoS-specific data:

```
Bytes 0-31:     Vanity (validator info)
Bytes 32-96:    Proposer signature
Bytes 97+:      Validator signatures (voting)
```

### Block Production Timing

```
Block N:
  Time: T
  Proposer: Determined by rotation
  
Block N+1:
  Time: T + 2 seconds (target)
  Proposer: Next in rotation
```

### Uncle Blocks

XDPoS v2 does **not** have uncle/orphan blocks like Ethereum. Each block has exactly one parent.

---

## Monitoring Tools

### Consensus Monitor

```bash
# Show all consensus info
xdc consensus

# Watch mode (updates every 5 seconds)
xdc consensus --watch

# Specific metrics
xdc consensus epoch       # Epoch progress
xdc consensus rounds      # Round tracking
xdc consensus votes       # Vote counts
xdc consensus finality    # Checkpoint status
xdc consensus rotation    # Masternode schedule
xdc consensus penalties   # Active penalties
```

### Network Statistics

```bash
# Validator rankings
xdc network-stats rankings

# Network aggregates
xdc network-stats aggregate

# Peer reputation
xdc network-stats reputation

# Geographic distribution
xdc network-stats geo

# Client diversity
xdc network-stats clients
```

### Dashboard

Access the web dashboard for visual monitoring:

```bash
# Start dashboard
xdc dashboard

# Access at http://localhost:3000
```

**Consensus Page Features:**
- Epoch progress bar with countdown
- Real-time block production
- Masternode rotation visualization
- Penalty alerts
- Vote monitoring

### Alerting

Configure alerts for critical events:

```yaml
# monitoring/alerts.yml
- alert: XDCEpochChange
  expr: changes(xdpos_epoch_number[15m]) > 0
  
- alert: XDCPenaltyIssued
  expr: xdpos_penalties_active > 0
  
- alert: XDCMasternodeMissedBlocks
  expr: increase(xdpos_masternode_missed_blocks[1h]) > 5
```

### API Endpoints

The dashboard provides JSON APIs:

```bash
# Consensus data
curl http://localhost:3000/api/consensus

# Network stats
curl http://localhost:3000/api/network-stats

# Masternode rewards
curl http://localhost:3000/api/masternode/rewards
```

---

## Advanced Topics

### Random Number Generation

XDPoS v2 uses a commit-reveal scheme for randomness:

1. **Commit Phase**: Validators submit hashed random values
2. **Reveal Phase**: Validators reveal their values
3. **Combine**: XOR of all revealed values = epoch random seed

This prevents manipulation while ensuring unpredictability.

### Finality Guarantees

- **Probabilistic**: After 1 confirmation (next block)
- **Economic**: After checkpoint (irreversible without 1/3+ collusion)
- **Absolute**: After 2 checkpoints (practically impossible to revert)

### Fork Choice Rule

XDC uses the **GHOST** (Greedy Heaviest Observed SubTree) rule:
- Select the chain with most total difficulty
- In ties, prefer the chain with more checkpoint blocks
- Locally, prefer the chain received first

### Network Partition Handling

During network splits:
1. Each partition continues with available validators
2. If either partition has < 2/3 validators, it halts
3. When partition heals, longer chain wins
4. Short chain validators re-sync

---

## Configuration Reference

### XDPoS v2 Parameters

See `/opt/xdc-node/configs/xdpos-v2.json`:

```json
{
  "epoch": {
    "duration": 900,
    "blockTime": 2,
    "estimatedDuration": "30 minutes"
  },
  "masternode": {
    "threshold": 10000000,
    "maxValidators": 108,
    "minValidators": 21
  },
  "penalty": {
    "threshold": 5
  },
  "checkpoint": {
    "period": 900,
    "finalityThreshold": 2
  }
}
```

### Contract Addresses

| Contract | Address | Purpose |
|----------|---------|---------|
| MasternodeRegistration | 0x00...0088 | Stake management |
| ValidatorSet | 0x00...0089 | Validator list |
| Randomize | 0x00...0090 | Random seed |
| Slashing | 0x00...0091 | Penalty enforcement |

---

## Troubleshooting

### Node Not Producing Blocks

1. Check if in validator set: `xdc consensus rotation`
2. Verify stake is locked: `xdc masternode status`
3. Ensure sync complete: `xdc sync status`
4. Check for penalties: `xdc consensus penalties`

### Sync Stuck at Epoch Boundary

1. Restart node: `xdc restart`
2. Check peers: `xdc network peers`
3. Verify network config: `cat /etc/xdc-node/xdc.conf`

### Governance Vote Not Counting

1. Verify masternode is active: `xdc masternode status`
2. Check vote was submitted: `xdc governance history`
3. Ensure within voting period

---

## Resources

- **XDC Documentation**: https://docs.xdc.network
- **GitHub**: https://github.com/XinFinOrg/XDPoSChain
- **Explorer**: https://explorer.xinfin.network
- **Governance**: https://master.xinfin.network/governance

---

*This guide is maintained by Anil Chinchawale for the XDC Community*
