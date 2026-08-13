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
- [ ] It does **not** ask for a Linear team, a Notion home directory, a docs
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

## Mode switch

Run these last — the first one leaves the workspace in `remote` mode until the
final check puts it back.

- [ ] **An ordinary re-run does not re-ask.** Run `/sdlc-workspace-init` with
      no arguments. It does **not** ask where artifacts should live; the mode
      already on disk is kept, and the summary still prints the "To switch
      artifact stores later" line.
- [ ] **The flag reopens the choice.** Run
      `/sdlc-workspace-init --switch-mode`. Phase 0 asks again. Choose
      **Notion + Linear**.
- [ ] It states that nothing is migrated — existing `.sdlc/` files stay on
      disk and are not copied to Notion or Linear.
- [ ] `.claude/settings.local.json` now contains `"mode": "remote"`, and
      `.sdlc/features/001-<slug>/` still holds every file created above,
      unchanged.
- [ ] **Switch back.** Run `/sdlc-workspace-init --switch-mode` again and
      choose **Local files**. The file reads `"mode": "local"` again, and
      `.sdlc/` is still intact. `/sdlc-implement-task 001-001` resolves the
      same task file as before.

## Teardown

`rm -rf /tmp/sdlc-smoke`
