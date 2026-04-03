# XDC Network Configuration

This document explains how to configure and run nodes on different XDC networks.

## Supported Networks

### 1. **Mainnet** (Production)
- **Chain ID:** 50
- **Network ID:** 50
- **Name:** XDC Mainnet
- **Purpose:** Production network with real XDC tokens
- **Ethstats:** stats.xinfin.network:3000

### 2. **Apothem Testnet**
- **Chain ID:** 51
- **Network ID:** 51
- **Name:** XDC Apothem Testnet
- **Purpose:** Public testnet for development and testing
- **Ethstats:** stats.apothem.network:3001
- **Faucet:** https://faucet.apothem.network

### 3. **Devnet** (Development)
- **Chain ID:** 551
- **Network ID:** 551
- **Name:** XDC Devnet
- **Purpose:** Development and experimental features
- **Note:** May be reset periodically

## Port Configuration

All networks use the same default ports but can be customized:

```bash
# P2P Communication
P2P_PORT=30303       # TCP and UDP

# RPC API
RPC_PORT=8545        # HTTP JSON-RPC
WS_PORT=8546         # WebSocket

# Dashboard
DASHBOARD_PORT=7070  # Web UI
```

## Starting a Node

### Using Docker Compose

```bash
cd /root/xdc-node-setup/docker

# Apothem Testnet (recommended for development)
NETWORK=apothem docker compose up -d

# Mainnet (production)
NETWORK=mainnet docker compose up -d

# Devnet (experimental)
NETWORK=devnet docker compose up -d
```

### Using xdc CLI

```bash
# Start Apothem node
xdc start --network apothem

# Start Mainnet node
xdc start --network mainnet

# Start Devnet node
xdc start --network devnet
```

## Network Detection

The dashboard automatically detects the network by querying the \`net_version\` RPC method. The chainId is displayed dynamically:

- **Mainnet:** Green badge with "XDC Mainnet #50"
- **Apothem:** Blue badge with "XDC Apothem Testnet #51"
- **Devnet:** Purple badge with "XDC Devnet #551"

## Configuration Files

Each network has its own configuration directory:

```
xdc-node-setup/
├── docker/
│   ├── mainnet/
│   │   ├── start-node.sh      # Network-specific startup script
│   │   ├── bootnodes.list     # Bootstrap nodes
│   │   └── genesis.json       # Genesis block
│   ├── apothem/              # (or testnet/)
│   │   ├── start-node.sh
│   │   ├── bootnodes.list
│   │   └── genesis.json
│   └── devnet/
│       ├── start-node.sh
│       ├── bootnodes.list
│       └── genesis.json
├── mainnet/
│   ├── xdcchain/             # Blockchain data
│   └── .xdc-node/            # Node configuration
├── apothem/
│   ├── xdcchain/
│   └── .xdc-node/
└── devnet/
    ├── xdcchain/
    └── .xdc-node/
```

## Network-Specific Settings

### Apothem Start Script Example

```bash
exec XDC \
  --datadir /work/xdcchain \
  --networkid 51 \
  --port 30303 \
  --syncmode full \
  --gcmode full \
  --bootnodes "$BOOTNODES" \
  --ethstats xdc-node:xdc_openscan_stats_2026@stats.xdcindia.com:443 \
  --rpc --rpcaddr 0.0.0.0 --rpcport 8545 \
  --ws --wsaddr 0.0.0.0 --wsport 8546
```

### Key Parameters

- \`--networkid\`: Must match the chain ID (50/51/551)
- \`--bootnodes\`: Network-specific bootstrap nodes
- \`--ethstats\`: Network monitoring endpoint
- \`--datadir\`: Separate data directory per network

## Switching Networks

To switch from one network to another:

1. **Stop containers:**
   ```bash
   cd /root/xdc-node-setup/docker
   docker compose down
   ```

2. **(Optional) Clean data if starting fresh:**
   ```bash
   rm -rf ../apothem/xdcchain/*
   ```

3. **Start with new network:**
   ```bash
   NETWORK=apothem docker compose up -d
   ```

4. **Verify network:**
   ```bash
   curl -X POST http://localhost:8545 \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' | jq .result
   ```

## SkyNet Monitoring

SkyNet automatically detects the network from the chainId:

```javascript
// Dashboard heartbeat includes network info
{
  "blockHeight": 1360799,
  "peerCount": 3,
  "isSyncing": true,
  "clientType": "geth",
  "version": "v2.6.8",
  "network": "apothem",    // Auto-detected
  "chainId": 51
}
```

## Troubleshooting

### Wrong Network ID

**Symptom:** Dashboard shows wrong chainId (50 instead of 51)

**Fix:**
1. Check \`NETWORK\` env var: \`docker compose config | grep NETWORK\`
2. Verify start script: \`docker exec xdc-node cat /work/start.sh | grep networkid\`
3. Restart with explicit network: \`NETWORK=apothem docker compose up -d\`

### No Peers Connecting

**Symptom:** Peer count stays at 0

**Fix:**
1. Check bootnodes are loaded: \`docker exec xdc-node cat /work/bootnodes.list\`
2. Verify P2P port is open: \`sudo ufw status | grep 30303\`
3. Check network connectivity: \`docker logs xdc-node 2>&1 | grep -i peer\`

### Dashboard Shows Wrong Network

**Fix:**
1. Clear browser cache
2. Rebuild dashboard: \`docker compose build xdc-agent\`
3. Restart: \`docker compose up -d xdc-agent\`

## Best Practices

1. **Use explicit network IDs** in start scripts (don't rely on \`--testnet\` flag alone)
2. **Separate data directories** per network to avoid conflicts
3. **Monitor via dashboard** at http://your-ip:7070
4. **Register with SkyNet** for network-wide visibility
5. **Keep bootnodes updated** from official XinFin repositories

## Resources

- **Official Repository:** https://github.com/XinFinOrg/XinFin-Node
- **Apothem Faucet:** https://faucet.apothem.network
- **SkyNet Dashboard:** https://skynet.xdcindia.com
- **Documentation:** https://docs.xdc.org

---

**Last Updated:** 2026-02-17  
**Maintainer:** XDC Node Setup Community
