# GitHub Issues to Create

## Issue #1: SkyNet API heartbeat fails for Apothem testnet nodes

### Description
SkyNet heartbeat API returns "Failed to process heartbeat" error even though the node is properly configured and sending correct data.

### Current Behavior
- Heartbeat sends successfully from node
- API Response: `Failed to process heartbeat`
- Data sent includes:
  - blockHeight: 1,483,620+
  - peerCount: 16
  - network: "apothem"
  - chainId: 51
  - isSyncing: true

### Expected Behavior
SkyNet API should accept heartbeat and display node on dashboard.

### Possible Causes
1. SkyNet API may not recognize Apothem testnet nodes yet
2. API payload format may need adjustment for testnet
3. Node registration may need update for testnet support

### Environment
- Node ID: 6bbd0e18-1133-49a7-ae22-e74888e9081e
- Network: Apothem Testnet (Chain ID: 51)
- API URL: https://skynet.xdcindia.com/api/v1

### Proposed Solutions
1. Contact SkyNet team to verify testnet node support
2. Check if payload needs network-specific fields
3. Verify node registration is valid for testnet
4. Try re-registering node specifically for Apothem network

### Labels
bug, skynet, apothem, help wanted

---

## Issue #2: Erigon container needs bootnodes configuration update

### Description
Erigon fails to start with "invalid node URL" error due to malformed bootnodes format.

### Error Message
```
Fatal: Option bootnodes: invalid node URL 
enode://...: invalid public key (wrong length, want 128 hex chars)
```

### Current Configuration
Bootnodes are being passed from file but format may be truncated or malformed.

### Expected Behavior
Erigon should start successfully with valid bootnodes.

### Proposed Solutions
1. Remove bootnodes parameter temporarily (let Erigon use defaults)
2. Verify bootnodes.list file format matches Erigon requirements
3. Update entrypoint script to format bootnodes correctly for Erigon
4. Use static bootnodes embedded in XDC Erigon binary

### Files Affected
- docker/docker-compose.erigon.yml
- docker/erigon-entrypoint.sh

### Labels
bug, erigon, bootnodes, good first issue

---

## Issue #3: Multi-client dashboard should display both Geth and Erigon stats

### Feature Request
Enhance dashboard to show metrics from both Geth and Erigon clients simultaneously.

### Current State
- Dashboard only shows Geth (xdc-node) metrics
- Erigon runs on ports 8555/8556

### Proposed Implementation
1. Add second metrics endpoint for Erigon
2. Display both clients in UI with labels
3. Show sync progress comparison
4. Alert if one client falls behind

### UI Mockup
```
Multi-Client Status
Client      Block       Status
Geth        1,535,445   Syncing 1.9%
Erigon      1,520,000   Syncing 1.8%
```

### Labels
enhancement, dashboard, multi-client

---

## Issue #4: Document Erigon build process for XDC networks

### Documentation Request
Add comprehensive documentation for building XDC Erigon from source.

### Current State
- XDC Erigon fork exists at https://github.com/AnilChinchawale/erigon-xdc
- Pre-built image available: docker-xdc-erigon:latest
- No build instructions in main repo

### Content Needed
1. Clone instructions
2. Build dependencies (Go version, etc.)
3. Docker build commands
4. Available chain names (xdc, xdc-apothem)
5. Troubleshooting common issues

### Proposed Location
- docs/ERIGON.md or
- Update existing NETWORKS.md with Erigon section

### Labels
documentation, erigon, good first issue

---

## Issue #5: Automated backup for chaindata

### Feature Request
Implement automated backup system for blockchain data.

### Motivation
- Chaindata is large (will grow to 100GB+)
- Re-syncing takes days
- Protection against corruption

### Proposed Solution
1. Daily incremental backups
2. Compress and upload to S3/Backblaze
3. Automated restore testing
4. Backup retention policy (keep last 7 days)

### Labels
enhancement, backup, infrastructure

---

## How to Create These Issues

1. Go to: https://github.com/AnilChinchawale/xdc-node-setup/issues
2. Click "New issue"
3. Copy title and description from above
4. Add appropriate labels
5. Submit
