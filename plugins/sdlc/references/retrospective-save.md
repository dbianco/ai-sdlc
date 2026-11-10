# Post-retrospective ask and save

This is the shared procedure parent skills follow **after** the Skill
Retrospective Agent returns its proposal. The agent only proposes; it never
asks the user and never writes a file. This file is read verbatim by:

- `sdlc-generate-scoping-doc`
- `sdlc-generate-jotdown`
- `sdlc-generate-data-ui-inventory`
- `sdlc-implement-task`

The parent already has the tools this procedure needs: `AskUserQuestion`,
`Read`, `Edit`, and `Write`.

## Inputs

The agent's final message carries a ```retrospective``` fenced JSON block
with these fields:

- `skill` — the skill name
- `recommended_target` — `{ label, path }`
- `alternate_targets` — list of `{ label, path }`
- `lessons` — list of `{ kind, text, duplicate }`
- `today` — `YYYY-MM-DD`

Parse that JSON block first. If it is missing or malformed, do not silently
fall back — report "Retrospective proposal could not be parsed" to the user
and skip the save. Do not invent lessons on the agent's behalf.

## Steps

### 1. Present the proposal and ask

Show the user the two lessons, each labelled with its `kind` and the target
path the agent recommended. Mark any lesson with `duplicate: true` as
"(already captured — will be skipped on save)".

Then ask the user with `AskUserQuestion`, in a single interaction with
**two** questions:

- **Action** (single select): `Save` / `Edit and save` / `Ignore`.
- **Target** (single select): the `recommended_target.label` first (marked
  "(Recommended)"), then every `alternate_targets` entry.

If the user picks `Ignore`, stop — nothing to save. Report "Retrospective
discarded."

If the user picks `Edit and save`, ask one follow-up `AskUserQuestion` per
non-duplicate lesson, with the current text as the default option to accept,
plus an "Other" that lets them rewrite it. Keep the `kind` field unchanged.

### 2. Resolve the target path

The chosen `label` maps to its `path` in the proposal. If the resolved path
is relative, resolve it against the workspace root (`cwd` at the start of
the parent skill run), never against the agent's temporary cwd.

### 3. Write the lessons

For every non-duplicate lesson (post-edit):

1. If the target file does not exist, create it with:

   ```markdown
   # CLAUDE.md

   ## Lessons Learned

   ### <skill-name>
   - <lesson 1> (<today>)
   - <lesson 2> (<today>)
   ```

   where `<today>` is from the proposal. Stop after this — both lessons are
   already in the file.

2. If the file exists but has no `## Lessons Learned` section, append this
   block to the end of the file, separated from the preceding content by a
   single blank line:

   ```markdown

   ## Lessons Learned

   ### <skill-name>
   - <lesson text> (<today>)
   ```

3. If `## Lessons Learned` exists but there is no `### <skill-name>`
   subsection, add it at the end of that section with the lesson line under
   it.

4. If both `## Lessons Learned` and `### <skill-name>` exist, append the
   lesson line to the end of the existing subsection. Preserve every other
   line in the file exactly — never reorder, re-indent, or re-wrap.

### 4. Report

Tell the user:

- The absolute path written to.
- Which lessons were saved and which were skipped (duplicates, or lessons
  the user declined to accept during `Edit and save`).
- If the user chose `Ignore`, that nothing was saved.

## Constraints

- Only touch the `## Lessons Learned` section of the target file. Never edit
  other sections.
- Never use string manipulation that reflows the rest of the file. Use
  targeted edits (append under the right heading) via `Edit`, or `Write` the
  file whole only when it did not exist.
- Never save lessons the agent did not propose. If the agent returned only
  one lesson (a bug), save that one and tell the user; do not invent a
  second.
- Never save on `Ignore`. Never save duplicates.
