# Onboarding Guide

Welcome! This guide walks you through setting up the AI SDLC plugin on your
machine. Total time: ~15 minutes.

## Prerequisites

- [ ] **Claude Code** — The AI engine the entire plugin runs on. If you haven't installed it yet, that's the first step.
  - 🔍 *Check:* `claude --version` → should print a version number like `1.x.x`
  - 📦 *Install:* Follow the instructions at https://claude.com/claude-code

- [ ] **Claude Code authenticated** — Claude Code must be signed in to connect to Anthropic's servers and run AI models.
  - 🔍 *Check:* Run `claude` in your terminal → if it opens a chat prompt without asking you to sign in, you're good
  - 📦 *Sign in:* Run `claude` and follow the sign-in link it provides.

- [ ] **Node.js v18+ and npm** — Required for the Playwright MCP server, which the plugin uses for browser automation in UI-focused skills. You likely already have this if you do any web development.
  - 🔍 *Check:* `node --version` → should print `v18.x.x` or higher; `npm --version` → should print any version
  - 📦 *Install:* macOS: `brew install node` — or download the **LTS** version from https://nodejs.org

- [ ] **Git SSH access to GitHub** — Skills that write code clone and push to your team's repositories over SSH. Without this, the implementation step will fail.
  - 🔍 *Check:* `ssh -T git@github.com` → should print `Hi <your-username>! You've successfully authenticated`
  - 📦 *Fix:* If it fails, add an SSH key to your GitHub account: https://docs.github.com/en/authentication/connecting-to-github-with-ssh

- [ ] **Your team's Linear team name** — The task breakdown skill creates issues in your team's Linear board and needs to know which team to post to.
  - 🔍 *Check:* It's the name shown at the top of your Linear workspace (e.g. `Commerce`, `Engagement`). Ask your EM if unsure.
  - 📦 *No install needed*

- [ ] **A Notion page URL for AI-generated documents** — Every pipeline output (PRDs, Scoping Docs, Jot Downs) is saved as a Notion page. This URL tells the plugin where to put them.
  - 🔍 *Check:* Ask your PM or EM for the URL of your team's Notion space — usually a team or project page.
  - 📦 *No install needed*

## Step 1 -- Create Your Workspace

A **workspace** is a local directory that groups all the repositories needed
to operate a full-stack domain. The SDLC pipeline works best when it can see
the entire domain at once — frontend, backend, APIs, shared libraries — so
it can trace data flows, plan cross-service changes, and generate accurate
scoping documents and task breakdowns.

**Create one workspace per domain you work on.** Each workspace is a
self-contained project directory where you run `claude` and invoke skills.

### Example workspaces

```
~/code/TextraAI/workspace-commerce/        # Commerce domain
├── api-gateway/                       # API layer
├── commerce-service/                  # Core business logic
├── commerce-web/                      # Frontend
├── payments-service/                  # Payment processing
└── shared-libs/                       # Shared utilities

~/code/TextraAI/workspace-engagement/      # Engagement domain
├── engagement-api/
├── engagement-service/
├── campaigns-service/
├── notifications-service/
└── engagement-web/


### Why full-stack workspaces matter

Because it limit the context of action for agents. This reduces the chances of hallucination and uses less space in the context.
The smaller the surface area, the better the performance

### Set up your workspace

Ask your tech lead or EM which repositories belong to your domain. Then:

```bash
# Commerce domain example
mkdir -p ~/code/TextraAI/workspace-commerce
cd ~/code/TextraAI/workspace-commerce
git clone git@github.com:TextraAI/api-gateway.git
git clone git@github.com:TextraAI/commerce-service.git
git clone git@github.com:TextraAI/commerce-web.git
git clone git@github.com:TextraAI/payments-service.git
git clone git@github.com:TextraAI/shared-libs.git
```

**Rule of thumb:** if a feature in your domain would require changes across
multiple repos, all of those repos should be in your workspace.

## Step 2 -- Install the Plugin

Open Claude Code **from your workspace root** and register the marketplace:

```bash
cd ~/code/TextraAI/workspace-commerce
claude
```

```
/plugin marketplace add TextraAI/ai-sdlc
```

**Exit and restart Claude Code** (`/exit`, then `claude`) so the marketplace
is fully loaded. Then install the plugin:

```
/plugin install sdlc@TextraAI-sdlc
```

**Exit and restart Claude Code again.** The plugin's skills, agents, hooks,
and MCP configuration will be available after this restart.

## Step 3 -- Run the Setup Wizard

Start Claude Code from your workspace root and run the setup wizard:

```bash
cd ~/code/TextraAI/workspace-commerce
claude
```

```
/sdlc-workspace-init
```

The wizard will:
1. **Configure `.claude/settings.local.json`** -- ask for your Linear team
   name, Notion home page URL, and repository list (only asks for values that
   are missing)
2. **Verify MCP integrations** -- test connectivity to Linear, Notion, and
   Figma. If an integration is not yet authenticated, your browser will open
   for sign-in
3. **Show a summary** -- report what is configured, what integrations are
   connected, and what to do next

You can run `/sdlc-workspace-init` again at any time to check your workspace
status. It is idempotent -- it only asks about missing values and always
reports status.

**Repeat this step for each workspace you created.** Each workspace gets its
own `.claude/settings.local.json` with its own Linear team, Notion page, and
repository list.

## Step 4 -- Initialize Your Repositories

Generate the codebase context file for all repositories:

```
/sdlc-init-claude-context --all
```

This scans each repo and generates a `CLAUDE.md` file that the AI uses
to understand the codebase — architecture, conventions, test patterns, and
key directories. Without it, skills produce lower-quality output.

## Step 5 -- Verify Everything Works

Try generating a simple PRD:

```
/sdlc-generate-prd Add a health check endpoint to the API gateway
```

If Claude Code connects to Notion and asks clarifying questions, your setup
is complete.

## The Pipeline

```
/sdlc-workspace-init ──────────────────────► Configured settings.local.json
    │                                    MCP integrations verified
    │                                    (run once per project)
    ▼
Feature Idea
    │
    ▼
/sdlc-generate-prd ──────────────────────► PRD (Notion)
    │                                  11 sections, numbered IDs (G-x, REQ-xx, OQ-x)
    │                                  Human reviews & resolves all TBDs
    ▼
/sdlc-generate-scoping-doc ──────────────► Scoping Doc (Notion)
    │                                  Context, Problem, Solution, Milestones, Risks
    │                                  Human reviews & resolves all TBDs
    ▼
┌──────────────────────────────────────────────────────────┐
│  Two parallel tracks (both feed into the Jot Down):      │
│                                                          │
│  /sdlc-generate-data-ui-inventory ──► Data UI Inventory  │
│       (for features with UI)     Components DB,          │
│                                  Payloads, Figma         │
│                                                          │
│  /sdlc-generate-jotdown ────────────► Jot Down (Notion)  │
│       Accepts any source:        DB changes, APIs,       │
│       Scoping Doc, Linear issue, System design,          │
│       Slack thread, Notion page, Arch decisions          │
│       or free text                                       │
└──────────────────────────────────────────────────────────┘
    │                                  Human reviews & resolves all TBDs
    ▼
/sdlc-generate-task-breakdown ───────────► Linear Issues
    │                                  Parent epic + sub-issues with PERT estimates,
    │                                  dependencies, and sequencing
    ▼
/sdlc-implement-task [LINEAR-ID] ────────► Code + Tests + Docs (GitHub branch)
    │
    │   ┌──────────────────────────────────────────┐
    │   │  Coding Agent → writes code + tests      │
    │   │  Test Agent   → validates (up to 3 loops)│
    │   │  Documentator → updates docs             │
    │   └──────────────────────────────────────────┘
    │
    ▼
Human Review ───────────────────────► PR merged

    ┌──────────────────────────────────────────────────────┐
    │  After each deep-work skill run:                     │
    │  Skill Retrospective Agent → proposes 2 lessons      │
    │  User saves to CLAUDE.md → future runs improve       │
    └──────────────────────────────────────────────────────┘
```

## Skills Reference

### `/sdlc-workspace-init`

Interactive setup wizard that configures `.claude/settings.local.json` and
verifies MCP integration connectivity. **Run this first** when setting up a
new project directory. Idempotent — only asks for missing values, always
reports status.

**Input:** None (interactive wizard)
**Output:** Updated `.claude/settings.local.json`, MCP connectivity report, next steps

---

### `/sdlc-init-claude-context <repo-name>`

Scans a repository and generates a `CLAUDE.md` file with codebase context,
architecture decisions, coding conventions, and testing patterns. Run this
on every repo before using pipeline skills.

**Input:** Repository name from your config
**Output:** `.claude/CLAUDE.md` and `.claude/ARCHITECTURE.md` in each repo

---

### `/sdlc-generate-prd <feature description>`

Generates a Product Requirements Document in Notion. Asks clarifying questions
about business case, personas, scope, and success metrics before writing.

**Input:** Natural language feature description
**Output:** Notion page with 11 sections and numbered IDs (G-x, REQ-xx, US-xx, OQ-x)

---

### `/sdlc-generate-scoping-doc <PRD Notion URL>`

Generates an engineering Scoping Document from a PRD. Reads the target repos'
`CLAUDE.md` files to ground the scoping in the actual codebase.

**Input:** Notion URL of a completed PRD
**Output:** Notion page with Context, Problem, Solution, Milestones, Risks, Affected Services
**Validation gate:** Stops if the PRD has unresolved `TBD`, `NEEDS HUMAN INPUT`, or open `OQ-x` items.

---

### `/sdlc-generate-data-ui-inventory <PRD Notion URL>`

Generates a Data UI Inventory cataloging all frontend components, their data
payloads, and implementation tasks. Uses Figma MCP to pull design data
directly from the linked Figma file.

**Input:** Notion URL of a completed PRD (must include a Figma link in Section 6)
**Output:** Notion page with Overview, Observations, Screenshots, inline Components database, Payloads, Open Questions, Tasks
**Validation gate:** Stops if source documents have unresolved items or missing Figma link.

---

### `/sdlc-generate-jotdown <source>`

Generates a Jot Down Implementation Spec — the detailed technical blueprint
that coding agents use. Includes architectural decisions, database model
changes, API specs, system design, service interactions, deployment stages,
and testing strategy.

Accepts any source type:
- **Scoping Doc** (Notion URL) — the standard pipeline path; also fetches the linked PRD
- **Linear issue** (URL or `XXX-NNN`) — for work already tracked in Linear
- **Slack thread** (URL) — for designs discussed in Slack
- **Notion page** (URL) — any Notion page with context
- **Free text** — describe what needs to be built directly
- **No input** — the skill will ask interactively

The skill asks clarifying questions about affected repos, feature flags, Data
UI Inventory (for frontend work), and GTM events before generating.

**Input:** URL, Linear issue ID, or free text (see list above)
**Output:** Notion page with up to 11 technical sections (some conditional on scope)
**Validation gate:** When the source is a Scoping Doc with a linked PRD, stops if either document has unresolved `TBD`, `NEEDS HUMAN INPUT`, or open `OQ-x` items. Other source types skip this gate.

---

### `/sdlc-generate-task-breakdown <Jot Down Notion URL>`

Decomposes a Jot Down into Linear issues with PERT estimates, dependency
sequencing, and critical path analysis. Asks the user to select a Linear
project before creating any issues.

**Input:** Notion URL of a completed Jot Down
**Output:** Parent Linear issue (epic) + sub-issues with estimates and dependencies
**Validation gate:** Stops if any source document (Jot Down, Scoping Doc, PRD) has unresolved items.

---

### `/sdlc-implement-task <LINEAR-ID>`

Orchestrates the autonomous coding loop. Spawns three agents in sequence:

1. **Coding Agent** — Implements the code changes and writes tests
2. **Test Agent** — Validates coverage, edge cases, lint, and test results. If failures are found, feeds back to the Coding Agent (up to 3 iterations)
3. **Documentator Agent** — Updates README, API docs, inline docs, and changelog

**Input:** Linear issue identifier (e.g. `YAL-123`)
**Output:** Git branch with code, tests, and docs ready for human review

---

### `/sdlc-workspace-sync`

Scan the parent directory and git-update all sibling repositories. Discovers
every first-level git repo automatically — no configuration needed.

**Input:** Optional flags: `--fetch-only`, `--status`
**Output:** Per-repo status table showing branch, pull result, and dirty-file warnings

## Feedback Loop (Lessons Learned)

The pipeline gets better the more you use it. After completing their work, four
skills (`/sdlc-generate-scoping-doc`, `/sdlc-generate-jotdown`,
`/sdlc-generate-data-ui-inventory`, `/sdlc-implement-task`) automatically spawn
a **Skill Retrospective Agent** that:

1. Reflects on what happened during the run
2. Proposes **2 key learnings** — one about what worked well, one about what
   to improve
3. Asks you where to save them:
   - **Workspace CLAUDE.md** — for process lessons applicable across repos
   - **Repo CLAUDE.md** — for lessons specific to a codebase
4. You choose: **Save** / **Edit and save** / **Ignore**

Lessons accumulate in a `## Lessons Learned` section inside CLAUDE.md. Since
skills already read CLAUDE.md, the lessons are automatically incorporated into
future runs — no extra steps needed.

Over time, your workspace builds a tailored knowledge base. For example:
- "API specs should include rate limiting details when the service has external consumers"
- "This service has 50+ DB tables — always include migration rollback plans"
- "When generating milestones, default to user-facing increments not technical layers"

## Validation Gates

Every skill that consumes an upstream document validates it before proceeding.
If any of these markers are found, the skill **stops** and lists every
unresolved item:

- `NEEDS HUMAN INPUT`
- Unresolved Open Questions (`OQ-x` without answers)
- `TBD`, `TODO`, `[placeholder]`, `[to be defined]`
- Empty or stub sections
- Missing Figma links (for Data UI Inventory)
- Incomplete API specs or undefined schemas (for Task Breakdown)

This ensures garbage never flows downstream. Fix the items in Notion, then
re-run the skill.

## Safety Boundaries

Defined in `.claude/settings.local.json` under the `sdlc` key:

- **Restricted paths** -- Files/directories agents must never modify
- **Mandatory human review** -- File patterns (e.g. `.env*`) that always require human review
- **PR size limits** -- Maximum files (`max_files_per_pr: 20`) and lines (`max_lines_per_pr: 500`) per PR

Agents enforce these limits and abort if they would be violated.

## MCP Integrations

| Integration | Type | Purpose |
|-------------|------|---------|
| Notion | Claude built-in integration | Read/write documents |
| Linear | Claude built-in integration | Read/write issues |
| Figma  | Claude built-in integration | Read design files |
| Playwright | Local (bundled in plugin) | Browser automation |

Notion, Linear, and Figma are Claude built-in integrations -- enable them in
your Claude Code settings and authenticate via OAuth when prompted. Playwright
is bundled as a local MCP server inside the plugin and runs via `npx`. It
auto-downloads browser binaries on first use (~150 MB, no auth needed).

## Keeping Repos in Sync

Before starting a new feature pipeline, make sure all repos in your workspace
are up to date:

```
/sdlc-workspace-sync
```

This pulls the latest changes across all sibling repos. Run it at the
start of each work session.

## Updating

Plugins update automatically when the marketplace source changes. To manually
pull the latest version:

```
/plugin marketplace update
```

No file copying or backup steps required.

## Troubleshooting

**Marketplace not found error**
If you see `Marketplace "TextraAI-sdlc" not found`, try using the full GitHub URL instead:

```
/plugin marketplace add https://github.com/TextraAI/ai-sdlc
```

Then exit and restart Claude Code before installing the plugin.

**Marketplace or plugin not showing up after install**
Sometimes Claude Code does not pick up newly added marketplaces or plugins
until you restart the session. Exit Claude Code (`/exit` or Ctrl+C) and start
it again with `claude`. Then run `/plugin marketplace list` or `/plugin list`
to verify.

**MCP integration not connected**
Run `/mcp` and re-authenticate. OAuth tokens can expire. For Notion, Linear,
and Figma, make sure you have enabled the built-in integrations in your Claude
Code settings.

**Playwright MCP fails to start**
Ensure Node.js (v18+) is installed: `node --version`. The Playwright MCP runs
via `npx` and will auto-download browser binaries on first use. If it fails,
try running `npx @playwright/mcp@latest` manually to see the error.

**Skills not showing up**
Verify the plugin is installed: run `/plugin list` and check that
`sdlc@TextraAI-sdlc` appears. If not, re-run the install commands from
Step 2.

**Plugin or marketplace stuck on an old version**
Force a clean reinstall by removing and re-adding:

```
# Force update the marketplace
/plugin marketplace remove TextraAI-sdlc
/plugin marketplace add TextraAI/ai-sdlc

# Exit and restart Claude Code, then force update the plugin
/plugin uninstall sdlc
/plugin install sdlc@TextraAI-sdlc
```

Exit and restart Claude Code after each step to ensure changes take effect.

**Nuclear option -- start over from scratch**
If nothing else works, wipe the plugin and marketplace from your local Claude
Code configuration and redo Step 2:

```bash
# 1. Remove everything
/plugin uninstall sdlc
/plugin marketplace remove TextraAI-sdlc

# 2. Exit Claude Code
/exit

# 3. Delete any cached plugin data
rm -rf ~/.claude/plugins/sdlc
rm -rf ~/.claude/marketplace/TextraAI-sdlc

# 4. Start Claude Code fresh and reinstall from Step 2
claude
/plugin marketplace add TextraAI/ai-sdlc
# Exit and restart
/exit
claude
/plugin install sdlc@TextraAI-sdlc
# Exit and restart
/exit
claude
```

Your `.claude/settings.local.json` is not affected — workspace config is
preserved.

**"Repository not found"**
The repo name you passed to a skill doesn't match any entry in your config.
Check spelling in `.claude/settings.local.json` and ensure the repo is listed.

**Incomplete scoping docs or task breakdowns**
This usually means your workspace is missing repos. If a feature spans
services that aren't in your workspace, the pipeline can't account for them.
Add the missing repos, run `/sdlc-init-claude-context` on each, and re-run
the skill.

## Getting Help

- Plugin issues: file in the `TextraAI/ai-sdlc` repo
- Skill bugs: include the skill name and error output
- Setup problems: include your OS version and Claude Code version
