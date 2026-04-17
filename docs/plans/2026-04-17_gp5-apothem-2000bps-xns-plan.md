# GP5 Apothem 2000+ bl/s Sync Test Plan

> **For Hermes:** Use `subagent-driven-development` skill to implement this plan task-by-task.

**Goal:** Deploy the **latest GP5 codebase** on the **Apothem network** across the XDC fleet using **XNS standards**, test **multiple sync/state schemes** in parallel, and validate **≥2000 blocks/sec** sustained sync speed on transaction blocks.

**Architecture:**
- Use **Tier A servers** (`xdc07`, `local`) for high-throughput scheme tests where 2000 bl/s is achievable.
- Use **Tier B servers** (`APO`, `xdc02`) for controlled baseline and compatibility verification.
- Standardize all deployments via **XNS naming conventions** and `docker-compose.gp5-apothem.yml`.
- Monitor via **SkyNet agents** + **ethstats** for real-time sync telemetry.

**Tech Stack:** GP5 (Geth 1.17 fork), Docker Compose, XNS CLI (`xdc`), SkyNet agent containers, `curl`/`jq` for RPC benchmarking.

---

## Current Context & Assumptions

- **Latest GP5 image:** `anilchinchawale/gp5-xdc:latest` built from `XDCIndia/go-ethereum` `xdc-network` branch.
- **XNS naming:** `{location}-{client}-{sync}-{scheme}-{network}-{server_id}`
- **Fleet state (2026-04-17):**
  - `xdc07` (Tier A) has a **crashing snap-PBSS v34** node → ideal candidate for replacement with latest build.
  - `local` (Tier A) has multi-client testbed → can host 2–3 parallel scheme tests after cleanup.
  - `APO` (Tier B) has **both containers stopped** → perfect clean-slate baseline.
  - `xdc02` has a restarting v2.6.8 node → can be repurposed for a secondary GP5 scheme test.
- **Target metric:** `2000 bl/s` on Apothem transaction blocks (not empty epochs).
- **Reference issue:** `XDCIndia/go-ethereum#176` — GP5 Sync Optimization path.

---

## Task 1: Build & Tag Latest GP5 Image

**Objective:** Produce a single canonical image for all scheme tests.

**Files:**
- Modify: `XDC-Geth/Makefile` or CI script
- Create: `xdc-node-setup/docker/Dockerfile.gp5-latest`

**Step 1: Build from latest `xdc-network` branch**

```bash
cd /Users/anilchinchawale/github/XDCNetwork/XDC-Geth
git checkout xdc-network
git pull origin xdc-network
make geth
```

**Step 2: Dockerize and tag**

```bash
docker build -t anilchinchawale/gp5-xdc:latest -f Dockerfile .
docker push anilchinchawale/gp5-xdc:latest
```

**Step 3: Record commit hash**

```bash
COMMIT=$(git rev-parse --short HEAD)
echo "GP5 latest commit: $COMMIT" > /Users/anilchinchawale/github/XDCNetwork/xdc-node-setup/docs/plans/gp5-latest-commit.txt
```

**Verification:**
- `docker run --rm anilchinchawale/gp5-xdc:latest /usr/local/bin/geth version` prints expected version.

---

## Task 2: Server Cleanup & Preparation

**Objective:** Free resources and remove conflicting/failing containers before deploying standardized tests.

### 2a — xdc07 (Primary 2000 bl/s target)

```bash
ssh -p 12141 root@65.21.71.4 <<'EOF'
  # Stop/remove the crashing snap-PBSS v34 test container
  docker stop xdc07-geth-snap-pbss-apothem-4
  docker rm -f xdc07-geth-snap-pbss-apothem-4
  docker volume rm -f xdc07-geth-snap-pbss-apothem-4_data 2>/dev/null || true

  # Keep the c84df16 (preferred) and v21 nodes for comparison, but isolate ports if needed
  # Ensure port 9545/9546/30303 are not bound by new container names
EOF
```

### 2b — local (Parallel scheme testbed)

```bash
ssh -p 12141 root@95.217.56.168 <<'EOF'
  # Remove unhealthy PR5 and Erigon test containers to free ~400GB
  docker rm -f xdc03-geth-pr5 test-erigon-full-hbss-apothem-168
  docker volume prune -f
EOF
```

### 2c — APO (Clean baseline)

```bash
ssh -p 52316 root@185.180.220.183 <<'EOF'
  # Remove stopped epoch-opt and latest containers completely
  docker rm -f apo-geth-full-hbss-apothem-183 apo-geth-full-hbss-mainnet-183
  docker volume prune -f
EOF
```

### 2d — xdc02 (Secondary scheme test)

```bash
ssh -p 12141 root@135.181.117.109 <<'EOF'
  # Remove the crashing v2.6.8 reference to free the name/port space
  docker rm -f gp5-apothem-xdc02
  docker volume prune -f
EOF
```

**Verification:**
- Run `docker ps -a` on each host and confirm no `Restarting` or `Exited` GP5 containers in the target slots.

---

## Task 3: Define the Scheme Test Matrix

**Objective:** Deploy 4–5 scheme variants so we can compare sync speed and stability.

| ID | Server | Scheme | Sync Mode | Expected Role | Target bl/s |
|----|--------|--------|-----------|---------------|-------------|
| `A` | **xdc07** | `snap` + `PBSS` | `--syncmode snap --state.scheme path` | **Primary speed run** | ≥ 2000 |
| `B` | **local** | `snap` + `HBSS` | `--syncmode snap --state.scheme hash` | Hybrid comparison | 1200–1500 |
| `C` | **local** | `full` + `HBSS` | `--syncmode full --state.scheme hash` | Compatibility baseline | 600–800 |
| `D` | **APO** | `full` + `HBSS` | `--syncmode full --state.scheme hash` | Stable baseline (Tier B) | 400–600 |
| `E` | **xdc02** | `snap` + `PBSS` | `--syncmode snap --state.scheme path` | Tier B PBSS validation | 1000–1500 |

> **Why PBSS for 2000 bl/s?** Path-Based State Scheme (Geth 1.17) reduces trie lookups and commit latency, which is the bottleneck during high-transaction-block sync.

---

## Task 4: Create XNS-Standardized Compose Templates

**Objective:** Generate one compose file per scheme so deployment is repeatable and follows XNS conventions.

**Files:**
- Create: `xdc-node-setup/docker/docker-compose.gp5-apothem-snap-pbss.yml`
- Create: `xdc-node-setup/docker/docker-compose.gp5-apothem-snap-hbss.yml`
- Create: `xdc-node-setup/docker/docker-compose.gp5-apothem-full-hbss.yml`
- Modify: `xdc-node-setup/docker/docker-compose.gp5-apothem.yml` (update to delegate to scheme-specific files or deprecate)

### Template: snap + PBSS

```yaml
# docker-compose.gp5-apothem-snap-pbss.yml
services:
  geth:
    image: anilchinchawale/gp5-xdc:latest
    container_name: ${CONTAINER_NAME:-xdc-gp5-snap-pbss-apothem}
    restart: unless-stopped
    ports:
      - "9545:8545"
      - "9546:8546"
      - "30303:30303"
      - "30303:30303/udp"
    volumes:
      - ${DATA_DIR:-./data}:/xdcchain
    environment:
      - NETWORK=apothem
      - SYNC_MODE=snap
      - STATE_SCHEME=path
      - STATS_HOST=stats.xdcindia.com:443
      - STATS_SECRET=xdc_openscan_stats_2026
    command: >
      /usr/local/bin/geth
      --apothem
      --syncmode snap
      --state.scheme path
      --datadir /xdcchain
      --rpc
      --rpcaddr 0.0.0.0
      --rpcport 8545
      --rpcapi eth,net,web3,txpool,debug
      --ws
      --wsaddr 0.0.0.0
      --wsport 8546
      --wsapi eth,net,web3
      --maxpeers 50
      --cache 8192
      --snapshot
      --ethstats "${CONTAINER_NAME}:xdc_openscan_stats_2026@stats.xdcindia.com:443"
```

### Template: full + HBSS (baseline)

```yaml
# docker-compose.gp5-apothem-full-hbss.yml
services:
  geth:
    image: anilchinchawale/gp5-xdc:latest
    container_name: ${CONTAINER_NAME:-xdc-gp5-full-hbss-apothem}
    restart: unless-stopped
    ports:
      - "9545:8545"
      - "9546:8546"
      - "30303:30303"
      - "30303:30303/udp"
    volumes:
      - ${DATA_DIR:-./data}:/xdcchain
    environment:
      - NETWORK=apothem
      - SYNC_MODE=full
      - STATE_SCHEME=hash
      - STATS_HOST=stats.xdcindia.com:443
      - STATS_SECRET=xdc_openscan_stats_2026
    command: >
      /usr/local/bin/geth
      --apothem
      --syncmode full
      --state.scheme hash
      --datadir /xdcchain
      --rpc
      --rpcaddr 0.0.0.0
      --rpcport 8545
      --rpcapi eth,net,web3,txpool,debug
      --ws
      --wsaddr 0.0.0.0
      --wsport 8546
      --wsapi eth,net,web3
      --maxpeers 50
      --cache 4096
      --snapshot
      --ethstats "${CONTAINER_NAME}:xdc_openscan_stats_2026@stats.xdcindia.com:443"
```

> **Cache sizing:** Tier A gets `8192`, Tier B gets `4096` to leave headroom for OS + agents.

**Verification:**
- `docker compose -f docker-compose.gp5-apothem-snap-pbss.yml config` returns valid YAML.

---

## Task 5: Deploy the Scheme Matrix via XNS

**Objective:** Launch all test nodes using standardized names and environment variables.

### 5a — Deploy Scheme A (xdc07, snap+PBSS)

```bash
ssh -p 12141 root@65.21.71.4 <<'EOF'
  mkdir -p /opt/xns/xdc07-gp5-snap-pbss-apothem-4
  cd /opt/xns/xdc07-gp5-snap-pbss-apothem-4

  export CONTAINER_NAME=xdc07-gp5-snap-pbss-apothem-4
  export DATA_DIR=/opt/xns/xdc07-gp5-snap-pbss-apothem-4/data

  docker compose -f /opt/xns/compose/gp5-apothem-snap-pbss.yml up -d
EOF
```

### 5b — Deploy Scheme B (local, snap+HBSS)

```bash
ssh -p 12141 root@95.217.56.168 <<'EOF'
  mkdir -p /opt/xns/local-gp5-snap-hbss-apothem-168
  cd /opt/xns/local-gp5-snap-hbss-apothem-168

  export CONTAINER_NAME=local-gp5-snap-hbss-apothem-168
  export DATA_DIR=/opt/xns/local-gp5-snap-hbss-apothem-168/data

  docker compose -f /opt/xns/compose/gp5-apothem-snap-hbss.yml up -d
EOF
```

### 5c — Deploy Scheme C (local, full+HBSS)

```bash
ssh -p 12141 root@95.217.56.168 <<'EOF'
  mkdir -p /opt/xns/local-gp5-full-hbss-apothem-168
  cd /opt/xns/local-gp5-full-hbss-apothem-168

  export CONTAINER_NAME=local-gp5-full-hbss-apothem-168
  export DATA_DIR=/opt/xns/local-gp5-full-hbss-apothem-168/data

  docker compose -f /opt/xns/compose/gp5-apothem-full-hbss.yml up -d
EOF
```

### 5d — Deploy Scheme D (APO, full+HBSS)

```bash
ssh -p 52316 root@185.180.220.183 <<'EOF'
  mkdir -p /opt/xns/apo-gp5-full-hbss-apothem-183
  cd /opt/xns/apo-gp5-full-hbss-apothem-183

  export CONTAINER_NAME=apo-gp5-full-hbss-apothem-183
  export DATA_DIR=/opt/xns/apo-gp5-full-hbss-apothem-183/data

  docker compose -f /opt/xns/compose/gp5-apothem-full-hbss.yml up -d
EOF
```

### 5e — Deploy Scheme E (xdc02, snap+PBSS)

```bash
ssh -p 12141 root@135.181.117.109 <<'EOF'
  mkdir -p /opt/xns/xdc02-gp5-snap-pbss-apothem-109
  cd /opt/xns/xdc02-gp5-snap-pbss-apothem-109

  export CONTAINER_NAME=xdc02-gp5-snap-pbss-apothem-109
  export DATA_DIR=/opt/xns/xdc02-gp5-snap-pbss-apothem-109/data

  docker compose -f /opt/xns/compose/gp5-apothem-snap-pbss.yml up -d
EOF
```

**Verification:**
- Run `docker ps` on each host → all 5 containers show `Up` and healthy.
- `curl -s -X POST http://<ip>:9545 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'` returns `true` (syncing) for all fresh nodes.

---

## Task 6: Attach SkyNet Agents for Monitoring

**Objective:** Every test node must report to SkyNet so we can track sync speed centrally.

**Files:**
- Create: `xdc-node-setup/scripts/deploy-skynet-agent.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

SERVER_IP=$1
SERVER_ID=$2
CONTAINER_NAME=$3
SSH_PORT=${4:-12141}

ssh -p "$SSH_PORT" "root@${SERVER_IP}" <<EOF
  docker run -d \
    --name "skyone-${CONTAINER_NAME}" \
    --network host \
    -e TARGET_CONTAINER="${CONTAINER_NAME}" \
    -e STATSD_HOST=127.0.0.1 \
    -e SKYNET_URL=https://skynet.xdcindia.com/api \
    anilchinchawale/xdc-agent:latest
EOF
```

**Step 1: Deploy agents for all 5 test containers**

```bash
cd /Users/anilchinchawale/github/XDCNetwork/xdc-node-setup

# xdc07
./scripts/deploy-skynet-agent.sh 65.21.71.4 4 xdc07-gp5-snap-pbss-apothem-4

# local (x2)
./scripts/deploy-skynet-agent.sh 95.217.56.168 168 local-gp5-snap-hbss-apothem-168
./scripts/deploy-skynet-agent.sh 95.217.56.168 168 local-gp5-full-hbss-apothem-168

# APO
./scripts/deploy-skynet-agent.sh 185.180.220.183 183 apo-gp5-full-hbss-apothem-183 52316

# xdc02
./scripts/deploy-skynet-agent.sh 135.181.117.109 109 xdc02-gp5-snap-pbss-apothem-109
```

**Verification:**
- Check SkyNet dashboard (`https://skynet.xdcindia.com`) → 5 new agents appear within 5 minutes.

---

## Task 7: Benchmark Sync Speed

**Objective:** Measure blocks/sec for each scheme. Focus on **transaction blocks** (not empty epoch headers).

**Files:**
- Create: `xdc-node-setup/scripts/benchmark-sync.sh`

```bash
#!/usr/bin/env bash
set -uo pipefail

RPC_URL=$1
DURATION_SEC=${2:-60}

START_BLOCK=$(curl -s -X POST "$RPC_URL" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result' | sed 's/0x//')
START_BLOCK_DEC=$((16#$START_BLOCK))
START_TIME=$(date +%s)

sleep "$DURATION_SEC"

END_BLOCK=$(curl -s -X POST "$RPC_URL" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result' | sed 's/0x//')
END_BLOCK_DEC=$((16#$END_BLOCK))
END_TIME=$(date +%s)

DELTA_BLOCKS=$((END_BLOCK_DEC - START_BLOCK_DEC))
DELTA_TIME=$((END_TIME - START_TIME))
BL_S=$(awk "BEGIN {printf \"%.2f\", $DELTA_BLOCKS / $DELTA_TIME}")

echo "{\"start\":$START_BLOCK_DEC,\"end\":$END_BLOCK_DEC,\"delta\":$DELTA_BLOCKS,\"time\":$DELTA_TIME,\"bl_s\":$BL_S}"
```

**Step 1: Run 60-second benchmarks after 5-minute warm-up**

```bash
# Scheme A — xdc07 snap+PBSS (primary 2000 bl/s target)
ssh -p 12141 root@65.21.71.4 \
  'bash -s' < scripts/benchmark-sync.sh http://localhost:9545 60

# Scheme B — local snap+HBSS
ssh -p 12141 root@95.217.56.168 \
  'bash -s' < scripts/benchmark-sync.sh http://localhost:9545 60

# Scheme C — local full+HBSS
ssh -p 12141 root@95.217.56.168 \
  'bash -s' < scripts/benchmark-sync.sh http://localhost:9545 60

# Scheme D — APO full+HBSS
ssh -p 52316 root@185.180.220.183 \
  'bash -s' < scripts/benchmark-sync.sh http://localhost:9545 60

# Scheme E — xdc02 snap+PBSS
ssh -p 12141 root@135.181.117.109 \
  'bash -s' < scripts/benchmark-sync.sh http://localhost:9545 60
```

**Step 2: Capture peak vs sustained**

Run the benchmark at:
- `t=5min` (early sync)
- `t=30min` (mid sync)
- `t=2h` (near-head sync, most critical for 2000 bl/s claim)

**Verification:**
- JSON output for each run shows `bl_s`. Scheme A should hit `≥2.0` during transaction-heavy ranges.

---

## Task 8: Optimize for 2000+ bl/s (Tuning Runbook)

**Objective:** If Scheme A (xdc07 snap+PBSS) is below 2000 bl/s, apply these optimizations iteratively.

### 8a — Geth 1.17 Sync Optimizations

Update the compose command for **Scheme A** with these flags:

```yaml
    command: >
      /usr/local/bin/geth
      --apothem
      --syncmode snap
      --state.scheme path
      --datadir /xdcchain
      --rpc --rpcaddr 0.0.0.0 --rpcport 8545
      --rpcapi eth,net,web3,txpool,debug
      --ws --wsaddr 0.0.0.0 --wsport 8546
      --wsapi eth,net,web3
      --maxpeers 100
      --cache 12288
      --cache.database 50
      --cache.snapshot 20
      --snapshot
      --txpool.pricelimit 1
      --txlookuplimit 0
      --history.transactions 0
      --db.engine pebble
      --rpc.batch-request-limit 1000
      --rpc.batch-response-max-size 50000000
      --ethstats "${CONTAINER_NAME}:xdc_openscan_stats_2026@stats.xdcindia.com:443"
```

> **Tuning rationale:**
> - `--cache 12288` → maximize state trie cache on Tier A (leaves ~50GB for OS).
> - `--db.engine pebble` → Geth 1.17 default, better write throughput than LevelDB.
> - `--history.transactions 0` → prune tx index to reduce I/O during sync.
> - `--maxpeers 100` → saturate download pipeline with Apothem peers.

### 8b — Host-Level Optimizations (xdc07)

```bash
ssh -p 12141 root@65.21.71.4 <<'EOF'
  # Disable swap to prevent I/O thrashing during heavy sync
  swapoff -a

  # Increase file descriptor limits
  sysctl -w fs.file-max=2097152
  sysctl -w fs.nr_open=2097152

  # Network tuning for P2P
  sysctl -w net.core.rmem_max=134217728
  sysctl -w net.core.wmem_max=134217728
  sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728"
  sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728"
EOF
```

### 8c — Storage I/O Check

Ensure `/opt/xns/.../data` is on SSD/NVMe (all Tier A servers should be). If disk I/O is the bottleneck, move data to the fastest mount:

```bash
ssh -p 12141 root@65.21.71.4 'lsblk -d -o NAME,ROTA,TYPE,SIZE | grep -v rom'
```

If any rotational disk (`ROTA=1`) is in use, migrate to NVMe.

**Verification:**
- Re-run benchmark after each tuning change. Document which change produced the biggest `bl_s` delta.

---

## Task 9: Validate State Integrity Post-Sync

**Objective:** Fast sync is meaningless if the state is corrupt. Verify each scheme reaches a valid head.

**Step 1: Check sync completion**

```bash
for host in 65.21.71.4 95.217.56.168 185.180.220.183 135.181.117.109; do
  port=12141
  [ "$host" = "185.180.220.183" ] && port=52316
  ssh -p $port root@$host '
    curl -s -X POST http://localhost:9545 -H "Content-Type: application/json" \
      -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_syncing\",\"params\":[],\"id\":1}"
  '
done
```

Expected: `false` for all (synced to head).

**Step 2: Deep snapshot validation (XNS Phase 1.2)**

For the fastest scheme (A), run the deep validation script:

```bash
ssh -p 12141 root@65.21.71.4 <<'EOF'
  cd /opt/xns/xdc07-gp5-snap-pbss-apothem-4/data
  bash /opt/xns/scripts/validate-snapshot-deep.sh \
    --datadir /opt/xns/xdc07-gp5-snap-pbss-apothem-4/data \
    --network apothem
EOF
```

**Verification:**
- Validation script exits `0` with no `CRITICAL` or `MISMATCH` logs.

---

## Task 10: Report & Decide on Production Rollout

**Objective:** Summarize findings and recommend which scheme goes to `prod` and `xdc01` canary.

**Files:**
- Create: `xdc-node-setup/docs/plans/gp5-apothem-2000bps-report.md`

**Report structure:**
1. **Executive Summary** — which scheme hit 2000 bl/s and on which hardware.
2. **Scheme Comparison Table** — bl/s, time-to-sync, disk usage, CPU%, RAM%.
3. **Tuning Delta Log** — which flags moved the needle.
4. **Risks** — PBSS maturity, rollback path to HBSS.
5. **Recommendation** — deploy `snap+PBSS` to `prod` (Mainnet + Apothem) or wait for longer soak test.

**Verification:**
- Report is reviewed and linked in `XDCIndia/go-ethereum#176`.

---

## Risks, Tradeoffs, and Open Questions

| Risk | Mitigation |
|------|------------|
| **PBSS state corruption on GP5 fork** | Run `validate-snapshot-deep.sh` before declaring success. Keep HBSS nodes as fallback. |
| **Port collisions** on `local` / `xdc07` | Use sequential RPC ports (9545, 9547, 9549) if deploying multiple containers on one host. |
| **APO firewall on port 52316** | Verify SSH works; use `nc -vz 185.180.220.183 9545` after deploy to confirm RPC exposure. |
| **Snap sync stalls near head** | Monitor `eth_syncing.highestBlock - currentBlock`. If < 100 blocks for > 5 min, restart geth. |
| **Latest GP5 image has regression** | Tag the previous known-good image (`v34`) and keep it as instant rollback. |

**Open Questions:**
1. Does the GP5 fork support `--db.engine pebble` in production, or is it still LevelDB-only?
2. Should we add `--light.serve 0` to reduce sync overhead?
3. Do we need a **dedicated benchmark peer** on Apothem to guarantee saturated download?

---

## Execution Order Summary

1. **Task 1** — Build & push `gp5-xdc:latest`
2. **Task 2** — Clean up failing containers on xdc07, local, APO, xdc02
3. **Task 3** — Confirm scheme test matrix
4. **Task 4** — Create XNS compose templates for snap+PBSS, snap+HBSS, full+HBSS
5. **Task 5** — Deploy all 5 scheme variants
6. **Task 6** — Attach SkyNet agents
7. **Task 7** — Run sync benchmarks at 5min / 30min / 2h
8. **Task 8** — Apply 2000 bl/s optimizations iteratively
9. **Task 9** — Validate state integrity post-sync
10. **Task 10** — Write report and recommend rollout

**Total estimated effort:** 3–4 hours of focused implementation + 4–6 hours of sync observation.
