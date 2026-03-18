# mac-toolbox

A collection of **zero-dependency macOS utilities** that replace paid apps like CleanMyMac, AppCleaner, iStat Menus, and OnyX — entirely from the terminal.

Every tool is a single bash script. No Homebrew, no Python, no Node. Just `chmod +x` and run.

![Bash](https://img.shields.io/badge/bash-3.2%2B-blue?logo=gnu-bash&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-10.15%2B-000000?logo=apple&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)
![Tools](https://img.shields.io/badge/tools-10-orange)

---

## Quick Start

```bash
git clone https://github.com/tejinder-gh/mac-toolbox.git
cd mac-toolbox

# Interactive menu — see all tools, pick one
./mac-toolbox

# Install the 'mactool' alias (one-time setup)
./mac-toolbox install
source ~/.zshrc         # or restart terminal

# Now use from anywhere
mactool disk --hogs     # Where's my disk space going?
mactool uninstall       # Remove apps completely
mactool dev             # Free GBs from node_modules etc.
```

Every tool supports `--dry-run` where applicable — preview before you commit.

---

## The Tools

### Cleanup & Storage

| Tool | Replaces | What It Does |
|---|---|---|
| **[uninstall.sh](#uninstallsh)** | AppCleaner, AppZapper | Remove apps + all hidden Library leftovers. Orphan scanner finds files from already-deleted apps. |
| **[diskmap.sh](#diskmapsh)** | DaisyDisk, OmniDiskSweeper | Interactive disk breakdown with drill-down. Detects known space hogs (Xcode, npm, Docker, browser caches). |
| **[dupes.sh](#dupessh)** | Gemini 2 | Find duplicate files via multi-pass hashing (size → partial → full). Quick Look preview. |
| **[dev-clean.sh](#dev-cleansh)** | — | Scans for `node_modules`, `DerivedData`, `build/`, `target/`, `__pycache__`, `.venv` etc. Stale project detection. |
| **[brew-doctor.sh](#brew-doctorsh)** | — | Homebrew hygiene: orphan deps, ghost casks, cache cleanup, broken symlinks. |

### System Management

| Tool | Replaces | What It Does |
|---|---|---|
| **[launchctl-manager.sh](#launchctl-managersh)** | Lingon, iStat Menus | List/disable/remove launch agents & daemons. Safety classification (Apple vs third-party). Backup before removal. |
| **[defaults-manager.sh](#defaults-managersh)** | TinkerTool, OnyX | Curated macOS hidden preferences. Toggle Finder, Dock, Screenshot, Safari tweaks. Backup/restore. |
| **[privacy-audit.sh](#privacy-auditsh)** | — | Audit all privacy permissions (Camera, Mic, Screen Recording, etc.). Flags removed apps that still hold permissions. |

### Diagnostics

| Tool | Replaces | What It Does |
|---|---|---|
| **[battery.sh](#batterysh)** | coconutBattery, iStat | Battery health, cycle count, power-hungry process detection, live charge monitor. |
| **[netcheck.sh](#netchecksh)** | WiFi Explorer, iStatistica | WiFi signal strength, DNS benchmark, ping latency, active connections, bandwidth estimate. |
| **[update-prep.sh](#update-prepsh)** | — | Pre-update checklist: disk space, kernel extensions, 32-bit apps, Time Machine, config backup. |

---

## Tool Details

### uninstall.sh

The most complete app uninstaller. Reads bundle IDs from `Info.plist`, scans 16 Library directories, and uses confidence scoring to prevent false positives.

```bash
./uninstall.sh              # Interactive menu
./uninstall.sh --dry-run    # Preview mode
```

**Key features:** Dual matching strategy (strict for uninstall, conservative for orphan exclusion), token-based orphan detection, trash-based deletion (⌘+Z to undo), confidence scoring (HIGH/MED/LOW).

### diskmap.sh

Find what's eating your disk. Interactive drill-down with visual size bars, plus a known-hogs scanner that finds Xcode caches, `node_modules`, browser caches, Homebrew downloads, and more.

```bash
./diskmap.sh                # Analyze home directory
./diskmap.sh /path          # Analyze specific path
./diskmap.sh --hogs         # Known space hogs only
./diskmap.sh --dry-run      # Preview cleanup
```

### dupes.sh

Three-pass duplicate detection: file size grouping (instant), partial hash of first 4KB (fast), full MD5 only for confirmed candidates (accurate). Quick Look preview support.

```bash
./dupes.sh                  # Scan home directory
./dupes.sh ~/Downloads      # Scan specific path
./dupes.sh --min-size 1M    # Skip files under 1MB
```

### dev-clean.sh

Purpose-built for developers. Finds and cleans build artifacts across Node, Python, Rust, Java, Swift, Flutter, and more. Flags stale projects (>90 days untouched).

```bash
./dev-clean.sh              # Full artifact scan
./dev-clean.sh --stale-days 60  # Custom staleness threshold
```

**Artifact types:** `node_modules`, `.next`, `dist`, `build`, `__pycache__`, `.tox`, `.venv`, `venv`, `.pytest_cache`, `target/`, `.gradle`, `.dart_tool`, `Pods`, `DerivedData`

### brew-doctor.sh

Keeps Homebrew lean. Detects orphaned formulae, ghost casks (app deleted but still in `brew list`), stale cache, broken symlinks, outdated packages.

```bash
./brew-doctor.sh            # Health report + cleanup
./brew-doctor.sh --dry-run
```

*Requires Homebrew installed.*

### launchctl-manager.sh

See everything that runs at startup — not just what System Settings shows. Lists all launch agents/daemons with load status, owning app, and safety classification. Backs up plists before removal.

```bash
./launchctl-manager.sh
./launchctl-manager.sh --dry-run
```

**Safety:** Apple agents require typing `yes-apple` to disable. Third-party agents are backed up to `~/.mac-toolbox-backups/` before removal. Restore function included.

### defaults-manager.sh

Curated, verified `defaults write` tweaks organized by category. Shows current value of each setting, lets you toggle individually or batch-apply. Backup and restore all customizations.

```bash
./defaults-manager.sh
./defaults-manager.sh --backup
./defaults-manager.sh --restore <file>
```

**Categories:** Finder, Dock, Screenshots, Safari, Typing & Input, Security & Privacy.

### privacy-audit.sh

Reads the TCC database to show every app that has been granted privacy permissions. Flags apps that have been uninstalled but still hold permissions (Camera, Microphone, Screen Recording, etc.). Includes a security quick-check (FileVault, Firewall, SIP, Gatekeeper).

```bash
./privacy-audit.sh
```

### battery.sh

Battery health dashboard for MacBooks. Shows cycle count, max capacity, condition, current charge, power source, and health tips. Identifies power-hungry processes. Live charge monitor mode.

```bash
./battery.sh
```

*MacBooks only — exits gracefully on desktops.*

### netcheck.sh

Network diagnostics without installing anything. WiFi signal strength and SNR, DNS resolution speed benchmarks, ping latency to multiple targets, active connection summary, and a rough bandwidth estimate.

```bash
./netcheck.sh
```

### update-prep.sh

Run before any major macOS update. Checks disk space (need ~35GB), SIP status, Time Machine freshness, kernel extensions, 32-bit apps, and login items. Optionally backs up shell configs, SSH key listings, Homebrew package lists, and app preferences.

```bash
./update-prep.sh
```

---

## Security Principles

Every tool in this collection follows these principles:

1. **Trash over rm.** Destructive tools move to `~/.Trash`, not `rm -rf`. Recoverable via ⌘+Z.
2. **Dry-run by default mindset.** All destructive tools support `--dry-run`. Documentation encourages running it first.
3. **Explicit confirmation.** Bulk deletions require typing `yes`, not just `y`.
4. **No network home.** No tool phones home, sends telemetry, or downloads anything (except `netcheck.sh` which makes standard network requests to measure connectivity).
5. **Read-only diagnostics.** Diagnostic tools (`battery.sh`, `netcheck.sh`, `privacy-audit.sh`) never modify system state.
6. **Backup before destroy.** `launchctl-manager.sh` backs up plists before removal. `defaults-manager.sh` has backup/restore. `update-prep.sh` backs up configs.
7. **Apple protection.** `launchctl-manager.sh` requires a special confirmation string (`yes-apple`) before touching Apple system agents. `privacy-audit.sh` never modifies the TCC database.
8. **No SIP bypass.** Nothing in this toolkit attempts to circumvent System Integrity Protection.
9. **Minimal sudo.** `sudo` is only used per-file when standard permissions fail (system-level LaunchDaemons, etc.), never blanket at script start.
10. **bash 3.2 compatible.** No `mapfile`, no associative arrays, no bash 4+ features. Works on stock macOS.

---

## Requirements

- macOS 10.15 (Catalina) or later
- bash 3.2+ (ships with macOS)
- `brew-doctor.sh` requires Homebrew (all others are zero-dependency)

---

## Installation

```bash
# Clone the repo
git clone https://github.com/tejinder-gh/mac-toolbox.git
cd mac-toolbox

# One-command setup: makes tools executable + adds 'mactool' alias
./mac-toolbox install

# Activate in current session
source ~/.zshrc    # or ~/.bash_profile for bash users
```

This does two things:
1. Adds `alias mactool='/path/to/mac-toolbox/mac-toolbox'` to your shell config
2. Adds `tools/` to your `PATH` so individual scripts work directly too

**After install, three ways to use:**

```bash
# 1. Unified CLI with short names
mactool disk --hogs
mactool uninstall --dry-run
mactool dev

# 2. Interactive menu (no args)
mactool

# 3. Run scripts directly (they're in PATH)
diskmap.sh --hogs
uninstall.sh --dry-run
```

**Uninstall the alias:**
```bash
./mac-toolbox uninstall-alias
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Key rules:

- bash 3.2 compatibility is non-negotiable
- Destructive actions must be trash-based with dry-run support
- Test on real macOS with `/bin/bash`, not Homebrew bash
- New tools should follow the existing interactive menu pattern

---

## License

[MIT](LICENSE)

---

*10 tools. Zero dependencies. Your Mac, under your control.*
# mac-toolbox
