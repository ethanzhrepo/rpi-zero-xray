#!/usr/bin/env bash
#
# check-status.sh - Status check and diagnostics
# Comprehensive health check for Xray exit node
#

set -euo pipefail

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# ============================================================================
# Helper Functions
# ============================================================================

check_service() {
    local service="$1"
    local status

    status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")

    if [[ "$status" == "active" ]]; then
        echo -e "  ${GREEN}●${NC} $service: ${GREEN}active${NC}"
        return 0
    else
        echo -e "  ${RED}●${NC} $service: ${RED}$status${NC}"
        return 1
    fi
}

check_port() {
    local port="$1"
    local description="$2"

    if ss -tlnp 2>/dev/null | grep -q ":$port"; then
        echo -e "  ${GREEN}✓${NC} $description listening on port $port"
        return 0
    else
        echo -e "  ${RED}✗${NC} $description NOT listening on port $port"
        return 1
    fi
}

get_uptime() {
    local service="$1"
    local uptime

    uptime=$(systemctl show "$service" --property=ActiveEnterTimestamp --value 2>/dev/null || echo "unknown")

    if [[ "$uptime" != "unknown" && -n "$uptime" ]]; then
        local start_time
        start_time=$(date -d "$uptime" +%s 2>/dev/null || echo "0")
        local current_time
        current_time=$(date +%s)
        local diff=$((current_time - start_time))

        local days=$((diff / 86400))
        local hours=$(( (diff % 86400) / 3600 ))
        local minutes=$(( (diff % 3600) / 60 ))

        if [ "$days" -gt 0 ]; then
            echo "${days}d ${hours}h ${minutes}m"
        elif [ "$hours" -gt 0 ]; then
            echo "${hours}h ${minutes}m"
        else
            echo "${minutes}m"
        fi
    else
        echo "unknown"
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

log_section "Xray Exit Node - Status Check"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_warning "Running without root privileges - some checks may be limited"
    echo ""
fi

# ============================================================================
# Service Status
# ============================================================================

log_section "Service Status"

echo ""
SERVICES_OK=true

if check_service "xray.service"; then
    XRAY_UPTIME=$(get_uptime "xray.service")
    echo "    Uptime: $XRAY_UPTIME"
else
    SERVICES_OK=false
fi

echo ""

if check_service "cloudflared.service"; then
    CLOUDFLARED_UPTIME=$(get_uptime "cloudflared.service")
    echo "    Uptime: $CLOUDFLARED_UPTIME"
else
    SERVICES_OK=false
fi

echo ""

# ============================================================================
# Port Listening Check
# ============================================================================

log_section "Port Listening Check"

echo ""
PORTS_OK=true

if ! check_port "$XRAY_PORT" "Xray"; then
    PORTS_OK=false
fi

echo ""

# ============================================================================
# Process Check
# ============================================================================

log_section "Process Information"

echo ""

if pgrep -x xray &>/dev/null; then
    XRAY_PID=$(pgrep -x xray)
    XRAY_MEM=$(ps -p "$XRAY_PID" -o rss= 2>/dev/null | awk '{printf "%.1f MB", $1/1024}')
    XRAY_CPU=$(ps -p "$XRAY_PID" -o %cpu= 2>/dev/null || echo "N/A")
    echo -e "  ${GREEN}✓${NC} Xray process: PID $XRAY_PID"
    echo "    Memory: $XRAY_MEM"
    echo "    CPU: $XRAY_CPU%"
else
    echo -e "  ${RED}✗${NC} Xray process not running"
fi

echo ""

if pgrep -x cloudflared &>/dev/null; then
    CF_PID=$(pgrep -x cloudflared)
    CF_MEM=$(ps -p "$CF_PID" -o rss= 2>/dev/null | awk '{printf "%.1f MB", $1/1024}')
    CF_CPU=$(ps -p "$CF_PID" -o %cpu= 2>/dev/null || echo "N/A")
    echo -e "  ${GREEN}✓${NC} Cloudflared process: PID $CF_PID"
    echo "    Memory: $CF_MEM"
    echo "    CPU: $CF_CPU%"
else
    echo -e "  ${RED}✗${NC} Cloudflared process not running"
fi

echo ""

# ============================================================================
# Configuration Check
# ============================================================================

log_section "Configuration Files"

echo ""

if [ -f "$CONFIG_DIR/xray.json" ]; then
    echo -e "  ${GREEN}✓${NC} Xray config: $CONFIG_DIR/xray.json"
else
    echo -e "  ${RED}✗${NC} Xray config missing: $CONFIG_DIR/xray.json"
fi

if [ -f "$CLOUDFLARED_CONFIG_DIR/config.yml" ]; then
    echo -e "  ${GREEN}✓${NC} Cloudflared config: $CLOUDFLARED_CONFIG_DIR/config.yml"
else
    echo -e "  ${RED}✗${NC} Cloudflared config missing: $CLOUDFLARED_CONFIG_DIR/config.yml"
fi

echo ""

# ============================================================================
# Tunnel Information
# ============================================================================

log_section "Cloudflare Tunnel Information"

echo ""

if [ -f "$EXPORT_DIR/exit_node_info.json" ]; then
    TUNNEL_HOSTNAME=$(jq -r '.tunnel_hostname // "N/A"' "$EXPORT_DIR/exit_node_info.json")
    UUID=$(jq -r '.uuid // "N/A"' "$EXPORT_DIR/exit_node_info.json")
    XRAY_VERSION=$(jq -r '.xray_version // "N/A"' "$EXPORT_DIR/exit_node_info.json")

    echo "  Tunnel Hostname: $TUNNEL_HOSTNAME"
    echo "  UUID: $UUID"
    echo "  Xray Version: $XRAY_VERSION"
else
    echo -e "  ${YELLOW}⚠${NC} Node info file not found"
fi

echo ""

# ============================================================================
# System Resources
# ============================================================================

log_section "System Resources"

echo ""

# CPU Temperature (Raspberry Pi specific)
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP_C=$((TEMP / 1000))
    if [ "$TEMP_C" -gt 80 ]; then
        echo -e "  CPU Temperature: ${RED}${TEMP_C}°C (HIGH)${NC}"
    elif [ "$TEMP_C" -gt 70 ]; then
        echo -e "  CPU Temperature: ${YELLOW}${TEMP_C}°C (WARM)${NC}"
    else
        echo -e "  CPU Temperature: ${GREEN}${TEMP_C}°C${NC}"
    fi
else
    echo "  CPU Temperature: N/A"
fi

# Memory usage
if command -v free &>/dev/null; then
    MEM_TOTAL=$(free -m | awk 'NR==2 {print $2}')
    MEM_USED=$(free -m | awk 'NR==2 {print $3}')
    MEM_PERCENT=$((MEM_USED * 100 / MEM_TOTAL))

    if [ "$MEM_PERCENT" -gt 90 ]; then
        echo -e "  Memory Usage: ${RED}${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PERCENT}%)${NC}"
    elif [ "$MEM_PERCENT" -gt 80 ]; then
        echo -e "  Memory Usage: ${YELLOW}${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PERCENT}%)${NC}"
    else
        echo -e "  Memory Usage: ${GREEN}${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PERCENT}%)${NC}"
    fi
fi

# Disk usage
if command -v df &>/dev/null; then
    DISK_USAGE=$(df -h /opt | awk 'NR==2 {print $5}' | sed 's/%//')
    DISK_AVAIL=$(df -h /opt | awk 'NR==2 {print $4}')

    if [ "$DISK_USAGE" -gt 90 ]; then
        echo -e "  Disk Usage (/opt): ${RED}${DISK_USAGE}% (${DISK_AVAIL} free)${NC}"
    elif [ "$DISK_USAGE" -gt 80 ]; then
        echo -e "  Disk Usage (/opt): ${YELLOW}${DISK_USAGE}% (${DISK_AVAIL} free)${NC}"
    else
        echo -e "  Disk Usage (/opt): ${GREEN}${DISK_USAGE}% (${DISK_AVAIL} free)${NC}"
    fi
fi

# Load average
if [ -f /proc/loadavg ]; then
    LOAD=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
    echo "  Load Average: $LOAD"
fi

echo ""

# ============================================================================
# Network Connectivity
# ============================================================================

log_section "Network Connectivity"

echo ""

if ping -c 1 -W 2 1.1.1.1 &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Internet connectivity: OK"
else
    echo -e "  ${RED}✗${NC} Internet connectivity: FAILED"
fi

if ping -c 1 -W 2 cloudflare.com &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} DNS resolution: OK"
else
    echo -e "  ${RED}✗${NC} DNS resolution: FAILED"
fi

echo ""

# ============================================================================
# Recent Logs
# ============================================================================

log_section "Recent Log Entries"

echo ""
echo -e "${BLUE}Xray logs (last 10 lines):${NC}"
if [[ $EUID -eq 0 ]]; then
    journalctl -u xray.service -n 10 --no-pager 2>/dev/null || echo "  Unable to read logs"
else
    echo "  Run with sudo to view logs"
fi

echo ""
echo -e "${BLUE}Cloudflared logs (last 10 lines):${NC}"
if [[ $EUID -eq 0 ]]; then
    journalctl -u cloudflared.service -n 10 --no-pager 2>/dev/null || echo "  Unable to read logs"
else
    echo "  Run with sudo to view logs"
fi

echo ""

# ============================================================================
# Overall Status Summary
# ============================================================================

log_section "Overall Status"

echo ""

if [[ "$SERVICES_OK" == "true" && "$PORTS_OK" == "true" ]]; then
    echo -e "  ${GREEN}✓ System Status: HEALTHY${NC}"
    echo ""
    echo "  All services are running normally."
    exit 0
else
    echo -e "  ${RED}✗ System Status: ISSUES DETECTED${NC}"
    echo ""
    if [[ "$SERVICES_OK" == "false" ]]; then
        echo "  - One or more services are not running"
    fi
    if [[ "$PORTS_OK" == "false" ]]; then
        echo "  - Xray is not listening on expected port"
    fi
    echo ""
    echo "  Check the logs for more details:"
    echo "    sudo journalctl -u xray.service -n 50"
    echo "    sudo journalctl -u cloudflared.service -n 50"
    exit 1
fi
