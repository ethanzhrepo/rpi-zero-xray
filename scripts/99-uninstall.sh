#!/usr/bin/env bash
#
# 99-uninstall.sh - Complete uninstallation script
# Removes all Xray and Cloudflare Tunnel components
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

log_section "Xray Exit Node - Complete Uninstallation"

check_root

# Warning
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED} WARNING: This will completely remove:${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  - Xray binary and configuration"
echo "  - Cloudflared binary and configuration"
echo "  - All systemd services"
echo "  - All log files"
echo "  - User accounts (xray, cloudflared)"
echo "  - Cloudflare Tunnel (from your account)"
echo ""
echo -e "${RED}This action cannot be undone!${NC}"
echo ""

read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
echo
if [[ "$REPLY" != "yes" ]]; then
    log_info "Uninstallation cancelled"
    exit 0
fi

# ============================================================================
# Stop and Disable Services
# ============================================================================

log_section "Stopping Services"

if systemctl is-active cloudflared.service &>/dev/null; then
    log_info "Stopping cloudflared service..."
    systemctl stop cloudflared.service || true
    log_success "Cloudflared service stopped"
fi

if systemctl is-active xray.service &>/dev/null; then
    log_info "Stopping xray service..."
    systemctl stop xray.service || true
    log_success "Xray service stopped"
fi

log_info "Disabling services..."
systemctl disable cloudflared.service 2>/dev/null || true
systemctl disable xray.service 2>/dev/null || true
log_success "Services disabled"

# ============================================================================
# Remove Systemd Units
# ============================================================================

log_section "Removing Systemd Units"

if [ -f /etc/systemd/system/xray.service ]; then
    log_info "Removing xray.service..."
    rm -f /etc/systemd/system/xray.service
    log_success "xray.service removed"
fi

if [ -f /etc/systemd/system/cloudflared.service ]; then
    log_info "Removing cloudflared.service..."
    rm -f /etc/systemd/system/cloudflared.service
    log_success "cloudflared.service removed"
fi

log_info "Reloading systemd daemon..."
systemctl daemon-reload
log_success "Systemd daemon reloaded"

# ============================================================================
# Delete Cloudflare Tunnel
# ============================================================================

log_section "Removing Cloudflare Tunnel"

if command -v cloudflared &>/dev/null; then
    # Try to get tunnel name
    TUNNEL_NAME="rpi-exit-$(hostname)"

    if [ -n "${CF_API_TOKEN:-}" ]; then
        log_info "Attempting to delete tunnel: $TUNNEL_NAME"
        if cloudflared tunnel list 2>/dev/null | grep -q "$TUNNEL_NAME"; then
            if cloudflared tunnel delete -f "$TUNNEL_NAME" 2>/dev/null; then
                log_success "Tunnel deleted from Cloudflare"
            else
                log_warning "Failed to delete tunnel (may need manual cleanup)"
            fi
        else
            log_info "Tunnel not found in Cloudflare account"
        fi
    else
        log_warning "CF_API_TOKEN not set, skipping tunnel deletion"
        log_warning "You may need to manually delete the tunnel from Cloudflare dashboard"
    fi
fi

# ============================================================================
# Remove Directories
# ============================================================================

log_section "Removing Directories and Files"

DIRS_TO_REMOVE=(
    "$INSTALL_DIR"
    "$CONFIG_DIR"
    "$LOG_DIR"
    "$CLOUDFLARED_CONFIG_DIR"
    "$BUILD_DIR"
    "/root/.cloudflared"
)

for dir in "${DIRS_TO_REMOVE[@]}"; do
    if [ -d "$dir" ]; then
        log_info "Removing directory: $dir"
        rm -rf "$dir"
        log_success "Removed: $dir"
    fi
done

# Remove logrotate configuration
if [ -f /etc/logrotate.d/xray-exit ]; then
    log_info "Removing logrotate configuration..."
    rm -f /etc/logrotate.d/xray-exit
    log_success "Logrotate configuration removed"
fi

# Remove sysctl configuration
if [ -f /etc/sysctl.d/99-xray-exit.conf ]; then
    log_info "Removing sysctl configuration..."
    rm -f /etc/sysctl.d/99-xray-exit.conf
    log_success "Sysctl configuration removed"
fi

# ============================================================================
# Remove Binaries
# ============================================================================

log_section "Removing Binaries"

if [ -f /usr/local/bin/cloudflared ]; then
    log_info "Removing cloudflared binary..."
    rm -f /usr/local/bin/cloudflared
    log_success "cloudflared binary removed"
fi

# ============================================================================
# Remove Users
# ============================================================================

log_section "Removing User Accounts"

if id "$XRAY_USER" &>/dev/null; then
    log_info "Removing user: $XRAY_USER"
    userdel "$XRAY_USER" 2>/dev/null || true
    log_success "User $XRAY_USER removed"
fi

if id "$CLOUDFLARED_USER" &>/dev/null; then
    log_info "Removing user: $CLOUDFLARED_USER"
    userdel "$CLOUDFLARED_USER" 2>/dev/null || true
    log_success "User $CLOUDFLARED_USER removed"
fi

# ============================================================================
# Optional: Remove Build Dependencies
# ============================================================================

log_section "Optional Cleanup"

echo ""
read -p "Do you want to remove Go and build tools? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Removing Go..."
    rm -rf /usr/local/go
    rm -f /etc/profile.d/go.sh
    log_success "Go removed"

    log_info "Removing build tools..."
    apt-get remove -y build-essential git jq 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
    log_success "Build tools removed"
else
    log_info "Keeping Go and build tools"
fi

# ============================================================================
# Summary
# ============================================================================

log_section "Uninstallation Complete"

echo ""
log_success "All Xray Exit Node components have been removed"
echo ""

log_info "Removed items:"
echo "  ✓ Systemd services (xray, cloudflared)"
echo "  ✓ Installation directory: $INSTALL_DIR"
echo "  ✓ Configuration directory: $CONFIG_DIR"
echo "  ✓ Log directory: $LOG_DIR"
echo "  ✓ Cloudflared configuration: $CLOUDFLARED_CONFIG_DIR"
echo "  ✓ User accounts: $XRAY_USER, $CLOUDFLARED_USER"
echo "  ✓ Binaries: cloudflared"
echo ""

if [ -n "${CF_API_TOKEN:-}" ]; then
    log_info "Cloudflare Tunnel deletion attempted"
else
    log_warning "Manual Cloudflare Tunnel cleanup may be required"
    echo ""
    echo "To manually remove the tunnel:"
    echo "  1. Go to https://dash.cloudflare.com/"
    echo "  2. Navigate to Zero Trust > Networks > Tunnels"
    echo "  3. Delete the tunnel: rpi-exit-$(hostname)"
    echo ""
fi

log_success "System has been cleaned"
