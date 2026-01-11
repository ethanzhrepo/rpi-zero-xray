#!/usr/bin/env bash
#
# 01-install-deps.sh - Install build dependencies
# Installs Go, Git, jq, and other required tools
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

log_section "Installing Build Dependencies"

check_root
check_internet

# Install basic build tools
log_info "Installing basic build tools..."
apt-get install -y -qq \
    git \
    curl \
    wget \
    jq \
    build-essential \
    ca-certificates \
    gnupg \
    || { log_error "Failed to install basic build tools"; exit 1; }
log_success "Basic build tools installed"

# Check if Go is already installed and meets version requirement
MIN_GO_VERSION="1.21"
GO_INSTALLED=false
GO_VERSION_OK=false

if command -v go &>/dev/null; then
    GO_INSTALLED=true
    CURRENT_GO_VERSION=$(go version | grep -oP 'go\K[0-9]+\.[0-9]+' || echo "0.0")
    log_info "Found Go version: $CURRENT_GO_VERSION"

    # Compare versions (simple comparison for major.minor)
    if awk -v cur="$CURRENT_GO_VERSION" -v min="$MIN_GO_VERSION" 'BEGIN {exit !(cur >= min)}'; then
        GO_VERSION_OK=true
        log_success "Go version meets minimum requirement (>= $MIN_GO_VERSION)"
    else
        log_warning "Go version $CURRENT_GO_VERSION is below minimum $MIN_GO_VERSION, will install/upgrade"
    fi
fi

# Install or upgrade Go if needed
if [[ "$GO_INSTALLED" == "false" || "$GO_VERSION_OK" == "false" ]]; then
    log_info "Installing Go for ARM64..."

    # Determine latest stable Go version for ARM64
    GO_VERSION="1.23.5"  # Explicitly set stable version for ARM64
    GO_TARBALL="go${GO_VERSION}.linux-arm64.tar.gz"
    GO_URL="https://go.dev/dl/${GO_TARBALL}"

    log_info "Downloading Go ${GO_VERSION}..."

    # Download Go
    cd /tmp
    if wget -q --show-progress "$GO_URL"; then
        log_success "Go tarball downloaded"
    else
        log_error "Failed to download Go from $GO_URL"
        exit 1
    fi

    # Remove old Go installation if exists
    if [ -d /usr/local/go ]; then
        log_info "Removing old Go installation..."
        rm -rf /usr/local/go
    fi

    # Extract Go
    log_info "Extracting Go..."
    tar -C /usr/local -xzf "$GO_TARBALL"
    rm -f "$GO_TARBALL"

    # Add Go to PATH
    if ! grep -q '/usr/local/go/bin' /etc/profile; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    fi

    # Make Go available in current session
    export PATH=$PATH:/usr/local/go/bin

    log_success "Go ${GO_VERSION} installed"

    # Verify installation
    if /usr/local/go/bin/go version; then
        log_success "Go installation verified"
    else
        log_error "Go installation verification failed"
        exit 1
    fi
else
    log_success "Go is already installed and meets requirements"
fi

# Ensure Go is in PATH for all users
if [ ! -f /etc/profile.d/go.sh ]; then
    log_info "Creating Go profile script..."
    cat > /etc/profile.d/go.sh <<'EOF'
export PATH=$PATH:/usr/local/go/bin
export GOPATH=${HOME}/.go
export GOCACHE=${HOME}/.cache/go-build
EOF
    chmod +x /etc/profile.d/go.sh
    log_success "Go profile script created"
fi

# Source the profile to make Go available
export PATH=$PATH:/usr/local/go/bin
export GOPATH=${HOME}/.go
export GOCACHE=${HOME}/.cache/go-build

# Verify all required tools
log_info "Verifying installed tools..."

TOOLS_OK=true

if ! command -v git &>/dev/null; then
    log_error "git not found"
    TOOLS_OK=false
else
    GIT_VERSION=$(git --version | cut -d' ' -f3)
    log_success "git version $GIT_VERSION"
fi

if ! command -v jq &>/dev/null; then
    log_error "jq not found"
    TOOLS_OK=false
else
    JQ_VERSION=$(jq --version | cut -d'-' -f2)
    log_success "jq version $JQ_VERSION"
fi

if ! command -v curl &>/dev/null; then
    log_error "curl not found"
    TOOLS_OK=false
else
    CURL_VERSION=$(curl --version | head -n1 | cut -d' ' -f2)
    log_success "curl version $CURL_VERSION"
fi

if ! command -v go &>/dev/null; then
    log_error "go not found in PATH"
    TOOLS_OK=false
else
    FINAL_GO_VERSION=$(go version | grep -oP 'go\K[0-9.]+')
    log_success "go version $FINAL_GO_VERSION"
fi

if [[ "$TOOLS_OK" == "false" ]]; then
    log_error "Some required tools are missing"
    exit 1
fi

# Create Go build directories
log_info "Creating Go build directories..."
mkdir -p "$GOPATH"/{src,bin,pkg}
mkdir -p "$GOCACHE"
log_success "Go build directories created"

# Summary
log_section "Dependency Installation Complete"
log_success "All build dependencies installed and verified"
echo ""
echo "Installed tools:"
echo "  - Git: $GIT_VERSION"
echo "  - jq: $JQ_VERSION"
echo "  - curl: $CURL_VERSION"
echo "  - Go: $FINAL_GO_VERSION"
echo ""
log_success "GOPATH: $GOPATH"
log_success "GOCACHE: $GOCACHE"

echo -e "\n${GREEN}▶${NC} Next step: Run ${BLUE}02-build-xray.sh${NC}"
