# Apothem Testnet Configuration Fixes

## Issues Found and Fixed

### 1. **CRITICAL: Wrong Genesis File in docker/apothem/genesis.json**
- **Issue**: The genesis file at `docker/apothem/genesis.json` was outdated and did not match the official XDPoSChain testnet genesis
- **Problems**:
  - Missing `eip1559Block` configuration
  - Wrong `foudationWalletAddr` (xdc92a289fe95a85c53b8d0d113cbaef0c1ec98ac65 instead of xdc746249c61f5832c5eed53172776b460491bdcd5c)
  - Wrong `timestamp` (0x5cefae27 instead of 0x5d02164f)
  - Wrong `extraData` (different validator set)
  - Missing proper alloc accounts
- **Fix**: Updated genesis.json to match https://github.com/XinFinOrg/XDPoSChain/blob/main/genesis/testnet.json

### 2. **RPC Not Exposed on 0.0.0.0 (as requested)**
- **Issue**: Several docker-compose files had RPC ports exposed only on localhost (127.0.0.1) or without explicit 0.0.0.0 binding
- **Files Affected**:
  - `docker-compose.apothem-erigon.yml`: Changed from `127.0.0.1:8556:8545` to `0.0.0.0:8556:8545`
  - `docker-compose.apothem-nethermind.yml`: Added explicit `0.0.0.0` binding
  - `docker-compose.apothem-full.yml`: Added explicit `0.0.0.0` binding for all services

### 3. **Missing/Outdated Bootnodes**
- **Issue**: Bootnode lists were incomplete compared to the official Apothem testnet bootnodes
- **Fix**: Updated bootnode lists in docker-compose files to include all 11 official Apothem testnet bootnodes:
  - enode://ee1e11e3f56b015b2b391eb9c45292159713583b4adfe29d24675238f73d33e6ec0a62397847823e2bca622c91892075c517fc383c9355d43a89bb7532e834a0@157.173.120.219:30312
  - enode://729d763db071595bacbbf33037a8e7639d8e9a97bfcfcda3afe963435d919cb95634f27375f0aadf6494dad47e506c888bf15cb5633d5f81dbb793b05b27e676@207.90.192.100:30312
  - enode://49c7586c221250cac7070df41c1b6c77180c5d9051e20d1d2b77dfa0dc80b8dc48a8e3c7ca068ac757429223530d6445a06a32ab4af20819cfaa1d47282a0401@80.243.180.121:30312
  - enode://946cc4d00c4f3e9ffb50fda9d351672d8deaf546e3406228587f8e7131e3c1ad1a0f5ca2d0e2172463a04d747b3e7b29167d93684195952734f4535e7da58351@209.209.10.19:30312
  - enode://83a51d04ca4056d3630bc2f4e3028de4d041ab346fa5f7ca5bacfb88f4f30b6a055ec34e6350685103abf21cbfed2e79afa229df734909b659c81efc81d3df1c@38.143.58.153:30312
  - enode://266dfa5fd0152c3ec2b21ac71c5ae8c263c748b417feac2d2b6b3ff8b0d64e435e7d91d079856ec7a997d3f3ead62d5bd7922ffae7937893179b36d7ae7886e9@38.102.124.102:30312
  - enode://476328d1d7e38783b627241ec2ae1814ca535dd35ec1beb7942feb9a05b5af7634d465b5c10606f72cf0f25279cdbc53503e772ac2ad84beb46c7be654e3f9b7@172.98.12.15:30312
  - enode://a2267247a3bcc49909cd025de6db46001ff47ed9271ab0a1845a2915c381f29549d243708179c77aa1dda54d373aeff788abbc440c52f12ff98ae938fc06e5ce@185.198.27.214:30312
  - enode://cf97d46e2dbf9f81a1150d071458e4f95802826df163347fb241c74379fb72f8a0cf77e3a4af49c4ab68e330874e47fcc0db7acec026b055fc57abacfe08ebab@38.102.86.183:30312
  - enode://03acada1fdb36b32e2c69067e59338f22a986796202005fd882b2ef295f83f0db50ac09cd71af1e930e3bb15f805bc44f1da907460b007588d12d7efc8156d93@209.209.11.134:30312

### 4. **Port Configuration Issues**
- **Issue**: Port comments were unclear and some WebSocket ports were not properly exposed
- **Fix**: 
  - Added WebSocket port exposure for Erigon (8559)
  - Updated port comments to clarify "enode port" vs "RPC port"
  - Ensured all P2P ports (30303, 30306, 30308) are properly exposed

### 5. **CORS Configuration Too Restrictive**
- **Issue**: The `start-node.sh` script had restrictive CORS settings
- **Fix**: Changed default CORS from `localhost,https://*.xdc.network,https://*.xinfin.org` to `*` for broader compatibility

## Files Modified

1. `docker/apothem/genesis.json` - Updated to official testnet genesis
2. `docker/apothem/start-node.sh` - Fixed CORS default
3. `docker/docker-compose.apothem-erigon.yml` - Fixed RPC binding and bootnodes
4. `docker/docker-compose.apothem-nethermind.yml` - Fixed RPC binding and bootnodes
5. `docker/docker-compose.apothem-full.yml` - Fixed RPC binding for all services

## Verification

- Network ID: 51 (correct for Apothem testnet)
- Genesis Hash: Should be 0xbdea512b4f12ff1135ec92c00dc047ffb93890c2ea1aa0eefe9b013d80640075
- Chain ID: 51
- All RPC endpoints now exposed on 0.0.0.0 as requested
- All enode ports (30303, 30306, 30308) properly exposed
