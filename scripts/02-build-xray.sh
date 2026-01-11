#!/usr/bin/env bash
#
# 02-build-xray.sh - Build Xray from source
# Clones Xray-core repository and builds for ARM64
#

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Error handler
cleanup_on_error() {
    log_error "Script failed at line $1"
    if [ -d "$BUILD_DIR" ]; then
        log_info "Cleaning up build directory..."
        rm -rf "$BUILD_DIR"
    fi
}
trap 'cleanup_on_error $LINENO' ERR

# ============================================================================
# Main Execution
# ============================================================================

log_section "Building Xray $XRAY_VERSION from Source"

check_root
check_internet

# Ensure Go is available
if ! command -v go &>/dev/null; then
    log_error "Go is not installed. Please run 01-install-deps.sh first"
    exit 1
fi

GO_VERSION=$(go version | grep -oP 'go\K[0-9.]+')
log_info "Using Go version: $GO_VERSION"

# Set up Go environment
export PATH=$PATH:/usr/local/go/bin
export GOPATH=${HOME}/.go
export GOCACHE=${HOME}/.cache/go-build

# Clean up old build directory if exists
if [ -d "$BUILD_DIR" ]; then
    log_info "Cleaning up old build directory..."
    rm -rf "$BUILD_DIR"
fi

# Create build directory
log_info "Creating build directory: $BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Clone Xray-core repository
log_info "Cloning Xray-core repository..."
if git clone --depth=1 --branch "$XRAY_VERSION" https://github.com/XTLS/Xray-core.git "$BUILD_DIR"; then
    log_success "Xray-core cloned successfully"
else
    log_error "Failed to clone Xray-core repository"
    log_error "Please verify that version tag $XRAY_VERSION exists"
    exit 1
fi

# Enter build directory
cd "$BUILD_DIR"

log_info "Building Xray binary (this may take 5-10 minutes on RPi Zero 2 W)..."
log_warning "Building on ARM64 - expect slower compilation times"

# Build Xray with optimized flags
if go build -v -o xray -trimpath -ldflags "-s -w -buildid=" ./main; then
    log_success "Xray built successfully"
else
    log_error "Failed to build Xray"
    exit 1
fi

# Verify the binary
log_info "Verifying binary architecture..."
BINARY_ARCH=$(file xray | grep -oP 'ARM aarch64' || echo "unknown")
if [[ "$BINARY_ARCH" == "ARM aarch64" ]]; then
    log_success "Binary architecture verified: ARM aarch64"
else
    log_warning "Binary architecture: $(file xray)"
fi

# Get binary size
BINARY_SIZE=$(du -h xray | cut -f1)
log_info "Binary size: $BINARY_SIZE"

# Test binary execution
log_info "Testing Xray binary..."
if ./xray version; then
    log_success "Xray binary execution test passed"
else
    log_error "Xray binary execution test failed"
    exit 1
fi

# Create installation directory structure
log_info "Creating installation directory structure..."
mkdir -p "$INSTALL_DIR/bin"

# Install binary
log_info "Installing Xray binary to $INSTALL_DIR/bin/xray..."
cp xray "$INSTALL_DIR/bin/xray"
chmod +x "$INSTALL_DIR/bin/xray"
log_success "Xray binary installed"

# Set capabilities for binding to privileged ports (if needed)
log_info "Setting capabilities for Xray binary..."
if command -v setcap &>/dev/null; then
    if setcap cap_net_bind_service=+ep "$INSTALL_DIR/bin/xray"; then
        log_success "Capabilities set: cap_net_bind_service"
    else
        log_warning "Failed to set capabilities (may require libcap2-bin package)"
    fi
else
    log_warning "setcap not available, skipping capability setting"
fi

# Create xray user and group if not exists
log_info "Creating xray user and group..."
if ! id "$XRAY_USER" &>/dev/null; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "$XRAY_USER"
    log_success "User $XRAY_USER created"
else
    log_success "User $XRAY_USER already exists"
fi

# Set ownership and permissions
log_info "Setting ownership and permissions..."
chown -R "$XRAY_USER:$XRAY_GROUP" "$INSTALL_DIR"
chown -R "$XRAY_USER:$XRAY_GROUP" "$CONFIG_DIR"
chown -R "$XRAY_USER:$XRAY_GROUP" "$LOG_DIR"
chmod 755 "$INSTALL_DIR/bin"
chmod 755 "$INSTALL_DIR/bin/xray"
log_success "Ownership and permissions set"

# Clean up build directory
log_info "Cleaning up build directory..."
cd /
rm -rf "$BUILD_DIR"
log_success "Build directory cleaned"

# Verify installation
log_info "Verifying installation..."
if [ -x "$INSTALL_DIR/bin/xray" ]; then
    INSTALLED_VERSION=$("$INSTALL_DIR/bin/xray" version | head -n1)
    log_success "Xray installed successfully"
    echo ""
    echo "  $INSTALLED_VERSION"
    echo "  Location: $INSTALL_DIR/bin/xray"
    echo "  User: $XRAY_USER"
    echo ""
else
    log_error "Installation verification failed"
    exit 1
fi

# Summary
log_section "Xray Build Complete"
log_success "Xray $XRAY_VERSION built and installed"
log_success "Binary: $INSTALL_DIR/bin/xray"
log_success "User: $XRAY_USER"
log_success "Configuration directory: $CONFIG_DIR"
log_success "Log directory: $LOG_DIR"

echo -e "\n${GREEN}▶${NC} Next step: Run ${BLUE}03-config-xray.sh${NC}"
