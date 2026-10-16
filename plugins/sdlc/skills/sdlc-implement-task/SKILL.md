---
name: sdlc-implement-task
description: Implement a task by orchestrating the Coding, Test, optional Security, and Documentator agents
disable-model-invocation: true
---

# /sdlc-implement-task

Implement a task by orchestrating the Coding Agent, Test Agent, Security
Agent (optional — the user is asked each run), and Documentator Agent. This
is the entry point for the autonomous coding loop. In `remote` mode the task
is a Linear issue; in `local` mode it is a task file under a feature's
`tasks/` directory.

## Input

$ARGUMENTS — In `remote` mode, a Linear issue identifier (e.g. `YAL-123`). In
`local` mode, a task id (e.g. `001-002`) or a path to a task file.

## Procedure

0. **Resolve the artifact store.** Read `sdlc.mode` from
   `.claude/settings.local.json` (absent means `remote`). Read
   `${CLAUDE_PLUGIN_ROOT}/references/artifact-store.md` and use the
   implementation for that mode for every artifact operation named below.
   Never call Notion or Linear directly.

1. **Load `.claude/settings.local.json`** from the project root. Read the `sdlc` config key,
   including safety boundaries.

2. **Read the task.** Let `ref` be $ARGUMENTS, exactly as the user passed it.
   Call `read_task(ref)`, and let `feature` be the feature that `read_task`
   resolved `ref` within. Both are used throughout the rest of this
   procedure — `feature` by `list_tasks(feature)` below, `ref` by
   `update_task_status(ref, ...)` in the abort paths and step 15. Read:
   - Title, description, acceptance criteria
   - Parent context — the parent issue in `remote` mode, `tasks/README.md` in
     `local` mode
   - Sibling tasks and their status — the issue's sub-issues in `remote` mode
     (via the Linear MCP), or `list_tasks(feature)` in `local` mode (every
     other task file in the feature's `tasks/` directory)
   - Dependencies (ensure they are completed — abort if not). In `local` mode
     these are the `depends_on:` ids; a dependency is complete when its
     `status:` is `done`
   - Labels in `remote` mode (to identify target repository, language, and
     domain), or the `labels:` field in `local` mode (language and domain —
     the target repository comes from the task's `repository:` field, read
     in step 4)
   - The `Implements:` line (requirement IDs such as `REQ-03, US-02`) and the
     expected **Files** list, both written by `/sdlc-generate-task-breakdown`.
     Older issues predate these fields — if either is absent, continue without
     it and note the omission in the final report rather than guessing.

   After reading labels, build an initial `domain_skills` candidate list by
   matching labels against the mapping table in
   `${CLAUDE_PLUGIN_ROOT}/domain-skills/README.md`:

   | Label match                              | Add to `domain_skills`       |
   | ---------------------------------------- | ---------------------------- |
   | `golang`, `go`, `go-service`             | `golang.md`                  |
   | `frontend`, `react`, `web-app`           | `frontend-react.md`          |
   | `design`, `ui-design`                    | `frontend-design.md`         |
   | `backend`, `node`, `api`, `express`      | `backend-node.md`            |
   | `accessibility`, `web-design`, `audit`   | `web-design-audit.md`        |

   If no labels match, also scan the issue title and description for keywords
   (`goroutine`, `gRPC` → `golang.md`; `component`, `suspense`, `MUI` →
   `frontend-react.md`; `controller`, `Prisma`, `Zod` → `backend-node.md`;
   `design`, `aesthetic`, `visual` → `frontend-design.md`). Keyword matches are
   lower-confidence — only use them if no label signal exists.

3. **Confirm with the user** before proceeding. Present a summary using
   `AskUserQuestion`:
   - **Task ID and title**
   - **Description** (first ~3 sentences or acceptance criteria)
   - **Status** (and priority, in `remote` mode)
   - **Sibling tasks** (list each with ID, title, and status)
   - **Dependencies** (list any, noting if they are completed or not)
   - **Labels**

   Ask: "Do you want to proceed with implementing this task?"
   Options:
   - "Yes, implement it" — continue to step 4.
   - "No, cancel" — abort gracefully with no changes.

   If the user cancels, stop execution and inform them that no changes were
   made. Do NOT proceed to any subsequent steps.

4. **Identify the target repository.** In `local` mode, read it directly from
   the task's `repository:` front-matter field. In `remote` mode, identify it
   from the issue description or labels, as before. Validate it exists in
   `.claude/settings.local.json`. Abort if not found — same check in both
   modes.

5. **Navigate to the repository** and read its `.claude/CLAUDE.md` and
   `.claude/ARCHITECTURE.md` (if they exist). If `.claude/CLAUDE.md` does
   not exist, check for a legacy `CLAUDE.md` at the repository root.

   While reading CLAUDE.md, parse the `## Tech Stack` section (if present).
   For each indicator found, add to `domain_skills` if not already present:

   | CLAUDE.md indicator                              | Add to `domain_skills`  |
   | ------------------------------------------------ | ----------------------- |
   | `Language: Go`                                   | `golang.md`             |
   | `Language: TypeScript` + `Framework: React`      | `frontend-react.md`     |
   | `Language: TypeScript` + `Framework: Express`    | `backend-node.md`       |

   Deduplicate `domain_skills` after this step.

6. **Validate safety boundaries:**
   - Check that the implementation won't require modifying restricted paths.
   - Read `sdlc.safety_boundaries.max_files_per_pr` (default: 20) and
     `sdlc.safety_boundaries.max_lines_per_pr` (default: 500) from the config.
     Check that estimated changes are within these limits.
   - If boundaries would be violated, report to user and abort.

7. **Pull latest from remote and create a working branch:**
   ```
   git fetch origin
   git checkout main
   git pull origin main
   git checkout -b ai/<task-id>-<slugified-title>
   ```

   `<task-id>` is the Linear issue id (`yal-123`) in `remote` mode, or the
   composite task id (`001-002`) in `local` mode — producing branches like
   `ai/001-002-add-csv-export-endpoint`.

7a. **Load domain engineering standards:**

    For each file in `domain_skills`, read
    `${CLAUDE_PLUGIN_ROOT}/domain-skills/<file>`.

    Special case: if `web-design-audit.md` is in the list, fetch the live
    guidelines from `https://raw.githubusercontent.com/vercel-labs/web-interface-guidelines/main/command.md`
    via WebFetch and append the retrieved content to the file's body before
    including it in the block below.

    Concatenate all loaded content into a single `domain_context` block:

    ```
    ## Domain Engineering Standards

    The following domain-specific standards apply to this implementation. They
    supplement (not replace) the conventions in CLAUDE.md. Where they conflict
    with CLAUDE.md, CLAUDE.md takes precedence.

    ---
    [content of each matched domain skill file, separated by ---]
    ```

    If `domain_skills` is empty, set `domain_context = ""`.

    Log to the user which domain skills were loaded, e.g.:
    `Domain context loaded: golang.md, backend-node.md`

7b. **Verify the task file's premises against the tree.** The Jot Down's
    preflight already spot-checks the Jot Down itself, but the task file is
    generated from it and often carries concrete references the Jot Down
    never stated: paths, exhaustive lists, message keys, routes, env vars,
    assumptions about existing test or build harnesses. The Coding Agent is
    handed the task file as its instructions — a false premise there turns
    into "faithfully implements the wrong thing".

    Scan the task file (title, description, acceptance criteria, Files list,
    any embedded notes) and extract every concrete reference. For each
    class, run the cheapest check that falsifies it:

    | Reference class | Check |
    |-----------------|-------|
    | Named file paths (Files list, "the file at X") | `test -e <path>` in the target repo; mark new-file entries as expected-absent. |
    | Exhaustive lists ("the N files that…", "the only place that…") | `rg -l` the pattern across the repo and compare the count/set against the task's claim. |
    | Message / translation keys ("renders key X") | `rg -F '<key>'` in the repo; if the key is claimed to live on a specific code path, confirm the path references it. |
    | Routes, endpoints, URL paths | `rg -F '<path>'` in route tables/registries; confirm the route is registered where the task says. |
    | Env var names, flag names, Split names | `rg -F '<name>'` across source and config; flag any shadowed or absent. |
    | Test / build infrastructure claims ("the e2e suite already uses X", "the harness forwards /api/\*") | Open the actual harness file(s) and confirm the behaviour: a Playwright `route.fulfill` with no `continue`/`fallback` does not forward, regardless of what the task says. |

    These are cheap greps; budget a minute per class.

    Classify each discrepancy:

    - **Blocking** — the Coding Agent cannot implement the task correctly as
      written. Examples: an acceptance criterion asserts a message key that
      no code path emits; the Files list omits a file that must change for
      the AC to be satisfiable; a premise about the test harness is false
      in a way that makes the AC vacuous.
    - **Advisory** — the premise is incomplete but the intent is clear.
      Example: an exhaustive list of 5 files misses 1; the Coding Agent can
      be told the full set.

    Present discrepancies to the user via `AskUserQuestion`:

    > "Preflight found N discrepancies between the task file and the tree.
    > <per-item summary>. How should I proceed?"
    >
    > - **Pause so I can fix the task file** — stop here. The user edits
    >   the task file (and the Jot Down, if the premise originated there);
    >   re-run the skill.
    > - **Proceed with notes** — continue. Pass every discrepancy to the
    >   Coding Agent in step 8 as a "Preflight notes" block, instructing
    >   it to treat the corrected facts as authoritative over the task
    >   file where they differ.
    > - **Abort** — stop the run.

    If zero discrepancies are found, say so in one line and continue
    silently.

    Record every discrepancy and the chosen disposition. These feed step 8
    (Coding Agent context), step 14 (user report), and step 16 (retrospective).

8. **Spawn the Coding Agent** as a sub-agent via Task:

   Pass to the Coding Agent:
   - The task details (title, description, acceptance criteria)
   - The requirement IDs from the task's `Implements:` line, and the
     expected **Files** list, when the task carries them
   - The repository path and CLAUDE.md content
   - The workspace safety boundaries
   - The `domain_context` block (if non-empty) as "Domain Engineering Standards"
   - The **Preflight notes** block from step 7b, when any discrepancy was
     recorded. Instruct the Coding Agent to treat the corrected facts as
     authoritative over the task file where the two differ, and to note in
     its final report which preflight items it acted on.
   - Instruction: "Implement the changes and write tests following the domain
     engineering standards provided (if any). Do not submit a PR."

   Read the Coding Agent instructions from `${CLAUDE_PLUGIN_ROOT}/agents/coding-agent.md`.

9. **Spawn the Test Agent** as a sub-agent via Task:

   Pass to the Test Agent:
   - The changes made by the Coding Agent (files modified)
   - The repository path and CLAUDE.md content
   - The acceptance criteria from the task

   Read the Test Agent instructions from `${CLAUDE_PLUGIN_ROOT}/agents/test-agent.md`.

10. **Handle Test Agent feedback:**
   - If the Test Agent reports **PASS**: proceed to step 11.
   - If the Test Agent reports **FAIL**: pass the feedback back to a new
     Coding Agent Task for iteration. Maximum 3 iteration cycles.
     If still failing after 3 cycles, report to user and abort.

     Every iteration Task receives the same context as the original step 8
     spawn — including the `domain_context` block when it is non-empty. The
     domain standards must not drop on retries, or later iterations will be
     held to weaker conventions than the first.

11. **Ask whether to run the Security Agent.** The security scan is optional
    and the user decides on every run. Present using `AskUserQuestion`:
    - **Context**: the number of files modified by the Coding Agent, and the
      list of those files.

    Ask: "Run the Security Agent (Snyk scan) on these changes?"
    Options:
    - "Yes, run the scan" — continue to step 11a.
    - "No, skip it" — record the security status as
      `SKIPPED — scan declined by user` and go directly to step 12. Do NOT
      spawn the Security Agent.

11a. **Spawn the Security Agent** as a sub-agent via Task:

    Pass to the Security Agent:
    - The exact list of files modified by the Coding Agent
    - The repository path, CLAUDE.md content, and ARCHITECTURE.md content
      (if it exists)
    - The task details (title, description, acceptance criteria) —
      used for false positive evaluation context
    - The workspace safety boundaries from `.claude/settings.local.json`

    Read the Security Agent instructions from
    `${CLAUDE_PLUGIN_ROOT}/agents/security-agent.md`.

    **Handle Security Agent results:**
    - **PASS** or **PASS-WITH-FP**: proceed to step 12. If PASS-WITH-FP,
      include the FP summary in the final report.
    - **FAIL**: surface the unresolved findings to the user. Ask whether to:
      - "Fix manually and continue" — pause for human fixes, then re-run
        the Security Agent once more before proceeding.
      - "Accept risk and continue" — proceed with a documented security
        exception noted in the commit message.
      - "Abort" — stop and mark the task Blocked, noting the unresolved
        findings. In `remote` mode, update the Linear issue to "Blocked" with
        a comment. In `local` mode, call `update_task_status(ref, blocked,
        reason)` with the unresolved findings as `reason` — this writes both
        `status: blocked` and `blocked_reason:`, so the cause survives in the
        committed task file rather than only the chat report. Also include
        the findings in the final report.
    - **SKIPPED**: proceed to step 12 with a warning note for the commit
      message: `Security scan was skipped — Snyk not configured.`

    There are two distinct skip reasons. Keep them separate everywhere they
    are reported so a declined scan is never mistaken for a broken setup:
    - `SKIPPED — scan declined by user` (step 11, user chose "No, skip it")
    - `SKIPPED — Snyk not configured` (Security Agent returned SKIPPED)

12. **Spawn the Documentator Agent** as a sub-agent via Task:

    Pass to the Documentator Agent:
    - The changes made (files modified, new endpoints, schema changes)
    - The repository path and CLAUDE.md content

    Read the Documentator Agent instructions from
    `${CLAUDE_PLUGIN_ROOT}/agents/documentator-agent.md`.

13. **Commit all changes:**
    ```
    git add -A
    git commit -m "<type>(<scope>): <description>

    Implements <task-id>

    <bullet summary of changes>

    Security: <PASS|PASS-WITH-FP|FAIL|SKIPPED> — <N findings remediated, M FPs documented, 'unresolved findings — see report', 'scan declined by user', or 'Snyk not configured'>"
    ```
    `<task-id>` is the Linear issue id in `remote` mode, or the composite task
    id in `local` mode.

    Follow the repo's commit convention from CLAUDE.md if one exists.
    Always include the `Security:` trailer line — from the Security Agent
    report when it ran, or `Security: SKIPPED — scan declined by user` when
    the user skipped it at step 11. The trailer is never omitted, so every
    commit records whether the code was scanned.

14. **Report to the user:**
    - Summary of changes made
    - Test results (pass/fail counts, coverage)
    - Security scan results (status, findings remediated, FPs documented) —
      or a note that the scan was skipped at the user's request
    - Files modified (list)
    - **Requirement trace** (when the task carried an `Implements:` line):
      each requirement ID and the change that satisfies it, as reported by the
      Coding Agent. Call out any ID with no corresponding change, and any file
      modified that was not in the task's expected **Files** list. Neither is
      automatically wrong — the breakdown's file list is best-effort — but an
      unexplained drift between planned and actual scope is the thing a
      reviewer most needs pointed at.
    - Number of iteration cycles needed
    - **Preflight notes** (when any were recorded in step 7b): the list of
      task-file discrepancies, the user's disposition, and — if the user
      chose "Proceed with notes" — which items the Coding Agent reports
      having acted on.
    - Ready for human review: `git diff main..HEAD`

15. **Update the task status** to in-review. Call
    `update_task_status(ref, in_review)`.

    In `remote` mode this sets the Linear issue to "In Review". In `local` mode
    it rewrites the `status:` front-matter field to `in_review`, leaving the
    rest of the file byte-identical.

---

### Retrospective

16. **Spawn the Skill Retrospective Agent.** After all changes are committed
    and the task status is updated, spawn a sub-agent using the instructions
    in `${CLAUDE_PLUGIN_ROOT}/agents/skill-retrospective.md`.

    Pass to the agent:
    - **Skill name**: `sdlc-implement-task`
    - **What was built**: the task id (Linear issue id in `remote` mode,
      composite task id in `local` mode), title, and branch name
    - **Run summary**: number of Coding/Test Agent iteration cycles needed,
      test results (pass/fail/coverage), whether the user opted into the
      security scan and its status and finding counts, files modified count,
      any safety boundary concerns, any preflight discrepancies recorded in
      step 7b and how they were resolved, any user corrections or pushback
      during the run
    - **Workspace config**: the repository list from `.claude/settings.local.json`

## Important

- This skill orchestrates. It does NOT write code itself.
- Each sub-agent runs in a sandboxed Task. The orchestrator passes context
  in and reads results out.
- If any step fails unrecoverably, mark the task Blocked and report to the
  user. In `remote` mode, update the Linear issue with a comment explaining
  what happened and set status to "Blocked". In `local` mode, call
  `update_task_status(ref, blocked, reason)` with a short explanation as
  `reason` — this writes both `status: blocked` and `blocked_reason:` so the
  cause survives in the committed task file. Also include the explanation in
  the final report.
- Never push to remote or create a PR automatically. The human decides when
  to push.