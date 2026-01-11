#!/usr/bin/env bash
#
# deploy-all.sh - Master deployment script
# Runs all deployment scripts in sequence
#

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# ============================================================================
# Configuration
# ============================================================================

# Log file for deployment
DEPLOY_LOG="/tmp/xray-exit-deploy-$(date +%Y%m%d-%H%M%S).log"

# Deployment scripts in order
DEPLOY_SCRIPTS=(
    "00-system-prepare.sh"
    "01-install-deps.sh"
    "02-build-xray.sh"
    "03-config-xray.sh"
    "04-install-cloudflared.sh"
    "05-config-tunnel.sh"
    "06-systemd-enable.sh"
)

# ============================================================================
# Helper Functions
# ============================================================================

log_to_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$DEPLOY_LOG"
}

run_script() {
    local script="$1"
    local script_path="$SCRIPT_DIR/$script"

    log_section "Running: $script"
    log_to_file "Starting: $script"

    if [ ! -f "$script_path" ]; then
        log_error "Script not found: $script_path"
        exit 1
    fi

    if [ ! -x "$script_path" ]; then
        log_info "Making script executable: $script"
        chmod +x "$script_path"
    fi

    # Run script and capture output
    if bash "$script_path" 2>&1 | tee -a "$DEPLOY_LOG"; then
        log_success "Completed: $script"
        log_to_file "Completed: $script"
        return 0
    else
        log_error "Failed: $script"
        log_to_file "Failed: $script"
        return 1
    fi
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

log_section "Xray Exit Node - Full Deployment"

echo "This script will deploy a complete Xray VLESS exit node with Cloudflare Tunnel"
echo "on Raspberry Pi Zero 2 W."
echo ""
echo "Deployment log: $DEPLOY_LOG"
echo ""

# Pre-flight checks
log_section "Pre-flight Checks"

check_root
check_architecture
check_internet

# Check for CF_API_TOKEN
if [ -z "${CF_API_TOKEN:-}" ]; then
    log_warning "CF_API_TOKEN not set"
    echo ""
    echo "The Cloudflare Tunnel setup requires CF_API_TOKEN."
    echo "You can either:"
    echo "  1. Set it now and continue"
    echo "  2. Run scripts individually and set it before 05-config-tunnel.sh"
    echo ""
    read -p "Do you have CF_API_TOKEN ready? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Enter CF_API_TOKEN: " -r
        export CF_API_TOKEN="$REPLY"
        log_success "CF_API_TOKEN set"
    else
        log_warning "Deployment will pause at tunnel configuration"
    fi
fi

# Disk space check
log_info "Checking available disk space..."
AVAILABLE_MB=$(df /opt | tail -1 | awk '{print $4}')
AVAILABLE_MB=$((AVAILABLE_MB / 1024))

if [ "$AVAILABLE_MB" -lt 500 ]; then
    log_warning "Low disk space: ${AVAILABLE_MB}MB available"
    log_warning "Recommended: at least 500MB free"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi
else
    log_success "Disk space: ${AVAILABLE_MB}MB available"
fi

# Confirm deployment
echo ""
log_info "Deployment will:"
echo "  - Update system packages"
echo "  - Install Go, Git, jq, and build tools"
echo "  - Build Xray $XRAY_VERSION from source"
echo "  - Configure Xray VLESS TCP exit node"
echo "  - Install and configure Cloudflare Tunnel"
echo "  - Set up systemd services"
echo ""
read -p "Proceed with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Deployment cancelled by user"
    exit 0
fi

# ============================================================================
# Main Deployment
# ============================================================================

log_section "Starting Deployment"

DEPLOY_START=$(date +%s)
FAILED=false

for script in "${DEPLOY_SCRIPTS[@]}"; do
    if ! run_script "$script"; then
        log_error "Deployment failed at: $script"
        FAILED=true
        break
    fi

    # Add separator between scripts
    echo ""
    sleep 1
done

DEPLOY_END=$(date +%s)
DEPLOY_DURATION=$((DEPLOY_END - DEPLOY_START))
DEPLOY_MINUTES=$((DEPLOY_DURATION / 60))
DEPLOY_SECONDS=$((DEPLOY_DURATION % 60))

# ============================================================================
# Deployment Summary
# ============================================================================

log_section "Deployment Summary"

if [[ "$FAILED" == "true" ]]; then
    log_error "Deployment failed"
    echo ""
    echo "Check the log file for details: $DEPLOY_LOG"
    echo ""
    log_info "You can continue deployment by running individual scripts"
    exit 1
fi

log_success "Deployment completed successfully!"
echo ""
echo "Duration: ${DEPLOY_MINUTES}m ${DEPLOY_SECONDS}s"
echo "Log file: $DEPLOY_LOG"
echo ""

# Display final configuration
if [ -f "$EXPORT_DIR/exit_node_info.json" ]; then
    log_section "Exit Node Configuration"

    TUNNEL_HOSTNAME=$(jq -r '.tunnel_hostname' "$EXPORT_DIR/exit_node_info.json")
    UUID=$(jq -r '.uuid' "$EXPORT_DIR/exit_node_info.json")
    XRAY_VERSION_DEPLOYED=$(jq -r '.xray_version' "$EXPORT_DIR/exit_node_info.json")

    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW} Save This Information${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${GREEN}UUID:${NC}              $UUID"
    echo -e "  ${GREEN}Tunnel Hostname:${NC}   $TUNNEL_HOSTNAME"
    echo -e "  ${GREEN}Xray Version:${NC}      $XRAY_VERSION_DEPLOYED"
    echo ""
    echo "  Transit Server Configuration:"
    echo "    - Address: $TUNNEL_HOSTNAME"
    echo "    - Port: 443"
    echo "    - UUID: $UUID"
    echo "    - Protocol: VLESS"
    echo "    - Transport: TCP"
    echo "    - Security: TLS"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Save to permanent location
    cp "$EXPORT_DIR/exit_node_info.json" "$CONFIG_DIR/node_info.json"
    log_success "Configuration saved to: $CONFIG_DIR/node_info.json"
fi

# Next steps
log_section "Next Steps"
echo ""
echo "1. Verify services are running:"
echo "   sudo systemctl status xray cloudflared"
echo ""
echo "2. Check status and diagnostics:"
echo "   sudo bash $SCRIPT_DIR/check-status.sh"
echo ""
echo "3. View logs:"
echo "   sudo journalctl -u xray -f"
echo "   sudo journalctl -u cloudflared -f"
echo ""
echo "4. Configure your transit server with the UUID and tunnel hostname above"
echo ""
echo "5. Test connectivity through the tunnel"
echo ""

log_success "Exit node is now running and ready for use!"

# Cleanup
log_to_file "Deployment completed successfully"
