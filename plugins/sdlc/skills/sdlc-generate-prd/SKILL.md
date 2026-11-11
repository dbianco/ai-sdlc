---
name: sdlc-generate-prd
description: Generate a Product Requirements Document from a feature description
disable-model-invocation: true
---

# /sdlc-generate-prd

Generate a Product Requirements Document from a feature description. In
`remote` mode it is created as a Notion page under the workspace's configured
home directory; in `local` mode it is written to `.sdlc/features/`. The PRD
follows the standard 11-section template with numbered IDs for
cross-referencing in engineering workflows.

## Input

$ARGUMENTS — A natural language description of the feature or product need.
Can be a few sentences or a detailed brief.

## Procedure

0. **Resolve the artifact store.** Read `sdlc.mode` from
   `.claude/settings.local.json` (absent means `remote`). Read
   `${CLAUDE_PLUGIN_ROOT}/references/artifact-store.md` and use the
   implementation for that mode for every artifact operation named below.
   Never call Notion or Jira/Linear directly.

1. **Load `.claude/settings.local.json`** from the project root. Read the `sdlc` config key,
   including Notion `home_directory`, `docs_database`, and `templates.prd` values.

2. **Verify Notion permissions — `remote` mode only.** Skip this step entirely
   when `sdlc.mode` is `local`; there is nothing to authorize. In `remote`
   mode, before doing any work, test that the Notion
   MCP can both read and write to the configured `home_directory`. Fetch the
   home directory page using `notion-fetch`. If the fetch fails or returns an
   access error:
   - Tell the user: "The Notion integration does not have access to your
     home directory page. Please re-authorize the Notion MCP connection
     (run `/mcp` to check status) and ensure the integration has edit
     access to the target page."
   - **STOP.** Do not proceed until permissions are confirmed.

3. **If a PRD template is configured and `sdlc.mode` is `remote`**, fetch it
   from Notion using the MCP and
   use its structure as the authoritative layout. Otherwise, use the default
   structure defined in step 5 below.

   In `local` mode there is no configured template — use the structure defined
   in step 5 of this procedure. Do not create a template file.

4. **Ask clarifying questions** before generating. Gather enough information to
   fill every mandatory section. At minimum, ask about:

   **Product & People:**
   - Who is the Product Owner and Engineering Manager?
   - Who is the client? (specific client name, or "Internal" if platform-wide)
   - Target release quarter or date?

   **Problem & Context:**
   - Target users / personas — who experiences this problem and how?
   - What is broken, missing, or insufficient today? (core gaps)
   - What is the business impact of these gaps? (revenue, churn, cost, compliance)

   **Business Case (mandatory):**
   - What is the estimated revenue opportunity? (new ARR, expansion, cost savings)
   - Which specific customers have requested this or would adopt it?
   - Are there prospects where this is a deal blocker? What deal sizes?
   - What new market segments does this unlock?
   - What is the cost of inaction? (at-risk ARR, lost pipeline, operational waste)

   **Scope & Constraints:**
   - Known constraints (timeline, tech, compliance)
   - What is explicitly out of scope or deferred?
   - Related existing features or services
   - Are there Figma prototypes or design references?
   - Does this feature involve user-facing input that needs validation rules?

   **Goals & Metrics:**
   - What does success look like? (measurable targets)
   - Do any goals map to existing OKRs?

   If the user's input already covers some of these, do not re-ask. Only ask
   for what is missing. If the input is too vague to produce a useful PRD, say
   so and request more detail rather than generating filler.

5. **Generate the PRD** with this structure. Every item that gets an ID must
   use the specified prefix and sequential numbering (G-1, G-2, ...; NG-1;
   US-01, US-02, ...; REQ-01; V-01; OQ-1). IDs are mandatory — they enable
   traceability across downstream tasks, scoping docs, and design reviews.

   ---

   ### Metadata Block

   **Product Owner:** [Name]
   **Engineering Manager:** [Name]
   **Client:** [Client name, or "Internal" if platform-wide]
   **Status:** Draft v0.1
   **Date:** [YYYY-MM-DD — use today's date]
   **Version:** 1.0
   **Target Release:** [Quarter / Date]

   > **Context:** [2-3 sentence elevator pitch. A reader should understand the
   > full scope of this PRD from this box alone.]

   ---

   ### 1. Problem Statement

   #### 1.1 Core Gaps
   What is missing, broken, or insufficient in the current system? Reference
   actual product surfaces, services, or workflows.

   #### 1.2 Business Impact
   Consequence of the gaps: lost revenue, operational cost, churn risk,
   compliance exposure, competitive disadvantage. Quantify where possible.

   #### 1.3 Who Experiences This Problem
   List personas affected: end-users, enterprise clients, internal teams.
   Describe how each is impacted.

   #### 1.4 Scope
   High-level phasing summary. What is in this PRD vs. deferred to future
   phases.

   ---

   ### 2. Business Case

   This section is **mandatory** and must contain concrete financial
   justification. Vague statements like "this will drive growth" are not
   acceptable.

   #### 2.1 Revenue Opportunity
   Estimated revenue impact: new ARR, expansion ARR, or cost savings. Explain
   the calculation methodology and time horizon.

   #### 2.2 Customer Pipeline
   Table with columns: Customer | Stage | Estimated Deal Impact | Notes.
   Stage values: Active request / Discovery / Prospect.
   Include both existing customers and prospects.

   #### 2.3 New Market / Segment Unlock
   What new segments or industries become addressable? Name competitive deals
   lost due to this gap if known.

   #### 2.4 Cost of Inaction
   What happens if we do not build this? Quantify: at-risk ARR, lost pipeline
   value, operational person-hours wasted, compliance risk.

   ---

   ### 3. Goals

   Table with columns: # | Goal | Type | Target | OKR Reference.
   - IDs: G-1, G-2, G-3, ...
   - Type values: User / Business / Technical
   - Target must be measurable (number, percentage, threshold)
   - OKR Reference: link to OKR ID or "—" if none

   ---

   ### 4. Non-Goals

   Table with columns: # | Non-Goal | Rationale.
   - IDs: NG-1, NG-2, ...
   - Rationale: why this is out of scope (deferred, better solved differently,
     separate effort)

   ---

   ### 5. User Stories

   For each persona:

   **Persona: [Name]**
   > [Brief description: who they are, daily activities, tools, motivations.]

   Group stories by feature area. Each story must have:
   - ID: US-01, US-02, ... (sequential across all personas)
   - Title
   - Format: As a [persona], I want to [action] so that [benefit].
   - Acceptance Criteria in Given/When/Then format (at least one per story)

   #### User Story Traceability
   Include a traceability table mapping Story ID -> Description -> Requirement(s)
   for complex PRDs. This is optional for simple features (fewer than 5 stories)
   but recommended otherwise.

   ---

   ### 6. Prototype / Design Reference

   Link to Figma file. Include a table of key screens with columns:
   Node ID | Screen name/description.

   If no designs exist yet, write: "Design pending — to be linked before
   engineering scoping begins."

   ---

   ### 7. Validation Rules ⚡

   **This section is conditional.** Include it only when the feature involves
   user-facing input that requires validation (forms, file uploads, API inputs).
   If not applicable, omit this section entirely and note its omission:
   "Section 7 (Validation Rules) omitted — no user-facing input validation
   required."

   When included, use a table with columns: Rule | Category | Description |
   Error Message.
   - IDs: V-01, V-02, ...
   - Category values: Structure / Format / Business
   - Error Message: the exact user-facing message

   ---

   ### 8. Requirements

   Organize by priority tier. Each requirement must have:
   - ID: REQ-01, REQ-02, ... (sequential across all tiers)
   - Title
   - Description
   - Acceptance Criteria as a checkbox list

   #### P0 — Must Have (MVP)
   Requirements that are non-negotiable for launch.

   #### P1 — Should Have
   Requirements important but not blocking MVP.

   #### P2 — Future Consideration
   Requirements for subsequent phases.

   ---

   ### 9. Success Metrics

   #### Leading Indicators
   Measured at 1 week and 1 month post-launch.
   Table with columns: Metric | Target | Measurement.
   Target must be quantified. Measurement must specify the tool or method.

   #### Lagging Indicators
   Measured at 60 and 90 days post-launch.
   Same table format.

   ---

   ### 10. Open Questions

   Table with columns: # | Question | Owner | Blocking?
   - IDs: OQ-1, OQ-2, ...
   - Owner values: Product / Engineering / Client / Design
   - Blocking values: "Yes — needed before [X]" or "No — can default to [Y]
     for v1"

   ---

   ### 11. Timeline Considerations

   #### Hard Deadlines
   Contractual, business, or external deadlines that constrain delivery.

   #### Proposed Phasing
   Table with columns: Phase | Scope | Duration | Dependencies.
   Each phase should be named (e.g., "Phase 1: Core API").

   #### Key Dependencies
   Bulleted list: external dependencies, internal blockers, required decisions
   (reference OQ IDs where applicable).

6. **Write the PRD.** Call `new_feature(<feature name>)` to allocate the
   feature, then `write_doc(feature, prd, <content>)`.

   In `remote` mode `new_feature` creates nothing by itself — it only binds the
   feature name that titles the page `write_doc` then creates. This skill does
   not touch Jira/Linear at all: no project, no issue. Jira/Linear enters the pipeline
   only at `/sdlc-generate-task-breakdown`.

   In `remote` mode this creates the Notion page titled `PRD: <Feature Name>`
   with the properties described below. In `local` mode it writes
   `.sdlc/features/NNN-slug/prd.md` and no properties are needed — the
   directory name carries the feature identity.

   **Remote mode — page properties:**

   **If `docs_database` is configured** (non-empty in `.claude/settings.local.json`):
   Create the page as an entry in the SDLC Documents database with these
   properties:
   - **Doc Type:** `PRD`
   - **Feature:** The feature name extracted from the title (e.g. if title
     is `PRD: Budget Export`, Feature is `Budget Export`)
   - **Quarter:** Computed from today's date (e.g. `2026-Q1` for Jan-Mar,
     `2026-Q2` for Apr-Jun, etc.)

   **If `docs_database` is empty:** Fall back to creating a flat page under
   the configured `home_directory`.

   **In `remote` mode**, when creating the page, use Notion's enhanced
   markdown format to produce:
   - Callout blocks for the usage instructions, context box, and business case
     warning (matching the template's callout styles)
   - Tables with header rows for all structured data (Customer Pipeline, Goals,
     Non-Goals, Traceability, Figma Nodes, Validation Rules, Metrics, Open
     Questions, Phasing)
   - Horizontal rules (---) between major sections
   - Checkbox lists for acceptance criteria in the Requirements section
   - Bold formatting for requirement IDs and user story IDs

7. **Return the artifact reference** to the user — the Notion page URL in
   `remote` mode, or the path returned by `write_doc` in `local` mode.

## ID Numbering Reference

| Section | Prefix | Example | Notes |
|---------|--------|---------|-------|
| Goals | G- | G-1, G-2 | Sequential |
| Non-Goals | NG- | NG-1, NG-2 | Sequential |
| User Stories | US- | US-01, US-02 | Zero-padded, sequential across all personas |
| Validation Rules | V- | V-01, V-02 | Zero-padded, conditional section |
| Requirements | REQ- | REQ-01, REQ-02 | Zero-padded, sequential across all priority tiers |
| Open Questions | OQ- | OQ-1, OQ-2 | Sequential |

## Important

- Write for a technical audience (engineers + PMs).
- Be specific. Avoid filler. Every section should contain actionable information
  or be explicitly marked as "TBD — needs input from [role]".
- If the user's input is too vague to produce a useful PRD, say so and ask for
  more detail rather than generating fluff.
- The Business Case section (Section 2) is **mandatory**. If the user cannot
  provide financial justification, populate it with "TBD — needs input from
  [Product/Sales]" for each subsection, but never omit it.
- Section 7 (Validation Rules) is the only conditional section. Include it only
  when the feature involves user-facing input validation. When omitting it,
  explicitly note the omission so downstream consumers know it was a deliberate
  decision.
- All IDs must be sequential within their section and never reused. These IDs
  are referenced by the scoping doc, jot down, and task breakdown skills.
- Tables are preferred over prose for structured data. Use prose only for
  narrative sections (Problem Statement, Business Case narratives).
- Acceptance criteria in Requirements (Section 8) must be checkbox items so they
  can be tracked as done/not-done.
- Success Metrics must always separate leading indicators (short-term signals)
  from lagging indicators (long-term outcomes).
