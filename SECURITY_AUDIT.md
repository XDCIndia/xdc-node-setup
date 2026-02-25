# XDC Node Setup - Security Audit Findings

## Executive Summary

This document contains comprehensive security audit findings for the xdc-node-setup repository (SkyOne). The audit was conducted as part of the XDC EVM Expert Agent validation process.

## Critical Issues (P0)

### [P0] S1: RPC CORS Wildcard Configuration
**Risk Level:** Critical  
**Location:** `docker/mainnet/start-node.sh`, environment defaults  
**Description:** RPC CORS is configured with wildcards (`*`) by default, allowing any domain to make RPC calls to the node.

```bash
export RPC_CORS_DOMAIN="${CORS_DOMAIN:-${RPC_CORS:-localhost,https://*.xdc.network,https://*.xinfin.org}}"
export RPC_VHOSTS="${VHOSTS:-*}"
export WS_ORIGINS="${WS_ORIGINS:-*}"
```

**Impact:** If a wallet is unlocked on the node, any malicious website visited by the operator could steal funds.

**Recommendation:**
- Default to `localhost` only
- Add explicit configuration for allowed origins
- Document security implications in setup wizard

### [P0] S2: RPC Bound to 0.0.0.0 by Default
**Risk Level:** Critical  
**Location:** `docker/mainnet/start-node.sh`  
**Description:** RPC address defaults to `0.0.0.0`, exposing the RPC endpoint to all network interfaces.

```bash
export RPC_ADDR="${ADDR:-0.0.0.0}"
export WS_ADDR="${WS_ADDR:-0.0.0.0}"
```

**Impact:** Without proper firewall configuration, RPC is exposed to the internet, enabling remote attacks.

**Recommendation:**
- Default to `127.0.0.1` (localhost only)
- Provide nginx reverse proxy template for external access
- Add firewall configuration checks to setup script

### [P0] S3: Docker Socket Mount Security Risk
**Risk Level:** Critical  
**Location:** `docker/docker-compose.yml` (commented but documented)  
**Description:** Docker socket mount allows container escape to host with root privileges.

**Recommendation:**
- Remove docker socket mount from default configuration
- Use Docker API over TCP with TLS if container monitoring is required
- Document security profile usage: `docker compose --profile docker-monitor up -d`

### [P0] S4: Privileged Container Usage
**Risk Level:** Critical  
**Location:** `docker/docker-compose.monitoring.yml`  
**Description:** cAdvisor runs with `privileged: true`, granting full host access.

**Recommendation:**
- Remove privileged mode
- Use specific capability grants instead
- Document minimum required capabilities

## High Priority Issues (P1)

### [P1] S5: Missing Input Validation in Setup Script
**Risk Level:** High  
**Location:** `setup.sh`  
**Description:** User-provided values (email, node name, ports) are not validated before use.

**Recommendation:**
- Add validation functions for all user inputs
- Sanitize shell-special characters
- Validate port ranges and network configurations

### [P1] S6: Shell Script Sources Config Without Sanitization
**Risk Level:** High  
**Location:** `scripts/lib/*.sh`  
**Description:** Configuration files are sourced directly without validation.

```bash
source "$CONF_FILE"
```

**Recommendation:**
- Parse config files instead of sourcing
- Validate all values before use
- Use restricted shell for config parsing

### [P1] S7: No Rate Limiting on RPC Endpoints
**Risk Level:** High  
**Location:** `docker/docker-compose.yml`  
**Description:** No rate limiting is implemented on RPC endpoints.

**Recommendation:**
- Add nginx reverse proxy with rate limiting
- Implement per-IP connection limits
- Document DDoS protection measures

## Medium Priority Issues (P2)

### [P2] S8: curl | sudo bash Install Pattern
**Risk Level:** Medium  
**Location:** `README.md`  
**Description:** The recommended install method uses `curl | sudo bash` which is inherently insecure.

**Recommendation:**
- Provide package manager installation (APT, Homebrew)
- Add checksum verification to install script
- Document manual installation steps

### [P2] S9: No TLS on Dashboard and Grafana
**Risk Level:** Medium  
**Location:** All services  
**Description:** No TLS encryption for dashboard, Grafana, or RPC endpoints.

**Recommendation:**
- Add Let's Encrypt integration
- Provide self-signed certificate generation
- Document TLS configuration

### [P2] S10: Keystore Password Handling
**Risk Level:** Medium  
**Location:** `docker/mainnet/.pwd` handling  
**Description:** Password file permissions and handling need review.

**Recommendation:**
- Ensure 0600 permissions on password files
- Use Docker secrets for production deployments
- Document secure password management

## Security Best Practices Observed

✅ **Docker Security Options:** `no-new-privileges`, `cap_drop: ALL`  
✅ **Prometheus/Alertmanager:** Bound to localhost (127.0.0.1)  
✅ **Monitoring Network:** Marked as `internal: true`  
✅ **Security Hardening:** Comprehensive `security-harden.sh` script included  
✅ **Fail2ban:** SSH hardening and audit logging included  
✅ **Log Rotation:** Configured on all containers

## Compliance Notes

- CIS benchmark script provided for compliance auditing
- Comprehensive Grafana dashboards for security monitoring
- Audit logging configured for system events

## Recommendations Summary

| Priority | Issue | Effort | Impact |
|----------|-------|--------|--------|
| P0 | RPC CORS wildcard | Low | Critical |
| P0 | RPC bind address | Low | Critical |
| P0 | Docker socket mount | Low | Critical |
| P0 | Privileged containers | Low | Critical |
| P1 | Input validation | Medium | High |
| P1 | Config sanitization | Medium | High |
| P1 | Rate limiting | Medium | High |
| P2 | Install method | Medium | Medium |
| P2 | TLS configuration | Medium | Medium |
| P2 | Password handling | Low | Medium |

## Appendix: XDPoS 2.0 Consensus Security

The node setup correctly implements XDPoS 2.0 consensus parameters:
- Epoch length: 900 blocks
- Gap blocks: 450 blocks before epoch end
- Vote/timeout mechanisms properly configured
- No evidence of consensus parameter tampering

## References

- [XDPoS 2.0 Consensus Spec](https://docs.xdc.network/consensus)
- [Docker Security Best Practices](https://docs.docker.com/develop/security-best-practices/)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
