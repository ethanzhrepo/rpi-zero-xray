#!/usr/bin/env bash
#
# Shared configuration for Raspberry Pi Zero 2 W Xray Exit Node
# Source this file in all deployment scripts
#

# Xray Configuration
readonly XRAY_VERSION="${XRAY_VERSION:-v25.12.8}"
readonly XRAY_PORT="${XRAY_PORT:-10808}"
readonly XRAY_USER="xray"
readonly XRAY_GROUP="xray"

# Cloudflared Configuration
readonly CLOUDFLARED_USER="cloudflared"
readonly CLOUDFLARED_GROUP="cloudflared"

# Installation Paths
readonly INSTALL_DIR="/opt/xray-exit"
readonly CONFIG_DIR="/etc/xray-exit"
readonly LOG_DIR="/var/log/xray-exit"
readonly CLOUDFLARED_CONFIG_DIR="/etc/cloudflared"

# Build Configuration
readonly BUILD_DIR="/tmp/xray-build"
readonly GOPATH="${HOME}/.go"
readonly GOCACHE="${HOME}/.cache/go-build"

# Project Paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly TEMPLATE_DIR="$PROJECT_DIR/config-template"
readonly SYSTEMD_DIR="$PROJECT_DIR/systemd"
readonly EXPORT_DIR="$PROJECT_DIR/export"

# System Configuration
readonly TIMEZONE="${TIMEZONE:-UTC}"

# Color Definitions (matching existing project style)
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# Logging Functions
log_info() {
    echo -e "${BLUE}▶${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

log_section() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE} $*${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Helper Functions
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

check_architecture() {
    local arch
    arch="$(uname -m)"
    if [[ "$arch" != "aarch64" && "$arch" != "arm64" ]]; then
        log_error "This script is designed for ARM64 architecture, detected: $arch"
        exit 1
    fi
}

check_internet() {
    if ! ping -c 1 -W 2 1.1.1.1 &>/dev/null; then
        log_error "No internet connectivity detected"
        exit 1
    fi
}
