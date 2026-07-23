---
name: sdlc-generate-data-ui-inventory
description: Generate a Data UI Inventory from a PRD and its Figma designs, cataloging all UI components, payloads, and implementation tasks
disable-model-invocation: true
---

# /sdlc-generate-data-ui-inventory

Generate a Data UI Inventory document in Notion. This artifact catalogs every
UI component, its data payloads, library dependencies, and implementation tasks
for a feature's frontend. It is produced after the Scoping Doc and is consumed
by the Jot Down and task breakdown skills.

## Input

$ARGUMENTS — A Notion URL or page ID pointing to an existing PRD.

## Procedure

1. **Load `.claude/settings.local.json`** from the project root. Read the `sdlc` config key,
   including Notion config (`docs_database`) and the list of allowed repositories.

2. **Verify MCP permissions.** Before doing any work, check both integrations:

   **Notion:** Fetch the configured `home_directory` page using `notion-fetch`.
   If the fetch fails or returns an access error:
   - Tell the user: "The Notion integration does not have access to your
     home directory page. Please re-authorize the Notion MCP connection
     (run `/mcp` to check status) and ensure the integration has edit
     access to the target page."
   - **STOP.** Do not proceed.

   **Figma:** Extract the Figma design link from the PRD's Section 6
   (Prototype / Design Reference) and attempt to fetch the file metadata
   using the Figma MCP. If the fetch fails, returns an auth error, or
   the Figma MCP is not available:
   - Tell the user: "The Figma integration is not connected or does not
     have access to the design file. Please re-authorize the Figma MCP
     connection (run `/mcp` to check status) and ensure the file is
     accessible to the integration."
   - **STOP.** Do not proceed.

   If either check fails, list all failures together so the user can fix
   them in one pass.

3. **Fetch the PRD** from Notion using the MCP. Read it completely. Also look
   for a linked Scoping Document and fetch it if one exists.

4. **Validate that the PRD and Scoping Doc (if present) are complete.** Scan
   both documents for any sections that require human intervention. Check for
   ALL of the following markers:
   - `⚠️ NEEDS HUMAN INPUT` or `NEEDS HUMAN INPUT`
   - Open Questions marked as unresolved (`OQ-x` items without an answer)
   - Sections containing `TBD`, `TODO`, `[placeholder]`, or `[to be defined]`
   - Empty or stub sections (e.g. a heading with no content underneath)
   - PRD Section 6 (Prototype / Design Reference) missing a Figma link

   **Classify each marker as blocking or non-blocking:**

   A marker is **non-blocking** (warn only) when ALL of these are true:
   - It is a `TBD` or `TODO` inside a table cell
   - The same row has a Resolution, Notes, or similar column that explicitly
     acknowledges it (e.g. "Not relevant in this moment", "Deferred to
     scoping", "Will be determined during engineering estimation")
   - The field is inherently a downstream concern — such as Duration,
     Estimate, or Timeline fields whose values are outputs of a later
     process, not inputs to this one

   Everything else is **blocking** — including `NEEDS HUMAN INPUT`, unresolved
   Open Questions, empty sections, and any `TBD` without an accompanying
   resolution. (Missing Figma link is already caught in step 2.)

   **If blocking items exist:**
   - List **every single one** to the user, grouped by document and section,
     including the exact marker text and its location.
   - Tell the user: "The source documents have unresolved items that must be
     completed before a Data UI Inventory can be generated. Please resolve
     them in Notion and re-run this skill."
   - **STOP. Do NOT proceed.** Do not generate a partial inventory.

   **If only non-blocking items exist:**
   - List them in an "Acknowledged TBDs (non-blocking)" section so the user
     is aware.
   - **Proceed** with generation.

5. **Use the Figma MCP to inspect the design file.** The Figma link and
   auth were already verified in step 2. From the design file, pull:
   - Page/frame structure and names
   - Component instances and their variant properties
   - Layout hierarchy (parent-child relationships between frames)
   - Key screen states (default, loading, error, empty, populated)

   **Capture screenshots:** For every node ID listed in the PRD's Section 6
   (Prototype / Design Reference), use the Figma MCP to export or render
   the node as an image. Store the image URLs — they will be embedded in
   Section 3 of the document. If the PRD does not list specific node IDs,
   identify the top-level frames in the Figma file and capture those.

6. **Identify affected frontend repositories** from `.claude/settings.local.json` (or the
   Scoping Doc if available). For each one, read its `.claude/CLAUDE.md` and
   `.claude/ARCHITECTURE.md` (if they exist). If `.claude/CLAUDE.md` does
   not exist, check for a legacy `CLAUDE.md` at the repository root.
   Use these files to understand:
   - UI framework (React, Vue, etc.) and version
   - Component library / design system in use (MUI, YDS, custom, etc.)
   - State management approach
   - Routing patterns
   - Project structure conventions

7. **If a Data UI Inventory template is configured** in `.claude/settings.local.json`
   (`templates.data_ui_inventory`), fetch it from Notion and use its structure
   as the authoritative layout. Otherwise, use the default structure below.

8. **Generate the Data UI Inventory** with the following structure:

   ---

   ### Title: Data UI Inventory — <Feature Name>

   ### References
   Callout block with links to: PRD | Scoping Doc | Figma Design File

   ### Author / Date / Status: Draft

   ---

   ### 1. Overview

   Brief description of the feature's UI scope (2-3 sentences). What screens
   or pages are being built or modified? What is the user-facing outcome?

   ---

   ### 2. Observations

   #### 2.1 UI Libraries
   Which component libraries will be used and why. List each library with its
   purpose (e.g. "MUI — layout primitives", "YDS — branded components").
   Flag any new libraries that need to be added to the project.

   #### 2.2 Project Setup
   Considerations before implementation can begin:
   - Where will the code live? (existing repo, new repo, micro-frontend)
   - Framework compatibility issues (e.g. React version constraints)
   - Base folder/file structure needed
   - Integration points with the main application (routing, navigation,
     feature flags)
   - State management needs (providers, stores, context)

   #### 2.3 Layout Structure
   Describe the overall layout composition: which panels, areas, or zones
   make up the screen. Reference the Figma frame hierarchy. Identify the
   top-level layout components and how they nest.

   ---

   ### 3. Screenshots

   Embed actual Figma screenshots (captured in step 6) for each screen or
   state. Each screenshot subsection must include:
   - The rendered image from Figma (not just a node ID reference)
   - A heading with the screen/state name
   - The Figma node ID in parentheses for traceability

   Use collapsible/toggle sections to keep the document navigable.
   Cover at minimum:
   - Default / initial state
   - Primary flow (main interaction sequence)
   - Loading states
   - Error states
   - Empty states
   - Edge cases (long content, responsive breakpoints if applicable)

   **Do NOT** emit text-only references like "Figma Node: `5557:42457`"
   without the actual image. Every node reference must be accompanied by
   its rendered screenshot.

   ---

   ### 4. Component Inventory

   Create an **inline Notion database** with the following columns:

   | Column | Type | Description |
   |--------|------|-------------|
   | Name | Title | Component name in PascalCase |
   | Parent | Select | The parent component this belongs to |
   | UI Library Components | Multi-select | Library components used (e.g. "Button [YDS]", "Box [MUI]") |
   | Status | Status | Not started / In progress / Done |
   | Assignee | Person | Developer responsible |

   Populate the database with every component identified from the Figma
   design. Components should be organized hierarchically:
   - Top-level layout components first (e.g. MainLayout, PageHeader)
   - Then child components grouped by their parent
   - Leaf components (buttons, inputs, labels) as children of their container

   For each component in the database, name it matching the Figma layer
   name where possible, converted to PascalCase.

   ---

   ### 5. Payloads

   Define the TypeScript data structures that the UI will consume. For each
   major data flow:
   - Interface/type name
   - All fields with types and descriptions
   - Which API endpoint or data source provides this data
   - Note whether this is an existing API response, a new endpoint needed,
     or a BFF aggregation

   Use TypeScript code blocks with comments. Example format:
   ```typescript
   interface FeatureData {
     id: string;
     name: string;
     status: 'active' | 'inactive';
     items: ItemData[];
     metadata?: Record<string, unknown>;
   }
   ```

   If the exact API contract is not yet defined, propose an ideal frontend
   data structure and mark it as `⚠️ NEEDS HUMAN INPUT: API contract TBD`.

   ---

   ### 6. Open Questions

   Group by category:

   #### Design
   Questions about UI behavior, interactions, or visual specs not covered
   in the Figma file.

   #### Implementation
   Questions about technical approach, library choices, or integration
   points that need clarification.

   Each question should tag the relevant owner (Design, Engineering,
   Product) and note whether it is blocking.

   ---

   ### 7. Tasks

   Implementation checklist organized by phase. Each task should be a
   checkbox item prefixed with its category:
   - `UI` — Create/modify a component (pure presentation)
   - `Integration` — Wire a component to data/state/APIs
   - `Setup` — Project scaffolding, configuration, providers

   Example:
   ```
   ## Phase 1 — Foundation
   - [ ] Setup - Initialize project structure and providers
   - [ ] UI - Create MainLayout component
   - [ ] UI - Create PageHeader component

   ## Phase 2 — Core Components
   - [ ] UI - Create DataTable component
   - [ ] Integration - Connect DataTable to API endpoint
   ```

   ---

9. **Create the Notion page.** Title format: `Data UI Inventory: <Feature Name>`.

   **If `docs_database` is configured** (non-empty in `.claude/settings.local.json`):
   Create the page as an entry in the SDLC Documents database with these
   properties:
   - **Doc Type:** `Data UI Inventory`
   - **Feature:** Extracted from the PRD title (e.g. `Budget Export`)
   - **Quarter:** Computed from today's date (e.g. `2026-Q1`)
   - **Related PRD:** URL of the source PRD page

   **If `docs_database` is empty:** Fall back to creating a flat page under
   the configured `home_directory`.

10. **Create the inline Components database** on the page using the Notion
    MCP `create-database` tool with the schema defined in section 4.

11. **Return the Notion page URL** to the user.

---

### Retrospective

12. **Spawn the Skill Retrospective Agent.** After the Notion page is created
    and URL returned, spawn a sub-agent using the instructions in
    `${CLAUDE_PLUGIN_ROOT}/agents/skill-retrospective.md`.

    Pass to the agent:
    - **Skill name**: `sdlc-generate-data-ui-inventory`
    - **What was built**: the Data UI Inventory title and Notion URL
    - **Run summary**: number of components cataloged, Figma extraction quality,
      payload definitions that needed user input, open questions identified,
      any user corrections or pushback during the run
    - **Workspace config**: the repository list from `.claude/settings.local.json`

## Important

- Ground every component in the Figma design. Do not invent components that
  are not in the design. If the design is ambiguous, flag it as an Open
  Question rather than guessing.
- The validation in step 4 ensures source documents are complete before
  generation begins. If validation was somehow bypassed, STOP and re-run
  validation.
- Component names must match the Figma layer names (converted to PascalCase)
  so that designers and engineers share the same vocabulary.
- Payload interfaces must use concrete types, not `any`. If a type cannot be
  determined, use `unknown` and add an Open Question.
- The Component Inventory database is the source of truth for tracking
  implementation progress. Every UI component that needs to be built must
  have a row in this database.
- Tasks in Section 7 are a lightweight planning aid. The authoritative task
  breakdown happens downstream via `/sdlc-generate-task-breakdown`.
- This document must be detailed enough that an engineer can look at a
  component row, find its parent in the layout, see which library components
  to use, and know what data payload it receives — without opening Figma.
