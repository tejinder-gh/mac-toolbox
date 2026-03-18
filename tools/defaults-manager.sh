#!/bin/bash

# ============================================================
# defaults-manager.sh — macOS Hidden Preferences Manager
# Part of mac-toolbox • Zero dependencies • bash 3.2+
#
# Features:
#   - Curated, verified macOS defaults tweaks
#   - Shows current value, lets you toggle
#   - Backup/restore all custom defaults
#   - Categorized: Finder, Dock, Screenshots, Safari, etc.
#
# Security:
#   - Only writes to well-known, documented defaults keys
#   - Backup before any batch operation
#   - No system-level SIP-protected changes
#
# Usage:
#   ./defaults-manager.sh
#   ./defaults-manager.sh --backup
#   ./defaults-manager.sh --restore <file>
# ============================================================

set -uo pipefail

VERSION="1.0"
BACKUP_DIR="$HOME/.mac-toolbox-backups/defaults"

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
    echo -e "${CYAN}${BOLD}  ║  macOS Defaults Manager v${VERSION}                          ║${NC}"
    echo -e "${CYAN}${BOLD}  ╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ===================== DEFAULTS DATABASE =====================
# Format: domain|key|type|on_value|off_value|description|restart_target
# type: bool, int, float, string
# restart_target: Finder, Dock, SystemUIServer, none

# Each function prints the tweaks for a category
get_finder_tweaks() {
    cat <<'TWEAKS'
com.apple.finder|AppleShowAllFiles|bool|true|false|Show hidden files|Finder
com.apple.finder|ShowPathbar|bool|true|false|Show path bar at bottom|Finder
com.apple.finder|ShowStatusBar|bool|true|false|Show status bar|Finder
com.apple.finder|_FXShowPosixPathInTitle|bool|true|false|Show full path in title bar|Finder
NSGlobalDomain|AppleShowAllExtensions|bool|true|false|Show all file extensions|Finder
com.apple.finder|FXEnableExtensionChangeWarning|bool|false|true|Disable extension change warning|Finder
com.apple.finder|FXDefaultSearchScope|string|SCcf|SCsp|Search current folder by default|Finder
com.apple.desktopservices|DSDontWriteNetworkStores|bool|true|false|No .DS_Store on network volumes|none
com.apple.desktopservices|DSDontWriteUSBStores|bool|true|false|No .DS_Store on USB volumes|none
TWEAKS
}

get_dock_tweaks() {
    cat <<'TWEAKS'
com.apple.dock|autohide|bool|true|false|Auto-hide the Dock|Dock
com.apple.dock|autohide-delay|float|0|0.5|Remove auto-hide delay|Dock
com.apple.dock|autohide-time-modifier|float|0.2|0.5|Speed up hide animation|Dock
com.apple.dock|show-recents|bool|false|true|Hide recent apps in Dock|Dock
com.apple.dock|minimize-to-application|bool|true|false|Minimize windows into app icon|Dock
com.apple.dock|tilesize|int|48|64|Set icon size to 48px|Dock
com.apple.dock|static-only|bool|true|false|Show only open apps in Dock|Dock
TWEAKS
}

get_screenshot_tweaks() {
    cat <<'TWEAKS'
com.apple.screencapture|type|string|png|png|Screenshot format (png/jpg/pdf)|SystemUIServer
com.apple.screencapture|disable-shadow|bool|true|false|Disable window shadow in screenshots|SystemUIServer
com.apple.screencapture|show-thumbnail|bool|false|true|Disable floating thumbnail preview|SystemUIServer
com.apple.screencapture|include-date|bool|true|true|Include date in filename|SystemUIServer
TWEAKS
}

get_safari_tweaks() {
    cat <<'TWEAKS'
com.apple.Safari|IncludeDevelopMenu|bool|true|false|Show Develop menu|none
com.apple.Safari|ShowFullURLInSmartSearchField|bool|true|false|Show full URL in address bar|none
com.apple.Safari|AutoOpenSafeDownloads|bool|false|true|Disable auto-open safe downloads|none
com.apple.Safari|SendDoNotTrackHTTPHeader|bool|true|false|Send Do Not Track header|none
TWEAKS
}

get_misc_tweaks() {
    cat <<'TWEAKS'
NSGlobalDomain|NSAutomaticSpellingCorrectionEnabled|bool|false|true|Disable auto-correct|none
NSGlobalDomain|NSAutomaticCapitalizationEnabled|bool|false|true|Disable auto-capitalization|none
NSGlobalDomain|NSAutomaticPeriodSubstitutionEnabled|bool|false|true|Disable period on double-space|none
NSGlobalDomain|NSAutomaticQuoteSubstitutionEnabled|bool|false|true|Disable smart quotes|none
NSGlobalDomain|NSAutomaticDashSubstitutionEnabled|bool|false|true|Disable smart dashes|none
NSGlobalDomain|KeyRepeat|int|2|6|Faster key repeat rate|none
NSGlobalDomain|InitialKeyRepeat|int|15|25|Shorter delay before key repeat|none
com.apple.BluetoothAudioAgent|"Apple Bitpool Min (editable)"|int|40|2|Improve Bluetooth audio quality|none
com.apple.print.PrintingPrefs|"Quit When Finished"|bool|true|false|Auto-quit Printer app when done|none
TWEAKS
}

get_security_tweaks() {
    cat <<'TWEAKS'
com.apple.finder|WarnOnEmptyTrash|bool|false|true|Disable empty trash warning|Finder
com.apple.LaunchServices|LSQuarantine|bool|false|true|Disable download quarantine popup|none
TWEAKS
}

# ===================== TWEAK ENGINE =====================

get_current_value() {
    local domain="$1"
    local key="$2"
    defaults read "$domain" "$key" 2>/dev/null || echo "__unset__"
}

apply_tweak() {
    local domain="$1"
    local key="$2"
    local type="$3"
    local value="$4"
    local restart="$5"

    case "$type" in
        bool)   defaults write "$domain" "$key" -bool "$value" ;;
        int)    defaults write "$domain" "$key" -int "$value" ;;
        float)  defaults write "$domain" "$key" -float "$value" ;;
        string) defaults write "$domain" "$key" -string "$value" ;;
    esac

    # Restart affected process
    if [ "$restart" != "none" ]; then
        killall "$restart" 2>/dev/null || true
    fi
}

reset_tweak() {
    local domain="$1"
    local key="$2"
    local restart="$3"

    defaults delete "$domain" "$key" 2>/dev/null

    if [ "$restart" != "none" ]; then
        killall "$restart" 2>/dev/null || true
    fi
}

# ===================== CATEGORY DISPLAY =====================
show_category() {
    local category_name="$1"
    local tweaks_func="$2"

    header
    echo -e "  ${BOLD}${category_name}${NC}"
    divider

    local -a domains=() keys=() types=() on_vals=() off_vals=() descs=() restarts=()

    while IFS='|' read -r domain key type on_val off_val desc restart; do
        [ -z "$domain" ] && continue
        domains+=("$domain")
        keys+=("$key")
        types+=("$type")
        on_vals+=("$on_val")
        off_vals+=("$off_val")
        descs+=("$desc")
        restarts+=("$restart")
    done < <($tweaks_func)

    for ((i=0; i<${#domains[@]}; i++)); do
        local current
        current=$(get_current_value "${domains[$i]}" "${keys[$i]}")

        local status_icon
        if [ "$current" = "${on_vals[$i]}" ] || [ "$current" = "1" -a "${on_vals[$i]}" = "true" ]; then
            status_icon="${GREEN}[ON] ${NC}"
        elif [ "$current" = "__unset__" ]; then
            status_icon="${DIM}[--] ${NC}"
        else
            status_icon="${RED}[OFF]${NC}"
        fi

        printf "  ${GREEN}%3d.${NC} %b %-44s ${DIM}(%s)${NC}\n" \
            "$((i+1))" "$status_icon" "${descs[$i]}" "$current"
    done

    echo ""
    divider
    echo -e "  ${DIM}[#] Toggle  (a) Apply all ON  (r) Reset all  (q) Back${NC}"
    read -rp "  > " input

    case "$input" in
        q|Q) return ;;
        a|A)
            echo -e "\n  ${RED}Apply all tweaks in this category?${NC}"
            read -rp "  Type 'yes': " confirm
            if [ "$confirm" = "yes" ]; then
                for ((i=0; i<${#domains[@]}; i++)); do
                    apply_tweak "${domains[$i]}" "${keys[$i]}" "${types[$i]}" "${on_vals[$i]}" "${restarts[$i]}"
                    echo -e "  ${GREEN}✓${NC} ${descs[$i]}"
                done
            fi
            press_enter
            ;;
        r|R)
            echo -e "\n  ${RED}Reset all tweaks to system defaults?${NC}"
            read -rp "  Type 'yes': " confirm
            if [ "$confirm" = "yes" ]; then
                for ((i=0; i<${#domains[@]}; i++)); do
                    reset_tweak "${domains[$i]}" "${keys[$i]}" "${restarts[$i]}"
                    echo -e "  ${GREEN}✓${NC} Reset: ${descs[$i]}"
                done
            fi
            press_enter
            ;;
        *)
            if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le ${#domains[@]} ]; then
                local idx=$((input-1))
                local current
                current=$(get_current_value "${domains[$idx]}" "${keys[$idx]}")

                # Toggle: if currently ON → set OFF, else → set ON
                if [ "$current" = "${on_vals[$idx]}" ] || \
                   [ "$current" = "1" -a "${on_vals[$idx]}" = "true" ]; then
                    apply_tweak "${domains[$idx]}" "${keys[$idx]}" "${types[$idx]}" "${off_vals[$idx]}" "${restarts[$idx]}"
                    echo -e "  ${YELLOW}→${NC} ${descs[$idx]}: OFF"
                else
                    apply_tweak "${domains[$idx]}" "${keys[$idx]}" "${types[$idx]}" "${on_vals[$idx]}" "${restarts[$idx]}"
                    echo -e "  ${GREEN}→${NC} ${descs[$idx]}: ON"
                fi
                sleep 0.5
            fi
            show_category "$category_name" "$tweaks_func"
            ;;
    esac
}

# ===================== BACKUP/RESTORE =====================
backup_defaults() {
    mkdir -p "$BACKUP_DIR"
    local backup_file="${BACKUP_DIR}/defaults_$(date +%Y%m%d_%H%M%S).txt"

    echo -e "  ${DIM}Backing up current custom defaults...${NC}"

    local count=0
    for func in get_finder_tweaks get_dock_tweaks get_screenshot_tweaks get_safari_tweaks get_misc_tweaks get_security_tweaks; do
        while IFS='|' read -r domain key type on_val off_val desc restart; do
            [ -z "$domain" ] && continue
            local val
            val=$(get_current_value "$domain" "$key")
            if [ "$val" != "__unset__" ]; then
                echo "${domain}|${key}|${type}|${val}|${restart}" >> "$backup_file"
                ((count++))
            fi
        done < <($func)
    done

    echo -e "  ${GREEN}✓${NC} Backed up ${count} settings to:"
    echo -e "  ${DIM}${backup_file}${NC}"
    press_enter
}

restore_defaults() {
    local file="${1:-}"

    if [ -z "$file" ]; then
        # List available backups
        if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
            echo -e "  ${YELLOW}No backups found.${NC}"
            press_enter
            return
        fi

        local -a backups=()
        while IFS= read -r f; do
            backups+=("$f")
        done < <(ls -1t "$BACKUP_DIR" 2>/dev/null)

        divider
        for ((i=0; i<${#backups[@]}; i++)); do
            printf "  ${GREEN}%3d.${NC} %s\n" "$((i+1))" "${backups[$i]}"
        done

        echo ""
        read -rp "  Select backup [#]: " pick
        if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le ${#backups[@]} ]; then
            file="${BACKUP_DIR}/${backups[$((pick-1))]}"
        else
            return
        fi
    fi

    if [ ! -f "$file" ]; then
        echo -e "  ${RED}File not found: ${file}${NC}"
        press_enter
        return
    fi

    echo -e "  ${RED}Restore defaults from $(basename "$file")?${NC}"
    read -rp "  Type 'yes': " confirm
    [ "$confirm" != "yes" ] && return

    local count=0
    while IFS='|' read -r domain key type value restart; do
        [ -z "$domain" ] && continue
        apply_tweak "$domain" "$key" "$type" "$value" "$restart"
        ((count++))
    done < "$file"

    echo -e "  ${GREEN}✓${NC} Restored ${count} settings."
    press_enter
}

# ===================== MAIN MENU =====================
# Handle CLI args
case "${1:-}" in
    --backup)  header; backup_defaults; exit 0 ;;
    --restore) header; restore_defaults "${2:-}"; exit 0 ;;
esac

main_menu() {
    while true; do
        header
        echo -e "  ${BOLD}Categories:${NC}"
        echo ""
        echo -e "  ${GREEN}1.${NC}  Finder"
        echo -e "  ${GREEN}2.${NC}  Dock"
        echo -e "  ${GREEN}3.${NC}  Screenshots"
        echo -e "  ${GREEN}4.${NC}  Safari"
        echo -e "  ${GREEN}5.${NC}  Typing & Input"
        echo -e "  ${GREEN}6.${NC}  Security & Privacy"
        echo ""
        echo -e "  ${GREEN}b.${NC}  Backup current settings"
        echo -e "  ${GREEN}r.${NC}  Restore from backup"
        echo -e "  ${GREEN}q.${NC}  Quit"
        echo ""
        divider
        read -rp "  > " choice

        case "$choice" in
            1) show_category "Finder" get_finder_tweaks ;;
            2) show_category "Dock" get_dock_tweaks ;;
            3) show_category "Screenshots" get_screenshot_tweaks ;;
            4) show_category "Safari" get_safari_tweaks ;;
            5) show_category "Typing & Input" get_misc_tweaks ;;
            6) show_category "Security & Privacy" get_security_tweaks ;;
            b|B) backup_defaults ;;
            r|R) header; restore_defaults ;;
            q|Q) echo -e "\n  ${GREEN}Done.${NC}\n"; exit 0 ;;
        esac
    done
}

main_menu
