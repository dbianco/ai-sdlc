# TextraAI AI SDLC Plugin

An agentic AI-powered Software Development Lifecycle (SDLC) plugin for
[Claude Code](https://claude.com/claude-code). It transforms product ideas into
shipped code through a structured pipeline of AI skills and agents — from PRD
generation through implementation, testing, and documentation.

# [>> INSTALLATION & USAGE GUIDE <<](ONBOARDING.md)

> [!IMPORTANT]
> **If you want to install, set up, or use the plugin, go to [ONBOARDING.md](ONBOARDING.md).**
>
> This README is for **contributors** working on the plugin source code.

## Goal

Achieve **3x engineering productivity** by systematically integrating AI into
every stage of software delivery. Humans remain in control: they make decisions,
review outputs, and approve artifacts at every stage. AI handles the toil.

## Plugin Structure

```
plugins/
└── sdlc/
    ├── .claude-plugin/plugin.json    # Plugin manifest
    ├── skills/                       # 9 slash commands
    │   ├── workspace-init/
    │   ├── init-claude-context/
    │   ├── generate-prd/
    │   ├── generate-scoping-doc/
    │   ├── generate-data-ui-inventory/
    │   ├── generate-jotdown/
    │   ├── generate-task-breakdown/
    │   ├── implement-task/
    │   └── workspace-sync/
    ├── agents/                       # 6 sub-agents
    │   ├── coding-agent.md
    │   ├── test-agent.md
    │   ├── documentator-agent.md
    │   ├── codebase-scanner.md
    │   └── skill-retrospective.md
    ├── hooks/hooks.json              # Event hooks
    ├── scripts/                      # Shell scripts (sync)
    ├── templates/                    # Config templates
    └── .mcp.json                     # Playwright MCP server
```

### Marketplace manifest

`.claude-plugin/marketplace.json` at the repo root defines the marketplace
name (`TextraAI-sdlc`) and lists available plugins. This is what Claude Code reads
when a user runs `/plugin marketplace add`.

### Plugin manifest

`plugins/sdlc/.claude-plugin/plugin.json` defines the plugin metadata (name,
version, author). This is read when a user runs `/plugin install`.

## Contributing

### Local Development Setup

Test changes locally without pushing to GitHub:

```bash
# From a workspace directory (NOT this repo)
cd ~/code/workspace-commerce

# Start Claude Code
claude

# Add the local marketplace (point to your clone of this repo)
/plugin marketplace add /path/to/ai-sdlc

# Install the plugin
/plugin install sdlc@TextraAI-sdlc
```

After making changes to skill/agent files, uninstall and reinstall to pick
them up:

```
/plugin uninstall sdlc
/plugin install sdlc@TextraAI-sdlc
```

### Managing the plugin

```bash
/plugin list                        # List installed plugins
/plugin marketplace list            # List registered marketplaces
/plugin uninstall sdlc              # Uninstall the plugin
/plugin marketplace remove TextraAI-sdlc  # Remove the marketplace
```

### Writing Skills

Each skill lives in `plugins/sdlc/skills/<skill-name>/SKILL.md`:

- YAML frontmatter must include `name` (matching the folder name) and
  `description`
- Users invoke skills as `/sdlc:<skill-name>`
- Use `$ARGUMENTS` to reference user input passed after the slash command
- Reference scripts with `${CLAUDE_PLUGIN_ROOT}/scripts/` — never hardcode
  `.claude/scripts/`
- Set `disable-model-invocation: true` only for skills that run a single bash
  command without AI interpretation

### Writing Agents

Each agent lives in `plugins/sdlc/agents/<agent-name>.md`:

- Specify model in frontmatter (`model: sonnet`, `model: opus`)
- Agents are spawned by skills using the Agent tool
- Define the agent's role, constraints, and expected outputs

### Writing Scripts

Scripts live in `plugins/sdlc/scripts/`:

- Must be bash and executable (`chmod +x`)
- Referenced from hooks via `${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh`
- `workspace-sync.sh` takes an optional project directory argument and mode
  flags

### Hooks

`plugins/sdlc/hooks/hooks.json` maps Claude Code lifecycle events to script
commands. All hooks reference scripts via `${CLAUDE_PLUGIN_ROOT}/scripts/`.

Supported events: `SessionStart`, `SessionEnd`, `UserPromptSubmit`,
`PostToolUse`, `PostToolUseFailure`, `SubagentStart`, `SubagentStop`,
`PreCompact`.

### Configuration Schema

Skills read workspace config from `.claude/settings.local.json` under the
`sdlc` key. The full schema:

```json
{
  "sdlc": {
    "workspace": { "name": "string" },
    "linear": { "team": "string" },
    "notion": {
      "home_directory": "Notion page URL or ID",
      "docs_database": "Notion database ID (auto-populated)"
    },
    "templates": {
      "prd": "Notion page ID",
      "scoping_doc": "Notion page ID",
      "jotdown": "Notion page ID",
      "data_ui_inventory": "Notion page ID"
    },
    "repositories": [
      { "name": "repo-name", "path": "./relative-path" }
    ],
    "feature_flags": "split | env | none",
    "safety_boundaries": {
      "restricted_paths": [],
      "mandatory_human_review": ["**/.env*"],
      "max_files_per_pr": 20,
      "max_lines_per_pr": 500
    }
  }
}
```

`feature_flags` steers the doc generators: `split` asks for Split.io-style fields (name, traffic type, treatments), `env` asks for in-repo fields (flag name, scope, default, fallback), and `none` skips the feature-flag section entirely. The generators ask once if the key is missing.

## Releasing

Releases are managed per-plugin via a GitHub Actions workflow.

### Creating a release

1. Go to **Actions → Release Plugin → Run workflow**
2. Select the `plugin` name (default: `sdlc`) and the `bump` type (`patch`, `minor`, or `major`)
3. The workflow will:
   - Verify the plugin has changes since the last release
   - Bump the version in `plugins/<plugin>/.claude-plugin/plugin.json`
   - Commit, tag (`<plugin>-v<version>`), and push
   - Create a GitHub Release with auto-generated notes

### Versioning policy

This plugin follows [Semantic Versioning](https://semver.org/):

| Bump | When |
|------|------|
| **Major** | Breaking changes to existing skills/agents (renamed, removed, changed interface) or required changes due to Claude plugin system updates |
| **Minor** | New skills/agents, new capabilities in existing ones, meaningful changes to scripts/hooks/MCP config |
| **Patch** | Bug fixes, documentation, templates, cosmetic changes |

The version is kept in sync across `plugins/sdlc/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` — the release workflow updates both automatically.

### Tag convention

Tags follow the format `<plugin>-v<semver>` (e.g., `sdlc-v1.0.2`). This supports multiple plugins in the same marketplace.

### First release for a new plugin

If no previous tag exists for a plugin, the workflow treats it as an initial release and skips change detection. Ensure the plugin's `plugin.json` has a valid starting version before running.

## Feedback Loop (Lessons Learned)

The pipeline includes a built-in feedback loop that helps skills improve over
time. After completing their work, four deep-work skills spawn a **Skill
Retrospective Agent** that:

1. Reflects on the run — what decisions were made, what the user corrected
2. Proposes **2 key learnings** (one positive, one improvement)
3. Asks the user where to save: workspace-level or repo-level CLAUDE.md
4. User chooses: **Save** / **Edit and save** / **Ignore**

Lessons accumulate in a `## Lessons Learned` section inside CLAUDE.md and are
automatically incorporated into future skill runs.

Skills with retrospective: `generate-scoping-doc`, `generate-jotdown`,
`generate-data-ui-inventory`, `implement-task`.

## Team Setup

To auto-install the plugin for every engineer on your team, add this to each
repository's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "TextraAI-sdlc": {
      "source": {
        "source": "github",
        "repo": "TextraAI/ai-sdlc",
        "ref": "main"
      }
    }
  },
  "enabledPlugins": {
    "sdlc@TextraAI-sdlc": true
  }
}
```

When a teammate opens Claude Code in that project, the plugin is installed
automatically. They still need to run `/sdlc-workspace-init` to configure
their local settings and authenticate MCP integrations.

### Lock down to approved marketplaces only

For organizations that need strict control over which plugins engineers can
install, administrators can restrict marketplace sources using
`strictKnownMarketplaces` in [managed settings](https://code.claude.com/docs/en/settings#strictknownmarketplaces)
(read-only, cannot be overridden by users):

```json
{
  "strictKnownMarketplaces": [
    {
      "source": "github",
      "repo": "TextraAI/ai-sdlc",
      "ref": "main"
    }
  ]
}
```

### Pin to a specific version

For stability, pin the marketplace to a specific commit SHA instead of a
branch. This prevents automatic updates until you explicitly bump the SHA:

```json
{
  "extraKnownMarketplaces": {
    "TextraAI-sdlc": {
      "source": {
        "source": "github",
        "repo": "TextraAI/ai-sdlc",
        "ref": "main",
        "sha": "<full-40-char-commit-sha>"
      }
    }
  }
}
```

### Recommended rollout

1. Add `extraKnownMarketplaces` + `enabledPlugins` to one pilot project's
   `.claude/settings.json`
2. Have 2-3 engineers test the full pipeline (`/sdlc-workspace-init` through
   `/sdlc-implement-task`)
3. Once validated, copy the settings block to all team repositories
4. Optionally add `strictKnownMarketplaces` to managed settings for
   org-wide governance

## Maturity Model

Teams progress through three stages per-service:

| Stage | Role of AI | Human Role | Graduation Criteria |
|-------|-----------|------------|---------------------|
| **1 -- Assistant** | Helps humans work faster | Full control | CLAUDE.md in all repos |
| **2 -- Collaborator** | Generates first drafts | Reviews and approves | 90%+ CI pass rate, 80%+ test coverage |
| **3 -- Autonomous** | Handles routine work E2E | Exceptions and strategy | 98% PR approval without modification, 90%+ coverage |

## License

Internal use only. See your organization's policies for details.
