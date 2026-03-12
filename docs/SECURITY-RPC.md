# RPC Security Best Practices

## 🚨 Issue #355 - RPC Security Hardening

**Priority:** P0 (Critical)  
**Status:** FIXED  
**Date:** 2026-02-28

### Problem

Previous default configuration bound RPC endpoints to `0.0.0.0` (all network interfaces), exposing node RPC to potential unauthorized access.

### Fix Applied

All XDC client startup scripts now default to **localhost-only** binding:

```bash
# Before (INSECURE):
--http.addr 0.0.0.0

# After (SECURE):
--http.addr 127.0.0.1
```

### Files Modified

- `docker/geth-pr5/start-gp5.sh`
- `docker/apothem/start-node.sh`
- `docker/apothem/start-erigon.sh`
- `docker/erigon/start-erigon.sh`
- `docker/nethermind/start-nethermind.sh`
- `docker/reth/start-reth.sh`

---

## ✅ Secure Default Configuration

### RPC Binding

```bash
# Environment variables (docker-compose.yml or .env)
HTTP_ADDR=127.0.0.1  # Localhost only (DEFAULT - SECURE)
HTTP_PORT=8545
HTTP_API=eth,net,web3  # NEVER include: admin,debug,personal
HTTP_CORS_DOMAIN=http://localhost:3000
HTTP_VHOSTS=localhost,127.0.0.1
```

### WebSocket Binding

```bash
WS_ADDR=127.0.0.1  # Localhost only (DEFAULT - SECURE)
WS_PORT=8546
WS_API=eth,net,web3
WS_ORIGINS=localhost
```

---

## 🔓 External RPC Access (Advanced)

If you **must** expose RPC externally, use one of these secure methods:

### Option 1: Nginx Reverse Proxy (RECOMMENDED)

**Why:** Adds authentication, rate limiting, SSL/TLS, logging

```nginx
# /etc/nginx/sites-available/xdc-rpc
upstream xdc_rpc {
    server 127.0.0.1:8545;
}

server {
    listen 443 ssl http2;
    server_name rpc.yourdomain.com;

    ssl_certificate /etc/ssl/certs/rpc.yourdomain.com.crt;
    ssl_certificate_key /etc/ssl/private/rpc.yourdomain.com.key;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=rpc:10m rate=60r/m;
    limit_req zone=rpc burst=10 nodelay;

    # JWT Authentication (optional)
    auth_request /auth;

    location / {
        proxy_pass http://xdc_rpc/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

### Option 2: SSH Tunnel

```bash
# On your local machine:
ssh -L 8545:127.0.0.1:8545 -p 12141 root@YOUR_NODE_IP

# Now access RPC via:
curl http://localhost:8545
```

### Option 3: VPN (Wireguard/OpenVPN)

Set up a VPN and connect through the private network.

### Option 4: Firewall + IP Whitelist (LAST RESORT)

```bash
# Only if you understand the risks:
ufw allow from YOUR_TRUSTED_IP to any port 8545 proto tcp
```

---

## ⚠️ NEVER DO THIS IN PRODUCTION

```bash
# ❌ DANGER: Exposes RPC to the internet
HTTP_ADDR=0.0.0.0
HTTP_API=admin,debug,personal,eth,net,web3  # Includes dangerous APIs
HTTP_CORS_DOMAIN=*  # Allows any origin
HTTP_VHOSTS=*  # Allows any virtual host
```

**Why this is dangerous:**
- Anyone can query your node
- `admin` API allows node shutdown
- `debug` API exposes internal state
- `personal` API manages accounts/wallets

---

## 🔒 Firewall Configuration

Even with localhost binding, ensure firewall rules are correct:

```bash
# P2P ports (OPEN to internet for node discovery):
sudo ufw allow 30303/tcp comment 'XDC Geth P2P'
sudo ufw allow 30303/udp comment 'XDC Geth Discovery'
sudo ufw allow 30304/tcp comment 'XDC Erigon P2P'
sudo ufw allow 30304/udp comment 'XDC Erigon Discovery'
sudo ufw allow 30306/tcp comment 'XDC Nethermind P2P'
sudo ufw allow 30306/udp comment 'XDC Nethermind Discovery'
sudo ufw allow 40303/tcp comment 'XDC Reth P2P'

# RPC ports (BLOCKED from internet):
# No ufw rules needed - localhost-only binding handles this

# SSH (OPEN to your IP only):
sudo ufw allow from YOUR_IP to any port 12141 proto tcp comment 'SSH from admin'
```

---

## 📊 Multi-Client Port Allocation

See [PORT-ALLOCATION.md](./PORT-ALLOCATION.md) for complete port reference.

| Client | RPC Port | WS Port | P2P Port | Metrics |
|--------|----------|---------|----------|---------|
| Geth XDC | 8545 | 8546 | 30303 | 6060 |
| Erigon XDC | 8547 | 8548 | 30304/30311 | 6061 |
| Nethermind XDC | 8558 | 8559 | 30306 | 6070 |
| Reth XDC | 7073 | 7074 | 40303 | 6071 |

---

## 🛡️ Security Checklist

- [ ] RPC bound to `127.0.0.1` (not `0.0.0.0`)
- [ ] Dangerous APIs disabled (`admin`, `debug`, `personal`)
- [ ] CORS domain restricted (not `*`)
- [ ] Virtual hosts restricted (not `*`)
- [ ] Firewall configured (RPC ports not exposed)
- [ ] SSH uses non-default port (12141)
- [ ] SSH key authentication only (no passwords)
- [ ] Regular security updates applied
- [ ] Monitoring and alerting enabled
- [ ] External access via reverse proxy (if needed)

---

## 📚 References

- [XDC Node Setup Security Guide](./SECURITY.md)
- [Port Allocation Reference](./PORT-ALLOCATION.md)
- [Ethereum JSON-RPC Spec](https://ethereum.github.io/execution-apis/api-documentation/)
- [OWASP API Security Top 10](https://owasp.org/www-project-api-security/)
