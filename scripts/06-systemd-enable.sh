#!/usr/bin/env bash
#
# 06-systemd-enable.sh - Enable and start systemd services
# Installs systemd units and starts Xray and Cloudflared
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

log_section "Enabling and Starting Services"

check_root

# Verify prerequisites
log_info "Verifying prerequisites..."

PREREQ_OK=true

if [ ! -x "$INSTALL_DIR/bin/xray" ]; then
    log_error "Xray binary not found: $INSTALL_DIR/bin/xray"
    PREREQ_OK=false
fi

if [ ! -f "$CONFIG_DIR/xray.json" ]; then
    log_error "Xray configuration not found: $CONFIG_DIR/xray.json"
    PREREQ_OK=false
fi

if ! command -v cloudflared &>/dev/null; then
    log_error "cloudflared not found"
    PREREQ_OK=false
fi

if [ ! -f "$CLOUDFLARED_CONFIG_DIR/config.yml" ]; then
    log_error "Cloudflared configuration not found: $CLOUDFLARED_CONFIG_DIR/config.yml"
    PREREQ_OK=false
fi

if [ ! -d "$SYSTEMD_DIR" ]; then
    log_error "Systemd service files directory not found: $SYSTEMD_DIR"
    PREREQ_OK=false
fi

if [[ "$PREREQ_OK" == "false" ]]; then
    log_error "Prerequisites not met. Please run previous setup scripts."
    exit 1
fi

log_success "All prerequisites verified"

# Install systemd service files
log_info "Installing systemd service files..."

# Check if service files exist in systemd directory
if [ ! -f "$SYSTEMD_DIR/xray.service" ]; then
    log_error "xray.service not found in $SYSTEMD_DIR"
    exit 1
fi

if [ ! -f "$SYSTEMD_DIR/cloudflared.service" ]; then
    log_error "cloudflared.service not found in $SYSTEMD_DIR"
    exit 1
fi

# Copy service files
cp "$SYSTEMD_DIR/xray.service" /etc/systemd/system/
cp "$SYSTEMD_DIR/cloudflared.service" /etc/systemd/system/

log_success "Service files installed to /etc/systemd/system/"

# Reload systemd
log_info "Reloading systemd daemon..."
systemctl daemon-reload
log_success "Systemd daemon reloaded"

# Stop services if already running
log_info "Stopping services if already running..."
systemctl stop xray.service 2>/dev/null || true
systemctl stop cloudflared.service 2>/dev/null || true

# Enable services
log_info "Enabling services to start on boot..."
systemctl enable xray.service
systemctl enable cloudflared.service
log_success "Services enabled"

# Start Xray service first
log_info "Starting Xray service..."
if systemctl start xray.service; then
    log_success "Xray service started"
else
    log_error "Failed to start Xray service"
    journalctl -u xray.service -n 20 --no-pager
    exit 1
fi

# Wait a moment for Xray to fully start
sleep 2

# Verify Xray is running and listening
log_info "Verifying Xray is listening on port $XRAY_PORT..."
if ss -tlnp | grep -q ":$XRAY_PORT"; then
    log_success "Xray is listening on 127.0.0.1:$XRAY_PORT"
else
    log_error "Xray is not listening on expected port"
    systemctl status xray.service --no-pager
    exit 1
fi

# Start Cloudflared service
log_info "Starting Cloudflared service..."
if systemctl start cloudflared.service; then
    log_success "Cloudflared service started"
else
    log_error "Failed to start Cloudflared service"
    journalctl -u cloudflared.service -n 20 --no-pager
    exit 1
fi

# Wait for services to stabilize
log_info "Waiting for services to stabilize..."
sleep 5

# Check service status
log_info "Checking service status..."

XRAY_STATUS=$(systemctl is-active xray.service || echo "failed")
CLOUDFLARED_STATUS=$(systemctl is-active cloudflared.service || echo "failed")

if [[ "$XRAY_STATUS" == "active" ]]; then
    log_success "Xray service is active"
else
    log_error "Xray service status: $XRAY_STATUS"
fi

if [[ "$CLOUDFLARED_STATUS" == "active" ]]; then
    log_success "Cloudflared service is active"
else
    log_error "Cloudflared service status: $CLOUDFLARED_STATUS"
fi

if [[ "$XRAY_STATUS" != "active" || "$CLOUDFLARED_STATUS" != "active" ]]; then
    log_error "Services are not running properly"
    exit 1
fi

# Display service status
log_section "Service Status"

echo -e "\n${BLUE}Xray Service:${NC}"
systemctl status xray.service --no-pager --lines=5 || true

echo -e "\n${BLUE}Cloudflared Service:${NC}"
systemctl status cloudflared.service --no-pager --lines=5 || true

# Display tunnel info
log_section "Cloudflare Tunnel Information"

if [ -f "$EXPORT_DIR/exit_node_info.json" ]; then
    TUNNEL_HOSTNAME=$(jq -r '.tunnel_hostname' "$EXPORT_DIR/exit_node_info.json")
    UUID=$(jq -r '.uuid' "$EXPORT_DIR/exit_node_info.json")

    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW} Exit Node Ready${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  Tunnel Hostname: ${GREEN}$TUNNEL_HOSTNAME${NC}"
    echo -e "  UUID:            ${GREEN}$UUID${NC}"
    echo ""
    echo "  Configure your transit server:"
    echo "    - Address: $TUNNEL_HOSTNAME"
    echo "    - Port: 443"
    echo "    - UUID: $UUID"
    echo "    - Protocol: VLESS"
    echo "    - Transport: TCP"
    echo "    - Security: TLS (Cloudflare)"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
fi

# Summary
log_section "System Service Setup Complete"
log_success "Xray service: active and enabled"
log_success "Cloudflared service: active and enabled"
log_success "Services will start automatically on boot"

echo ""
log_info "Useful commands:"
echo "  - Check status:  systemctl status xray cloudflared"
echo "  - View logs:     journalctl -u xray -f"
echo "  - View logs:     journalctl -u cloudflared -f"
echo "  - Restart:       systemctl restart xray cloudflared"
echo "  - Stop:          systemctl stop xray cloudflared"
echo ""

log_success "Deployment complete! Your exit node is now running."
