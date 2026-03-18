#!/bin/bash

# ============================================================
# dupes.sh — Duplicate File Finder
# Part of mac-toolbox • Zero dependencies • bash 3.2+
#
# Features:
#   - Multi-pass scanning: size → partial hash → full hash
#   - Fast: skips full hash unless size+partial match
#   - Interactive review with Quick Look preview
#   - Trash-based deletion (recoverable)
#   - Minimum size filter to skip tiny files
#
# Security:
#   - Never auto-deletes — always asks
#   - Always keeps at least one copy
#   - Trash-based, not rm
#
# Usage:
#   ./dupes.sh [path]              # Scan path (default: ~)
#   ./dupes.sh --min-size 1M       # Minimum file size (K, M, G)
#   ./dupes.sh --dry-run           # Preview only
# ============================================================

set -uo pipefail

DRY_RUN=false
TRASH_DIR="$HOME/.Trash"
TARGET_DIR="$HOME"
MIN_SIZE_KB=100  # Default: skip files < 100KB
VERSION="1.0"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)   DRY_RUN=true ;;
        --min-size)
            shift
            local_val="${1:-100K}"
            case "$local_val" in
                *G|*g) MIN_SIZE_KB=$(( ${local_val%[Gg]} * 1048576 )) ;;
                *M|*m) MIN_SIZE_KB=$(( ${local_val%[Mm]} * 1024 )) ;;
                *K|*k) MIN_SIZE_KB="${local_val%[Kk]}" ;;
                *)     MIN_SIZE_KB="$local_val" ;;
            esac
            ;;
        -h|--help)
            echo "Usage: dupes.sh [path] [--min-size SIZE] [--dry-run]"
            echo "  path         Directory to scan (default: ~)"
            echo "  --min-size   Minimum file size: 100K, 1M, 1G (default: 100K)"
            echo "  --dry-run    Preview only"
            exit 0
            ;;
        *)
            [ -d "$1" ] && TARGET_DIR="$1" || { echo "Error: '$1' not a directory"; exit 1; }
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

divider() { echo -e "${DIM}$(printf '─%.0s' {1..60})${NC}"; }
press_enter() { echo ""; read -rp "  Press Enter to continue..." _; }

header() {
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}  ║  Duplicate File Finder v${VERSION}                           ║${NC}"
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

safe_trash() {
    local item="$1"
    local base
    base=$(basename "$item")
    local dest="${TRASH_DIR}/${base}_$(date +%s)_$$"

    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}[DRY]${NC} Would trash: $item"
        return 0
    fi

    mv "$item" "$dest" 2>/dev/null && \
        echo -e "  ${GREEN}✓${NC} Trashed: $(basename "$item")" && return 0
    echo -e "  ${RED}✗${NC} Failed: $item"
    return 1
}

# ===================== HASHING =====================
# Partial hash: first 4KB only (fast filter)
partial_hash() {
    dd if="$1" bs=4096 count=1 2>/dev/null | md5 -q 2>/dev/null || \
    dd if="$1" bs=4096 count=1 2>/dev/null | md5sum 2>/dev/null | cut -d' ' -f1
}

# Full hash
full_hash() {
    md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | cut -d' ' -f1
}

# ===================== SCANNING =====================
scan_duplicates() {
    header
    echo -e "  ${BOLD}Scanning: ${CYAN}${TARGET_DIR}${NC}"
    echo -e "  ${DIM}Minimum size: $(human_size $MIN_SIZE_KB)${NC}"
    echo ""

    # ---- Pass 1: Group files by size ----
    echo -e "  ${CYAN}Pass 1/3:${NC} Grouping by file size..."

    local size_file
    size_file=$(mktemp /tmp/dupes_sizes.XXXXXX)
    trap 'rm -f "$size_file" 2>/dev/null' EXIT

    # Find all regular files above minimum size, output size\tpath
    find "$TARGET_DIR" -type f -size "+${MIN_SIZE_KB}k" \
        -not -path "*/.*" \
        -not -path "*/node_modules/*" \
        -not -path "*/.Trash/*" \
        -not -path "*/Library/Caches/*" \
        2>/dev/null | while IFS= read -r filepath; do
        local kb
        kb=$(du -k "$filepath" 2>/dev/null | cut -f1)
        [ -n "$kb" ] && echo "${kb}	${filepath}"
    done > "$size_file"

    local total_files
    total_files=$(wc -l < "$size_file" | tr -d ' ')
    echo -e "  ${DIM}  Found ${total_files} files above threshold${NC}"

    # Find sizes that appear more than once
    local -a dup_sizes=()
    while IFS= read -r sz; do
        dup_sizes+=("$sz")
    done < <(cut -f1 "$size_file" | sort | uniq -d)

    if [ ${#dup_sizes[@]} -eq 0 ]; then
        echo -e "\n  ${GREEN}✓ No potential duplicates found.${NC}"
        rm -f "$size_file"
        press_enter
        return
    fi

    echo -e "  ${DIM}  ${#dup_sizes[@]} size groups with potential duplicates${NC}"

    # ---- Pass 2: Partial hash within size groups ----
    echo -e "  ${CYAN}Pass 2/3:${NC} Partial hashing (first 4KB)..."

    local partial_file
    partial_file=$(mktemp /tmp/dupes_partial.XXXXXX)
    trap 'rm -f "$size_file" "$partial_file" 2>/dev/null' EXIT

    local checked=0
    for sz in "${dup_sizes[@]}"; do
        # Get all files of this size
        while IFS=$'\t' read -r file_size filepath; do
            [ "$file_size" != "$sz" ] && continue
            local phash
            phash=$(partial_hash "$filepath")
            echo "${phash}	${file_size}	${filepath}" >> "$partial_file"
            ((checked++))
            printf "\r  ${DIM}  Checked: %d files...${NC}" "$checked"
        done < "$size_file"
    done
    printf "\r                                          \r"

    # Find partial hashes that appear more than once
    local -a dup_phashes=()
    while IFS= read -r ph; do
        dup_phashes+=("$ph")
    done < <(cut -f1 "$partial_file" | sort | uniq -d)

    if [ ${#dup_phashes[@]} -eq 0 ]; then
        echo -e "\n  ${GREEN}✓ No duplicates confirmed after partial hash.${NC}"
        rm -f "$size_file" "$partial_file"
        press_enter
        return
    fi

    echo -e "  ${DIM}  ${#dup_phashes[@]} partial hash groups to verify${NC}"

    # ---- Pass 3: Full hash for candidates ----
    echo -e "  ${CYAN}Pass 3/3:${NC} Full hash verification..."

    # Collect confirmed duplicate groups
    local -a all_groups=()     # pipe-separated file paths per group
    local -a group_sizes=()    # size in KB per group
    local group_count=0
    local total_waste=0

    for phash in "${dup_phashes[@]}"; do
        # Get files matching this partial hash
        local -a candidates=()
        local cand_size=0
        while IFS=$'\t' read -r ph sz fp; do
            [ "$ph" != "$phash" ] && continue
            candidates+=("$fp")
            cand_size="$sz"
        done < "$partial_file"

        # Full hash each candidate
        local -a full_hashes=()
        local -a full_paths=()
        for cand in "${candidates[@]}"; do
            [ ! -f "$cand" ] && continue
            local fh
            fh=$(full_hash "$cand")
            full_hashes+=("$fh")
            full_paths+=("$cand")
        done

        # Group by full hash
        local -a seen_fh=()
        for ((i=0; i<${#full_hashes[@]}; i++)); do
            local fh="${full_hashes[$i]}"

            # Check if we already processed this hash
            local already=0
            for s in "${seen_fh[@]+"${seen_fh[@]}"}"; do
                [ "$s" = "$fh" ] && already=1 && break
            done
            [ $already -eq 1 ] && continue
            seen_fh+=("$fh")

            # Collect all files with this full hash
            local group=""
            local count=0
            for ((j=0; j<${#full_hashes[@]}; j++)); do
                if [ "${full_hashes[$j]}" = "$fh" ]; then
                    [ -n "$group" ] && group+="|"
                    group+="${full_paths[$j]}"
                    ((count++))
                fi
            done

            if [ $count -ge 2 ]; then
                all_groups+=("$group")
                group_sizes+=("$cand_size")
                local waste=$(( cand_size * (count - 1) ))
                total_waste=$((total_waste + waste))
                ((group_count++))
            fi
        done
    done

    rm -f "$size_file" "$partial_file"

    if [ $group_count -eq 0 ]; then
        echo -e "\n  ${GREEN}✓ No confirmed duplicates.${NC}"
        press_enter
        return
    fi

    # ---- Display results ----
    echo ""
    echo -e "  ${BOLD}Found ${group_count} duplicate groups${NC}"
    echo -e "  ${BOLD}Wasted space: ${YELLOW}$(human_size $total_waste)${NC}"
    echo ""

    review_duplicates "${all_groups[@]}" -- "${group_sizes[@]}"
}

# ===================== REVIEW INTERFACE =====================
review_duplicates() {
    # Parse args: groups... -- sizes...
    local -a groups=()
    local -a sizes=()
    local in_sizes=false

    for arg in "$@"; do
        if [ "$arg" = "--" ]; then
            in_sizes=true
            continue
        fi
        if [ "$in_sizes" = true ]; then
            sizes+=("$arg")
        else
            groups+=("$arg")
        fi
    done

    local total=${#groups[@]}
    local current=0

    while [ $current -lt $total ]; do
        local group="${groups[$current]}"
        local size="${sizes[$current]}"

        # Split group into individual files
        local -a files=()
        local IFS_BAK="$IFS"
        IFS='|'
        for f in $group; do
            files+=("$f")
        done
        IFS="$IFS_BAK"

        header
        echo -e "  ${BOLD}Duplicate Group $((current+1)) of ${total}${NC}"
        echo -e "  ${DIM}Each file: $(human_size $size)${NC}"
        divider

        for ((i=0; i<${#files[@]}; i++)); do
            local mod_date
            mod_date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "${files[$i]}" 2>/dev/null || echo "unknown")
            local dir_name
            dir_name=$(dirname "${files[$i]}")

            if [ $i -eq 0 ]; then
                printf "  ${GREEN}%3d.${NC} ${GREEN}[KEEP]${NC}  %-35s\n" "$((i+1))" "$(basename "${files[$i]}")"
            else
                printf "  ${GREEN}%3d.${NC}         %-35s\n" "$((i+1))" "$(basename "${files[$i]}")"
            fi
            echo -e "       ${DIM}${dir_name}  (${mod_date})${NC}"
        done

        echo ""
        divider
        echo -e "  ${DIM}First file is auto-kept. Others can be deleted.${NC}"
        echo -e "  ${DIM}(d) Delete all except #1  (s) Select to delete  (p) Preview${NC}"
        echo -e "  ${DIM}(n) Next group  (q) Quit review${NC}"
        read -rp "  > " action

        case "$action" in
            d|D)
                for ((i=1; i<${#files[@]}; i++)); do
                    safe_trash "${files[$i]}"
                done
                ;;
            s|S)
                echo -e "  ${CYAN}Enter numbers to DELETE (e.g., 2 3):${NC}"
                read -rp "  > " selections
                for num in $selections; do
                    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#files[@]} ]; then
                        if [ "$num" -eq 1 ]; then
                            echo -e "  ${YELLOW}Skipping #1 (keeping at least one copy)${NC}"
                        else
                            safe_trash "${files[$((num-1))]}"
                        fi
                    fi
                done
                ;;
            p|P)
                echo -e "  ${CYAN}Which file to preview? [#]:${NC}"
                read -rp "  > " pnum
                if [[ "$pnum" =~ ^[0-9]+$ ]] && [ "$pnum" -ge 1 ] && [ "$pnum" -le ${#files[@]} ]; then
                    qlmanage -p "${files[$((pnum-1))]}" 2>/dev/null &
                    echo -e "  ${DIM}Quick Look opened. Close it to continue.${NC}"
                    wait 2>/dev/null
                fi
                continue  # Don't advance
                ;;
            n|N) ;;
            q|Q) return ;;
            *) continue ;;
        esac

        ((current++))
    done

    echo -e "\n  ${GREEN}Review complete.${NC}"
    press_enter
}

# ===================== MAIN =====================
main_menu() {
    while true; do
        header
        echo -e "  ${BOLD}Choose an option:${NC}"
        echo ""
        echo -e "  ${GREEN}1.${NC}  Scan home directory for duplicates"
        echo -e "  ${GREEN}2.${NC}  Scan specific directory"
        echo -e "  ${GREEN}3.${NC}  Scan Downloads folder"
        echo -e "  ${GREEN}4.${NC}  Scan Desktop + Documents"
        echo -e "  ${GREEN}q.${NC}  Quit"
        echo ""
        divider
        read -rp "  > " choice

        case "$choice" in
            1) TARGET_DIR="$HOME"; scan_duplicates ;;
            2)
                read -rp "  Path: " path
                [ -d "$path" ] && { TARGET_DIR="$path"; scan_duplicates; } || \
                    echo -e "  ${RED}Not a directory.${NC}"
                ;;
            3) TARGET_DIR="$HOME/Downloads"; scan_duplicates ;;
            4) TARGET_DIR="$HOME/Documents"; scan_duplicates ;;
            q|Q) echo -e "\n  ${GREEN}Done.${NC}\n"; exit 0 ;;
        esac
    done
}

main_menu
