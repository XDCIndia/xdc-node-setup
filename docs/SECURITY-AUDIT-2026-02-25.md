# XDC Node Setup - Security Audit Report

**Date:** February 25, 2026  
**Auditor:** XDC EVM Expert Agent  
**Repository:** https://github.com/AnilChinchawale/xdc-node-setup  
**Version:** v2.2.0

---

## Executive Summary

This security audit identifies **4 Critical (P0)**, **8 Important (P1)**, and **6 Low (P2)** security issues in the XDC Node Setup repository. Immediate action is required for P0 issues to prevent potential security breaches.

### Risk Assessment

| Severity | Count | Status |
|----------|-------|--------|
| 🔴 P0 - Critical | 4 | Requires immediate action |
| 🟡 P1 - Important | 8 | Address within 30 days |
| 🔵 P2 - Low | 6 | Address within 90 days |

---

## Critical Issues (P0)

### 1. Hardcoded Credentials in Repository

**Issue:** Sensitive credentials committed to git history

**Location:**
- `docker/mainnet/.env` - Grafana password "changeme"
- `docker/mainnet/.pwd` - Keystore password
- Empty API keys in configuration files

**Impact:**
- Unauthorized access to deployed nodes
- Potential fund theft if wallets are unlocked
- Compliance violations

**Remediation:**
1. Immediately rotate all exposed credentials
2. Use BFG Repo-Cleaner to remove from git history
3. Add `.env` and `*.pwd` to `.gitignore`
4. Create `.env.example` templates

### 2. RPC CORS Wildcard Configuration

**Issue:** RPC endpoints allow cross-origin requests from any domain

**Location:** `docker/mainnet/.env`

```
RPC_CORS_DOMAIN=*
RPC_VHOSTS=*
WS_ORIGINS=*
```

**Impact:**
- Any website can call node RPC methods
- CSRF attacks possible
- Information disclosure

**Remediation:**
```bash
# Secure defaults
RPC_CORS_DOMAIN=localhost,127.0.0.1
RPC_VHOSTS=localhost,127.0.0.1
WS_ORIGINS=localhost,127.0.0.1
```

### 3. RPC Bound to 0.0.0.0

**Issue:** RPC exposed on all network interfaces

**Impact:**
- Bypasses firewall if not explicitly configured
- Potential unauthorized access

**Remediation:**
Bind to localhost and use reverse proxy:
```yaml
ports:
  - "127.0.0.1:8545:8545"
```

### 4. Docker Socket Mount Creates Container Escape Risk

**Issue:** Docker socket mounted into containers

**Location:** `docker-compose.yml`

**Impact:**
- Container escape to host root access
- Full host compromise

**Remediation:**
- Remove docker.sock mounts
- Use Docker API over TCP with TLS
- Run cAdvisor without privileged mode

---

## Important Issues (P1)

### 5. pprof Profiler Exposed

**Issue:** Go pprof profiler on 0.0.0.0

**Remediation:** Bind to localhost or disable in production

### 6. No Rate Limiting on RPC

**Issue:** RPC endpoints lack rate limiting

**Remediation:** Implement nginx rate limiting or application-level throttling

### 7. No TLS on Endpoints

**Issue:** No encryption for RPC, WS, Dashboard

**Remediation:** Implement Let's Encrypt or provide TLS configuration

### 8. curl | sudo bash Install Pattern

**Issue:** Remote code execution risk during installation

**Remediation:** Provide package manager installation (APT, Homebrew)

### 9. No Input Validation in setup.sh

**Issue:** User inputs not sanitized

**Remediation:** Add input validation and sanitization

### 10. Grafana Default Credentials

**Issue:** Grafana admin/admin default

**Remediation:** Force password change on first login

### 11. No Audit Logging

**Issue:** No record of administrative actions

**Remediation:** Implement audit logging for all mutations

### 12. Shell Script Sources Without Sanitization

**Issue:** `source "$CONF_FILE"` without validation

**Remediation:** Validate config files before sourcing

---

## Low Priority Issues (P2)

- Missing Content Security Policy headers
- No automated security scanning in CI
- Secrets not rotated automatically
- No security.txt file
- Missing dependency vulnerability scanning
- No incident response documentation

---

## Recommendations

### Immediate Actions (24-48 hours)

1. Rotate all exposed credentials
2. Remove sensitive files from git history
3. Update .gitignore
4. Notify users to update their configurations

### Short-term Actions (1-2 weeks)

1. Implement secure defaults for all services
2. Add security documentation
3. Create security checklist for deployments
4. Add pre-commit hooks for secret detection

### Long-term Actions (1-3 months)

1. Implement comprehensive security testing
2. Add automated vulnerability scanning
3. Create incident response plan
4. Obtain security certification (SOC2)

---

## Compliance Considerations

| Framework | Status | Notes |
|-----------|--------|-------|
| SOC2 | ⚠️ Partial | Needs audit logging, access controls |
| ISO 27001 | ⚠️ Partial | Needs risk assessment, policies |
| GDPR | ✅ Compliant | No PII collection |
| PCI DSS | N/A | No payment processing |

---

## Appendix: Security Checklist

### Pre-deployment

- [ ] Change all default passwords
- [ ] Configure firewall rules
- [ ] Enable audit logging
- [ ] Set up monitoring and alerting
- [ ] Document incident response procedures

### Post-deployment

- [ ] Verify RPC is not exposed to internet
- [ ] Check CORS configuration
- [ ] Confirm TLS is enabled
- [ ] Test backup and recovery
- [ ] Review access logs

---

*Report generated by XDC EVM Expert Agent - February 25, 2026*
