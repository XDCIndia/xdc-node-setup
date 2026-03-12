# Security Documentation

This document outlines security considerations and recommended mitigations for the XDC Node Setup project.

## Table of Contents

- [Docker Socket Mount Security](#docker-socket-mount-security)
- [RPC Security](#rpc-security)
- [Credential Management](#credential-management)
- [Network Security](#network-security)
- [Report Security Issues](#report-security-issues)

---

## Docker Socket Mount Security

### Issue (#499)

The XDC Agent containers mount the Docker socket (`/var/run/docker.sock`) to monitor container health and status. This is a **necessary tradeoff** that requires careful consideration.

### Why It's Needed

The xdc-agent container requires access to docker.sock to:
- Monitor container health status
- Read container logs for analysis
- Perform container lifecycle operations (restart, etc.)
- Collect metrics from the Docker daemon

### Security Risk

Mounting the Docker socket grants significant privileges:
- **Container Escape Risk**: A compromised agent container could escape to the host
- **Root Equivalent**: Access to docker.sock is equivalent to root on the host
- **Lateral Movement**: Attackers could spawn privileged containers

### Recommended Mitigations

1. **Use Read-Only Mount** (where possible):
   ```yaml
   volumes:
     - /var/run/docker.sock:/var/run/docker.sock:ro
   ```
   Note: `:ro` provides limited protection but doesn't prevent all attacks.

2. **Network Isolation**:
   - Run agent containers on isolated networks
   - Use `network_mode: bridge` instead of `host` where possible
   - Restrict inter-container communication

3. **Capability Restrictions**:
   ```yaml
   cap_drop:
     - ALL
   cap_add:
     - CHOWN
     - SETGID
     - SETUID
   security_opt:
     - no-new-privileges:true
   ```

4. **Dedicated Monitoring User**:
   - Create a dedicated non-root user for monitoring
   - Use Docker's RBAC if available

5. **Alternative: Docker API Proxy**:
   Consider using a restricted Docker API proxy like [Docker Socket Proxy](https://github.com/Tecnativa/docker-socket-proxy) to limit API access.

---

## RPC Security

### Issues (#492, #493)

By default, all XDC node clients now bind RPC to `127.0.0.1` (localhost only) with:
- **CORS**: Restricted to `localhost` (not `*` wildcard)
- **VHosts**: Restricted to `localhost` (not `*` wildcard)
- **RPC Address**: `127.0.0.1` (not `0.0.0.0` which binds all interfaces)

### Configuration

To override for production deployments (with caution):

```bash
# In your .env file or environment
RPC_ADDR=0.0.0.0              # Bind to all interfaces
RPC_ALLOW_ORIGINS=example.com # Specific origin(s)
RPC_VHOSTS=example.com        # Specific vhost(s)
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RPC_ADDR` | `127.0.0.1` | RPC bind address |
| `RPC_ALLOW_ORIGINS` | `localhost` | CORS allowed origins |
| `RPC_VHOSTS` | `localhost` | HTTP virtual hosts |
| `RPC_PORT` | Varies | RPC listening port |

### Production Recommendations

1. **Use a Reverse Proxy**: Put Nginx or Traefik in front with SSL/TLS
2. **Firewall Rules**: Restrict access to specific IPs
3. **Authentication**: Enable dashboard authentication
   ```bash
   DASHBOARD_AUTH_ENABLED=true
   DASHBOARD_USER=secure_admin
   DASHBOARD_PASS=strong_password_here
   ```

---

## Credential Management

### Issue (#498)

Never commit credentials to version control. All sensitive values use environment variable fallbacks.

### Environment Files

Create a `.env` file in your network directory:

```bash
# /mainnet/.xdc-node/.env
GRAFANA_PASSWORD=your_secure_password_here
SKYNET_API_KEY=your_api_key_here
DASHBOARD_PASS=another_secure_password
```

### Template (`.env.example`)

Copy from `.env.example` files and customize:

```bash
cp mainnet/.xdc-node/.env.example mainnet/.xdc-node/.env
# Edit mainnet/.xdc-node/.env with your values
```

### Protected Files (in .gitignore)

```
.env
**/.env
*.secret
*.key
keystore/
```

---

## Network Security

### Default Ports

| Service | Default Port | Bind Address | Notes |
|---------|--------------|--------------|-------|
| Geth RPC | 8545 | 127.0.0.1 | Localhost only |
| Geth WS | 8546 | 127.0.0.1 | Localhost only |
| Erigon RPC | 8547 | 127.0.0.1 | Localhost only |
| Nethermind RPC | 8556 | 127.0.0.1 | Localhost only |
| Reth RPC | 7073 | 127.0.0.1 | Localhost only |
| Dashboard | 7070 | 127.0.0.1 | Localhost only |
| Grafana | 3000 | 127.0.0.1 | Localhost only |

### P2P Ports

P2P ports must be exposed externally for blockchain synchronization:
- Geth: 30303/tcp+udp
- Erigon: 30304/tcp+udp, 30311/tcp+udp
- Nethermind: 30306/tcp+udp
- Reth: 40303/tcp+udp

---

## Installation Security

### Issue (#507)

The `curl | bash` installation pattern has inherent security risks:

1. **MITM Attacks**: If HTTPS is compromised
2. **Supply Chain**: Script could be modified on the server
3. **No Verification**: Hard to verify what will execute

### Safer Installation Methods

**Method 1: Git Clone (Recommended)**
```bash
git clone https://github.com/AnilChinchawale/xdc-node-setup.git
cd xdc-node-setup
bash install.sh
```

**Method 2: Download and Review**
```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/install.sh
# Review the script
cat install.sh
# Then execute
bash install.sh
```

**Method 3: With Verification**
```bash
curl -fsSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/install.sh | bash -s -- --verify
```

---

## Report Security Issues

If you discover a security vulnerability:

1. **DO NOT** open a public issue
2. Email security concerns to: `anil24593@gmail.com`
3. Include detailed description and reproduction steps
4. Allow time for response before public disclosure

---

## Security Checklist

Before deploying to production:

- [ ] Changed all default passwords
- [ ] RPC bound to specific IPs or localhost
- [ ] Firewall rules configured
- [ ] SSL/TLS enabled for external access
- [ ] Dashboard authentication enabled
- [ ] Docker socket mounted read-only where possible
- [ ] Regular security updates applied
- [ ] Monitoring and alerting configured

---

*Last updated: March 2025*
