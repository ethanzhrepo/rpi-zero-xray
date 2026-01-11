#!/usr/bin/env bash
#
# 00-system-prepare.sh - System preparation and optimization
# Prepares Raspberry Pi Zero 2 W for Xray exit node deployment
#

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Error handler
cleanup_on_error() {
    log_error "Script failed at line $1"
}
trap 'cleanup_on_error $LINENO' ERR

# ============================================================================
# Main Execution
# ============================================================================

log_section "System Preparation for Xray Exit Node"

check_root
check_architecture
check_internet

# Update system packages
log_info "Updating system packages..."
if apt-get update -qq && apt-get upgrade -y -qq; then
    log_success "System packages updated"
else
    log_error "Failed to update system packages"
    exit 1
fi

# Install essential utilities
log_info "Installing essential utilities..."
apt-get install -y -qq \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    uuidgen \
    gettext-base \
    sudo \
    || { log_error "Failed to install essential utilities"; exit 1; }
log_success "Essential utilities installed"

# Set timezone
log_info "Setting timezone to $TIMEZONE..."
if timedatectl set-timezone "$TIMEZONE" 2>/dev/null || ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime; then
    log_success "Timezone set to $TIMEZONE"
else
    log_warning "Failed to set timezone, continuing..."
fi

# Disable unnecessary services for low power consumption
log_info "Disabling unnecessary services..."

# Disable Bluetooth if not needed
if systemctl is-enabled bluetooth.service &>/dev/null; then
    systemctl disable bluetooth.service 2>/dev/null || true
    systemctl stop bluetooth.service 2>/dev/null || true
    log_success "Bluetooth service disabled"
fi

# Disable WiFi power management for stability (if using WiFi)
if command -v iwconfig &>/dev/null; then
    log_info "Disabling WiFi power management..."
    cat > /etc/network/if-up.d/disable-wifi-powersave <<'EOF'
#!/bin/sh
/sbin/iwconfig wlan0 power off 2>/dev/null || true
EOF
    chmod +x /etc/network/if-up.d/disable-wifi-powersave
    /sbin/iwconfig wlan0 power off 2>/dev/null || true
    log_success "WiFi power management disabled"
fi

# Configure sysctl for network performance
log_info "Configuring sysctl for network performance..."

cat > /etc/sysctl.d/99-xray-exit.conf <<EOF
# TCP Fast Open
net.ipv4.tcp_fastopen = 3

# BBR Congestion Control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Network performance tuning
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Connection tracking
net.netfilter.nf_conntrack_max = 65536
net.netfilter.nf_conntrack_tcp_timeout_established = 7200

# File descriptor limits
fs.file-max = 65536
EOF

# Apply sysctl settings
if sysctl -p /etc/sysctl.d/99-xray-exit.conf >/dev/null 2>&1; then
    log_success "Sysctl settings applied"
else
    log_warning "Some sysctl settings may not be applied (kernel module may need loading)"
fi

# Create required directories
log_info "Creating installation directories..."

mkdir -p "$INSTALL_DIR"/{bin,var}
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$CLOUDFLARED_CONFIG_DIR"
mkdir -p "$EXPORT_DIR"

log_success "Directories created: $INSTALL_DIR, $CONFIG_DIR, $LOG_DIR"

# Configure log rotation
log_info "Configuring log rotation..."

cat > /etc/logrotate.d/xray-exit <<EOF
$LOG_DIR/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 $XRAY_USER $XRAY_GROUP
    sharedscripts
    postrotate
        systemctl reload xray.service > /dev/null 2>&1 || true
    endscript
}
EOF

log_success "Log rotation configured"

# Set CPU governor to powersave for low power consumption
log_info "Configuring CPU governor for low power..."
if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "ondemand" > "$cpu" 2>/dev/null || echo "conservative" > "$cpu" 2>/dev/null || true
    done
    log_success "CPU governor configured"
else
    log_warning "CPU frequency scaling not available"
fi

# Summary
log_section "System Preparation Complete"
log_success "System packages updated"
log_success "Network performance optimized (BBR, TCP Fast Open)"
log_success "Unnecessary services disabled"
log_success "Directories created and log rotation configured"
log_success "System is ready for Xray and Cloudflared installation"

echo -e "\n${GREEN}▶${NC} Next step: Run ${BLUE}01-install-deps.sh${NC}"
