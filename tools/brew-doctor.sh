#!/bin/bash

# ============================================================
# brew-doctor.sh — Homebrew Hygiene Tool
# Part of mac-toolbox • bash 3.2+
#
# Features:
#   - Detect orphaned formulae (installed but unused)
#   - Find outdated casks and formulae
#   - Measure and clean Homebrew cache
#   - Find cask apps deleted outside Homebrew
#   - Broken symlink detection
#   - Dry-run mode
#
# Requires: Homebrew (exits gracefully if not installed)
#
# Usage:
#   ./brew-doctor.sh [--dry-run]
# ============================================================

set -uo pipefail

DRY_RUN=false
VERSION="1.0"

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

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
    echo -e "${CYAN}${BOLD}  ║  Brew Hygiene Tool v${VERSION}                                ║${NC}"
    if [ "$DRY_RUN" = true ]; then
    echo -e "${CYAN}${BOLD}  ║  ${YELLOW}DRY-RUN MODE${CYAN}${BOLD}                                          ║${NC}"
    fi
    echo -e "${CYAN}${BOLD}  ╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

human_size() {
    local kb="$1"
    if [ "$kb" -ge 1048576 ]; then
        awk "BEGIN {printf \"%.1f GB\", $kb/1048576}"
    elif [ "$kb" -ge 1024 ]; then
        awk "BEGIN {printf \"%.1f MB\", $kb/1024}"
    else
        echo "${kb} KB"
    fi
}

# ===================== PREFLIGHT =====================
check_brew() {
    if ! command -v brew &>/dev/null; then
        echo -e "  ${RED}Homebrew is not installed.${NC}"
        echo -e "  ${DIM}Install: https://brew.sh${NC}"
        exit 1
    fi
}

# ===================== SCAN: CACHE SIZE =====================
scan_cache() {
    echo -e "  ${CYAN}Cache Analysis${NC}"

    local cache_dir
    cache_dir=$(brew --cache 2>/dev/null)

    if [ -d "$cache_dir" ]; then
        local cache_kb
        cache_kb=$(du -sk "$cache_dir" 2>/dev/null | cut -f1)
        echo -e "  Cache location: ${DIM}${cache_dir}${NC}"
        echo -e "  Cache size:     ${YELLOW}$(human_size $cache_kb)${NC}"

        local download_count
        download_count=$(find "$cache_dir" -type f 2>/dev/null | wc -l | tr -d ' ')
        echo -e "  Cached files:   ${download_count}"
    else
        echo -e "  ${DIM}No cache directory found.${NC}"
    fi

    # Homebrew logs
    local log_dir="$HOME/Library/Logs/Homebrew"
    if [ -d "$log_dir" ]; then
        local log_kb
        log_kb=$(du -sk "$log_dir" 2>/dev/null | cut -f1)
        echo -e "  Logs size:      $(human_size $log_kb)"
    fi
}

# ===================== SCAN: ORPHANED FORMULAE =====================
scan_orphans() {
    echo -e "\n  ${CYAN}Orphaned Formulae${NC}"
    echo -e "  ${DIM}(Installed but not required by any other formula)${NC}"

    local -a orphans=()
    while IFS= read -r pkg; do
        [ -n "$pkg" ] && orphans+=("$pkg")
    done < <(brew autoremove --dry-run 2>/dev/null | grep "Would remove" | sed 's/Would remove: //')

    # Fallback: use leaves minus cask dependencies
    if [ ${#orphans[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✓ No orphaned formulae detected.${NC}"
    else
        for orphan in "${orphans[@]}"; do
            echo -e "  ${YELLOW}•${NC} $orphan"
        done
        echo -e "  ${DIM}Total: ${#orphans[@]} orphaned formulae${NC}"
    fi
}

# ===================== SCAN: OUTDATED =====================
scan_outdated() {
    echo -e "\n  ${CYAN}Outdated Packages${NC}"

    local -a outdated_formulae=()
    while IFS= read -r line; do
        [ -n "$line" ] && outdated_formulae+=("$line")
    done < <(brew outdated --formula 2>/dev/null)

    local -a outdated_casks=()
    while IFS= read -r line; do
        [ -n "$line" ] && outdated_casks+=("$line")
    done < <(brew outdated --cask --greedy 2>/dev/null)

    if [ ${#outdated_formulae[@]} -eq 0 ] && [ ${#outdated_casks[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✓ Everything is up to date.${NC}"
    else
        if [ ${#outdated_formulae[@]} -gt 0 ]; then
            echo -e "  ${BOLD}Formulae (${#outdated_formulae[@]}):${NC}"
            for f in "${outdated_formulae[@]}"; do
                echo -e "    ${YELLOW}•${NC} $f"
            done
        fi
        if [ ${#outdated_casks[@]} -gt 0 ]; then
            echo -e "  ${BOLD}Casks (${#outdated_casks[@]}):${NC}"
            for c in "${outdated_casks[@]}"; do
                echo -e "    ${YELLOW}•${NC} $c"
            done
        fi
    fi
}

# ===================== SCAN: GHOST CASKS =====================
# Cask apps that were manually deleted but not `brew uninstall`ed
scan_ghost_casks() {
    echo -e "\n  ${CYAN}Ghost Casks${NC}"
    echo -e "  ${DIM}(Apps deleted from /Applications but still registered in Homebrew)${NC}"

    local -a ghosts=()

    while IFS= read -r cask; do
        [ -z "$cask" ] && continue

        # Get the app name from cask info
        local app_path=""
        app_path=$(brew info --cask "$cask" 2>/dev/null | grep -o '/Applications/[^(]*\.app' | head -1)

        if [ -n "$app_path" ] && [ ! -d "$app_path" ]; then
            ghosts+=("${cask}|${app_path}")
        fi
    done < <(brew list --cask 2>/dev/null)

    if [ ${#ghosts[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✓ No ghost casks found.${NC}"
    else
        for g in "${ghosts[@]}"; do
            local cask_name="${g%%|*}"
            local app="${g##*|}"
            echo -e "  ${YELLOW}•${NC} ${cask_name} ${DIM}(${app} missing)${NC}"
        done
        echo -e "  ${DIM}Total: ${#ghosts[@]} ghost casks${NC}"
    fi
}

# ===================== SCAN: BROKEN SYMLINKS =====================
scan_broken_links() {
    echo -e "\n  ${CYAN}Broken Symlinks${NC}"

    local brew_prefix
    brew_prefix=$(brew --prefix 2>/dev/null)
    local -a broken=()

    while IFS= read -r link; do
        [ -n "$link" ] && broken+=("$link")
    done < <(find "${brew_prefix}/bin" "${brew_prefix}/lib" -type l ! -exec test -e {} \; -print 2>/dev/null)

    if [ ${#broken[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✓ No broken symlinks.${NC}"
    else
        for b in "${broken[@]}"; do
            echo -e "  ${RED}•${NC} $b"
        done
        echo -e "  ${DIM}Total: ${#broken[@]} broken links${NC}"
    fi
}

# ===================== FULL REPORT =====================
full_report() {
    header
    echo -e "  ${BOLD}Homebrew Health Report${NC}"
    divider

    # Brew version info
    local brew_ver
    brew_ver=$(brew --version 2>/dev/null | head -1)
    local formula_count
    formula_count=$(brew list --formula 2>/dev/null | wc -l | tr -d ' ')
    local cask_count
    cask_count=$(brew list --cask 2>/dev/null | wc -l | tr -d ' ')

    echo -e "  ${DIM}${brew_ver}${NC}"
    echo -e "  Formulae: ${formula_count}  Casks: ${cask_count}"
    echo ""

    scan_cache
    scan_orphans
    scan_outdated
    scan_ghost_casks
    scan_broken_links

    echo ""
    divider
}

# ===================== CLEANUP =====================
run_cleanup() {
    header
    echo -e "  ${BOLD}Homebrew Cleanup${NC}"
    divider
    echo ""
    echo -e "  This will:"
    echo -e "  ${GREEN}•${NC} Remove old versions of installed formulae"
    echo -e "  ${GREEN}•${NC} Clear the download cache"
    echo -e "  ${GREEN}•${NC} Remove orphaned dependencies"
    echo -e "  ${GREEN}•${NC} Clean stale lock files"
    echo ""

    # Estimate savings
    local cache_dir
    cache_dir=$(brew --cache 2>/dev/null)
    local cache_kb=0
    [ -d "$cache_dir" ] && cache_kb=$(du -sk "$cache_dir" 2>/dev/null | cut -f1)

    echo -e "  ${BOLD}Estimated savings: ${YELLOW}$(human_size $cache_kb)${NC} (cache alone)"
    echo ""
    read -rp "  Proceed? (y/n): " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if [ "$DRY_RUN" = true ]; then
            echo -e "\n  ${YELLOW}[DRY-RUN] Would execute:${NC}"
            echo -e "  ${DIM}brew cleanup --prune=all${NC}"
            echo -e "  ${DIM}brew autoremove${NC}"
        else
            echo ""
            echo -e "  ${DIM}Running brew cleanup...${NC}"
            brew cleanup --prune=all 2>&1 | while IFS= read -r line; do
                echo -e "  ${DIM}${line}${NC}"
            done

            echo -e "\n  ${DIM}Running brew autoremove...${NC}"
            brew autoremove 2>&1 | while IFS= read -r line; do
                echo -e "  ${DIM}${line}${NC}"
            done

            echo -e "\n  ${GREEN}✓ Cleanup complete.${NC}"

            # Show new cache size
            [ -d "$cache_dir" ] && {
                local new_kb
                new_kb=$(du -sk "$cache_dir" 2>/dev/null | cut -f1)
                echo -e "  Cache after cleanup: $(human_size $new_kb)"
            }
        fi
    else
        echo -e "  ${YELLOW}Cancelled.${NC}"
    fi

    press_enter
}

# ===================== UNINSTALL GHOSTS =====================
uninstall_ghosts() {
    header
    echo -e "  ${BOLD}Uninstall Ghost Casks${NC}"
    divider

    local -a ghosts=()
    local -a ghost_names=()

    while IFS= read -r cask; do
        [ -z "$cask" ] && continue
        local app_path=""
        app_path=$(brew info --cask "$cask" 2>/dev/null | grep -o '/Applications/[^(]*\.app' | head -1)
        if [ -n "$app_path" ] && [ ! -d "$app_path" ]; then
            ghosts+=("${cask}|${app_path}")
            ghost_names+=("$cask")
        fi
    done < <(brew list --cask 2>/dev/null)

    if [ ${#ghosts[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✓ No ghost casks.${NC}"
        press_enter
        return
    fi

    for ((i=0; i<${#ghosts[@]}; i++)); do
        local name="${ghosts[$i]%%|*}"
        local path="${ghosts[$i]##*|}"
        printf "  ${GREEN}%3d.${NC} %-30s ${DIM}(%s)${NC}\n" "$((i+1))" "$name" "$path"
    done

    echo ""
    echo -e "  ${DIM}(a) Uninstall all  (s) Select  (n) Cancel${NC}"
    read -rp "  > " choice

    case "$choice" in
        a|A)
            for name in "${ghost_names[@]}"; do
                if [ "$DRY_RUN" = true ]; then
                    echo -e "  ${YELLOW}[DRY]${NC} Would: brew uninstall --cask $name"
                else
                    brew uninstall --cask "$name" 2>/dev/null && \
                        echo -e "  ${GREEN}✓${NC} Uninstalled: $name" || \
                        echo -e "  ${RED}✗${NC} Failed: $name"
                fi
            done
            ;;
        s|S)
            echo -e "  ${CYAN}Enter numbers (e.g., 1 3):${NC}"
            read -rp "  > " selections
            for num in $selections; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#ghost_names[@]} ]; then
                    local name="${ghost_names[$((num-1))]}"
                    if [ "$DRY_RUN" = true ]; then
                        echo -e "  ${YELLOW}[DRY]${NC} Would: brew uninstall --cask $name"
                    else
                        brew uninstall --cask "$name" 2>/dev/null && \
                            echo -e "  ${GREEN}✓${NC} Uninstalled: $name" || \
                            echo -e "  ${RED}✗${NC} Failed: $name"
                    fi
                fi
            done
            ;;
    esac

    press_enter
}

# ===================== MAIN =====================
check_brew

main_menu() {
    while true; do
        header
        echo -e "  ${BOLD}Choose an option:${NC}"
        echo ""
        echo -e "  ${GREEN}1.${NC}  Full health report"
        echo -e "  ${GREEN}2.${NC}  Run cleanup (cache + orphans)"
        echo -e "  ${GREEN}3.${NC}  Uninstall ghost casks"
        echo -e "  ${GREEN}4.${NC}  Update all packages"
        echo -e "  ${GREEN}q.${NC}  Quit"
        echo ""
        divider
        read -rp "  > " choice

        case "$choice" in
            1) full_report; press_enter ;;
            2) run_cleanup ;;
            3) uninstall_ghosts ;;
            4)
                if [ "$DRY_RUN" = true ]; then
                    echo -e "  ${YELLOW}[DRY]${NC} Would run: brew update && brew upgrade"
                else
                    brew update && brew upgrade && brew upgrade --cask --greedy
                fi
                press_enter
                ;;
            q|Q) echo -e "\n  ${GREEN}Done.${NC}\n"; exit 0 ;;
        esac
    done
}

main_menu
