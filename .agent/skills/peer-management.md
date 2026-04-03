# Skill: Peer Management

How to troubleshoot P2P peer connectivity for XDC nodes.

## Diagnosing Peer Issues

### Step 1: Check peer count

```bash
# Geth (port 8545)
curl -s http://localhost:8545 \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","id":1}' | jq -r '.result | tonumber'

# Erigon (port 8547)
curl -s http://localhost:8547 \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","id":1}' | jq -r '.result | tonumber'

# Nethermind (port 8548)
curl -s http://localhost:8548 \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","id":1}' | jq -r '.result | tonumber'
```

Healthy counts:
- ≥ 10 peers: healthy
- 3–9 peers: marginal
- 1–2 peers: low, add more
- 0 peers: isolated — urgent fix needed

### Step 2: List current peers

```bash
# Geth: get connected peers and their block heights
curl -s http://localhost:8545 \
  -d '{"jsonrpc":"2.0","method":"admin_peers","id":1}' | \
  jq -r '.result[] | "\(.network.remoteAddress) head=\(.protocols.eth.difficulty)"'
```

### Step 3: Check own enode

```bash
# Get this node's enode (needed to verify it's discoverable)
curl -s http://localhost:8545 \
  -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","id":1}' | jq -r .result.enode
```

The enode must have a routable public IP, not `0.0.0.0` or `127.0.0.1`.

## Common Causes of Zero Peers

### 1. Firewall blocking P2P port

```bash
# Check if P2P port is open (from outside the server)
# Geth mainnet P2P: 30303 (TCP+UDP)
nc -zv <server-ip> 30303  # TCP
# UDP check: use nmap or an external tool

# On the server, verify port is bound
ss -tlnp | grep 30303    # TCP
ss -ulnp | grep 30303    # UDP

# Open firewall if using ufw
ufw allow 30303/tcp
ufw allow 30303/udp
```

### 2. Wrong advertised IP (NAT issue)

If behind NAT, the node may advertise a private IP. Fix:

```bash
# Geth: add --nat=extip:<public-ip>
# or: --nat=stun (auto-detect via STUN)
docker exec xdc-geth cat /proc/net/fib_trie | awk '/32 HOST/{print f} {f=$2}' | grep -v 127
```

### 3. Docker networking issues

```bash
# Check if P2P port is exposed in Docker
docker port xdc-geth | grep 30303

# If not exposed, the docker-compose.yml needs:
# ports:
#   - "30303:30303/tcp"
#   - "30303:30303/udp"

# Restart with correct port mapping
docker-compose -f docker/mainnet/geth/docker-compose.yml down
docker-compose -f docker/mainnet/geth/docker-compose.yml up -d
```

### 4. No bootnodes configured

```bash
# Check current bootnodes in config
docker inspect xdc-geth | jq -r '.[].Args[]' | grep bootnode

# For geth: check --bootnodes flag
# For erigon: check --bootnodes flag
# For nethermind: check Discovery.Bootnodes in JSON config
```

## Adding Peers Manually

### Geth — add via RPC

```bash
# Add a specific peer
curl -s http://localhost:8545 \
  -d '{"jsonrpc":"2.0","method":"admin_addPeer",
       "params":["enode://PUBKEY@IP:PORT"],
       "id":1}' | jq .

# Add trusted peer (won't be dropped)
curl -s http://localhost:8545 \
  -d '{"jsonrpc":"2.0","method":"admin_addTrustedPeer",
       "params":["enode://PUBKEY@IP:PORT"],
       "id":1}' | jq .

# Add all mainnet bootnodes
BOOTNODES=$(jq -r '.geth[]' configs/bootnodes-mainnet.json 2>/dev/null || echo "")
for enode in ${BOOTNODES}; do
  echo "Adding: ${enode}"
  curl -s http://localhost:8545 \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addPeer\",\"params\":[\"${enode}\"],\"id\":1}" \
    | jq -r .result
done
```

### Erigon — add via config (no runtime addPeer)

Erigon does not support `admin_addPeer`. Use static peers in the config:

```bash
# Edit erigon start command to add --staticpeers
docker exec xdc-erigon cat /proc/1/cmdline | tr '\0' '\n'

# Or modify docker-compose.yml command:
# --staticpeers="enode://...@ip:port,enode://...@ip:port"

# Restart erigon
docker restart xdc-erigon
```

### Nethermind — add via JSON config

```bash
# Edit discovery config
jq '.Discovery.Bootnodes = ["enode://...@ip:port"]' \
  configs/nethermind-mainnet.json > /tmp/nm.json && \
  mv /tmp/nm.json configs/nethermind-mainnet.json

# Restart
docker restart xdc-nethermind
```

## Bootnode Sources

```bash
# Official XDC mainnet bootnodes
cat configs/bootnodes-mainnet.json

# Official XDC testnet (apothem) bootnodes
cat configs/bootnodes-testnet.json

# Optimized bootnode selection (benchmark-tested)
bash scripts/bootnode-optimize.sh --client geth --network mainnet
```

## Peer Quality Check

Not all peers are equal. Check if connected peers are synced:

```bash
# List peers with their block heights
curl -s http://localhost:8545 \
  -d '{"jsonrpc":"2.0","method":"admin_peers","id":1}' | \
  jq -r '.result[] | "\(.id[:10]) \(.network.remoteAddress) eth_head=\(.protocols.eth.head // "n/a")"'

# If all peers have lower block heights than you, they can't help you sync
# Add peers from known-good sources (XDC Foundation nodes, well-known validators)
```

## Persistent Peer Issues

If a node repeatedly loses peers after restart:

1. **Check logs for banning**: `grep -i "ban\|drop\|disconnect" container_logs`
2. **IP blocklist**: Some IPs may be blocked by peers; try with a different server IP
3. **Version mismatch**: Ensure your node version supports current protocol version
4. **Test from another location**: Some ISPs block ETH P2P traffic; try a VPS

## Reference: P2P Port Assignments

| Client     | P2P TCP | P2P UDP | Apothem TCP | Apothem UDP |
|------------|---------|---------|-------------|-------------|
| geth       | 30303   | 30303   | 30313       | 30313       |
| erigon     | 30305   | 30305   | 30315       | 30315       |
| nethermind | 30304   | 30304   | 30314       | 30314       |
| reth       | 30306   | 30306   | 30316       | 30316       |
