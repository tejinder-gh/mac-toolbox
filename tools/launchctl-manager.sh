#!/bin/bash

# ============================================================
# launchctl-manager.sh — Startup & Background Process Manager
# Part of mac-toolbox • Zero dependencies • bash 3.2+
#
# Features:
#   - Lists ALL launch agents & daemons (user + system)
#   - Shows status, owning app, and load state
#   - Disable/enable/remove agents interactively
#   - Safety classification (system/apple vs third-party)
#   - Dry-run mode
#
# Security:
#   - Never modifies Apple/system agents without explicit override
#   - Backup plist before removal
#   - Disable = unload only (plist preserved, reversible)
#
# Usage:
#   ./launchctl-manager.sh [--dry-run]
# ============================================================

set -uo pipefail

DRY_RUN=false
VERSION="1.0"
BACKUP_DIR="$HOME/.mac-toolbox-backups/launchagents"

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

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
    echo -e "${CYAN}${BOLD}  ║  Startup & Background Process Manager v${VERSION}            ║${NC}"
    if [ "$DRY_RUN" = true ]; then
    echo -e "${CYAN}${BOLD}  ║  ${YELLOW}DRY-RUN MODE${CYAN}${BOLD}                                          ║${NC}"
    fi
    echo -e "${CYAN}${BOLD}  ╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ===================== AGENT DISCOVERY =====================
# Returns: label|path|type|status|owner
discover_agents() {
    local scan_dirs=(
        "$HOME/Library/LaunchAgents|user-agent"
        "/Library/LaunchAgents|system-agent"
        "/Library/LaunchDaemons|system-daemon"
    )

    for entry in "${scan_dirs[@]}"; do
        local dir="${entry%%|*}"
        local type="${entry##*|}"

        [ ! -d "$dir" ] && continue

        for plist in "$dir"/*.plist; do
            [ ! -f "$plist" ] && continue

            local label=""
            label=$(/usr/libexec/PlistBuddy -c "Print :Label" "$plist" 2>/dev/null || basename "$plist" .plist)

            # Determine owner
            local owner="unknown"
            local lower_label
            lower_label=$(echo "$label" | tr '[:upper:]' '[:lower:]')

            if [[ "$lower_label" == com.apple.* ]] || [[ "$lower_label" == com.apple* ]]; then
                owner="apple"
            elif [[ "$lower_label" == *"google"* ]]; then
                owner="Google"
            elif [[ "$lower_label" == *"microsoft"* ]] || [[ "$lower_label" == *"office"* ]]; then
                owner="Microsoft"
            elif [[ "$lower_label" == *"adobe"* ]]; then
                owner="Adobe"
            elif [[ "$lower_label" == *"spotify"* ]]; then
                owner="Spotify"
            elif [[ "$lower_label" == *"dropbox"* ]]; then
                owner="Dropbox"
            elif [[ "$lower_label" == *"slack"* ]]; then
                owner="Slack"
            elif [[ "$lower_label" == *"zoom"* ]]; then
                owner="Zoom"
            elif [[ "$lower_label" == *"docker"* ]]; then
                owner="Docker"
            elif [[ "$lower_label" == *"jetbrains"* ]]; then
                owner="JetBrains"
            elif [[ "$lower_label" == *"brew"* ]] || [[ "$lower_label" == *"homebrew"* ]]; then
                owner="Homebrew"
            else
                # Try to extract developer name from reverse-DNS
                local second_seg
                second_seg=$(echo "$label" | awk -F. '{print $2}')
                [ -n "$second_seg" ] && owner="$second_seg"
            fi

            # Check if loaded
            local status="unloaded"
            if launchctl list 2>/dev/null | grep -q "$label"; then
                status="loaded"
            fi

            echo "${label}|${plist}|${type}|${status}|${owner}"
        done
    done
}

# ===================== DISPLAY AGENTS =====================
list_agents() {
    local filter="${1:-all}"  # all, user, system, loaded, third-party

    header
    echo -e "  ${BOLD}Launch Agents & Daemons${NC} ${DIM}(filter: ${filter})${NC}"
    echo -e "  ${DIM}Scanning...${NC}"

    local -a labels=()
    local -a paths=()
    local -a types=()
    local -a statuses=()
    local -a owners=()

    while IFS='|' read -r label path type status owner; do
        # Apply filter
        case "$filter" in
            user)        [[ "$type" != "user-agent" ]] && continue ;;
            system)      [[ "$type" == "user-agent" ]] && continue ;;
            loaded)      [[ "$status" != "loaded" ]] && continue ;;
            third-party) [[ "$owner" == "apple" ]] && continue ;;
        esac

        labels+=("$label")
        paths+=("$path")
        types+=("$type")
        statuses+=("$status")
        owners+=("$owner")
    done < <(discover_agents | sort -t'|' -k5,5 -k1,1)

    local total=${#labels[@]}

    if [ "$total" -eq 0 ]; then
        echo -e "  ${YELLOW}No agents found matching filter.${NC}"
        press_enter
        return
    fi

    header
    echo -e "  ${BOLD}Launch Agents & Daemons${NC} ${DIM}(${total} items, filter: ${filter})${NC}"
    divider

    for ((i=0; i<total; i++)); do
        local status_icon
        if [ "${statuses[$i]}" = "loaded" ]; then
            status_icon="${GREEN}●${NC}"
        else
            status_icon="${RED}○${NC}"
        fi

        local type_label
        case "${types[$i]}" in
            user-agent)    type_label="${DIM}user ${NC}" ;;
            system-agent)  type_label="${YELLOW}sys  ${NC}" ;;
            system-daemon) type_label="${RED}daemon${NC}" ;;
        esac

        local owner_display="${owners[$i]}"
        if [ "$owner_display" = "apple" ]; then
            owner_display="${DIM}Apple${NC}"
        fi

        printf "  %b ${GREEN}%3d.${NC} %-38s %b  %b\n" \
            "$status_icon" "$((i+1))" "${labels[$i]}" "$type_label" "$owner_display"
    done

    echo ""
    divider
    echo -e "  ${DIM}[#] Manage  [f] Filter  [q] Back${NC}"
    read -rp "  > " input

    case "$input" in
        q|Q) return ;;
        f|F)
            echo -e "  ${DIM}Filters: (a)ll (u)ser (s)ystem (l)oaded (t)hird-party${NC}"
            read -rp "  > " f
            case "$f" in
                a) list_agents "all" ;;
                u) list_agents "user" ;;
                s) list_agents "system" ;;
                l) list_agents "loaded" ;;
                t) list_agents "third-party" ;;
            esac
            ;;
        *)
            if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le "$total" ]; then
                manage_agent "${labels[$((input-1))]}" \
                             "${paths[$((input-1))]}" \
                             "${types[$((input-1))]}" \
                             "${statuses[$((input-1))]}" \
                             "${owners[$((input-1))]}"
                list_agents "$filter"
            fi
            ;;
    esac
}

# ===================== MANAGE SINGLE AGENT =====================
manage_agent() {
    local label="$1"
    local path="$2"
    local type="$3"
    local status="$4"
    local owner="$5"

    header
    echo -e "  ${BOLD}Agent Details${NC}"
    divider
    echo -e "  ${CYAN}Label:${NC}   $label"
    echo -e "  ${CYAN}Path:${NC}    $path"
    echo -e "  ${CYAN}Type:${NC}    $type"
    echo -e "  ${CYAN}Status:${NC}  $status"
    echo -e "  ${CYAN}Owner:${NC}   $owner"

    # Show plist contents (sanitized)
    echo ""
    echo -e "  ${BOLD}Configuration:${NC}"
    local program=""
    program=$(/usr/libexec/PlistBuddy -c "Print :Program" "$path" 2>/dev/null || \
              /usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$path" 2>/dev/null || \
              echo "unknown")
    local run_at_load=""
    run_at_load=$(/usr/libexec/PlistBuddy -c "Print :RunAtLoad" "$path" 2>/dev/null || echo "false")
    local keep_alive=""
    keep_alive=$(/usr/libexec/PlistBuddy -c "Print :KeepAlive" "$path" 2>/dev/null || echo "false")

    echo -e "  ${DIM}Program:${NC}      $program"
    echo -e "  ${DIM}RunAtLoad:${NC}    $run_at_load"
    echo -e "  ${DIM}KeepAlive:${NC}    $keep_alive"

    # Safety check
    echo ""
    if [ "$owner" = "apple" ]; then
        echo -e "  ${RED}${BOLD}⚠  This is an Apple system agent.${NC}"
        echo -e "  ${RED}  Modifying it may cause system instability.${NC}"
    fi

    echo ""
    divider

    if [ "$status" = "loaded" ]; then
        echo -e "  ${DIM}(d) Disable (unload)  (r) Remove  (q) Back${NC}"
    else
        echo -e "  ${DIM}(e) Enable (load)  (r) Remove  (q) Back${NC}"
    fi
    read -rp "  > " action

    case "$action" in
        d|D)
            if [ "$owner" = "apple" ]; then
                echo -e "\n  ${RED}Are you SURE you want to disable an Apple agent?${NC}"
                read -rp "  Type 'yes-apple': " confirm
                [ "$confirm" != "yes-apple" ] && return
            fi

            if [ "$DRY_RUN" = true ]; then
                echo -e "  ${YELLOW}[DRY]${NC} Would unload: $label"
            else
                if [[ "$type" == *"daemon"* ]]; then
                    sudo launchctl unload -w "$path" 2>/dev/null && \
                        echo -e "  ${GREEN}✓${NC} Disabled: $label" || \
                        echo -e "  ${RED}✗${NC} Failed to disable"
                else
                    launchctl unload -w "$path" 2>/dev/null && \
                        echo -e "  ${GREEN}✓${NC} Disabled: $label" || \
                        echo -e "  ${RED}✗${NC} Failed to disable"
                fi
            fi
            press_enter
            ;;
        e|E)
            if [ "$DRY_RUN" = true ]; then
                echo -e "  ${YELLOW}[DRY]${NC} Would load: $label"
            else
                if [[ "$type" == *"daemon"* ]]; then
                    sudo launchctl load -w "$path" 2>/dev/null && \
                        echo -e "  ${GREEN}✓${NC} Enabled: $label" || \
                        echo -e "  ${RED}✗${NC} Failed to enable"
                else
                    launchctl load -w "$path" 2>/dev/null && \
                        echo -e "  ${GREEN}✓${NC} Enabled: $label" || \
                        echo -e "  ${RED}✗${NC} Failed to enable"
                fi
            fi
            press_enter
            ;;
        r|R)
            if [ "$owner" = "apple" ]; then
                echo -e "\n  ${RED}Cannot remove Apple system agents.${NC}"
                press_enter
                return
            fi

            echo -e "\n  ${RED}Remove this agent permanently?${NC}"
            echo -e "  ${DIM}(A backup will be saved to ${BACKUP_DIR})${NC}"
            read -rp "  Type 'yes': " confirm

            if [ "$confirm" = "yes" ]; then
                # Backup first
                mkdir -p "$BACKUP_DIR"
                local backup_name
                backup_name="$(basename "$path")_$(date +%Y%m%d_%H%M%S)"

                if [ "$DRY_RUN" = true ]; then
                    echo -e "  ${YELLOW}[DRY]${NC} Would backup to: ${BACKUP_DIR}/${backup_name}"
                    echo -e "  ${YELLOW}[DRY]${NC} Would unload and remove: $path"
                else
                    cp "$path" "${BACKUP_DIR}/${backup_name}" 2>/dev/null && \
                        echo -e "  ${GREEN}✓${NC} Backed up to: ${BACKUP_DIR}/${backup_name}"

                    # Unload first
                    if [[ "$type" == *"daemon"* ]]; then
                        sudo launchctl unload "$path" 2>/dev/null
                        sudo rm -f "$path" 2>/dev/null
                    else
                        launchctl unload "$path" 2>/dev/null
                        rm -f "$path" 2>/dev/null
                    fi

                    if [ ! -f "$path" ]; then
                        echo -e "  ${GREEN}✓${NC} Removed: $label"
                    else
                        echo -e "  ${RED}✗${NC} Failed to remove"
                    fi
                fi
            fi
            press_enter
            ;;
        *) ;;
    esac
}

# ===================== RESTORE BACKUPS =====================
restore_backups() {
    header
    echo -e "  ${BOLD}Restore Backed-Up Agents${NC}"

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        echo -e "  ${YELLOW}No backups found in ${BACKUP_DIR}${NC}"
        press_enter
        return
    fi

    local -a backups=()
    while IFS= read -r f; do
        backups+=("$f")
    done < <(ls -1 "$BACKUP_DIR" 2>/dev/null)

    divider
    for ((i=0; i<${#backups[@]}; i++)); do
        printf "  ${GREEN}%3d.${NC} %s\n" "$((i+1))" "${backups[$i]}"
    done

    echo ""
    echo -e "  ${DIM}[#] Restore  [q] Back${NC}"
    read -rp "  > " pick

    if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le ${#backups[@]} ]; then
        local backup_file="${BACKUP_DIR}/${backups[$((pick-1))]}"
        # Strip timestamp suffix to get original name
        local original_name
        original_name=$(echo "${backups[$((pick-1))]}" | sed 's/_[0-9]*_[0-9]*$//')

        echo -e "  ${CYAN}Restore to:${NC}"
        echo -e "  1. ~/Library/LaunchAgents/"
        echo -e "  2. /Library/LaunchAgents/"
        echo -e "  3. /Library/LaunchDaemons/"
        read -rp "  > " dest_choice

        local dest_dir
        case "$dest_choice" in
            1) dest_dir="$HOME/Library/LaunchAgents" ;;
            2) dest_dir="/Library/LaunchAgents" ;;
            3) dest_dir="/Library/LaunchDaemons" ;;
            *) echo -e "  ${YELLOW}Cancelled.${NC}"; press_enter; return ;;
        esac

        if [ "$DRY_RUN" = true ]; then
            echo -e "  ${YELLOW}[DRY]${NC} Would restore: ${original_name} → ${dest_dir}/"
        else
            if cp "$backup_file" "${dest_dir}/${original_name}" 2>/dev/null || \
               sudo cp "$backup_file" "${dest_dir}/${original_name}" 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} Restored: ${original_name}"
                echo -e "  ${DIM}Run 'launchctl load ${dest_dir}/${original_name}' to activate${NC}"
            else
                echo -e "  ${RED}✗${NC} Failed to restore"
            fi
        fi
    fi

    press_enter
}

# ===================== MAIN MENU =====================
main_menu() {
    while true; do
        header
        echo -e "  ${BOLD}Choose an option:${NC}"
        echo ""
        echo -e "  ${GREEN}1.${NC}  List all agents & daemons"
        echo -e "  ${GREEN}2.${NC}  Show third-party only"
        echo -e "  ${GREEN}3.${NC}  Show currently loaded"
        echo -e "  ${GREEN}4.${NC}  Restore backed-up agents"
        echo -e "  ${GREEN}q.${NC}  Quit"
        echo ""
        if [ "$DRY_RUN" = true ]; then
            echo -e "  ${YELLOW}${BOLD}⚠  DRY-RUN active${NC}"
            echo ""
        fi
        divider
        read -rp "  > " choice

        case "$choice" in
            1) list_agents "all" ;;
            2) list_agents "third-party" ;;
            3) list_agents "loaded" ;;
            4) restore_backups ;;
            q|Q) echo -e "\n  ${GREEN}Done.${NC}\n"; exit 0 ;;
        esac
    done
}

main_menu
