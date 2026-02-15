# SSL/HTTPS Setup for SkyOne Dashboard

This guide explains how to enable HTTPS for your SkyOne production dashboard using Let's Encrypt SSL certificates with nginx as a reverse proxy.

## Quick Start

### Option 1: Using the Automated Script (Recommended)

```bash
# Run the SSL setup script
sudo ./scripts/setup-ssl.sh --domain dashboard.yourdomain.com --email admin@yourdomain.com

# Or via the xdc CLI
xdc ssl --domain dashboard.yourdomain.com --email admin@yourdomain.com
```

### Option 2: Using Docker Compose with Environment Variables

You can also enable HTTPS directly in the dashboard container by setting environment variables:

```yaml
# docker-compose.yml
services:
  xdc-agent:
    environment:
      - HTTPS_ENABLED=true
      - SSL_CERT_PATH=/certs/fullchain.pem
      - SSL_KEY_PATH=/certs/privkey.pem
    volumes:
      - /etc/letsencrypt/live/yourdomain.com:/certs:ro
```

## Prerequisites

1. **A registered domain name** pointing to your server's IP address
2. **Port 80 and 443 open** in your firewall
3. **Root/sudo access** on the server
4. **Nginx installed** (script will auto-install if missing)

## Detailed Setup

### Step 1: Configure DNS

Before running the setup, ensure your domain's A record points to your server's IP:

```
dashboard.yourdomain.com → YOUR_SERVER_IP
```

You can verify DNS propagation:
```bash
dig dashboard.yourdomain.com
nslookup dashboard.yourdomain.com
```

### Step 2: Run SSL Setup

```bash
# Basic setup
sudo ./scripts/setup-ssl.sh --domain dashboard.yourdomain.com --email admin@yourdomain.com

# Test with staging environment (no rate limits)
sudo ./scripts/setup-ssl.sh --domain dashboard.yourdomain.com --email admin@yourdomain.com --staging

# Custom dashboard port (if not using default 7070)
sudo ./scripts/setup-ssl.sh --domain dashboard.yourdomain.com --email admin@yourdomain.com --port 3000
```

### Step 3: Verify HTTPS

After setup completes, access your dashboard at:
```
https://dashboard.yourdomain.com
```

## Using the xdc CLI

### Install SSL
```bash
xdc ssl --domain dashboard.yourdomain.com --email admin@yourdomain.com
```

### Renew Certificates
```bash
xdc ssl --renew
```

### Revoke Certificate
```bash
xdc ssl --domain dashboard.yourdomain.com --revoke
```

## Manual Setup (Advanced)

If you prefer to configure nginx manually:

### 1. Install Nginx and Certbot

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y nginx certbot python3-certbot-nginx

# CentOS/RHEL
sudo yum install -y nginx certbot python3-certbot-nginx
```

### 2. Create Nginx Configuration

Copy the template from `configs/nginx/skyone-ssl.conf`:

```bash
sudo cp configs/nginx/skyone-ssl.conf /etc/nginx/sites-available/dashboard
```

Edit the file and replace:
- `{{DOMAIN}}` with your domain name
- `{{DASHBOARD_PORT}}` with your dashboard port (default: 7070)
- `{{SSL_CERT_PATH}}` with `/etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem`
- `{{SSL_KEY_PATH}}` with `/etc/letsencrypt/live/YOUR_DOMAIN/privkey.pem`

### 3. Obtain SSL Certificate

```bash
sudo certbot certonly --standalone -d dashboard.yourdomain.com
```

### 4. Enable Site and Reload Nginx

```bash
sudo ln -s /etc/nginx/sites-available/dashboard /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

## Certificate Renewal

Certificates are automatically renewed via cron. The setup script installs a daily cron job at 3:00 AM.

### Manual Renewal

```bash
# Test renewal (dry run)
sudo certbot renew --dry-run

# Force renewal
sudo certbot renew --force-renewal
```

## Security Features

The nginx configuration includes:

- **TLS 1.2 and 1.3** only (no older, insecure protocols)
- **Strong cipher suites**
- **HSTS headers** (HTTP Strict Transport Security)
- **X-Frame-Options** (clickjacking protection)
- **X-Content-Type-Options** (MIME sniffing protection)
- **X-XSS-Protection** (XSS filter)
- **Referrer-Policy** (privacy protection)
- **Gzip compression** for better performance
- **OCSP Stapling** for faster certificate validation

## Troubleshooting

### "Could not resolve domain"
- Ensure DNS A record is configured correctly
- Wait for DNS propagation (can take up to 24 hours)
- Use `dig` or `nslookup` to verify

### "Connection refused" or "Connection timeout"
- Check firewall rules for ports 80 and 443
- Verify nginx is running: `sudo systemctl status nginx`

### "Certificate issuance failed"
- Check that port 80 is accessible from the internet
- Try with `--staging` flag to test without rate limits
- Check certbot logs: `sudo journalctl -u certbot`

### Rate Limits
Let's Encrypt has rate limits:
- 50 certificates per registered domain per week
- 5 duplicate certificates per week

Use `--staging` for testing to avoid hitting limits.

### Dashboard Not Loading
- Verify the dashboard is running: `xdc status`
- Check nginx error logs: `sudo tail -f /var/log/nginx/xdc-dashboard-error.log`
- Test proxy connection: `curl http://localhost:7070/api/health`

## File Locations

| Component | Path |
|-----------|------|
| SSL Certificates | `/etc/letsencrypt/live/YOUR_DOMAIN/` |
| Nginx Config | `/etc/nginx/sites-available/YOUR_DOMAIN` |
| Nginx Logs | `/var/log/nginx/xdc-dashboard-*.log` |
| Renewal Script | `/usr/local/bin/xdc-ssl-renew` |
| Cron Job | User crontab (daily at 3:00 AM) |

## Environment Variables for Docker

When running the dashboard in Docker, you can pass these environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `HTTPS_ENABLED` | Enable HTTPS mode | `false` |
| `SSL_CERT_PATH` | Path to SSL certificate | - |
| `SSL_KEY_PATH` | Path to SSL private key | - |
| `DASHBOARD_PORT` | Dashboard internal port | `3000` |

## Next.js Custom Server HTTPS

If you need HTTPS directly in the Next.js custom server (without nginx):

```javascript
// server.js or next.config modification
const https = require('https');
const fs = require('fs');
const { parse } = require('url');
const next = require('next');

const dev = process.env.NODE_ENV !== 'production';
const app = next({ dev });
const handle = app.getRequestHandler();

const httpsOptions = {
  key: fs.readFileSync(process.env.SSL_KEY_PATH),
  cert: fs.readFileSync(process.env.SSL_CERT_PATH)
};

app.prepare().then(() => {
  https.createServer(httpsOptions, (req, res) => {
    const parsedUrl = parse(req.url, true);
    handle(req, res, parsedUrl);
  }).listen(3000, (err) => {
    if (err) throw err;
    console.log('> Ready on https://localhost:3000');
  });
});
```

## Support

For issues or questions:
- GitHub Issues: https://github.com/AnilChinchawale/xdc-node-setup/issues
- Documentation: https://github.com/AnilChinchawale/xdc-node-setup/tree/main/docs
