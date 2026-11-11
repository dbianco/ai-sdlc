---
name: sdlc-generate-task-breakdown
description: Generate a sequenced task breakdown with PERT estimates from a Jot Down, Scoping Doc, and Data UI Inventory
disable-model-invocation: true
---

# /sdlc-generate-task-breakdown

Generate a sequenced task breakdown with PERT estimates from a Jot Down
Implementation Spec, enriched by the Scoping Doc and Data UI Inventory. In
`remote` mode the tasks are created as Jira/Linear issues; in `local` mode they are
written as task files under the feature's `tasks/` directory.

## Input

$ARGUMENTS — In `remote` mode, a Notion URL or page ID pointing to an existing
Jot Down. In `local` mode, a feature reference — `001`, `order-export`, or
`001-order-export`.

## Procedure

0. **Resolve the artifact store.** Read `sdlc.mode` from
   `.claude/settings.local.json` (absent means `remote`). Read
   `${CLAUDE_PLUGIN_ROOT}/references/artifact-store.md` and use the
   implementation for that mode for every artifact operation named below.
   Never call Notion or Jira/Linear directly.

1. **Load `.claude/settings.local.json`** from the project root. Read the `sdlc` config key,
   including the repository list, the Jira/Linear team name (`remote` mode only),
   and safety boundaries (`max_files_per_pr`,
   `max_lines_per_pr`). These limits constrain the maximum size of any single
   task — defaults are 20 files and 500 lines if not configured.

2. **Read the source documents.** Call `resolve_feature($ARGUMENTS)`, then
   `read_doc` for each kind: `jotdown` (required — stop if absent),
   `scoping-doc`, `prd`, and `data-ui-inventory` (each optional; continue
   without any that are missing, noting the omission).

   In `remote` mode, follow the reference links inside the Jot Down to reach the
   Scoping Doc and PRD, as before. For the Data UI Inventory, search for one
   linked from the PRD or Scoping Doc, or search Notion for one matching the
   feature name.

   Use each document for what it carries:
   - **Jot Down** — the primary input.
   - **Scoping Doc** — milestone context, architectural decisions, affected
     services, and risk mitigations.
   - **PRD** — requirements (REQ-xx), user stories (US-xx), validation rules
     (V-xx), and acceptance criteria.
   - **Data UI Inventory** — component inventory, payloads, and frontend task
     decomposition. If absent, skip frontend-specific decomposition from this
     source.

   In `local` mode a single `jotdown.md` may cover several milestones, each
   under its own `### Milestone N of M` heading. Read the whole file and treat
   each such section as a milestone's scope — do not assume one file per
   milestone.

3. **Establish task grouping.** Call `select_grouping()`. This runs after the
   documents are read because that is where the milestone names come from.

   In `remote` mode this lists Jira/Linear projects via
   `mcp__claude_ai_Linear__list_projects` and requires the user to pick one via
   `AskUserQuestion`, then lists milestones for that project via
   `mcp__claude_ai_Linear__list_milestones` and maps or creates them:

   - If the Jot Down covers a specific milestone from the Scoping Doc, ask the
     user which Jira/Linear milestone to assign issues to.
   - If the Jira/Linear project has no milestones yet, create them from the Scoping
     Doc milestones using `mcp__claude_ai_Linear__save_milestone`. Ask the user
     to confirm before creating.

   Every issue must belong to a project and a milestone. Do not proceed until
   both are chosen.

   In `local` mode there is no project and no picker. Take the milestone names
   from the source documents and stamp each task's `milestone:` field. If the
   documents define no milestones, use a single milestone named after the
   feature. Ask the user nothing.

4. **Validate that all source documents are complete.** Scan all documents
   for any sections that require human intervention. Check for ALL of the
   following markers in each document:
   - `⚠️ NEEDS HUMAN INPUT` or `NEEDS HUMAN INPUT`
   - Open Questions marked as unresolved (`OQ-x` items without an answer)
   - Sections containing `TBD`, `TODO`, `[placeholder]`, or `[to be defined]`
   - Empty or stub sections (e.g. a heading with no content underneath)
   - Unresolved risks without mitigations
   - Incomplete API specs, missing schemas, or undefined error responses
     in the Jot Down
   - PRD requirements (`REQ-xx`) or Scoping Doc milestones referenced but
     incomplete in their source documents

   **Classify each marker as blocking or non-blocking:**

   A marker is **non-blocking** (warn only) when ALL of these are true:
   - It is a `TBD` or `TODO` inside a table cell
   - The same row has a Resolution, Notes, or similar column that explicitly
     acknowledges it (e.g. "Not relevant in this moment", "Deferred to
     scoping", "Will be determined during engineering estimation")
   - The field is inherently a downstream concern — such as Duration,
     Estimate, or Timeline fields whose values are outputs of a later
     process, not inputs to this one

   Everything else is **blocking** — including `NEEDS HUMAN INPUT`, unresolved
   Open Questions, empty sections, incomplete API specs, and any `TBD` without
   an accompanying resolution.

   **If blocking items exist:**
   - List **every single one** to the user, grouped by document and section,
     including the exact marker text and its location.
   - Tell the user: "The source documents have unresolved items that must be
     completed before a task breakdown can be generated. Please resolve them
     and re-run this skill." Name the file path in `local` mode, or the Notion
     page in `remote` mode.
   - **STOP. Do NOT proceed.** Do not create any tasks — no Jira/Linear issues in
     `remote` mode, no task files in `local` mode.

   **If only non-blocking items exist:**
   - List them in an "Acknowledged TBDs (non-blocking)" section so the user
     is aware.
   - **Proceed** with generation.

5. **Decompose into implementable tasks.** Use ALL available source documents:

   - **Jot Down** — primary source for backend tasks: database changes, API
     endpoints, service interactions, deployment stages.
   - **Scoping Doc** — milestone grouping, architectural decisions, affected
     services, risk mitigations (create risk-related tasks where needed).
   - **Data UI Inventory** (if available) — primary source for frontend tasks:
     one task per component or component group from the Component Inventory
     database, integration tasks from the Payloads section, setup tasks from
     the Observations section.
   - **PRD** — acceptance criteria from user stories (US-xx) and requirements
     (REQ-xx), validation rules (V-xx) for validation-related tasks.

   Each task must be:
   - Small enough to be a single PR — within the configured
     `max_files_per_pr` and `max_lines_per_pr` limits (defaults: ≤ 20 files,
     ≤ 500 lines changed). If a task would exceed either limit, split it
     into smaller tasks.
   - Self-contained: it can be implemented, tested, and reviewed independently
   - Clearly scoped: an engineer (or coding agent) can start without ambiguity

6. **For each task, define:**
   - **Title**: Verb-first, concise (e.g. "Add `status` field to Order model")
   - **Description**: What to implement, with references to the source
     document and section. Include specific file paths, function names, and
     patterns to follow. For frontend tasks from the Data UI Inventory,
     reference the component name, parent, and library components.
   - **Implements**: The upstream requirement IDs this task satisfies —
     `REQ-xx`, `US-xx`, and `V-xx` from the PRD. Write them as a literal
     line in the task description — the Jira/Linear issue body in `remote` mode,
     the task file body in `local` mode:

     ```
     Implements: REQ-03, US-02, V-07
     ```

     Every task MUST carry at least one ID. A task that implements no stated
     requirement is either scope creep or a requirement missing from the PRD —
     in both cases, stop and resolve it with the user rather than inventing a
     justification. The single exception is infrastructure work with no user-
     facing requirement (build config, CI wiring); mark those
     `Implements: INFRA` so they are distinguishable from unmapped tasks.
   - **Files**: The exact paths the task is expected to create or modify,
     relative to the repository root (e.g. `internal/orders/model.go`,
     `apps/menu/src/components/OrderStatus.tsx`). Best-effort is fine — this
     is what makes the task reviewable and lets the sequencing step detect
     file collisions.
     Use a directory path only when the exact filename genuinely cannot be
     known yet, and say why.
   - **Acceptance criteria**: Testable conditions for "done". Pull from
     PRD user stories (US-xx) and requirements (REQ-xx) where applicable.
     Each criterion must be measurable as written — a quality adjective
     (`fast`, `secure`, `robust`, `reliable`, `intuitive`) with no number,
     threshold, or observable behavior attached is not an acceptance
     criterion. Carry the threshold down from the Jot Down; do not invent one.
   - **Parallelizable**: `[P]` if this task shares no file with any other task
     in the same milestone and has no unmet dependency. Omit otherwise.
   - **PERT estimate**: Optimistic / Most Likely / Pessimistic (in hours)
   - **Dependencies**: Which other tasks must be completed first.
   - **Repository**: Which repo from `.claude/settings.local.json` this task belongs to.
   - **Labels**: `ai-sdlc`, plus language label (e.g. `golang`, `typescript`).
   - **Milestone**: Which milestone this task belongs to (from the task
     grouping step) — a
     Jira/Linear milestone in `remote` mode, the `milestone:` front-matter value in
     `local` mode.

6a. **Verify every task's references are satisfiable.** Before sequencing,
    walk each task from step 6 and run three cheap checks against the
    target repository (`task.repository`). The checks together close two
    classes of defect that have shipped before: acceptance criteria that
    no implementation can satisfy, and `files:` lists that name paths
    which do not exist.

    For each task:

    a. **Files existence.** For every path in `files:`, `test -e <path>`
       inside the task's repository.
       - Exists → OK.
       - Does not exist → flag as **new file** (the task is expected to
         create it) or as **missing** (if the task's description implies
         the file already exists). The two are distinct; mark which one.
       - Directory-only entry → OK; the step 6 rule already requires a
         `why` note for those.

    b. **Satisfiability of mutation / failing-test / guard criteria.**
       For every acceptance criterion that names a mutation ("apply the
       bound after `LIMIT` by reordering — the limit case must go red"),
       a specific test that must fail ("the completeness test fails on
       orphans"), or a guard test ("adding this field without widening
       the union must trip a typecheck"), ask: *can a deliberately broken
       implementation make the named test red?*

       Read the named test's source. If the test's assertions cannot
       distinguish the correct implementation from the broken one — the
       mutant is equivalent, the test scans a disjoint set of files, or
       the harness compares the two implementations against each other
       and would stay green either way — the criterion is **vacuous**.

       Vacuous criteria must not reach a Coding Agent: either rewrite the
       criterion so the harness can falsify it, add the missing coverage
       as a separate task (and the criterion depends on it), or drop the
       criterion with an explicit note.

    c. **Repo-wide claims need a citation.** For every acceptance
       criterion that asserts something about the whole repository or an
       entire test suite — "the completeness test fails on orphans", "no
       source file references the removed key", "every public endpoint
       enforces the auth header" — record the exact command that would
       prove it (`rg -F '<key>' src/`, `npm test -- i18n-catalog`, etc.)
       as part of the criterion. The Coding Agent and Test Agent run the
       command instead of guessing what "the suite" covers.

    Classify every discrepancy:

    - **Blocking** — a Files path marked **missing**, a **vacuous**
      criterion, or a repo-wide claim with no runnable citation. The
      breakdown cannot be shipped as-is.
    - **Advisory** — a new file whose intent is clear; a citation that
      names a command but with a flag that may need confirmation.

    If any blocking item exists, present every discrepancy via
    `AskUserQuestion` with three options:

    > - **Pause so I can fix the Jot Down** — stop here. The user amends
    >   the Jot Down (and/or the PRD) and re-runs the skill.
    > - **Rewrite in place** — the skill proposes a corrected criterion
    >   or a corrected `files:` list, batched up to 4 per `AskUserQuestion`
    >   round, and the user confirms each one. The breakdown continues
    >   with the corrected tasks.
    > - **Abort** — stop the run.

    If only advisory items exist, list them in a short "Advisory notes"
    block and continue silently.

    Record every discrepancy and the chosen disposition. These feed step
    11 (user report).

7. **Sequence the tasks** using dependency order. Identify the critical path.
   Group tasks by their milestone.

   Then resolve file collisions using the **Files** list from the task
   definition step. Any two
   tasks that touch the same file MUST be sequenced, never marked `[P]` —
   either give one a dependency on the other, or merge them if the split was
   artificial. Two agents editing one file in parallel produce conflicting
   edits and a merge the human has to untangle, which is exactly the
   inconsistency this breakdown exists to prevent.

   Strip `[P]` from any task that fails this check, and report the collisions
   you resolved in the report step.

8. **Map requirement coverage.** Before creating anything, map every
   requirement stated in the PRD — each `REQ-xx`, `US-xx`, and `V-xx` — to the
   tasks that implement it, reading each task's `Implements:` line. This
   produces one table, built once here and used twice: written into the epic
   in `local` mode, and presented to the user in the report step.

   | Requirement | Covered by | Notes |
   | ----------- | ---------- | ----- |
   | REQ-03      | YAL-124, YAL-127 | |
   | US-05       | — | no task created |

   Identify tasks in the **Covered by** column the way the current mode names
   them:

   - In `local` mode the composite task id (e.g. `001-002`) is assigned here,
     following the order fixed by the sequencing step. The whole table is
     therefore known before a single file is written, which is what lets the
     epic carry it.
   - In `remote` mode Jira/Linear assigns the identifier (e.g. `YAL-124`) only when
     the issue is created, so **Covered by** is completed in the task-creation
     step below. The Jira/Linear epic carries links to the source documents, not
     this table — unchanged from before.

   Follow the table with two explicit counts: **requirements with no task**
   and **tasks with no requirement** (`Implements: INFRA` does not count as
   unmapped). Both should be zero. If either is non-zero, list the offenders
   by ID and tell the user which side needs fixing — a missing task means the
   breakdown is incomplete, a missing requirement means the PRD is.

9. **Create the epic.** Call `create_epic(feature)`.

   In `remote` mode this creates the parent Jira/Linear issue titled
   `[Feature Name] — Implementation`, labelled `ai-sdlc` and `epic`, in the
   configured team and in the selected project and milestone, with links to
   all source documents.

   In `local` mode it writes `tasks/README.md` containing: the feature name, a
   link to each source document via `doc_link`, the ordered task list with
   dependencies, the critical path, and the requirement coverage table from
   the coverage step.

10. **Create each task.** Call `create_task(feature, task)` per task.

    In `remote` mode this creates a Jira/Linear sub-issue under the parent created
    in the epic step, carrying `project` and `milestone`, with dependencies set
    from the sequencing. Once Jira/Linear has assigned the issue identifiers, use
    them to complete the **Covered by** column of the coverage table.

    In `local` mode it writes `tasks/<NNN>-<slug>.md` using the task file format
    in the artifact store contract — front matter carrying `id`, `title`,
    `status`, `milestone`, `repository`, `depends_on`, `implements`, `files`,
    `parallelizable`, `estimate`, and `labels`. Every field defined there is
    required except `depends_on`, `parallelizable`, and `labels`. The
    `Implements:` line becomes the `implements:` front-matter list, and the
    expected file list becomes `files:`; `[P]` becomes `parallelizable: true`.
    Every newly created task file starts at `status: todo` — `/sdlc-implement-task`
    reads that field to resolve dependencies, so it must be present and correct
    from the moment the file is written.

11. **Report to the user:**
    - Total number of tasks created, grouped by milestone
    - Critical path and estimated timeline (using PERT expected values)
    - The artifact reference for the epic — the parent Jira/Linear issue URL in
      `remote` mode, the path to `tasks/README.md` in `local` mode
    - Any tasks where you were uncertain about scope or estimates
    - **Requirement coverage table** — the table built in the coverage step,
      now complete in both modes, together with its two counts:
      **requirements with no task** and **tasks with no requirement**. Present
      it here in full even in `local` mode, where the epic also carries it —
      the user should not have to open a file to see whether anything went
      unmapped.
    - **File collisions resolved** in the sequencing step, if any: which tasks
      shared a file and how you sequenced them.
    - **Satisfiability notes** from step 6a, if any: Files paths that
      were absent and classified new vs. missing, acceptance criteria
      rewritten or dropped as vacuous, and repo-wide claims that gained
      a runnable citation.

## Task Decomposition Rules

- Database schema changes are always separate tasks from API changes.
- Test-only tasks are acceptable when backfilling coverage for existing code.
- Feature flag setup is its own task.
- Documentation updates are handled by the Documentator Agent, not as tasks.
- Never create a task that spans multiple repositories.
- Split along file boundaries wherever the work allows it. A split that leaves
  two tasks editing the same file has not reduced the risk of the work, it has
  only hidden it behind two task IDs.

## Important

- Task descriptions must be detailed enough for `/sdlc-implement-task` to execute
  without additional context beyond the task description + repo CLAUDE.md.
- The `Implements:` line is read downstream: `/sdlc-implement-task` passes it to
  the Coding Agent, which reports back which requirement each change satisfies.
  Keep the IDs exact — a typo breaks the trace silently.
- The validation step ensures no "NEEDS HUMAN INPUT" sections reach task
  creation. If validation was somehow bypassed, STOP and re-run validation.
- Estimate honestly. A 2-hour optimistic / 40-hour pessimistic task is a sign
  the task needs to be broken down further.