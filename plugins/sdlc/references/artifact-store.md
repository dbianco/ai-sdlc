# Artifact Store Contract

Skills in this plugin read and write artifacts — PRDs, Scoping Docs, Jot Downs,
Data UI Inventories, and tasks — through the operations below. Two
implementations exist. A skill picks one based on `sdlc.mode` and then never
names Notion or Linear again.

## Resolving the mode

Read `sdlc.mode` from `.claude/settings.local.json` in the workspace root.

| Value | Implementation |
| ----- | -------------- |
| `"local"` | Local files, below |
| `"remote"` | Notion + Linear, below |
| absent or empty | `remote` — this is the default, so existing workspaces are unaffected |

If `sdlc.mode` is `"local"` and `.sdlc/` does not exist, create it. That is
idempotent scaffolding, not an error.

## Vocabulary

`feature` — a unit of work with its own document set. Identified by a
three-digit number and a slug: `001-order-export`.

`kind` — one of `prd`, `scoping-doc`, `jotdown`, `data-ui-inventory`.

`ref` — however the user named a thing in `$ARGUMENTS`. Locally a feature ref
is `001`, `order-export`, `001-order-export`, or a path; a task ref is `001-002`
or a path. Remotely a feature ref is a Notion URL or page ID and a task ref is a
Linear issue identifier.

## Operations

| Operation | Local | Remote |
| --------- | ----- | ------ |
| `new_feature(name)` | Create `.sdlc/features/NNN-slug/`, where NNN is the lowest unused three-digit number and slug is the kebab-cased name | Bind the feature to its name — that name titles the Notion page `write_doc` then creates. Create nothing else: no second page, and never a Linear project. Linear is touched only where it always was, by `generate-task-breakdown` |
| `resolve_feature(ref)` | Match ref against directory names under `.sdlc/features/`. On no match, list what exists and ask. On multiple matches, ask | Fetch the Notion page by URL or ID |
| `read_doc(feature, kind)` | Read `<feature-dir>/<kind>.md`. Missing file is a reportable absence, not a crash | `notion-fetch` the page |
| `write_doc(feature, kind, content)` | Write `<feature-dir>/<kind>.md`; return the path relative to the workspace root | Create the page in the configured docs database; return its URL |
| `doc_link(feature, kind)` | Return `./<kind>.md` | Return the Notion page URL |
| `list_tasks(feature)` | Read every `<feature-dir>/tasks/*.md` except `README.md`; parse front-matter | Linear `list_issues` for the project |
| `create_task(feature, task)` | Write `<feature-dir>/tasks/<NNN>-<slug>.md` using the task file format below | Linear `save_issue` |
| `read_task(ref)` | Locate the task file by composite id or path; parse front-matter and body | Linear `get_issue` |
| `update_task_status(ref, status, reason?)` | Rewrite the `status:` front-matter field in place. When `status` is `blocked` and `reason` is given, also write it to `blocked_reason:`. When `status` is `partial` and `reason` is given, write it to `unmet:` as a list (one entry per criterion/label). When `status` is anything other than `blocked`, delete any `blocked_reason:` line the file already carries, and when it is anything other than `partial`, delete any `unmet:` line — a reason must never outlive the state it explains. Leave everything else byte-identical | Update the Linear issue status |
| `create_epic(feature)` | Write `<feature-dir>/tasks/README.md` — the index holding sequencing, critical path, and the requirement coverage table | Create the Linear parent issue |
| `select_grouping()` | Return the milestone name to stamp into each task's `milestone:` field. Take the names from the source documents. If the documents define no milestones, use a single milestone named after the feature. Ask the user nothing | Prompt for the Linear project, then map or create milestones |

## Local layout

```
<workspace-root>/
├── .claude/settings.local.json
├── .sdlc/
│   ├── README.md
│   └── features/
│       └── 001-order-export/
│           ├── prd.md
│           ├── scoping-doc.md
│           ├── jotdown.md
│           ├── data-ui-inventory.md      # only when generated
│           └── tasks/
│               ├── README.md
│               ├── 001-add-status-field.md
│               └── 002-export-endpoint.md
└── <configured repositories>/
```

`.sdlc/` sits at the workspace root because a feature spans repositories — which
is why every task carries a `repository:` field.

`.sdlc/` is committed. These files are the specification.

## Task file format

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

| Field | Required | Notes |
| ----- | -------- | ----- |
| `id` | yes | `<feature-NNN>-<task-NNN>`. The filename carries only the task half |
| `title` | yes | Verb-first |
| `status` | yes | `todo` \| `in_progress` \| `in_review` \| `partial` \| `blocked` \| `done` |
| `kind` | no | `code` (default) \| `acceptance-run`. Code tasks produce source changes; acceptance-run tasks execute an existing artefact against a sequence and record observations. The orchestrator routes to a different agent set for each |
| `milestone` | yes | Free text, from `select_grouping` |
| `repository` | yes | Must match a repository in `.claude/settings.local.json` |
| `depends_on` | no | List of composite task ids |
| `implements` | yes | `REQ-xx`/`US-xx`/`V-xx`, or `INFRA` for work with no user-facing requirement |
| `files` | yes | Expected paths; drives the file-collision check in the breakdown |
| `parallelizable` | no | `true` is the `[P]` marker |
| `estimate` | yes | PERT hours |
| `labels` | no | |
| `blocked_reason` | no | Short free text recording why the task was blocked; present only when `status:` is `blocked`. `update_task_status` removes it as soon as the task leaves that state |
| `unmet` | no | List of acceptance-criterion IDs or short labels the run could not satisfy; present only when `status:` is `partial`. `update_task_status` removes it as soon as the task leaves that state |

Status values mirror Linear's, so reporting language is identical in both modes.

## Failure handling

Every case resolves toward asking or reporting. Never guess.

| Condition | Behavior |
| --------- | -------- |
| `.sdlc/` missing in local mode | Create it; not an error |
| `write_doc` target already exists | Report the existing path and ask before overwriting. Never overwrite silently |
| `new_feature` slug already taken | Reuse the existing directory when the ref clearly names the same feature; otherwise allocate the next free number and say which directory you chose |
| Feature ref matches nothing | List `.sdlc/features/` contents and ask |
| Feature or task ref is ambiguous | Ask |
| Unknown `status:` value | Treat as `todo`, warn, do not rewrite the file |
| Required front-matter field missing | Name the field and stop; do not infer it |
| Task `repository:` not in config | Stop, same as the existing remote-mode check |
| `remote` mode and Notion unreachable | Existing abort behavior, unchanged |
