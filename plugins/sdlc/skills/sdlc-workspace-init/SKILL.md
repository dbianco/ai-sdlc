---
name: sdlc-workspace-init
description: Interactive setup wizard that configures .claude/settings.local.json, creates .claude/CLAUDE.md, and verifies MCP connectivity
---

# /sdlc-workspace-init

Interactive setup wizard for configuring your workspace. Walks through
`.claude/settings.local.json` to fill in missing values under the `sdlc` key,
ensures `.claude/CLAUDE.md` exists with a Lessons Learned section,
verifies MCP connectivity (Linear, Notion, Figma, Playwright), and reports a
summary of your workspace status.

This skill is **idempotent** — run it as many times as you want. It only asks
about fields that are missing or still using placeholder values. It always
reports MCP status and a full workspace summary.

## Input

No arguments required. This skill is a guided wizard.

## Procedure

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

   Do NOT assess or prompt the user about:
   - `sdlc.templates` — seeded with defaults in step 1.1, never changed after
   - `sdlc.safety_boundaries.restricted_paths` — managed externally
   - `sdlc.safety_boundaries.mandatory_human_review` — managed externally

### Phase 2 — Configure Missing Fields Only

2.1. **If ALL fields are already configured, skip to Phase 5.** Do not ask the
   user to re-confirm values that are already set.

2.2. **For each field that needs setup, ask the user:**

   **Workspace name** (only if missing or empty):
   Propose the current directory name as the default: "I'll use
   `<dirname>` as the workspace name. Is that correct, or would you like a
   different name?"
   If accepted, set `sdlc.workspace.name` to the directory name.

   **Linear team** (only if placeholder):
   "What is your Linear team name? This is the team where your issues live
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
   - Only update the specific fields that had placeholder values
   - Write the file back with 2-space indented JSON

### Phase 3 — Create SDLC Documents Database (If Needed)

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

5.1. **Tell the user what is about to happen:**
   "I'll now check MCP connectivity. If a service is not yet authenticated,
   your browser may open for sign-in — this is normal and expected."

5.2. **Check Linear.** Attempt to call the Linear `list_teams` tool (limit 5).
   - **If successful:** Record status as "Connected". Show the teams found.
     If the configured `linear.team` value appears in the results, note:
     "Your team '<name>' was found in Linear." If it does NOT appear, warn:
     "Your team '<name>' was not found. Available teams: [list]."
   - **If it fails:** Record status as "Not connected". Do NOT retry or
     block. Note: "Linear will prompt for sign-in the first time you use a
     skill that needs it (`/sdlc-generate-task-breakdown`,
     `/sdlc-implement-task`)."

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
    `/sdlc-generate-data-ui-inventory`.
    - Ask: "Figma is optional (only needed for
      `/sdlc-generate-data-ui-inventory`). Would you like to test Figma
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

6.1. **Set up Snyk MCP globally.** Snyk is required for `/sdlc-implement-task`
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
        > re-run `/sdlc-workspace-init` to sign in via browser instead."
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

    Preserve all other keys in `~/.claude.json`. Write back with 2-space
    indentation.

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
    Write back with 2-space indentation.

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
      > `/sdlc-implement-task` will be active after the restart."
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

### Phase 8 — Summary (Always Runs)

8.1. **Display the workspace configuration summary:**

    ```
    Workspace Configuration (.claude/settings.local.json)
    ─────────────────────────────────────────
    Default model:     <model value>
    Workspace name:    <value>
    Linear team:       <value>
    Notion home page:  <value>
    Docs database:     <ID or "Not created yet">
    Repositories:      <repo1>, <repo2>, ...
    PR max files:      <value>
    PR max lines:      <value>
    Workspace CLAUDE:  <"OK" or "Created" or "Missing Lessons Learned">
    ```

8.2. **Display the MCP status table:**

    ```
    MCP Status
    ─────────────────────────────────────────────────────────────────
    Integration  Status                    Skills that need it
    ─────────────────────────────────────────────────────────────────
    Linear       <status>                  /sdlc-generate-task-breakdown,
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

    ```
    Repositories
    ──────────────────────────────────────────────────────────────────────────────
    Repository          Path             Exists   CLAUDE.md              ARCH.md
    ──────────────────────────────────────────────────────────────────────────────
    api-gateway         ./api-gateway    Yes      No                     No
    commerce-service    ./commerce-svc   Yes      .claude/CLAUDE.md      Yes
    web-app             ./web-app        Yes      CLAUDE.md (root!)      No
    ```

    If a repository has `CLAUDE.md` at the root but NOT in `.claude/`,
    show a warning: "Legacy location — run
    `/sdlc-init-claude-context <repo>` to move it to `.claude/CLAUDE.md`."

8.4. **Display actionable next steps** based on what is still pending:

    - If any MCP is not connected: "Authenticate <service> by running any
      skill that uses it, or run `/sdlc-workspace-init` again after signing
      in."
    - If any repository directory is missing: "Clone the missing
      repositories into your project directory."
    - If any repository is missing `.claude/CLAUDE.md`: "Run
      `/sdlc-init-claude-context <repo>` to generate codebase context, or
      `/sdlc-init-claude-context --all` to generate for all repos in
      parallel."
    - If any repository has a legacy root-level `CLAUDE.md`: "Run
      `/sdlc-init-claude-context <repo>` to migrate it to
      `.claude/CLAUDE.md`."
    - If any recommended plugin is "Not installed": "Install recommended
      plugins to improve code quality — Claude Code will have access to
      real-time type checking, go-to-definition, and up-to-date library
      docs. Run the `/plugin install` commands listed above."
    - If everything is green: "You are all set! Try
      `/sdlc-generate-prd <your feature idea>` to create your first PRD."

## Important

- This skill modifies the `sdlc` key and the `model` key inside
  `.claude/settings.local.json`. It must NEVER modify any other top-level
  keys in that file (e.g. `permissions`, `env`, etc.).
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
  already has a real value. Always run Phase 5 (MCP checks), Phase 6
  (Snyk), Phase 7 (plugins), and Phase 8 (summary) regardless.
- When writing `.claude/settings.local.json`, always read the full file first,
  parse it, modify only `sdlc.*` keys and `permissions.allow` (for Snyk tools
  in Step D2), and write back with 2-space indentation.
  Never use string manipulation — always use proper JSON read-modify-write.
- Keep language clear and non-technical. This is the first skill most users
  will encounter. Say "your browser will open for sign-in" rather than
  "the OAuth flow will initiate."
- If the user seems confused about where to find their Linear team name or
  Notion page URL, suggest they ask their Engineering Manager or PM.
- MCP checks should not block the wizard. If a check fails, report it and
  move on. The user can authenticate later.
- Notion, Linear, and Figma are Claude built-in integrations — there is no
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
