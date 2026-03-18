#!/bin/bash

# ============================================================
# netcheck.sh — Network Diagnostics
# Part of mac-toolbox • Zero dependencies • bash 3.2+
#
# Features:
#   - WiFi signal strength and channel info
#   - DNS resolution speed test
#   - Ping latency to multiple targets
#   - Active connections and listening ports
#   - Public/private IP info
#   - Quick bandwidth estimate
#
# Security:
#   - Read-only — never modifies network settings
#   - No external data sent (except standard ping/DNS)
#
# Usage:
#   ./netcheck.sh
# ============================================================

set -uo pipefail

VERSION="1.0"

# ===================== COLORS =====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

divider() { echo -e "${DIM}$(printf '─%.0s' {1..60})${NC}"; }
press_enter() { echo ""; read -rp "  Press Enter to continue..." _; }

header() {
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}  ║  Network Diagnostics v${VERSION}                              ║${NC}"
    echo -e "${CYAN}${BOLD}  ╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ===================== WIFI INFO =====================
wifi_info() {
    echo -e "  ${BOLD}WiFi Status${NC}"
    divider

    # macOS airport utility path
    local airport="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"

    if [ ! -x "$airport" ]; then
        echo -e "  ${YELLOW}airport utility not found. Using system_profiler.${NC}"
        system_profiler SPAirPortDataType 2>/dev/null | grep -E "Status|SSID|Channel|Security|Signal|Noise|PHY Mode" | \
            sed 's/^  */  /'
        return
    fi

    local info
    info=$("$airport" -I 2>/dev/null)

    if [ -z "$info" ]; then
        echo -e "  ${RED}WiFi appears to be off or not connected.${NC}"
        return
    fi

    local ssid
    ssid=$(echo "$info" | grep ' SSID:' | awk -F': ' '{print $2}')
    local rssi
    rssi=$(echo "$info" | grep 'agrCtlRSSI:' | awk -F': ' '{print $2}')
    local noise
    noise=$(echo "$info" | grep 'agrCtlNoise:' | awk -F': ' '{print $2}')
    local channel
    channel=$(echo "$info" | grep ' channel:' | awk -F': ' '{print $2}')
    local tx_rate
    tx_rate=$(echo "$info" | grep 'lastTxRate:' | awk -F': ' '{print $2}')
    local security
    security=$(echo "$info" | grep 'link auth:' | awk -F': ' '{print $2}')

    echo -e "  Network:    ${BOLD}${ssid:-unknown}${NC}"
    echo -e "  Channel:    ${channel:-unknown}"
    echo -e "  Security:   ${security:-unknown}"
    echo -e "  TX Rate:    ${tx_rate:-?} Mbps"

    # Signal quality
    if [ -n "$rssi" ]; then
        local quality
        if [ "$rssi" -ge -50 ]; then
            quality="${GREEN}Excellent${NC}"
        elif [ "$rssi" -ge -60 ]; then
            quality="${GREEN}Good${NC}"
        elif [ "$rssi" -ge -70 ]; then
            quality="${YELLOW}Fair${NC}"
        else
            quality="${RED}Weak${NC}"
        fi
        echo -e "  Signal:     ${rssi} dBm (${quality})"
    fi

    [ -n "$noise" ] && echo -e "  Noise:      ${noise} dBm"

    if [ -n "$rssi" ] && [ -n "$noise" ]; then
        local snr=$((rssi - noise))
        echo -e "  SNR:        ${snr} dB"
    fi
}

# ===================== IP INFO =====================
ip_info() {
    echo -e "\n  ${BOLD}IP Addresses${NC}"
    divider

    # Private IPs
    local interfaces
    interfaces=$(ifconfig 2>/dev/null | grep -E '^[a-z]' | cut -d: -f1)

    for iface in $interfaces; do
        local ip
        ip=$(ifconfig "$iface" 2>/dev/null | grep 'inet ' | awk '{print $2}')
        [ -z "$ip" ] && continue
        [ "$ip" = "127.0.0.1" ] && continue

        local status="${GREEN}●${NC}"
        echo -e "  ${status} ${iface}: ${BOLD}${ip}${NC}"
    done

    # Public IP (using Apple's captive portal check endpoint — no tracking)
    echo -e "  ${DIM}Checking public IP...${NC}"
    local pub_ip
    pub_ip=$(curl -s --connect-timeout 3 --max-time 5 ifconfig.me 2>/dev/null || echo "unavailable")
    echo -e "  Public IP:  ${BOLD}${pub_ip}${NC}"

    # Default gateway
    local gateway
    gateway=$(route -n get default 2>/dev/null | grep 'gateway:' | awk '{print $2}')
    [ -n "$gateway" ] && echo -e "  Gateway:    ${gateway}"

    # DNS servers
    local dns
    dns=$(scutil --dns 2>/dev/null | grep 'nameserver' | head -3 | awk '{print $3}' | tr '\n' ', ' | sed 's/,$//')
    [ -n "$dns" ] && echo -e "  DNS:        ${dns}"
}

# ===================== DNS BENCHMARK =====================
dns_benchmark() {
    echo -e "\n  ${BOLD}DNS Resolution Speed${NC}"
    divider

    local -a dns_targets=("google.com" "apple.com" "github.com" "cloudflare.com" "amazon.com")

    for target in "${dns_targets[@]}"; do
        local start_ms
        start_ms=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time()*1000000000))" 2>/dev/null)

        local result
        result=$(nslookup "$target" 2>/dev/null | grep -c 'Address')

        local end_ms
        end_ms=$(date +%s%N 2>/dev/null || python3 -c "import time; print(int(time.time()*1000000000))" 2>/dev/null)

        if [ -n "$start_ms" ] && [ -n "$end_ms" ]; then
            local elapsed_ms=$(( (end_ms - start_ms) / 1000000 ))
            local speed_color
            if [ "$elapsed_ms" -lt 50 ]; then
                speed_color="${GREEN}"
            elif [ "$elapsed_ms" -lt 150 ]; then
                speed_color="${YELLOW}"
            else
                speed_color="${RED}"
            fi
            printf "  %-20s ${speed_color}%4d ms${NC}\n" "$target" "$elapsed_ms"
        else
            # Fallback without nanosecond timing
            printf "  %-20s ${DIM}resolved${NC}\n" "$target"
        fi
    done
}

# ===================== PING TEST =====================
ping_test() {
    echo -e "\n  ${BOLD}Latency Test${NC}"
    divider

    local -a ping_targets=("8.8.8.8|Google DNS" "1.1.1.1|Cloudflare" "208.67.222.222|OpenDNS")

    for entry in "${ping_targets[@]}"; do
        local ip="${entry%%|*}"
        local name="${entry##*|}"

        local result
        result=$(ping -c 3 -t 5 "$ip" 2>/dev/null | tail -1)

        if echo "$result" | grep -q 'avg'; then
            local avg
            avg=$(echo "$result" | awk -F'/' '{print $5}')
            local speed_color
            local avg_int=${avg%.*}
            if [ "$avg_int" -lt 20 ]; then
                speed_color="${GREEN}"
            elif [ "$avg_int" -lt 50 ]; then
                speed_color="${YELLOW}"
            else
                speed_color="${RED}"
            fi
            printf "  %-18s ${speed_color}%s ms avg${NC}\n" "$name" "$avg"
        else
            printf "  %-18s ${RED}unreachable${NC}\n" "$name"
        fi
    done
}

# ===================== ACTIVE CONNECTIONS =====================
active_connections() {
    echo -e "\n  ${BOLD}Active Connections${NC}"
    divider

    # Count by state
    local established
    established=$(netstat -an 2>/dev/null | grep -c ESTABLISHED)
    local listening
    listening=$(netstat -an 2>/dev/null | grep -c LISTEN)
    local time_wait
    time_wait=$(netstat -an 2>/dev/null | grep -c TIME_WAIT)

    echo -e "  Established: ${GREEN}${established}${NC}"
    echo -e "  Listening:   ${CYAN}${listening}${NC}"
    echo -e "  Time Wait:   ${DIM}${time_wait}${NC}"

    # Top connections by remote host
    echo ""
    echo -e "  ${DIM}Top remote hosts:${NC}"
    netstat -an 2>/dev/null | grep ESTABLISHED | awk '{print $5}' | \
        cut -d. -f1-4 | sort | uniq -c | sort -rn | head -5 | \
        while read -r count host; do
            printf "    %4d connections → %s\n" "$count" "$host"
        done

    # Listening ports (user processes)
    echo ""
    echo -e "  ${DIM}Listening ports (non-system):${NC}"
    lsof -iTCP -sTCP:LISTEN -n -P 2>/dev/null | grep -v "^COMMAND" | \
        awk '{printf "    %-15s %s\n", $1, $9}' | sort -u | head -10
}

# ===================== BANDWIDTH TEST =====================
bandwidth_test() {
    echo -e "\n  ${BOLD}Bandwidth Estimate${NC}"
    divider
    echo -e "  ${DIM}Downloading a test file to measure speed...${NC}"

    # Use Apple's captive portal test URL (small, reliable, no tracking)
    local url="http://captive.apple.com/hotspot-detect.html"
    local start_time end_time elapsed

    start_time=$(date +%s)

    # Download a larger file for better accuracy
    local bytes
    bytes=$(curl -s -o /dev/null -w '%{size_download}' --connect-timeout 5 --max-time 10 \
        "https://speed.cloudflare.com/__down?bytes=10000000" 2>/dev/null)

    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    if [ "$elapsed" -gt 0 ] && [ "${bytes:-0}" -gt 0 ]; then
        local mbps
        mbps=$(awk "BEGIN {printf \"%.1f\", ($bytes * 8) / ($elapsed * 1000000)}")
        echo -e "  Download: ~${BOLD}${mbps} Mbps${NC}"
        echo -e "  ${DIM}(rough estimate — use speedtest.net for accuracy)${NC}"
    else
        echo -e "  ${YELLOW}Could not measure bandwidth.${NC}"
    fi
}

# ===================== FULL REPORT =====================
full_report() {
    header
    echo -e "  ${BOLD}Network Diagnostics Report${NC}"
    echo -e "  ${DIM}$(date)${NC}"
    echo ""

    wifi_info
    ip_info
    dns_benchmark
    ping_test
    active_connections

    echo ""
    divider
}

# ===================== MAIN =====================
main_menu() {
    while true; do
        header
        echo -e "  ${BOLD}Choose an option:${NC}"
        echo ""
        echo -e "  ${GREEN}1.${NC}  Full diagnostics report"
        echo -e "  ${GREEN}2.${NC}  WiFi info"
        echo -e "  ${GREEN}3.${NC}  DNS benchmark"
        echo -e "  ${GREEN}4.${NC}  Ping test"
        echo -e "  ${GREEN}5.${NC}  Active connections"
        echo -e "  ${GREEN}6.${NC}  Bandwidth test"
        echo -e "  ${GREEN}q.${NC}  Quit"
        echo ""
        divider
        read -rp "  > " choice

        case "$choice" in
            1) full_report; press_enter ;;
            2) header; wifi_info; press_enter ;;
            3) header; dns_benchmark; press_enter ;;
            4) header; ping_test; press_enter ;;
            5) header; active_connections; press_enter ;;
            6) header; bandwidth_test; press_enter ;;
            q|Q) echo -e "\n  ${GREEN}Done.${NC}\n"; exit 0 ;;
        esac
    done
}

main_menu
