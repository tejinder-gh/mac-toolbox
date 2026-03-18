#!/bin/bash

# ============================================================
# battery.sh — Battery Health Report
# Part of mac-toolbox • Zero dependencies • bash 3.2+
#
# Features:
#   - Cycle count and max capacity
#   - Health percentage and condition
#   - Current charge and time remaining
#   - Power-hungry process identification
#   - Temperature reading
#   - Charging history awareness
#
# Security:
#   - Read-only — never modifies power settings
#
# Usage:
#   ./battery.sh
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
    echo -e "${CYAN}${BOLD}  ║  Battery Health Report v${VERSION}                             ║${NC}"
    echo -e "${CYAN}${BOLD}  ╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ===================== CHECK LAPTOP =====================
check_battery() {
    if ! system_profiler SPPowerDataType &>/dev/null; then
        echo -e "  ${YELLOW}No battery detected. This tool is for MacBooks.${NC}"
        exit 0
    fi

    local has_battery
    has_battery=$(system_profiler SPPowerDataType 2>/dev/null | grep -c "Cycle Count")
    if [ "$has_battery" -eq 0 ]; then
        echo -e "  ${YELLOW}No battery detected (desktop Mac?).${NC}"
        exit 0
    fi
}

# ===================== BATTERY DATA =====================
get_battery_data() {
    local power_info
    power_info=$(system_profiler SPPowerDataType 2>/dev/null)

    # Parse values
    CYCLE_COUNT=$(echo "$power_info" | grep "Cycle Count:" | awk '{print $NF}')
    CONDITION=$(echo "$power_info" | grep "Condition:" | awk -F': ' '{print $2}')
    MAX_CAPACITY=$(echo "$power_info" | grep "Maximum Capacity:" | awk '{print $NF}' | tr -d '%')
    CHARGING=$(echo "$power_info" | grep "Charging:" | awk '{print $NF}')
    FULL_CHARGED=$(echo "$power_info" | grep "Fully Charged:" | awk '{print $NF}' | head -1)
    CONNECTED=$(echo "$power_info" | grep "Connected:" | awk '{print $NF}' | head -1)
    MANUFACTURE=$(echo "$power_info" | grep "Manufacturer:" | awk -F': ' '{print $2}')
    CELL_VOLTAGE=$(echo "$power_info" | grep "Voltage" | head -1 | awk '{print $NF}')

    # Get current percentage from pmset
    CURRENT_PCT=$(pmset -g batt 2>/dev/null | grep -o '[0-9]*%' | head -1 | tr -d '%')
    TIME_REMAINING=$(pmset -g batt 2>/dev/null | grep -o '[0-9]*:[0-9]*' | head -1)
    POWER_SOURCE=$(pmset -g batt 2>/dev/null | head -1 | grep -o "'.*'" | tr -d "'")
}

# ===================== HEALTH VISUALIZATION =====================
health_bar() {
    local pct="$1"
    local width=30

    local filled=$(( (pct * width) / 100 ))
    [ $filled -gt $width ] && filled=$width

    local bar=""
    local i
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=filled; i<width; i++)); do bar+="░"; done

    if [ "$pct" -ge 80 ]; then
        echo -e "${GREEN}${bar}${NC} ${pct}%"
    elif [ "$pct" -ge 50 ]; then
        echo -e "${YELLOW}${bar}${NC} ${pct}%"
    else
        echo -e "${RED}${bar}${NC} ${pct}%"
    fi
}

# ===================== MAIN REPORT =====================
battery_report() {
    header
    get_battery_data

    echo -e "  ${BOLD}Battery Overview${NC}"
    divider

    # Health status with color
    local health_color
    if [ "${MAX_CAPACITY:-0}" -ge 80 ]; then
        health_color="${GREEN}"
    elif [ "${MAX_CAPACITY:-0}" -ge 50 ]; then
        health_color="${YELLOW}"
    else
        health_color="${RED}"
    fi

    echo -e "  Health:        $(health_bar "${MAX_CAPACITY:-0}")"
    echo -e "  Condition:     ${health_color}${CONDITION:-unknown}${NC}"
    echo -e "  Cycle Count:   ${BOLD}${CYCLE_COUNT:-?}${NC}"

    # Max cycles info (Apple rates most at 1000)
    if [ -n "$CYCLE_COUNT" ]; then
        local max_cycles=1000
        local cycle_pct=$(( (CYCLE_COUNT * 100) / max_cycles ))
        echo -e "  Cycle Life:    ${cycle_pct}% used (of ~${max_cycles} rated)"
    fi

    echo ""
    echo -e "  ${BOLD}Current State${NC}"
    divider

    echo -e "  Charge:        $(health_bar "${CURRENT_PCT:-0}")"
    echo -e "  Power Source:  ${POWER_SOURCE:-unknown}"

    if [ "${CHARGING:-No}" = "Yes" ]; then
        echo -e "  Status:        ${GREEN}Charging${NC}"
    elif [ "${FULL_CHARGED:-No}" = "Yes" ]; then
        echo -e "  Status:        ${GREEN}Fully Charged${NC}"
    elif [ "${CONNECTED:-No}" = "Yes" ]; then
        echo -e "  Status:        ${CYAN}On AC (not charging)${NC}"
    else
        echo -e "  Status:        ${YELLOW}On Battery${NC}"
        [ -n "$TIME_REMAINING" ] && echo -e "  Remaining:     ${BOLD}${TIME_REMAINING}${NC}"
    fi

    [ -n "$CELL_VOLTAGE" ] && echo -e "  Voltage:       ${CELL_VOLTAGE} mV"

    # Tips
    echo ""
    echo -e "  ${BOLD}Health Tips${NC}"
    divider

    if [ "${MAX_CAPACITY:-0}" -lt 80 ]; then
        echo -e "  ${YELLOW}•${NC} Battery below 80% — consider replacement"
        echo -e "    ${DIM}Apple replaces under warranty if <80% and <1000 cycles${NC}"
    fi

    if [ "${CYCLE_COUNT:-0}" -gt 800 ]; then
        echo -e "  ${YELLOW}•${NC} High cycle count (${CYCLE_COUNT}/1000)"
    fi

    if [ "${CURRENT_PCT:-0}" -ge 100 ] && [ "${CONNECTED:-No}" = "Yes" ]; then
        echo -e "  ${DIM}•${NC} Fully charged on AC — macOS manages trickle charging automatically"
    fi

    echo -e "  ${DIM}•${NC} Keep between 20-80% for longest lifespan"
    echo -e "  ${DIM}•${NC} Enable Optimized Battery Charging in System Settings"
}

# ===================== POWER-HUNGRY PROCESSES =====================
power_hogs() {
    header
    echo -e "  ${BOLD}Power-Hungry Processes${NC}"
    echo -e "  ${DIM}(sorted by CPU usage — higher CPU = faster battery drain)${NC}"
    divider

    echo ""
    printf "  ${BOLD}%-6s  %-25s  %s${NC}\n" "CPU%" "Process" "PID"
    divider

    ps aux 2>/dev/null | sort -rn -k3 | head -15 | \
        awk '{printf "  %-6s  %-25s  %s\n", $3"%", $11, $2}' | \
        while IFS= read -r line; do
            local cpu_val
            cpu_val=$(echo "$line" | awk '{print $1}' | tr -d '%')
            if [ "${cpu_val%.*}" -ge 20 ]; then
                echo -e "${RED}${line}${NC}"
            elif [ "${cpu_val%.*}" -ge 5 ]; then
                echo -e "${YELLOW}${line}${NC}"
            else
                echo -e "${DIM}${line}${NC}"
            fi
        done

    # Assertions about energy
    echo ""
    echo -e "  ${BOLD}Energy Impact (via pmset)${NC}"
    divider
    pmset -g thermlog 2>/dev/null | head -5 || \
        echo -e "  ${DIM}Thermal data not available.${NC}"
}

# ===================== MAIN =====================
check_battery

main_menu() {
    while true; do
        header
        echo -e "  ${BOLD}Choose an option:${NC}"
        echo ""
        echo -e "  ${GREEN}1.${NC}  Battery health report"
        echo -e "  ${GREEN}2.${NC}  Power-hungry processes"
        echo -e "  ${GREEN}3.${NC}  Live charge monitor"
        echo -e "  ${GREEN}q.${NC}  Quit"
        echo ""
        divider
        read -rp "  > " choice

        case "$choice" in
            1) battery_report; press_enter ;;
            2) power_hogs; press_enter ;;
            3)
                echo -e "  ${DIM}Monitoring battery (Ctrl+C to stop)...${NC}"
                echo ""
                while true; do
                    local pct
                    pct=$(pmset -g batt 2>/dev/null | grep -o '[0-9]*%' | head -1)
                    local src
                    src=$(pmset -g batt 2>/dev/null | head -1 | grep -o "'.*'" | tr -d "'")
                    local status
                    status=$(pmset -g batt 2>/dev/null | grep -oE 'charging|discharging|charged|finishing charge' | head -1)

                    printf "\r  %s  %s  %-20s  %s" \
                        "$(date +%H:%M:%S)" "$pct" "$status" "$src"
                    sleep 5
                done
                ;;
            q|Q) echo -e "\n  ${GREEN}Done.${NC}\n"; exit 0 ;;
        esac
    done
}

main_menu
