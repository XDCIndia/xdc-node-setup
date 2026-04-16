# GP5 Node Deployment Standard

## Rule: Automatic SkyNet & Stats Integration

### Overview
All GP5 client nodes MUST be deployed with automatic SkyNet registration and ethstats visibility enabled by default.

### Deployment Requirements

#### 1. SkyNet Agent (Mandatory)
- **Auto-registration**: Node must auto-register with SkyNet on startup
- **Heartbeat**: Every 30 seconds
- **Endpoint**: https://net.xdc.network
- **API Key**: master (from environment)
- **Data Reported**:
  - Block height
  - Peer count
  - Client version
  - Network ID
  - Node name

#### 2. EthStats (Mandatory)
- **Server**: stats.xdcindia.com:3000
- **Secret**: From environment variable or config
- **Node Name**: Follow naming convention `{location}-{client}-{network}-{ip}`
- **Visibility**: Must appear on stats dashboard within 5 minutes

#### 3. Discovery Mode
- **Default**: `--nodiscover` (for controlled peer connections)
- **Static Peers**: Must include at least 2 v2.6.8 client nodes
- **Trusted Peers**: Configured via `admin_addPeer` on startup

### Implementation

#### Docker Run Template
```bash
docker run -d \
  --name {NODE_NAME} \
  --restart unless-stopped \
  -v {DATADIR}:/data \
  -p {RPC_PORT}:8545 \
  -p {P2P_PORT}:30303 \
  -p {P2P_PORT}:30303/udp \
  -e SKYNET_URL=https://net.xdc.network \
  -e SKYNET_API_KEY=master \
  -e ETHSTATS_SECRET={SECRET} \
  -e ETHSTATS_NAME={NODE_NAME} \
  anilchinchawale/gp5-xdc:v34 \
  --datadir /data \
  --networkid {51|50} \
  --http \
  --http.addr 0.0.0.0 \
  --http.port 8545 \
  --http.api eth,net,web3,XDPoS,admin \
  --syncmode full \
  --maxpeers 50 \
  --nodiscover \
  --ethstats "{NODE_NAME}:{SECRET}@stats.xdcindia.com:3000"
```

#### SkyNet Agent Script
```bash
#!/bin/bash
# Auto-generated SkyNet agent for {NODE_NAME}

NODE_NAME="{NODE_NAME}"
NETWORK="{apothem|mainnet}"
RPC_URL="http://127.0.0.1:{RPC_PORT}"
SKYNET_URL="https://net.xdc.network"
API_KEY="master"

while true; do
    BLOCK=$(curl -s -X POST $RPC_URL \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result')
    
    PEERS=$(curl -s -X POST $RPC_URL \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' | jq -r '.result')
    
    curl -s -X POST "$SKYNET_URL/api/nodes/heartbeat" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $API_KEY" \
        -d "{\"name\":\"$NODE_NAME\",\"network\":\"$NETWORK\",\"blockHeight\":\"$BLOCK\",\"peers\":\"$PEERS\",\"client\":\"gp5\",\"version\":\"v34\"}"
    
    sleep 30
done
```

### Validation Checklist

- [ ] Node appears on SkyNet within 2 minutes
- [ ] Node appears on stats.xdcindia.com within 5 minutes
- [ ] Block height increasing
- [ ] At least 2 peers connected
- [ ] XDPoS consensus working (HookReward visible in logs)

### XNS Integration

Update XNS CLI to enforce this standard:

```bash
# xdc node start should automatically:
1. Generate SkyNet agent script
2. Configure ethstats
3. Add static peers from config
4. Verify visibility after 5 minutes
5. Report status to user
```

### Enforcement

**Non-compliant deployments will:**
- Not be tracked in fleet management
- Not appear on monitoring dashboards
- Be flagged in audits

### Version History

- **v1.0** (2026-04-16): Initial standard
- Applies to: GP5 v34+
- Mandatory from: 2026-04-16
