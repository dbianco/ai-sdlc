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

$ARGUMENTS — In `remote` mode, one or more Linear issue identifiers
(e.g. `YAL-123` or `YAL-123, YAL-124`). In `local` mode, one or more task
ids (e.g. `001-002` or `001-002, 001-003`) or paths to task files. The user
may also write sequencing hints like `001-002 and 001-003 on top of 001-001`;
treat any trailing `on top of <ref>` as a declaration that the named task is
already a dependency satisfied by that branch, and base the first new
branch on it instead of `main` (step 7 covers the mechanics).

When $ARGUMENTS carries more than one ref, parse the list (comma or " and "
separated), confirm the order with the user once at step 3, and run steps
2a through 15 **once per task**, in order. Each task gets its own branch
and its own commit; a failure in task N stops the loop and surfaces every
task's state. The retrospective in step 16 runs once at the end, covering
every task.

## Procedure

0. **Resolve the artifact store.** Read `sdlc.mode` from
   `.claude/settings.local.json` (absent means `remote`). Read
   `${CLAUDE_PLUGIN_ROOT}/references/artifact-store.md` and use the
   implementation for that mode for every artifact operation named below.
   Never call Notion or Linear directly.

1. **Load `.claude/settings.local.json`** from the project root. Read the `sdlc` config key,
   including safety boundaries.

1a. **Refresh the task store (local mode only).** `.sdlc/` is typically a
   symlink into another repo (commonly `platform-docs`), and `read_task`
   reads from whichever revision is currently checked out there. A task
   that exists on `origin/main` or on an open PR of the task-store repo
   will otherwise be reported as "not found".

   - Resolve the task-store repo: `readlink .sdlc` (or `realpath`), walk
     up to the enclosing git repository, record its path.
   - If its working tree has uncommitted changes, say so and stop; do not
     fetch over local work. The user commits or stashes first.
   - Run `git fetch origin --prune` in the task-store repo. Do not check
     out anything — step 7 operates on the target code repo, not here.
   - After `read_task(ref)` runs in step 2: if the result is "not found",
     before aborting, search `git branch -a --list '*<task-id>*'` and
     `gh pr list --search '<task-id>'` in the task-store repo and tell
     the user **where** the task lives (branch name, PR number, SHA).
     Ask whether to check that revision out first and retry.

   For `remote` mode, skip this step — Linear is always "current" and the
   task-store concept does not apply.

2. **Read the task.** Let `ref` be the current task id from $ARGUMENTS
   (see the loop in the Input section).
   Call `read_task(ref)`, and let `feature` be the feature that `read_task`
   resolved `ref` within. Both are used throughout the rest of this
   procedure — `feature` by `list_tasks(feature)` below, `ref` by
   `update_task_status(ref, ...)` in the abort paths and step 15.

   Read `task.kind` (default `code`) and the task's labels. If `kind` is
   `acceptance-run` or the labels include `acceptance-run`, this is **not** a
   code-writing task — the pipeline below (Coding Agent → Test Agent → …) is
   replaced by step 8-alt. The orchestrator still reads the task, picks the
   target repository, resolves domain context, and runs the safety and
   preflight checks, but the implementing step is a single Acceptance Run
   Agent spawn.

   Read:
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

2a. **Detect already-worked-on tasks.** Check the task's own `status:` field.
   If it is **not** `todo` or `in_progress`, the task has been through the
   loop before. Treat it as a resumption, not a fresh start.

   - In `local` mode search for an existing branch matching
     `ai/<task-id>-*` with `git branch -a --list 'ai/<task-id>-*'` in the
     target repository (resolved in step 4; this check actually runs after
     step 5).
   - Search for an open PR with `gh pr list --head 'ai/<task-id>-*' --state open`.
   - Record what was found: existing branch(es), their heads, any open PR
     number, and the task's current status (`in_review`, `blocked`, `done`,
     `partial`).

   Present via `AskUserQuestion`:

   > "Task `<task-id>` is already at status `<status>` with branch
   > `<branch>` (PR `#<n>`). What should I do?"
   >
   > - **Verify** — check out the existing branch, re-run tests, and
   >   report. No new commit is made.
   > - **Resume** — check out the existing branch and keep going. Useful
   >   when the task was `in_progress` or `blocked`.
   > - **Redo from scratch** — delete the existing branch (after
   >   confirming no uncommitted work is on it) and treat the task as
   >   `todo`. Rarely the right choice; the user must confirm explicitly.
   > - **Cancel** — stop. The task's state is unchanged.

   For `todo` or `in_progress` tasks with no existing branch, skip this
   step silently.

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

6a. **Guard against a dirty tree in the target repo.** Run `git status
   --porcelain` in the target repository. If the output is non-empty, the
   tree has uncommitted changes — the next step would otherwise pull over
   them (step 7's `git checkout main && git pull`) or sweep them into the
   commit (step 13's `git add`).

   List the paths and ask via `AskUserQuestion`:

   > "The target repo has uncommitted changes. These are unrelated to
   > `<task-id>` and must not land in its commit. How should I proceed?"
   >
   > - **Stash them** — `git stash push -u -m "sdlc: before <task-id>"`,
   >   restore after step 13 (`git stash pop`). The stash list carries
   >   the task id so the user can recover if something fails.
   > - **Commit them separately first** — stop; the user commits the
   >   unrelated work on a side branch, then re-runs this skill.
   > - **Abort** — stop and leave the tree as-is.

   If the output is empty, continue silently.

7. **Pull latest from remote and create a working branch:**
   ```
   git fetch origin
   git checkout <base>
   git pull origin <base>
   git checkout -b ai/<task-id>-<slugified-title>
   ```

   `<base>` is `main` by default. When the Input section's "on top of
   `<other-task>`" hint was given — or when the previous task in a
   multi-ref run completed — set `<base>` to that task's branch
   (`ai/<other-task>-*`) so the new branch stacks on top of it instead of
   diverging from `main`. Say which base was used in the final report so
   the reviewer knows the stacking order.

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

    For `kind: acceptance-run` tasks, the "Coding Agent" references above
    apply to the Acceptance Run Agent spawned in step 8-alt instead.

7c. **If `kind` is `acceptance-run`, ask the head policy up front.** Present
    the services the task names, each with the SHA the task expects, and
    whether each matches `origin/main` right now. Via `AskUserQuestion`:

    > "This is an acceptance-run task across <N> services. Some heads
    > appear to be unmerged (<list the branch tips>). How should the run
    > execute?"
    >
    > - **At merged heads** — the run checks out the merge commit on
    >   `main` for each service. Unmerged branch tips are ignored.
    > - **At the branch tips the task names** — the run records SHAs and
    >   notes "unmerged" in the run log for each.
    > - **Wait** — do not run. The user pushes and merges first; stop
    >   this invocation.

    Record the choice. The Acceptance Run Agent receives it as the head
    policy input. For `kind: code` tasks, skip this step.

8. **Spawn the Coding Agent** as a sub-agent via Task:
   **Skip this step entirely when `kind` is `acceptance-run`; use step 8-alt
   below instead.**

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

8-alt. **Spawn the Acceptance Run Agent** (only when `kind` is
   `acceptance-run`). Pass to the agent:
   - The task details (title, description, acceptance criteria, the
     acceptance script or sequence)
   - The repository path(s) under test, each with the SHA the task expects
   - The **head policy** chosen in step 7c
   - **Isolation parameters** generated here: a unique compose project name
     (e.g. `sdlc-acc-<task-id>-<short-random>`), a port offset derived from
     a hash of the task id, and dedicated volume names of the same shape.
     Record these so the final report can quote them.
   - Each repo's CLAUDE.md content
   - The workspace safety boundaries
   - The **Preflight notes** block from step 7b, when any discrepancy was
     recorded.

   Read the Acceptance Run Agent instructions from
   `${CLAUDE_PLUGIN_ROOT}/agents/acceptance-run-agent.md`.

   **Handle Acceptance Run Agent results:**

   - **PASS** — the run observed every criterion satisfied with real
     measurements. Treat as the task's final successful outcome. Skip
     steps 9–11a (Test, Security) and step 12 (Documentator); go to step
     13 and commit the **run log** produced by the agent. In step 15,
     call `update_task_status(ref, in_review)`.
   - **PARTIAL** — the run completed but one or more criteria could not
     be measured in this environment. Treat as a complete, honest result.
     Skip steps 9–11a and 12. Go to step 13 and commit the run log. In
     step 15, call `update_task_status(ref, partial, unmet)` where
     `unmet` is the list of criteria the agent returned.
   - **FAIL** — the run observed at least one criterion violated.
     Surface the findings to the user. In step 15, call
     `update_task_status(ref, blocked, reason)` with the failing
     criteria as `reason`.
   - **BLOCKED** — the run could not execute at all. Surface the cause.
     In step 15, call `update_task_status(ref, blocked, reason)`.

   An acceptance-run task never spawns the Coding, Test, Security, or
   Documentator agents. The run log is the only artefact it produces.

9. **Spawn the Test Agent** as a sub-agent via Task:
   **Skip this step entirely when `kind` is `acceptance-run`.**

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

11. **Ask whether to run the Security Agent.**
    **Skip this step entirely when `kind` is `acceptance-run`** — an
    acceptance-run task produces a run log, not source changes, and the
    Snyk scanners have nothing to analyse. Record the security status as
    `SKIPPED — acceptance-run task, no source changes` and continue.

    The security scan is optional and the user decides on every run.
    Present using `AskUserQuestion`:
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

12. **Spawn the Documentator Agent** as a sub-agent via Task.

    **Skip this step entirely when `kind` is `acceptance-run`** — the run
    log already written by the Acceptance Run Agent is the documentation.

    **Doc-only task shortcut (`kind: code` only).** If every file the
    Coding Agent reported modifying is a documentation file
    (`CHANGELOG.md`, `README.md`, any path under `docs/`, `*.md` outside
    `src/` or `tests/`), the documentation has effectively already been
    written by the Coding Agent. Ask the user once via `AskUserQuestion`:

    > "The Coding Agent only touched documentation files. Run the
    > Documentator Agent anyway, or skip?"
    >
    > - **Skip** — proceed to step 13.
    > - **Run anyway** — spawn the agent normally.

    Default to Skip when there is no interactive user (e.g. the loop over
    multiple task refs is running unattended). Record which choice was
    made in the final report.

    Pass to the Documentator Agent:
    - The changes made (files modified, new endpoints, schema changes)
    - The repository path and CLAUDE.md content

    Read the Documentator Agent instructions from
    `${CLAUDE_PLUGIN_ROOT}/agents/documentator-agent.md`.

13. **Commit all changes.** Commit **only the files the Coding Agent (or
    Documentator Agent) reported modifying** — never `git add -A`. The
    tree may still carry unrelated changes that step 6a did not catch
    (new files generated by test runs, caches), and `-A` would sweep them
    into the task's commit. Pass the explicit path list to `git add`.

    ```
    git add <path1> <path2> …     # the Coding Agent's reported files
    git commit -m "<type>(<scope>): <description>

    Implements <task-id>

    <bullet summary of changes>

    Security: <PASS|PASS-WITH-FP|FAIL|SKIPPED> — <N findings remediated, M FPs documented, 'unresolved findings — see report', 'scan declined by user', 'Snyk not configured', or 'acceptance-run task, no source changes'>"
    ```
    `<task-id>` is the Linear issue id in `remote` mode, or the composite task
    id in `local` mode.

    Follow the repo's commit convention from CLAUDE.md if one exists.
    Always include the `Security:` trailer line — from the Security Agent
    report when it ran, or the matching skip reason when it did not. The
    trailer is never omitted, so every commit records whether the code was
    scanned.

    **For `kind: acceptance-run` tasks**, the committed artefact is the
    **run log** produced by the Acceptance Run Agent, not source changes.
    Use a commit message of the form:

    ```
    chore(<scope>): acceptance run for <task-id>

    Implements <task-id>

    Outcome: <PASS|PARTIAL|FAIL|BLOCKED>
    Head policy: <merged|branch-tips|wait>
    Isolation: compose project <name>, ports <offset>
    Run log: <path to run log>
    <unmet, when PARTIAL>

    Security: SKIPPED — acceptance-run task, no source changes
    ```

14. **Report to the user:**
    - Summary of changes made (for `kind: code`) or **acceptance run
      outcome** and run log path (for `kind: acceptance-run`)
    - Branch base used in step 7 (`main` or `ai/<other-task>-*`), so a
      reviewer can tell when a branch stacks on another
    - Test results (pass/fail counts, coverage) — omit for `acceptance-run`
    - Security scan results (status, findings remediated, FPs documented) —
      or a note that the scan was skipped at the user's request, or that
      it was skipped because this was an acceptance-run task
    - Files modified (list) — for an acceptance-run task this is just the
      run log
    - **Requirement trace** (when the task carried an `Implements:` line):
      each requirement ID and the change that satisfies it, as reported by
      the Coding Agent — or by the Acceptance Run Agent, which cites the
      run-log step that is evidence for each criterion. Call out any ID
      with no corresponding change, and any file modified that was not in
      the task's expected **Files** list. Neither is automatically wrong —
      the breakdown's file list is best-effort — but an unexplained drift
      between planned and actual scope is the thing a reviewer most needs
      pointed at.
    - Number of iteration cycles needed — omit for `acceptance-run`
    - **Preflight notes** (when any were recorded in step 7b): the list of
      task-file discrepancies, the user's disposition, and — if the user
      chose "Proceed with notes" — which items the Coding Agent (or the
      Acceptance Run Agent, for `kind: acceptance-run`) reports having
      acted on.
    - **Acceptance-run specifics** (only for `kind: acceptance-run`): the
      head policy chosen in step 7c, the isolation parameters used, and
      the `unmet:` list when the outcome was PARTIAL.
    - **Follow-up repositories** (when the task carries a `follow_up:`
      field): list each consumer repo and the expected post-merge action
      (e.g. "re-vendor the contracts commit"). Also list the DRIFT state
      each will report between now and the merge, so the reviewer is not
      surprised by a `DRIFT` output from `vectors/sync.sh check` or a
      similar comparator — a comparator pinned to `origin/main` reports
      DRIFT until the task's PR merges.
    - Ready for human review: `git diff <base>..HEAD`

15. **Update the task status.** For `kind: code` tasks, call
    `update_task_status(ref, in_review)`.

    For `kind: acceptance-run` tasks, choose the terminal state from the
    Acceptance Run Agent's outcome:
    - **PASS** → `update_task_status(ref, in_review)`.
    - **PARTIAL** → `update_task_status(ref, partial, unmet)` where
      `unmet` is the list of criterion IDs the run could not measure.
    - **FAIL** or **BLOCKED** → `update_task_status(ref, blocked, reason)`.

    In `remote` mode this sets the Linear issue status (and attaches the
    reason as a comment when non-empty). In `local` mode it rewrites the
    `status:` front-matter field in place and, when applicable, writes
    `unmet:` or `blocked_reason:` as the artifact-store contract defines,
    leaving the rest of the file byte-identical.

    **Commit the status change in the task-store repo (local mode only).**
    `update_task_status` writes into the task file, which lives in the
    task-store repo (typically a sibling repo surfaced through the `.sdlc/`
    symlink). The status edit must land as its own commit on the branch
    the task-store repo is currently on, or it is easily lost when a
    reviewer checks out another branch there. This applies to both
    `kind: code` and `kind: acceptance-run` tasks.

    - In the task-store repo, confirm the modified file is just the task
      file (`git status --porcelain` should show one path).
    - Commit it with a short message, naming the task id and the new
      status:

      ```
      chore(tasks): mark <task-id> <in_review|partial|blocked>
      ```

    - Do not push — the task-store repo's push/PR flow is the user's.
      Record the commit SHA in the final report so it is traceable.

    For `remote` mode, Linear persists the status itself; nothing to
    commit.

---

### Retrospective

16. **Spawn the Skill Retrospective Agent.** After all changes are committed
    and the task status is updated, spawn a sub-agent using the instructions
    in `${CLAUDE_PLUGIN_ROOT}/agents/skill-retrospective.md`.

    Pass to the agent:
    - **Skill name**: `sdlc-implement-task`
    - **What was built**: the task id (Linear issue id in `remote` mode,
      composite task id in `local` mode), title, and branch name
    - **Run summary**: pass the step-14 report **verbatim**, not a
      paraphrase. Step 14 already covers both `kind: code` (iteration
      counts, test and security results, files modified, preflight notes)
      and `kind: acceptance-run` (outcome, head policy, isolation
      parameters, `unmet:` list, preflight notes), so the verbatim report
      carries the right facts for the kind of task that ran. The agent
      must quote only facts present in that summary. Append a one-line
      instruction: *"When proposing lessons, cite each one against a
      quoted line of the Run summary. Do not infer causes, conditions, or
      remediations that are not present in the summary; if a proposed
      lesson has no backing line, drop it instead of hedging."*
    - **Workspace config**: the repository list from `.claude/settings.local.json`
    - **Target repo path**: the path of the repo whose code was changed, so
      the agent can recommend that repo's CLAUDE.md as the target
    - **Today's date**: in `YYYY-MM-DD` form, so the agent stamps lessons with
      a stable value instead of guessing

    The agent only proposes. It returns a ```retrospective``` fenced JSON
    block — it never asks the user and never writes any file.

    When a multi-ref run is in progress, the retrospective runs **once**
    at the end of the loop and receives every task's step-14 report
    concatenated verbatim. The agent still proposes exactly two lessons
    across the whole run, not two per task.

17. **Ask the user and save the lessons.** Read
    `${CLAUDE_PLUGIN_ROOT}/references/retrospective-save.md` and follow it
    exactly on the agent's proposal.

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