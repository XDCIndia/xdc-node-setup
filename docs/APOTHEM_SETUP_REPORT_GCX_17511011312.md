# XDC Apothem Network Setup Report - GCX Server (175.110.113.12)

## Setup Attempt Summary

**Date**: 2026-02-16  
**Server**: 175.110.113.12 (GCX)  
**Objective**: Set up XDC Apothem network with three clients (stable, erigon, geth-pr5)

---

## 1. Stable XDC (geth) - Apothem

**Status**: FAILED - Configuration issue  
**Ports**: 8545 (RPC), 30303 (P2P)  
**Container**: xdc-apothem-stable  
**Data Dir**: /opt/xdc-apothem/stable/data

### Error
```
cp: can't stat '/work/apothem/*': No such file or directory
/work/entry.sh: line 13: /work/start.sh: No such file or directory
```

### Issue
The xdc-node-setup's stable client docker image expects apothem configuration files that don't exist in the container.

---

## 2. Erigon - Apothem

**Status**: FAILED - Data directory issue  
**Ports**: 8546 (RPC), 30304 (P2P)  
**Container**: xdc-apothem-erigon  
**Data Dir**: /opt/xdc-apothem/erigon/data

### Error
```
github.com/erigontech/erigon/db/datadir.New
Erigon datadir configuration error
```

### Issue
Erigon container has permission/datadir configuration issues.

---

## 3. Geth PR5 - Apothem

**Status**: NOT STARTED - Build required  
**Ports**: 8547 (RPC), 30305 (P2P)  
**Data Dir**: /opt/xdc-apothem/geth-pr5/data

### Issue
Docker image needs to be built from source using:
```bash
cd /root/xdc-node-setup/docker/geth-pr5 && docker build -t xdc-geth-pr5:apothem .
```
Estimated build time: 10-15 minutes

---

## Files Created

```
/opt/xdc-apothem/
├── stable/
│   ├── docker-compose.yml
│   └── data/
├── erigon/
│   ├── docker-compose.yml
│   └── data/
└── geth-pr5/
    ├── docker-compose.yml
    └── data/
```

---

## Cleanup Performed

1. Stopped and removed old containers: xdc-node, xdc-agent, xdc-node-erigon
2. Removed old data directories: /root/.xdc-node, /root/xdcchain
3. Pruned docker volumes

---

## Next Steps to Complete Setup

### Fix Stable XDC
```bash
cd /root/xdc-node-setup
# Use testnet configuration (which is Apothem)
NETWORK=testnet ./setup.sh --client stable --type full
```

### Fix Erigon
```bash
cd /opt/xdc-apothem/erigon
# Fix datadir permissions
chmod -R 777 /opt/xdc-apothem/erigon/data
# Update docker-compose with proper erigon flags
```

### Build and Start Geth PR5
```bash
cd /root/xdc-node-setup/docker/geth-pr5
docker build -t xdc-geth-pr5:apothem .
cd /opt/xdc-apothem/geth-pr5
docker compose up -d
```

---

## SkyNet Registration

Nodes need to be registered on SkyNet after successful startup:
- URL: https://skynet.xdcindia.com
- Node naming convention: xdc-gcx-apothem-{client}

---

## GitHub Repository

Repository: AnilChinchawale/xdc-node-setup  
Branch: main  
Changes to push: None (setup attempted but not completed)

---

**Note**: This report documents the attempted setup. All three clients failed to start due to configuration issues that need to be resolved before nodes can be registered on SkyNet.
