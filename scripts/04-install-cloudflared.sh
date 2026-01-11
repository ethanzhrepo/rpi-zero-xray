#!/usr/bin/env bash
#
# 04-install-cloudflared.sh - Install Cloudflare Tunnel daemon
# Downloads and installs cloudflared binary for ARM64
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

log_section "Installing Cloudflare Tunnel (cloudflared)"

check_root
check_internet

# Detect architecture
ARCH=$(uname -m)
log_info "Detected architecture: $ARCH"

# Determine download URL based on architecture
if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
    log_success "Architecture is ARM64"
elif [[ "$ARCH" == "armv7l" || "$ARCH" == "armhf" ]]; then
    CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm"
    log_warning "Architecture is ARMv7 (32-bit) - performance may be limited"
else
    log_error "Unsupported architecture: $ARCH"
    exit 1
fi

# Check if cloudflared is already installed
if [ -x /usr/local/bin/cloudflared ]; then
    EXISTING_VERSION=$(cloudflared --version 2>&1 | head -n1 || echo "unknown")
    log_info "cloudflared is already installed: $EXISTING_VERSION"
    read -p "Do you want to reinstall/upgrade? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Keeping existing cloudflared installation"
        # Still create user and directories if needed
        if ! id "$CLOUDFLARED_USER" &>/dev/null; then
            log_info "Creating cloudflared user..."
            useradd --system --no-create-home --shell /usr/sbin/nologin "$CLOUDFLARED_USER"
            log_success "User $CLOUDFLARED_USER created"
        fi
        mkdir -p "$CLOUDFLARED_CONFIG_DIR"
        chown "$CLOUDFLARED_USER:$CLOUDFLARED_GROUP" "$CLOUDFLARED_CONFIG_DIR"
        log_success "Cloudflared setup verified"
        echo -e "\n${GREEN}▶${NC} Next step: Run ${BLUE}05-config-tunnel.sh${NC}"
        exit 0
    fi
fi

# Download cloudflared
log_info "Downloading cloudflared from GitHub releases..."
TEMP_FILE="/tmp/cloudflared-download"

if wget -q --show-progress -O "$TEMP_FILE" "$CLOUDFLARED_URL"; then
    log_success "cloudflared downloaded successfully"
else
    log_error "Failed to download cloudflared from $CLOUDFLARED_URL"
    exit 1
fi

# Verify download is a valid binary
log_info "Verifying downloaded binary..."
if file "$TEMP_FILE" | grep -q "ELF.*executable"; then
    log_success "Binary verification passed"
else
    log_error "Downloaded file is not a valid ELF executable"
    rm -f "$TEMP_FILE"
    exit 1
fi

# Install binary
log_info "Installing cloudflared to /usr/local/bin/cloudflared..."
mv "$TEMP_FILE" /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared
log_success "cloudflared installed"

# Verify installation
log_info "Verifying installation..."
if cloudflared --version; then
    INSTALLED_VERSION=$(cloudflared --version 2>&1 | head -n1)
    log_success "cloudflared installed successfully"
    echo "  $INSTALLED_VERSION"
else
    log_error "cloudflared installation verification failed"
    exit 1
fi

# Create cloudflared user and group if not exists
log_info "Creating cloudflared user and group..."
if ! id "$CLOUDFLARED_USER" &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "$CLOUDFLARED_USER"
    log_success "User $CLOUDFLARED_USER created"
else
    log_success "User $CLOUDFLARED_USER already exists"
fi

# Create configuration directory
log_info "Creating configuration directory..."
mkdir -p "$CLOUDFLARED_CONFIG_DIR"
chown "$CLOUDFLARED_USER:$CLOUDFLARED_GROUP" "$CLOUDFLARED_CONFIG_DIR"
chmod 750 "$CLOUDFLARED_CONFIG_DIR"
log_success "Configuration directory created: $CLOUDFLARED_CONFIG_DIR"

# Summary
log_section "Cloudflared Installation Complete"
log_success "cloudflared binary: /usr/local/bin/cloudflared"
log_success "Configuration directory: $CLOUDFLARED_CONFIG_DIR"
log_success "User: $CLOUDFLARED_USER"

echo -e "\n${GREEN}▶${NC} Next step: Run ${BLUE}05-config-tunnel.sh${NC}"
