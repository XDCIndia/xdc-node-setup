# Windows Setup Guide for XDC Node

This guide covers setting up an XDC node on Windows 10/11 using WSL2 (Windows Subsystem for Linux) and Docker Desktop.

## Prerequisites

- Windows 10 version 2004+ (Build 19041+) or Windows 11
- Administrator access to your machine
- At least 8GB RAM (16GB+ recommended)
- At least 500GB free disk space (SSD strongly recommended)

## Step 1: Install WSL2

### Option A: Automatic Installation (Recommended)

Open PowerShell as Administrator and run:

```powershell
wsl --install
```

This will install WSL2 with Ubuntu as the default distribution. **Restart your computer** when prompted.

### Option B: Manual Installation

If the automatic method doesn't work:

1. Enable WSL2:
```powershell
# In PowerShell (Admin)
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
```

2. Restart your computer

3. Download and install the WSL2 Linux kernel update package:
   - [WSL2 Linux Kernel Update Package](https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi)

4. Set WSL2 as the default:
```powershell
wsl --set-default-version 2
```

5. Install Ubuntu from Microsoft Store:
   - Open Microsoft Store
   - Search for "Ubuntu 22.04 LTS"
   - Click "Get" and install

## Step 2: Install Docker Desktop

1. Download Docker Desktop for Windows:
   - [Docker Desktop Download](https://www.docker.com/products/docker-desktop)

2. Run the installer with default settings

3. During installation, ensure **"Use WSL 2 instead of Hyper-V"** is checked

4. After installation, open Docker Desktop

5. Go to **Settings → Resources → WSL Integration**

6. Enable integration with your installed Ubuntu distribution:
   - Toggle on "Enable integration with my default WSL distro"
   - Or specifically enable for Ubuntu

7. Click **Apply & Restart**

## Step 3: Configure Ubuntu

1. Open Ubuntu (from Start menu or run `wsl` in PowerShell)

2. Create a user if prompted (this will be your Linux username)

3. Update packages:
```bash
sudo apt update && sudo apt upgrade -y
```

4. Install required dependencies:
```bash
sudo apt install -y curl wget jq git
```

## Step 4: Set Up XDC Node

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
git clone https://github.com/AnilChinchawale/XDC-Node-Setup.git
cd XDC-Node-Setup
./setup.sh
```

## Step 5: Access Your Node

### From Windows

The XDC node RPC will be available at:
- `http://localhost:8545` (HTTP)
- `http://localhost:8546` (WebSocket)

### From WSL2 Ubuntu

Use:
- `http://localhost:8545` or
- `http://127.0.0.1:8545`

### Grafana Dashboard

Access Grafana at: http://localhost:3000
- Default username: `admin`
- Default password: `admin` (change on first login)

## Managing Your Node

### Start/Stop Node

From PowerShell or Command Prompt:
```powershell
# Stop node
wsl -e docker stop xdc-node

# Start node
wsl -e docker start xdc-node

# View logs
wsl -e docker logs -f xdc-node
```

From WSL2 Ubuntu:
```bash
# Stop node
docker stop xdc-node

# Start node
docker start xdc-node

# View logs
docker logs -f xdc-node
```

### Check Node Status

```powershell
wsl -e docker ps
```

Or from WSL2:
```bash
docker ps
```

## File Locations

### Data Directory
- **In WSL2**: `~/xdcchain` or `/root/xdcchain`
- **Windows path**: `\\wsl$\Ubuntu\home\<username>\xdcchain`

### Configuration
- **In WSL2**: `~/.xdc-config/`
- **Windows path**: `\\wsl$\Ubuntu\home\<username>\.xdc-config`

## Important Notes

### Networking Differences

⚠️ **Docker Desktop does not support `--network host`**

On Windows/WSL2, Docker uses port mapping instead of host networking:
- RPC: `8545:8545`
- WebSocket: `8546:8546`
- P2P: `30303:30303`
- Grafana: `3000:3000`

### Firewall Configuration

Windows Defender Firewall may block connections:

1. Open Windows Security → Firewall & network protection
2. Click "Allow an app through firewall"
3. Ensure "Docker Desktop" is allowed on both Private and Public networks

### Performance Considerations

1. **File System**: Store data in the WSL2 filesystem (`/home/<user>/`) for better performance than Windows mounts
2. **Memory**: Docker Desktop defaults to 2GB RAM. Increase in Settings → Resources:
   - Recommended: 8GB minimum, 16GB+ for full nodes
3. **Disk**: Use SSD. The node requires significant I/O

### Antivirus Exclusions

Add these exclusions to Windows Defender (or your antivirus):
- `C:\Users\<YourUsername>\AppData\Local\Docker`
- `\\wsl$\Ubuntu\home\<username>\xdcchain`

## Troubleshooting

### Docker Desktop Won't Start

1. Ensure virtualization is enabled in BIOS
2. Check Windows Features:
   - Hyper-V (if using Hyper-V backend)
   - Virtual Machine Platform
   - Windows Subsystem for Linux

### High CPU Usage

1. Create/edit `.wslconfig` in your Windows home directory (`C:\Users\<username>\`):
```ini
[wsl2]
processors=4
memory=8GB
swap=2GB
```

2. Restart WSL2:
```powershell
wsl --shutdown
```

### Out of Disk Space

1. Check WSL2 disk usage:
```powershell
wsl --list --verbose
```

2. Clean up Docker:
```powershell
wsl -e docker system prune -a
```

3. Compact WSL2 VHDX (advanced):
   - See [Microsoft WSL docs](https://docs.microsoft.com/en-us/windows/wsl/disk-space)

### Connection Refused Errors

1. Verify Docker Desktop is running
2. Check WSL2 integration is enabled
3. Restart Docker Desktop
4. Verify ports are not in use:
```powershell
netstat -ano | findstr :8545
```

## Known Limitations

1. **Host networking**: Not available on Docker Desktop
2. **Systemd services**: WSL2 doesn't use systemd by default (may need manual setup)
3. **Firewall UFW**: Linux firewall not applicable; use Windows Firewall
4. **Security hardening**: Some Linux-specific hardening steps don't apply

## Next Steps

- [Security Best Practices](../SECURITY.md)
- [Monitoring Guide](../MONITORING.md)
- [Backup and Recovery](../BACKUP.md)

## Support

For help, visit:
- [XDC Documentation](https://docs.xdc.community/)
- [GitHub Issues](https://github.com/AnilChinchawale/xdc-node-setup/issues)
