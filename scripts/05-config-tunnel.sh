#!/usr/bin/env bash
#
# 05-config-tunnel.sh - Configure Cloudflare Tunnel
# Creates and configures Cloudflare Tunnel to Xray
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
# Helper Functions
# ============================================================================

show_token_requirements() {
    echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW} Cloudflare API Token Required${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Please create a Cloudflare API token with these minimum permissions:"
    echo ""
    echo -e "${GREEN}Account Level:${NC}"
    echo "  ✓ Cloudflare Tunnel: Read, Edit"
    echo ""
    echo -e "${GREEN}Zone Level (optional, for custom domain routing):${NC}"
    echo "  ✓ DNS: Read, Edit"
    echo ""
    echo "Create token at:"
    echo "  https://dash.cloudflare.com/profile/api-tokens"
    echo ""
    echo "Then export the token as an environment variable:"
    echo -e "  ${BLUE}export CF_API_TOKEN=\"your-token-here\"${NC}"
    echo ""
    echo "And re-run this script."
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# ============================================================================
# Main Execution
# ============================================================================

log_section "Configuring Cloudflare Tunnel"

check_root
check_internet

# Verify cloudflared is installed
if ! command -v cloudflared &>/dev/null; then
    log_error "cloudflared not found. Please run 04-install-cloudflared.sh first"
    exit 1
fi

# Check for CF_API_TOKEN
if [ -z "${CF_API_TOKEN:-}" ]; then
    log_error "CF_API_TOKEN environment variable not set"
    show_token_requirements
    exit 1
fi

log_success "CF_API_TOKEN found"

# Authenticate with Cloudflare
log_info "Authenticating with Cloudflare..."
export TUNNEL_TOKEN="$CF_API_TOKEN"

# Generate tunnel name
TUNNEL_NAME="rpi-exit-$(hostname)"
log_info "Tunnel name: $TUNNEL_NAME"

# Check if tunnel already exists
log_info "Checking for existing tunnels..."
EXISTING_TUNNEL=$(cloudflared tunnel list --output json 2>/dev/null | jq -r ".[] | select(.name==\"$TUNNEL_NAME\") | .id" || echo "")

if [ -n "$EXISTING_TUNNEL" ]; then
    log_warning "Tunnel '$TUNNEL_NAME' already exists (ID: $EXISTING_TUNNEL)"
    read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deleting existing tunnel..."
        cloudflared tunnel delete -f "$TUNNEL_NAME" || true
        sleep 2
        log_success "Existing tunnel deleted"
    else
        log_info "Using existing tunnel"
        TUNNEL_ID="$EXISTING_TUNNEL"
    fi
fi

# Create tunnel if not using existing
if [ -z "${TUNNEL_ID:-}" ]; then
    log_info "Creating new Cloudflare Tunnel..."
    if cloudflared tunnel create "$TUNNEL_NAME"; then
        log_success "Tunnel created: $TUNNEL_NAME"
    else
        log_error "Failed to create tunnel"
        log_error "Please verify your CF_API_TOKEN has correct permissions"
        show_token_requirements
        exit 1
    fi

    # Get tunnel ID
    TUNNEL_ID=$(cloudflared tunnel list --output json | jq -r ".[] | select(.name==\"$TUNNEL_NAME\") | .id")
    if [ -z "$TUNNEL_ID" ]; then
        log_error "Failed to retrieve tunnel ID"
        exit 1
    fi
    log_success "Tunnel ID: $TUNNEL_ID"
fi

# Locate tunnel credentials file
log_info "Locating tunnel credentials..."
CRED_FILE_HOME="$HOME/.cloudflared/${TUNNEL_ID}.json"
CRED_FILE_ROOT="/root/.cloudflared/${TUNNEL_ID}.json"

if [ -f "$CRED_FILE_HOME" ]; then
    CRED_FILE="$CRED_FILE_HOME"
elif [ -f "$CRED_FILE_ROOT" ]; then
    CRED_FILE="$CRED_FILE_ROOT"
else
    log_error "Tunnel credentials file not found"
    log_error "Expected: $CRED_FILE_HOME or $CRED_FILE_ROOT"
    exit 1
fi

log_success "Credentials found: $CRED_FILE"

# Copy credentials to cloudflared config directory
log_info "Installing tunnel credentials..."
cp "$CRED_FILE" "$CLOUDFLARED_CONFIG_DIR/${TUNNEL_ID}.json"
chown "$CLOUDFLARED_USER:$CLOUDFLARED_GROUP" "$CLOUDFLARED_CONFIG_DIR/${TUNNEL_ID}.json"
chmod 600 "$CLOUDFLARED_CONFIG_DIR/${TUNNEL_ID}.json"
log_success "Credentials installed to $CLOUDFLARED_CONFIG_DIR"

# Create cloudflared configuration
log_info "Creating cloudflared configuration..."

cat > "$CLOUDFLARED_CONFIG_DIR/config.yml" <<EOF
tunnel: $TUNNEL_ID
credentials-file: $CLOUDFLARED_CONFIG_DIR/${TUNNEL_ID}.json

# TCP ingress to local Xray service
ingress:
  - service: tcp://127.0.0.1:$XRAY_PORT

# Catch-all rule (required by Cloudflare)
  - service: http_status:404
EOF

chown "$CLOUDFLARED_USER:$CLOUDFLARED_GROUP" "$CLOUDFLARED_CONFIG_DIR/config.yml"
chmod 640 "$CLOUDFLARED_CONFIG_DIR/config.yml"
log_success "Configuration created: $CLOUDFLARED_CONFIG_DIR/config.yml"

# Get tunnel hostname
log_info "Retrieving tunnel hostname..."
TUNNEL_HOSTNAME=$(cloudflared tunnel list --output json | jq -r ".[] | select(.id==\"$TUNNEL_ID\") | .connections[0].colo_name // empty" 2>/dev/null || echo "")

# Construct tunnel hostname (Cloudflare default format)
TUNNEL_HOSTNAME="${TUNNEL_ID}.cfargotunnel.com"
log_success "Tunnel hostname: $TUNNEL_HOSTNAME"

# Update export file with tunnel information
log_info "Updating export file with tunnel information..."
if [ -f "$EXPORT_DIR/exit_node_info.json" ]; then
    TMP_FILE=$(mktemp)
    jq --arg hostname "$TUNNEL_HOSTNAME" '.tunnel_hostname = $hostname' "$EXPORT_DIR/exit_node_info.json" > "$TMP_FILE"
    mv "$TMP_FILE" "$EXPORT_DIR/exit_node_info.json"
    log_success "Export file updated: $EXPORT_DIR/exit_node_info.json"
else
    log_warning "Export file not found, creating new one..."
    cat > "$EXPORT_DIR/exit_node_info.json" <<EOF
{
  "node_type": "xray-vless-exit",
  "tunnel_id": "$TUNNEL_ID",
  "tunnel_name": "$TUNNEL_NAME",
  "tunnel_hostname": "$TUNNEL_HOSTNAME",
  "listen_address": "127.0.0.1",
  "listen_port": $XRAY_PORT,
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    log_success "Export file created"
fi

# Test tunnel configuration
log_info "Testing tunnel configuration..."
if sudo -u "$CLOUDFLARED_USER" cloudflared tunnel --config "$CLOUDFLARED_CONFIG_DIR/config.yml" info 2>/dev/null | grep -q "$TUNNEL_ID"; then
    log_success "Tunnel configuration test passed"
else
    log_warning "Could not verify tunnel configuration (this may be normal)"
fi

# Summary
log_section "Cloudflare Tunnel Configuration Complete"

echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW} Tunnel Information${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Tunnel Name: ${GREEN}$TUNNEL_NAME${NC}"
echo -e "  Tunnel ID:   ${GREEN}$TUNNEL_ID${NC}"
echo -e "  Hostname:    ${GREEN}$TUNNEL_HOSTNAME${NC}"
echo ""
echo "  Local Service: tcp://127.0.0.1:$XRAY_PORT"
echo ""
echo "  Configure your transit server to connect to:"
echo -e "    ${GREEN}$TUNNEL_HOSTNAME:443${NC}"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

log_success "Configuration file: $CLOUDFLARED_CONFIG_DIR/config.yml"
log_success "Credentials: $CLOUDFLARED_CONFIG_DIR/${TUNNEL_ID}.json"
log_success "Export file: $EXPORT_DIR/exit_node_info.json"

echo -e "\n${GREEN}▶${NC} Next step: Run ${BLUE}06-systemd-enable.sh${NC}"
