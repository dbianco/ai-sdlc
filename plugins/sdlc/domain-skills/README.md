# Domain Skills

These files are **not slash commands**. They are markdown knowledge documents
injected into the Coding Agent's Task prompt by `/sdlc-implement-task` when a
matching tech domain is detected from the Jira/Linear issue.

They are read from `${CLAUDE_PLUGIN_ROOT}/domain-skills/` — they ship with the
plugin and require no per-workspace setup.

## How Detection Works

`sdlc-implement-task` builds a `domain_skills` list using three signal sources, in
priority order:

1. **Jira/Linear labels** (highest confidence) — explicit labels set by the team
2. **CLAUDE.md `## Tech Stack` section** — `Language:` / `Framework:` fields
3. **Issue title + description keywords** (fallback) — keyword scan

Multiple domain files can match simultaneously (e.g. a full-stack issue loads
both `golang.md` and `frontend-react.md`). If nothing matches, the Coding Agent
runs with CLAUDE.md context only.

## Label / Keyword → File Mapping

| Jira/Linear Label                       | CLAUDE.md Keyword                                  | Issue Keywords                     | Domain File           |
| ---------------------------------- | -------------------------------------------------- | ---------------------------------- | --------------------- |
| `golang`, `go`, `go-service`       | `Language: Go`                                     | `goroutine`, `gRPC`, `golang`      | `golang.md`           |
| `frontend`, `react`, `web-app`     | `Language: TypeScript` + `Framework: React`        | `component`, `suspense`, `MUI`     | `frontend-react.md`   |
| `design`, `ui-design`              | (React + design/styling intent in issue body)      | `design`, `aesthetic`, `visual`    | `frontend-design.md`  |
| `backend`, `node`, `api`, `express`| `Language: TypeScript` + `Framework: Express`      | `controller`, `Prisma`, `Zod`      | `backend-node.md`     |
| `accessibility`, `web-design`, `audit` | —                                              | `a11y`, `audit`, `accessibility`   | `web-design-audit.md` |

Notes:
- `frontend-design.md` co-activates with `frontend-react.md` only when the issue
  explicitly involves design, styling, or visual work.
- `backend-node.md` uses a TypeScript + Express conjunction to distinguish from
  React TypeScript frontends.
- `web-design-audit.md` fetches Vercel Labs guidelines at runtime via WebFetch —
  it is procedure-driven, not static. The orchestrator should fetch-and-inline
  the content before passing it to the Coding Agent.

## Updating Skill Content

These files are curated copies of skills from
[`antigravity-awesome-skills`](https://github.com/antigravity-awesome-skills).

To sync a file with its upstream source:

1. Read the upstream SKILL.md from the source repo.
2. Strip the YAML frontmatter block (`---` … `---`).
3. Replace the content after the Yalo preamble comment block (lines 1–6) with
   the updated upstream body.
4. Update the `Last synced:` date in line 2 of the file.

## File Format

Each file follows this structure:

```markdown
<!-- Source: antigravity-awesome-skills/skills/<skill-name> — curated for Yalo SDLC -->
<!-- Last synced: YYYY-MM-DD -->

# <Title> (Yalo SDLC)

You are implementing <domain> code inside the Yalo AI SDLC pipeline. The following
standards apply on top of any repo-specific conventions in CLAUDE.md.
Where this document and CLAUDE.md conflict, CLAUDE.md takes precedence.

---

[upstream skill body, verbatim from the Capabilities / Core Doctrine section onward]
```
