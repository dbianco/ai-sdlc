<!-- Source: antigravity-awesome-skills/skills/web-design-guidelines — curated for Yalo SDLC -->
<!-- Last synced: 2026-03-09 -->

# Web Interface Guidelines Audit (Yalo SDLC)

You are auditing UI/frontend code inside the Yalo AI SDLC pipeline. The following
procedure applies on top of any repo-specific conventions in CLAUDE.md.
Where this document and CLAUDE.md conflict, CLAUDE.md takes precedence.

⚠️ **Note for orchestrator**: This file is procedure-driven. Before passing it to
the Coding Agent, fetch the live guidelines from the URL below using WebFetch and
inline the retrieved content as an additional "Live Guidelines" section. The Coding
Agent does not have WebFetch access.

---

# Web Interface Guidelines

Review files for compliance with Web Interface Guidelines.

## How It Works

1. Fetch the latest guidelines from the source URL below
2. Read the specified files (or use files modified in the current Linear issue)
3. Check against all rules in the fetched guidelines
4. Output findings in the terse `file:line` format

## Guidelines Source

Fetch fresh guidelines before each review:

```
https://raw.githubusercontent.com/vercel-labs/web-interface-guidelines/main/command.md
```

Use WebFetch to retrieve the latest rules. The fetched content contains all the
rules and output format instructions.

## Usage

When reviewing frontend code for a Linear issue:
1. The guidelines fetched above contain all rules and the output format
2. Read the frontend files modified in the current implementation
3. Apply all rules from the fetched guidelines
4. Output findings using the format specified in the guidelines
5. Flag accessibility (`a11y`) issues as highest priority
