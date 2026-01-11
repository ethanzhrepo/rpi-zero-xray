# Raspberry Pi Zero 2 W - Xray VLESS Exit Node (Based on Cloudflare Tunnel)

Production-grade Xray VLESS exit node deployment script for Raspberry Pi Zero 2 W, utilizing Cloudflare Tunnel for reverse penetration, eliminating the need for a public IP.

## Architecture Description

```
Relay Xray Server
   ↓  VLESS (TCP + TLS)
Cloudflare Edge Node
   ↓  Cloudflare Tunnel (mTLS Encryption)
Raspberry Pi Zero 2 W (Exit Node)
   ├─ cloudflared (systemd daemon)
   └─ xray (systemd daemon, VLESS → freedom direct)
```

**How it Works:**
1. The relay server connects to the Cloudflare Tunnel domain via VLESS + TLS.
2. Cloudflare Tunnel establishes an encrypted tunnel between the local Raspberry Pi and Cloudflare Edge.
3. Xray on the Raspberry Pi receives traffic and accesses the target website directly.

## Important Security Notice

**⚠️ This script does NOT configure VLESS + REALITY**

- This deployment script configures **STANDARD VLESS protocol**, without REALITY masking.
- Communication between the exit node and the relay server relies on **Cloudflare Tunnel's TLS/mTLS encryption**.
- **Please ensure the connection from the relay server to Cloudflare uses TLS encryption** (Port 443).
- If you need REALITY on the frontend of the relay server (Client to Relay), please configure the relay server's inbound yourself.
- **DO NOT** expose this exit node directly to the public internet; it must be accessed via Cloudflare Tunnel.

**Encryption Link Explanation:**
```
Client → Relay Server: User-configured encryption needed (e.g., VLESS+REALITY, VMess+TLS, etc.)
Relay Server → Cloudflare: TLS Encryption (Port 443, configured by this script)
Cloudflare → Exit Node: Cloudflare Tunnel mTLS Encryption (Automatic)
Exit Node → Target Website: Plaintext or HTTPS encryption by the target website
```

## Use Cases

- **Scenario**: External Relay → Exit Node
- **Purpose**: Provide reverse penetration access for exit nodes without public IP.
- **Target User**: Single-user self-hosted, 24/7 operation.
- **Design Focus**: Stability, Low Power Consumption, Low Maintenance.

## Features

- **Idempotent Scripts**: All scripts can be safely re-executed.
- **Production Ready**: Complete systemd integration, log rotation, security hardening.
- **Auto-Start**: Services start automatically after system reboot, no manual intervention needed.
- **Low Power Optimization**: Optimized for Raspberry Pi Zero 2 W.
- **Auto-Recovery**: Automatic restart on service failure.
- **Monitoring & Diagnostics**: Complete status check and diagnostic scripts.

## Prerequisites

### Hardware Requirements
- Raspberry Pi Zero 2 W (ARM64 Architecture)
- MicroSD Card (Recommended 8GB+)
- Stable Power Supply (Recommended 5V 2.5A)
- Network Connection (Ethernet Adapter or WiFi)

### Software Requirements
- Raspberry Pi OS Lite (Debian-based 64-bit system)
- Clean installation recommended
- Internet connection
- Root or sudo privileges

### Cloudflare Account Requirements
- Cloudflare Account (Free plan suffices, **Domain NOT required**)
- API Token (Specific permissions needed, see details below)

## Cloudflare Token Configuration (Important)

### Step 1: Create API Token

1. Visit Cloudflare Dashboard: https://dash.cloudflare.com/profile/api-tokens
2. Click "Create Token"
3. Select "Create Custom Token"

### Step 2: Configure Token Permissions

**Required Permissions:**

| Permission Type | Permission Scope | Permission Level | Description |
|----------------|------------------|------------------|-------------|
| **Account** | Cloudflare Tunnel | **Read + Edit** | Required, for creating and managing Tunnels |
| **Zone** | DNS | **Read + Edit** | Optional, only needed when using custom domains |

**Configuration Example:**

```
Account Permissions:
  ┣━ Cloudflare Tunnel: Edit ✓

Zone Permissions (Optional):
  ┗━ DNS: Edit ✓
```

### Step 3: Save Token

1. Click "Continue to Summary"
2. Click "Create Token"
3. **Copy and Save the Token immediately** (Token is shown only once)

### Step 4: Use Token

```bash
# Set environment variable before deployment
export CF_API_TOKEN="your-cloudflare-api-token"

# Then run the deployment script
sudo bash scripts/deploy-all.sh
```

**Notes:**
- Token is displayed only once after creation, please save it to a safe location immediately.
- No need to own a Cloudflare domain; the system automatically assigns a `*.cfargotunnel.com` domain.
- Token permissions follow the principle of least privilege; grant only necessary permissions.
- Recommended to rotate the Token periodically.

## Quick Start

### One-Click Deployment

```bash
# 1. Copy this directory to Raspberry Pi
cd rpi-zero-xray

# 2. Set Cloudflare API Token
export CF_API_TOKEN="your-cloudflare-api-token"

# 3. Run full deployment script
sudo bash scripts/deploy-all.sh
```

The deployment script will automatically:
1. Update system and optimize network settings (Enable BBR, TCP Fast Open).
2. Install Go compiler and build dependencies.
3. Compile Xray v25.12.8 from GitHub source.
4. Generate UUID and create Xray configuration.
5. Install cloudflared client.
6. Create and configure Cloudflare Tunnel.
7. Install and start systemd services.
8. **Configure services allowed to auto-start** (Runs automatically after reboot).

**Estimated Time**: About 20-30 minutes on RPi Zero 2 W.

## Step-by-Step Deployment

If you need to execute step-by-step:

```bash
cd rpi-zero-xray/scripts

# Step 1: System Preparation
sudo bash 00-system-prepare.sh

# Step 2: Install Build Dependencies
sudo bash 01-install-deps.sh

# Step 3: Compile Xray
sudo bash 02-build-xray.sh

# Step 4: Configure Xray (Auto-generates UUID)
sudo bash 03-config-xray.sh

# Step 5: Install cloudflared
sudo bash 04-install-cloudflared.sh

# Step 6: Configure Cloudflare Tunnel (Requires CF_API_TOKEN)
export CF_API_TOKEN="your-token"
sudo bash 05-config-tunnel.sh

# Step 7: Enable and Start Services
sudo bash 06-systemd-enable.sh
```

## Environment Variable Configuration

| Variable Name | Default Value | Description |
|---------------|---------------|-------------|
| `XRAY_VERSION` | v25.12.8 | Xray version to compile |
| `XRAY_PORT` | 10808 | Xray listening port |
| `TIMEZONE` | UTC | System Timezone |
| `CF_API_TOKEN` | - | Cloudflare API Token (Required) |

Example:
```bash
export XRAY_VERSION="v25.12.8"
export XRAY_PORT="10808"
export TIMEZONE="Asia/Shanghai"
export CF_API_TOKEN="your-token"
sudo bash scripts/deploy-all.sh
```

## File Path Description

| Path | Description |
|------|-------------|
| `/opt/xray-exit/bin/xray` | Xray Executable |
| `/etc/xray-exit/xray.json` | Xray Configuration File |
| `/var/log/xray-exit/` | Xray Log Directory |
| `/etc/cloudflared/config.yml` | Cloudflared Configuration File |
| `/etc/cloudflared/*.json` | Tunnel Credential Files |
| `/etc/systemd/system/xray.service` | Xray systemd Service |
| `/etc/systemd/system/cloudflared.service` | Cloudflared systemd Service |

## Post-Deployment Configuration

### Get Connection Info

After successful deployment, check node information:

```bash
# Method 1: View from deployment directory
cat export/exit_node_info.json

# Method 2: View from system config
sudo cat /etc/xray-exit/node_info.json
```

Output Example:
```json
{
  "uuid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "tunnel_hostname": "a1b2c3d4-e5f6-7890-abcd-ef1234567890.cfargotunnel.com",
  "listen_port": 10808,
  "xray_version": "v25.12.8"
}
```

**Important Info Explanation:**
- **UUID**: Authentication credential for the relay server.
- **tunnel_hostname**: Tunnel domain assigned by Cloudflare.
- **listen_port**: Xray local listening port (usually no need to check).

### Authentication Method Explanation

**Authentication Mechanism: Based on UUID**

- This system uses **UUID (Universally Unique Identifier)** as the sole authentication credential.
- UUID is auto-generated during deployment, following RFC 4122 standard.
- Only relay servers holding the correct UUID can pass authentication.
- UUID is saved in `/etc/xray-exit/xray.json` and the export configuration file.

**Security:**
- UUID is a 128-bit random number, brute-force cracking is almost impossible.
- Traffic is encrypted via Cloudflare Tunnel; UUID is not transmitted in plaintext.
- Recommended to rotate UUID periodically (requires updating relay server config synchronously).

### Configure Relay Server

Use the UUID and tunnel_hostname obtained above to configure the relay server's outbound:

```json
{
  "outbounds": [
    {
      "tag": "to-exit-rpi",
      "protocol": "vless",
      "settings": {
        "vnext": [{
          "address": "a1b2c3d4-e5f6-7890-abcd-ef1234567890.cfargotunnel.com",
          "port": 443,
          "users": [{
            "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            "encryption": "none",
            "email": "rpi-exit-node"
          }]
        }]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "a1b2c3d4-e5f6-7890-abcd-ef1234567890.cfargotunnel.com",
          "allowInsecure": false
        }
      }
    }
  ]
}
```

**Configuration Points:**
1. **address**: Use the domain assigned by Cloudflare Tunnel.
2. **port**: Must be 443 (Cloudflare Tunnel standard port).
3. **id**: Use the UUID generated during deployment.
4. **encryption**: Set to "none" (Encryption is handled by Cloudflare Tunnel).
5. **network**: Must be "tcp".
6. **security**: Must be "tls" (Connecting to Cloudflare requires TLS).
7. **serverName**: Same as address.

### Test Connection

Test connection on the relay server:

```bash
# Use curl to access external network via relay server
curl -x socks5h://127.0.0.1:1080 https://www.google.com

# Or check Xray logs to confirm connection
# On the Exit Node (Raspberry Pi):
sudo journalctl -u xray -f
```

## Daily Management

### Check Status

```bash
# Comprehensive status check (Recommended)
sudo bash scripts/check-status.sh

# Quick check service status
sudo systemctl status xray cloudflared

# Check if service is running
systemctl is-active xray cloudflared

# Verify if service is enabled for auto-start
systemctl is-enabled xray cloudflared
# Should all display "enabled"
```

### View Logs

```bash
# Real-time tracking of Xray logs
sudo journalctl -u xray -f

# Real-time tracking of Cloudflared logs
sudo journalctl -u cloudflared -f

# View last 50 lines of logs
sudo journalctl -u xray -n 50
sudo journalctl -u cloudflared -n 50

# View logs from the last 1 hour
sudo journalctl -u xray --since "1 hour ago"
```

### Service Control

```bash
# Restart Services
sudo systemctl restart xray
sudo systemctl restart cloudflared

# Stop Services
sudo systemctl stop xray cloudflared

# Start Services
sudo systemctl start xray cloudflared

# Reload after configuration modification
sudo systemctl daemon-reload
sudo systemctl restart xray cloudflared
```

### Modify Configuration

#### Modify Xray Configuration

```bash
# Edit configuration file
sudo nano /etc/xray-exit/xray.json

# Test if configuration is correct
sudo /opt/xray-exit/bin/xray test -config /etc/xray-exit/xray.json

# Restart service to apply configuration
sudo systemctl restart xray
```

#### Modify Cloudflared Configuration

```bash
# Edit configuration file
sudo nano /etc/cloudflared/config.yml

# Restart service to apply configuration
sudo systemctl restart cloudflared
```

## Maintenance Operations

### Log Rotation

Logs are automatically rotated daily, keeping 7 days of history. Configuration file located at `/etc/logrotate.d/xray-exit`.

### System Update

```bash
# Update Raspberry Pi OS
sudo apt update && sudo apt upgrade -y

# Reboot if kernel is updated
sudo reboot
```

### Upgrade Xray

```bash
# Set new version number
export XRAY_VERSION="v25.13.0"

# Stop service
sudo systemctl stop xray

# Recompile and install
cd rpi-zero-xray/scripts
sudo bash 02-build-xray.sh

# Start service
sudo systemctl start xray

# Verify version
/opt/xray-exit/bin/xray version
```

### Upgrade Cloudflared

```bash
# Stop service
sudo systemctl stop cloudflared

# Reinstall (Will download the latest version)
cd rpi-zero-xray/scripts
sudo bash 04-install-cloudflared.sh

# Start service
sudo systemctl start cloudflared

# Verify version
cloudflared --version
```

## Troubleshooting

### Service Fails to Start

```bash
# View service status
sudo systemctl status xray cloudflared

# View detailed logs
sudo journalctl -u xray -n 100 --no-pager
sudo journalctl -u cloudflared -n 100 --no-pager

# Test Xray Configuration
sudo /opt/xray-exit/bin/xray test -config /etc/xray-exit/xray.json

# Check if port is occupied
sudo ss -tlnp | grep 10808
```

### Xray Not Listening on Port

```bash
# Check if process is running
pgrep -a xray

# Check port binding
sudo ss -tlnp | grep xray

# Restart Service
sudo systemctl restart xray

# View Error Logs
sudo journalctl -u xray -n 50
```

### Cloudflared Connection Issues

```bash
# View Tunnel Status
cloudflared tunnel list

# View Tunnel Details
cloudflared tunnel info rpi-exit-$(hostname)

# View Logs
sudo journalctl -u cloudflared -n 50

# Verify CF_API_TOKEN Permissions
# Token must have: Cloudflare Tunnel (Read, Edit) permissions
```

### CPU Temperature Too High

```bash
# View Temperature (Unit: millidegree Celsius, divide by 1000)
cat /sys/class/thermal/thermal_zone0/temp

# If seemingly higher than 80°C:
# - Improve cooling and ventilation
# - Lower CPU frequency (configure in config.sh)
# - Check if any process is stuck
```

### Insufficient Memory

```bash
# View Memory Usage
free -h

# View Process Memory Usage
ps aux --sort=-%mem | head

# If memory is tight:
# - Lower log level (xray.json loglevel: "warning" → "error")
# - Disable access logs
# - Increase swap (not recommended for long term)
```

### Insufficient Disk Space

```bash
# View Disk Usage
df -h

# Clean old logs
sudo journalctl --vacuum-time=3d

# Clean package cache
sudo apt clean

# Find large files
sudo du -h /opt /etc /var/log | sort -rh | head -20
```

## Uninstall

Completely remove the exit node:

```bash
cd rpi-zero-xray/scripts

# If you want to remove Tunnel from Cloudflare, Token is required
export CF_API_TOKEN="your-token"

# Run uninstall script
sudo bash 99-uninstall.sh
```

Uninstall operations include:
- Stop and disable services
- Delete systemd unit files
- Delete all files and directories
- Delete user accounts
- Delete Cloudflare Tunnel (if CF_API_TOKEN is set)
- Clean system configuration

## Performance Expectations

### Raspberry Pi Zero 2 W Specs

- **CPU**: Quad-core ARM Cortex-A53 @ 1GHz
- **RAM**: 512MB
- **Expected Throughput**: 10-30 Mbps (Limited by CPU and network)
- **CPU Usage**: Idle 5-15%, Load 30-60%
- **Memory Usage**: Total 100-200MB
- **Temperature**: Idle 40-60°C, Load 60-80°C

### Compilation and Deployment Time

- **Xray Compilation**: 5-10 minutes
- **Full Deployment**: 20-30 minutes
- **First Startup**: Extra 2-3 minutes

## Security Notes

### Applied Security Hardening

- Services run as non-privileged users (`xray`, `cloudflared`)
- Enable systemd security limits
- Xray only listens on localhost (127.0.0.1)
- All traffic encrypted via Cloudflare Tunnel
- Log rotation prevents disk filling
- Minimal attack surface (No public ports)
- Auto-start and auto-recovery (Ensure service availability)

### Additional Security Recommendations

1. **SSH Security**: Change default password, use SSH key authentication
2. **Firewall**: Consider enabling UFW (Not necessary since no public ports)
3. **Auto Updates**: Enable unattended-upgrades for auto-installing security patches
4. **Monitoring**: Set up external monitoring to check node online status
5. **Backup**: Periodically backup `/etc/xray-exit/` and `/etc/cloudflared/`

## Tech Specs

### Xray Configuration Specs

- **Protocol**: VLESS (**Without REALITY masking**)
- **Transport**: TCP (No WebSocket, gRPC)
- **Security**: None (Encryption handled by Cloudflare Tunnel)
- **Encryption**: No encryption at Xray level (Relies on outer TLS and Cloudflare Tunnel encryption)
- **Disabled Features**: sniffing, mux, fallback
- **Log Level**: warning (Production Environment)
- **Outbound**: freedom (Direct Internet Access)
- **⚠️ Note**: Relay server must connect to Cloudflare via TLS (Port 443) to ensure encrypted transmission link

### Cloudflare Tunnel Specs

- **Type**: TCP Tunnel
- **Encryption**: mTLS (Cloudflare Tunnel Protocol)
- **Target**: `tcp://127.0.0.1:10808`
- **Hostname**: `<tunnel-id>.cfargotunnel.com`
- **Non-HTTP/HTTPS**: Pure TCP passthrough

## FAQ

**Q: Will the service start automatically after system reboot?**
A: Yes! The deployment script already configured systemd auto-start. Xray and cloudflared will run automatically after reboot without manual operation. Verify with `systemctl is-enabled xray cloudflared`.

**Q: Can I run multiple exit nodes?**
A: Yes, run this script on multiple Raspberry Pis, then configure multiple outbounds on the relay server.

**Q: What if I don't have a Cloudflare domain?**
A: Not needed! Cloudflare will automatically assign a free `*.cfargotunnel.com` domain.

**Q: Can I change ports?**
A: Yes, set `XRAY_PORT` environment variable before deployment.

**Q: Can I run this on Raspberry Pi 3/4?**
A: Yes! Performance will be better due to stronger CPU and more RAM.

**Q: Is IPv6 supported?**
A: Cloudflare Tunnel supports IPv6; just ensure the Raspberry Pi has IPv6 connection.

**Q: How to migrate to a new Raspberry Pi?**
A: Backup config files, run deployment on new device, then update relay server's UUID and domain.

**Q: Why compile Xray from source?**
A: To ensure binary integrity and security, while optimizing performance for ARM64 architecture.

**Q: Does Cloudflare limit speed?**
A: Free version Cloudflare Tunnel has no explicit speed limit, but is limited by Raspberry Pi hardware performance (approx. 10-30 Mbps).

## Technical Support

When encountering issues:
1. Check logs: `sudo journalctl -u xray -u cloudflared -n 100`
2. Run diagnostics: `sudo bash scripts/check-status.sh`
3. Read this README carefully
4. Refer to Xray Documentation: https://xtls.github.io/
5. Refer to Cloudflare Tunnel Documentation: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps

## License

This deployment package is provided as-is for personal use. Xray and Cloudflared follow their respective open-source licenses.

## Acknowledgments

- **Xray-core**: https://github.com/XTLS/Xray-core
- **Cloudflare Tunnel**: https://developers.cloudflare.com/cloudflare-one/
- **Raspberry Pi**: https://www.raspberrypi.org/
