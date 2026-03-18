#!/bin/bash

# ============================================================
# dev-clean.sh — Developer Environment Cleaner
# Part of mac-toolbox • Zero dependencies • bash 3.2+
#
# Features:
#   - Scans for node_modules, DerivedData, build dirs, venvs, caches
#   - Stale project detection (>90 days untouched)
#   - Per-project size reporting
#   - Selective or bulk cleanup
#   - Trash-based deletion
#
# Usage:
#   ./dev-clean.sh [path] [--dry-run] [--stale-days N]
# ============================================================

set -uo pipefail

DRY_RUN=false
TRASH_DIR="$HOME/.Trash"
SCAN_DIR="$HOME"
STALE_DAYS=90
VERSION="1.0"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)     DRY_RUN=true ;;
        --stale-days)  shift; STALE_DAYS="${1:-90}" ;;
        -h|--help)
            echo "Usage: dev-clean.sh [path] [--dry-run] [--stale-days N]"
            exit 0
            ;;
        *)  [ -d "$1" ] && SCAN_DIR="$1" ;;
    esac
    shift
done

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
    echo -e "${CYAN}${BOLD}  ║  Dev Environment Cleaner v${VERSION}                          ║${NC}"
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

safe_remove() {
    local item="$1"

    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}[DRY]${NC} Would remove: $item"
        return 0
    fi

    # For large build artifacts, rm is faster than trash (and they're regenerable)
    rm -rf "$item" 2>/dev/null && \
        echo -e "  ${GREEN}✓${NC} Removed: $(basename "$item")" && return 0
    echo -e "  ${RED}✗${NC} Failed: $item"
    return 1
}

# ===================== ARTIFACT DEFINITIONS =====================
# name|find_pattern|find_type|max_depth|description
ARTIFACT_TYPES=(
    "node_modules|node_modules|d|7|Node.js dependencies"
    ".next|.next|d|6|Next.js build cache"
    "dist|dist|d|5|Build output (JS/TS)"
    "build|build|d|5|Build output (generic)"
    "__pycache__|__pycache__|d|8|Python bytecode cache"
    ".tox|.tox|d|5|Python tox environments"
    ".venv|.venv|d|5|Python virtual environments"
    "venv|venv|d|5|Python virtual environments"
    ".pytest_cache|.pytest_cache|d|6|Pytest cache"
    "target|target|d|5|Rust/Java/Scala build"
    ".gradle|.gradle|d|5|Gradle build cache"
    ".dart_tool|.dart_tool|d|6|Dart/Flutter tool cache"
    ".pub-cache|.pub-cache|d|5|Dart pub cache"
    "Pods|Pods|d|5|CocoaPods dependencies"
    "DerivedData|DerivedData|d|3|Xcode build artifacts"
)

# ===================== SCAN =====================
scan_artifacts() {
    local artifact_name="$1"
    local find_pattern="$2"
    local find_type="$3"
    local max_depth="$4"

    local -a results=()
    local -a result_sizes=()
    local -a result_parents=()
    local total_kb=0

    while IFS= read -r found; do
        [ -z "$found" ] && continue

        local kb
        kb=$(du -sk "$found" 2>/dev/null | cut -f1)
        [ "${kb:-0}" -lt 100 ] && continue  # Skip tiny

        results+=("$found")
        result_sizes+=("$kb")
        total_kb=$((total_kb + kb))

        # Get parent project name
        local parent
        parent=$(dirname "$found")
        result_parents+=("$parent")
    done < <(find "$SCAN_DIR" -maxdepth "$max_depth" \
        -name "$find_pattern" -type "$find_type" -prune \
        -not -path "*/.Trash/*" \
        -not -path "*/Library/*" \
        2>/dev/null)

    echo "${#results[@]}|${total_kb}"

    # Store results in temp file for later use
    local tmpfile="/tmp/devclean_${artifact_name}.tmp"
    : > "$tmpfile"
    for ((i=0; i<${#results[@]}; i++)); do
        echo "${result_sizes[$i]}|${results[$i]}|${result_parents[$i]}" >> "$tmpfile"
    done
}

# ===================== FULL SCAN =====================
full_scan() {
    header
    echo -e "  ${BOLD}Scanning: ${CYAN}${SCAN_DIR}${NC}"
    echo -e "  ${DIM}This may take a minute for large home directories...${NC}"
    echo ""
    divider

    local -a art_names=()
    local -a art_counts=()
    local -a art_totals=()
    local -a art_descs=()
    local grand_total=0

    for entry in "${ARTIFACT_TYPES[@]}"; do
        local IFS_BAK="$IFS"
        IFS='|'
        set -- $entry
        local name="$1" pattern="$2" ftype="$3" depth="$4" desc="$5"
        IFS="$IFS_BAK"

        printf "\r  Scanning %-20s" "${name}..."
        local result
        result=$(scan_artifacts "$name" "$pattern" "$ftype" "$depth")
        local count="${result%%|*}"
        local total_kb="${result##*|}"

        if [ "$count" -gt 0 ]; then
            art_names+=("$name")
            art_counts+=("$count")
            art_totals+=("$total_kb")
            art_descs+=("$desc")
            grand_total=$((grand_total + total_kb))
        fi
    done

    printf "\r                                          \r"

    if [ ${#art_names[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✓ No significant dev artifacts found.${NC}"
        press_enter
        return
    fi

    # Display summary
    for ((i=0; i<${#art_names[@]}; i++)); do
        printf "  ${GREEN}%3d.${NC} %-20s %4d dirs   ${YELLOW}%10s${NC}  ${DIM}%s${NC}\n" \
            "$((i+1))" "${art_names[$i]}" "${art_counts[$i]}" \
            "$(human_size "${art_totals[$i]}")" "${art_descs[$i]}"
    done

    echo ""
    divider
    echo -e "  ${BOLD}Total reclaimable: ${YELLOW}$(human_size $grand_total)${NC}"
    echo ""
    echo -e "  ${DIM}[#] Expand category  (a) Clean all  (f) Clean safe only  (q) Back${NC}"
    read -rp "  > " choice

    case "$choice" in
        a|A)
            echo -e "\n  ${RED}Confirm: remove ALL dev artifacts?${NC}"
            echo -e "  ${DIM}(node_modules and build dirs will be regenerated on next build)${NC}"
            read -rp "  Type 'yes': " confirm
            if [ "$confirm" = "yes" ]; then
                for name in "${art_names[@]}"; do
                    local tmpfile="/tmp/devclean_${name}.tmp"
                    [ ! -f "$tmpfile" ] && continue
                    while IFS='|' read -r sz path parent; do
                        safe_remove "$path"
                    done < "$tmpfile"
                done
                echo -e "\n  ${GREEN}Done. Freed ~$(human_size $grand_total).${NC}"
            fi
            press_enter
            ;;
        f|F)
            # "Safe" = caches and build artifacts, NOT venvs or source deps
            local safe_names=("node_modules" ".next" "dist" "build" "__pycache__"
                            ".pytest_cache" "DerivedData" ".dart_tool" "target" ".tox")
            echo -e "\n  ${YELLOW}Cleaning safe-to-remove artifacts only...${NC}"
            local freed=0
            for name in "${safe_names[@]}"; do
                local tmpfile="/tmp/devclean_${name}.tmp"
                [ ! -f "$tmpfile" ] && continue
                while IFS='|' read -r sz path parent; do
                    safe_remove "$path"
                    freed=$((freed + sz))
                done < "$tmpfile"
            done
            echo -e "\n  ${GREEN}Freed ~$(human_size $freed).${NC}"
            press_enter
            ;;
        q|Q) ;;
        *)
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#art_names[@]} ]; then
                expand_category "${art_names[$((choice-1))]}"
            fi
            ;;
    esac

    # Cleanup temp files
    rm -f /tmp/devclean_*.tmp 2>/dev/null
}

# ===================== EXPAND CATEGORY =====================
expand_category() {
    local name="$1"
    local tmpfile="/tmp/devclean_${name}.tmp"

    if [ ! -f "$tmpfile" ]; then
        echo -e "  ${RED}No data for ${name}.${NC}"
        press_enter
        return
    fi

    header
    echo -e "  ${BOLD}${name} directories${NC}"
    divider

    local -a paths=()
    local -a sizes=()
    local -a parents=()
    local total_kb=0

    while IFS='|' read -r sz path parent; do
        sizes+=("$sz")
        paths+=("$path")
        parents+=("$parent")
        total_kb=$((total_kb + sz))
    done < <(sort -rn -t'|' -k1,1 "$tmpfile")

    for ((i=0; i<${#paths[@]}; i++)); do
        local proj_name
        proj_name=$(basename "${parents[$i]}")

        # Check staleness
        local stale=""
        local last_mod
        last_mod=$(find "${parents[$i]}" -maxdepth 1 -type f -newer "$SCAN_DIR" 2>/dev/null | head -1)
        if [ -z "$last_mod" ]; then
            local mod_days
            mod_days=$(( ( $(date +%s) - $(stat -f %m "${parents[$i]}" 2>/dev/null || echo 0) ) / 86400 ))
            if [ "$mod_days" -gt "$STALE_DAYS" ]; then
                stale=" ${RED}(stale: ${mod_days}d)${NC}"
            fi
        fi

        printf "  ${GREEN}%3d.${NC} %-30s %10s%b\n" \
            "$((i+1))" "$proj_name" "$(human_size "${sizes[$i]}")" "$stale"
    done

    echo ""
    divider
    echo -e "  ${BOLD}Total: ${YELLOW}$(human_size $total_kb)${NC}"
    echo ""
    echo -e "  ${DIM}(a) Remove all  (s) Select  (q) Back${NC}"
    read -rp "  > " choice

    case "$choice" in
        a|A)
            echo -e "\n  ${RED}Remove all ${name} directories?${NC}"
            read -rp "  Type 'yes': " confirm
            if [ "$confirm" = "yes" ]; then
                for path in "${paths[@]}"; do
                    safe_remove "$path"
                done
            fi
            ;;
        s|S)
            echo -e "  ${CYAN}Enter numbers (e.g., 1 3 5):${NC}"
            read -rp "  > " selections
            for num in $selections; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#paths[@]} ]; then
                    safe_remove "${paths[$((num-1))]}"
                fi
            done
            ;;
    esac

    press_enter
}

# ===================== STALE PROJECTS =====================
find_stale_projects() {
    header
    echo -e "  ${BOLD}Stale Projects${NC}"
    echo -e "  ${DIM}Projects not modified in ${STALE_DAYS}+ days with build artifacts${NC}"
    echo ""

    local -a stale_dirs=()
    local -a stale_sizes=()
    local total_kb=0

    # Look for common project indicators
    for indicator in "package.json" "Cargo.toml" "go.mod" "Gemfile" "*.xcodeproj" "pubspec.yaml" "requirements.txt" "setup.py"; do
        while IFS= read -r proj_file; do
            [ -z "$proj_file" ] && continue
            local proj_dir
            proj_dir=$(dirname "$proj_file")

            # Check modification time
            local mod_epoch
            mod_epoch=$(stat -f %m "$proj_dir" 2>/dev/null || echo 0)
            local now_epoch
            now_epoch=$(date +%s)
            local age_days=$(( (now_epoch - mod_epoch) / 86400 ))

            [ "$age_days" -lt "$STALE_DAYS" ] && continue

            # Check if it has cleanable artifacts
            local artifact_kb=0
            for art_dir in "node_modules" "dist" "build" ".next" "target" "__pycache__" "DerivedData" "Pods" ".tox" ".venv"; do
                if [ -d "${proj_dir}/${art_dir}" ]; then
                    local kb
                    kb=$(du -sk "${proj_dir}/${art_dir}" 2>/dev/null | cut -f1)
                    artifact_kb=$((artifact_kb + kb))
                fi
            done

            [ $artifact_kb -lt 1024 ] && continue  # Skip if < 1MB artifacts

            stale_dirs+=("$proj_dir")
            stale_sizes+=("$artifact_kb")
            total_kb=$((total_kb + artifact_kb))
        done < <(find "$SCAN_DIR" -maxdepth 5 -name "$indicator" -not -path "*/node_modules/*" -not -path "*/.Trash/*" -not -path "*/Library/*" 2>/dev/null)
    done

    if [ ${#stale_dirs[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✓ No stale projects with significant artifacts found.${NC}"
        press_enter
        return
    fi

    divider
    for ((i=0; i<${#stale_dirs[@]}; i++)); do
        local proj_name
        proj_name=$(basename "${stale_dirs[$i]}")
        printf "  ${GREEN}%3d.${NC} %-35s ${YELLOW}%10s${NC}\n" \
            "$((i+1))" "$proj_name" "$(human_size "${stale_sizes[$i]}")"
    done

    echo ""
    divider
    echo -e "  ${BOLD}Total artifact space in stale projects: ${YELLOW}$(human_size $total_kb)${NC}"
    echo ""
    echo -e "  ${DIM}(s) Select to clean  (q) Back${NC}"
    read -rp "  > " choice

    if [ "$choice" = "s" ] || [ "$choice" = "S" ]; then
        echo -e "  ${CYAN}Enter numbers (e.g., 1 3):${NC}"
        read -rp "  > " selections
        for num in $selections; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#stale_dirs[@]} ]; then
                local proj="${stale_dirs[$((num-1))]}"
                for art_dir in "node_modules" "dist" "build" ".next" "target" "__pycache__" "DerivedData" "Pods" ".tox" ".venv"; do
                    [ -d "${proj}/${art_dir}" ] && safe_remove "${proj}/${art_dir}"
                done
            fi
        done
    fi

    press_enter
}

# ===================== MAIN =====================
main_menu() {
    while true; do
        header
        echo -e "  ${BOLD}Choose an option:${NC}"
        echo ""
        echo -e "  ${GREEN}1.${NC}  Full artifact scan"
        echo -e "  ${GREEN}2.${NC}  Find stale projects (>${STALE_DAYS} days)"
        echo -e "  ${GREEN}3.${NC}  Quick: clean all node_modules"
        echo -e "  ${GREEN}4.${NC}  Quick: clean Xcode DerivedData"
        echo -e "  ${GREEN}q.${NC}  Quit"
        echo ""
        divider
        read -rp "  > " choice

        case "$choice" in
            1) full_scan ;;
            2) find_stale_projects ;;
            3)
                echo -e "\n  ${DIM}Scanning for node_modules...${NC}"
                local nm_count=0 nm_total=0
                while IFS= read -r nm; do
                    local kb
                    kb=$(du -sk "$nm" 2>/dev/null | cut -f1)
                    nm_total=$((nm_total + kb))
                    ((nm_count++))
                    safe_remove "$nm"
                done < <(find "$SCAN_DIR" -maxdepth 7 -name "node_modules" -type d -prune -not -path "*/.Trash/*" 2>/dev/null)
                echo -e "  ${GREEN}Cleaned ${nm_count} dirs (~$(human_size $nm_total))${NC}"
                press_enter
                ;;
            4)
                local dd="$HOME/Library/Developer/Xcode/DerivedData"
                if [ -d "$dd" ]; then
                    local kb
                    kb=$(du -sk "$dd" 2>/dev/null | cut -f1)
                    safe_remove "$dd"
                    mkdir -p "$dd"  # Xcode expects it to exist
                    echo -e "  ${GREEN}Freed $(human_size $kb)${NC}"
                else
                    echo -e "  ${DIM}DerivedData not found.${NC}"
                fi
                press_enter
                ;;
            q|Q) echo -e "\n  ${GREEN}Done.${NC}\n"; exit 0 ;;
        esac
    done
}

main_menu
