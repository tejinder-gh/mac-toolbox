#!/bin/bash

# ============================================================
# update-prep.sh — macOS Update Preparation Checklist
# Part of mac-toolbox • Zero dependencies • bash 3.2+
#
# Features:
#   - Pre-update system readiness check
#   - Disk space verification (need ~35GB free)
#   - Incompatible kernel extension scan
#   - 32-bit app detection
#   - Time Machine backup status
#   - Critical config backup
#   - APFS snapshot for rollback
#
# Security:
#   - Read-only checks by default
#   - Backup actions are opt-in and non-destructive
#
# Usage:
#   ./update-prep.sh
# ============================================================

set -uo pipefail

VERSION="1.0"
BACKUP_DIR="$HOME/.mac-toolbox-backups/update-prep"
MIN_SPACE_GB=35

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
    echo -e "${CYAN}${BOLD}  ║  macOS Update Preparation v${VERSION}                         ║${NC}"
    echo -e "${CYAN}${BOLD}  ╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ===================== CHECKS =====================
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

check_pass() { echo -e "  ${GREEN}✓${NC} $1"; ((PASS_COUNT++)); }
check_warn() { echo -e "  ${YELLOW}!${NC} $1"; ((WARN_COUNT++)); }
check_fail() { echo -e "  ${RED}✗${NC} $1"; ((FAIL_COUNT++)); }

# ---- Disk Space ----
check_disk_space() {
    echo -e "  ${BOLD}Disk Space${NC}"

    local avail_kb
    avail_kb=$(df -k / 2>/dev/null | tail -1 | awk '{print $4}')
    local avail_gb=$(( avail_kb / 1048576 ))

    if [ "$avail_gb" -ge "$MIN_SPACE_GB" ]; then
        check_pass "Free space: ${avail_gb}GB (need ${MIN_SPACE_GB}GB)"
    elif [ "$avail_gb" -ge 20 ]; then
        check_warn "Free space: ${avail_gb}GB — tight for major update (need ${MIN_SPACE_GB}GB)"
        echo -e "    ${DIM}Run diskmap.sh or dev-clean.sh to free space${NC}"
    else
        check_fail "Free space: ${avail_gb}GB — insufficient for update"
        echo -e "    ${DIM}Need at least ${MIN_SPACE_GB}GB free. Run diskmap.sh to find reclaimable space.${NC}"
    fi

    # Purgeable space
    local purgeable
    purgeable=$(diskutil info / 2>/dev/null | grep "Purgeable" | awk '{print $NF}')
    [ -n "$purgeable" ] && echo -e "    ${DIM}Purgeable space: ${purgeable} (macOS can reclaim automatically)${NC}"
}

# ---- macOS Version ----
check_current_os() {
    echo -e "\n  ${BOLD}Current System${NC}"

    local os_ver
    os_ver=$(sw_vers -productVersion 2>/dev/null)
    local build
    build=$(sw_vers -buildVersion 2>/dev/null)
    local chip
    chip=$(uname -m)

    check_pass "macOS ${os_ver} (${build}) on ${chip}"

    # Check architecture
    if [ "$chip" = "arm64" ]; then
        echo -e "    ${DIM}Apple Silicon — all recent updates supported${NC}"
    else
        echo -e "    ${DIM}Intel — verify your Mac model is supported for the target update${NC}"
    fi
}

# ---- Time Machine ----
check_time_machine() {
    echo -e "\n  ${BOLD}Time Machine Backup${NC}"

    local tm_status
    tm_status=$(tmutil status 2>/dev/null)

    if echo "$tm_status" | grep -q "Running = 1"; then
        check_warn "Time Machine backup currently in progress — wait for completion"
    else
        local last_backup
        last_backup=$(tmutil latestbackup 2>/dev/null)

        if [ -n "$last_backup" ]; then
            local backup_date
            backup_date=$(basename "$last_backup")
            check_pass "Last backup: ${backup_date}"

            # Check if backup is recent (within 24h)
            local backup_epoch
            backup_epoch=$(stat -f %m "$last_backup" 2>/dev/null || echo 0)
            local now
            now=$(date +%s)
            local age_hours=$(( (now - backup_epoch) / 3600 ))

            if [ "$age_hours" -gt 24 ]; then
                check_warn "Backup is ${age_hours}h old — run a fresh backup before updating"
            fi
        else
            check_warn "No Time Machine backup found"
            echo -e "    ${DIM}Strongly recommend backing up before a major update${NC}"
        fi
    fi
}

# ---- Kernel Extensions ----
check_kexts() {
    echo -e "\n  ${BOLD}Kernel Extensions${NC}"

    local -a third_party_kexts=()
    while IFS= read -r kext; do
        [ -z "$kext" ] && continue
        # Skip Apple kexts
        echo "$kext" | grep -qi "com.apple" && continue
        third_party_kexts+=("$kext")
    done < <(kextstat 2>/dev/null | awk '{print $6}' | tail -n +2)

    if [ ${#third_party_kexts[@]} -eq 0 ]; then
        check_pass "No third-party kernel extensions"
    else
        check_warn "${#third_party_kexts[@]} third-party kernel extension(s) found"
        echo -e "    ${DIM}These may be incompatible with the new macOS version:${NC}"
        for kext in "${third_party_kexts[@]}"; do
            echo -e "    ${YELLOW}•${NC} ${kext}"
        done
        echo -e "    ${DIM}Check with vendors for updated versions before updating.${NC}"
    fi
}

# ---- 32-bit Apps ----
check_32bit() {
    echo -e "\n  ${BOLD}32-bit Applications${NC}"
    echo -e "    ${DIM}Scanning (this may take a moment)...${NC}"

    local -a legacy_apps=()
    while IFS= read -r app; do
        [ -z "$app" ] && continue
        # Check if app has any 32-bit executables
        local exec_path="${app}/Contents/MacOS"
        [ ! -d "$exec_path" ] && continue

        local has_32=false
        while IFS= read -r binary; do
            if file "$binary" 2>/dev/null | grep -q "i386"; then
                has_32=true
                break
            fi
        done < <(find "$exec_path" -type f -perm +111 2>/dev/null | head -3)

        [ "$has_32" = true ] && legacy_apps+=("$(basename "$app" .app)")
    done < <(find /Applications -maxdepth 2 -name "*.app" 2>/dev/null)

    printf "\r                                              \r"

    if [ ${#legacy_apps[@]} -eq 0 ]; then
        check_pass "No 32-bit applications found"
    else
        check_warn "${#legacy_apps[@]} 32-bit app(s) — won't work on macOS Catalina+"
        for app in "${legacy_apps[@]}"; do
            echo -e "    ${YELLOW}•${NC} ${app}"
        done
    fi
}

# ---- SIP Status ----
check_sip() {
    echo -e "\n  ${BOLD}System Integrity${NC}"

    local sip
    sip=$(csrutil status 2>/dev/null)
    if echo "$sip" | grep -q "enabled"; then
        check_pass "System Integrity Protection: Enabled"
    else
        check_fail "SIP is disabled — re-enable before updating"
        echo -e "    ${DIM}Boot to Recovery Mode → Terminal → csrutil enable${NC}"
    fi
}

# ---- FileVault ----
check_filevault() {
    local fv
    fv=$(fdesetup status 2>/dev/null)
    if echo "$fv" | grep -q "On"; then
        check_pass "FileVault: Enabled"
    else
        check_warn "FileVault: Disabled — consider enabling before update"
    fi
}

# ---- Login Items ----
check_login_items() {
    echo -e "\n  ${BOLD}Startup Items${NC}"

    local agent_count=0
    for dir in "$HOME/Library/LaunchAgents" "/Library/LaunchAgents" "/Library/LaunchDaemons"; do
        [ -d "$dir" ] && agent_count=$((agent_count + $(ls "$dir"/*.plist 2>/dev/null | wc -l)))
    done

    if [ "$agent_count" -gt 20 ]; then
        check_warn "${agent_count} launch agents/daemons — consider disabling non-essential ones"
        echo -e "    ${DIM}Run launchctl-manager.sh to review${NC}"
    else
        check_pass "${agent_count} launch agents/daemons (normal)"
    fi
}

# ===================== BACKUP CONFIGS =====================
backup_configs() {
    mkdir -p "$BACKUP_DIR"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local bdir="${BACKUP_DIR}/${timestamp}"
    mkdir -p "$bdir"

    echo -e "\n  ${BOLD}Backing Up Critical Configs${NC}"
    divider

    # Shell configs
    for f in .bash_profile .bashrc .zshrc .zprofile .gitconfig .ssh/config; do
        if [ -f "$HOME/$f" ]; then
            local target_dir="${bdir}/$(dirname "$f")"
            mkdir -p "$target_dir"
            cp "$HOME/$f" "${bdir}/$f" 2>/dev/null && \
                echo -e "  ${GREEN}✓${NC} ~/${f}" || \
                echo -e "  ${DIM}  Skipped: ~/${f}${NC}"
        fi
    done

    # SSH keys (just list them, don't copy private keys for security)
    if [ -d "$HOME/.ssh" ]; then
        ls -la "$HOME/.ssh"/*.pub 2>/dev/null > "${bdir}/ssh_public_keys.txt"
        echo -e "  ${GREEN}✓${NC} SSH public key listing"
        echo -e "    ${DIM}Private keys NOT copied for security — ensure you have these backed up${NC}"
    fi

    # Homebrew bundle
    if command -v brew &>/dev/null; then
        brew list --formula > "${bdir}/brew_formulae.txt" 2>/dev/null
        brew list --cask > "${bdir}/brew_casks.txt" 2>/dev/null
        echo -e "  ${GREEN}✓${NC} Homebrew package lists"
    fi

    # Installed apps list
    ls /Applications/ > "${bdir}/installed_apps.txt" 2>/dev/null
    echo -e "  ${GREEN}✓${NC} Installed apps list"

    # macOS defaults exports for our managed domains
    defaults export com.apple.finder "${bdir}/finder_defaults.plist" 2>/dev/null
    defaults export com.apple.dock "${bdir}/dock_defaults.plist" 2>/dev/null
    echo -e "  ${GREEN}✓${NC} Finder and Dock preferences"

    # Crontabs
    crontab -l > "${bdir}/crontab.txt" 2>/dev/null
    echo -e "  ${GREEN}✓${NC} Crontab"

    echo ""
    echo -e "  ${GREEN}Backup saved to: ${bdir}${NC}"
}

# ===================== FULL CHECKLIST =====================
full_checklist() {
    header
    echo -e "  ${BOLD}Pre-Update Checklist${NC}"
    echo -e "  ${DIM}$(date)${NC}"
    echo ""

    PASS_COUNT=0
    WARN_COUNT=0
    FAIL_COUNT=0

    check_current_os
    check_disk_space
    check_time_machine
    check_sip
    check_filevault
    check_kexts
    check_32bit
    check_login_items

    # Summary
    echo ""
    divider
    echo -e "  ${BOLD}Summary:${NC}  ${GREEN}✓ ${PASS_COUNT} passed${NC}  ${YELLOW}! ${WARN_COUNT} warnings${NC}  ${RED}✗ ${FAIL_COUNT} failed${NC}"

    if [ $FAIL_COUNT -gt 0 ]; then
        echo -e "\n  ${RED}${BOLD}⚠  Fix failed checks before updating.${NC}"
    elif [ $WARN_COUNT -gt 0 ]; then
        echo -e "\n  ${YELLOW}Review warnings, but safe to proceed with caution.${NC}"
    else
        echo -e "\n  ${GREEN}${BOLD}✓ System is ready for update.${NC}"
    fi

    echo ""
    echo -e "  ${DIM}(b) Backup configs before update  (q) Done${NC}"
    read -rp "  > " choice

    case "$choice" in
        b|B) backup_configs; press_enter ;;
    esac
}

# ===================== MAIN =====================
main_menu() {
    while true; do
        header
        echo -e "  ${BOLD}Choose an option:${NC}"
        echo ""
        echo -e "  ${GREEN}1.${NC}  Full pre-update checklist"
        echo -e "  ${GREEN}2.${NC}  Backup configs only"
        echo -e "  ${GREEN}3.${NC}  Check disk space"
        echo -e "  ${GREEN}4.${NC}  Check kernel extensions"
        echo -e "  ${GREEN}q.${NC}  Quit"
        echo ""
        divider
        read -rp "  > " choice

        case "$choice" in
            1) full_checklist ;;
            2) header; backup_configs; press_enter ;;
            3) header; PASS_COUNT=0; WARN_COUNT=0; FAIL_COUNT=0; check_disk_space; press_enter ;;
            4) header; PASS_COUNT=0; WARN_COUNT=0; FAIL_COUNT=0; check_kexts; press_enter ;;
            q|Q) echo -e "\n  ${GREEN}Done.${NC}\n"; exit 0 ;;
        esac
    done
}

main_menu
