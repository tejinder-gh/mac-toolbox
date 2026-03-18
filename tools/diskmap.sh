#!/bin/bash

# ============================================================
# diskmap.sh — Interactive Disk Space Analyzer
# Part of mac-toolbox • Zero dependencies • bash 3.2+
#
# Features:
#   - Treemap-style directory breakdown sorted by size
#   - Known space hog detection (Xcode, node_modules, Docker, etc.)
#   - Interactive drill-down navigation
#   - One-command safe cleanup for known-safe targets
#   - Trash-based deletion
#
# Usage:
#   ./diskmap.sh [path]         # Analyze path (default: ~)
#   ./diskmap.sh --hogs         # Scan for known space hogs only
#   ./diskmap.sh --dry-run      # Preview cleanup without deleting
# ============================================================

set -uo pipefail

# ===================== CONFIG =====================
DRY_RUN=false
SCAN_HOGS_ONLY=false
TRASH_DIR="$HOME/.Trash"
TARGET_DIR="$HOME"
VERSION="1.0"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=true ;;
        --hogs)     SCAN_HOGS_ONLY=true ;;
        -h|--help)
            echo "Usage: diskmap.sh [path] [--hogs] [--dry-run]"
            echo "  path       Directory to analyze (default: ~)"
            echo "  --hogs     Scan for known space hogs only"
            echo "  --dry-run  Preview cleanup without deleting"
            exit 0
            ;;
        *)
            if [ -d "$1" ]; then
                TARGET_DIR="$1"
            else
                echo "Error: '$1' is not a directory"
                exit 1
            fi
            ;;
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

# ===================== UI =====================
divider() { echo -e "${DIM}$(printf '─%.0s' {1..60})${NC}"; }

header() {
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}  ║  Disk Space Analyzer v${VERSION}                             ║${NC}"
    if [ "$DRY_RUN" = true ]; then
    echo -e "${CYAN}${BOLD}  ║  ${YELLOW}DRY-RUN MODE${CYAN}${BOLD}                                          ║${NC}"
    fi
    echo -e "${CYAN}${BOLD}  ╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

press_enter() { echo ""; read -rp "  Press Enter to continue..." _; }

# ===================== SIZE HELPERS =====================
human_size() {
    local kb="$1"
    if [ "$kb" -ge 1073741824 ]; then
        awk "BEGIN {printf \"%.1f TB\", $kb/1073741824}"
    elif [ "$kb" -ge 1048576 ]; then
        awk "BEGIN {printf \"%.1f GB\", $kb/1048576}"
    elif [ "$kb" -ge 1024 ]; then
        awk "BEGIN {printf \"%.1f MB\", $kb/1024}"
    else
        echo "${kb} KB"
    fi
}

# Size bar visualization
size_bar() {
    local kb="$1"
    local max_kb="$2"
    local width=25

    if [ "$max_kb" -le 0 ]; then
        printf '%*s' "$width" ''
        return
    fi

    local filled=$(( (kb * width) / max_kb ))
    [ $filled -gt $width ] && filled=$width
    [ $filled -lt 1 ] && [ "$kb" -gt 0 ] && filled=1

    local bar=""
    local i
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=filled; i<width; i++)); do bar+="░"; done

    # Color based on percentage
    local pct=$(( (kb * 100) / max_kb ))
    if [ $pct -ge 50 ]; then
        echo -e "${RED}${bar}${NC}"
    elif [ $pct -ge 20 ]; then
        echo -e "${YELLOW}${bar}${NC}"
    else
        echo -e "${GREEN}${bar}${NC}"
    fi
}

# ===================== SAFE TRASH =====================
safe_trash() {
    local item="$1"

    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}[DRY]${NC} Would trash: $item"
        return 0
    fi

    local base
    base=$(basename "$item")
    local dest="${TRASH_DIR}/${base}_$(date +%s)_$$"

    if mv "$item" "$dest" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Trashed: $(basename "$item")"
        return 0
    elif sudo mv "$item" "$dest" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Trashed (sudo): $(basename "$item")"
        return 0
    else
        echo -e "  ${RED}✗${NC} Failed: $item"
        return 1
    fi
}

# ===================== DIRECTORY ANALYSIS =====================
analyze_dir() {
    local dir="$1"
    local depth="${2:-1}"

    echo -e "  ${DIM}Analyzing ${dir}...${NC}"
    echo ""

    # Get top items by size
    local -a names=()
    local -a sizes=()
    local max_size=0

    while IFS=$'\t' read -r size name; do
        [ -z "$name" ] && continue
        sizes+=("$size")
        names+=("$name")
        [ "$size" -gt "$max_size" ] && max_size="$size"
    done < <(du -sk "$dir"/*/ "$dir"/.* 2>/dev/null | \
             grep -v '/\.$' | grep -v '/\.\.$' | \
             sort -rn | head -20)

    if [ ${#names[@]} -eq 0 ]; then
        echo -e "  ${YELLOW}Empty or inaccessible directory.${NC}"
        return
    fi

    # Display
    local total_kb=0
    for ((i=0; i<${#names[@]}; i++)); do
        total_kb=$((total_kb + sizes[i]))
    done

    echo -e "  ${BOLD}Total: $(human_size $total_kb)${NC}"
    divider

    for ((i=0; i<${#names[@]}; i++)); do
        local display_name
        display_name=$(basename "${names[$i]}")
        local h_size
        h_size=$(human_size "${sizes[$i]}")
        local bar
        bar=$(size_bar "${sizes[$i]}" "$max_size")

        printf "  ${GREEN}%3d.${NC} %-28s %8s  %s\n" \
            "$((i+1))" "$display_name" "$h_size" "$bar"
    done

    echo ""
    divider
    echo -e "  ${DIM}[#] Drill into  [c] Clean known hogs  [q] Back${NC}"
    read -rp "  > " input

    case "$input" in
        q|Q) return ;;
        c|C) scan_known_hogs ;;
        *)
            if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le ${#names[@]} ]; then
                local selected="${names[$((input-1))]}"
                if [ -d "$selected" ]; then
                    header
                    analyze_dir "$selected" $((depth+1))
                fi
            fi
            ;;
    esac
}

# ===================== KNOWN SPACE HOGS =====================
scan_known_hogs() {
    header
    echo -e "  ${BOLD}Known Space Hogs Scanner${NC}"
    echo -e "  ${DIM}Scanning for safely removable caches and artifacts...${NC}"
    echo ""

    local -a hog_paths=()
    local -a hog_names=()
    local -a hog_sizes=()
    local -a hog_safe=()   # "safe" = can delete without side effects beyond rebuild time

    # Each entry: description | path | safety level (safe/caution)
    check_hog() {
        local name="$1"
        local path="$2"
        local safety="$3"

        if [ -d "$path" ] || [ -f "$path" ]; then
            local kb
            kb=$(du -sk "$path" 2>/dev/null | cut -f1)
            if [ "${kb:-0}" -ge 1024 ]; then  # Only report >1MB
                hog_paths+=("$path")
                hog_names+=("$name")
                hog_sizes+=("$kb")
                hog_safe+=("$safety")
            fi
        fi
    }

    # --- Developer caches ---
    check_hog "Xcode DerivedData" \
        "$HOME/Library/Developer/Xcode/DerivedData" "safe"

    check_hog "Xcode Archives" \
        "$HOME/Library/Developer/Xcode/Archives" "caution"

    check_hog "Xcode iOS DeviceSupport" \
        "$HOME/Library/Developer/Xcode/iOS DeviceSupport" "safe"

    check_hog "CocoaPods cache" \
        "$HOME/Library/Caches/CocoaPods" "safe"

    check_hog "Carthage cache" \
        "$HOME/Library/Caches/org.carthage.CarthageKit" "safe"

    check_hog "Gradle cache" \
        "$HOME/.gradle/caches" "safe"

    check_hog "Maven cache" \
        "$HOME/.m2/repository" "caution"

    check_hog "Pip cache" \
        "$HOME/Library/Caches/pip" "safe"

    check_hog "NPM cache" \
        "$HOME/.npm/_cacache" "safe"

    check_hog "Yarn cache" \
        "$HOME/Library/Caches/Yarn" "safe"

    check_hog "Cargo registry" \
        "$HOME/.cargo/registry" "safe"

    check_hog "Go module cache" \
        "$HOME/go/pkg/mod/cache" "safe"

    # --- System caches ---
    check_hog "Homebrew cache" \
        "$HOME/Library/Caches/Homebrew" "safe"

    check_hog "Homebrew logs" \
        "$HOME/Library/Logs/Homebrew" "safe"

    check_hog "Safari cache" \
        "$HOME/Library/Caches/com.apple.Safari" "safe"

    check_hog "Chrome cache" \
        "$HOME/Library/Caches/Google/Chrome" "safe"

    check_hog "Firefox cache" \
        "$HOME/Library/Caches/Firefox" "safe"

    check_hog "Spotify cache" \
        "$HOME/Library/Caches/com.spotify.client" "safe"

    check_hog "Slack cache" \
        "$HOME/Library/Caches/com.tinyspeck.slackmacgap" "safe"

    check_hog "Adobe cache" \
        "$HOME/Library/Caches/Adobe" "safe"

    # --- Trash ---
    check_hog "Trash contents" \
        "$HOME/.Trash" "safe"

    # --- Logs ---
    check_hog "System logs (user)" \
        "$HOME/Library/Logs" "safe"

    check_hog "Core dumps" \
        "/cores" "safe"

    # --- Scan for node_modules trees ---
    echo -e "  ${DIM}Scanning for node_modules (may take a moment)...${NC}"
    local node_total=0
    local node_count=0
    while IFS= read -r nm_dir; do
        local nm_kb
        nm_kb=$(du -sk "$nm_dir" 2>/dev/null | cut -f1)
        node_total=$((node_total + nm_kb))
        ((node_count++))
    done < <(find "$HOME" -maxdepth 6 -name "node_modules" -type d -prune 2>/dev/null)

    if [ $node_total -ge 1024 ]; then
        hog_paths+=("__node_modules__")
        hog_names+=("node_modules (${node_count} dirs)")
        hog_sizes+=("$node_total")
        hog_safe+=("caution")
    fi

    printf "\r                                                  \r"

    if [ ${#hog_paths[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✓ No significant space hogs found!${NC}"
        press_enter
        return
    fi

    # Sort by size (descending) — simple bubble sort for bash 3.2
    local n=${#hog_sizes[@]}
    local swapped=true
    while [ "$swapped" = true ]; do
        swapped=false
        for ((i=0; i<n-1; i++)); do
            if [ "${hog_sizes[$i]}" -lt "${hog_sizes[$((i+1))]}" ]; then
                local tmp="${hog_sizes[$i]}"
                hog_sizes[$i]="${hog_sizes[$((i+1))]}"
                hog_sizes[$((i+1))]="$tmp"
                tmp="${hog_names[$i]}"
                hog_names[$i]="${hog_names[$((i+1))]}"
                hog_names[$((i+1))]="$tmp"
                tmp="${hog_paths[$i]}"
                hog_paths[$i]="${hog_paths[$((i+1))]}"
                hog_paths[$((i+1))]="$tmp"
                tmp="${hog_safe[$i]}"
                hog_safe[$i]="${hog_safe[$((i+1))]}"
                hog_safe[$((i+1))]="$tmp"
                swapped=true
            fi
        done
        ((n--))
    done

    # Display
    local total_kb=0
    local max_kb="${hog_sizes[0]}"
    divider

    for ((i=0; i<${#hog_paths[@]}; i++)); do
        total_kb=$((total_kb + hog_sizes[i]))
        local h_size
        h_size=$(human_size "${hog_sizes[$i]}")
        local safety_label=""
        if [ "${hog_safe[$i]}" = "safe" ]; then
            safety_label="${GREEN}safe${NC}"
        else
            safety_label="${YELLOW}caution${NC}"
        fi
        local bar
        bar=$(size_bar "${hog_sizes[$i]}" "$max_kb")

        printf "  ${GREEN}%3d.${NC} %-30s %8s  [%b]  %s\n" \
            "$((i+1))" "${hog_names[$i]}" "$h_size" "$safety_label" "$bar"
    done

    echo ""
    divider
    echo -e "  ${BOLD}Total reclaimable: ${YELLOW}$(human_size $total_kb)${NC}"
    echo ""
    echo -e "  ${DIM}(f) Clean 'safe' items only  (s) Select items  (n) Cancel${NC}"
    read -rp "  > " choice

    case "$choice" in
        f|F)
            echo -e "\n  ${RED}Confirm: clean all items marked 'safe'?${NC}"
            read -rp "  Type 'yes': " confirm
            if [ "$confirm" = "yes" ]; then
                for ((i=0; i<${#hog_paths[@]}; i++)); do
                    if [ "${hog_safe[$i]}" = "safe" ] && [ "${hog_paths[$i]}" != "__node_modules__" ]; then
                        if [ -d "${hog_paths[$i]}" ]; then
                            # For caches, delete contents not the folder itself
                            if [[ "${hog_paths[$i]}" == *"/Caches/"* ]] || [[ "${hog_paths[$i]}" == *"/Logs/"* ]]; then
                                if [ "$DRY_RUN" = true ]; then
                                    echo -e "  ${YELLOW}[DRY]${NC} Would clean: ${hog_names[$i]}"
                                else
                                    rm -rf "${hog_paths[$i]:?}"/* 2>/dev/null && \
                                        echo -e "  ${GREEN}✓${NC} Cleaned: ${hog_names[$i]}" || \
                                        echo -e "  ${RED}✗${NC} Failed: ${hog_names[$i]}"
                                fi
                            else
                                safe_trash "${hog_paths[$i]}"
                            fi
                        fi
                    fi
                done
                echo -e "\n  ${GREEN}Done.${NC}"
            fi
            ;;
        s|S)
            echo -e "\n  ${CYAN}Enter numbers (e.g., 1 3 5) or 'q':${NC}"
            read -rp "  > " selections
            [ "$selections" = "q" ] && return

            for num in $selections; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#hog_paths[@]} ]; then
                    local idx=$((num-1))
                    local path="${hog_paths[$idx]}"
                    if [ "$path" = "__node_modules__" ]; then
                        echo -e "  ${YELLOW}node_modules cleanup — use dev-clean.sh for selective removal${NC}"
                        continue
                    fi
                    if [[ "$path" == *"/Caches/"* ]] || [[ "$path" == *"/Logs/"* ]]; then
                        if [ "$DRY_RUN" = true ]; then
                            echo -e "  ${YELLOW}[DRY]${NC} Would clean: ${hog_names[$idx]}"
                        else
                            rm -rf "${path:?}"/* 2>/dev/null && \
                                echo -e "  ${GREEN}✓${NC} Cleaned: ${hog_names[$idx]}" || \
                                echo -e "  ${RED}✗${NC} Failed: ${hog_names[$idx]}"
                        fi
                    else
                        safe_trash "$path"
                    fi
                fi
            done
            ;;
        *) echo -e "\n  ${YELLOW}Cancelled.${NC}" ;;
    esac

    press_enter
}

# ===================== DISK OVERVIEW =====================
disk_overview() {
    header

    # System disk info
    local disk_info
    disk_info=$(df -kl / 2>/dev/null | tail -1)
    local total_kb used_kb avail_kb
    total_kb=$(echo "$disk_info" | awk '{print $2}')
    used_kb=$(echo "$disk_info" | awk '{print $3}')
    avail_kb=$(echo "$disk_info" | awk '{print $4}')
    local pct_used=$(( (used_kb * 100) / total_kb ))

    echo -e "  ${BOLD}System Disk${NC}"
    echo -e "  Total: $(human_size $total_kb)  Used: $(human_size $used_kb)  Free: ${GREEN}$(human_size $avail_kb)${NC} (${pct_used}% used)"

    local disk_bar
    disk_bar=$(size_bar $used_kb $total_kb)
    echo -e "  $disk_bar"
    echo ""

    # Quick summary of home directory
    echo -e "  ${BOLD}Home Directory Breakdown${NC}"
    analyze_dir "$TARGET_DIR"
}

# ===================== MAIN MENU =====================
main_menu() {
    if [ "$SCAN_HOGS_ONLY" = true ]; then
        header
        scan_known_hogs
        exit 0
    fi

    while true; do
        header
        echo -e "  ${BOLD}Choose an option:${NC}"
        echo ""
        echo -e "  ${GREEN}1.${NC}  Disk overview + directory breakdown"
        echo -e "  ${GREEN}2.${NC}  Scan for known space hogs"
        echo -e "  ${GREEN}3.${NC}  Analyze specific directory"
        echo -e "  ${GREEN}q.${NC}  Quit"
        echo ""
        if [ "$DRY_RUN" = true ]; then
            echo -e "  ${YELLOW}${BOLD}⚠  DRY-RUN active${NC}"
            echo ""
        fi
        divider
        read -rp "  > " choice

        case "$choice" in
            1) disk_overview; press_enter ;;
            2) scan_known_hogs ;;
            3)
                read -rp "  Path: " path
                if [ -d "$path" ]; then
                    header
                    analyze_dir "$path"
                    press_enter
                else
                    echo -e "  ${RED}Not a valid directory.${NC}"
                    sleep 1
                fi
                ;;
            q|Q)
                echo -e "\n  ${GREEN}Done.${NC}\n"
                exit 0
                ;;
        esac
    done
}

main_menu
