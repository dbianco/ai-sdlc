---
name: sdlc-generate-task-breakdown
description: Generate Linear issues with PERT sequencing from a Jot Down, Scoping Doc, and Data UI Inventory
disable-model-invocation: true
---

# /sdlc-generate-task-breakdown

Generate Linear issues with PERT sequencing from a Jot Down Implementation
Spec, enriched by the Scoping Doc and Data UI Inventory.

## Input

$ARGUMENTS — A Notion URL or page ID pointing to an existing Jot Down document.

## Procedure

1. **Load `.claude/settings.local.json`** from the project root. Read the `sdlc` config key,
   including the Linear team name and safety boundaries (`max_files_per_pr`,
   `max_lines_per_pr`). These limits constrain the maximum size of any single
   task — defaults are 20 files and 500 lines if not configured.

2. **Ask the user which Linear project to use.** Use the Linear MCP to list
   available projects for the team (`mcp__claude_ai_Linear__list_projects`). Present the
   project names to the user via `AskUserQuestion` and let them pick one.
   All issues created by this skill MUST belong to the selected project.
   Do NOT proceed until the user has selected a project.

3. **Map milestones to Linear project milestones.** Use the Linear MCP to
   list milestones for the selected project (`mcp__claude_ai_Linear__list_milestones`).

   - If the Jot Down covers a specific milestone from the Scoping Doc, ask
     the user which Linear milestone to assign issues to.
   - If the Linear project has no milestones yet, create them from the
     Scoping Doc milestones using `mcp__claude_ai_Linear__save_milestone`. Ask the
     user to confirm before creating.
   - Every issue created by this skill MUST be assigned to a milestone.

4. **Fetch all source documents** from Notion via MCP:
   - **Jot Down** — the primary input (from $ARGUMENTS)
   - **Scoping Doc** — follow the reference link in the Jot Down. Use it for
     milestone context, architectural decisions, affected services, and
     risk mitigations.
   - **PRD** — follow the reference link. Use it for requirements (REQ-xx),
     user stories (US-xx), validation rules (V-xx), and acceptance criteria.
   - **Data UI Inventory** (if it exists) — search for a Data UI Inventory
     linked from the PRD or Scoping Doc, or search Notion for one matching
     the feature name. Use it for component inventory, payloads, and
     frontend task decomposition. If not found, skip frontend-specific
     decomposition from this source.

5. **Validate that all source documents are complete.** Scan all documents
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
     in Notion and re-run this skill."
   - **STOP. Do NOT proceed.** Do not create any Linear issues.

   **If only non-blocking items exist:**
   - List them in an "Acknowledged TBDs (non-blocking)" section so the user
     is aware.
   - **Proceed** with generation.

6. **Decompose into implementable tasks.** Use ALL available source documents:

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

7. **For each task, define:**
   - **Title**: Verb-first, concise (e.g. "Add `status` field to Order model")
   - **Description**: What to implement, with references to the source
     document and section. Include specific file paths, function names, and
     patterns to follow. For frontend tasks from the Data UI Inventory,
     reference the component name, parent, and library components.
   - **Implements**: The upstream requirement IDs this task satisfies —
     `REQ-xx`, `US-xx`, and `V-xx` from the PRD. Write them as a literal
     line in the issue description:

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
     is what makes the task reviewable and lets step 8 detect file collisions.
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
   - **Milestone**: Which Linear milestone this task belongs to (from step 3).

8. **Sequence the tasks** using dependency order. Identify the critical path.
   Group tasks by their Linear milestone.

   Then resolve file collisions using the **Files** list from step 7. Any two
   tasks that touch the same file MUST be sequenced, never marked `[P]` —
   either give one a dependency on the other, or merge them if the split was
   artificial. Two agents editing one file in parallel produce conflicting
   edits and a merge the human has to untangle, which is exactly the
   inconsistency this breakdown exists to prevent.

   Strip `[P]` from any task that fails this check, and report the collisions
   you resolved in step 11.

9. **Create a parent Linear issue** in the configured team **and project**:
   - Title: `[Feature Name] — Implementation`
   - Description: Summary with links to all source documents (Jot Down,
     Scoping Doc, PRD, and Data UI Inventory if available).
   - Label: `ai-sdlc`, `epic`
   - Project: The project selected by the user in step 2.
   - Milestone: The milestone from step 3.

10. **Create sub-issues** under the parent for each task, using the Linear MCP.
    Set dependencies between issues based on the sequencing.
    Every sub-issue MUST include:
    - `project` — the project selected in step 2.
    - `milestone` — the Linear milestone mapped in step 3.

11. **Report to the user:**
    - Total number of issues created, grouped by milestone
    - Critical path and estimated timeline (using PERT expected values)
    - Link to the parent Linear issue
    - Any tasks where you were uncertain about scope or estimates
    - **Requirement coverage table** — one row per `REQ-xx`, `US-xx`, and
      `V-xx` found in the PRD:

      | Requirement | Covered by | Notes |
      | ----------- | ---------- | ----- |
      | REQ-03      | YAL-124, YAL-127 | |
      | US-05       | — | no task created |

      Follow the table with two explicit counts: **requirements with no
      task** and **tasks with no requirement** (`Implements: INFRA` does not
      count as unmapped). Both should be zero. If either is non-zero, list
      the offenders by ID and tell the user which side needs fixing — a
      missing task means the breakdown is incomplete, a missing requirement
      means the PRD is.
    - **File collisions resolved** in step 8, if any: which tasks shared a
      file and how you sequenced them.

## Task Decomposition Rules

- Database schema changes are always separate tasks from API changes.
- Test-only tasks are acceptable when backfilling coverage for existing code.
- Feature flag setup is its own task.
- Documentation updates are handled by the Documentator Agent, not as tasks.
- Never create a task that spans multiple repositories.
- Split along file boundaries wherever the work allows it. A split that leaves
  two tasks editing the same file has not reduced the risk of the work, it has
  only hidden it behind two issue IDs.

## Important

- Task descriptions must be detailed enough for `/sdlc-implement-task` to execute
  without additional context beyond the task description + repo CLAUDE.md.
- The `Implements:` line is read downstream: `/sdlc-implement-task` passes it to
  the Coding Agent, which reports back which requirement each change satisfies.
  Keep the IDs exact — a typo breaks the trace silently.
- The validation in step 5 ensures no "NEEDS HUMAN INPUT" sections reach task
  creation. If validation was somehow bypassed, STOP and re-run validation.
- Estimate honestly. A 2-hour optimistic / 40-hour pessimistic task is a sign
  the task needs to be broken down further.