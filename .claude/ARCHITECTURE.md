# Architecture — ai-sdlc

## Overview

A Claude Code plugin that provides an AI-powered SDLC pipeline. The plugin is a collection of markdown skill definitions, agent definitions, bash scripts, and JSON manifests that Claude Code interprets. It lives under `plugins/sdlc/` and is distributed via the `TextraAI-sdlc` marketplace.

## Components

### Skills (11 slash commands)

Each skill is a markdown file with YAML frontmatter defining a structured procedure Claude follows when the user invokes the corresponding slash command.

| Skill | Purpose |
|-------|---------|
| `sdlc-workspace-init` | Guided wizard: configures `.claude/settings.local.json`, verifies MCP connectivity, creates Notion SDLC Documents database |
| `sdlc-generate-prd` | Generates an 11-section PRD in Notion from a feature description |
| `sdlc-generate-scoping-doc` | Generates a Scoping Doc in Notion from a PRD |
| `sdlc-generate-data-ui-inventory` | Generates a frontend component/payload inventory in Notion |
| `sdlc-generate-jotdown` | Generates a self-sufficient Jot Down Implementation Spec from any source (Scoping Doc, Linear issue, Slack thread, or free text) |
| `sdlc-generate-task-breakdown` | Decomposes a Jot Down into PERT-sequenced Linear issues |
| `sdlc-implement-task` | Orchestrates Coding → Test → Security (optional, user-confirmed) → Documentator agents to implement a Linear issue |
| `sdlc-init-claude-context` | Spawns `codebase-scanner` agents to generate `CLAUDE.md`/`ARCHITECTURE.md` for workspace repos |
| `sdlc-install-pr-review` | Installs the `needs-human-review` GitHub Action workflow into each configured repository; seeds inputs from `sdlc.safety_boundaries` |
| `sdlc-pr-triage` | Runs `needs-human-review` locally (`scripts/local-review.ts`) against the current branch and prints the verdict; never pushes or opens a PR |
| `sdlc-workspace-sync` | Runs `workspace-sync.sh` to git-pull all workspace repos |

### Agents (6 sub-agents)

| Agent | Model | Role |
|-------|-------|------|
| `coding-agent` | opus | Implements code changes + tests from a Linear issue |
| `test-agent` | opus | Quality gate: runs tests, checks coverage, writes missing tests, reports PASS/FAIL |
| `security-agent` | sonnet | Optional security gate (user opts in per run): classifies changed files, runs targeted Snyk scans (SAST/SCA/IaC), auto-remediates findings, documents FPs, reports PASS/PASS-WITH-FP/FAIL/SKIPPED |
| `documentator-agent` | opus | Updates inline docs, API specs, README, CHANGELOG after tests pass |
| `codebase-scanner` | sonnet | Scans a repo and generates `CLAUDE.md` + `ARCHITECTURE.md` |
| `skill-retrospective` | haiku | Reflects on a skill run and returns a structured proposal of 2 lessons. The parent skill asks the user and saves to CLAUDE.md via `references/retrospective-save.md` — the agent itself never asks or writes |

### Scripts

- **`workspace-sync.sh`** — Git-syncs all repos; supports `--fetch-only`, `--status`, `--no-recover`.

### Configuration

Per-workspace config in `.claude/settings.local.json` under the `sdlc` key:
- `workspace.name`, `linear.team`, `notion.home_directory`, `notion.docs_database`
- `templates.*` — Notion template page IDs (seeded once, never overwritten)
- `repositories[]` — list of `{name, path}` entries
- `safety_boundaries` — `restricted_paths`, `mandatory_human_review`, `max_files_per_pr` (default 20), `max_lines_per_pr` (default 500)

## Data Flow

### Document Generation Pipeline

```
User idea
  → /sdlc-generate-prd           (Notion PRD)
  → /sdlc-generate-scoping-doc   (Notion Scoping Doc — validates PRD completeness)
  → /sdlc-generate-jotdown       (Notion Jot Down — self-sufficient spec; any source)
      ↗ /sdlc-generate-data-ui-inventory  (parallel, for UI features)
  → /sdlc-generate-task-breakdown (Linear issues with PERT sequencing)
  → /sdlc-implement-task          (code on branch ai/<issue-id>-<title>)
```

### Implementation Loop (implement-task)

```
sdlc-implement-task (orchestrator)
  ├─ Coding Agent     → writes code + unit tests to branch
  ├─ Test Agent       → runs suite, checks coverage, reports PASS/FAIL
  │   └─ (FAIL) → Coding Agent (up to 3 iterations)
  ├─ Security Agent   → OPTIONAL: user is asked each run whether to scan
  │   │                 classifies files, runs Snyk SAST/SCA/IaC scans,
  │   │                 auto-remediates findings (up to 3 cycles),
  │   │                 documents false positives with inline suppressions
  │   └─ (FAIL) → user decides: fix manually / accept risk / abort
  ├─ Documentator Agent → updates docs, CHANGELOG
  └─ skill-retrospective → proposes 2 lessons for CLAUDE.md
```

## Key Abstractions

**Skill frontmatter:** `name` (must match folder), `description`, optional `disable-model-invocation: true`. Skills reference `${CLAUDE_PLUGIN_ROOT}/scripts/` at runtime.

**Self-sufficient Jot Down:** The Jot Down is designed so `generate-task-breakdown` can work from it alone — all milestones, acceptance criteria, service interactions, and architectural decisions are embedded directly (no PRD/Scoping Doc lookup needed at task generation time).

**Validation gates:** `generate-jotdown` and `generate-task-breakdown` both scan source docs for `NEEDS HUMAN INPUT`, `TBD`, unresolved `OQ-x`, and empty sections before proceeding. Blocking markers halt execution with a list of items for the user to resolve.

**Feedback loop:** `skill-retrospective` agent appends lessons to `## Lessons Learned` in CLAUDE.md. Future skill runs consume CLAUDE.md, creating a reinforcement loop without any external state.

**Safety boundaries:** `max_files_per_pr` / `max_lines_per_pr` limits are enforced at both `generate-task-breakdown` (task sizing) and `implement-task` (validation before coding).

## Dependencies

### External Services (MCP — Claude built-in OAuth)
- **Notion** — document creation and reading for all doc-generation skills
- **Linear** — issue fetching, creation, status updates for task breakdown and implementation
- **Figma** — design reference fetching (optional; only for data-ui-inventory)

### Custom MCP
- **Playwright** (`@playwright/mcp@latest` via npx) — browser automation; bundled in `plugins/sdlc/.mcp.json`; downloads ~150 MB of browser binaries on first use
- **Snyk** (direct binary) — security scanning (SAST, SCA, IaC); configured globally in `~/.claude.json` by `/sdlc-workspace-init` (not in `.mcp.json`); requires Snyk account; setup handles OAuth or `SNYK_TOKEN` env var, writes MCP entry with direct binary path, adds tool permissions, and pre-trusts repo directories

### Runtime Dependencies
- `git` — required by `workspace-sync.sh` and `sdlc-implement-task`
- `npx` — required to run Playwright MCP server

### Release Infrastructure
- GitHub Actions: `release-plugin.yml` (manual trigger creates bump PR; on merge creates `sdlc-v*` tag + GitHub Release)
- Version kept in sync between `plugins/sdlc/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` via `.github/scripts/bump-plugin-version.sh`
