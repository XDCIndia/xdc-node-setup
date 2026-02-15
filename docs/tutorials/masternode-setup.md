# Masternode (Validator) Setup Guide

This guide covers running an XDC Network masternode — a validator that participates in consensus and earns rewards.

## Requirements

| Requirement | Specification |
|------------|---------------|
| XDC Stake | 10,000,000 XDC |
| CPU | 4+ cores |
| RAM | 16 GB |
| Disk | 500 GB NVMe SSD |
| Network | 100 Mbps, static IP |
| Uptime | 99.9%+ recommended |

## Step 1: Set Up a Synced Node

Follow the [Getting Started](./getting-started.md) guide first. Your node **must be fully synced** before becoming a masternode.

```bash
# Verify sync status
xdc status --sync
# Wait until "Synced: true"
```

## Step 2: Create a Wallet

```bash
# Generate a new wallet (save the private key securely!)
xdc wallet create

# Or import an existing private key
xdc wallet import --key <your-private-key>
```

> ⚠️ **Security**: Never share your private key. Store it offline in a hardware wallet or encrypted vault.

## Step 3: Fund Your Wallet

Transfer **10,000,000 XDC** to your wallet address.

Verify the balance:
```bash
xdc wallet balance
```

## Step 4: Register as Masternode Candidate

```bash
xdc masternode register --name "My Masternode" --coinbase <your-wallet-address>
```

This submits a transaction to the XDC masternode smart contract.

## Step 5: Configure Masternode Mode

```bash
xdc setup --masternode
```

This updates your `config.toml` with:
- Coinbase address
- Mining/signing enabled
- Unlock account configuration

## Step 6: Restart with Masternode Config

```bash
xdc restart
```

## Step 7: Verify Masternode Status

```bash
# Check masternode status
xdc masternode status

# Verify on-chain registration
xdc masternode info
```

## Monitoring Your Masternode

```bash
# Real-time block production
xdc logs --filter "mined\|signed\|sealed"

# Health dashboard
xdc health --json | jq '{blocks: .blockHeight, peers: .peerCount, signing: .isSigning}'
```

See the [Monitoring Guide](./monitoring.md) for Prometheus + Grafana setup.

## Masternode Maintenance

### Updating
```bash
xdc update
xdc restart
```

### Key Rotation
```bash
xdc masternode rotate-key --new-coinbase <new-address>
```

### Resignation
```bash
xdc masternode resign
```

> After resignation, your stake is locked for 30 days before withdrawal.

## Security Best Practices

1. **Firewall**: Only expose P2P port (30303); block RPC from public internet
2. **SSH**: Use key-based auth, disable password login
3. **Updates**: Keep OS and Docker updated
4. **Monitoring**: Set up alerts for downtime (see [Monitoring](./monitoring.md))
5. **Backups**: Regularly backup wallet keys and `config.toml`

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Not signing blocks" | Check coinbase address matches registered wallet |
| "Peer count: 0" | Verify firewall allows port 30303 TCP/UDP |
| "Sync stuck" | Run `xdc reset --keep-config` and resync |
| "Insufficient stake" | Ensure 10M XDC at registered coinbase address |
