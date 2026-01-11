#!/usr/bin/env bash
#
# 03-config-xray.sh - Generate Xray configuration
# Creates xray.json with auto-generated UUID
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

log_section "Configuring Xray VLESS Exit Node"

check_root

# Verify Xray is installed
if [ ! -x "$INSTALL_DIR/bin/xray" ]; then
    log_error "Xray binary not found. Please run 02-build-xray.sh first"
    exit 1
fi

# Generate UUID for VLESS
log_info "Generating UUID for VLESS authentication..."
UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
log_success "UUID generated: $UUID"

# Create Xray configuration
log_info "Creating Xray configuration file..."

cat > "$CONFIG_DIR/xray.json" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "$LOG_DIR/access.log",
    "error": "$LOG_DIR/error.log"
  },
  "inbounds": [
    {
      "tag": "vless-in",
      "listen": "127.0.0.1",
      "port": $XRAY_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "email": "transit-server"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "none"
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

log_success "Xray configuration created: $CONFIG_DIR/xray.json"

# Set ownership and permissions
chown "$XRAY_USER:$XRAY_GROUP" "$CONFIG_DIR/xray.json"
chmod 640 "$CONFIG_DIR/xray.json"
log_success "Configuration file permissions set"

# Validate configuration
log_info "Validating Xray configuration..."
if "$INSTALL_DIR/bin/xray" test -config "$CONFIG_DIR/xray.json" &>/dev/null; then
    log_success "Configuration validation passed"
else
    log_error "Configuration validation failed"
    log_error "Please check the configuration file: $CONFIG_DIR/xray.json"
    exit 1
fi

# Create export file with node information
log_info "Creating export file with node information..."

mkdir -p "$EXPORT_DIR"

CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "$EXPORT_DIR/exit_node_info.json" <<EOF
{
  "node_type": "xray-vless-exit",
  "uuid": "$UUID",
  "listen_address": "127.0.0.1",
  "listen_port": $XRAY_PORT,
  "tunnel_hostname": "PENDING",
  "created_at": "$CREATED_AT",
  "xray_version": "$XRAY_VERSION",
  "protocol": "vless",
  "transport": "tcp",
  "security": "none"
}
EOF

log_success "Export file created: $EXPORT_DIR/exit_node_info.json"

# Display important information
log_section "Xray Configuration Complete"

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW} IMPORTANT: Save this UUID${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  UUID: ${GREEN}$UUID${NC}"
echo ""
echo "  This UUID is required for your transit server configuration."
echo "  Add this UUID to your transit server's allowed clients."
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log_success "Configuration summary:"
echo "  - Listen: 127.0.0.1:$XRAY_PORT"
echo "  - Protocol: VLESS over TCP"
echo "  - Security: None (handled by Cloudflare Tunnel)"
echo "  - Outbound: Direct (freedom)"
echo "  - Log level: warning"
echo ""

log_info "Configuration file: $CONFIG_DIR/xray.json"
log_info "Export file: $EXPORT_DIR/exit_node_info.json"

echo -e "\n${GREEN}▶${NC} Next step: Run ${BLUE}04-install-cloudflared.sh${NC}"
