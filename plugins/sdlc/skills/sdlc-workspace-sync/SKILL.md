---
name: sdlc-workspace-sync
description: Scan the workspace directory and git-update all repositories
---

# /sdlc-workspace-sync

Discover all git repositories in the current workspace directory and update
them. Runs the `workspace-sync.sh` script under the hood.

## Input

$ARGUMENTS — Optional mode flag:

- No arguments — pull latest changes on every repo (default)
- `--fetch-only` — fetch from remotes without merging
- `--status` — show branch and dirty-file status only (no network)

## Procedure

### 1. Run the sync script

Execute the workspace-sync script with any flags passed through:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/workspace-sync.sh $ARGUMENTS
```

### 2. Display the output

Show the full output from the script to the user exactly as printed.
The script produces a formatted table with color codes for the terminal.

### 3. Suggest next steps

After the output, if any repos show:

- **DIRTY** — suggest: "Some repos have uncommitted changes. Commit or stash
  them before pulling."
- **FAIL** — suggest: "Some repos failed to update. Check for merge conflicts
  or network issues."
- All **OK** — say: "All repositories are up to date."

## Important

- This skill is **read-only** when using `--status`.
- In default (pull) mode it runs `git pull --rebase` on clean repos.
- It skips dirty repos automatically to avoid conflicts.
- It does NOT require `.claude/settings.local.json` — it scans the filesystem directly.
