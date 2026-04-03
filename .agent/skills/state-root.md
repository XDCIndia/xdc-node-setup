# Skill: State Root Bypass

Understanding and handling state root mismatches in XDC Network.

## What Is a State Root?

The state root is a Merkle Patricia Trie root hash included in every block header.
It commits to the complete EVM state (all accounts, balances, contract storage).

When a client imports a block, it:
1. Executes all transactions
2. Computes the resulting state trie root
3. Verifies it matches the block header's `stateRoot` field

If they don't match: **state root mismatch** — the client rejects the block.

## Why Does It Happen on XDC?

### 1. XDPoS Epoch Transition Divergence

At epoch switch blocks (every 900 blocks), XDPoS v2 executes special state transitions:
- Updates the validator set
- Processes masternode penalties
- Locks/unlocks staking rewards

If clients implement these transitions slightly differently, they produce different state roots.

**This is the most common cause** on XDC — one client (usually Erigon) handles epoch blocks differently than geth.

### 2. Precompile Differences

XDC has custom precompiles. If a client doesn't implement them identically, state diverges.

### 3. Gas Calculation Edge Cases

Subtle differences in gas refund or EIP implementation across forks.

## Identifying a State Root Mismatch

```bash
# In geth logs:
grep "state root mismatch\|bad block\|invalid block" <(docker logs xdc-geth 2>&1) | tail -5

# In Erigon logs:
docker logs xdc-erigon 2>&1 | grep -i "wrong state root\|state root\|bad block" | tail -5

# Cross-verify: get block hash from both clients at a specific height
BLOCK_NUM=75000000
HEX_BLOCK=$(printf '0x%x' ${BLOCK_NUM})

GETH_HASH=$(curl -s http://localhost:8545 \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${HEX_BLOCK}\",false],\"id\":1}" \
  | jq -r '.result.hash')

ERIGON_HASH=$(curl -s http://localhost:8547 \
  -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"${HEX_BLOCK}\",false],\"id\":1}" \
  | jq -r '.result.hash')

echo "geth:   ${GETH_HASH}"
echo "erigon: ${ERIGON_HASH}"
[[ "${GETH_HASH}" == "${ERIGON_HASH}" ]] && echo "MATCH ✓" || echo "MISMATCH ✗"
```

## The State Root Bypass Approach

When a known-bad block causes a mismatch on a specific client, there are two strategies:

### Strategy A: Skip the Bad Block (Bad Block List)

Geth supports a `--badBlockHash` flag. The block is skipped and re-downloaded from peers.

```bash
# Find the bad block hash from logs
BAD_BLOCK=$(docker logs xdc-geth 2>&1 | grep "bad block" | grep -oP '0x[a-f0-9]{64}' | tail -1)
echo "Bad block: ${BAD_BLOCK}"

# Add to bad block list via environment variable / docker-compose
# In docker-compose.yml, add to command:
# --badBlockHash=${BAD_BLOCK}

# Or add to geth data directory bad-blocks file
docker stop xdc-geth
echo "${BAD_BLOCK}" >> /data/geth/bad-blocks
docker start xdc-geth
```

### Strategy B: Bypass State Root Validation (Erigon)

Erigon supports a `--state.root.bypass.list` flag with a file listing blocks where state root checks should be bypassed.

```bash
# Create bypass list file
cat > /data/erigon/state-root-bypass.txt <<EOF
# Block numbers where state root check is bypassed
# Format: one block number per line
75000000
75000900
EOF

# Add to Erigon start command in docker-compose.yml:
# --state.root.bypass.list=/data/erigon/state-root-bypass.txt

# Restart Erigon
docker stop xdc-erigon
docker start xdc-erigon
```

### Strategy C: Patch the Client

For systematic divergences (like epoch block handling), the proper fix is a code patch.

```bash
# Check if a patch exists in the client repo
cd /path/to/xdc-erigon
git log --oneline --grep="state root\|epoch" | head -10

# Apply patch if available
git cherry-pick <commit-hash>
docker build -t xdc-erigon:patched .
# Update docker-compose to use patched image
```

## When to Use Each Strategy

| Scenario | Strategy |
|----------|---------|
| One-off bad block, rare | Strategy A (bad block list) |
| Erigon diverges at epoch blocks | Strategy B (bypass list) |
| Systematic divergence, many blocks | Strategy C (patch) |
| Uncertain | Cross-verify with 3+ clients first |

## Finding the Divergence Point

```bash
# Binary search for the first diverging block
bash scripts/block-divergence.sh --client1 geth --client2 erigon \
  --start 74990000 --end 75000000
```

The script will binary-search for the exact block where hashes diverge.

## Reporting to XDC Core Team

If you find a genuine state root divergence (not a client bug):

1. Document: exact block number, block hash, client versions, state roots from each client
2. Open issue at https://github.com/XDCIndia/xdc-node-setup/issues
3. Tag with `consensus-bug` label
4. Include output of `scripts/block-divergence.sh`

## Known Bypass Blocks

```bash
# Check configs/healing-playbook-v2.json for known bypass blocks
jq '.known_bad_blocks' configs/healing-playbook-v2.json 2>/dev/null || echo "none documented"
```

## Prevention

- Keep all clients updated — most state root issues are fixed in newer versions
- Monitor cross-client block hash agreement with `scripts/cross-verify.sh`
- Set up alerts for block height divergence > 10 blocks between clients
