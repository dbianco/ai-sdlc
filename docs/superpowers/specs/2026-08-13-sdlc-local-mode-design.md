# SDLC Local Mode — Design

**Date:** 2026-08-13
**Status:** Approved, not yet implemented
**Scope:** `plugins/sdlc` — a file-based artifact backend so the pipeline runs without Notion or Jira/Linear

## Problem

The SDLC pipeline currently cannot start without a configured Notion workspace
and Jira/Linear team. `/sdlc-workspace-init` collects a Jira/Linear team, a Notion home
directory, a docs database, and four Notion template page IDs before anything
else works, and `generate-prd` and `generate-jotdown` each abort on a Notion
permission preflight.

That makes the pipeline impossible to try. Someone who installs the plugin to
see what it does hits a setup wall before producing a single artifact.

GitHub's [Spec Kit](https://github.com/github/spec-kit) (MIT) runs the
equivalent flow entirely on files and directories in the repo. This design
takes that property — and only that property — into our pipeline.

## Purpose

**Zero-setup evaluation.** Install the plugin, run a skill, get artifacts. The
target is that a first run needs no external account, no OAuth, and no
configuration beyond answering one question in `workspace-init`.

This purpose sets the bar for everything below: where fidelity to the
Notion/Jira/Linear flow costs little, keep it; where it costs a lot, drop it and say
so.

## Goals

1. The full four-document chain — PRD → Scoping Doc → Jot Down → Task Breakdown
   — plus `implement-task`, runs against local files.
2. A local run exercises the same templates, the same validation gates, and the
   same requirement traceability as a Notion/Jira/Linear run. What someone evaluates
   is the real product, not a reduced imitation.
3. Existing workspaces are unaffected. No migration, no config rewrite, no
   behavior change when `sdlc.mode` is absent.
4. Exactly one definition of every gate, template, and decomposition rule,
   shared by both modes.

## Non-goals

- **No promotion path.** Local artifacts never become Notion pages or Jira/Linear
  issues. Someone who likes the pipeline configures it properly and re-runs the
  doc chain. This removes template mapping, ID rewriting, and re-run
  idempotency from scope.
- **No bidirectional sync.**
- **No per-run override flag** (`--local`). Mode is config-only. A flag doubles
  the state every skill reasons about to serve a case one config edit already
  covers.
- **No new local templates.** Covered under Decisions below.

## Decisions

| Question | Decision | Consequence |
|---|---|---|
| Primary scenario | Zero-setup evaluation | Optimize first-run friction over feature parity |
| Artifact shape | Mirror the existing four docs as markdown | Skills, gates, and templates stay singly-defined |
| Post-evaluation | Nothing — start fresh in Notion | No export/sync code |
| Mode dispatch | Shared artifact-store contract (not per-skill branching, not a parallel skill family) | One new reference file; skills gain a preamble, not a second narration |

### Why a shared contract rather than inline branching

Inline `if local / else remote` prose in six skills means two parallel
narrations of every step, in files already 165–660 lines long. They drift the
first time someone edits one branch and not the other — a failure this
repository has already produced once, when a Key Directories row landed in
`.claude/CLAUDE.md` but not its mirror `AGENTS.md`.

A parallel `sdlc-local-*` skill family drifts worse and directly contradicts
goal 2.

The contract's cost is real but bounded: an agent must read one extra file, and
a prompt-level contract holds because the skill instructs it to, not because a
compiler enforces it.

### Why no local template files

Each doc skill already fetches its Notion template *only if configured* and
otherwise falls back to a document structure defined inline in the skill body
(`generate-data-ui-inventory` states this explicitly: "Otherwise, use the
default structure below"). Local mode takes that existing fallback path.
Bundling markdown templates would create a third definition of each document's
structure.

## Architecture: the artifact store contract

New file: `plugins/sdlc/references/artifact-store.md`. This introduces a
`references/` directory, which the plugin does not have today.

It defines eleven operations, each with a local and a remote implementation.
Skills invoke operations by name and never reference Notion or Jira/Linear directly.

| Operation | Local | Remote |
|---|---|---|
| `new_feature(name)` | create `.sdlc/features/NNN-slug/`, NNN = next unused | Notion page + Jira/Linear project |
| `resolve_feature(ref)` | match slug, `NNN`, or path under `.sdlc/features/` | Notion URL / page ID |
| `read_doc(feature, kind)` | read `<kind>.md` | fetch Notion page |
| `write_doc(feature, kind, content)` | write `<kind>.md`; return relative path | create page in docs DB; return URL |
| `doc_link(feature, kind)` | relative path (`./prd.md`) | Notion URL |
| `list_tasks(feature)` | parse `tasks/*.md` front-matter | Jira/Linear `list_issues` |
| `create_task(feature, task)` | write `tasks/NNN-slug.md` | Jira/Linear `save_issue` |
| `read_task(ref)` | task file by ID or path | Jira/Linear `get_issue` |
| `update_task_status(ref, status)` | rewrite `status:` front-matter | Jira/Linear status update |
| `create_epic(feature)` | write `tasks/README.md` index | Jira/Linear parent issue |
| `select_grouping()` | `milestone:` front-matter field | Jira/Linear project + milestone pickers |

`kind` is one of `prd`, `scoping-doc`, `jotdown`, `data-ui-inventory`.

### Notes on three operations

**`select_grouping` is where local mode is genuinely simpler.** Steps 2 and 3
of `generate-task-breakdown` — list Jira/Linear projects, require the user to pick
one, list or create milestones, refuse to proceed without both — collapse to a
front-matter field. Removing those two blocking prompts is most of the
first-run speed gain.

**`doc_link` carries the fidelity.** The documents cross-reference each other
("follow the reference link in the Jot Down"), and the validation gates chase
those links to check upstream completeness. Making links an operation means the
chase behaves identically in both modes.

**Task dependencies and the `Implements:` line need no operation.** Both are
front-matter and body text in a task file, which is what they already are
inside a Jira/Linear issue description.

## On-disk layout

```
<workspace-root>/
├── .claude/settings.local.json
├── .sdlc/
│   ├── README.md                         # explains the layout; written by workspace-init
│   └── features/
│       └── 001-order-export/
│           ├── prd.md
│           ├── scoping-doc.md
│           ├── jotdown.md
│           ├── data-ui-inventory.md      # only when generated
│           └── tasks/
│               ├── README.md             # epic index: sequencing, critical path, coverage table
│               ├── 001-add-status-field.md
│               ├── 002-export-endpoint.md
│               └── 003-csv-serializer.md
└── frontend-platform/                    # the configured repositories
```

**`.sdlc/` sits at the workspace root, not inside a repository.** A feature
spans repositories — which is why tasks already carry a `repository:` field —
and the four documents describe the feature rather than any one codebase. This
places `.sdlc/` as a sibling of `.claude/`.

**`.sdlc/` is committed, not ignored.** These files are the specification.

### Task file format

```markdown
---
id: 001-002
title: Add CSV export endpoint
status: todo
milestone: M1 — Core Export
repository: frontend-platform
depends_on: [001-001]
implements: [REQ-03, US-02]
files: [src/api/export.ts, src/api/export.test.ts]
parallelizable: false
estimate: { optimistic: 2, likely: 4, pessimistic: 8 }
labels: [ai-sdlc, typescript]
---

## Description
...

## Acceptance Criteria
- [ ] ...
```

Field reference:

| Field | Required | Source | Notes |
|---|---|---|---|
| `id` | yes | `create_task` | `<feature-NNN>-<task-NNN>`. The **filename** carries only the task half (`002-export-endpoint.md`); the composite id lives in front-matter, so a task is unambiguous once read out of its directory. |
| `title` | yes | breakdown step 7 | verb-first |
| `status` | yes | lifecycle | `todo` \| `in_progress` \| `in_review` \| `blocked` \| `done` |
| `milestone` | yes | `select_grouping` | free text |
| `repository` | yes | breakdown step 7 | must match a configured repository |
| `depends_on` | no | breakdown step 8 | list of task ids |
| `implements` | yes | breakdown step 7 | `REQ-xx`/`US-xx`/`V-xx`, or `INFRA` |
| `files` | yes | breakdown step 7 | expected paths; drives collision detection |
| `parallelizable` | no | breakdown step 8 | `true` == the `[P]` marker |
| `estimate` | yes | breakdown step 7 | PERT hours |
| `labels` | no | breakdown step 7 | |

**Status vocabulary mirrors Jira/Linear's** so `implement-task` sets `in_review` in
both modes and downstream reporting language is unchanged.

**Branch naming becomes `ai/001-002-add-csv-export-endpoint`** — the composite
feature+task id standing in for `YAL-123`. The `ai/<id>-<slug>` shape is
preserved, so nothing downstream of the branch name changes.

## Configuration and `workspace-init`

One new setting, sibling to `workspace` and `repositories`:

```json
"sdlc": {
  "mode": "local",
  "workspace": { "name": "" }
}
```

`"local" | "remote"`. **Absent means `remote`**, so existing workspaces are
untouched and need no migration.

`workspace-init` asks for the mode as its first real decision, and the answer
prunes the wizard:

| Init phase | `remote` | `local` |
|---|---|---|
| 2 — field collection | asks Jira/Linear team, Notion home dir, docs DB, template IDs | skips all |
| 3 — create Notion docs database | runs | skipped |
| 4 — `.claude/CLAUDE.md` | runs | runs |
| 5 — verify Notion / Jira/Linear / Figma | runs; blocks on failure | skipped; summary reads "not required in local mode" |
| 6 — Snyk | runs | runs (local binary, unaffected) |
| new — scaffold `.sdlc/` | — | create `.sdlc/features/` and `.sdlc/README.md` |
| 8 — summary | shows MCP status table | shows mode and `.sdlc/` path |

**Auto-default on unreachable tools.** When init cannot reach Notion or Jira/Linear,
it offers local mode as the recommended option rather than returning a
half-configured workspace, and states plainly that artifacts will live in
`.sdlc/` as markdown and that re-running the skill switches to Notion/Jira/Linear
later.

**Switching modes is a re-run of `workspace-init` and moves nothing.** Given
the no-promotion decision, flipping to `remote` leaves `.sdlc/` in place and
starts fresh upstream. Init says this out loud rather than silently orphaning
the directory.

## Skill changes

Six skills touch artifacts and each gains the same step 0:

> **0. Resolve the artifact store.** Read `sdlc.mode` from
> `.claude/settings.local.json` (absent = `remote`). Read
> `${CLAUDE_PLUGIN_ROOT}/references/artifact-store.md` and use the
> implementation for that mode for every artifact operation named below. Never
> call Notion or Jira/Linear directly.

Each skill body then replaces tool-specific prose with operation names — "create
the Notion page" becomes `write_doc(feature, jotdown)`.

**Validation gates are unchanged.** They scan document content for `TBD`,
`NEEDS HUMAN INPUT`, unresolved `OQ-x`, and unmeasurable acceptance criteria.
Markdown is as scannable as a Notion page.

### `$ARGUMENTS` per mode

| Skill | `remote` | `local` |
|---|---|---|
| `generate-prd` | feature description | unchanged; allocates `NNN-slug/` |
| `generate-scoping-doc` | Notion URL of PRD | feature ref (`001` or `001-order-export`) |
| `generate-jotdown` | URL / ID / free text | feature ref or free text |
| `generate-data-ui-inventory` | Notion URL of PRD | feature ref (Figma URL still required) |
| `generate-task-breakdown` | Notion URL of Jot Down | feature ref |
| `implement-task` | `YAL-123` | task id `001-002` |

### Edits beyond the operation swap

- `generate-prd` step 2 and `generate-jotdown` step 2 — the Notion permission
  preflight that aborts on failure becomes conditional on `remote`.
- `generate-task-breakdown` steps 2–3 — the project picker and milestone
  mapping are skipped in `local`; `select_grouping` supplies the milestone
  field.
- `implement-task` step 15 — "Update the Jira/Linear issue status to In Review"
  becomes `update_task_status(ref, in_review)`.

### Agent changes

- `coding-agent.md` — the inputs list says "Jira/Linear issue"; becomes "task".
- `test-agent.md`, `security-agent.md`, `documentator-agent.md` — unchanged.
  They receive code and file lists, never artifacts.
- `skill-retrospective.md` — unchanged.

## Failure modes

Every case resolves toward asking or reporting, never guessing — consistent
with the Coding Agent's existing "never invent a threshold" rule.

| Condition | Behavior |
|---|---|
| `.sdlc/` missing in local mode | create it; idempotent scaffolding, not an error |
| feature ref not found | list `.sdlc/features/` contents and ask |
| ambiguous ref | ask |
| unknown `status:` value | treat as `todo`, warn, do not rewrite |
| missing required front-matter field | name the field and stop; do not infer |
| `remote` mode, Notion unreachable | existing abort behavior, unchanged |
| task `repository:` not in config | stop; same as the existing remote-mode check |

## Verification

This repository has no test runner, and prompt behavior cannot be unit-tested.
The honest plan is three checks, none of which is a test suite:

1. **Smoke-test checklist**, run once by hand in a scratch workspace: init →
   prd → scoping → jotdown → breakdown → implement against a trivial repo,
   confirming each artifact lands at its expected path and each gate fires.
   Written down as a checklist file so it is repeatable.
2. **Mechanical grep**: no skill references Notion or Jira/Linear outside a mode
   branch or the contract file.
3. **Diff review**: the `remote` path's steps are textually unchanged, so
   existing workspaces provably keep their behavior.

The first real local run is where this design gets its actual verdict.

## Deferred

- Per-run `--local` override
- Promotion of local artifacts to Notion/Jira/Linear
- A `converge`-style command that reconciles `.sdlc/` against the codebase
- Local mode for `sdlc-init-claude-context` and `sdlc-workspace-sync` — neither
  produces feature artifacts, so neither is affected
