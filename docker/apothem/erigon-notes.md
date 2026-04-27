# Erigon Support for XDC Apothem

## Current Status
Standard Erigon (erigontech/erigon) does NOT support XDC chains natively.
XDC uses XDPoS consensus which requires custom modifications to Erigon.

## Why It Doesn\t Work
1. Erigon has built-in chain specs for Ethereum networks only
2. XDC Apothem (Chain ID 51) is not recognized
3. XDPoS consensus mechanism differs from Ethereum PoS

## Solution Options

### Option 1: XinFin Official Erigon (Recommended - When Available)
Wait for XinFin to release official Erigon Docker image:
```yaml
image: xinfinorg/erigon:latest
```

### Option 2: Build Custom Erigon
Build Erigon from source with XDC chain configurations:
```bash
git clone https://github.com/XinFinOrg/erigon.git
cd erigon
git checkout xdc-mainnet  # or xdc-apothem branch
make erigon
docker build -t xdc-erigon .
```

### Option 3: Chain Specification File
Provide custom chain spec (limited support):
```bash
erigon --chain=/work/apothem-genesis.json
```

## Current Workaround
Geth (XDC client) is running and syncing properly.
All Erigon configuration files are prepared for when support is available.

## Files Prepared
- docker-compose.erigon-apothem.yml - Erigon service definition
- erigon-entrypoint.sh - Network-aware startup script
- start-erigon.sh - Apothem-specific configuration
- /root/xdc-node-setup/apothem/erigon/ - Data directory

## References
- XinFin GitHub: https://github.com/XinFinOrg
- Erigon Docs: https://github.com/erigontech/erigon
- XDC Consensus: https://docs.xdc.org/consensus/xdpos
