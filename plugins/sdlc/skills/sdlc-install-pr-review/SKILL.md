---
name: sdlc-install-pr-review
description: Install the Needs Human Review GitHub Action workflow into one or more configured repositories, seeded from the workspace's safety boundaries
---

# /sdlc-install-pr-review

Install Alfonso Graziano's
[Needs Human Review](https://github.com/alfonsograziano/needs-human-review)
GitHub Action into one or more repositories configured in this workspace. The
action runs after CI completes on every PR and decides — by hard rules you
control first, an AI reviewer second — whether the PR needs a human reviewer
or can merge on its own.

This skill is **idempotent**. On repeat runs it skips repositories that already
have `.github/workflows/needs-human-review.yml`. A re-install for a single repo
is possible via `--repo <name> --force`.

The installed workflow starts in `mode: shadow` by default: it only comments
on PRs with what it would have done and changes nothing. Move it up to
`advisory` or `autonomous` by editing the file in each repository.

## Input

$ARGUMENTS — Optional flags:

- No arguments — guided wizard across all repositories in `sdlc.repositories`
  that do not already have the workflow
- `--repo <name>` — install only in the named repository (as listed in
  `sdlc.repositories`)
- `--force` — overwrite an existing `.github/workflows/needs-human-review.yml`
  (only valid with `--repo`)

## Procedure

### Phase 1 — Read workspace config

1.1. **Read `.claude/settings.local.json`** from the project root. If the file
   does not exist, or has no `sdlc` key, stop and tell the user:
   "No workspace config found. Run `/sdlc:sdlc-workspace-init` first."

1.2. **Extract these values:**

   - `sdlc.repositories` — list of `{name, path}` entries.
   - `sdlc.safety_boundaries.restricted_paths` — seed for `protected-paths`.
   - `sdlc.safety_boundaries.max_files_per_pr` — seed for `max-files-changed`.
   - `sdlc.safety_boundaries.max_lines_per_pr` — seed for `max-lines-changed`.

   If `sdlc.repositories` is missing or empty, stop and tell the user:
   "No repositories configured in this workspace. Add them with
   `/sdlc:sdlc-workspace-init` first."

### Phase 2 — Pick the repositories

2.1. **If `--repo <name>` was passed**, restrict the target list to that one
   repository. If the name is not in `sdlc.repositories`, stop and list the
   known names.

2.2. **Otherwise, inspect every repository** and classify each as:

   - **installed** — `<repo path>/.github/workflows/needs-human-review.yml`
     already exists. Skip unless `--force` is set.
   - **missing** — the file is absent. Candidate for install.
   - **unreachable** — the repository path does not exist on disk. Report
     and skip.

   Show the user the full list, mark each row with its classification, and
   ask with `AskUserQuestion` which of the **missing** repositories to install
   into. Default: all of them.

   If every configured repository is already installed, say so and stop —
   there is nothing to do.

### Phase 3 — Collect per-repo settings

For each target repository, ask the user — in a single interaction per repo —
these three things:

3.1. **CI workflow name.** Scan `<repo path>/.github/workflows/*.yml` and read
   the `name:` field of each file. If exactly one is found, propose it as the
   default. If more than one is found, list them and propose the one named
   `CI` if present, otherwise the first alphabetically. If none are found,
   warn: "No existing workflows found. You will need to create a CI workflow
   before Needs Human Review can trigger." and ask the user to name the one
   they plan to add.

   The value typed here replaces `__CI_WORKFLOW_NAME__` in the template.

3.2. **Protected paths.** Show the user the current
   `sdlc.safety_boundaries.restricted_paths` as the default. If that list is
   empty, show this starter list instead and tell them it is a guess:

   ```
   **/migrations/**
   **/*.tf
   **/charge*.ts
   **/payment*.ts
   .env*
   ```

   Let the user edit, accept, or type `none` to install with an empty list
   (the AI reviewer still runs — the user is only giving up the hard-rule
   protection for specific paths). Do not modify
   `sdlc.safety_boundaries.restricted_paths` — the workspace config is managed
   by `/sdlc:sdlc-workspace-init` and must not change here.

3.3. **Size caps.** Seed `max-files-changed` from
   `sdlc.safety_boundaries.max_files_per_pr` and `max-lines-changed` from
   `sdlc.safety_boundaries.max_lines_per_pr`. If either is missing in the
   workspace config, default to `0` (off). Show the two seeded values and ask
   the user to accept or change them. Always write the value as a quoted
   string in the YAML — the action's input is a string.

### Phase 4 — Write the workflow files

4.1. **For each target repository**, do these steps:

   a. **Ensure `<repo path>/.github/workflows/` exists.** Create it if missing.
      Do not touch any other file under `.github/`.

   b. **Read the template** from
      `${CLAUDE_PLUGIN_ROOT}/references/needs-human-review-workflow.yml`.

   c. **Substitute the placeholders** in the template content, in memory:

      | Placeholder               | Replacement                                           |
      |--------------------------|--------------------------------------------------------|
      | `__CI_WORKFLOW_NAME__`   | The name from 3.1, as-is                              |
      | `__PROTECTED_PATHS__`    | The list from 3.2, one entry per line, indented to match the surrounding YAML block |
      | `__MAX_FILES_CHANGED__`  | The value from 3.3, as a string                        |
      | `__MAX_LINES_CHANGED__`  | The value from 3.3, as a string                        |

      If the user typed `none` for protected paths, emit an empty block — keep
      the `protected-paths: |` key and put a single blank line under it, so
      the YAML parses and the action reads an empty list.

   d. **Write** the result to
      `<repo path>/.github/workflows/needs-human-review.yml` as UTF-8 with a
      trailing newline. Never use string manipulation that could reflow the
      rest of the file — this is a fresh write of a template, not an edit.

   e. **Verify** the file parses as valid YAML by piping it through
      `python3 -c 'import sys, yaml; yaml.safe_load(sys.stdin.read())'` or an
      equivalent check available in the session. If parsing fails, delete the
      file and report the error — never leave a broken workflow on disk.

   f. **Record** the result: installed / skipped / failed, with the path
      written.

### Phase 5 — Report and next steps

5.1. **Print an installation table**:

   ```
   Needs Human Review — Installation Summary
   ─────────────────────────────────────────────────────────────────
   Repository          Path                    Status
   ─────────────────────────────────────────────────────────────────
   api-gateway         ./api-gateway           Installed (shadow)
   commerce-service    ./commerce-service      Already installed — skipped
   web-app             ./web-app               Failed — YAML parse error
   ```

5.2. **Print the required next steps** for every repository that was just
   installed, exactly once (not per-repo):

   ```
   Before this gate takes effect:

   1. Add an Anthropic API key to each of these repositories as a secret
      named `API_KEY`:
        Settings → Secrets and variables → Actions → New repository secret

   2. Commit and merge .github/workflows/needs-human-review.yml into the
      default branch of each repository. GitHub only runs `workflow_run`
      workflows from the default branch — nothing happens until it is there.

   3. Leave it in `shadow` mode for a few weeks and compare its verdicts to
      what your reviewers decided. Edit the file to switch to `advisory` or
      `autonomous` when you are ready.
   ```

5.3. **If the workspace has an `sdlc` plugin version pinned** elsewhere, do
   not mention it. The installed workflow pins
   `alfonsograziano/needs-human-review@v2`, which follows the latest 2.x
   release. Users can tighten that to a specific tag or SHA by editing the
   workflow directly.

## Important

- This skill writes exactly one file per selected repository:
  `.github/workflows/needs-human-review.yml`. It never edits existing
  workflows, never changes `.github/CODEOWNERS`, and never changes the
  workspace `.claude/settings.local.json`.
- The template at `${CLAUDE_PLUGIN_ROOT}/references/needs-human-review-workflow.yml`
  is the source of truth. If you need to change the pinned action version,
  `actions/checkout` flags, or default permissions, edit the template — not
  the generated files in target repos.
- Never commit, push, or open a PR from this skill. The generated workflow is
  left uncommitted so the user can inspect it, adjust `protected-paths`, and
  decide when to merge it into the default branch.
- This skill is only Option A of the Needs Human Review integration. Option B
  — a local pre-push triage that runs the same review against the current
  branch before a PR is opened — is tracked separately.
- The upstream action is maintained by Alfonso Graziano
  ([`alfonsograziano/needs-human-review`](https://github.com/alfonsograziano/needs-human-review)).
  It is not part of this plugin; the plugin only installs the workflow that
  invokes it.
