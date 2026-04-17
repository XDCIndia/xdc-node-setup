# GP5 Apothem Deployment Plan — Nodiscover + Private Peer Network

> **Generated for XDCIndia Fleet** | Target: Isolate GP5 Apothem sync to fleet-only peers

---

## 1. Server Selection

### Primary Deployment Target: `xdc07` (65.21.71.4)
**Why:**
- Tier A (20 cores, 1.9TB disk, 62GB RAM) — highest sync throughput
- Existing GP5 v21 node at **56,828,699** blocks (stuck with quorum cert issue) — we replace with fresh latest build
- Already has OpenScan infra (ClickHouse, Redis, Dashboard) for monitoring
- Best candidate for 2000+ bl/s testing

### Backup / Secondary: `local` (95.217.56.168)
**Why:**
- Tier A (20 cores, 1.9TB disk)
- Has v2.6.8 reference at **70,110,450** blocks — can serve as a trusted sync source
- Multi-client testbed — can host parallel nodiscover node

### Optional Tertiary: `xdc01` (95.217.112.125)
**Why:**
- Designated canary for `geth-pr5`
- Currently has PR5 agent; can host a stable nodiscover baseline

---

## 2. Pre-Deployment: Extract Enodes from Fleet

Each fleet node needs a **nodekey** to derive its **enode URL**. Run this on every server that will join the private network:

```bash
#!/usr/bin/env bash
# extract-enodes.sh — Run on each fleet node

NODE_KEY_FILE="${1:-/data/XDC/nodekey}"
DATA_DIR="${2:-/data}"

if [ ! -f "$NODE_KEY_FILE" ]; then
    echo "Generating new nodekey..."
    docker run --rm -v "$DATA_DIR:/data" anilchinchawale/gp5-xdc:latest \
        sh -c "XDC --datadir /data account new 2>/dev/null; cat /data/XDC/nodekey" > /tmp/nodekey.raw
fi

# Extract enode from running container or generate from nodekey
docker run --rm -v "$DATA_DIR:/data" anilchinchawale/gp5-xdc:latest \
    sh -c "XDC --datadir /data --networkid 51 --nodiscover --port 30303 2>&1 &
           sleep 3
           XDC attach /data/XDC.ipc --exec 'admin.nodeInfo.enode'
           kill %1 2>/dev/null"
```

### Run on each server:

```bash
# xdc07
ssh -p 12141 root@65.21.71.4 'bash -s' < extract-enodes.sh /mnt/data/xdc07-gp5-apothem-v21/XDC/nodekey /mnt/data/xdc07-gp5-apothem-v21

# local
ssh -p 12141 root@95.217.56.168 'bash -s' < extract-enodes.sh /mnt/data/apothem/v268/XDC/nodekey /mnt/data/apothem/v268

# xdc01
ssh -p 12141 root@95.217.112.125 'bash -s' < extract-enodes.sh /work/xdcchain/XDC/nodekey /work/xdcchain

# xdc02
ssh -p 12141 root@135.181.117.109 'bash -s' < extract-enodes.sh /mnt/data/apothem/gp5/XDC/nodekey /mnt/data/apothem/gp5

# xdc03
ssh -p 12141 root@167.235.13.113 'bash -s' < extract-enodes.sh /mnt/data/apothem/gp5/XDC/nodekey /mnt/data/apothem/gp5

# APO
ssh -p 52316 root@185.180.220.183 'bash -s' < extract-enodes.sh /data/XDC/nodekey /data

# prod
ssh -p 12141 root@65.21.27.213 'bash -s' < extract-enodes.sh /mnt/data/apothem/gp5/XDC/nodekey /mnt/data/apothem/gp5
```

**Expected output per server:**
```
enode://<64-hex-pubkey>@<ip>:<port>?discport=0
```

Collect all enodes into `static-nodes.json` (see Section 4).

---

## 3. Docker Compose Template (Nodiscover + Private Peers)

```yaml
# docker-compose.gp5-apothem-nodiscover.yml
version: "3.8"

services:
  geth:
    image: anilchinchawale/gp5-xdc:latest
    container_name: ${CONTAINER_NAME:-xdc-gp5-apothem-nodiscover}
    restart: unless-stopped
    network_mode: host
    volumes:
      - ${DATA_DIR:-./data}:/data
      - ./static-nodes.json:/data/static-nodes.json:ro
    environment:
      - NETWORK=apothem
      - STATS_HOST=stats.xdcindia.com:443
      - STATS_SECRET=xdc_openscan_stats_2026
    command: >
      /usr/local/bin/XDC
      --apothem
      --syncmode snap
      --state.scheme path
      --datadir /data
      --nodiscover
      --netrestrict 95.217.0.0/16,65.21.0.0/16,135.181.0.0/16,167.235.0.0/16,185.180.0.0/16
      --maxpeers 25
      --cache 12288
      --cache.database 50
      --cache.snapshot 20
      --snapshot
      --rpc
      --rpcaddr 0.0.0.0
      --rpcport ${RPC_PORT:-9545}
      --rpcapi eth,net,web3,txpool,debug,admin
      --rpcvhosts "*"
      --rpccorsdomain "*"
      --ws
      --wsaddr 0.0.0.0
      --wsport ${WS_PORT:-9546}
      --wsapi eth,net,web3
      --wsorigins "*"
      --ethstats "${CONTAINER_NAME}:xdc_openscan_stats_2026@stats.xdcindia.com:443"
      --verbosity 3
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "5"

  skynet:
    image: anilchinchawale/xdc-agent:latest
    container_name: skyone-${CONTAINER_NAME}
    restart: unless-stopped
    network_mode: host
    environment:
      - TARGET_CONTAINER=${CONTAINER_NAME}
      - STATSD_HOST=127.0.0.1
      - SKYNET_URL=https://skynet.xdcindia.com/api
    depends_on:
      - geth
```

### Key Flags Explained

| Flag | Purpose |
|------|---------|
| `--nodiscover` | **Disables DHT/bootstrap node discovery** — no public peers auto-found |
| `--netrestrict` | **IP whitelist** — only allows P2P connections from XDCIndia's IP ranges |
| `--maxpeers 25` | Limit peers to fleet size + buffer |
| `--state.scheme path` | PBSS for maximum sync speed |
| `--syncmode snap` | Snap sync for fastest catch-up |
| `--cache 12288` | Maximize cache on Tier A servers |

### Port Allocation (Per-Server)

| Server | Container Name | RPC Port | WS Port | P2P Port |
|--------|---------------|----------|---------|----------|
| xdc07 | `xdc07-gp5-nodiscover-apothem-4` | 9545 | 9546 | 30303 |
| local | `local-gp5-nodiscover-apothem-168` | 9547 | 9548 | 30304 |
| xdc01 | `xdc01-gp5-nodiscover-apothem-125` | 9549 | 9550 | 30305 |
| xdc02 | `xdc02-gp5-nodiscover-apothem-109` | 9551 | 9552 | 30306 |
| xdc03 | `xdc03-gp5-nodiscover-apothem-113` | 9553 | 9554 | 30307 |
| APO | `apo-gp5-nodiscover-apothem-183` | 9555 | 9556 | 30308 |
| prod | `prod-gp5-nodiscover-apothem-213` | 9557 | 9558 | 30309 |

> **Note:** Using `network_mode: host` avoids Docker NAT overhead for P2P. Each server gets a unique P2P port to prevent conflicts.

---

## 4. static-nodes.json

Create this file on every node at `/data/static-nodes.json` (mounted in compose):

```json
[
  "enode://<xdc07-pubkey>@65.21.71.4:30303?discport=0",
  "enode://<local-pubkey>@95.217.56.168:30304?discport=0",
  "enode://<xdc01-pubkey>@95.217.112.125:30305?discport=0",
  "enode://<xdc02-pubkey>@135.181.117.109:30306?discport=0",
  "enode://<xdc03-pubkey>@167.235.13.113:30307?discport=0",
  "enode://<apo-pubkey>@185.180.220.183:30308?discport=0",
  "enode://<prod-pubkey>@65.21.27.213:30309?discport=0"
]
```

**Generation script:**

```bash
#!/usr/bin/env bash
# generate-static-nodes.sh
# Run after collecting all enodes from Section 2

cat > static-nodes.json <<'EOF'
[
  "enode://PASTE_XDC07_ENODE_HERE",
  "enode://PASTE_LOCAL_ENODE_HERE",
  "enode://PASTE_XDC01_ENODE_HERE",
  "enode://PASTE_XDC02_ENODE_HERE",
  "enode://PASTE_XDC03_ENODE_HERE",
  "enode://PASTE_APO_ENODE_HERE",
  "enode://PASTE_PROD_ENODE_HERE"
]
EOF

# Distribute to all servers
for server in 65.21.71.4 95.217.56.168 95.217.112.125 135.181.117.109 167.235.13.113 185.180.220.183 65.21.27.213; do
  port=12141
  [ "$server" = "185.180.220.183" ] && port=52316
  scp -P $port static-nodes.json root@$server:/opt/xns/static-nodes.json
done
```

---

## 5. Deployment Steps

### Step 1: Prepare xdc07 (Primary)

```bash
ssh -p 12141 root@65.21.71.4 <<'EOF'
  # Stop and remove the stuck v21 node (keep data if possible)
  docker stop xdc07-gp5-apothem-v21 || true
  docker rm -f xdc07-gp5-apothem-v21 || true

  # Clean up the crashing snap-PBSS node
  docker rm -f xdc07-geth-snap-pbss-apothem-4 || true

  # Create deployment directory
  mkdir -p /opt/xns/xdc07-gp5-nodiscover-apothem-4
  cd /opt/xns/xdc07-gp5-nodiscover-apothem-4

  # Copy static nodes config
  cp /opt/xns/static-nodes.json .

  # Set environment
  export CONTAINER_NAME=xdc07-gp5-nodiscover-apothem-4
  export DATA_DIR=/mnt/data/xdc07-gp5-nodiscover-apothem-4
  export RPC_PORT=9545
  export WS_PORT=9546

  # Create data dir if not exists
  mkdir -p $DATA_DIR

  # Deploy
  docker compose -f docker-compose.gp5-apothem-nodiscover.yml up -d
EOF
```

### Step 2: Prepare local (Secondary + Sync Source)

```bash
ssh -p 12141 root@95.217.56.168 <<'EOF'
  # Remove unhealthy PR5 and Erigon to free resources
  docker rm -f xdc03-geth-pr5 test-erigon-full-hbss-apothem-168 || true
  docker volume prune -f || true

  mkdir -p /opt/xns/local-gp5-nodiscover-apothem-168
  cd /opt/xns/local-gp5-nodiscover-apothem-168
  cp /opt/xns/static-nodes.json .

  export CONTAINER_NAME=local-gp5-nodiscover-apothem-168
  export DATA_DIR=/mnt/data/local-gp5-nodiscover-apothem-168
  export RPC_PORT=9547
  export WS_PORT=9548

  mkdir -p $DATA_DIR
  docker compose -f docker-compose.gp5-apothem-nodiscover.yml up -d
EOF
```

### Step 3: Prepare APO (Clean Baseline)

```bash
ssh -p 52316 root@185.180.220.183 <<'EOF'
  # Remove stopped containers
  docker rm -f apo-geth-full-hbss-apothem-183 apo-geth-full-hbss-mainnet-183 || true
  docker volume prune -f || true

  mkdir -p /opt/xns/apo-gp5-nodiscover-apothem-183
  cd /opt/xns/apo-gp5-nodiscover-apothem-183
  cp /opt/xns/static-nodes.json .

  export CONTAINER_NAME=apo-gp5-nodiscover-apothem-183
  export DATA_DIR=/mnt/data/apo-gp5-nodiscover-apothem-183
  export RPC_PORT=9555
  export WS_PORT=9556

  mkdir -p $DATA_DIR
  docker compose -f docker-compose.gp5-apothem-nodiscover.yml up -d
EOF
```

---

## 6. Verification: Confirm Private Network Isolation

### 6a: Check Connected Peers

```bash
# On any node, query admin.peers
curl -s -X POST http://localhost:9545 -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"admin_peers","params":[],"id":1}' | jq '.result[] | {enode: .enode, network: .network.remoteAddress}'
```

**Expected:** Only enodes from `static-nodes.json` with IPs in the fleet ranges.

**If public peers appear:**
- Check `--nodiscover` is in the command
- Verify `static-nodes.json` is mounted at `/data/static-nodes.json`
- Check for `--bootnodes` flag overriding static nodes

### 6b: Check Node Discovery is Disabled

```bash
curl -s -X POST http://localhost:9545 -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' | jq '.result | {enode: .enode, ports: .ports, ip: .ip}'
```

**Expected:** `enode` shows the correct IP and port. `discport` should be `0` or absent.

### 6c: Check Peer Count

```bash
curl -s -X POST http://localhost:9545 -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' | jq -r '.result' | xargs printf "%d\n"
```

**Expected:** Between 1 and 6 (other fleet nodes that are online). Should be 0 if no other fleet nodes are running GP5.

### 6d: Firewall Verification (Optional but Recommended)

```bash
# On each server, block non-fleet P2P at iptables level
iptables -A INPUT -p tcp --dport 30303:30309 -s 95.217.0.0/16 -j ACCEPT
iptables -A INPUT -p tcp --dport 30303:30309 -s 65.21.0.0/16 -j ACCEPT
iptables -A INPUT -p tcp --dport 30303:30309 -s 135.181.0.0/16 -j ACCEPT
iptables -A INPUT -p tcp --dport 30303:30309 -s 167.235.0.0/16 -j ACCEPT
iptables -A INPUT -p tcp --dport 30303:30309 -s 185.180.0.0/16 -j ACCEPT
iptables -A INPUT -p tcp --dport 30303:30309 -j DROP

# Save rules
iptables-save > /etc/iptables/rules.v4 2>/dev/null || iptables-save > /root/iptables-backup.rules
```

---

## 7. Sync Strategy: Use Fleet as Sync Sources

### Option A: Snap Sync from Fleet (Fastest)

With `--syncmode snap` and `--nodiscover`, the node will:
1. Download headers from the highest fleet peer
2. Download state snapshots from fleet peers
3. Backfill blocks after state sync

**Expected speed:** 1000–2000+ bl/s on Tier A servers during snap sync phase.

### Option B: Copy Chaindata from Existing Node (Instant)

If you want to skip sync entirely, copy chaindata from `local`'s v2.6.8 node:

```bash
# On local (source)
tar czf /mnt/data/apothem-v268-chaindata-70m.tar.gz -C /mnt/data/apothem/v268/XDC chaindata

# On xdc07 (destination)
scp -P 12141 root@95.217.56.168:/mnt/data/apothem-v268-chaindata-70m.tar.gz /tmp/
mkdir -p /mnt/data/xdc07-gp5-nodiscover-apothem-4/XDC
tar xzf /tmp/apothem-v268-chaindata-70m.tar.gz -C /mnt/data/xdc07-gp5-nodiscover-apothem-4/XDC

# IMPORTANT: Remove v2.6.8-specific state before starting GP5
rm -rf /mnt/data/xdc07-gp5-nodiscover-apothem-4/XDC/nodes/*/triecache
```

**Warning:** v2.6.8 chaindata may not be 100% compatible with GP5. Test on a backup first.

---

## 8. Rollback Plan

### If Node Gets Stuck (like xdc07 v21 at 56.8M)

```bash
# 1. Check logs for quorum cert or consensus errors
docker logs --tail 50 xdc07-gp5-nodiscover-apothem-4 | grep -iE "err|error|fail|quorum|certificate"

# 2. If stuck at snapshot boundary:
# Option A: Reset to earlier snapshot and re-sync
docker stop xdc07-gp5-nodiscover-apothem-4
rm -rf /mnt/data/xdc07-gp5-nodiscover-apothem-4/XDC/chaindata/*
docker start xdc07-gp5-nodiscover-apothem-4

# Option B: Switch to full sync instead of snap
# Edit compose: --syncmode full instead of snap
# This is slower but more resilient

# Option C: Revert to v34 or previous known-good image
docker stop xdc07-gp5-nodiscover-apothem-4
docker rm xdc07-gp5-nodiscover-apothem-4
# Edit compose to use anilchinchawale/gp5-xdc:v34
docker compose up -d
```

### If State Corrupts

```bash
# Emergency rollback: remove chaindata, keep nodekey
ssh -p 12141 root@65.21.71.4 <<'EOF'
  docker stop xdc07-gp5-nodiscover-apothem-4
  mv /mnt/data/xdc07-gp5-nodiscover-apothem-4/XDC/chaindata /mnt/data/xdc07-gp5-nodiscover-apothem-4/XDC/chaindata.bak.$(date +%s)
  mkdir -p /mnt/data/xdc07-gp5-nodiscover-apothem-4/XDC/chaindata
  docker start xdc07-gp5-nodiscover-apothem-4
EOF
```

### If Private Network Leaks Public Peers

```bash
# Emergency: kill all peers and restart with stricter config
ssh -p 12141 root@65.21.71.4 <<'EOF'
  docker stop xdc07-gp5-nodiscover-apothem-4
  
  # Add iptables block immediately
  iptables -A INPUT -p tcp --dport 30303 -m iprange ! --src-range 95.217.0.0-95.217.255.255 -j DROP
  iptables -A INPUT -p tcp --dport 30303 -m iprange ! --src-range 65.21.0.0-65.21.255.255 -j DROP
  
  # Verify static-nodes.json has no public IPs
  cat /opt/xns/xdc07-gp5-nodiscover-apothem-4/static-nodes.json | grep -v "95.217\|65.21\|135.181\|167.235\|185.180" && echo "LEAK DETECTED" || echo "Clean"
  
  docker start xdc07-gp5-nodiscover-apothem-4
EOF
```

---

## 9. Monitoring Checklist

| Check | Command | Expected |
|-------|---------|----------|
| Container running | `docker ps` | Status `Up` |
| Syncing | `eth_syncing` | `true` until caught up |
| Peer count | `net_peerCount` | 1–6 |
| Block height | `eth_blockNumber` | Increasing |
| Only fleet peers | `admin_peers` | All IPs in fleet ranges |
| No discovery | `admin_nodeInfo` | No `discport` |
| SkyNet reporting | `skynet.xdcindia.com` | Agent online |
| Ethstats | `stats.xdcindia.com` | Node visible |

---

## 10. Summary of Files Changed/Created

| File | Location | Action |
|------|----------|--------|
| `docker-compose.gp5-apothem-nodiscover.yml` | `xdc-node-setup/docker/` | Create |
| `static-nodes.json` | `/opt/xns/` on all servers | Create |
| `extract-enodes.sh` | `xdc-node-setup/scripts/` | Create |
| `generate-static-nodes.sh` | `xdc-node-setup/scripts/` | Create |
| `iptables-fleet-rules.sh` | `xdc-node-setup/scripts/` | Create (optional) |

---

## Open Questions

1. **enode collection:** Do all fleet nodes have existing `nodekey` files, or do we need to generate new ones?
2. **v2.6.8 chaindata compatibility:** Is v2.6.8 chaindata at 70M blocks compatible with GP5 latest? If not, we need a full snap sync instead of copy.
3. **Quorum certificate issue:** The xdc07 v21 node is stuck at 56,828,699 with "invalid quorum certificate." Does latest GP5 fix this, or is it an Apothem network issue?
4. **Bootstrap for first node:** If only one nodiscover node starts first, it has no peers. Should one node temporarily enable discovery to find the v2.6.8 reference, then disable?
