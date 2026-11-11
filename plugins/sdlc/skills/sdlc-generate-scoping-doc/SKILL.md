---
name: sdlc-generate-scoping-doc
description: Generate a Scoping Document from a PRD
disable-model-invocation: true
---

# /sdlc-generate-scoping-doc

Generate a Scoping Document from a PRD. The Scoping Doc is the engineering
team's response to "how will we build this?"

## Input

$ARGUMENTS — In `remote` mode, a Notion URL or page ID pointing to an existing
PRD. In `local` mode, a feature reference — `001`, `order-export`, or
`001-order-export`.

## Procedure

0. **Resolve the artifact store.** Read `sdlc.mode` from
   `.claude/settings.local.json` (absent means `remote`). Read
   `${CLAUDE_PLUGIN_ROOT}/references/artifact-store.md` and use the
   implementation for that mode for every artifact operation named below.
   Never call Notion or Jira/Linear directly.

1. **Load `.claude/settings.local.json`** from the project root. Read the `sdlc` config key,
   including Notion config (`docs_database`) and the list of allowed repositories.

2. **Verify Notion permissions — `remote` mode only.** Skip this step entirely
   when `sdlc.mode` is `local`. In `remote` mode, before doing any work, test
   that the Notion
   MCP can both read and write to the configured `home_directory`. Fetch the
   home directory page using `notion-fetch`. If the fetch fails or returns an
   access error:
   - Tell the user: "The Notion integration does not have access to your
     home directory page. Please re-authorize the Notion MCP connection
     (run `/mcp` to check status) and ensure the integration has edit
     access to the target page."
   - **STOP.** Do not proceed until permissions are confirmed.

3. **Read the PRD.** Call `resolve_feature($ARGUMENTS)`, then
   `read_doc(feature, prd)`. Read it completely.

   **If the PRD is absent**, check whether a non-canonical planning document
   exists in the feature's artifact store:
   - In `local` mode: any other `.md` file inside the feature directory
     (e.g. `plan-*.md`, `design-*.md`, `rfc-*.md`, or a file whose path was
     passed in `$ARGUMENTS`).
   - In `remote` mode: another page under the same home directory with a
     title that looks like a plan or design (`Plan:`, `Design:`, `RFC:`
     prefixes), or a page the user explicitly passed as `$ARGUMENTS`.

   **If no such document exists**, say so and stop — a Scoping Doc cannot
   be written without any input design. Do not offer to invent one.

   **If a plan/design document exists**, ask the user via `AskUserQuestion`:

   > "No `prd.md` was found, but `<path>` looks like a planning document.
   > The skill needs a PRD to work from. How should I proceed?"
   >
   > - **Restructure into `prd.md`** — Read `<path>` and write a canonical
   >   `prd.md` from it. Requirements are derived only from items the plan
   >   already specifies; no KPIs are invented. Then continue in the same
   >   run.
   > - **Stop** — Stop here so you can author the PRD manually.

   **If the user chooses "Restructure":**
   - Read the plan/design document completely.
   - Draft a `prd.md` using the standard PRD section structure.
   - Derive REQ-xx IDs only from design items the plan already specifies.
     Do **not** invent requirements that are not grounded in the source.
   - For any PRD section without a corresponding statement in the source,
     mark it `⚠️ NEEDS HUMAN INPUT` and record what is missing.
   - For the Business Case / KPI section, write exactly:
     `No KPI defined in the source plan — gather in a follow-up.`
     Do not fabricate metrics.
   - Gather every open item in the source plan (unresolved `OQ-x`, `TBD`,
     `[placeholder]`, bulleted "to decide" lists) and surface them in a
     single batched `AskUserQuestion` call (up to 4 questions per batch;
     repeat until exhausted). Fold answers into the draft inline.
   - Write the draft via `write_doc(feature, prd, <content>)`.
   - Record in the run summary that the PRD was reconstructed from
     `<path>` so `skill-retrospective` can carry it into CLAUDE.md.
   - Continue with step 4 (validation) using the newly written PRD. The
     validation step will catch any `⚠️ NEEDS HUMAN INPUT` markers that
     remain blocking.

   **If the user chooses "Stop":** stop. Do not continue.

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
   - Then ask with `AskUserQuestion` how to proceed. Default: resolve inline.

     - **Resolve inline** (default, recommended) — enter the per-blocker
       loop below. Most blockers are closable by a decision or a
       reclassification, and running a fresh session to resolve them costs
       a context handoff. This is the path recorded as a workspace lesson
       on prior runs.
     - **Stop and resolve externally** — fall through to the "STOP" path.
       Use this when the blockers need research the user cannot do right
       now (e.g. external stakeholder input).

   **If the user chose "Stop and resolve externally":**
   - Tell the user: "The PRD has unresolved items that must be completed
     before a Scoping Document can be generated. Please resolve them and
     re-run this skill." In `remote` mode, direct them to the PRD page
     fetched in step 3. In `local` mode, direct them to the PRD file —
     `doc_link(feature, prd)` (typically `<feature-dir>/prd.md`).
   - **STOP. Do NOT proceed.** Do not generate a partial scoping doc.

   **If the user chose "Resolve inline" — the blocker loop:**

   Work through the blockers in batches of up to 4 via a single
   `AskUserQuestion` call per batch. For each blocker, offer three options:

   - **Resolve** — the user provides the answer inline. The skill folds it
     into the PRD as a dated note (see "PRD write-back" below). The blocker
     is cleared.
   - **Reclassify as non-blocking** — the user explains why (free-text
     follow-up). The blocker is kept but moves to the "Acknowledged TBDs
     (non-blocking)" list, with the user's justification recorded.
   - **Record as pending** — the blocker is real but cannot be closed now
     (depends on code not yet read, external stakeholder, …). The item
     moves to the scoping doc as `⚠️ PENDING DECISION: <description>` with
     the user's one-line rationale. It stays blocking for the PRD gate
     only if the user says so — otherwise it clears.

   **Before any PRD write, verify the blocker is not stale.** If the
   blocker references another feature, module, or deliverable ("deferred
   to feature 033", "handled by the rollout service"), check it against
   `origin/main` using the evidence rules in step 6. A blocker that the
   tree has already answered is corrected in the PRD with a dated note
   first — then the user answers against the corrected text, not the stale
   one.

   **PRD write-back.** After every batch, update the PRD content in memory:

   - **Resolve:** append a dated note to the item, in this form:

     ```
     <original text>

     > [<today YYYY-MM-DD>: resolved at scoping] <user answer>
     ```

   - **Reclassify:** append `> [<today>: reclassified non-blocking at
     scoping] <user justification>`.

   - **Record as pending:** leave the PRD text as-is and only record the
     item in the scoping doc. Do not write a pending note into the PRD —
     the item is still open.

   **After the loop, write the modified PRD back to the artifact store.**
   Ask the user once with `AskUserQuestion` to confirm the overwrite, show
   the number of edits and the dated lines, and then call
   `write_doc(feature, prd, <new content>)` with the merged text. Keep every
   non-blocker line byte-identical. If the user declines the overwrite,
   keep the resolutions in memory for the scoping doc only — the PRD is
   left untouched, and the "Corrections to the PRD found at scoping"
   section (see step 11, Section 1b) records what would have been written.

   **After the loop, re-run the classification above.** Blockers that were
   resolved or cleared as pending are gone. If any blocker remains (user
   said a pending item must still block, or the user declined to resolve
   some), fall through to the "STOP" path above with the remaining list.

   **If only non-blocking items exist:**
   - List them in an "Acknowledged TBDs (non-blocking)" section so the user
     is aware.
   - **Proceed** with generation.

5. **Identify which repositories** from `.claude/settings.local.json` are relevant to this
   feature. If unclear, ask the user.

6. **Research each relevant repository against `origin/main`, not the
   working tree.** The checkouts may sit on old task branches, and the
   service `CLAUDE.md` / `ARCHITECTURE.md` files are frequently out of sync
   with the code they describe. A PRD that passed three architectural
   reviews can still carry claims the tree contradicts. Protect the scoping
   doc from both.

   **For every relevant repository**:

   a. Spawn **one research sub-agent per repository** (or per repo group,
      when repos share one service tree). In workspaces with 3+
      repositories, run these agents in parallel via a single multi-call
      dispatch — the queries do not depend on each other.

   b. Each research agent **must read from `origin/main`, never the working
      tree**, using commands like:

      - `git -C <repo> show origin/main:<path>` to read a specific file at
        `origin/main`.
      - `git -C <repo> grep -n <pattern> origin/main -- <paths>` to search.
      - `git -C <repo> ls-tree -r --name-only origin/main <path>` to list.

      Do **not** read the working tree (`cat <repo>/<path>`,
      `rg <pattern> <repo>`) for any claim that will land in the scoping
      doc. Working-tree reads are only acceptable for `.claude/CLAUDE.md`
      and `.claude/ARCHITECTURE.md`, which are high-level context — their
      claims must still be verified against `origin/main` before they
      reach the scoping doc.

   c. For every claim the agent plans to carry into the scoping doc, it
      must record the exact git command it ran and the verbatim output
      (or the lines that matter from it). "File `src/x.ts` contains
      function `foo`" is not a claim — "Running
      `git -C service-a show origin/main:src/x.ts | grep -n 'function foo'`
      returned `42:export function foo(...)`" is.

   d. The agent returns a list of findings: each finding carries the
      claim, the command, the verbatim output, and — when the claim
      contradicts the PRD — a correction suggestion.

   **Fold the corrections into the PRD.** For every finding where the
   verbatim output contradicts the PRD (a contract the PRD said was not
   vendored but is; a retention decision that assumes rows are deleted
   when nothing deletes them; a counter the PRD placed in the wrong class;
   a status value no code writes; a column the PRD said was absent on most
   rows but is written on every row), surface it to the user via
   `AskUserQuestion` using the same loop shape as step 4: **Correct the
   PRD** (write a dated note), **Keep the PRD** (record the discrepancy as
   a risk in the scoping doc instead), or **Investigate further** (log and
   defer). Writing back to the PRD uses the same `write_doc` call as the
   step-4 loop; collect corrections from both loops and write once.

   Every correction accepted also appears in the scoping doc's "Corrections
   to the PRD found at scoping" table (Section 1b in the template below).

   If `.claude/CLAUDE.md` does not exist in a repository, check for a
   legacy `CLAUDE.md` at the repository root. Flag missing or legacy
   locations to the user and suggest they type
   `/sdlc:sdlc-init-claude-context <repo>` after this run to regenerate
   context.

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
   drives the downstream Jot Down generation. How it lands depends on the
   mode: in `remote` mode each milestone becomes its own Jot Down page; in
   `local` mode one feature directory holds one `jotdown.md`, so the selected
   milestones are consolidated into that single document, each under its own
   heading.

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

9. **Collect feature flag details.** After architectural decisions are
   resolved, read `sdlc.feature_flags` from `.claude/settings.local.json` and
   branch on its value. If the key is missing or empty, ask the user with
   `AskUserQuestion` which of `Split.io`, `Environment variables or settings
   tables`, or `None` applies to this workspace, use the answer for this run,
   and remind them they can persist it by running `/sdlc:sdlc-workspace-init`.

   **If `feature_flags` is `split`** (Split.io or an equivalent SaaS
   platform), ask with `AskUserQuestion`:

   > "This feature should be gated behind a feature flag. Please create the
   > split now and provide:
   >
   > 1. **Split name** (e.g. `enable_budget_export`)
   > 2. **Traffic type** — the entity that controls rollout:
   >    `account`, `user`, `workflow`, or other (describe it)
   >
   > Treatments are always `on` / `off` (default: `off`).
   >
   > If this feature does NOT need a feature flag, reply 'none'."

   Downstream skills will assume the split already exists in the SaaS
   platform and coding agents will use the SDK to evaluate it.

   **If `feature_flags` is `env`** (environment variables, settings tables,
   or per-tenant kill switches), ask with `AskUserQuestion`:

   > "This feature should be gated behind an in-repo flag. Please provide:
   >
   > 1. **Flag name** (e.g. `BUDGET_EXPORT_ENABLED`)
   > 2. **Scope** — where the flag is read: `env var`, `settings table`,
   >    `config file`, or `other` (describe it)
   > 3. **Default value** — the safe/current behavior when unset or
   >    unreachable (e.g. `false`, `legacy`, `off`)
   >
   > If this feature does NOT need a flag, reply 'none'."

   Downstream skills will assume the operator sets the flag before enabling
   the feature, and the code must fall back to the default value when the
   flag is unset or unreachable.

   **If `feature_flags` is `none`**: skip this step entirely and omit
   Section 8 from the output. Do not ask the user about flags.

   If the user replies "none" to either of the above prompts, also omit
   Section 8.

10. **If a scoping doc template is configured and `sdlc.mode` is `remote`**,
    fetch and
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

   ### 1b. Corrections to the PRD found at scoping
   Include this section only when step 4's blocker loop or step 6's research
   agents surfaced discrepancies the user accepted as corrections. Omit it
   entirely if the PRD was byte-identical to what the tree says.

   Table: Area | PRD claim (before) | Evidence against `origin/main` | Correction applied
   | Writeback status

   For every row:
   - **Area**: which PRD section the claim came from (e.g. "Section 4,
     Retention policy").
   - **PRD claim (before)**: the PRD text as it was at the start of this
     run, verbatim and short (quote the one sentence the correction
     touched).
   - **Evidence against `origin/main`**: the git command and the verbatim
     line(s) of its output that justify the correction. One command per
     claim, shown as a fenced block.
   - **Correction applied**: the dated note the PRD now carries, or the
     user's wording if they chose "Keep the PRD".
   - **Writeback status**: `written back to prd.md` (or the Notion page URL)
     when the user accepted the overwrite; `not written — kept here only`
     when the user declined. Never "pending" — the user answered one way
     or the other in step 4.

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

   ### 8. Feature Flag
   Include this section only if the user provided flag details in step 9.
   Pick the subsection that matches `sdlc.feature_flags` and drop the other.

   **If `feature_flags` is `split`:**

   | Field | Value |
   |-------|-------|
   | Platform | Split.io (or equivalent SaaS) |
   | Split Name | `<split_name>` |
   | Traffic Type | `<traffic_type>` |
   | Treatments | `on` / `off` (default: `off`) |

   Downstream skills (Jot Down, Task Breakdown, Implement Task) will
   reference this split by name. The coding agent will assume the split
   already exists in the SaaS platform and will use the SDK to evaluate it.

   **If `feature_flags` is `env`:**

   | Field | Value |
   |-------|-------|
   | Platform | In-repo (`env var` / `settings table` / `config file`) |
   | Flag Name | `<flag_name>` |
   | Scope | `<scope>` |
   | Default Value | `<default>` (fallback when unset or unreachable) |

   Downstream skills will reference this flag by name. The coding agent
   will read it at the scope you specified and fall back to the default
   value when the flag is unset or unreachable.

12. **Write the Scoping Doc.** Call `write_doc(feature, scoping-doc, <content>)`.

    In `remote` mode this creates the Notion page titled
    `Scoping: <Feature Name>` with the properties described below. In `local`
    mode it writes `.sdlc/features/NNN-slug/scoping-doc.md`.

    Reference the PRD using `doc_link(feature, prd)` so the link resolves in
    both modes.

    **Remote mode — page properties:**

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

13. **Return the artifact reference** to the user — the Notion page URL in
    `remote` mode, or the path returned by `write_doc` in `local` mode.

---

### Retrospective

14. **Spawn the Skill Retrospective Agent.** After the Scoping Doc is written
    and its artifact reference returned — the Notion page in `remote` mode, or
    the file in `local` mode — spawn a sub-agent using the instructions in
    `${CLAUDE_PLUGIN_ROOT}/agents/skill-retrospective.md`.

    Pass to the agent:
    - **Skill name**: `sdlc-generate-scoping-doc`
    - **What was built**: the scoping doc title and its artifact reference —
      the Notion URL in `remote` mode, or the file path in `local` mode
    - **Run summary**: key decisions made (milestones chosen, architectural
      decisions resolved or left pending, feature flag details), any user
      corrections or pushback during the run, sections that required iteration
    - **Workspace config**: the repository list from `.claude/settings.local.json`
    - **Today's date**: in `YYYY-MM-DD` form, so the agent stamps lessons with
      a stable value instead of guessing

    The agent only proposes. It returns a ```retrospective``` fenced JSON
    block — it never asks the user and never writes any file.

15. **Ask the user and save the lessons.** Read
    `${CLAUDE_PLUGIN_ROOT}/references/retrospective-save.md` and follow it
    exactly on the agent's proposal.

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