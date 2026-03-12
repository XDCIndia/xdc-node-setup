# Security Policy

## Supported Versions

The following versions of XDC Node Setup are currently supported with security updates:

| Version | Supported          |
| ------- | ------------------ |
| 3.x.x   | :white_check_mark: |
| 2.x.x   | :white_check_mark: |
| < 2.0   | :x:                |

## Reporting a Vulnerability

We take security seriously. If you discover a security vulnerability, please follow these steps:

### 1. Do Not Open a Public Issue

Please **do not** file a public issue or pull request for security vulnerabilities, as this could expose the vulnerability to malicious actors before a fix is available.

### 2. Contact Us Directly

Send a detailed report to:

- **Email:** security@xdc.network
- **Subject:** `[SECURITY] XDC Node Setup - Brief Description`

### 3. Include the Following Information

Your report should include:

- **Description:** Clear description of the vulnerability
- **Impact:** What could an attacker achieve?
- **Steps to Reproduce:** Detailed steps to reproduce the issue
- **Affected Versions:** Which versions are affected?
- **Proof of Concept:** If available, include a minimal proof of concept
- **Suggested Fix:** If you have one, include a proposed fix

### 4. Response Timeline

We will acknowledge receipt of your vulnerability report within **48 hours** and will provide a more detailed response within **5 business days** indicating:

- Whether we can confirm the vulnerability
- Our planned remediation steps
- An estimated timeline for a fix

## Security Best Practices

### Running XDC Nodes Securely

1. **Use Non-Root Containers**
   - All official Docker images run as non-root users
   - Do not override the `USER` directive in Dockerfiles

2. **Enable RPC Rate Limiting**
   - Configure rate limiting to prevent abuse
   - Use nginx proxy with the provided configuration

3. **Use TLS for RPC Endpoints**
   - Enable HTTPS for all JSON-RPC endpoints
   - Use Let's Encrypt for production certificates

4. **Firewall Configuration**
   - Only expose necessary ports (8545 for RPC, 30303 for P2P)
   - Use firewall rules to restrict access to admin endpoints

5. **Keep Dependencies Updated**
   - Regularly update base images and dependencies
   - Monitor security advisories for used components

6. **Use Secrets Management**
   - Never commit private keys or passwords to version control
   - Use Docker secrets or environment files for sensitive data

### Security Features

This project includes several built-in security features:

- **Container Security**: All containers run as non-root users
- **Rate Limiting**: Configurable RPC rate limiting via nginx
- **TLS Support**: Built-in support for TLS/HTTPS termination
- **Vulnerability Scanning**: Automated Trivy scanning in CI/CD
- **ShellCheck**: All shell scripts are linted for security issues

## Security Updates

Security updates will be released as patch versions (e.g., 3.0.1). We recommend:

1. Watching this repository for releases
2. Reading the changelog for security-related fixes
3. Updating promptly when security patches are released

## Acknowledgments

We thank the following security researchers who have responsibly disclosed vulnerabilities:

*This section will be updated with acknowledgments as vulnerabilities are reported and fixed.*

## Security-Related Configuration

### Environment Variables

| Variable | Description | Security Impact |
|----------|-------------|-----------------|
| `RPC_RATE_LIMIT` | Requests per minute per IP | Prevents RPC abuse |
| `TLS_ENABLED` | Enable TLS termination | Encrypts RPC traffic |
| `GF_SECURITY_ADMIN_PASSWORD` | Grafana admin password | Protects monitoring |

### File Permissions

Ensure proper permissions on sensitive files:

```bash
chmod 600 .env
chmod 600 certs/server.key
chmod 644 certs/server.crt
```

## Compliance

This project aims to follow security best practices:

- OWASP Docker Security Guidelines
- CIS Docker Benchmark
- Supply-chain Levels for Software Artifacts (SLSA)

## Contact

For questions about this security policy, contact:

- **Security Team:** security@xdc.network
- **Project Maintainers:** Anil Chinchawale (github.com/AnilChinchawale)

---

Last Updated: March 2025
