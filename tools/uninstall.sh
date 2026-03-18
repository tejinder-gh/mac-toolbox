#!/bin/bash

# ============================================================
# Mac App Uninstaller v3.2 — Safe + Full-Featured
#
# Features:
#   - Browse & uninstall apps (paginated, searchable)
#   - Orphan scanner (detects leftovers from removed apps)
#   - Quick uninstall by name
#   - Trash-based delete (undoable via ⌘+Z)
#   - Dry-run mode (preview only)
#   - Confidence scoring (HIGH/MED/LOW)
#
# v3.2 critical fix:
#   Orphan scanner was using strict matching for exclusion,
#   causing installed apps' data to be flagged and deleted.
#   Now uses dual strategy:
#     UNINSTALL = strict matching (avoid deleting wrong files)
#     ORPHAN    = conservative matching (avoid flagging installed)
#   Bundle IDs are tokenized: com.tinyspeck.slackmacgap →
#   ["tinyspeck", "slackmacgap", "slack"] all become known tokens.
#
# Usage:
#   ./mac-app-uninstaller.sh              # Normal mode
#   ./mac-app-uninstaller.sh --dry-run    # Preview only
#
# Requires: macOS 10.15+, bash 3.2+
# ============================================================

set -uo pipefail

# ===================== CONFIG =====================
DRY_RUN=false
TRASH_DIR="$HOME/.Trash"
VERSION="3.2"

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Temp files (bash 3.2 compat — no associative arrays)
SEEN_FILE=$(mktemp /tmp/uninstaller_seen.XXXXXX)
KNOWN_TOKENS_FILE=$(mktemp /tmp/uninstaller_tokens.XXXXXX)
trap 'rm -f "$SEEN_FILE" "$KNOWN_TOKENS_FILE"' EXIT

# ===================== COLORS =====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ===================== UI HELPERS =====================
divider() { echo -e "${DIM}$(printf '─%.0s' {1..56})${NC}"; }

header() {
    clear
    echo ""
    echo -e "${CYAN}${BOLD}  ╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}  ║  Mac App Uninstaller v${VERSION}                        ║${NC}"
    if [ "$DRY_RUN" = true ]; then
    echo -e "${CYAN}${BOLD}  ║  ${YELLOW}DRY-RUN MODE — nothing will be deleted${CYAN}${BOLD}            ║${NC}"
    else
    echo -e "${CYAN}${BOLD}  ║  ${DIM}Trash-based • Confidence-scored • Safe${CYAN}${BOLD}            ║${NC}"
    fi
    echo -e "${CYAN}${BOLD}  ╚════════════════════════════════════════════════════╝${NC}"
    echo ""
}

press_enter() {
    echo ""
    read -rp "  Press Enter to continue..." _
}

# ===================== DEDUP (bash 3.2 safe) =====================
seen_reset() { : > "$SEEN_FILE"; }

seen_add() {
    if grep -qxF "$1" "$SEEN_FILE" 2>/dev/null; then
        return 0  # duplicate
    fi
    echo "$1" >> "$SEEN_FILE"
    return 1  # new
}

# ===================== BUNDLE ID =====================
get_bundle_id() {
    local plist="$1/Contents/Info.plist"
    if [ -f "$plist" ]; then
        /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null || true
    fi
}

# ===================== STRICT MATCHING (for uninstall) =====================
# "Go" does NOT match "Google". Dot/hyphen segment boundaries required.
matches_strict() {
    local name="$1"    # already lowercased
    local pattern="$2" # already lowercased

    [[ "$name" == "$pattern" ]]       && return 0
    [[ "$name" == "$pattern".* ]]     && return 0
    [[ "$name" == *".$pattern" ]]     && return 0
    [[ "$name" == *".$pattern".* ]]   && return 0
    [[ "$name" == "${pattern}-"* ]]   && return 0
    [[ "$name" == *"-${pattern}" ]]   && return 0
    [[ "$name" == *"-${pattern}-"* ]] && return 0

    # Multi-word: "google chrome" → googlechrome, google.chrome, google-chrome
    if [[ "$pattern" == *" "* ]]; then
        local nospace="${pattern// /}"
        local dotted="${pattern// /.}"
        local hyphenated="${pattern// /-}"

        [[ "$name" == "$nospace" ]]        && return 0
        [[ "$name" == "$nospace".* ]]      && return 0
        [[ "$name" == *".$nospace" ]]      && return 0
        [[ "$name" == *".$nospace".* ]]    && return 0
        [[ "$name" == "$dotted" ]]         && return 0
        [[ "$name" == "$dotted".* ]]       && return 0
        [[ "$name" == *".$dotted" ]]       && return 0
        [[ "$name" == *".$dotted".* ]]     && return 0
        [[ "$name" == "$hyphenated" ]]     && return 0
        [[ "$name" == "$hyphenated".* ]]   && return 0
        [[ "$name" == *".$hyphenated" ]]   && return 0
        [[ "$name" == *".$hyphenated".* ]] && return 0
    fi

    return 1
}

# ===================== CONSERVATIVE MATCHING (for orphan exclusion) =====================
# The OPPOSITE goal: when deciding if a Library item belongs to an
# installed app, we want to be LOOSE to avoid false orphan flags.
# Uses a pre-built token file of all known identifiers.

# Build comprehensive token list from all installed apps
build_known_tokens() {
    : > "$KNOWN_TOKENS_FILE"

    # Generic tokens to never use for matching (too many false hits)
    local -a generic_tokens=("com" "org" "net" "io" "co" "app" "mac"
        "macos" "osx" "desktop" "helper" "agent" "daemon" "service"
        "main" "core" "lib" "framework" "extension" "plugin" "widget"
        "the" "my" "pro" "plus" "free" "beta" "dev" "test")

    for app in /Applications/*.app "$HOME"/Applications/*.app; do
        [ ! -d "$app" ] && continue

        local name
        name=$(basename "$app" .app)
        local name_lower
        name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')

        # Token 1: full app name
        echo "$name_lower" >> "$KNOWN_TOKENS_FILE"

        # Token 2: app name with spaces stripped
        local nospace="${name_lower// /}"
        [ "$nospace" != "$name_lower" ] && echo "$nospace" >> "$KNOWN_TOKENS_FILE"

        # Token 3: app name with spaces → dots
        local dotted="${name_lower// /.}"
        [ "$dotted" != "$name_lower" ] && echo "$dotted" >> "$KNOWN_TOKENS_FILE"

        # Token 4: app name with spaces → hyphens
        local hyphenated="${name_lower// /-}"
        [ "$hyphenated" != "$name_lower" ] && echo "$hyphenated" >> "$KNOWN_TOKENS_FILE"

        # Token 5: individual words from multi-word names (≥4 chars only)
        if [[ "$name_lower" == *" "* ]]; then
            for word in $name_lower; do
                [ ${#word} -ge 4 ] && echo "$word" >> "$KNOWN_TOKENS_FILE"
            done
        fi

        # Token 6: full bundle ID
        local bid
        bid=$(get_bundle_id "$app")
        if [ -n "$bid" ]; then
            local bid_lower
            bid_lower=$(echo "$bid" | tr '[:upper:]' '[:lower:]')
            echo "$bid_lower" >> "$KNOWN_TOKENS_FILE"

            # Token 7: each meaningful segment of bundle ID
            # com.tinyspeck.slackmacgap → tinyspeck, slackmacgap
            local IFS_BAK="$IFS"
            IFS='.'
            for segment in $bid_lower; do
                IFS="$IFS_BAK"
                # Skip generic segments
                local is_generic=0
                for g in "${generic_tokens[@]}"; do
                    [ "$segment" = "$g" ] && is_generic=1 && break
                done
                # Skip very short segments (≤2 chars)
                if [ $is_generic -eq 0 ] && [ ${#segment} -ge 3 ]; then
                    echo "$segment" >> "$KNOWN_TOKENS_FILE"
                fi
            done
            IFS="$IFS_BAK"
        fi
    done

    # Deduplicate and sort
    sort -u "$KNOWN_TOKENS_FILE" -o "$KNOWN_TOKENS_FILE"
}

# Check if a Library item name matches ANY known token (conservative)
matches_any_known_token() {
    local name="$1"  # already lowercased

    while IFS= read -r token; do
        [ -z "$token" ] && continue

        # Exact match
        [[ "$name" == "$token" ]] && return 0

        # Dot/hyphen segment match (both directions)
        [[ "$name" == "$token".* ]]     && return 0
        [[ "$name" == *".$token" ]]     && return 0
        [[ "$name" == *".$token".* ]]   && return 0
        [[ "$name" == "${token}-"* ]]   && return 0
        [[ "$name" == *"-${token}" ]]   && return 0
        [[ "$name" == *"-${token}-"* ]] && return 0

        # Substring containment for tokens ≥5 chars
        # (shorter tokens cause too many false matches)
        if [ ${#token} -ge 5 ]; then
            [[ "$name" == *"$token"* ]] && return 0
        fi

    done < "$KNOWN_TOKENS_FILE"

    return 1
}

# ===================== CONFIDENCE SCORING (uninstall) =====================
get_confidence() {
    local filepath="$1"
    local app_name="$2"
    local bundle_id="${3:-}"

    local base
    base=$(basename "$filepath")
    local lower
    lower=$(echo "$base" | tr '[:upper:]' '[:lower:]')
    local app_lower
    app_lower=$(echo "$app_name" | tr '[:upper:]' '[:lower:]')
    local app_nospace="${app_lower// /}"
    local app_dotted="${app_lower// /.}"
    local bid_lower=""
    [ -n "$bundle_id" ] && bid_lower=$(echo "$bundle_id" | tr '[:upper:]' '[:lower:]')

    # HIGH: exact name, .app bundle, exact bundle ID, standard OS patterns
    [[ "$lower" == "$app_lower" ]]                            && echo "HIGH" && return
    [[ "$lower" == "$app_nospace" ]]                          && echo "HIGH" && return
    [[ "$lower" == "${app_lower}.app" ]]                      && echo "HIGH" && return
    [[ -n "$bid_lower" && "$lower" == "$bid_lower" ]]         && echo "HIGH" && return
    [[ -n "$bid_lower" && "$lower" == "$bid_lower".* ]]       && echo "HIGH" && return
    [[ -n "$bid_lower" && "$lower" == "${bid_lower}.plist" ]] && echo "HIGH" && return
    [[ "$lower" == "${app_lower}.savedstate" ]]               && echo "HIGH" && return
    [[ "$lower" == "${app_nospace}.savedstate" ]]              && echo "HIGH" && return
    [[ "$lower" == "${app_lower}.plist" ]]                    && echo "HIGH" && return
    [[ "$lower" == "${app_nospace}.plist" ]]                   && echo "HIGH" && return
    [[ "$lower" == "com."*".${app_nospace}" ]]                && echo "HIGH" && return
    [[ "$lower" == "com."*".${app_nospace}.plist" ]]          && echo "HIGH" && return
    [[ "$lower" == "com."*".${app_dotted}" ]]                 && echo "HIGH" && return

    # MED: app name + separator, or contains bundle ID
    [[ "$lower" == "${app_lower}"[-_.]* ]]                    && echo "MED" && return
    [[ "$lower" == "${app_nospace}"[-_.]* ]]                  && echo "MED" && return
    if [ -n "$bid_lower" ]; then
        echo "$lower" | grep -qi "${bid_lower}" && echo "MED" && return
    fi

    echo "LOW"
}

confidence_color() {
    case "$1" in
        HIGH) echo -e "${GREEN}HIGH${NC}" ;;
        MED)  echo -e "${YELLOW}MED ${NC}" ;;
        LOW)  echo -e "${RED}LOW ${NC}" ;;
    esac
}

# ===================== SAFE TRASH-BASED DELETE =====================
safe_delete() {
    local item="$1"
    local base
    base=$(basename "$item")
    local dest="${TRASH_DIR}/${base}_$(date +%s)_$$"

    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${YELLOW}[DRY]${NC} Would trash: $(basename "$item")"
        return 0
    fi

    if mv "$item" "$dest" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $(basename "$item") → Trash"
        return 0
    elif sudo mv "$item" "$dest" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $(basename "$item") → Trash ${DIM}(sudo)${NC}"
        return 0
    else
        echo -e "  ${RED}✗${NC} Failed: $item"
        return 1
    fi
}

delete_items() {
    local deleted=0
    local failed=0

    echo ""
    [ "$DRY_RUN" = true ] && echo -e "  ${YELLOW}${BOLD}DRY-RUN — no files will be moved${NC}\n"

    for item in "$@"; do
        if safe_delete "$item"; then
            ((deleted++))
        else
            ((failed++))
        fi
    done

    echo ""
    divider
    echo -e "  ${GREEN}Processed: ${deleted}${NC}  |  ${RED}Failed: ${failed}${NC}"
    [ "$DRY_RUN" = false ] && echo -e "  ${DIM}Files are in Trash — ⌘+Z in Finder to undo${NC}"
    echo -e "  ${YELLOW}Tip:${NC} Check System Settings → General → Login Items"
}

# ===================== PKG RECEIPT =====================
cleanup_receipt() {
    local bid="${1:-}"
    [ -z "$bid" ] && return
    if pkgutil --pkgs 2>/dev/null | grep -qi "$bid"; then
        if [ "$DRY_RUN" = true ]; then
            echo -e "  ${YELLOW}[DRY]${NC} Would forget pkg: $bid"
        else
            sudo pkgutil --forget "$bid" 2>/dev/null && \
                echo -e "  ${GREEN}✓${NC} Removed pkg receipt: $bid" || true
        fi
    fi
}

# ===================== LIBRARY DIRECTORIES =====================
LIBRARY_DIRS=(
    "$HOME/Library/Application Support"
    "$HOME/Library/Caches"
    "$HOME/Library/Preferences"
    "$HOME/Library/Saved Application State"
    "$HOME/Library/Logs"
    "$HOME/Library/Containers"
    "$HOME/Library/Group Containers"
    "$HOME/Library/HTTPStorages"
    "$HOME/Library/WebKit"
    "$HOME/Library/Cookies"
    "$HOME/Library/LaunchAgents"
    "$HOME/Library/Application Scripts"
    "/Library/LaunchAgents"
    "/Library/LaunchDaemons"
    "/Library/Application Support"
    "/Library/Preferences"
)

# ===================== FILE DISCOVERY (uninstall mode — strict) =====================
find_leftovers() {
    local patterns=("$@")

    for dir in "${LIBRARY_DIRS[@]}"; do
        [ ! -d "$dir" ] && continue

        while IFS= read -r -d '' item; do
            local base
            base=$(basename "$item")
            local lower
            lower=$(echo "$base" | tr '[:upper:]' '[:lower:]')

            for p in "${patterns[@]}"; do
                local p_lower
                p_lower=$(echo "$p" | tr '[:upper:]' '[:lower:]')
                if matches_strict "$lower" "$p_lower"; then
                    if ! seen_add "$item"; then
                        echo "$item"
                    fi
                    break
                fi
            done
        done < <(find "$dir" -maxdepth 2 -mindepth 1 -print0 2>/dev/null)
    done
}

# ===================== INSTALLED APPS =====================
get_installed_apps() {
    for app in /Applications/*.app "$HOME"/Applications/*.app; do
        [ -d "$app" ] && basename "$app" .app
    done | sort -f | uniq
}

# ================================================================
#   SCAN → DISPLAY (grouped by confidence) → DELETE
# ================================================================
scan_and_delete() {
    local app_name="$1"
    local include_bundle="${2:-no}"

    local -a found=()
    seen_reset

    # Resolve .app path
    local app_path=""
    [ -d "/Applications/${app_name}.app" ]      && app_path="/Applications/${app_name}.app"
    [ -d "$HOME/Applications/${app_name}.app" ] && app_path="$HOME/Applications/${app_name}.app"

    # Search patterns: app name + bundle ID
    local -a patterns=("$app_name")
    local bundle_id=""
    if [ -n "$app_path" ]; then
        bundle_id=$(get_bundle_id "$app_path")
        [ -n "$bundle_id" ] && patterns+=("$bundle_id")
    fi

    echo ""
    echo -e "  ${CYAN}Target:${NC}     ${BOLD}${app_name}${NC}"
    [ -n "$bundle_id" ] && echo -e "  ${CYAN}Bundle ID:${NC}  ${bundle_id}"
    [ -n "$app_path" ]  && echo -e "  ${CYAN}Location:${NC}   ${app_path}"
    echo -e "  ${DIM}Scanning...${NC}"

    # Include .app bundle
    if [ "$include_bundle" = "yes" ] && [ -n "$app_path" ]; then
        found+=("$app_path")
        seen_add "$app_path"
    fi

    # Discover leftovers (strict matching)
    while IFS= read -r f; do
        [ -n "$f" ] && found+=("$f")
    done < <(find_leftovers "${patterns[@]}")

    if [ ${#found[@]} -eq 0 ]; then
        echo -e "\n  ${YELLOW}No files found for '${app_name}'.${NC}"
        return 1
    fi

    # Score confidence
    local -a confidences=()
    local high_count=0 med_count=0 low_count=0

    for f in "${found[@]}"; do
        local conf
        conf=$(get_confidence "$f" "$app_name" "$bundle_id")
        confidences+=("$conf")
        case "$conf" in
            HIGH) ((high_count++)) ;;
            MED)  ((med_count++)) ;;
            LOW)  ((low_count++)) ;;
        esac
    done

    # Build display order: HIGH → MED → LOW
    local -a display_order=()
    for conf_level in HIGH MED LOW; do
        for i in "${!found[@]}"; do
            [ "${confidences[$i]}" = "$conf_level" ] && display_order+=("$i")
        done
    done

    # Display grouped by confidence
    echo ""
    divider

    local display_num=1
    for conf_level in HIGH MED LOW; do
        local printed_header=false
        for i in "${!found[@]}"; do
            [ "${confidences[$i]}" != "$conf_level" ] && continue

            if [ "$printed_header" = false ]; then
                local clr
                case "$conf_level" in
                    HIGH) clr="${GREEN}" ;;
                    MED)  clr="${YELLOW}" ;;
                    LOW)  clr="${RED}" ;;
                esac
                echo -e "  ${clr}${BOLD}── ${conf_level} confidence ──${NC}"
                printed_header=true
            fi

            local size
            size=$(du -sh "${found[$i]}" 2>/dev/null | cut -f1)
            local label=""
            [[ "${found[$i]}" == *.app ]] && label=" ${CYAN}← app${NC}"

            printf "  ${GREEN}%3d.${NC} %-36s ${DIM}%6s${NC}  [$(confidence_color "${confidences[$i]}")]%b\n" \
                "$display_num" "$(basename "${found[$i]}")" "$size" "$label"
            ((display_num++))
        done
    done

    local total
    total=$(du -shc "${found[@]}" 2>/dev/null | tail -1 | cut -f1)
    echo ""
    divider
    echo -e "  ${BOLD}Found: ${#found[@]} items (${YELLOW}${total}${NC}${BOLD})${NC}"
    echo -e "  ${DIM}HIGH: ${high_count}  MED: ${med_count}  LOW: ${low_count}${NC}"
    echo ""

    # LOW items require explicit opt-in
    if [ $low_count -gt 0 ]; then
        echo -e "  ${DIM}(h) Trash HIGH+MED only  (a) Trash ALL  (s) Select  (n) Cancel${NC}"
    else
        echo -e "  ${DIM}(a) Trash all  (s) Select items  (n) Cancel${NC}"
    fi
    read -rp "  > " choice

    case "$choice" in
        h|H)
            local -a safe_items=()
            for i in "${!found[@]}"; do
                [ "${confidences[$i]}" != "LOW" ] && safe_items+=("${found[$i]}")
            done
            if [ ${#safe_items[@]} -gt 0 ]; then
                echo -e "\n  ${RED}Confirm: trash ${#safe_items[@]} HIGH+MED items?${NC}"
                read -rp "  Type 'yes': " confirm
                [ "$confirm" = "yes" ] && delete_items "${safe_items[@]}" && cleanup_receipt "$bundle_id"
            fi
            ;;
        a|A)
            echo -e "\n  ${RED}Confirm: trash ALL ${#found[@]} items (including LOW confidence)?${NC}"
            read -rp "  Type 'yes': " confirm
            [ "$confirm" = "yes" ] && delete_items "${found[@]}" && cleanup_receipt "$bundle_id"
            ;;
        s|S)
            echo -e "\n  ${CYAN}Enter numbers to trash (e.g., 1 3 5) or 'q':${NC}"
            read -rp "  > " selections
            [ "$selections" = "q" ] && return

            local -a to_delete=()
            for num in $selections; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#found[@]} ]; then
                    local real_idx="${display_order[$((num-1))]}"
                    to_delete+=("${found[$real_idx]}")
                else
                    echo -e "  ${YELLOW}Skipping invalid: ${num}${NC}"
                fi
            done

            if [ ${#to_delete[@]} -gt 0 ]; then
                delete_items "${to_delete[@]}"
                cleanup_receipt "$bundle_id"
            else
                echo -e "  ${YELLOW}Nothing selected.${NC}"
            fi
            ;;
        *)
            echo -e "\n  ${YELLOW}Cancelled.${NC}"
            ;;
    esac
}

# ================================================================
#   FEATURE 1 — Paginated App Browser + Search
# ================================================================
interactive_uninstall() {
    local -a apps=()
    while IFS= read -r line; do
        apps+=("$line")
    done < <(get_installed_apps)

    local total=${#apps[@]}

    if [ "$total" -eq 0 ]; then
        echo -e "  ${YELLOW}No apps found in /Applications.${NC}"
        press_enter
        return
    fi

    local page_size=15
    local page=0
    local max_page=$(( (total - 1) / page_size ))

    while true; do
        header
        echo -e "  ${BOLD}Installed Apps${NC} ${DIM}— ${total} total — Page $((page+1)) of $((max_page+1))${NC}"
        divider

        local start=$((page * page_size))
        local end=$((start + page_size))
        [ $end -gt $total ] && end=$total

        for ((i=start; i<end; i++)); do
            local num=$((i + 1))
            local apath="/Applications/${apps[$i]}.app"
            [ ! -d "$apath" ] && apath="$HOME/Applications/${apps[$i]}.app"
            local size=""
            size=$(du -sh "$apath" 2>/dev/null | cut -f1)
            printf "  ${GREEN}%3d.${NC} %-36s ${DIM}%s${NC}\n" "$num" "${apps[$i]}" "$size"
        done

        echo ""
        divider
        echo -e "  ${DIM}[#] Select  [n]ext  [p]rev  [/word] Search  [q] Back${NC}"
        read -rp "  > " input

        case "$input" in
            q|Q) return ;;
            n|N) [ $page -lt $max_page ] && ((page++)) ;;
            p|P) [ $page -gt 0 ] && ((page--)) ;;
            /*)
                local search_term="${input#/}"
                [ -z "$search_term" ] && read -rp "  Search: " search_term
                [ -n "$search_term" ] && search_apps "$search_term" "${apps[@]}"
                ;;
            *)
                if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le "$total" ]; then
                    local selected="${apps[$((input-1))]}"
                    header
                    echo -e "  ${BOLD}Uninstall: ${YELLOW}${selected}${NC}"
                    scan_and_delete "$selected" "yes"
                    press_enter

                    # Refresh
                    apps=()
                    while IFS= read -r line; do
                        apps+=("$line")
                    done < <(get_installed_apps)
                    total=${#apps[@]}
                    if [ "$total" -eq 0 ]; then
                        echo -e "  ${YELLOW}No apps remaining.${NC}"
                        press_enter
                        return
                    fi
                    max_page=$(( (total - 1) / page_size ))
                    [ $page -gt $max_page ] && page=$max_page
                else
                    echo -e "  ${RED}Invalid selection.${NC}"
                    sleep 0.8
                fi
                ;;
        esac
    done
}

search_apps() {
    local term="$1"
    shift
    local -a all_apps=("$@")
    local -a matches=()

    for app in "${all_apps[@]}"; do
        echo "$app" | grep -qi "$term" && matches+=("$app")
    done

    if [ ${#matches[@]} -eq 0 ]; then
        echo -e "\n  ${YELLOW}No apps matching '${term}'.${NC}"
        sleep 1.5
        return
    fi

    header
    echo -e "  ${BOLD}Search: ${YELLOW}${term}${NC} ${DIM}— ${#matches[@]} results${NC}"
    divider

    local i=1
    for app in "${matches[@]}"; do
        local apath="/Applications/${app}.app"
        [ ! -d "$apath" ] && apath="$HOME/Applications/${app}.app"
        local size=""
        size=$(du -sh "$apath" 2>/dev/null | cut -f1)
        printf "  ${GREEN}%3d.${NC} %-36s ${DIM}%s${NC}\n" "$i" "$app" "$size"
        ((i++))
    done

    echo ""
    echo -e "  ${DIM}[#] Select  [q] Back${NC}"
    read -rp "  > " pick

    if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le ${#matches[@]} ]; then
        local selected="${matches[$((pick-1))]}"
        header
        echo -e "  ${BOLD}Uninstall: ${YELLOW}${selected}${NC}"
        scan_and_delete "$selected" "yes"
        press_enter
    fi
}

# ================================================================
#   FEATURE 2 — Orphan File Scanner (conservative exclusion)
# ================================================================
scan_orphans() {
    header
    echo -e "  ${BOLD}Orphan File Scanner${NC}"
    echo -e "  ${DIM}Detects leftover files from apps you've already removed.${NC}"
    echo ""
    echo -e "  ${DIM}Building installed app index...${NC}"

    # Build comprehensive known-token list from all installed apps
    build_known_tokens

    local token_count
    token_count=$(wc -l < "$KNOWN_TOKENS_FILE" | tr -d ' ')
    echo -e "  ${DIM}Indexed ${token_count} tokens from installed apps${NC}"

    # System patterns — always skip (never flag as orphans)
    # These go in a separate list since they're not "installed apps"
    local -a system_skip=(
        "apple" "com.apple" "icloud" "mobileme"
        "finder" "safari" "dock" "spotlight"
        "systemuiserver" "loginwindow" "kernel" "launchd"
        "notificationcenter" "airplay" "bluetooth"
        "coreservices" "webkit" "appstore" "softwareupdate"
        "screensaver" "cloudkit" "cloudd" "gamed" "gamekit"
        "knowledge" "siri" "assistant" "diagnostics"
        "addressbook" "calendar" "mail" "maps" "messages"
        "music" "news" "notes" "photos" "podcasts" "reminders"
        "stocks" "tv" "weather" "xcode" "instruments"
        "sharedfilelist" "group.com" "systempreferences"
        "coredata" "corespotlight" "networkextension"
        "swift" "objective-c" "llvm" "clang"
    )

    local scan_dirs=(
        "$HOME/Library/Application Support"
        "$HOME/Library/Caches"
        "$HOME/Library/Saved Application State"
        "$HOME/Library/HTTPStorages"
        "$HOME/Library/Containers"
        "$HOME/Library/Group Containers"
        "$HOME/Library/Logs"
    )

    local -a orphans=()
    local -a orphan_sources=()
    local scanned=0
    local excluded=0

    for dir in "${scan_dirs[@]}"; do
        [ ! -d "$dir" ] && continue
        local dir_label
        dir_label=$(basename "$dir")

        for item in "$dir"/*/; do
            [ ! -d "$item" ] && continue
            ((scanned++))
            printf "\r  Scanned: %d items (excluded: %d)..." "$scanned" "$excluded"

            local bname
            bname=$(basename "$item")
            local lower
            lower=$(echo "$bname" | tr '[:upper:]' '[:lower:]')

            # ---- Check 1: system patterns (fast, no file I/O) ----
            local matched=0
            for sp in "${system_skip[@]}"; do
                if [[ "$lower" == "$sp" ]] || \
                   [[ "$lower" == "$sp".* ]] || \
                   [[ "$lower" == *".$sp" ]] || \
                   [[ "$lower" == *".$sp".* ]]; then
                    matched=1; break
                fi
            done
            if [ $matched -eq 1 ]; then
                ((excluded++))
                continue
            fi

            # ---- Check 2: known token match (conservative) ----
            if matches_any_known_token "$lower"; then
                ((excluded++))
                continue
            fi

            # ---- Check 3: Skip tiny items (<100KB) ----
            local size_kb
            size_kb=$(du -sk "$item" 2>/dev/null | cut -f1)
            [ "${size_kb:-0}" -lt 100 ] && continue

            orphans+=("$item")
            orphan_sources+=("$dir_label")
        done
    done

    printf "\r                                                    \r"

    if [ ${#orphans[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✓ No significant orphans found — system is clean!${NC}"
        echo -e "  ${DIM}Scanned: ${scanned} items, excluded: ${excluded}${NC}"
        press_enter
        return
    fi

    echo -e "  ${YELLOW}Found ${#orphans[@]} potential orphans${NC} ${DIM}(scanned: ${scanned}, excluded: ${excluded})${NC}"
    echo ""
    divider

    local total_kb=0
    for ((i=0; i<${#orphans[@]}; i++)); do
        local size
        size=$(du -sh "${orphans[$i]}" 2>/dev/null | cut -f1)
        local kb
        kb=$(du -sk "${orphans[$i]}" 2>/dev/null | cut -f1)
        total_kb=$((total_kb + kb))

        printf "  ${GREEN}%3d.${NC} %-34s ${DIM}%6s  (%s)${NC}\n" \
            "$((i+1))" "$(basename "${orphans[$i]}")" "$size" "${orphan_sources[$i]}"
    done

    local total_human
    if [ $total_kb -gt 1048576 ]; then
        total_human=$(awk "BEGIN {printf \"%.1f GB\", $total_kb/1048576}")
    elif [ $total_kb -gt 1024 ]; then
        total_human=$(awk "BEGIN {printf \"%.1f MB\", $total_kb/1024}")
    else
        total_human="${total_kb} KB"
    fi

    echo ""
    divider
    echo -e "  ${BOLD}Reclaimable: ${YELLOW}${total_human}${NC}"
    echo ""
    echo -e "  ${YELLOW}${BOLD}⚠  Review carefully before deleting.${NC}"
    echo -e "  ${DIM}(s) Select items  (a) Trash all  (n) Cancel${NC}"
    read -rp "  > " choice

    case "$choice" in
        a|A)
            echo -e "\n  ${RED}Confirm: trash ALL ${#orphans[@]} orphan items?${NC}"
            read -rp "  Type 'yes': " confirm
            if [ "$confirm" = "yes" ]; then
                delete_items "${orphans[@]}"
            else
                echo -e "\n  ${YELLOW}Cancelled.${NC}"
            fi
            ;;
        s|S)
            echo -e "\n  ${CYAN}Enter numbers (e.g., 1 3 5) or 'q':${NC}"
            read -rp "  > " selections
            [ "$selections" = "q" ] && press_enter && return

            local -a to_delete=()
            for num in $selections; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#orphans[@]} ]; then
                    to_delete+=("${orphans[$((num-1))]}")
                fi
            done
            [ ${#to_delete[@]} -gt 0 ] && delete_items "${to_delete[@]}"
            ;;
        *)
            echo -e "\n  ${YELLOW}Cancelled.${NC}"
            ;;
    esac

    press_enter
}

# ================================================================
#   MAIN MENU
# ================================================================
main_menu() {
    while true; do
        header
        echo -e "  ${BOLD}Choose an option:${NC}"
        echo ""
        echo -e "  ${GREEN}1.${NC}  Browse & uninstall an app"
        echo -e "  ${GREEN}2.${NC}  Scan for orphan files"
        echo -e "  ${GREEN}3.${NC}  Quick uninstall by name"
        echo -e "  ${GREEN}q.${NC}  Quit"
        echo ""
        if [ "$DRY_RUN" = true ]; then
            echo -e "  ${YELLOW}${BOLD}⚠  DRY-RUN active — nothing will be deleted${NC}"
            echo ""
        fi
        divider
        read -rp "  > " choice

        case "$choice" in
            1) interactive_uninstall ;;
            2) scan_orphans ;;
            3)
                echo ""
                read -rp "  App name: " app_name
                if [ -n "$app_name" ]; then
                    header
                    local has_bundle="no"
                    if [ -d "/Applications/${app_name}.app" ] || \
                       [ -d "$HOME/Applications/${app_name}.app" ]; then
                        has_bundle="yes"
                    fi
                    scan_and_delete "$app_name" "$has_bundle"
                    press_enter
                fi
                ;;
            q|Q)
                echo ""
                echo -e "  ${GREEN}Done. Your Mac thanks you.${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "  ${RED}Invalid.${NC}"
                sleep 0.8
                ;;
        esac
    done
}

# ===================== ENTRY =====================
main_menu
