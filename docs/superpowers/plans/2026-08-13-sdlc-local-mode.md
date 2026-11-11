# SDLC Local Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the full SDLC pipeline run against markdown files in `.sdlc/`, so the plugin can be evaluated with no Notion workspace and no Jira/Linear team.

**Architecture:** One new reference file defines eleven artifact operations with a local and a remote implementation. Six artifact-touching skills gain a step 0 that resolves `sdlc.mode` and then call operations by name instead of naming Notion or Jira/Linear. `workspace-init` gains the mode question and prunes its Notion/Jira/Linear phases when mode is `local`. No skill logic, gate, or template is duplicated.

**Tech Stack:** Markdown + YAML frontmatter only. No code, no build, no package manager.

**Spec:** `docs/superpowers/specs/2026-08-13-sdlc-local-mode-design.md`

## Testing Note — Read This First

**This repository has no test runner and prompt behavior cannot be unit-tested.** Do not invent one, and do not add a JS/Python test harness.

The TDD cycle in this plan is a **verification cycle** instead. Every task defines a shell check that genuinely fails before the edit and passes after. These are real red-green cycles — run the check and read the output; do not assume.

Behavioral confirmation comes from the smoke-test checklist built in Task 9, run by hand once at the end. Nothing in Tasks 1–8 proves the pipeline *works*, only that it is *wired*. Do not claim otherwise in commit messages.

All commands below are run from the repository root.

## Global Constraints

Copied verbatim from the spec. Every task's requirements implicitly include these.

- `sdlc.mode` accepts `"local"` or `"remote"`. **Absent means `remote`.** Existing workspaces must keep working with zero config changes.
- Skills must **never call Notion or Jira/Linear directly** once converted — only named operations from the contract.
- **Validation gates are unchanged.** They scan document content for `TBD`, `NEEDS HUMAN INPUT`, unresolved `OQ-x`, and unmeasurable acceptance criteria. Do not weaken, duplicate, or mode-branch a gate.
- **No local template files.** Skills already fall back to a structure defined inline in their own body when no Notion template is configured. Local mode uses that existing fallback.
- `.sdlc/` lives at the **workspace root** (sibling of `.claude/`), not inside a repository.
- `.sdlc/` is **committed, not gitignored**.
- Task status vocabulary: `todo` | `in_progress` | `in_review` | `blocked` | `done`.
- Local branch naming: `ai/<feature-NNN>-<task-NNN>-<slug>`, e.g. `ai/001-002-add-csv-export-endpoint`.
- Task filenames carry only the task number (`002-export-endpoint.md`); the composite `id: 001-002` lives in front-matter.
- **No promotion path** to Notion/Jira/Linear. **No `--local` per-run flag.**
- Plugin file references use `${CLAUDE_PLUGIN_ROOT}/...` — never hardcoded paths (existing repo convention).
- Skill folder name must exactly match its `name:` frontmatter field (existing repo convention).
- `.claude/CLAUDE.md` and `AGENTS.md` are mirrors — any edit to one must be made to the other.

## File Structure

**Create:**

| Path | Responsibility |
|---|---|
| `plugins/sdlc/references/artifact-store.md` | The eleven operations and their two implementations. Single source of truth for local paths and mode dispatch. |
| `plugins/sdlc/references/local-mode-smoke-test.md` | Hand-run checklist proving the pipeline works end to end in local mode. |

`references/` is a new directory in the plugin. It holds contracts read by skills at runtime — distinct from `domain-skills/`, which holds coding standards injected into an agent prompt.

**Modify:**

| Path | Change |
|---|---|
| `plugins/sdlc/skills/sdlc-workspace-init/SKILL.md` | Mode question, phase pruning, `.sdlc/` scaffold, summary, auto-default |
| `plugins/sdlc/skills/sdlc-generate-prd/SKILL.md` | Step 0, conditional preflight, `write_doc` |
| `plugins/sdlc/skills/sdlc-generate-scoping-doc/SKILL.md` | Step 0, conditional preflight, `read_doc`/`write_doc`, arg resolution |
| `plugins/sdlc/skills/sdlc-generate-data-ui-inventory/SKILL.md` | Step 0, conditional preflight, `read_doc`/`write_doc`, arg resolution |
| `plugins/sdlc/skills/sdlc-generate-jotdown/SKILL.md` | Step 0, conditional preflight, `read_doc`/`write_doc`, arg resolution |
| `plugins/sdlc/skills/sdlc-generate-task-breakdown/SKILL.md` | Step 0, skip project/milestone pickers in local, `create_task`/`create_epic` |
| `plugins/sdlc/skills/sdlc-implement-task/SKILL.md` | Step 0, `read_task`/`update_task_status`, branch naming |
| `plugins/sdlc/agents/coding-agent.md` | Inputs list: "Jira/Linear issue" → "task" |
| `.claude/CLAUDE.md` + `AGENTS.md` | Document mode, `references/`, local layout — both mirrors |

**Task order is dependency order.** Task 1 defines the vocabulary every later task uses. Task 2 makes mode selectable. Tasks 3–8 convert skills in pipeline order. Task 9 documents and verifies.

---

### Task 1: The artifact store contract

**Files:**
- Create: `plugins/sdlc/references/artifact-store.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the eleven operation names every later task calls — `new_feature`, `resolve_feature`, `read_doc`, `write_doc`, `doc_link`, `list_tasks`, `create_task`, `read_task`, `update_task_status`, `create_epic`, `select_grouping`. Also produces the `kind` vocabulary (`prd`, `scoping-doc`, `jotdown`, `data-ui-inventory`) and the local path convention `.sdlc/features/<NNN-slug>/`.

- [ ] **Step 1: Write the failing verification check**

Create `/tmp/check-task1.sh`:

```bash
#!/usr/bin/env bash
F=plugins/sdlc/references/artifact-store.md
test -f "$F" || { echo "FAIL: $F missing"; exit 1; }
n=$(grep -cE '^\| `[a-z_]+\(' "$F")
test "$n" -eq 11 || { echo "FAIL: expected 11 operation rows, found $n"; exit 1; }
for op in new_feature resolve_feature read_doc write_doc doc_link list_tasks \
          create_task read_task update_task_status create_epic select_grouping; do
  grep -q "$op" "$F" || { echo "FAIL: operation $op not documented"; exit 1; }
done
echo "PASS"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/check-task1.sh`
Expected: `FAIL: plugins/sdlc/references/artifact-store.md missing`

- [ ] **Step 3: Create the contract file**

Create `plugins/sdlc/references/artifact-store.md` with this content:

````markdown
# Artifact Store Contract

Skills in this plugin read and write artifacts — PRDs, Scoping Docs, Jot Downs,
Data UI Inventories, and tasks — through the operations below. Two
implementations exist. A skill picks one based on `sdlc.mode` and then never
names Notion or Jira/Linear again.

## Resolving the mode

Read `sdlc.mode` from `.claude/settings.local.json` in the workspace root.

| Value | Implementation |
| ----- | -------------- |
| `"local"` | Local files, below |
| `"remote"` | Notion + Jira/Linear, below |
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
Jira/Linear issue identifier.

## Operations

| Operation | Local | Remote |
| --------- | ----- | ------ |
| `new_feature(name)` | Create `.sdlc/features/NNN-slug/`, where NNN is the lowest unused three-digit number and slug is the kebab-cased name | Create the Notion page and Jira/Linear project |
| `resolve_feature(ref)` | Match ref against directory names under `.sdlc/features/`. On no match, list what exists and ask. On multiple matches, ask | Fetch the Notion page by URL or ID |
| `read_doc(feature, kind)` | Read `<feature-dir>/<kind>.md`. Missing file is a reportable absence, not a crash | `notion-fetch` the page |
| `write_doc(feature, kind, content)` | Write `<feature-dir>/<kind>.md`; return the path relative to the workspace root | Create the page in the configured docs database; return its URL |
| `doc_link(feature, kind)` | Return `./<kind>.md` | Return the Notion page URL |
| `list_tasks(feature)` | Read every `<feature-dir>/tasks/*.md` except `README.md`; parse front-matter | Jira/Linear `list_issues` for the project |
| `create_task(feature, task)` | Write `<feature-dir>/tasks/<NNN>-<slug>.md` using the task file format below | Jira/Linear `save_issue` |
| `read_task(ref)` | Locate the task file by composite id or path; parse front-matter and body | Jira/Linear `get_issue` |
| `update_task_status(ref, status)` | Rewrite the `status:` front-matter field in place, leaving everything else byte-identical | Update the Jira/Linear issue status |
| `create_epic(feature)` | Write `<feature-dir>/tasks/README.md` — the index holding sequencing, critical path, and the requirement coverage table | Create the Jira/Linear parent issue |
| `select_grouping()` | Return the milestone name to stamp into each task's `milestone:` field. Ask the user only if the source documents define milestones | Prompt for the Jira/Linear project, then map or create milestones |

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
| `status` | yes | `todo` \| `in_progress` \| `in_review` \| `blocked` \| `done` |
| `milestone` | yes | Free text, from `select_grouping` |
| `repository` | yes | Must match a repository in `.claude/settings.local.json` |
| `depends_on` | no | List of composite task ids |
| `implements` | yes | `REQ-xx`/`US-xx`/`V-xx`, or `INFRA` for work with no user-facing requirement |
| `files` | yes | Expected paths; drives the file-collision check in the breakdown |
| `parallelizable` | no | `true` is the `[P]` marker |
| `estimate` | yes | PERT hours |
| `labels` | no | |

Status values mirror Jira/Linear's, so reporting language is identical in both modes.

## Failure handling

Every case resolves toward asking or reporting. Never guess.

| Condition | Behavior |
| --------- | -------- |
| `.sdlc/` missing in local mode | Create it; not an error |
| Feature ref matches nothing | List `.sdlc/features/` contents and ask |
| Feature or task ref is ambiguous | Ask |
| Unknown `status:` value | Treat as `todo`, warn, do not rewrite the file |
| Required front-matter field missing | Name the field and stop; do not infer it |
| Task `repository:` not in config | Stop, same as the existing remote-mode check |
| `remote` mode and Notion unreachable | Existing abort behavior, unchanged |
````

- [ ] **Step 4: Run the check to verify it passes**

Run: `bash /tmp/check-task1.sh`
Expected: `PASS`

- [ ] **Step 5: Commit**

```bash
git add plugins/sdlc/references/artifact-store.md
git commit -m "feat: add artifact store contract for local mode

Defines eleven artifact operations with local-file and Notion/Jira/Linear
implementations, the local .sdlc/ layout, the task file format, and
failure handling. No skill consumes it yet."
```

---

### Task 2: `workspace-init` mode selection and phase pruning

**Files:**
- Modify: `plugins/sdlc/skills/sdlc-workspace-init/SKILL.md` (Phase 1 config block at line 26; Phase 2.2 at line 103; Phase 3 at line 171; Phase 5 at line 262; Phase 8.1 at line 534)

**Interfaces:**
- Consumes: the local layout and mode-resolution rules from Task 1.
- Produces: the `sdlc.mode` config key that Tasks 3–8 read, and a scaffolded `.sdlc/features/` directory with `.sdlc/README.md`.

- [ ] **Step 1: Write the failing verification check**

Create `/tmp/check-task2.sh`:

```bash
#!/usr/bin/env bash
F=plugins/sdlc/skills/sdlc-workspace-init/SKILL.md
grep -q '"mode"' "$F" || { echo "FAIL: sdlc.mode absent from the config block"; exit 1; }
grep -q 'Phase 0' "$F" || { echo "FAIL: no Phase 0 mode question"; exit 1; }
grep -q 'Skip this phase entirely when `sdlc.mode` is `local`' "$F" \
  || { echo "FAIL: phases not pruned for local mode"; exit 1; }
grep -q '.sdlc/features/' "$F" || { echo "FAIL: no .sdlc scaffold step"; exit 1; }
echo "PASS"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/check-task2.sh`
Expected: `FAIL: sdlc.mode absent from the config block`

- [ ] **Step 3: Add `mode` to the config block**

In the JSON block starting at line 26, add `"mode"` as the first key inside `"sdlc"`:

```json
    "sdlc": {
      "mode": "remote",
      "workspace": {
        "name": ""
      },
```

- [ ] **Step 4: Add Phase 0, before Phase 1**

Insert immediately above `### Phase 1 — Read and Assess`:

```markdown
### Phase 0 — Choose the Artifact Store

0.1. **If `sdlc.mode` is already set in `.claude/settings.local.json`, skip this
     phase.** Do not re-ask on every run.

0.2. **Ask where SDLC artifacts should live**, using `AskUserQuestion`:

     "Where should this workspace keep its PRDs, Scoping Docs, Jot Downs, and
     tasks?"

     - **Notion + Jira/Linear** — documents become Notion pages and tasks become
       Jira/Linear issues. Requires a Notion workspace and a Jira/Linear team.
     - **Local files** — everything is markdown under `.sdlc/` in this
       workspace. No external accounts, no setup. You can switch later by
       re-running this skill.

     Write the answer to `sdlc.mode` as `"remote"` or `"local"` respectively.

0.3. **Recommend local mode when the tools are unreachable.** Before asking,
     attempt the Jira/Linear and Notion checks described in Phase 5. If either
     fails, present **Local files** as the recommended option and say why:
     "Notion and/or Jira/Linear are not reachable from this session, so remote mode
     cannot be configured right now. Local mode works immediately and needs no
     accounts."

     Never silently choose for the user — recommend, then let them answer.

0.4. **If the user switches an existing workspace from `local` to `remote`**,
     tell them plainly: "Your existing `.sdlc/` artifacts stay on disk. They
     are not copied to Notion or Jira/Linear — there is no migration. New documents
     will be created in Notion from now on."
```

- [ ] **Step 5: Prune Phase 2.2, Phase 3, and Phase 5**

At the start of the field list in Phase 2.2 (line 103), insert:

```markdown
   **In `local` mode, skip the Jira/Linear team, Notion home directory, Notion docs
   database, and all four template ID fields.** None of them apply — local mode
   uses each skill's inline document structure. Still collect the workspace name
   and the repository list.
```

Immediately under the `### Phase 3` heading (line 171), insert:

```markdown
Skip this phase entirely when `sdlc.mode` is `local`. There is no Notion
database to create.
```

Immediately under the `### Phase 5` heading (line 262), insert:

```markdown
Skip this phase entirely when `sdlc.mode` is `local`. Report "not required in
local mode" for Notion, Jira/Linear, and Figma in the Phase 8 summary instead.
Snyk and Playwright are unaffected — they are local tools and Phase 6 still runs.
```

- [ ] **Step 6: Add the scaffold step and summary line**

Insert a new phase immediately above `### Phase 8 — Summary (Always Runs)`:

```markdown
### Phase 7b — Scaffold the Local Artifact Store (Local Mode Only)

7b.1. **Skip this phase entirely when `sdlc.mode` is `remote`.**

7b.2. **Create `.sdlc/features/`** in the workspace root if it does not exist.

7b.3. **Create `.sdlc/README.md`** if it does not exist, with this content:

      ```markdown
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

      To switch to Notion and Jira/Linear, re-run `/sdlc-workspace-init`. Existing
      files stay on disk; they are not migrated.
      ```

7b.4. **Do not add `.sdlc/` to `.gitignore`.** These artifacts are meant to be
      committed.
```

In Phase 8.1 (line 534), add a line to the configuration summary showing
`Artifact store: Local files (.sdlc/)` or `Artifact store: Notion + Jira/Linear`.

- [ ] **Step 7: Run the check to verify it passes**

Run: `bash /tmp/check-task2.sh`
Expected: `PASS`

- [ ] **Step 8: Commit**

```bash
git add plugins/sdlc/skills/sdlc-workspace-init/SKILL.md
git commit -m "feat: add mode selection and local scaffold to workspace-init

Phase 0 asks where artifacts live and recommends local mode when Notion
or Jira/Linear are unreachable. Local mode prunes the Notion/Jira/Linear phases and
scaffolds .sdlc/. Absent mode still means remote."
```

---

### Task 3: `generate-prd` — the entry point

**Files:**
- Modify: `plugins/sdlc/skills/sdlc-generate-prd/SKILL.md` (step 1 at line 20; step 2 preflight at line 23; step 3 template fetch at line 33; step 6 page creation at line 259; step 7 at line 283)

**Interfaces:**
- Consumes: `new_feature`, `write_doc`, `doc_link` from Task 1; `sdlc.mode` from Task 2.
- Produces: the first feature directory. Every later doc skill resolves against the `NNN-slug` this task allocates.

- [ ] **Step 1: Write the failing verification check**

Create `/tmp/check-skill.sh` — reused by Tasks 3–8:

```bash
#!/usr/bin/env bash
# usage: bash /tmp/check-skill.sh <skill-dir-name>
F="plugins/sdlc/skills/$1/SKILL.md"
grep -q 'Resolve the artifact store' "$F" || { echo "FAIL: $1 has no step 0"; exit 1; }
grep -q 'references/artifact-store.md' "$F" || { echo "FAIL: $1 does not reference the contract"; exit 1; }
echo "PASS: $1"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/check-skill.sh sdlc-generate-prd`
Expected: `FAIL: sdlc-generate-prd has no step 0`

- [ ] **Step 3: Insert step 0 above step 1**

Insert immediately under `## Procedure`:

```markdown
0. **Resolve the artifact store.** Read `sdlc.mode` from
   `.claude/settings.local.json` (absent means `remote`). Read
   `${CLAUDE_PLUGIN_ROOT}/references/artifact-store.md` and use the
   implementation for that mode for every artifact operation named below.
   Never call Notion or Jira/Linear directly.
```

- [ ] **Step 4: Make the Notion preflight conditional**

At step 2 (line 23), change the opening sentence to:

```markdown
2. **Verify Notion permissions — `remote` mode only.** Skip this step entirely
   when `sdlc.mode` is `local`; there is nothing to authorize. In `remote`
   mode, before doing any work, test that the Notion
```

Leave the remainder of step 2 unchanged.

- [ ] **Step 5: Make the template fetch conditional**

At step 3 (line 33), change the opening to:

```markdown
3. **If a PRD template is configured and `sdlc.mode` is `remote`**, fetch it
   from Notion using the MCP and
```

Then append to the end of step 3:

```markdown
   In `local` mode there is no configured template — use the structure defined
   in step 5 of this procedure. Do not create a template file.
```

- [ ] **Step 6: Convert page creation to operations**

Replace step 6 (line 259) with:

```markdown
6. **Write the PRD.** Call `new_feature(<feature name>)` to allocate the
   feature, then `write_doc(feature, prd, <content>)`.

   In `remote` mode this creates the Notion page titled `PRD: <Feature Name>`
   with the properties described below. In `local` mode it writes
   `.sdlc/features/NNN-slug/prd.md` and no properties are needed — the
   directory name carries the feature identity.
```

Keep the existing Notion property list beneath it, prefixed with
`**Remote mode — page properties:**`.

Replace step 7 (line 283) with:

```markdown
7. **Return the artifact reference** to the user — the Notion page URL in
   `remote` mode, or the path returned by `write_doc` in `local` mode.
```

- [ ] **Step 7: Run the check to verify it passes**

Run: `bash /tmp/check-skill.sh sdlc-generate-prd`
Expected: `PASS: sdlc-generate-prd`

- [ ] **Step 8: Commit**

```bash
git add plugins/sdlc/skills/sdlc-generate-prd/SKILL.md
git commit -m "feat: route generate-prd through the artifact store

Adds step 0 mode resolution, makes the Notion preflight and template
fetch remote-only, and replaces page creation with new_feature +
write_doc. PRD structure and ID numbering are unchanged."
```

---

### Task 4: `generate-scoping-doc`

**Files:**
- Modify: `plugins/sdlc/skills/sdlc-generate-scoping-doc/SKILL.md` (`## Input` at line 12; step 1 at line 18; step 2 preflight at line 21; step 3 PRD fetch at line 31; step 10 template at line 153; step 12 page creation at line 220; step 13 at line 234)

**Interfaces:**
- Consumes: `resolve_feature`, `read_doc`, `write_doc` from Task 1; the feature directory created in Task 3.
- Produces: `scoping-doc.md` in the feature directory.

- [ ] **Step 1: Run the check to verify it fails**

Run: `bash /tmp/check-skill.sh sdlc-generate-scoping-doc`
Expected: `FAIL: sdlc-generate-scoping-doc has no step 0`

- [ ] **Step 2: Update the Input section**

Replace the `$ARGUMENTS` line at line 13 with:

```markdown
$ARGUMENTS — In `remote` mode, a Notion URL or page ID pointing to an existing
PRD. In `local` mode, a feature reference — `001`, `order-export`, or
`001-order-export`.
```

- [ ] **Step 3: Insert step 0 above step 1**

Insert immediately under `## Procedure`:

```markdown
0. **Resolve the artifact store.** Read `sdlc.mode` from
   `.claude/settings.local.json` (absent means `remote`). Read
   `${CLAUDE_PLUGIN_ROOT}/references/artifact-store.md` and use the
   implementation for that mode for every artifact operation named below.
   Never call Notion or Jira/Linear directly.
```

- [ ] **Step 4: Make the preflight conditional and convert the PRD fetch**

At step 2 (line 21), change the opening sentence to:

```markdown
2. **Verify Notion permissions — `remote` mode only.** Skip this step entirely
   when `sdlc.mode` is `local`. In `remote` mode, before doing any work, test
   that the Notion
```

Replace step 3 (line 31) with:

```markdown
3. **Read the PRD.** Call `resolve_feature($ARGUMENTS)`, then
   `read_doc(feature, prd)`. Read it completely.

   If the PRD is absent, say so and stop — a Scoping Doc cannot be written
   without it. Do not offer to invent one.
```

- [ ] **Step 5: Convert template fetch and page creation**

At step 10 (line 153), change the opening to:

```markdown
10. **If a scoping doc template is configured and `sdlc.mode` is `remote`**,
    fetch and
```

Replace step 12 (line 220) with:

```markdown
12. **Write the Scoping Doc.** Call `write_doc(feature, scoping-doc, <content>)`.

    In `remote` mode this creates the Notion page titled
    `Scoping: <Feature Name>` with the properties described below. In `local`
    mode it writes `.sdlc/features/NNN-slug/scoping-doc.md`.

    Reference the PRD using `doc_link(feature, prd)` so the link resolves in
    both modes.
```

Keep the existing property list beneath it, prefixed with
`**Remote mode — page properties:**`.

Replace step 13 (line 234) with:

```markdown
13. **Return the artifact reference** to the user — the Notion page URL in
    `remote` mode, or the path returned by `write_doc` in `local` mode.
```

- [ ] **Step 6: Run the check to verify it passes**

Run: `bash /tmp/check-skill.sh sdlc-generate-scoping-doc`
Expected: `PASS: sdlc-generate-scoping-doc`

- [ ] **Step 7: Commit**

```bash
git add plugins/sdlc/skills/sdlc-generate-scoping-doc/SKILL.md
git commit -m "feat: route generate-scoping-doc through the artifact store

Adds step 0, accepts a feature ref in local mode, and replaces the PRD
fetch and page creation with read_doc/write_doc. The PRD completeness
gate is untouched."
```

---

### Task 5: `generate-data-ui-inventory`

**Files:**
- Modify: `plugins/sdlc/skills/sdlc-generate-data-ui-inventory/SKILL.md` (`## Input` at line 14; step 1 at line 20; step 2 preflight at line 23; step 3 PRD fetch at line 46; step 7 template at line 110; step 9 page creation at line 268; step 10 components database at line 281; step 11 at line 284)

**Interfaces:**
- Consumes: `resolve_feature`, `read_doc`, `write_doc` from Task 1.
- Produces: `data-ui-inventory.md` in the feature directory.

- [ ] **Step 1: Run the check to verify it fails**

Run: `bash /tmp/check-skill.sh sdlc-generate-data-ui-inventory`
Expected: `FAIL: sdlc-generate-data-ui-inventory has no step 0`

- [ ] **Step 2: Update the Input section**

Replace the `$ARGUMENTS` line at line 15 with:

```markdown
$ARGUMENTS — In `remote` mode, a Notion URL or page ID pointing to an existing
PRD. In `local` mode, a feature reference — `001`, `order-export`, or
`001-order-export`. A Figma link is required in both modes.
```

- [ ] **Step 3: Insert step 0 above step 1**

Insert immediately under `## Procedure`:

```markdown
0. **Resolve the artifact store.** Read `sdlc.mode` from
   `.claude/settings.local.json` (absent means `remote`). Read
   `${CLAUDE_PLUGIN_ROOT}/references/artifact-store.md` and use the
   implementation for that mode for every artifact operation named below.
   Never call Notion or Jira/Linear directly.
```

- [ ] **Step 4: Split the MCP preflight**

Step 2 (line 23) checks both Notion and Figma. Replace its opening with:

```markdown
2. **Verify MCP permissions.** Check Figma in both modes — it is required for
   this skill regardless of where artifacts live. Check Notion only when
   `sdlc.mode` is `remote`. In `local` mode, skip the Notion check entirely.
```

Leave the individual Notion and Figma check bodies unchanged beneath it.

- [ ] **Step 5: Convert the PRD fetch, template, and page creation**

Replace step 3 (line 46) with:

```markdown
3. **Read the PRD.** Call `resolve_feature($ARGUMENTS)`, then
   `read_doc(feature, prd)`. Read it completely. Also call
   `read_doc(feature, scoping-doc)` — if it exists, read it for milestone and
   architecture context; if not, continue without it.
```

At step 7 (line 110), change the opening to:

```markdown
7. **If a Data UI Inventory template is configured and `sdlc.mode` is
   `remote`**,
```

Replace step 9 (line 268) with:

```markdown
9. **Write the Data UI Inventory.** Call
   `write_doc(feature, data-ui-inventory, <content>)`.

   In `remote` mode this creates the Notion page titled
   `Data UI Inventory: <Feature Name>`. In `local` mode it writes
   `.sdlc/features/NNN-slug/data-ui-inventory.md`.
```

Replace step 10 (line 281) with:

```markdown
10. **Create the Components database — `remote` mode only.** Skip in `local`
    mode: render the component inventory as a markdown table inside the
    document instead, using the same columns. A markdown table carries the same
    information for downstream skills, which read the inventory as text.
```

Replace step 11 (line 284) with:

```markdown
11. **Return the artifact reference** to the user — the Notion page URL in
    `remote` mode, or the path returned by `write_doc` in `local` mode.
```

- [ ] **Step 6: Run the check to verify it passes**

Run: `bash /tmp/check-skill.sh sdlc-generate-data-ui-inventory`
Expected: `PASS: sdlc-generate-data-ui-inventory`

- [ ] **Step 7: Commit**

```bash
git add plugins/sdlc/skills/sdlc-generate-data-ui-inventory/SKILL.md
git commit -m "feat: route generate-data-ui-inventory through the artifact store

Adds step 0, keeps the Figma check in both modes while making the Notion
check remote-only, and renders the component inventory as a markdown
table in local mode instead of a Notion database."
```

---

### Task 6: `generate-jotdown`

**Files:**
- Modify: `plugins/sdlc/skills/sdlc-generate-jotdown/SKILL.md` (`## Input` at line 12; step 1 at line 22; step 2 preflight at line 25; step 3 template at line 38; step 4 source-type table at line 54; step 5 Scoping Doc detection at line 67; step 13 page creation)

**Interfaces:**
- Consumes: `resolve_feature`, `read_doc`, `write_doc`, `doc_link` from Task 1.
- Produces: `jotdown.md` — the document `generate-task-breakdown` consumes in Task 7.

- [ ] **Step 1: Run the check to verify it fails**

Run: `bash /tmp/check-skill.sh sdlc-generate-jotdown`
Expected: `FAIL: sdlc-generate-jotdown has no step 0`

- [ ] **Step 2: Update the Input section**

Replace the `$ARGUMENTS` block at lines 14–16 with:

```markdown
$ARGUMENTS — (optional) The primary source. In `remote` mode: a Scoping Doc
Notion URL, a Jira/Linear issue (URL or `XXX-NNN`), a Slack thread URL, a Notion page
URL, or free text. In `local` mode: a feature reference (`001`, `order-export`,
`001-order-export`) or free text. If omitted, the skill will ask.
```

- [ ] **Step 3: Insert step 0 above step 1**

Insert immediately under `### Setup`:

```markdown
0. **Resolve the artifact store.** Read `sdlc.mode` from
   `.claude/settings.local.json` (absent means `remote`). Read
   `${CLAUDE_PLUGIN_ROOT}/references/artifact-store.md` and use the
   implementation for that mode for every artifact operation named below.
   Never call Notion or Jira/Linear directly.
```

- [ ] **Step 4: Make the preflight and template fetch conditional**

At step 2 (line 25), change the opening sentence to:

```markdown
2. **Verify Notion permissions — `remote` mode only.** Skip this step entirely
   when `sdlc.mode` is `local`. In `remote` mode, test that the Notion MCP can
   both read and
```

At step 3 (line 38), change the opening to:

```markdown
3. **Fetch the Jot Down template.** If `templates.jotdown` is configured and
   `sdlc.mode` is `remote`, fetch it from Notion via `notion-fetch`.
```

- [ ] **Step 5: Add local source resolution to the source-type table**

In the table at step 4 (line 57), add this row above the `Other non-empty text` row:

```markdown
   | A feature ref in `local` mode (`001`, `order-export`, `001-order-export`) | Local feature | `resolve_feature`, then `read_doc` for each kind present |
```

- [ ] **Step 6: Generalize the Scoping Doc detection**

Replace the opening of step 5 (line 67) with:

```markdown
5. **Check whether the source carries a Scoping Doc and a PRD.**

   In `remote` mode: if the source is a Notion page, look for Scoping Doc
   structural markers (milestones section, architectural decisions, affected
   services, linked PRD reference); if found, fetch the linked PRD as well.

   In `local` mode: call `read_doc(feature, scoping-doc)` and
   `read_doc(feature, prd)`. Treat whichever exist as the source documents.

   If both documents are present in either mode:
```

Leave the entire validation-gate body beneath it unchanged — including the
blocking/non-blocking classification. Change only the user-facing remediation
sentence to:

```markdown
     - Tell the user: "The source documents have unresolved items that must be
       completed before a Jot Down can be generated. Please resolve them and
       re-run this skill." Name the file path in `local` mode, or the Notion
       page in `remote` mode.
```

- [ ] **Step 7: Convert page creation**

Replace step 13 with:

```markdown
13. **Write the Jot Down.** Call `write_doc(feature, jotdown, <content>)`.

    In `remote` mode this creates the Notion page titled
    `Jot Down: <Feature Name> (Milestone N: <Name>)`, or
    `Jot Down: <Feature Name>` when covering the full scope, with the
    properties described below. In `local` mode it writes
    `.sdlc/features/NNN-slug/jotdown.md`; the milestone belongs in the document
    body, since one feature directory holds one Jot Down.

    Reference the PRD and Scoping Doc using `doc_link` so links resolve in both
    modes.
```

Keep the existing `docs_database` property list beneath it, prefixed with
`**Remote mode — page properties:**`.

- [ ] **Step 8: Run the check to verify it passes**

Run: `bash /tmp/check-skill.sh sdlc-generate-jotdown`
Expected: `PASS: sdlc-generate-jotdown`

- [ ] **Step 9: Verify the gates survived the edit**

Run:

```bash
grep -c "NEEDS HUMAN INPUT" plugins/sdlc/skills/sdlc-generate-jotdown/SKILL.md
grep -q "measurable" plugins/sdlc/skills/sdlc-generate-jotdown/SKILL.md && echo "12a gate intact"
```

Expected: a non-zero count, and `12a gate intact`. If either fails, the edit
removed a gate — restore it before committing.

- [ ] **Step 10: Commit**

```bash
git add plugins/sdlc/skills/sdlc-generate-jotdown/SKILL.md
git commit -m "feat: route generate-jotdown through the artifact store

Adds step 0, accepts a feature ref as a source type, resolves the
Scoping Doc and PRD through read_doc in local mode, and writes via
write_doc. Both validation gates are unchanged."
```

---

### Task 7: `generate-task-breakdown`

**Files:**
- Modify: `plugins/sdlc/skills/sdlc-generate-task-breakdown/SKILL.md` (`## Input`; step 1; steps 2–3 project and milestone pickers; step 4 document fetch; step 9 parent issue; step 10 sub-issues; step 11 report)

**Interfaces:**
- Consumes: `resolve_feature`, `read_doc`, `select_grouping`, `create_task`, `create_epic` from Task 1; the task file format from Task 1.
- Produces: task files that `implement-task` reads in Task 8, and `tasks/README.md`.

- [ ] **Step 1: Run the check to verify it fails**

Run: `bash /tmp/check-skill.sh sdlc-generate-task-breakdown`
Expected: `FAIL: sdlc-generate-task-breakdown has no step 0`

- [ ] **Step 2: Update the Input section**

Replace the `$ARGUMENTS` line with:

```markdown
$ARGUMENTS — In `remote` mode, a Notion URL or page ID pointing to an existing
Jot Down. In `local` mode, a feature reference — `001`, `order-export`, or
`001-order-export`.
```

- [ ] **Step 3: Insert step 0 above step 1**

Insert immediately under `## Procedure`:

```markdown
0. **Resolve the artifact store.** Read `sdlc.mode` from
   `.claude/settings.local.json` (absent means `remote`). Read
   `${CLAUDE_PLUGIN_ROOT}/references/artifact-store.md` and use the
   implementation for that mode for every artifact operation named below.
   Never call Notion or Jira/Linear directly.
```

- [ ] **Step 4: Replace the project and milestone pickers**

Replace steps 2 and 3 in their entirety with:

```markdown
2. **Establish task grouping.** Call `select_grouping()`.

   In `remote` mode this lists Jira/Linear projects via
   `mcp__claude_ai_Linear__list_projects`, requires the user to pick one via
   `AskUserQuestion`, then lists milestones via
   `mcp__claude_ai_Linear__list_milestones` and maps or creates them with
   `mcp__claude_ai_Linear__save_milestone`. Every issue must belong to a project
   and a milestone. Do not proceed until both are chosen.

   In `local` mode there is no project and no picker. Take the milestone names
   from the source documents and stamp each task's `milestone:` field. If the
   documents define no milestones, use a single milestone named after the
   feature. Ask the user nothing.

3. **Read the source documents.** Call `resolve_feature($ARGUMENTS)`, then
   `read_doc` for each kind: `jotdown` (required — stop if absent),
   `scoping-doc`, `prd`, and `data-ui-inventory` (each optional; continue
   without any that are missing, noting the omission).

   In `remote` mode, follow the reference links inside the Jot Down to reach the
   Scoping Doc and PRD, as before.
```

Renumber the remaining steps so the old step 4 (fetch all source documents) is
absorbed into the new step 3, and steps 5 onward shift down by one. Update the
cross-references inside the skill body that name "step 5" (the validation gate),
"step 7" (task fields), "step 8" (sequencing), and "step 11" (report)
accordingly.

- [ ] **Step 5: Convert issue creation**

Replace step 9 (parent issue) with:

```markdown
9. **Create the epic.** Call `create_epic(feature)`.

   In `remote` mode this creates the parent Jira/Linear issue titled
   `[Feature Name] — Implementation`, labelled `ai-sdlc` and `epic`, in the
   selected project and milestone, with links to all source documents.

   In `local` mode it writes `tasks/README.md` containing: the feature name, a
   link to each source document via `doc_link`, the ordered task list with
   dependencies, the critical path, and the requirement coverage table from
   step 11.
```

Replace step 10 (sub-issues) with:

```markdown
10. **Create each task.** Call `create_task(feature, task)` per task.

    In `remote` mode this creates a Jira/Linear sub-issue under the parent, carrying
    `project` and `milestone`, with dependencies set from the sequencing.

    In `local` mode it writes `tasks/<NNN>-<slug>.md` using the task file format
    in the artifact store contract. Every field defined there is required
    except `depends_on`, `parallelizable`, and `labels`. The `Implements:` line
    becomes the `implements:` front-matter list, and the expected file list
    becomes `files:`.
```

- [ ] **Step 6: Run the check to verify it passes**

Run: `bash /tmp/check-skill.sh sdlc-generate-task-breakdown`
Expected: `PASS: sdlc-generate-task-breakdown`

- [ ] **Step 7: Verify the traceability work from PR #4 survived**

Run:

```bash
F=plugins/sdlc/skills/sdlc-generate-task-breakdown/SKILL.md
grep -q 'Implements' "$F" && grep -q 'Requirement coverage table' "$F" \
  && grep -q 'file collisions' "$F" && echo "traceability intact"
```

Expected: `traceability intact`. If not, the renumbering dropped content —
restore it before committing.

- [ ] **Step 8: Commit**

```bash
git add plugins/sdlc/skills/sdlc-generate-task-breakdown/SKILL.md
git commit -m "feat: route generate-task-breakdown through the artifact store

Adds step 0, collapses the Jira/Linear project and milestone pickers into
select_grouping (a no-prompt path in local mode), and replaces issue
creation with create_epic/create_task. Requirement traceability, file
collision detection, and the completeness gate are unchanged."
```

---

### Task 8: `implement-task` and the Coding Agent

**Files:**
- Modify: `plugins/sdlc/skills/sdlc-implement-task/SKILL.md` (`## Input` at line 15; step 2 at line 22; step 7 branch creation at line 89; step 15 status update)
- Modify: `plugins/sdlc/agents/coding-agent.md` (Inputs list at line 21)

**Interfaces:**
- Consumes: `read_task`, `update_task_status`, `list_tasks` from Task 1; task files from Task 7.
- Produces: nothing downstream. This is the end of the pipeline.

- [ ] **Step 1: Run the check to verify it fails**

Run: `bash /tmp/check-skill.sh sdlc-implement-task`
Expected: `FAIL: sdlc-implement-task has no step 0`

- [ ] **Step 2: Update the Input section**

Replace line 15 with:

```markdown
$ARGUMENTS — In `remote` mode, a Jira/Linear issue identifier (e.g. `YAL-123`). In
`local` mode, a task id (e.g. `001-002`) or a path to a task file.
```

- [ ] **Step 3: Insert step 0 above step 1**

Insert immediately under `## Procedure`:

```markdown
0. **Resolve the artifact store.** Read `sdlc.mode` from
   `.claude/settings.local.json` (absent means `remote`). Read
   `${CLAUDE_PLUGIN_ROOT}/references/artifact-store.md` and use the
   implementation for that mode for every artifact operation named below.
   Never call Notion or Jira/Linear directly.
```

- [ ] **Step 4: Convert the issue fetch**

Replace the opening of step 2 (line 22) with:

```markdown
2. **Read the task.** Call `read_task($ARGUMENTS)`. Read:
   - Title, description, acceptance criteria
   - Parent context — the parent issue in `remote` mode, `tasks/README.md` in
     `local` mode
   - Sibling tasks and their status, via `list_tasks(feature)`
   - Dependencies (ensure they are completed — abort if not). In `local` mode
     these are the `depends_on:` ids; a dependency is complete when its
     `status:` is `done`
   - Labels in `remote` mode, or the `labels:` field in `local` mode (to
     identify target repository, language, and domain)
```

Leave the rest of step 2 — the `Implements:` line, the Files list, and the
`domain_skills` mapping table — unchanged. In `local` mode those come from the
`implements:` and `files:` front-matter fields.

- [ ] **Step 5: Make branch naming mode-aware**

In step 7 (line 89), replace the last line of the code block with:

```
   git checkout -b ai/<task-id>-<slugified-title>
```

and add beneath the block:

```markdown
   `<task-id>` is the Jira/Linear issue id (`yal-123`) in `remote` mode, or the
   composite task id (`001-002`) in `local` mode — producing branches like
   `ai/001-002-add-csv-export-endpoint`.
```

- [ ] **Step 6: Convert the status update**

Replace step 15 with:

```markdown
15. **Update the task status** to in-review. Call
    `update_task_status(ref, in_review)`.

    In `remote` mode this sets the Jira/Linear issue to "In Review". In `local` mode
    it rewrites the `status:` front-matter field to `in_review`, leaving the
    rest of the file byte-identical.
```

- [ ] **Step 7: Update the Coding Agent inputs**

In `plugins/sdlc/agents/coding-agent.md` line 21, replace:

```markdown
- **Jira/Linear issue**: title, description, acceptance criteria
```

with:

```markdown
- **Task**: title, description, acceptance criteria. A Jira/Linear issue in remote
  mode, a task file in local mode — identical content either way
```

- [ ] **Step 8: Run the check to verify it passes**

Run: `bash /tmp/check-skill.sh sdlc-implement-task`
Expected: `PASS: sdlc-implement-task`

- [ ] **Step 9: Verify the domain-skills and security wiring survived**

Run:

```bash
F=plugins/sdlc/skills/sdlc-implement-task/SKILL.md
grep -q 'domain_context' "$F" && grep -q 'Security:' "$F" \
  && grep -q 'Requirement trace' "$F" && echo "pipeline wiring intact"
```

Expected: `pipeline wiring intact`.

- [ ] **Step 10: Commit**

```bash
git add plugins/sdlc/skills/sdlc-implement-task/SKILL.md plugins/sdlc/agents/coding-agent.md
git commit -m "feat: route implement-task through the artifact store

Adds step 0, reads the task via read_task, resolves dependencies from
depends_on in local mode, makes branch naming mode-aware, and sets
in_review via update_task_status. Agent pipeline order and the Security
trailer are unchanged."
```

---

### Task 9: Documentation, mirror sync, and the smoke test

**Files:**
- Create: `plugins/sdlc/references/local-mode-smoke-test.md`
- Modify: `.claude/CLAUDE.md` (Key Directories table; Important Notes)
- Modify: `AGENTS.md` (identical edits — these files are mirrors)

**Interfaces:**
- Consumes: everything from Tasks 1–8.
- Produces: the hand-run checklist that gives this design its actual verdict.

- [ ] **Step 1: Write the failing verification check**

Create `/tmp/check-task9.sh`:

```bash
#!/usr/bin/env bash
test -f plugins/sdlc/references/local-mode-smoke-test.md \
  || { echo "FAIL: smoke test checklist missing"; exit 1; }
grep -q 'references/' .claude/CLAUDE.md || { echo "FAIL: CLAUDE.md missing references/ row"; exit 1; }
grep -q 'sdlc.mode' .claude/CLAUDE.md || { echo "FAIL: CLAUDE.md does not document mode"; exit 1; }
diff -q .claude/CLAUDE.md AGENTS.md >/dev/null || { echo "FAIL: mirrors have drifted"; exit 1; }
# No skill may reach past the contract.
if grep -rlE 'notion-fetch|mcp__claude_ai_Linear' plugins/sdlc/skills \
     | xargs -r grep -L 'artifact-store.md' | grep -q .; then
  echo "FAIL: a skill calls Notion/Jira/Linear without referencing the contract"; exit 1
fi
echo "PASS"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash /tmp/check-task9.sh`
Expected: `FAIL: smoke test checklist missing`

- [ ] **Step 3: Write the smoke-test checklist**

Create `plugins/sdlc/references/local-mode-smoke-test.md`:

```markdown
# Local Mode Smoke Test

Run once by hand, in a scratch directory, after any change to the artifact
store contract or to a skill's step 0. This is the only end-to-end proof that
local mode works — the shell checks in the implementation plan prove wiring,
not behavior.

## Setup

1. `mkdir /tmp/sdlc-smoke && cd /tmp/sdlc-smoke && git init`
2. Create one trivial repository inside it: `mkdir demo-api && cd demo-api &&
   git init && echo "# demo-api" > README.md && git add -A &&
   git commit -m "init" && cd ..`
3. Start Claude Code in `/tmp/sdlc-smoke` with the plugin installed.

## Checks

- [ ] **Init.** Run `/sdlc-workspace-init`. Phase 0 asks where artifacts should
      live. Choose **Local files**.
- [ ] It does **not** ask for a Jira/Linear team, a Notion home directory, a docs
      database, or any template ID.
- [ ] `.sdlc/features/` and `.sdlc/README.md` exist. `.gitignore` does **not**
      mention `.sdlc`.
- [ ] `.claude/settings.local.json` contains `"mode": "local"`.
- [ ] **PRD.** Run `/sdlc-generate-prd` with a one-line feature description.
      `.sdlc/features/001-<slug>/prd.md` exists and contains `REQ-` and `US-`
      ids.
- [ ] **Scoping.** Run `/sdlc-generate-scoping-doc 001`. `scoping-doc.md` exists
      and links to `./prd.md`.
- [ ] **Gate fires.** Edit `prd.md`, replace a requirement with `TBD`, re-run
      the scoping skill. It **stops** and names the offending section. Undo.
- [ ] **Jot Down.** Run `/sdlc-generate-jotdown 001`. `jotdown.md` exists.
- [ ] **Measurable-criteria gate fires.** Ask for an acceptance criterion of
      "must be fast". The skill asks for a threshold instead of inventing one.
- [ ] **Breakdown.** Run `/sdlc-generate-task-breakdown 001`. It asks **no**
      project or milestone question. `tasks/README.md` and at least two
      `tasks/NNN-*.md` files exist.
- [ ] Each task file carries `implements:`, `files:`, `repository: demo-api`,
      and `status: todo`.
- [ ] `tasks/README.md` contains the requirement coverage table with zero
      unmapped requirements.
- [ ] **Implement.** Run `/sdlc-implement-task 001-001`. It creates branch
      `ai/001-001-<slug>` in `demo-api`, runs the Coding and Test agents, asks
      about the security scan, and commits with a `Security:` trailer.
- [ ] The task file's `status:` is now `in_review`.
- [ ] **No leakage.** `grep -ri notion /tmp/sdlc-smoke/.sdlc` returns nothing.

## Teardown

`rm -rf /tmp/sdlc-smoke`
```

- [ ] **Step 4: Update both context mirrors**

In `.claude/CLAUDE.md`, add to the Key Directories table, directly under the
`domain-skills` row:

```markdown
| `plugins/sdlc/references/*.md` | Contracts read by skills at runtime (`artifact-store.md`, `local-mode-smoke-test.md`) |
```

And add to Important Notes:

```markdown
- The pipeline has two artifact backends, selected by `sdlc.mode` in `.claude/settings.local.json`: `remote` (Notion + Jira/Linear, the default when the key is absent) and `local` (markdown under `.sdlc/features/NNN-slug/`). Skills never call Notion or Jira/Linear directly — they use the operations in `plugins/sdlc/references/artifact-store.md`. Local mode exists for zero-setup evaluation; there is no promotion or sync path between the two.
```

Apply the **same two edits verbatim** to `AGENTS.md`. The files are mirrors and
`diff .claude/CLAUDE.md AGENTS.md` must come back empty.

- [ ] **Step 5: Run the check to verify it passes**

Run: `bash /tmp/check-task9.sh`
Expected: `PASS`

- [ ] **Step 6: Verify existing workspaces are unaffected**

Run:

```bash
grep -rq 'absent means `remote`' plugins/sdlc/skills && echo "default preserved"
grep -rc 'sdlc.mode' plugins/sdlc/skills/*/SKILL.md
```

Expected: `default preserved`, and a non-zero count for each of the seven
modified skills.

- [ ] **Step 7: Commit**

```bash
git add plugins/sdlc/references/local-mode-smoke-test.md .claude/CLAUDE.md AGENTS.md
git commit -m "docs: document local mode and add the smoke-test checklist

Adds the hand-run end-to-end checklist, a references/ row in Key
Directories, and a note describing both artifact backends. Applied
identically to both context mirrors."
```

- [ ] **Step 8: Run the smoke test**

Follow `plugins/sdlc/references/local-mode-smoke-test.md` end to end. **Do not
report local mode as working until every box is ticked.** Record any failures
as issues rather than patching them silently — a failed box means the design
was wrong somewhere, and that is worth knowing explicitly.

---

## Self-Review

**Spec coverage.** Every spec section maps to a task: the contract and its
eleven operations → Task 1; the on-disk layout and task file format → Task 1;
config and `workspace-init` → Task 2; the six skill conversions → Tasks 3–8;
agent changes → Task 8; failure modes → Task 1 (documented once in the
contract, where all skills read them); verification → Task 9.

**Deferred items stay deferred.** No task implements a `--local` flag,
promotion, sync, or a `converge` command.

**Naming consistency.** Operation names are identical in Task 1 and in every
call site: `new_feature`, `resolve_feature`, `read_doc`, `write_doc`,
`doc_link`, `list_tasks`, `create_task`, `read_task`, `update_task_status`,
`create_epic`, `select_grouping`. The `kind` values (`prd`, `scoping-doc`,
`jotdown`, `data-ui-inventory`) match the filenames in the layout. Status
values match between the contract, Task 8's `in_review` write, and the smoke
test's assertion.

**Known risk, stated rather than hidden.** Task 7 renumbers steps in
`generate-task-breakdown`, which is the same file that gained requirement
traceability in PR #4. Step 7 of that task exists specifically to catch a
renumbering that drops that content. Review Task 7's diff more carefully than
the others.
