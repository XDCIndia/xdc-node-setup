# macOS Setup Guide for XDC Node

This guide covers setting up an XDC node on macOS 13+ (Ventura and later) using Docker Desktop.

## Prerequisites

- macOS 13.0 (Ventura) or later
- Intel Mac or Apple Silicon (M1/M2/M3) Mac
- At least 16GB RAM (32GB+ recommended for archive nodes)
- At least 500GB free disk space (SSD required)
- Administrator access

## Step 1: Install Homebrew

Homebrew is the package manager for macOS. Install it by running:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the on-screen instructions. After installation, add Homebrew to your PATH:

```bash
# For Intel Macs
echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/usr/local/bin/brew shellenv)"

# For Apple Silicon Macs
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

## Step 2: Install Required Dependencies

```bash
# Update Homebrew
brew update

# Install dependencies
brew install curl wget jq git
```

## Step 3: Install Docker Desktop

1. Download Docker Desktop for Mac:
   - **Apple Silicon (M1/M2/M3)**: [Docker Desktop for Apple Silicon](https://desktop.docker.com/mac/main/arm64/Docker.dmg)
   - **Intel Macs**: [Docker Desktop for Intel](https://desktop.docker.com/mac/main/amd64/Docker.dmg)

2. Open the downloaded `.dmg` file

3. Drag Docker to Applications

4. Launch Docker Desktop from Applications

5. Grant permissions when prompted (System Extension, etc.)

6. Wait for "Docker Desktop is running" message

### Verify Docker Installation

```bash
docker --version
docker compose version
```

## Step 4: Configure macOS for XDC Node

### Increase File Descriptor Limits

macOS has conservative limits by default. Increase them:

```bash
# Check current limits
ulimit -n

# Create a limits configuration file
sudo tee /etc/sysctl.conf << EOF
kern.maxfiles=65536
kern.maxfilesperproc=65536
EOF

# Apply (requires restart)
```

Add to your shell profile (`~/.zshrc` for macOS default shell):

```bash
cat >> ~/.zshrc << 'EOF'

# Increase file descriptor limits for XDC node
ulimit -n 65536
EOF
```

### Configure macOS Firewall (Optional)

1. Open **System Settings** → **Network** → **Firewall**
2. Enable Firewall if desired
3. Click **Options** and allow Docker Desktop if listed

Note: Docker Desktop handles port mapping automatically.

## Step 5: Set Up XDC Node

### Quick Start (Simple Mode)

```bash
curl -sSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/setup.sh | bash
```

### Advanced Setup

```bash
curl -sSL https://raw.githubusercontent.com/AnilChinchawale/xdc-node-setup/main/setup.sh | bash -s -- --advanced
```

### Manual Installation

```bash
# Clone the repository
git clone https://github.com/AnilChinchawale/XDC-Node-Setup.git
cd XDC-Node-Setup

# Run the setup
./setup.sh
```

## Apple Silicon (M1/M2/M3) Specific Notes

### ARM64 Docker Images

Docker Desktop on Apple Silicon uses ARM64 architecture by default. The XDC Docker images support ARM64:

```bash
# Verify the image architecture
docker pull xinfinorg/xdposchain:latest
docker inspect xinfinorg/xdposchain:latest | grep Architecture
# Should show: "arm64"
```

### Rosetta 2 (Fallback)

If you need to run Intel (amd64) images:

```bash
# Enable Rosetta for x86/amd64 emulation
softwareupdate --install-rosetta --agree-to-license

# In Docker Desktop:
# Settings → Features in development → Use Rosetta for x86/amd64 emulation
```

### Performance Considerations

Apple Silicon Macs generally perform well for XDC nodes:

1. **SSD Speed**: Ensure sufficient free space on internal SSD
2. **Memory**: M1/M2/M3 Macs with unified memory perform well
3. **Thermal**: Extended sync may cause fan noise on MacBook Air

## Managing Your Node

### Basic Commands

```bash
# Check if node is running
docker ps

# View logs
docker logs -f xdc-node

# Stop node
docker stop xdc-node

# Start node
docker start xdc-node

# Restart node
docker restart xdc-node

# Remove container (data is preserved)
docker rm xdc-node
```

### Access RPC

Your node RPC is available at:
- HTTP: `http://localhost:8545`
- WebSocket: `http://localhost:8546`

Test with:
```bash
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545
```

### Grafana Dashboard

Access at: http://localhost:3000
- Default credentials: `admin` / `admin`

## File Locations

### Data Directory

Default: `~/xdcchain` (in your home directory)

```bash
ls -la ~/xdcchain
```

### Configuration

Default: `~/.xdc-config/`

```bash
ls -la ~/.xdc-config/
```

### Logs

```bash
# View setup log
cat ~/xdc-node-setup.log

# View Docker logs
docker logs xdc-node
```

## Important macOS-Specific Notes

### No Host Networking

⚠️ Docker Desktop on macOS does **not** support `--network host`

The setup automatically uses port mapping:
- `8545:8545` (RPC HTTP)
- `8546:8546` (RPC WebSocket)
- `30303:30303` (P2P)
- `30303:30303/udp` (P2P UDP)

### System Integrity Protection (SIP)

Some advanced security features may be limited by macOS SIP. The setup handles this gracefully.

### Time Machine Exclusions

Add the XDC data directory to Time Machine exclusions to prevent backup bloat:

```bash
# Exclude from Time Machine
tmutil addexclusion ~/xdcchain

# Verify
ls -laO ~/ | grep xdcchain
# Should show 'excluded' attribute
```

Or via System Settings:
1. System Settings → General → Time Machine
2. Options
3. Click + and add `~/xdcchain`

## Troubleshooting

### "Docker Desktop not running" Error

```bash
# Check if Docker is running
docker info

# If not, start Docker Desktop from Applications
# Or use: open -a Docker
```

### Permission Denied Errors

```bash
# Fix Docker socket permissions (may be needed after Docker updates)
sudo chmod 666 /var/run/docker.sock
```

### High CPU/Memory Usage

1. Limit Docker resources:
   - Docker Desktop → Settings → Resources
   - Adjust CPU cores and Memory

2. For M1/M2/M3 Macs with 8GB RAM:
   - Limit to 6GB for Docker
   - Consider using a VPS for full nodes

### Slow Sync Performance

1. Ensure using SSD (not external USB drive)
2. Check Docker resource limits
3. Monitor system Activity Monitor for bottlenecks

### Port Already in Use

```bash
# Find process using port 8545
lsof -i :8545

# Kill if needed
kill -9 <PID>
```

### Docker Volume Mount Issues

On macOS, file system events may not propagate correctly. If using volumes:

```bash
# Use delegated mount for better performance
docker run -v ~/xdcchain:/xdcchain:delegated ...
```

## Security Best Practices

### 1. Firewall Configuration

```bash
# Check firewall status
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate

# Enable if needed
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
```

### 2. FileVault Encryption

Ensure FileVault is enabled for disk encryption:

```bash
# Check status
fdesetup status

# Enable if needed
sudo fdesetup enable
```

### 3. Regular Updates

```bash
# Update macOS
softwareupdate -l
softwareupdate -i -a

# Update Homebrew packages
brew update && brew upgrade

# Update Docker Desktop
# Check Docker Desktop → Check for Updates
```

## Comparison: macOS vs Linux

| Feature | Linux | macOS |
|---------|-------|-------|
| Host networking | ✅ Full support | ❌ Not available |
| UFW Firewall | ✅ Available | ❌ Use macOS Firewall |
| Systemd | ✅ Full support | ❌ Not available |
| Performance | ✅ Optimal | ⚠️ Good (Docker overhead) |
| Ease of setup | ⚠️ Moderate | ✅ Easier |

## Next Steps

- [Security Best Practices](../SECURITY.md)
- [Monitoring Guide](../MONITORING.md)
- [Backup and Recovery](../BACKUP.md)

## Support

For help:
- [XDC Documentation](https://docs.xdc.community/)
- [GitHub Issues](https://github.com/AnilChinchawale/xdc-node-setup/issues)
- [XDC Dev Discord](https://discord.gg/xdc)

## Known Limitations

1. **No Host Networking**: Docker Desktop limitation, port mapping used instead
2. **Systemd**: Not available, Docker handles process management
3. **Linux Firewall**: UFW not available, use macOS firewall settings
4. **Performance**: ~5-10% overhead from Docker virtualization layer
