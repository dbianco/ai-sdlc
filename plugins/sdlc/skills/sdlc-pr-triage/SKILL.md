---
name: sdlc-pr-triage
description: Run Needs Human Review's local triage against the current branch before opening a PR, surface the verdict, and record the JSON report
---

# /sdlc-pr-triage

Run Alfonso Graziano's
[Needs Human Review](https://github.com/alfonsograziano/needs-human-review)
locally against the current branch, before you open a PR. The same gates that
run on GitHub also run here — hard rules first (protected paths, size caps,
lock files), an AI reviewer second — and the verdict is printed back with the
risk level, star confidence, and the files each reviewer read.

This skill does not open the PR, does not push, and does not commit anything.
It only runs the review and shows you what it found, so you can decide to
push as draft, push as ready-for-review, or hold and fix first.

Option B of the Needs Human Review integration. Option A — the GitHub Action
installer — is `/sdlc:sdlc-install-pr-review`.

## Input

$ARGUMENTS — Optional flags, all passed through to the local runner:

- No arguments — review the current branch against the workspace's default
  base branch (see Phase 1.3)
- `--base <ref>` — override the base branch (default: the configured workspace
  default branch, or `origin/main`)
- `--head <ref>` — override the head ref (default: `HEAD`)
- `--harness <name>` — `claude-code` (default), `codex`, or `opencode`
- `--model <name>` — override the harness's default model
- `--dry` — run the hard rules only, do not call a model. Useful to verify the
  tool is reachable and `protected-paths` are set correctly.

## Procedure

### Phase 1 — Pre-flight

1.1. **Confirm this is a git repository**. Run `git rev-parse --is-inside-work-tree`.
   If it fails, stop and say "Not in a git repository."

1.2. **Confirm there is a change to review.** Resolve base and head refs, then
   run `git diff --quiet <base>...<head>`. If the diff is empty, stop and say
   "No commits between <base> and <head> — nothing to review."

1.3. **Pick the base branch.** In order:

   a. `--base <ref>` from `$ARGUMENTS`, if given.
   b. The workspace's configured default branch, if the project root holds a
      `.claude/settings.local.json` with `sdlc.default_base_branch` set.
      (The key may be missing — do not create it.)
   c. The repository's default branch, read from
      `git symbolic-ref refs/remotes/origin/HEAD` and stripped to the branch
      name.
   d. Fall back to `origin/main`.

   Report the resolved base to the user: "Reviewing <head> against <base>."

1.4. **Locate `needs-human-review`.** Check these paths in order and take the
   first that exists and contains `scripts/local-review.ts`:

   a. `$NEEDS_HUMAN_REVIEW_PATH` (env var — user override)
   b. `<workspace root>/../needs-human-review` (sibling of the workspace)
   c. `$HOME/src/needs-human-review`

   If none of them resolves, stop and tell the user:

   ```
   Needs Human Review is not installed locally. Install it once with:

     git clone https://github.com/alfonsograziano/needs-human-review.git ~/src/needs-human-review
     ( cd ~/src/needs-human-review && npm install )

   Then re-run `/sdlc:sdlc-pr-triage`. Set NEEDS_HUMAN_REVIEW_PATH to point
   somewhere else if you prefer a different location.
   ```

   Do not clone it on the user's behalf.

1.5. **Confirm an API key is available for the chosen harness.** Default
   harness is Claude Code. Check for a key in this order:

   a. `API_KEY` (the generic variable the local runner reads)
   b. `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` for `claude-code`
   c. `OPENAI_API_KEY` for `codex`
   d. `OPENCODE_API_KEY` for `opencode`

   If none is set, stop and tell the user which variable the chosen harness
   expects and how to get a key. Do not read secrets from
   `.claude/settings.local.json`.

   Exception: if `--dry` was passed, skip this check — a dry run makes no
   model call.

### Phase 2 — Collect protected paths

2.1. **Read `.claude/settings.local.json`** from the project root if it
   exists. Pull `sdlc.safety_boundaries.restricted_paths` as the default
   protected-paths list.

2.2. **If `restricted_paths` is empty or the file is absent**, warn the user:
   "No protected paths configured — hard rules will only catch forks, lock
   files, size caps, and workflow edits." Continue anyway. The AI review
   still runs.

### Phase 3 — Run the local review

3.1. **Create an output path** in the session scratchpad:
   `<scratchpad>/pr-triage-<timestamp>.json`.

3.2. **Build and run the command.** From the workspace root:

   ```bash
   node "<needs-human-review path>/scripts/local-review.ts" \
     --repo "<workspace root>" \
     --base "<base>" \
     --head "<head>" \
     --harness "<harness>" \
     --json "<output path>" \
     [--protected "<path>"]* \
     [--model "<model>"] \
     [--dry]
   ```

   Append one `--protected` for every entry from Phase 2.1, exactly as
   written. Pass through `--harness`, `--model` and `--dry` from
   `$ARGUMENTS`. Stream the runner's stdout to the user so the progress and
   the final rendered report are visible as they are produced.

3.3. **Give the run a hard time-budget.** If the runner is still going after
   15 minutes, kill it and tell the user. A real review on a medium PR with
   Claude Code finishes in a few minutes — a 15-minute run is a sign
   something is wrong (hung tool, loop, network issue).

### Phase 4 — Interpret the verdict

4.1. **Read the JSON record** from `<output path>`.

4.2. **Pull these fields** from the record (fail-safe on missing keys — the
   runner's output shape is the source of truth, this is only a convenience
   summary):

   - top-level decision: `merged`, `safe`, `needs_human` or `skipped`
   - gate that stopped the run (`stopped-at` or equivalent)
   - risk: `low`, `medium`, or `high`
   - confidence: `1..5`
   - reasons: short list of the rule or finding names

4.3. **Print a one-screen summary** in this shape:

   ```
   Needs Human Review — Local triage
   ──────────────────────────────────────────────────────────
   Branch:       <head>  →  <base>
   Harness:      <harness>  (<model>)
   Decision:     🟢 No human review needed       (or 🔴 Human review required)
   Risk:         <risk>
   Confidence:   ★★★★☆  (<n>/5)
   Stopped at:   <gate>
   Record:       <output path>

   Reasons:
     - <reason 1>
     - <reason 2>
   ```

4.4. **Offer the next step** based on the verdict. Never take the step for
   the user — only recommend.

   - `🟢 No human review needed` with `Confidence ≥ 4`: "Safe to push as
     ready-for-review. When you are, run `gh pr create` yourself."
   - `🔴 Human review required`: "This PR should go up as a draft, or stay
     local until the reasons above are addressed. The record at
     `<output path>` has the full detail."
   - Any other outcome (crash, timeout, unclear verdict): "The triage could
     not reach a clean verdict. Treat this as human-review-required and
     investigate the record at `<output path>`."

### Phase 5 — Clean up

5.1. The temporary worktree is created by the local runner inside the OS
   temp directory and cleaned up by it. This skill does not touch it.

5.2. The JSON record stays in the scratchpad. Do not delete it — the user
   may want to open it after the skill finishes.

## Important

- This skill never pushes, commits, opens a PR, labels, or merges. It only
  reads the branch and reports.
- The review runs in a temporary git worktree created by the local runner at
  the resolved head commit. Your working tree is never touched.
- `--dry` is the right flag for smoke-testing. It skips the model call and
  only exercises the hard gates and the plumbing — cheap, fast, and does
  not need an API key.
- The chosen harness runs in the local runner's restricted mode (read, grep,
  and glob only, inside the review folder). The repo's `.claude/`,
  `CLAUDE.md`, hooks, and MCP servers are not loaded — this is a property of
  Needs Human Review, not something this skill sets up.
- The upstream action is maintained by Alfonso Graziano
  ([`alfonsograziano/needs-human-review`](https://github.com/alfonsograziano/needs-human-review)).
  It is not part of this plugin; the plugin only invokes its local runner.
