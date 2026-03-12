# GP5 Protocol Compatibility

## Overview

GP5 (Geth PR5) is a modified version of go-ethereum that implements XDPoS consensus for the XDC Network. This document explains its protocol compatibility characteristics.

## Protocol Versions

### GP5 Node Protocol Support
- **eth/63** - Full support
- **XDC/1** - XDC-specific extensions

### XDC Mainnet Protocol Support
- **eth/63** - Backward compatibility
- **eth/100** - XDC-specific protocol extensions

## Peering Compatibility

### GP5 → XDC Mainnet ✅
GP5 **CAN** peer with XDC mainnet nodes because:
- XDC mainnet supports `eth/63` for backward compatibility
- GP5 uses `eth/63` which is a common supported version

### GP5 → Vanilla Geth ❌
GP5 **CANNOT** peer with vanilla (unmodified) Geth nodes because:
- Modern Geth (v1.10+) dropped support for `eth/63`
- Vanilla Geth now requires `eth/66` or higher
- GP5 only supports `eth/63`

## Protocol Matrix

| Client A | Client B | Protocol Match | Can Peer? |
|----------|----------|----------------|-----------|
| GP5 | XDC Mainnet | eth/63 | ✅ Yes |
| GP5 | GP5 | eth/63 | ✅ Yes |
| GP5 | Vanilla Geth | None | ❌ No |
| XDC Mainnet | Vanilla Geth | None | ❌ No |

## Checking Peering Status

Use the `admin_peers` RPC method to check current peer connections:

```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "admin_peers",
    "params": [],
    "id": 1
  }'
```

### Expected Response Structure

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": [
    {
      "enode": "enode://...",
      "id": "...",
      "name": "XDC/v2.6.8/...",
      "network": {
        "localAddress": "...",
        "remoteAddress": "..."
      },
      "protocols": {
        "eth": {
          "version": 63,
          "difficulty": ...,
          "head": "..."
        }
      }
    }
  ]
}
```

### Checking Protocol Version

The `protocols.eth.version` field shows the negotiated protocol version:
- `63` - Legacy Ethereum protocol (used by GP5 and XDC)
- `100` - XDC-specific extensions

## Troubleshooting Peering Issues

### "Too many peers" or Connection Refused

1. Check your node's external IP configuration:
   ```bash
   curl -X POST http://localhost:8545 \
     -H "Content-Type: application/json" \
     -d '{
       "jsonrpc": "2.0",
       "method": "admin_nodeInfo",
       "params": [],
       "id": 1
     }'
   ```

2. Verify port forwarding for P2P port (default: 30303)

3. Check firewall rules

### No Compatible Protocols

If you see "no compatible protocols" errors, the remote peer likely:
- Is running vanilla Geth (not XDC-compatible)
- Has disabled `eth/63` support
- Is on a different network (mainnet vs testnet)

## References

- [Ethereum Wire Protocol](https://github.com/ethereum/devp2p/blob/master/caps/eth.md)
- [XDC Network Documentation](https://xinfin.org)
