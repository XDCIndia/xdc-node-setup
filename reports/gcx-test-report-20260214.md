# GCX Server XDC Node Clean Install Test Report

**Date:** 2026-02-14  
**Server:** 175.110.113.12:12141 (GCX)  
**Test Duration:** ~5 minutes  
**Installation:** Fresh install from local XDC-Node-Setup repository  

---

## Executive Summary

The XDC node installation **COMPLETED** but the node is **NON-FUNCTIONAL**. While the installer ran successfully and containers are running, the node cannot connect to peers, sync blocks, or respond to RPC requests.

### Overall Status: 🔴 **CRITICAL**

- ✅ Installation: SUCCESS
- ✅ Container Status: RUNNING
- 🔴 Node Functionality: **FAILED**
- 🔴 Network Connectivity: **FAILED**
- 🔴 RPC Accessibility: **FAILED**

---

## Critical Issues (Priority: CRITICAL)

### 1. RPC Not Responding
**Symptom:** All RPC requests fail with "Connection refused"
```
wget: can't connect to remote host: Connection refused
```

**Impact:** Node cannot be queried, CLI commands fail, dashboard cannot fetch metrics

**Evidence:**
- Health check logs show continuous connection failures
- `xdc status` reports node as "Offline"
- Dashboard `/api/health` returns 503 status
- Direct curl to localhost:8545 fails

**Root Cause:** Node is listening on internal port 6060 (`--rpcport 6060`) but Docker is exposing 8545. Port mismatch or node failed to start RPC server.

---

### 2. Zero Peers Connected
**Symptom:** Node has 0 peers despite extensive bootnode list

**Impact:** Cannot sync blockchain, completely isolated from network

**Evidence:**
- Dashboard metrics: `"peers": 0`
- CLI health check: "✗ No peers connected"
- Node logs show bootnodes configured but no peer connections

**Possible Causes:**
- Network discovery failing
- P2P port 30303 not accessible (firewall issue?)
- Node enode not valid
- Mainnet boot nodes unreachable from this location

---

### 3. Block Height Stuck at 0
**Symptom:** Node remains at genesis block, not syncing

**Impact:** Node cannot provide any blockchain data

**Evidence:**
```
blockHeight: 0
highestBlock: 0
syncPercent: 0
isSyncing: false
```

**Related Error:**
```
ERROR[02-14|06:48:09.103] Failed to retrieve block author
  err="recovery failed" number=0 hash=4a9d74..42d6b1
```

**Analysis:** Node successfully wrote genesis state but cannot process block 0. This suggests:
- Genesis configuration issue
- Consensus mechanism not functioning
- Network isolation preventing initial sync

---

## High Priority Issues

### 4. Container Health Check Failing
**Symptom:** xdc-node container perpetually in "starting" state

**Evidence:**
```
STATUS: Up About a minute (health: starting)
Health Check Log: Connection refused (continuous failures)
```

**Impact:** Docker considers the container unhealthy, may restart it

---

### 5. Port Configuration Mismatch
**Symptom:** Documentation says dashboard on 8889, actually on 7070

**Evidence:**
- Installer output: "Dashboard: http://localhost:8889"
- Actual: xdc-agent on 0.0.0.0:7070
- `xdc status` shows: "Dashboard: http://localhost:8888"

**Impact:** User confusion, documentation inconsistency

---

## Medium Priority Issues

### 6. Hardware Below Recommended Specs
**Warnings during install:**
```
⚠ Minimum 16GB RAM recommended (found: 11GB)
⚠ Minimum 500GB disk space recommended (found: 60GB)
⚠ Hardware does not meet recommended specs — node may run slowly
```

**Impact:** May affect performance when node eventually syncs

**Recommendation:** Acceptable for testing, but not for production validator node

---

### 7. Deprecated Flags in Use
**Warnings in logs:**
```
WARN The flag --mine is deprecated and will be removed
WARN The flag XDCx-datadir or XDCx.datadir is deprecated, please remove this flag
```

**Impact:** May break in future XDC client versions

---

### 8. V2 Config Warnings
**Repeated warnings:**
```
WARN [V2Equal] One of the configs is nil
  a="V2: <nil>" b="V2{SwitchEpoch: 89300, SwitchBlock: 80370000...}"
```

**Impact:** XDPoS v2 configuration may not be properly initialized

---

## Low Priority Issues

### 9. Missing .pwd File
**During install:**
```
⚠ mainnet/.pwd is missing or empty. Re-downloading...
```

**Impact:** Minor, was auto-resolved

### 10. SkyNet Not Registered
**Setup completion:** Only 3/7 steps complete
```
[✗] SkyNet registered
[✗] Monitoring enabled
```

**Impact:** No remote monitoring, but expected for test install

---

## What's Working ✅

1. **Installation Process**
   - Installer ran smoothly
   - All dependencies installed
   - CLI tool functional
   - Docker compose configured correctly

2. **Security**
   - UFW firewall configured
   - Ports 22, 30303 (TCP/UDP) opened
   - Fail2ban enabled
   - Log rotation configured

3. **CLI Tool**
   - `xdc` command installed at `/usr/local/bin/xdc`
   - All subcommands available
   - Help system functional
   - Version detection working

4. **Dashboard (Partial)**
   - Next.js dashboard running
   - Web interface accessible on port 7070
   - Static pages load (/, /peers, /alerts, /network)
   - `/api/heartbeat` and `/api/health/live` responding

5. **Containers**
   - Both containers created and running
   - xdc-node: Using official XDC image
   - xdc-agent: Dashboard container operational
   - Docker network created

---

## Installation Log Analysis

### Phase 1: Cleanup ✅
- Successfully stopped 2 existing XDC containers
- Removed old chaindata
- Cleared ports
- No errors

### Phase 2: File Transfer ✅
- Transferred 320 files from local workspace
- Git repository initialized
- Commit: c28221a

### Phase 3: Installation ✅
- Installer version 1.0.0 detected Ubuntu 22.04
- Docker already present (27.0.3)
- Node configured as Full Node on mainnet
- Firewall rules applied
- CLI installed successfully
- Containers started

### Phase 4-5: Monitoring
- Node initialized genesis block successfully
- Genesis hash: `0x4a9d748bd78a8d0385b67788c2435dcdb914f98a96250b68863a1f8b7642d6b1`
- But immediately encountered block author retrieval error

---

## CLI Command Results

| Command | Exit Code | Status | Notes |
|---------|-----------|---------|-------|
| `xdc status` | 0 | ⚠️ Partial | Shows offline, 0 peers, 0 blocks |
| `xdc health` | 1 | ❌ Failed | 4 checks failed, security score 0/100 |
| `xdc info` | 0 | ⚠️ Partial | Same as status |
| `xdc peers` | 1 | ❌ Wrong cmd | Launched bootnode optimizer instead |
| `xdc sync` | 1 | ❌ Wrong cmd | Launched sync optimizer instead |
| `xdc help` | 0 | ✅ Pass | Full help displayed |
| `xdc version` | 0 | ✅ Pass | CLI v1.0.0, client version unknown |
| `xdc logs` | 1 | ❌ Failed | "No log files found" |

---

## Dashboard API Endpoints

| Endpoint | HTTP Status | Functionality |
|----------|-------------|---------------|
| `/` | 200 | ✅ Homepage loads |
| `/api/metrics` | 200 | ✅ Returns metrics (0 peers, 0 blocks) |
| `/api/health` | 503 | ❌ Service unavailable (RPC down) |
| `/api/health/live` | 200 | ✅ Liveness check passes |
| `/api/health/ready` | 503 | ❌ Not ready (RPC error) |
| `/api/health/deep` | 503 | ❌ Deep check fails (RPC) |
| `/api/peers` | 500 | ❌ Internal error (0 peers) |
| `/api/heartbeat` | 200 | ✅ Heartbeat responds |
| `/peers` | 200 | ✅ Peer map page loads |
| `/alerts` | 200 | ✅ Alerts page loads |
| `/network` | 200 | ✅ Network page loads |

---

## Network Configuration

### Ports Status
```
7070:  ✅ Dashboard (xdc-agent)
8545:  ❌ RPC HTTP (not responding)
8546:  ❌ RPC WebSocket (not responding)
8888:  ⚠️  Nginx (other services, not XDC)
30303: ✅ P2P (open, but no peers)
```

### Docker Network
- Network: `docker_xdc-network`
- xdc-node: Internal IP in Docker network
- xdc-agent: Can't reach xdc-node:8545

---

## Node Logs Key Excerpts

**Successful Genesis Init:**
```
INFO [02-14|06:48:06.779] Successfully wrote genesis state
  database=chaindata 
  hash=0x4a9d748bd78a8d0385b67788c2435dcdb914f98a96250b68863a1f8b7642d6b1
```

**Error Immediately After:**
```
ERROR[02-14|06:48:09.103] Failed to retrieve block author
  err="recovery failed" number=0 hash=4a9d74..42d6b1
```

**Node Configuration:**
```
Maximum peer count: ETH=50 total=50
Sync mode: full
GC mode: full
Network ID: 50
RPC listening on: 0.0.0.0:6060  ← NOTE: Not 8545!
```

---

## Recommendations

### Immediate Actions (Critical)

1. **Fix RPC Port Mismatch**
   ```bash
   # Option A: Change docker-compose to expose 6060:6060
   # Option B: Change start-node.sh to use --rpcport 8545
   # Option C: Update health check to use port 6060
   ```

2. **Investigate Block Author Error**
   - Check genesis.json validity
   - Verify consensus configuration
   - Compare with working mainnet node genesis

3. **Debug Peer Connection**
   - Test direct connection to bootnodes: `nc -zv 149.102.140.32 30303`
   - Check if P2P port is actually reachable externally
   - Review Docker network configuration
   - Try adding static peers manually

4. **Check Node Logs in Detail**
   ```bash
   docker logs xdc-node --tail 100
   # Look for P2P discovery errors
   # Check for RPC server startup messages
   ```

### Short-Term Improvements (High Priority)

1. **Fix Documentation Inconsistencies**
   - Update README with correct ports (7070 for dashboard)
   - Clarify RPC internal vs external ports
   - Document health check requirements

2. **Improve Error Handling**
   - Installer should validate RPC connectivity after startup
   - Add retry logic for peer connection
   - Better error messages for common failures

3. **Hardware Validation**
   - Add stricter hardware checks with override flag
   - Warn about test vs production requirements

### Long-Term Enhancements (Medium Priority)

1. **Better Health Checks**
   - Health check script should test correct port
   - Add timeout and retry configuration
   - Separate liveness from readiness checks

2. **Automated Troubleshooting**
   - `xdc diagnose` command to check common issues
   - Auto-fix for known problems
   - Better logging of startup sequence

3. **Testing Framework**
   - Add integration tests for fresh installs
   - Automated verification of all endpoints
   - Smoke tests before marking install as complete

---

## Comparison with Previous Installation

**Previous Issue:** BAD BLOCK error at ~166,500

**Current Status:** Can't even sync block 0 - **WORSE**

**Analysis:** The previous node at least connected to peers and began syncing. This fresh install is completely non-functional. Possible causes:
- Configuration changes between versions
- Network/firewall changes on GCX server
- Mainnet bootnodes becoming unreachable
- Docker compose configuration issues

---

## Test Environment Details

**Server:**
- OS: Ubuntu 22.04.4 LTS
- Kernel: 5.15.0-170-generic
- CPU: 4 cores (@ 22-27% usage)
- RAM: 11GB / 12GB (39-42% usage)
- Disk: 109GB used / 177GB total (61-65%)
- Docker: 27.0.3
- Uptime: 5 hours 20 minutes

**XDC Node Setup:**
- Version: 2.2.0
- Installation Mode: SIMPLE
- Network: mainnet (Chain ID 50)
- Sync Mode: full
- GC Mode: full
- Git Commit: c28221a (fresh clone)

**Other Services:**
- Gateway daemon (active)
- Skynet (active)
- News service (active)
- Nginx on port 8888

---

## Conclusion

This test reveals **critical functionality issues** with the XDC node setup that prevent it from operating:

1. The node cannot establish RPC connectivity (internal configuration error)
2. The node cannot connect to any peers (network isolation)
3. The node cannot process even the genesis block (consensus failure)

While the **installation process itself works smoothly**, the resulting node is completely non-functional. This is a **regression** from the previous installation which at least synced to block 166,500 before encountering BAD BLOCK errors.

### Root Cause Assessment

The most likely root cause is the **RPC port mismatch** (node listening on 6060, Docker exposing 8545, health check trying to connect to wrong port). This cascades into:
- Health checks perpetually failing
- Dashboard unable to fetch data
- CLI commands failing
- Node appearing "offline" despite running

### Next Steps

1. Fix the port configuration
2. Restart the node
3. Re-run health checks
4. Monitor peer connection establishment
5. Watch for the block author error at genesis

If the RPC issue is resolved but peer connection still fails, investigate:
- Mainnet bootnode accessibility from GCX server location
- P2P discovery mechanism
- External connectivity to port 30303

---

**Report Generated:** 2026-02-14 06:51:30 UTC  
**Test Executed By:** OpenClaw Subagent (gcx-clean-install)  
**Git Author:** anilcinchawale <anil24593@gmail.com>
