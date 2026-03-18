#!/bin/bash

# ============================================================
# privacy-audit.sh — macOS Privacy & Permissions Audit
# Part of mac-toolbox • Zero dependencies • bash 3.2+
#
# Features:
#   - Lists all apps with privacy permissions
#   - Categories: Full Disk Access, Camera, Microphone,
#     Screen Recording, Accessibility, Automation
#   - Flags apps that have been removed but still hold perms
#   - Shows which permissions each app has been granted
#
# Security:
#   - Read-only — never modifies TCC database
#   - Reads from user-accessible TCC.db only
#   - No SIP bypass, no elevated privileges
#
# Usage:
#   ./privacy-audit.sh
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

divider() { echo -e "${DIM}$(printf '─%.0s' {1..64})${NC}"; }
press_enter() { echo ""; read -rp "  Press Enter to continue..." _; }

header() {
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}  ║  Privacy & Permissions Audit v${VERSION}                      ║${NC}"
    echo -e "${CYAN}${BOLD}  ╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ===================== TCC DATABASE =====================
# The TCC (Transparency, Consent, and Control) database stores
# all privacy permissions. The user-level DB is readable without SIP.
TCC_USER_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"

# Map TCC service names to human-readable labels
service_label() {
    case "$1" in
        kTCCServiceMicrophone)           echo "Microphone" ;;
        kTCCServiceCamera)               echo "Camera" ;;
        kTCCServiceScreenCapture)        echo "Screen Recording" ;;
        kTCCServiceAccessibility)        echo "Accessibility" ;;
        kTCCServiceSystemPolicyAllFiles) echo "Full Disk Access" ;;
        kTCCServiceSystemPolicySysAdminFiles) echo "Admin Files" ;;
        kTCCServiceAddressBook)          echo "Contacts" ;;
        kTCCServiceCalendar)             echo "Calendar" ;;
        kTCCServiceReminders)            echo "Reminders" ;;
        kTCCServicePhotos)               echo "Photos" ;;
        kTCCServiceMediaLibrary)         echo "Media & Music" ;;
        kTCCServiceBluetoothAlways)      echo "Bluetooth" ;;
        kTCCServiceLocation)             echo "Location" ;;
        kTCCServiceMotion)               echo "Motion & Fitness" ;;
        kTCCServiceSpeechRecognition)    echo "Speech Recognition" ;;
        kTCCServiceAppleEvents)          echo "Automation" ;;
        kTCCServiceListenEvent)          echo "Input Monitoring" ;;
        kTCCServicePostEvent)            echo "Accessibility (Post)" ;;
        kTCCServiceSystemPolicyDesktopFolder) echo "Desktop Folder" ;;
        kTCCServiceSystemPolicyDocumentsFolder) echo "Documents Folder" ;;
        kTCCServiceSystemPolicyDownloadsFolder) echo "Downloads Folder" ;;
        kTCCServiceSystemPolicyNetworkVolumes) echo "Network Volumes" ;;
        kTCCServiceSystemPolicyRemovableVolumes) echo "Removable Volumes" ;;
        kTCCServiceDeveloperTool)        echo "Developer Tools" ;;
        kTCCServiceFocusStatus)          echo "Focus Status" ;;
        *)                               echo "$1" ;;
    esac
}

# Priority categories for display
PRIORITY_SERVICES=(
    "kTCCServiceSystemPolicyAllFiles"
    "kTCCServiceScreenCapture"
    "kTCCServiceCamera"
    "kTCCServiceMicrophone"
    "kTCCServiceAccessibility"
    "kTCCServiceListenEvent"
    "kTCCServiceAppleEvents"
)

# ===================== READ PERMISSIONS =====================
read_tcc_permissions() {
    if [ ! -f "$TCC_USER_DB" ]; then
        echo -e "  ${YELLOW}TCC database not accessible.${NC}"
        echo -e "  ${DIM}This may happen on newer macOS versions with stricter SIP.${NC}"
        echo -e "  ${DIM}Falling back to tccutil and system_profiler...${NC}"
        return 1
    fi

    # Query the TCC database
    # auth_value: 0=denied, 1=unknown, 2=allowed
    sqlite3 "$TCC_USER_DB" \
        "SELECT service, client, auth_value, auth_reason, last_modified FROM access WHERE auth_value = 2;" \
        2>/dev/null
}

# ===================== PERMISSION REPORT =====================
permission_report() {
    header
    echo -e "  ${BOLD}Privacy Permissions Report${NC}"
    echo -e "  ${DIM}Apps with granted privacy permissions${NC}"
    echo ""

    if [ ! -f "$TCC_USER_DB" ]; then
        # Fallback: use tccutil list (limited info)
        echo -e "  ${YELLOW}Cannot read TCC database directly.${NC}"
        echo -e "  ${DIM}Showing available info from system tools...${NC}"
        echo ""

        # At minimum, show Login Items
        echo -e "  ${BOLD}Login Items (Background activity):${NC}"
        divider
        sfltool dumpbtm 2>/dev/null | grep -E "Name:|Developer|Path:" | \
            sed 's/^  */  /' | head -40 || \
            echo -e "  ${DIM}Could not retrieve. Check System Settings → General → Login Items.${NC}"

        press_enter
        return
    fi

    # Group permissions by service
    local current_service=""
    local -a orphan_apps=()

    for service in "${PRIORITY_SERVICES[@]}"; do
        local label
        label=$(service_label "$service")

        local -a apps=()
        while IFS='|' read -r svc client auth_val auth_reason last_mod; do
            [ "$svc" != "$service" ] && continue
            apps+=("$client")
        done < <(read_tcc_permissions)

        [ ${#apps[@]} -eq 0 ] && continue

        echo -e "  ${BOLD}${label}${NC}"
        divider

        for app in "${apps[@]}"; do
            # Extract readable name from bundle ID
            local display_name="$app"

            # Check if app still exists
            local exists=true
            local app_path=""
            app_path=$(mdfind "kMDItemCFBundleIdentifier == '$app'" 2>/dev/null | head -1)

            if [ -z "$app_path" ]; then
                exists=false
                orphan_apps+=("${app}|${label}")
            fi

            if [ "$exists" = true ]; then
                local pretty_name
                pretty_name=$(basename "$app_path" .app 2>/dev/null || echo "$app")
                echo -e "    ${GREEN}●${NC} ${pretty_name} ${DIM}(${app})${NC}"
            else
                echo -e "    ${RED}●${NC} ${app} ${RED}[REMOVED — still has permission]${NC}"
            fi
        done
        echo ""
    done

    # Also scan other services
    echo -e "  ${BOLD}Other Permissions${NC}"
    divider

    local -a other_services=()
    while IFS='|' read -r svc client auth_val auth_reason last_mod; do
        # Skip priority services already shown
        local is_priority=0
        for ps in "${PRIORITY_SERVICES[@]}"; do
            [ "$svc" = "$ps" ] && is_priority=1 && break
        done
        [ $is_priority -eq 1 ] && continue

        local label
        label=$(service_label "$svc")
        local display="$client"
        local app_path
        app_path=$(mdfind "kMDItemCFBundleIdentifier == '$client'" 2>/dev/null | head -1)
        [ -n "$app_path" ] && display=$(basename "$app_path" .app 2>/dev/null || echo "$client")

        printf "    ${DIM}%-22s${NC} %s\n" "$label" "$display"
    done < <(read_tcc_permissions)

    echo ""
    divider

    # Orphan summary
    if [ ${#orphan_apps[@]} -gt 0 ]; then
        echo ""
        echo -e "  ${RED}${BOLD}⚠  Orphan Permissions (${#orphan_apps[@]} found)${NC}"
        echo -e "  ${DIM}These apps have been removed but still hold privacy permissions.${NC}"
        echo -e "  ${DIM}Reset them in System Settings → Privacy & Security.${NC}"
        echo ""

        for orphan in "${orphan_apps[@]}"; do
            local app_id="${orphan%%|*}"
            local perm="${orphan##*|}"
            echo -e "    ${RED}•${NC} ${app_id} → ${perm}"
        done
    else
        echo -e "  ${GREEN}✓ No orphan permissions found.${NC}"
    fi
}

# ===================== PER-APP VIEW =====================
per_app_view() {
    header
    echo -e "  ${BOLD}Per-App Permission Lookup${NC}"
    echo ""
    read -rp "  App name or bundle ID: " query

    if [ -z "$query" ]; then
        return
    fi

    local lower_query
    lower_query=$(echo "$query" | tr '[:upper:]' '[:lower:]')

    echo ""
    echo -e "  ${BOLD}Permissions for '${query}':${NC}"
    divider

    local found=0
    while IFS='|' read -r svc client auth_val auth_reason last_mod; do
        local lower_client
        lower_client=$(echo "$client" | tr '[:upper:]' '[:lower:]')

        if [[ "$lower_client" == *"$lower_query"* ]]; then
            local label
            label=$(service_label "$svc")
            echo -e "    ${GREEN}✓${NC} ${label}"
            found=1
        fi
    done < <(read_tcc_permissions)

    if [ $found -eq 0 ]; then
        echo -e "  ${DIM}No permissions found matching '${query}'.${NC}"
    fi
}

# ===================== SECURITY QUICK CHECK =====================
security_check() {
    header
    echo -e "  ${BOLD}Security Quick Check${NC}"
    divider
    echo ""

    # FileVault
    local fv_status
    fv_status=$(fdesetup status 2>/dev/null)
    if echo "$fv_status" | grep -q "On"; then
        echo -e "  ${GREEN}✓${NC} FileVault:         Enabled"
    else
        echo -e "  ${RED}✗${NC} FileVault:         ${RED}Disabled${NC}"
        echo -e "    ${DIM}Enable in System Settings → Privacy & Security → FileVault${NC}"
    fi

    # Firewall
    local fw_status
    fw_status=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null)
    if [ "${fw_status:-0}" -ge 1 ]; then
        echo -e "  ${GREEN}✓${NC} Firewall:          Enabled"
    else
        echo -e "  ${YELLOW}!${NC} Firewall:          ${YELLOW}Disabled${NC}"
        echo -e "    ${DIM}Enable in System Settings → Network → Firewall${NC}"
    fi

    # SIP
    local sip_status
    sip_status=$(csrutil status 2>/dev/null)
    if echo "$sip_status" | grep -q "enabled"; then
        echo -e "  ${GREEN}✓${NC} SIP:               Enabled"
    else
        echo -e "  ${RED}✗${NC} SIP:               ${RED}Disabled${NC}"
        echo -e "    ${DIM}Re-enable from Recovery Mode: csrutil enable${NC}"
    fi

    # Gatekeeper
    local gk_status
    gk_status=$(spctl --status 2>/dev/null)
    if echo "$gk_status" | grep -q "enabled"; then
        echo -e "  ${GREEN}✓${NC} Gatekeeper:        Enabled"
    else
        echo -e "  ${YELLOW}!${NC} Gatekeeper:        ${YELLOW}Disabled${NC}"
    fi

    # Remote Login (SSH)
    local ssh_status
    ssh_status=$(systemsetup -getremotelogin 2>/dev/null || echo "unknown")
    if echo "$ssh_status" | grep -qi "off"; then
        echo -e "  ${GREEN}✓${NC} Remote Login (SSH): Off"
    elif echo "$ssh_status" | grep -qi "on"; then
        echo -e "  ${YELLOW}!${NC} Remote Login (SSH): ${YELLOW}On${NC}"
    fi

    # Sharing services
    echo ""
    echo -e "  ${BOLD}Sharing Services${NC}"
    divider
    local sharing_prefs="/Library/Preferences/com.apple.RemoteManagement.plist"
    if [ -f "$sharing_prefs" ]; then
        echo -e "  ${YELLOW}!${NC} Remote Management appears enabled"
    else
        echo -e "  ${GREEN}✓${NC} Remote Management: Off"
    fi

    # Screen Sharing
    local screen_sharing
    screen_sharing=$(launchctl list 2>/dev/null | grep -c "screensharing")
    if [ "$screen_sharing" -gt 0 ]; then
        echo -e "  ${YELLOW}!${NC} Screen Sharing: ${YELLOW}Active${NC}"
    else
        echo -e "  ${GREEN}✓${NC} Screen Sharing: Off"
    fi
}

# ===================== MAIN =====================
main_menu() {
    while true; do
        header
        echo -e "  ${BOLD}Choose an option:${NC}"
        echo ""
        echo -e "  ${GREEN}1.${NC}  Full permission report"
        echo -e "  ${GREEN}2.${NC}  Security quick check"
        echo -e "  ${GREEN}3.${NC}  Look up app permissions"
        echo -e "  ${GREEN}q.${NC}  Quit"
        echo ""
        divider
        read -rp "  > " choice

        case "$choice" in
            1) permission_report; press_enter ;;
            2) security_check; press_enter ;;
            3) per_app_view; press_enter ;;
            q|Q) echo -e "\n  ${GREEN}Done.${NC}\n"; exit 0 ;;
        esac
    done
}

main_menu
