---
name: sdlc-generate-scoping-doc
description: Generate a Scoping Document from a PRD
disable-model-invocation: true
---

# /sdlc-generate-scoping-doc

Generate a Scoping Document from a PRD. The Scoping Doc is the engineering
team's response to "how will we build this?"

## Input

$ARGUMENTS — A Notion URL or page ID pointing to an existing PRD.

## Procedure

1. **Load `.claude/settings.local.json`** from the project root. Read the `sdlc` config key,
   including Notion config (`docs_database`) and the list of allowed repositories.

2. **Verify Notion permissions.** Before doing any work, test that the Notion
   MCP can both read and write to the configured `home_directory`. Fetch the
   home directory page using `notion-fetch`. If the fetch fails or returns an
   access error:
   - Tell the user: "The Notion integration does not have access to your
     home directory page. Please re-authorize the Notion MCP connection
     (run `/mcp` to check status) and ensure the integration has edit
     access to the target page."
   - **STOP.** Do not proceed until permissions are confirmed.

3. **Fetch the PRD** from Notion using the MCP. Read it completely.

4. **Validate the PRD is complete.** Scan the entire document for any sections
   that require human intervention. Check for ALL of the following markers:
   - `⚠️ NEEDS HUMAN INPUT` or `NEEDS HUMAN INPUT`
   - Open Questions marked as unresolved (`OQ-x` items without an answer)
   - Sections containing `TBD`, `TODO`, `[placeholder]`, or `[to be defined]`
   - Empty or stub sections (e.g. a heading with no content underneath)
   - Business Case section (Section 2) missing numbers or KPIs

   **Classify each marker as blocking or non-blocking:**

   A marker is **non-blocking** (warn only) when ALL of these are true:
   - It is a `TBD` or `TODO` inside a table cell
   - The same row has a Resolution, Notes, or similar column that explicitly
     acknowledges it (e.g. "Not relevant in this moment", "Deferred to
     scoping", "Will be determined during engineering estimation")
   - The field is inherently a downstream concern — such as Duration,
     Estimate, or Timeline fields whose values are outputs of the scoping
     process, not inputs to it

   Everything else is **blocking** — including `NEEDS HUMAN INPUT`, unresolved
   Open Questions, empty sections, and any `TBD` without an accompanying
   resolution.

   **If blocking items exist:**
   - List **every single one** to the user, grouped by section, including the
     exact marker text and its location in the document.
   - Tell the user: "The PRD has unresolved items that must be completed before
     a Scoping Document can be generated. Please resolve them in Notion and
     re-run this skill."
   - **STOP. Do NOT proceed.** Do not generate a partial scoping doc.

   **If only non-blocking items exist:**
   - List them in an "Acknowledged TBDs (non-blocking)" section so the user
     is aware.
   - **Proceed** with generation.

5. **Identify which repositories** from `.claude/settings.local.json` are relevant to this
   feature. If unclear, ask the user.

6. **For each relevant repository**, read its `.claude/CLAUDE.md` and
   `.claude/ARCHITECTURE.md` (if they exist) to understand architecture,
   components, data flow, patterns, and constraints. If `.claude/CLAUDE.md`
   does not exist, check for a legacy `CLAUDE.md` at the repository root.

7. **Define milestones with the user.** Milestones are the delivery units of
   the scoping doc. Each milestone must represent a **fully functional product
   increment** — something a user can interact with end-to-end, not a
   technical layer (e.g. "Create new user" is a good milestone; "Set up
   database schema" is not).

   **If the PRD already contains milestones** (look for Section 11's Proposed
   Phasing table or a similar phasing section):
   - Extract them and present them to the user via `AskUserQuestion`.
   - Ask: "The PRD proposes these milestones. Do you want to keep them,
     modify them, or define new ones?"
   - Options:
     - **Keep as-is** — use the PRD milestones directly.
     - **Modify** — the user provides adjustments (merge, split, reorder).
       Follow up with another question to capture the changes.
     - **Define new** — ignore the PRD milestones and let the user define
       their own (see below).

   **If the PRD has no milestones**, or the user chose "Define new":
   - Propose a milestone breakdown based on your understanding of the PRD
     requirements and the codebase. Each proposed milestone should:
     - Have a clear name describing the user-facing outcome
       (e.g. "Budget CSV Export", "Activity Log Timeline")
     - List which REQ-xx items it covers
     - Be independently deployable
   - Present the proposed milestones to the user and ask them to confirm,
     adjust, or add more.

   The final milestone list is used in Section 3.1 of the scoping doc and
   drives the downstream Jot Down generation (one Jot Down per milestone).

8. **Surface architectural decisions.** Before generating, identify any
   design choices where multiple valid approaches exist. Common examples:

   - Synchronous (HTTP) vs asynchronous (message queue / events) processing
   - New model/table within an existing service vs new microservice
   - Existing database vs new dedicated database
   - REST vs gRPC vs GraphQL for a new API surface
   - Streaming vs batch for data processing
   - Monorepo module vs separate repository
   - Server-side rendering vs client-side for a new page/flow

   For each decision found, present it to the user using `AskUserQuestion`
   with concrete options. Explain the trade-offs briefly (1-2 sentences per
   option). Include relevant context from the codebase (e.g. "the existing
   service already uses RabbitMQ for X").

   The user can:
   - **Pick an option** — the scoping doc will use that decision.
   - **Choose "Pending"** — the decision is recorded in the scoping doc as
     `⚠️ PENDING DECISION: <description>` so it can be resolved later.

   Batch related decisions into a single question set when possible (up to
   4 questions per `AskUserQuestion` call). Do NOT silently pick an approach
   — always ask.

9. **Collect feature flag details.** After architectural decisions are resolved,
   ask the user using `AskUserQuestion`:

   > "This feature should be gated behind a feature flag in Split.io.
   > Please create the split now and provide:
   >
   > 1. **Split name** (e.g. `enable_budget_export`)
   > 2. **Traffic type** — the entity that controls rollout:
   >    `account`, `user`, `workflow`, or other (describe it)
   >
   > Treatments are always `on` / `off` (default: `off`).
   >
   > If this feature does NOT need a feature flag, reply 'none'."

   Record the user's answers. These will be written into the Scoping Doc
   (Section 8) and flow downstream into the Jot Down and Linear issues so
   that coding agents can assume the split already exists in Split.io.

   If the user replies "none", omit Section 8 from the output.

10. **If a scoping doc template is configured** in `.claude/settings.local.json`, fetch and
   follow its structure. Otherwise, use the default structure below.

11. **Generate the Scoping Document:**

   ### Title: Scoping — <Feature Name>
   ### PRD Reference: [link to PRD]
   ### Author / Date / Status: Draft

   ### 1. Context
   Brief summary of the problem and business case from the PRD. Reference the
   PRD's Problem Statement (Section 1) and Business Case (Section 2). Link
   back to the PRD. Include the PRD's Goal IDs (G-x) that this scoping doc
   addresses.

   ### 2. Problem
   Technical restatement of the problem. What needs to change in our systems?

   ### 3. Solution
   High-level approach. Which services are affected and how.

   #### 3.1 Milestones
   Use the milestone list confirmed by the user in step 7. For each milestone:

   Table: # | Milestone | Description | REQ Coverage | Dependencies

   Each milestone must be a **fully functional product increment** — something
   a user can interact with end-to-end. Examples of good milestones:
   - "Budget CSV Export" — user can download a full budget snapshot
   - "Activity Log Timeline" — user can view and filter budget events
   - "Bulk Import with Validation" — user can upload and process a CSV

   Examples of bad milestones (too technical, not user-facing):
   - "Set up database schema"
   - "Create API endpoints"
   - "Add frontend components"

   ### 4. Scope
   #### In Scope (for this iteration)
   #### Out of Scope (deferred / separate effort)

   ### 5. Risks & Mitigations
   Technical risks, dependencies, unknowns. Each risk must have a mitigation.

   ### 6. Architectural Decisions
   Table: Decision | Options Considered | Chosen Approach | Rationale

   Include every decision surfaced in step 8. For pending decisions, set
   Chosen Approach to `⚠️ PENDING DECISION` and Rationale to the context
   that will help the team resolve it later.

   ### 7. Affected Services
   Table: Service | Changes Required | Estimated Complexity (S/M/L)

   ### 8. Feature Flag (Split.io)
   Include this section only if the user provided flag details in step 9.

   | Field | Value |
   |-------|-------|
   | Split Name | `<split_name>` |
   | Traffic Type | `<traffic_type>` |
   | Treatments | `on` / `off` (default: `off`) |

   Downstream skills (Jot Down, Task Breakdown, Implement Task) will
   reference this split by name. The coding agent will assume the split
   already exists in Split.io and will use the Split SDK to evaluate it.

12. **Create the Notion page.** Title format: `Scoping: <Feature Name>`.

    **If `docs_database` is configured** (non-empty in `.claude/settings.local.json`):
    Create the page as an entry in the SDLC Documents database with these
    properties:
    - **Doc Type:** `Scoping Doc`
    - **Feature:** Extracted from the PRD title (e.g. if PRD is
      `PRD: Budget Export`, Feature is `Budget Export`)
    - **Quarter:** Computed from today's date (e.g. `2026-Q1`)
    - **Related PRD:** URL of the source PRD page

    **If `docs_database` is empty:** Fall back to creating a flat page under
    the configured `home_directory`.

13. **Return the Notion page URL** to the user.

---

### Retrospective

14. **Spawn the Skill Retrospective Agent.** After the Notion page is created
    and URL returned, spawn a sub-agent using the instructions in
    `${CLAUDE_PLUGIN_ROOT}/agents/skill-retrospective.md`.

    Pass to the agent:
    - **Skill name**: `sdlc-generate-scoping-doc`
    - **What was built**: the scoping doc title and Notion URL
    - **Run summary**: key decisions made (milestones chosen, architectural
      decisions resolved or left pending, feature flag details), any user
      corrections or pushback during the run, sections that required iteration
    - **Workspace config**: the repository list from `.claude/settings.local.json`

## Important

- Ground the scoping doc in the actual codebase. Reference specific services,
  modules, and patterns from the repo CLAUDE.md and ARCHITECTURE.md files.
- The validation in step 4 ensures the PRD is complete before generation begins.
  If validation was somehow bypassed, STOP and re-run validation. Do not fill
  in assumptions silently.
- Milestones must be fully functional product increments that a user can
  interact with end-to-end. "Build the thing" or "Set up database" are not
  milestones. "Budget CSV Export" or "Activity Log Timeline" are.
- When referencing PRD requirements in the scoping doc, use the PRD's REQ-xx
  IDs to maintain traceability. The Affected Services table should note which
  REQ-xx items each service change addresses.