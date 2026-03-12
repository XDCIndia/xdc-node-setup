# [FIX] Issue #296: RPC Authentication and TLS Enforcement

## Problem Statement
The xdc-node-setup currently exposes RPC endpoints without proper security:
- RPC binds to 0.0.0.0 (all interfaces) by default
- No authentication mechanism for RPC calls
- No TLS/SSL encryption for data in transit
- No IP allowlisting capability
- Vulnerable to man-in-the-middle attacks

## Solution
Implemented comprehensive RPC security hardening with:
- Localhost-only binding by default
- JWT authentication for RPC calls
- TLS/SSL certificate support
- IP allowlisting
- Docker security hardening
- Access monitoring

## Changes Made

### 1. New Files Created

#### `scripts/security/harden-rpc.sh`
Interactive security hardening script that:
- Generates TLS certificates (self-signed or CA-signed)
- Creates JWT authentication secrets
- Configures IP allowlisting
- Generates client-specific security configs
- Sets up Docker security options
- Creates monitoring scripts

### 2. Security Features

#### A. Localhost Binding (Default)
```bash
# Before (INSECURE)
--http.addr=0.0.0.0  # Accessible from any IP

# After (SECURE)
--http.addr=127.0.0.1  # Localhost only
```

#### B. JWT Authentication
- 32-byte cryptographically secure random secret
- Required for Engine API (consensus layer)
- Optional for standard RPC

#### C. TLS/SSL Encryption
- Self-signed certificates generated automatically
- Support for CA-signed certificates
- TLS 1.2+ enforced

#### D. IP Allowlisting
- Configurable allowlist for trusted IPs
- CIDR notation support
- Default: localhost only

### 3. Client-Specific Configurations

| Client | Config File | Security Features |
|--------|-------------|-------------------|
| Geth | `geth-security.conf` | JWT, TLS, CORS, VHosts |
| Erigon | `erigon-security.conf` | JWT, TLS, Private API |
| Nethermind | `nethermind-security.json` | JWT, TLS, Modules |
| Reth | `reth-security.toml` | JWT, TLS, CORS |

### 4. Docker Security

```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
cap_add:
  - NET_BIND_SERVICE
read_only: true
networks:
  - internal  # No external access
```

## Usage Instructions

### 1. Run Security Hardening Script

```bash
# For Geth
./scripts/security/harden-rpc.sh geth ./config ./data

# For Erigon
./scripts/security/harden-rpc.sh erigon ./config ./data

# For Nethermind
./scripts/security/harden-rpc.sh nethermind ./config ./data

# For Reth
./scripts/security/harden-rpc.sh reth ./config ./data
```

### 2. Review Generated Configs

```bash
ls -la config/
# tls/           - TLS certificates
# auth/          - JWT secrets and IP allowlist
# *-security.*   - Client-specific security configs
```

### 3. Edit IP Allowlist

```bash
vim config/auth/ip-allowlist.txt
# Add your monitoring/management IPs
```

### 4. Start Node with Security Config

```bash
# Geth example
geth --config config/geth-security.conf \
     --datadir ./data \
     --networkid 50

# Erigon example
erigon --config config/erigon-security.conf \
       --datadir ./data \
       --chain xdc-mainnet
```

### 5. Access RPC Securely

#### Option A: SSH Tunnel (Recommended)
```bash
ssh -L 8557:localhost:8557 user@node-server
# Then access via localhost:8557 on your machine
```

#### Option B: VPN
Connect to node network via VPN, then access localhost:8557

#### Option C: Reverse Proxy
```nginx
server {
    listen 443 ssl;
    server_name xdc-node.yourdomain.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location / {
        proxy_pass http://localhost:8557;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        
        # Add authentication here
        auth_basic "XDC Node RPC";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}
```

## Security Checklist

- [x] RPC binds to localhost by default
- [x] JWT authentication implemented
- [x] TLS/SSL encryption supported
- [x] IP allowlisting configured
- [x] Docker security hardening
- [x] Access monitoring script
- [x] Client-specific configurations
- [ ] Certificate rotation (manual)
- [ ] Automated security audits (separate PR)

## Testing

### Test 1: Verify Localhost Binding
```bash
# Should FAIL (connection refused from external IP)
curl http://YOUR_NODE_IP:8557 \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Should SUCCEED (via localhost)
curl http://localhost:8557 \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

### Test 2: Verify TLS
```bash
curl https://localhost:8557 \
  --cacert config/tls/xdc-node.crt \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

### Test 3: Verify JWT Authentication
```bash
# Generate JWT token (requires jwt-cli or similar)
jwt encode --secret "$(cat config/auth/jwt-secret)" '{"iat":1234567890}'

# Use token in request
curl http://localhost:8551 \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  --data '{"jsonrpc":"2.0","method":"engine_forkchoiceUpdatedV1","params":[],"id":1}'
```

## Migration Guide

### For Existing Nodes

1. **Backup current config:**
```bash
cp config/geth.conf config/geth.conf.backup
```

2. **Run hardening script:**
```bash
./scripts/security/harden-rpc.sh geth ./config ./data
```

3. **Merge configurations:**
Manually merge your custom settings with the generated security config

4. **Test locally:**
```bash
# Start node with new config
geth --config config/geth-security.conf --datadir ./data

# Verify RPC is localhost-only
netstat -tlnp | grep 8557
# Should show: 127.0.0.1:8557
```

5. **Update external access:**
Set up SSH tunnel, VPN, or reverse proxy before restarting production node

## Breaking Changes

| Change | Impact | Mitigation |
|--------|--------|------------|
| RPC binds to localhost | External access blocked | Use SSH tunnel/VPN/proxy |
| JWT required for Engine API | Consensus clients need update | Provide JWT secret path |
| TLS enabled | Clients need CA cert | Use --cacert or system CA |

## Related Issues

- Fixes #296: Security - RPC Authentication and TLS Enforcement
- Relates #249: Multi-Client Setup - Port Management
- Relates #139: Cross-Client Block Validation

## Deployment Notes

1. **Staging First**: Test on devnet before mainnet
2. **Monitor Logs**: Watch for authentication failures
3. **Certificate Renewal**: Set calendar reminder for TLS cert expiry (1 year)
4. **Backup Secrets**: Securely backup JWT secret and TLS keys

---

**Security Impact**: HIGH  
**Breaking Changes**: YES (external RPC access)  
**Migration Required**: YES (for external RPC users)