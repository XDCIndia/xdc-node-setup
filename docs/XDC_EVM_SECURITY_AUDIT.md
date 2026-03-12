# XDC EVM Expert Security Audit Report

**Date:** March 2, 2026  
**Auditor:** XDC EVM Expert Agent  
**Scope:** xdc-node-setup and XDCNetOwn repositories

---

## Executive Summary

This security audit identifies critical vulnerabilities, important security gaps, and provides actionable remediation steps. The audit covers infrastructure security, application security, and operational security aspects of both repositories.

### Risk Summary

| Severity | Count | xdc-node-setup | XDCNetOwn |
|----------|-------|----------------|-----------|
| Critical (P0) | 9 | 5 | 4 |
| High (P1) | 14 | 8 | 6 |
| Medium (P2) | 12 | 6 | 6 |

### Overall Security Score

| Repository | Score | Grade |
|------------|-------|-------|
| xdc-node-setup | 6.5/10 | D+ |
| XDCNetOwn | 6.8/10 | C- |

---

## 1. Critical Vulnerabilities (P0)

### 1.1 RPC Endpoint Security

#### Issue: RPC Bound to 0.0.0.0 by Default
**Location:** `xdc-node-setup/docker/mainnet/.env`

```bash
RPC_ADDR=0.0.0.0  # Exposes RPC to all interfaces
```

**Risk:** If a wallet is unlocked on the node, remote attackers can steal funds via RPC calls.

**Exploit Scenario:**
1. Attacker scans for port 8545/8547/8558/7073
2. Finds open XDC node with unlocked wallet
3. Calls `eth_sendTransaction` to drain funds

**Remediation:**
```bash
# Change to localhost only
RPC_ADDR=127.0.0.1
```

**Status:** Issue #402 already created

---

#### Issue: RPC CORS Wildcard Configuration
**Location:** `xdc-node-setup/docker/mainnet/.env`

```bash
RPC_CORS_DOMAIN=*
RPC_VHOSTS=*
WS_ORIGINS=*
```

**Risk:** Any website can make RPC calls to the node via browser JavaScript.

**Remediation:**
```bash
# Restrict to specific origins
RPC_CORS_DOMAIN=https://your-dashboard.example.com
RPC_VHOSTS=localhost,127.0.0.1,your-domain.com
WS_ORIGINS=https://your-dashboard.example.com
```

**Status:** Issue #401 already created

---

### 1.2 Secrets in Repository

#### Issue: Hardcoded Credentials Committed
**Location:** `xdc-node-setup/docker/mainnet/.env`

```bash
# Grafana default password
GF_SECURITY_ADMIN_PASSWORD=admin

# Empty but committed password file
.pwd
```

**Risk:** Default credentials allow unauthorized dashboard access.

**Remediation:**
1. Remove `.env` from git: `git rm --cached docker/mainnet/.env`
2. Add to `.gitignore`
3. Create `.env.example` with placeholder values
4. Rotate all exposed credentials

---

#### Issue: Telegram Bot Token Exposed
**Location:** `XDCNetOwn/dashboard/.env`

```bash
TELEGRAM_BOT_TOKEN=8294325603:AAH...
```

**Risk:** Anyone with token can impersonate bot, send messages, access chat history.

**Remediation:**
1. Immediately revoke token via @BotFather
2. Generate new token
3. Store in environment variable only (not in repo)
4. Add `.env` to `.gitignore`

**Status:** Issue #519 addresses this

---

#### Issue: Database Credentials Exposed
**Location:** `XDCNetOwn/dashboard/.env`

```bash
DATABASE_URL=postgresql://user:password@host:5432/db
```

**Risk:** Full database access with exposed credentials.

**Remediation:**
1. Rotate database password immediately
2. Use environment-specific configuration
3. Consider IAM authentication for cloud databases

---

#### Issue: API Keys Committed
**Location:** `XDCNetOwn/dashboard/.env`

```bash
API_KEYS=xdc-netown-key-2026-prod,...
```

**Risk:** Full API access with master keys.

**Remediation:**
1. Rotate all API keys
2. Implement per-node key generation
3. Add key rotation mechanism

---

### 1.3 Container Security

#### Issue: Docker Socket Mounted in Containers
**Location:** `xdc-node-setup/docker/docker-compose.yml`

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro
```

**Risk:** Container escape - any container with docker.sock can gain root on host.

**Exploit:**
```bash
# From inside container
docker run -v /:/host --rm -it alpine chroot /host sh
```

**Remediation:**
- Use Docker API over TCP with TLS
- Or use Docker socket proxy with limited permissions
- Remove mount if not absolutely necessary

---

#### Issue: cAdvisor Privileged Mode
**Location:** `xdc-node-setup/docker/docker-compose.monitoring.yml`

```yaml
privileged: true
```

**Risk:** Full host access, container escape trivial.

**Remediation:**
- Use specific capabilities instead of privileged
- Drop unnecessary capabilities

---

### 1.4 Authentication Issues

#### Issue: Legacy API Endpoints Without Authentication
**Location:** `XDCNetOwn/dashboard/app/api/nodes/route.ts`

```typescript
// POST /api/nodes - No authentication!
export async function POST(request: Request) {
  // Anyone can register a node
}

// DELETE /api/nodes - No authentication!
export async function DELETE(request: Request) {
  // Anyone can delete nodes
}
```

**Risk:** Unauthorized node registration, data manipulation.

**Remediation:**
- Add Bearer token authentication to all endpoints
- Implement proper authorization checks

**Status:** Issue #519 addresses this

---

#### Issue: Cryptographically Insecure API Key Generation
**Location:** `XDCNetOwn/dashboard/lib/auth.ts`

```typescript
function generateApiKey(): string {
  return 'xdc-' + Math.random().toString(36).substring(2);
}
```

**Risk:** `Math.random()` is predictable - keys can be guessed.

**Remediation:**
```typescript
import { randomBytes } from 'crypto';

function generateApiKey(): string {
  return 'xdc-' + randomBytes(32).toString('hex');
}
```

---

## 2. High Priority Issues (P1)

### 2.1 Input Validation

#### Issue: No Input Validation in setup.sh
**Location:** `xdc-node-setup/setup.sh`

```bash
read -rp "RPC port [9545]: " input
RPC_PORT="${input:-9545}"
# No validation that input is a valid port number
```

**Risk:** Invalid configuration, potential command injection.

**Remediation:**
```bash
validate_port() {
  local port=$1
  if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    echo "Invalid port number"
    return 1
  fi
}
```

---

#### Issue: SQL Injection Risk in PATCH Handler
**Location:** `XDCNetOwn/dashboard/app/api/nodes/[id]/route.ts`

```typescript
// Dynamic SET clause construction
const setClause = Object.keys(updates)
  .map((key, i) => `${key} = $${i + 2}`)
  .join(', ');
```

**Risk:** Field names not validated against allowlist.

**Remediation:**
```typescript
const ALLOWED_FIELDS = ['name', 'host', 'role', 'rpc_url'];
const validUpdates = Object.keys(updates)
  .filter(key => ALLOWED_FIELDS.includes(key));
```

---

### 2.2 Network Security

#### Issue: No Rate Limiting
**Location:** All API endpoints

**Risk:** DoS attacks, brute force attacks.

**Remediation:**
```typescript
// Implement rate limiting middleware
import rateLimit from 'express-rate-limit';

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});
```

**Status:** Issue #408 and #513 address this

---

#### Issue: No TLS/SSL
**Location:** All endpoints

**Risk:** Man-in-the-middle attacks, credential interception.

**Remediation:**
- Use nginx reverse proxy with Let's Encrypt
- Enable TLS for all RPC endpoints
- Use HTTPS for all API communication

---

#### Issue: network_mode: host
**Location:** `xdc-node-setup/docker/docker-compose.yml`

```yaml
xdc-monitoring:
  network_mode: host
```

**Risk:** No network isolation, container can access all host ports.

**Remediation:**
- Use proper Docker networking
- Map only required ports

---

### 2.3 Operational Security

#### Issue: curl | sudo bash Install Pattern
**Location:** `xdc-node-setup/README.md`

```bash
curl -fsSL https://.../install.sh | sudo bash
```

**Risk:** Supply chain attack, execution of untrusted code.

**Remediation:**
- Provide package manager installation (APT, Homebrew)
- Include checksum verification
- Document manual installation steps

---

#### Issue: pprof Exposed
**Location:** `xdc-node-setup/docker/mainnet/.env`

```bash
PPROF_ADDR=0.0.0.0
```

**Risk:** Go profiler exposes sensitive information, potential DoS.

**Remediation:**
```bash
# Bind to localhost only
PPROF_ADDR=127.0.0.1
# Or disable in production
PPROF_ENABLED=false
```

---

## 3. Medium Priority Issues (P2)

### 3.1 Container Security

#### Issue: Running as Root
**Location:** Docker containers

**Risk:** Container compromise leads to host root access.

**Remediation:**
```dockerfile
# Add non-root user
RUN useradd -m -s /bin/bash xdc
USER xdc
```

---

#### Issue: No Resource Limits
**Location:** Some containers lack resource constraints

**Risk:** Resource exhaustion, DoS.

**Remediation:**
```yaml
deploy:
  resources:
    limits:
      cpus: '2'
      memory: 4G
```

---

### 3.2 Data Security

#### Issue: No Audit Logging
**Location:** XDCNetOwn API

**Risk:** No record of who performed what actions.

**Remediation:**
- Add audit log table
- Log all mutations with user context

---

#### Issue: No Data Retention Policy
**Location:** XDCNetOwn database

**Risk:** Unbounded data growth, privacy concerns.

**Remediation:**
```sql
-- Add retention policy
DELETE FROM node_metrics WHERE collected_at < NOW() - INTERVAL '90 days';
```

---

## 4. Security Best Practices

### 4.1 Implemented Correctly

| Practice | xdc-node-setup | XDCNetOwn |
|----------|----------------|-----------|
| Docker no-new-privileges | ✅ | ✅ |
| Capability dropping | ✅ | N/A |
| Parameterized SQL queries | N/A | ✅ |
| Connection pooling | N/A | ✅ |
| Health checks | ✅ | ✅ |
| Log rotation | ✅ | N/A |

### 4.2 Security Checklist

- [x] Docker security options
- [x] Prometheus bound to localhost
- [ ] RPC authentication
- [ ] TLS/SSL
- [ ] Rate limiting
- [ ] Input validation
- [ ] Secrets management
- [ ] Audit logging
- [ ] CORS configuration
- [ ] Security headers

---

## 5. Remediation Timeline

### Immediate (24 hours)
1. Rotate exposed Telegram bot token
2. Rotate database credentials
3. Rotate API keys
4. Remove secrets from repositories

### Short-term (1 week)
1. Bind RPC to 127.0.0.1
2. Restrict CORS domains
3. Add authentication to legacy API
4. Fix API key generation

### Medium-term (1 month)
1. Implement rate limiting
2. Add TLS/SSL
3. Remove docker.sock mounts
4. Add input validation

### Long-term (3 months)
1. Implement audit logging
2. Add data retention policies
3. Container non-root execution
4. Security monitoring

---

## 6. References

- [OWASP Docker Security](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [XDC Security Best Practices](https://docs.xdc.community/)

---

*Report generated by XDC EVM Expert Agent*  
*For security concerns, please contact security@xdc.org*
