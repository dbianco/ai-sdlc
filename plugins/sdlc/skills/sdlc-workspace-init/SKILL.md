---
name: sdlc-workspace-init
description: Interactive setup wizard that configures .claude/settings.local.json, creates .claude/CLAUDE.md, and verifies MCP connectivity
---

# /sdlc-workspace-init

Interactive setup wizard for configuring your workspace. Walks through
`.claude/settings.local.json` to fill in missing values under the `sdlc` key,
ensures `.claude/CLAUDE.md` exists with a Lessons Learned section,
verifies MCP connectivity (Jira/Linear, Notion, Figma, Playwright), and reports a
summary of your workspace status.

This skill is **idempotent** — run it as many times as you want. It only asks
about fields that are missing or still using placeholder values. It always
reports MCP status and a full workspace summary.

## Input

$ARGUMENTS — Optional mode flag:

- No arguments — run the guided wizard normally (default)
- `--switch-mode` — re-open the artifact store choice (Phase 0) even though
  `sdlc.mode` is already set, to deliberately move between Notion + Jira/Linear
  and local files

## Procedure

### Phase 0 — Locate the Workspace and Choose the Artifact Store

0.0. **Check for an ancestor workspace before creating anything.** Walk up
     from the project root one directory at a time and test whether
     `<ancestor>/.claude/settings.local.json` exists and contains an `sdlc`
     key. **Stop before `$HOME`** — `~/.claude/settings.local.json` is
     user-scope Claude Code config, not a workspace, and must never be
     treated as an ancestor workspace.

     **If no ancestor workspace is found**, continue to 0.1 normally. This is
     the common case.

     **If an ancestor workspace is found**, stop and ask before writing
     anything. Creating a `.claude/settings.local.json` here would shadow the
     ancestor's config for every session started in this directory — its
     repository list, PR size limits, mode, and Snyk tool permissions would
     all silently stop applying, with no warning at the point of use. A repo
     nested inside a workspace is exactly where people naturally start a
     session, so this is easy to hit by accident.

     Ask with `AskUserQuestion`, naming the ancestor path and its workspace
     name: "`<ancestor path>` is already an SDLC workspace
     (`<workspace name>`), and this directory sits inside it."

     - **Register this repo in `<workspace name>`** (the default, and almost
       always correct) — add an entry to the ancestor's `sdlc.repositories`
       (`name` = this directory's name, `path` = this directory relative to
       the ancestor root), leave every other ancestor setting untouched, and
       create nothing here. This is a purely additive one-line change: apply
       it per the write rules in Phase 2.3, report what was added, and stop.
       The remaining phases do not run — they describe the ancestor
       workspace, which is already configured.
     - **Make this a separate workspace** — run the full wizard from Phase
       0.1. Say plainly: "Sessions started in this directory will use this
       config instead of `<workspace name>`'s, and the two will not stay in
       sync."

     If this directory is already listed in the ancestor's
     `sdlc.repositories`, say so and report that instead of adding a
     duplicate entry.

     Never create a nested workspace silently, and never pick either option
     for the user.

0.1. **Decide whether this phase runs at all.** Read
     `.claude/settings.local.json` first and classify the workspace into
     exactly one of these four cases:

     a. **`sdlc.mode` is already set and the skill was invoked without
        `--switch-mode`** — skip this phase. Do not re-ask on every ordinary
        run.

     b. **`sdlc.mode` is absent, but `sdlc.linear.team` and
        `sdlc.notion.home_directory` both already hold real, non-placeholder
        values** (same placeholder rules as Phase 1.2) — this workspace was
        configured before modes existed and is already running against Notion
        and Jira/Linear. Its mode is not an open question. Persist
        `"mode": "remote"` to `.claude/settings.local.json` (read-modify-write,
        per Phase 2.3), tell the user only that the existing Notion + Jira/Linear
        setup was kept, and **skip the rest of this phase**. Ask nothing.
        Probe nothing — a transient Notion or Jira/Linear auth failure must never
        turn into a recommendation to abandon a working remote workspace.

        The one exception: if `--switch-mode` was passed, still persist
        `"mode": "remote"` as the workspace's current value, then continue
        with this phase so the user can deliberately move off it. Phase 0.4
        compares against that value.

     c. **`sdlc.mode` is absent and the workspace is not already configured
        for Notion + Jira/Linear** (either of those two values missing or still a
        placeholder) — the genuine first run. Proceed with this phase
        regardless of how the skill was invoked. `--switch-mode` is redundant
        here and changes nothing: there is no previous mode to switch away
        from, so the phase behaves exactly as it does without the flag and
        Phase 0.4 has nothing to report.

     d. **`sdlc.mode` is already set and the skill was invoked with
        `--switch-mode`** — proceed with this phase to let the user pick a new
        mode. Phase 0.4 covers what to tell them once they do.

0.2. **Ask where SDLC artifacts should live**, using `AskUserQuestion`:

     "Where should this workspace keep its PRDs, Scoping Docs, Jot Downs, and
     tasks?"

     - **Notion + Jira/Linear** — documents become Notion pages and tasks become
       Jira/Linear issues. Requires a Notion workspace and a Jira/Linear team.
     - **Local files** — everything is markdown under `.sdlc/` in this
       workspace. No external accounts, no setup. You can switch later by
       running `/sdlc:sdlc-workspace-init --switch-mode`.

     Write the answer to `sdlc.mode` as `"remote"` or `"local"` respectively,
     and **persist it to `.claude/settings.local.json` immediately** — before
     Phase 1 runs. Create `.claude/` and the file first if they do not exist,
     using the default structure in Phase 1.1, and otherwise read-modify-write
     per Phase 2.3. Every later phase decides what to do by reading
     `sdlc.mode`, so a choice held only in memory can be overwritten by
     Phase 1.1's default.

0.3. **Recommend local mode only on evidence of an actual reachability
     failure — never on absence of configuration.** Before asking, check
     whether `sdlc.linear.team` and `sdlc.notion.home_directory` already
     hold real (non-placeholder) values in `.claude/settings.local.json`,
     using the same placeholder rules as Phase 1.2. If the file or either
     key does not exist yet, that also counts as "not yet configured."

     - **If either value is missing or still a placeholder** (the normal
       first-run case): do NOT probe anything — nothing is configured yet,
       so a reachability check would tell you nothing. Present the two
       options neutrally: "Nothing is configured yet. Local files work
       immediately with no accounts; Notion + Jira/Linear needs a Notion
       workspace and a Jira/Linear team you can point me at."

     - **Only if both `linear.team` and `notion.home_directory` already
       hold real values** — which, given Phase 0.1 case (b), means the user
       explicitly asked to reconsider with `--switch-mode` — attempt the
       Jira/Linear and Notion checks described
       in Phase 5. If either fails, present **Local files** as the
       recommended option and say precisely which one failed — e.g.
       "Jira/Linear is configured but not reachable from this session," or
       "Notion is configured but not reachable from this session." Never
       state or imply that a tool is unreachable when the true condition is
       that it is unconfigured.

     Never silently choose for the user — recommend, then let them answer.

0.4. **If `--switch-mode` was used and the answer actually changes `sdlc.mode`**
     from its previous value, tell the user plainly what does and does not
     move:

     - **`local` → `remote`:** "Your existing `.sdlc/` artifacts stay on disk.
       They are not copied to Notion or Jira/Linear — there is no migration. New
       documents will be created in Notion from now on."
     - **`remote` → `local`:** "Your existing Notion pages and Jira/Linear issues
       stay where they are. They are not copied into `.sdlc/` — there is no
       migration. New documents will be written to `.sdlc/` from now on."

     If `--switch-mode` was used but the user re-selects the same mode they
     already had, no migration note is needed — nothing changed.

     If `--switch-mode` was used on a genuine first run (Phase 0.1 case (c)),
     there is no previous value to compare against and no migration note
     applies — nothing exists yet to leave behind. Report only which mode was
     chosen and continue. The flag is never an error; on a first run it is
     simply redundant.

### Phase 1 — Read and Assess

1.1. **Read `.claude/settings.local.json`** from the project root directory. If
   the `.claude/` directory does not exist, create it. If the file does not
   exist, create it with the default structure below. This file is the
   **single source of truth** for all workspace configuration — every setting
   collected by this wizard MUST be written here.

   Default initial content:
   ```json
   {
     "model": "claude-opus-4-7",
     "sdlc": {
       "mode": "remote",
       "workspace": {
         "name": ""
       },
       "linear": {
         "team": ""
       },
       "notion": {
         "home_directory": "",
         "docs_database": ""
       },
       "repositories": [],
       "feature_flags": "",
       "templates": {
         "prd": "313d53382b2381549bf1d4c554ce074d",
         "scoping_doc": "0dad30066fac46ffb1de88f0c05c0e90",
         "jotdown": "5697951897e647c6a70b446c2cbaeece",
         "data_ui_inventory": "314d53382b23819d9841cd911d8f511a"
       },
       "safety_boundaries": {
         "restricted_paths": [],
         "mandatory_human_review": [],
         "max_files_per_pr": 20,
         "max_lines_per_pr": 500
       }
     }
   }
   ```

   **Mode:** the `"mode": "remote"` line above is a fallback for the case
   where no mode has been established at all. **Never let it overwrite a mode
   that already exists.** Use, in order: the value Phase 0.2 just wrote; then
   the value already on disk; and only if neither exists, `"remote"`. A user
   who chose **Local files** in Phase 0 must not find `remote` in the file
   afterwards — that is the whole answer they were asked for.

   **Model override:** If the file exists but has no `model` key, set
   `"model": "claude-opus-4-7"` at the top level. If `model` already exists,
   leave it unchanged — the user may have customized it.

   If the file exists but has no `sdlc` key, add one with the default
   templates above. If the file exists with an `sdlc` key but no
   `templates` section, add the default templates.
   **Preserve all other top-level keys in the file** — this file may contain
   Claude Code settings unrelated to the SDLC plugin.

1.2. **Classify every configurable field** under `sdlc` as one of:
   - **Configured** — has a real, non-placeholder value
   - **Needs setup** — contains a placeholder, is empty, or is missing

   Placeholder detection rules:
   - `workspace.name`: needs setup if missing or empty. Default to the
     current directory name (`basename` of the project root) if not set.
   - `linear.team`: needs setup if the value is `YOUR_TEAM_NAME` or empty
   - `notion.home_directory`: needs setup if the value contains
     `YOUR-PAGE-ID` or is empty
   - `notion.docs_database`: needs setup if empty (will be auto-populated
     in Phase 3)
   - `repositories`: needs setup if the array is missing, empty, or only
     contains default template examples (`api-gateway`, `commerce-service`,
     `web-app` all with default paths and no actual directories on disk)

   - `safety_boundaries.max_files_per_pr`: needs setup if missing. Default: `20`
   - `safety_boundaries.max_lines_per_pr`: needs setup if missing. Default: `500`
   - `feature_flags`: needs setup if missing or empty. Accepted values:
     `split` (Split.io or an equivalent SaaS flag platform), `env`
     (environment variables, settings tables, or per-tenant kill switches
     maintained in-repo), or `none` (this workspace does not gate features
     behind flags).

   Do NOT assess or prompt the user about:
   - `sdlc.templates` — seeded with defaults in step 1.1, never changed after
   - `sdlc.safety_boundaries.restricted_paths` — managed externally
   - `sdlc.safety_boundaries.mandatory_human_review` — managed externally

### Phase 2 — Configure Missing Fields Only

2.1. **If ALL fields are already configured, skip to Phase 5.** Do not ask the
   user to re-confirm values that are already set.

2.2. **For each field that needs setup, ask the user:**

   **In `local` mode, skip the Jira/Linear team, Notion home directory, Notion docs
   database, and all four template ID fields.** None of them apply — local mode
   uses each skill's inline document structure. Still collect the workspace name
   and the repository list.

   **Workspace name** (only if missing or empty):
   Propose the current directory name as the default: "I'll use
   `<dirname>` as the workspace name. Is that correct, or would you like a
   different name?"
   If accepted, set `sdlc.workspace.name` to the directory name.

   **Jira/Linear team** (only if placeholder):
   "What is your Jira/Linear team name? This is the team where your issues live
   (e.g. 'Platform', 'Commerce', 'Growth'). Ask your Engineering Manager if
   you are unsure."

   **Notion home directory** (only if placeholder):
   "What is the Notion page URL or page ID where AI-generated documents
   should be created? This is usually your team's or project's main page
   in Notion. Ask your PM or Engineering Manager if you are unsure."
   Accept either a full Notion URL or a page ID (UUID).

   **Repositories** (only if placeholder):
   **Always scan** the project root directory for first-level
   subdirectories that contain a `.git` folder. Also check if the project
   root itself is a git repository (a `.git` directory exists in the project
   root). Build a list of all
   discovered repos with their relative paths.

   Present the discovered repos to the user as a numbered list:
   "I found these git repositories in your workspace:
     1. `api-gateway` (./api-gateway)
     2. `commerce-service` (./commerce-service)
     3. `.` (current directory — this repo)
   Should I add all of them, or would you like to select specific ones?
   (Enter 'all' or comma-separated numbers like '1,3')"

   For each selected repo, set `name` to the directory name (or the
   workspace name for the root repo) and `path` to `./<directory-name>`
   (or `.` for the root).

   If no git repos are found at all, ask: "No git repositories found in
   the current directory. Which repositories do you work on? Give me the
   name and relative path for each one (e.g. `api-gateway ./api-gateway`).
   These should be cloned as sibling directories inside this project
   folder."

   **PR size limits** (only if missing):
   "PR size limits control how large a single pull request can be. These
   limits are enforced during task planning and implementation.
   Defaults: max **20 files** and **500 lines** per PR. Accept defaults
   or enter custom values."
   If accepted, set `sdlc.safety_boundaries.max_files_per_pr` to `20` and
   `sdlc.safety_boundaries.max_lines_per_pr` to `500`. If the user provides
   custom values, use those instead.

   **Feature flag platform** (only if missing or empty):
   Ask with `AskUserQuestion`:

   > "How does this workspace gate features behind flags? The doc
   > generators (`/sdlc:sdlc-generate-scoping-doc`,
   > `/sdlc:sdlc-generate-jotdown`) will ask the right fields based on
   > this answer, and skip the feature-flag section entirely when the
   > workspace does not use flags."

   Options, in this order:
   - **Split.io** — a SaaS flag platform. Splits have a name and a
     traffic type; coding agents assume the split already exists and use
     the SDK to evaluate it. Persist `"split"`.
   - **Environment variables or settings tables** — flags live in
     config (env vars, a config file, a per-tenant settings row, or a
     kill switch). Persist `"env"`.
   - **None** — this workspace does not use feature flags. The doc
     generators skip the flag section. Persist `"none"`.

   Write the chosen value to `sdlc.feature_flags`.

   Ask all missing fields in a single interaction — do not ask one at a time.

2.3. **If any values were collected, update `.claude/settings.local.json`.**
   When writing:
   - Read the full file content first
   - Parse the JSON, update only `model` and keys under `sdlc`
   - Preserve ALL other top-level keys unchanged
   - Preserve `sdlc.templates` — do not modify
   - Preserve `sdlc.safety_boundaries.restricted_paths` — do not modify
   - Preserve `sdlc.safety_boundaries.mandatory_human_review` — do not modify
   - `sdlc.safety_boundaries.max_files_per_pr` and `max_lines_per_pr` may be set
     if missing (seeded with defaults or user-provided values)
   - `sdlc.feature_flags` may be set if missing (seeded with the user's
     choice of `split`, `env`, or `none`)
   - Only update the specific fields that had placeholder values
   - Write the file back as UTF-8 with 2-space indented JSON, **without ASCII
     escaping** — every non-ASCII character already in the file must survive
     the round-trip unchanged

   **Encoding — this is not optional.** Python's `json.dump` defaults to
   `ensure_ascii=True`, which rewrites characters like `✓` into `✓`.
   The JSON is semantically identical, but the bytes are not: it produces a
   spurious diff inside `permissions.allow` and other keys this skill is
   forbidden to modify, and it churns the file again on every repeat run.
   Always pass `ensure_ascii=False` and open both the read and the write with
   `encoding="utf-8"`:
   ```python
   import json
   with open(path, encoding="utf-8") as f:
       cfg = json.load(f)
   # ... modify only the permitted keys ...
   with open(path, "w", encoding="utf-8") as f:
       json.dump(cfg, f, indent=2, ensure_ascii=False)
       f.write("\n")
   ```
   Whatever tool performs the write, verify afterwards that the only changed
   lines are the ones you intended.

### Phase 3 — Create SDLC Documents Database (If Needed)

Skip this phase entirely when `sdlc.mode` is `local`. There is no Notion
database to create.

3.1. **Ensure the SDLC Documents database exists.** This step is idempotent —
   it must never create a duplicate database.

   **If `notion.home_directory` is still a placeholder**, skip this step
   entirely. The database will be created on the next run after the home
   directory is configured.

   **If `notion.docs_database` already has a value**, verify the database
   still exists by fetching it with `notion-fetch`:
   - If the fetch succeeds: the database is healthy. Skip creation. Report
     in Phase 8: `Docs database: <title> (existing)`.
   - If the fetch fails (deleted or inaccessible): clear the
     `sdlc.notion.docs_database` value and fall through to creation below.

   **If `notion.docs_database` is empty** (or was just cleared above):
   First, search for an existing database named "SDLC Documents" under
   `home_directory` using `notion-search`. If found, store its ID in
   `sdlc.notion.docs_database` and skip creation.

   Only if no existing database is found, offer to create it:
   "No SDLC Documents database found under your Notion home page. Would you
   like me to create one? This database organizes all generated documents
   (PRDs, Scoping Docs, Jotdowns) with filterable views."

   If the user agrees, use the Notion MCP `notion-create-database` tool to
   create a database titled **"SDLC Documents"** as a child of
   `home_directory`. Define these properties:

   | Property     | Type    | Configuration                                           |
   |-------------|---------|--------------------------------------------------------|
   | Name        | Title   | (default title column)                                  |
   | Doc Type    | Select  | Options: `PRD`, `Scoping Doc`, `Jot Down`, `Data UI Inventory` |
   | Feature     | Text    | Plain text — the feature name                          |
   | Quarter     | Select  | Options: current + next quarter (e.g. `2026-Q1`, `2026-Q2`) |
   | Author      | Text    | Person who triggered generation                        |
   | Related PRD | URL     | Link to the PRD page for this feature                  |
   | Milestone   | Text    | For Jotdowns: milestone name                           |

   **After creation:**
   - Store the returned database ID in `sdlc.notion.docs_database`.
   - Write the updated value to `.claude/settings.local.json`.
   - Tell the user: "Created the SDLC Documents database under your home
     page. New docs will be organized as database entries with filterable
     views by quarter, feature, and type."

### Phase 4 — Create Workspace CLAUDE.md (If Needed)

4.1. **Ensure `.claude/CLAUDE.md` exists in the project root** and contains
   the required sections. This file gives Claude Code context about the
   workspace and provides a standard location for the `skill-retrospective`
   agent to append lessons learned.

   **If `.claude/CLAUDE.md` does not exist**, create it with:

   ```markdown
   # <workspace-name>

   SDLC-powered workspace managed by the `sdlc` Claude Code plugin.
   Workspace configuration lives in `.claude/settings.local.json`.

   ## Lessons Learned

   <!-- Lessons are added here by the skill-retrospective agent after skill runs. -->
   ```

   Replace `<workspace-name>` with `sdlc.workspace.name`. Do not duplicate
   information already in `settings.local.json` (repositories, team, etc.).

   Tell the user: "Created `.claude/CLAUDE.md` for your workspace. This
   gives Claude Code context about your SDLC setup and provides a place
   for lessons learned."

   **If `.claude/CLAUDE.md` already exists**, read it and verify compliance:

   a. **Check for `## Lessons Learned` section.** Search for a line
      matching `## Lessons Learned` (case-insensitive). If missing, note
      it as a required addition.

   b. **If the section is missing**, show the user what will be added:
      "Your `.claude/CLAUDE.md` is missing a `## Lessons Learned` section.
      Would you like me to add it? This section is used by the
      skill-retrospective agent to record lessons after skill runs."
      - If the user agrees: append the section to the end of the file.
        Never overwrite or reorder existing content.
      - If the user declines: skip and continue.

   c. **If the file is fully compliant**, report:
      "Workspace CLAUDE.md — OK" and move on.

### Phase 5 — Verify MCP Status (Always Runs)

Skip this phase entirely when `sdlc.mode` is `local`. Report "not required in
local mode" for Notion, Jira/Linear, and Figma in the Phase 8 summary instead.
Snyk and Playwright are unaffected — they are local tools and Phase 6 still runs.

5.1. **Tell the user what is about to happen:**
   "I'll now check MCP connectivity. If a service is not yet authenticated,
   your browser may open for sign-in — this is normal and expected."

5.2. **Check Jira/Linear.** Attempt to call the Jira/Linear `list_teams` tool (limit 5).
   - **If successful:** Record status as "Connected". Show the teams found.
     If the configured `linear.team` value appears in the results, note:
     "Your team '<name>' was found in Jira/Linear." If it does NOT appear, warn:
     "Your team '<name>' was not found. Available teams: [list]."
   - **If it fails:** Record status as "Not connected". Do NOT retry or
     block. Note: "Jira/Linear will prompt for sign-in the first time you use a
     skill that needs it (`/sdlc:sdlc-generate-task-breakdown`,
     `/sdlc:sdlc-implement-task`)."

5.3. **Check Notion.** Attempt to fetch the configured
   `notion.home_directory` page using the Notion MCP.
   - **If successful:** Record status as "Connected". Show the page title.
   - **If the page is not found but auth succeeded:** Record as "Connected
     (page not found)". Warn: "Connected to Notion, but the configured home
     page could not be found. Double-check the URL or page ID."
   - **If it fails:** Record status as "Not connected". Note: "Notion will
     prompt for sign-in the first time you use a skill that needs it. Most
     skills require Notion, so you will want to set this up soon."

5.4. **Check Figma.** Figma is optional — it is only needed for
    `/sdlc:sdlc-generate-data-ui-inventory`.
    - Ask: "Figma is optional (only needed for
      `/sdlc:sdlc-generate-data-ui-inventory`). Would you like to test Figma
      connectivity now, or skip it?"
    - **If the user wants to test:** Ask for a Figma file URL and attempt to
      fetch metadata. Report success or failure.
    - **If skipped:** Record status as "Skipped (optional)".

5.5. **Note Playwright status.** Playwright is a local MCP that runs via npx
    (configured in the plugin's `.mcp.json`). It does not require
    authentication. Record status as "Available (local)". Tell the user:
    "Playwright runs locally and does not need authentication. It will
    download browser binaries (~150 MB) on first use."

### Phase 6 — Set up Snyk MCP globally (Always Runs)

6.1. **Set up Snyk MCP globally.** Snyk is required for `/sdlc:sdlc-implement-task`
    security scanning. It must be registered in `~/.claude.json` so it is
    available in all sessions and sub-agents.

    **Step A — Check for SNYK_TOKEN.**
    Run:
    ```bash
    echo ${SNYK_TOKEN+set}
    ```
    - If the output is **not `set`**: no token in environment. Proceed to
      Step B normally (OAuth flow).
    - If the output is **`set`**: do **not** echo or display the token value.
      Tell the user:
      > "Found a `SNYK_TOKEN` in your environment — using it directly.
      > No browser sign-in needed."

      Proceed to Step B to detect/install the Snyk CLI, then **skip Step C's
      OAuth flow entirely** and go straight to token auth (using the env var
      directly — never echoing it):
      ```bash
      $SNYK_BIN auth "$SNYK_TOKEN"
      ```
      - If auth succeeds: proceed to Step D. Set a flag `USE_TOKEN=true` so
        Step D1 embeds the token in the MCP config's `env` section.
      - If auth fails (invalid or expired token): warn the user:
        > "⚠️ The `SNYK_TOKEN` in your environment appears to be invalid or
        > expired. Please update the token value or remove the variable and
        > re-run `/sdlc:sdlc-workspace-init` to sign in via browser instead."
        Record Snyk status as "Blocked — invalid SNYK_TOKEN". Skip to Step E.

    **Step B — Detect Snyk CLI installation.**
    Run:
    ```bash
    command -v snyk 2>/dev/null
    ```
    - If a path is returned (e.g. `/usr/local/bin/snyk`): store it as
      `SNYK_BIN`. This is the binary to use for both auth and MCP.
    - If not found: install Snyk CLI globally:
      ```bash
      npm install -g snyk
      ```
      Then run `command -v snyk` again and store the result as `SNYK_BIN`.

    **Step C — Check if already authenticated.**
    Use the CLI to check for a stored API token:
    ```bash
    $SNYK_BIN config get api 2>/dev/null
    ```
    - If a non-empty value is returned: credentials exist. Proceed to Step D
      (write config). **D3 must still run even in this case.**
    - If empty or error: proceed to authenticate below.

    Run auth using the detected binary:
    ```bash
    $SNYK_BIN auth
    ```
    Tell the user:
    > "Your browser is opening for Snyk sign-in. Complete the login and
    > confirm here when done."

    Wait for user confirmation, then verify credentials were saved:
    ```bash
    $SNYK_BIN config get api 2>/dev/null
    ```
    - If a non-empty value is returned: proceed to Step D.
    - If still missing: ask for token manually:
      > "Sign-in did not complete. Please get your API token from
      > https://app.snyk.io/account (Auth Token → Click to show) and
      > paste it here, or type **skip** to set this up later."
      If token provided: run `$SNYK_BIN auth <token>` then proceed to Step D.
      If skipped: record status as "Skipped". Skip to Step E.

    **Step D — Write Snyk to global Claude config and allow tools.**

    **D1 — Global MCP entry.** Read `~/.claude.json` (create as `{}` if it
    does not exist). Add or overwrite `mcpServers.Snyk` using the **direct
    binary path** from Step B — never use `npx` here, as it creates version
    conflicts with an already-installed Snyk CLI.

    If `USE_TOKEN=true` (SNYK_TOKEN was found in Step A), embed the token in
    the MCP server's `env` so it is always available to sub-agents regardless
    of whether they inherit the shell environment. Read the token value
    directly from the environment **without printing it** — use `$SNYK_TOKEN`
    in whatever write operation updates `~/.claude.json`. Never run
    `echo $SNYK_TOKEN` or log the token value at any point.
    **Warn the user before writing:**
    > "⚠️ Your SNYK_TOKEN will be stored in plaintext in `~/.claude.json`.
    > This file is user-readable only — ensure no other users share this
    > machine account. The token is needed so sub-agents always have Snyk
    > access regardless of shell environment."
    After writing, restrict file permissions:
    ```bash
    chmod 600 ~/.claude.json
    ```
    Config structure:
    ```json
    {
      "mcpServers": {
        "Snyk": {
          "command": "<SNYK_BIN>",
          "args": ["mcp", "-t", "stdio"],
          "env": {
            "SNYK_TOKEN": "<TOKEN_VALUE>"
          }
        }
      }
    }
    ```

    If `USE_TOKEN=false` (OAuth was used), omit the `env` section:
    ```json
    {
      "mcpServers": {
        "Snyk": {
          "command": "<SNYK_BIN>",
          "args": ["mcp", "-t", "stdio"]
        }
      }
    }
    ```

    Preserve all other keys in `~/.claude.json`. Write back as UTF-8 with
    2-space indentation and **without ASCII escaping** — the same encoding
    rule as Phase 2.3 (`ensure_ascii=False`, `encoding="utf-8"` on both read
    and write). `~/.claude.json` routinely contains non-ASCII text in
    unrelated keys; escaping it rewrites parts of the user's global config
    this step has no business touching.

    **D2 — Workspace tool permissions.** Read `.claude/settings.local.json`.
    Ensure the following tools are present in `permissions.allow` (add only
    those not already listed — never duplicate):
    ```
    mcp__Snyk__snyk_version
    mcp__Snyk__snyk_trust
    mcp__Snyk__snyk_code_scan
    mcp__Snyk__snyk_sca_scan
    mcp__Snyk__snyk_iac_scan
    ```
    If `permissions` does not exist in the file, add it. If `permissions.allow`
    does not exist, create it as an empty array first. Preserve all other
    `permissions` keys (`deny`, etc.) and all other top-level keys unchanged.
    Write back as UTF-8 with 2-space indentation and **without ASCII
    escaping**, per the encoding rule in Phase 2.3. Existing `permissions.allow`
    entries frequently contain non-ASCII characters inside quoted shell
    commands; appending the Snyk entries must not rewrite any of them.

    **D3 — Note on SCA folder trust.**

    The Snyk MCP server maintains its own folder trust store, populated via
    the `snyk_trust` MCP tool (which opens a browser for the user to approve
    each path). There is no CLI command to pre-seed this trust list.

    Because the Snyk MCP server is not loaded until after the Claude Code
    restart that follows this wizard, `snyk_trust` cannot be called here.
    Trust is handled automatically by the Security Agent at first scan time:
    if a folder is not yet trusted, the Security Agent calls `snyk_trust`
    before scanning, the browser opens for approval, and the scan proceeds
    once the user approves.

    No action is required in this step. Tell the user:
    > "SCA folder trust will be established automatically the first time the
    > Security Agent scans each repository. A browser window will open for
    > your approval at that point."

    **Step E — Report status and restart notice.**
    - If Snyk was **already configured and credentials exist**: record
      "Connected ✓". No restart needed unless the config entry was absent.
    - If Snyk was **just configured**: record "Configured — restart required"
      and display this notice prominently at the end of Phase 8:
      > "**Action required:** Snyk was just configured globally. Please
      > restart Claude Code for it to take effect. Security scanning in
      > `/sdlc:sdlc-implement-task` will be active after the restart."
    - If Snyk is **Blocked** or **Skipped**: record that status and include
      it in the next-steps list at the end of Phase 8.

### Phase 7 — Recommended Plugins (Always Runs)

7.1. **Check for recommended Claude Code plugins.** These plugins enhance
    Claude Code's capabilities and are strongly recommended for SDLC
    workflows.

    **Detection:** Read `~/.claude/plugins/installed_plugins.json` to
    determine which plugins are currently installed. A plugin is installed
    if its key (e.g. `context7@claude-plugins-official`) exists in the
    `plugins` object.

    **Language detection:** For each configured repository that exists on
    disk, check which languages are present by looking for files with
    relevant extensions (scan only the top 2 directory levels to keep it
    fast):
    - TypeScript/JavaScript: `.ts`, `.tsx`, `.js`, `.jsx` files
    - Go: `.go` files
    - Python: `.py` files

    **Recommended plugins:**

    | Plugin                                  | When to recommend                          | What it does                                                    |
    |-----------------------------------------|--------------------------------------------|-----------------------------------------------------------------|
    | `context7@claude-plugins-official`      | Always                                     | Pulls up-to-date library docs into context — helps Claude write correct code against current APIs |
    | `typescript-lsp@claude-plugins-official` | If any repo contains TypeScript/JS files  | Gives Claude real-time type errors, go-to-definition, and refactoring intelligence for TS/JS     |
    | `gopls-lsp@claude-plugins-official`      | If any repo contains Go files             | Gives Claude real-time type errors, go-to-definition, and refactoring intelligence for Go        |
    | `pyright-lsp@claude-plugins-official`    | If any repo contains Python files         | Gives Claude real-time type checking and code intelligence for Python                            |

    **Display the plugin status table.** Use the plugin name (the part
    before `@` in the key) as the display name in the table:

    ```
    Recommended Plugins
    ──────────────────────────────────────────────────────────────────────────────
    Plugin              Status       Why
    ──────────────────────────────────────────────────────────────────────────────
    context7            Installed    Up-to-date library documentation
    typescript-lsp      Not installed TS/JS detected in: ai-sdlc
    gopls-lsp           Skipped      No Go files detected
    pyright-lsp         Not installed Python detected in: ai-sdlc
    ```

    Status values:
    - **Installed** — found in `installed_plugins.json`
    - **Not installed** — relevant language detected but plugin missing
    - **Skipped** — no relevant language detected in any repo (display in
      dimmed/parenthetical style)

    **For each plugin that is "Not installed"**, show the install command
    using the full `name@marketplace` identifier:
    ```
    To install missing plugins, run:
      /plugin install typescript-lsp@claude-plugins-official
      /plugin install pyright-lsp@claude-plugins-official
    ```

    If ALL recommended plugins are either installed or skipped, report:
    "All relevant plugins are installed."

### Phase 7b — Scaffold the Local Artifact Store (Local Mode Only)

7b.1. **Skip this phase entirely when `sdlc.mode` is `remote`.**

7b.2. **Create `.sdlc/features/`** in the workspace root if it does not exist.

7b.3. **Create `.sdlc/README.md`** if it does not exist, with this content:

      ````markdown
      # SDLC Artifacts

      This workspace runs the `sdlc` plugin in local mode. Every PRD, Scoping
      Doc, Jot Down, Data UI Inventory, and task lives here as markdown instead
      of in Notion and Jira/Linear.

      ```
      features/
      └── 001-example-feature/
          ├── prd.md
          ├── scoping-doc.md
          ├── jotdown.md
          └── tasks/
              ├── README.md          # sequencing, critical path, coverage
              └── 001-first-task.md
      ```

      These files are the specification — commit them.

      To switch to Notion and Jira/Linear, run `/sdlc:sdlc-workspace-init --switch-mode`.
      Existing files stay on disk; they are not migrated.
      ````

7b.4. **Do not add `.sdlc/` to `.gitignore`.** These artifacts are meant to be
      committed.

### Phase 8 — Summary (Always Runs)

8.1. **Display the workspace configuration summary:**

    ```
    Workspace Configuration (.claude/settings.local.json)
    ─────────────────────────────────────────
    Default model:     <model value>
    Artifact store:    <"Local files (.sdlc/)" or "Notion + Jira/Linear">
    Workspace name:    <value>
    Jira/Linear team:       <value>
    Notion home page:  <value>
    Docs database:     <ID or "Not created yet">
    Repositories:      <repo1>, <repo2>, ...
    PR max files:      <value>
    PR max lines:      <value>
    Workspace CLAUDE:  <"OK" or "Created" or "Missing Lessons Learned">
    ```

    Directly under this block, always print: "To switch artifact stores
    later, run `/sdlc:sdlc-workspace-init --switch-mode`." This is the only place
    the flag needs to be advertised — it makes the switch path discoverable
    on every run without re-asking on ordinary ones.

8.2. **Display the MCP status table:**

    ```
    MCP Status
    ─────────────────────────────────────────────────────────────────
    Integration  Status                    Skills that need it
    ─────────────────────────────────────────────────────────────────
    Jira/Linear       <status>                  /sdlc-generate-task-breakdown,
                                           /sdlc-implement-task
    Notion       <status>                  /sdlc-generate-prd,
                                           /sdlc-generate-scoping-doc,
                                           /sdlc-generate-jotdown,
                                           /sdlc-generate-data-ui-inventory,
                                           /sdlc-generate-task-breakdown
    Figma        <status>                  /sdlc-generate-data-ui-inventory
    Playwright   Available (local)         (no auth needed)
    Snyk         <status>                  /sdlc-implement-task (security scan)
    ```

8.3. **Display the repository status table.** For each configured repository,
    check:
    - Does the directory exist on disk?
    - Does `.claude/CLAUDE.md` exist in the repository?
    - Does `.claude/ARCHITECTURE.md` exist in the repository?
    - Does a legacy `CLAUDE.md` file exist at the repository root?
    - Does `.github/workflows/needs-human-review.yml` exist (the PR triage
      gate installed by `/sdlc:sdlc-install-pr-review`)?

    ```
    Repositories
    ──────────────────────────────────────────────────────────────────────────────
    Repository          Path             Exists   CLAUDE.md              ARCH.md   PR triage
    ──────────────────────────────────────────────────────────────────────────────
    api-gateway         ./api-gateway    Yes      No                     No        No
    commerce-service    ./commerce-svc   Yes      .claude/CLAUDE.md      Yes       Yes
    web-app             ./web-app        Yes      CLAUDE.md (root!)      No        No
    ```

    If a repository has `CLAUDE.md` at the root but NOT in `.claude/`,
    show a warning: "Legacy location — type
    `/sdlc:sdlc-init-claude-context <repo>` yourself to move it to
    `.claude/CLAUDE.md`."

8.4. **Display actionable next steps** based on what is still pending.

    `sdlc-init-claude-context` sets `disable-model-invocation: true`, so the
    assistant cannot run it on the user's behalf even if asked — the user must
    type it. Word every step that references it as a user action ("type"),
    never as something about to happen, and always include the `/sdlc:`
    prefix, since the bare `/sdlc-init-claude-context` does not resolve.

    - If any MCP is not connected: "Authenticate <service> by running any
      skill that uses it, or run `/sdlc:sdlc-workspace-init` again after signing
      in."
    - If any repository directory is missing: "Clone the missing
      repositories into your project directory."
    - If any repository is missing `.claude/CLAUDE.md`: "Type
      `/sdlc:sdlc-init-claude-context <repo>` to generate codebase context, or
      `/sdlc:sdlc-init-claude-context --all` to generate for all repos in
      parallel. This one has to come from you — I cannot run it for you."
    - If any repository has a legacy root-level `CLAUDE.md`: "Type
      `/sdlc:sdlc-init-claude-context <repo>` yourself to migrate it to
      `.claude/CLAUDE.md`."
    - If any recommended plugin is "Not installed": "Install recommended
      plugins to improve code quality — Claude Code will have access to
      real-time type checking, go-to-definition, and up-to-date library
      docs. Run the `/plugin install` commands listed above."
    - If any repository is missing
      `.github/workflows/needs-human-review.yml`: "Install the PR triage
      gate with `/sdlc:sdlc-install-pr-review`. It runs after CI on every
      PR and decides, by rules you control, whether a human needs to
      review. Starts in shadow mode (comment-only) — you choose when to
      let it act."
    - If everything is green: "You are all set! Try
      `/sdlc:sdlc-generate-prd <your feature idea>` to create your first PRD."

## Important

- This skill modifies the `sdlc` key and the `model` key inside
  `.claude/settings.local.json`. It must NEVER modify any other top-level
  keys in that file (e.g. `permissions`, `env`, etc.) — the one exception is
  `permissions.allow`, which Step D2 appends the Snyk tool entries to.
- The only file outside the project root this skill may touch is
  `~/.claude.json` (Step D1), plus — when the user picks "Register this repo"
  in Phase 0.0 — a single additive entry in the ancestor workspace's
  `sdlc.repositories`. Never write anything else to an ancestor, and never
  reconfigure an ancestor workspace from a nested directory.
- Phase 0's answer is persisted to `.claude/settings.local.json` the moment
  it is given, and no later phase may write a different `sdlc.mode`.
  Phase 1.1's `"mode": "remote"` default applies only when no mode exists
  anywhere — neither in Phase 0's answer nor already on disk.
- A workspace that predates `sdlc.mode` but already holds a real Jira/Linear team
  and Notion home directory **is** `remote` by definition. Record that and
  move on. Never re-interview it and never probe its integrations during
  Phase 0 — existing workspaces must behave exactly as they did before modes
  existed.
- The `sdlc.templates` section must be seeded with the default values from
  step 1.1 if missing, but NEVER overwritten if it already exists. Those
  template IDs are shared across the organization.
- The `sdlc.safety_boundaries.restricted_paths` and `mandatory_human_review`
  sections must NEVER be changed by this skill. Only `max_files_per_pr` and
  `max_lines_per_pr` under `safety_boundaries` may be seeded with defaults.
- The `sdlc.notion.docs_database` field is auto-populated by Phase 3. Once
  set, it must not be changed by this skill on subsequent runs (unless the
  database no longer exists).
- This skill is **strictly idempotent**. On repeat runs, only prompt for
  fields that are still placeholders or missing. Never re-ask a field that
  already has a real value. Always run Phase 6 (Snyk), Phase 7 (plugins), and
  Phase 8 (summary) regardless. Phase 5 (MCP checks) also always runs in
  `remote` mode; it is skipped entirely in `local` mode, per Phase 5's own
  instructions.
- When writing `.claude/settings.local.json`, always read the full file first,
  parse it, modify only `sdlc.*` keys and `permissions.allow` (for Snyk tools
  in Step D2), and write back with 2-space indentation.
  Never use string manipulation — always use proper JSON read-modify-write.
- **Every JSON write in this skill must be UTF-8 and non-ASCII-escaping** —
  `.claude/settings.local.json` and `~/.claude.json` alike. Python's default
  `json.dump(..., ensure_ascii=True)` turns `✓` into `✓`, silently
  rewriting keys this skill must never modify and producing unexplained diffs
  in a git-tracked settings file. Use `ensure_ascii=False` and
  `encoding="utf-8"` on both read and write, then confirm the diff touches
  only the intended lines. "Proper JSON read-modify-write" is not sufficient
  on its own — the encoding is part of the requirement.
- Commands printed for the user to type must carry the plugin prefix:
  `/sdlc:<skill-name>`, not `/sdlc-<skill-name>`. The unprefixed form does
  not resolve. Note also that every skill except `sdlc-workspace-init` and
  `sdlc-workspace-sync` sets `disable-model-invocation: true`, so the
  assistant cannot run them on the user's behalf — word those next steps as
  something the user types.
- Keep language clear and non-technical. This is the first skill most users
  will encounter. Say "your browser will open for sign-in" rather than
  "the OAuth flow will initiate."
- If the user seems confused about where to find their Jira/Linear team name or
  Notion page URL, suggest they ask their Engineering Manager or PM.
- MCP checks should not block the wizard. If a check fails, report it and
  move on. The user can authenticate later.
- Notion, Jira/Linear, and Figma are Claude built-in integrations — there is no
  local MCP server configuration needed for them. Only Playwright requires
  a local MCP entry (already bundled in the plugin's `.mcp.json`).
- Snyk MCP is written to `~/.claude.json` (global user config), NOT to a
  project-level `.mcp.json`. This is required so it is available in all
  sessions and sub-agents. Always read-modify-write `~/.claude.json` —
  never overwrite the whole file. Only touch `mcpServers.Snyk`.
- The Snyk MCP command must use the **direct binary path** from `command -v snyk`,
  never `npx snyk@latest`. Using npx when snyk is already installed creates
  version conflicts and auth failures. The key must be `Snyk` (capital S) —
  this determines the tool name prefix (`mcp__Snyk__*`).
- A `SNYK_TOKEN` env var in the user's shell is used directly instead of
  OAuth — it is validated via `$SNYK_BIN auth $SNYK_TOKEN` and then embedded
  in the MCP server's `env` config so sub-agents always have it regardless of
  shell inheritance. Only block if the token is invalid or expired.
- `.claude/CLAUDE.md` must never be silently overwritten. If the file
  already exists, only append missing sections (e.g. `## Lessons Learned`)
  after user confirmation. Existing content must be preserved as-is.
