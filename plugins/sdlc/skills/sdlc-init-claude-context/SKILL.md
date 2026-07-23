---
name: sdlc-init-claude-context
description: Generate CLAUDE.md and ARCHITECTURE.md for one, many, or all repositories in .claude/settings.local.json
disable-model-invocation: true
---

# /sdlc-init-claude-context

Generate `CLAUDE.md` and `ARCHITECTURE.md` for repositories so that all other
skills and agents have the context they need to work effectively. Supports
single repos, multiple repos, or all repos at once using parallel sub-agents.

## Input

$ARGUMENTS — One of:
- A single repository name (e.g. `api-gateway`)
- Multiple repository names separated by spaces (e.g. `api-gateway commerce-service`)
- `--all` to process every repository defined in `.claude/settings.local.json` under the `sdlc` key
- No arguments — equivalent to `--all`

## Procedure

### Phase 1 — Resolve target repositories

1. **Read `.claude/settings.local.json`** from the project root. Read the `sdlc` config key
   and extract the full list of repositories.

2. **Determine which repos to process:**
   - If `$ARGUMENTS` is `--all` or empty: use all repositories.
   - Otherwise: match each argument against repository names. Abort with an
     error if any name is not found in `.claude/settings.local.json`.

3. **Verify each target repo exists on disk.** If a repo directory does not
   exist, skip it and warn: "Skipping `<name>` — directory `<path>` not found.
   Clone it first."

### Phase 2 — Check existing files (sequential)

4. **For each target repository**, check for existing CLAUDE.md files:

   a. **If `<repo-path>/CLAUDE.md` exists at the root** (legacy location):
      - Read its contents.
      - Tell the user: "I found a `CLAUDE.md` at the root of `<name>`. Claude
        Code now reads project instructions from `.claude/CLAUDE.md` instead.
        I recommend moving it there."
      - Ask the user to choose:
        1. **Move and update** — pass the existing content to the agent for
           merging with new scan findings, then delete the root file.
        2. **Move as-is** — move the existing file to
           `<repo-path>/.claude/CLAUDE.md` without scanning, and delete the
           root file. Skip this repo in Phase 3.
        3. **Keep both** — generate a new `.claude/CLAUDE.md` and leave the
           root file untouched.
      - Record the user's choice for this repo.

   b. **If `<repo-path>/.claude/CLAUDE.md` already exists** (current location):
      - Ask the user whether to **overwrite** or **skip** this repo.

   c. **If neither exists**, mark this repo for scanning.

   When processing multiple repos, batch these questions: show the status of
   all repos first, then ask for a single decision if they all have the same
   situation (e.g. "3 repos have no CLAUDE.md — proceed with all?"), or ask
   per-repo if situations differ.

### Phase 3 — Scan repositories via codebase-scanner agent

5. **For each repo that needs scanning**, spawn a `codebase-scanner` agent using
   the Agent tool. **Always use the agent, even for a single repository.** This
   ensures consistent output format and quality regardless of how many repos are
   being processed.

   - **One repo**: spawn a single `codebase-scanner` agent.
   - **Multiple repos**: spawn all `codebase-scanner` agents **in a single message**
     so they execute concurrently.

   Each agent receives:
   - **Repository path**: the absolute path to the repo
   - **Repository name**: for headings
   - **Target directory**: `<repo-path>/.claude/`
   - **Existing content** (if the user chose "Move and update" in step 4a):
     the contents of the legacy CLAUDE.md to merge with

   The agent will:
   - Scan the codebase
   - Generate `CLAUDE.md` (max 60 lines, concise and actionable)
   - Generate `ARCHITECTURE.md` (max 150 lines)
   - Write both files to the target directory

   Example prompt for each agent:

   > You are the codebase-scanner agent. Scan the repository at `<repo-path>`
   > (named `<name>`) and generate CLAUDE.md and ARCHITECTURE.md in
   > `<repo-path>/.claude/`. [If merging: "Here is the existing CLAUDE.md
   > content to merge with: ..."]

### Phase 4 — Cleanup and report

6. **For repos where the user chose "Move and update" or "Move as-is"**,
   delete the old `<repo-path>/CLAUDE.md` file.

7. **Display a summary table:**

   ```
   Repository          CLAUDE.md              ARCHITECTURE.md        Migration
   ──────────────────────────────────────────────────────────────────────────────
   api-gateway         Created                Created                —
   commerce-service    Updated (merged)       Created                Root → .claude/
   web-app             Skipped (user choice)  Skipped (user choice)  —
   ```

8. **Report any issues** — repos that were skipped, gaps flagged by agents,
   or areas needing manual review.

## Important

- **Always use the agent**: Every repo scan MUST go through the `codebase-scanner`
  agent — even when processing a single repository. Never scan or generate files
  inline. This guarantees consistent output regardless of whether the user runs
  `/sdlc-init-claude-context api-gateway` or `/sdlc-init-claude-context --all`.
- **Parallelism**: When scanning multiple repos, spawn all `codebase-scanner`
  agents in a single message so they run concurrently.
- **Agent delegation**: All codebase scanning and file generation is done by the
  `codebase-scanner` agent. This skill handles orchestration, user interaction, and
  migration logic only.
- **Target location**: Always `<repo-path>/.claude/CLAUDE.md` and
  `<repo-path>/.claude/ARCHITECTURE.md`. Create the `.claude/` directory if it
  does not exist.
- **No invented information**: Agents must use only facts observed in the
  codebase. Anything unclear should be omitted, not guessed.
- **Legacy migration**: If a root-level `CLAUDE.md` exists, always inform the
  user and recommend migration to `.claude/CLAUDE.md`.
