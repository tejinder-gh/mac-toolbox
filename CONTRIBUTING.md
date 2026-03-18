# Contributing

Thanks for your interest in improving mac-toolbox. Here's how to contribute effectively.

## Ground Rules

1. **bash 3.2 compatibility is non-negotiable.** macOS ships with bash 3.2. Do not use `mapfile`, `declare -A` (associative arrays), `readarray`, `${var,,}` (lowercase expansion), `|&` (pipe stderr), or any bash 4+ features.

2. **Safety first.** This script handles file deletion. Every change must preserve:
   - Trash-based deletion (never `rm -rf`)
   - Dry-run mode support
   - Confirmation prompts before destructive actions
   - The dual matching strategy (strict for uninstall, conservative for orphan exclusion)

3. **Test on real macOS.** Docker or Linux doesn't count — Library paths, `PlistBuddy`, `pkgutil`, and bash 3.2 behavior differ.

## Development Setup

```bash
# Clone
git clone https://github.com/YOUR_USERNAME/mac-app-uninstaller.git
cd mac-app-uninstaller

# Always test with system bash (3.2), not Homebrew bash
/bin/bash tools/*.sh --dry-run
```

## Testing Checklist

Before submitting a PR, verify:

- [ ] `--dry-run` shows expected output, zero files touched
- [ ] Browse mode: pagination works, search works, selection works
- [ ] Orphan scanner: does NOT flag files belonging to installed apps
- [ ] Quick uninstall: works for installed app, works for already-removed app
- [ ] Multi-word app names work ("Google Chrome", "Visual Studio Code")
- [ ] Apps with unusual bundle IDs work (e.g., Slack = `com.tinyspeck.slackmacgap`)
- [ ] Runs without errors under `/bin/bash` (not `/usr/local/bin/bash`)
- [ ] No `shellcheck` errors (install via `brew install shellcheck`)

```bash
# Run shellcheck
shellcheck -s bash tools/*.sh
```

## Pull Request Process

1. Fork and create a feature branch: `git checkout -b feature/my-change`
2. Make your changes
3. Run through the testing checklist above
4. Write a clear PR description explaining what changed and why
5. Reference any related issues

## What to Contribute

### High Impact
- Additional Library paths that apps use (with examples of which apps)
- Better orphan detection heuristics
- Homebrew Cask integration (detect `brew`-installed apps)
- Performance improvements for large Library scans

### Medium Impact
- Better terminal UI (but keep it bash 3.2 compatible — no `tput` dependency)
- Export scan results to a file
- Undo log (record what was trashed for bulk restore)

### Reporting Issues
- Include macOS version and `bash --version` output
- Include the app name that triggered the issue
- If orphan scanner flagged an installed app: include the app's bundle ID (`mdls -name kMDItemCFBundleIdentifier /Applications/AppName.app`)
- Use `--dry-run` output to show what would have been deleted

## Code Style

- 4-space indentation
- Functions named with `snake_case`
- Variables in `UPPER_CASE` for globals, `lower_case` for locals
- Always declare locals with `local`
- Quote all variable expansions: `"$var"` not `$var`
- Use `[[ ]]` for conditionals, not `[ ]` (bash-specific is fine since we require bash)
