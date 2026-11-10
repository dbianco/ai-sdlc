# ai-sdlc

A Claude Code plugin (`sdlc`) providing an AI-powered SDLC pipeline — from PRD generation through implementation. Distributed via the Claude Code plugin marketplace (`TextraAI-sdlc`). No build system, test runner, or CI for the repo itself.

> **Mirror file.** `AGENTS.md` and `.claude/CLAUDE.md` hold identical content — the same repo knowledge served to different agents (`AGENTS.md` for Codex, `.claude/CLAUDE.md` for Claude Code). Edit both, or neither. Never find-and-replace product names or paths between them: the paths below (`.claude-plugin/`, `~/.claude.json`, `.claude/settings.local.json`) are literal names on disk, not references to whichever agent is reading.

## Tech Stack

Markdown + YAML frontmatter (skills/agents), Bash (scripts/hooks), JSON (manifests/config) for the plugin. TypeScript + Node 22 for services under `services/`.

## Commands

```bash
# Local dev: test from a workspace directory (NOT this repo)
/plugin marketplace add /path/to/ai-sdlc
/plugin install sdlc@TextraAI-sdlc
/plugin uninstall sdlc   # pick up changes after editing skill/agent files

# Releasing (GitHub Actions only — never bump versions manually)
# Actions → Release Plugin → Run workflow → select plugin + bump type
```

## Key Directories

| Path | Purpose |
|------|---------|
| `plugins/sdlc/skills/*/SKILL.md` | 11 slash commands (each a markdown + YAML file) |
| `plugins/sdlc/agents/*.md` | 6 sub-agents spawned by skills |
| `plugins/sdlc/domain-skills/*.md` | 5 domain knowledge docs injected into the Coding Agent prompt by `sdlc-implement-task` (not slash commands) |
| `plugins/sdlc/references/*` | Contracts and templates read by skills at runtime (`artifact-store.md`, `local-mode-smoke-test.md`, `needs-human-review-workflow.yml`) |
| `plugins/sdlc/scripts/` | Bash scripts (`workspace-sync.sh`) |
| `plugins/sdlc/hooks/hooks.json` | Lifecycle event hooks (currently empty) |
| `plugins/sdlc/.mcp.json` | Playwright MCP server (only MCP bundled here; Snyk is global via `~/.claude.json`) |
| `plugins/sdlc/.claude-plugin/plugin.json` | Plugin metadata (name, version, author) |
| `.claude-plugin/marketplace.json` | Marketplace definition (`TextraAI-sdlc`) |
| `.github/scripts/bump-plugin-version.sh` | Bumps plugin version in plugin.json + marketplace.json |
| `.github/workflows/release-plugin.yml` | Plugin release: manual bump + on merge: tag, GitHub Release |

## Conventions

**Skill naming:** folder name must exactly match the `name` frontmatter field; all use the `sdlc-` prefix (e.g. `sdlc-generate-prd`). Users invoke as `/sdlc:<skill-name>`.

**Writing skills:** `name` + `description` required in frontmatter; use `$ARGUMENTS` for user input; reference scripts via `${CLAUDE_PLUGIN_ROOT}/scripts/` (never hardcode paths); set `disable-model-invocation: true` only for pure bash commands.

**Writing agents:** `name` + `description` required; `model: opus/sonnet/haiku` recommended; spawned by skills via the Agent tool.

**Scripts:** must be bash and executable (`chmod +x`).

**Workspace config:** lives in `.claude/settings.local.json` under the `sdlc` key; created by `/sdlc-workspace-init`; never modify `sdlc.templates` or `safety_boundaries.restricted_paths` programmatically.

## Plugin Development

When making changes to plugin source files, remember that installed plugin caches may contain stale copies. After editing source, sync/reinstall the plugin so changes take effect.

Typical workflow after editing a skill, agent, script, or manifest under `plugins/sdlc/`:

```bash
# Option A — uninstall/reinstall to force cache refresh
/plugin uninstall sdlc
/plugin install sdlc@TextraAI-sdlc

# Option B — copy edited files directly into the active cache (faster iteration)
cp plugins/sdlc/scripts/<file> ~/.claude/plugins/cache/TextraAI-sdlc/sdlc/<version>/scripts/<file>
```

The cache path pattern is `~/.claude/plugins/cache/TextraAI-sdlc/sdlc/<version>/`. Check `~/.claude/plugins/installed_plugins.json` for the currently installed version. Verify the change took effect by running the modified skill/script and confirming the new behavior — edits to source alone will not propagate to running sessions.

## Feature Flags

No feature flag usage detected in this repo. The doc generators (`sdlc-generate-scoping-doc` step 9, `sdlc-generate-jotdown` step 6b) read `sdlc.feature_flags` from the workspace config and branch on it: `split` prompts for Split.io-style fields (split name, traffic type, treatments, key, evaluation point), `env` prompts for in-repo fields (flag name, scope — env var / settings table / config file —, default, read point, fallback), and `none` skips the flag section entirely. When the key is missing or empty, the skill asks the user once for this run and reminds them to persist it via `/sdlc:sdlc-workspace-init`.

## After Making Changes

After any modification to the AI-SDLC project, check for inconsistencies or gaps introduced by the change:

- **Skill-level change** (editing a `SKILL.md`): review the affected skill — does the description still match the prompt body? Are referenced agents, scripts, or config keys still valid? Do validation gates and output formats align with downstream consumers?
- **Agent-level change** (editing an agent `.md`): review all skills that spawn this agent — do their prompts, expected inputs/outputs, and model assumptions still hold?
- **Cross-cutting change** (scripts, hooks, config, conventions): scan the whole project — skills, agents, scripts, hooks, and manifests — for anything that depends on the changed behavior.

If inconsistencies or gaps are found, report them to the user and ask how they'd like to proceed before making additional fixes.

## Important Notes

- Notion, Linear, and Figma are Claude built-in OAuth integrations — NOT in `.mcp.json`.
- One custom MCP is bundled in `plugins/sdlc/.mcp.json`: Playwright (~150 MB browser download on first use). Snyk is configured globally in `~/.claude.json` (not in `.mcp.json`) by `/sdlc-workspace-init` using the direct binary path.
- `security-agent` uses Snyk MCP tools (`snyk_trust`, `snyk_code_scan`, `snyk_sca_scan`, `snyk_iac_scan`). Snyk setup (install, auth, MCP entry, permissions) is handled entirely by `/sdlc-workspace-init` — the agent SKIPs and directs the user there if Snyk is unavailable. SCA folder trust is established at first scan time via `snyk_trust` (opens browser for approval). It is spawned by `sdlc-implement-task` after the Test Agent PASS, but only if the user opts in — the skill asks on every run whether to scan.
- Releasing: `release-plugin.yml` (manual trigger creates PR; on merge tags + publishes, tags follow `sdlc-v<semver>`).
- Four skills spawn `skill-retrospective` agent at the end: `generate-scoping-doc`, `generate-jotdown`, `generate-data-ui-inventory`, `implement-task`.
- Validation gates in `generate-jotdown` and `generate-task-breakdown` block on `TBD`, `NEEDS HUMAN INPUT`, or unresolved `OQ-x` in source docs. `generate-jotdown` additionally gates on acceptance criteria that are not measurable (unquantified quality adjectives) — it asks the user for a threshold rather than inventing one.
- Requirement traceability runs PRD → Linear → code: `generate-task-breakdown` writes an `Implements: REQ-xx, US-xx` line plus an expected **Files** list on every issue, `implement-task` forwards both to the Coding Agent, and the Coding Agent reports a requirement trace and any scope drift. `INFRA` is the marker for tasks with no user-facing requirement.
- `sdlc-implement-task` orchestrates sub-agents only; it does NOT write code itself. Branch format: `ai/<issue-id>-<slugified-title>`. Pipeline order: Coding Agent → Test Agent → Security Agent (optional — user is asked each run) → Documentator Agent → Commit. The commit always carries a `Security:` trailer, including `SKIPPED — scan declined by user`.
- The pipeline has two artifact backends, selected by `sdlc.mode` in `.claude/settings.local.json`: `remote` (Notion + Linear, the default when the key is absent) and `local` (markdown under `.sdlc/features/NNN-slug/`). Skills never call Notion or Linear directly — they use the operations in `plugins/sdlc/references/artifact-store.md`. Local mode exists for zero-setup evaluation; there is no promotion or sync path between the two.
- `sdlc-install-pr-review` installs `.github/workflows/needs-human-review.yml` into each configured repository from the template at `plugins/sdlc/references/needs-human-review-workflow.yml`. The workflow invokes `alfonsograziano/needs-human-review@v2` (external, Alfonso Graziano), which runs after CI on every PR and decides — hard rules first, AI reviewer second — whether a human reviewer is needed. The skill always writes the file in `mode: shadow` and leaves the file uncommitted. It never changes the workspace config; it reads `sdlc.safety_boundaries.{restricted_paths, max_files_per_pr, max_lines_per_pr}` to seed the workflow inputs. `sdlc-workspace-init` Phase 8.4 points users to this skill when a repository lacks the workflow.
- `sdlc-pr-triage` runs the same `needs-human-review` review locally against the current branch before a PR is opened, using the tool's `scripts/local-review.ts`. It locates the tool via `$NEEDS_HUMAN_REVIEW_PATH`, then `<workspace>/../needs-human-review`, then `$HOME/src/needs-human-review`; if none resolves it prints `git clone` instructions and stops. Defaults to the `claude-code` harness and reads the API key from the environment (`API_KEY`, `ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`, `OPENAI_API_KEY`, or `OPENCODE_API_KEY`). It never pushes, commits, or opens a PR — only reports the verdict and the JSON record path.

## Lessons Learned

### sdlc-implement-task
- Use Yarn (not npm) for all TypeScript services in this repo — save package manager preference to memory early to prevent rework across agent iterations (2026-03-26)
- When scaffolding services requiring Node 22+ (e.g. for node:sqlite), include the Node version requirement explicitly in task context so the Coding Agent doesn't discover runtime constraints mid-run (2026-03-26)
