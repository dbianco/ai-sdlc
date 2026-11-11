---
name: sdlc-generate-jotdown
description: Generate a Jot Down Implementation Spec from any source — Scoping Doc, Jira/Linear issue, Slack thread, Notion page, or direct input
disable-model-invocation: true
---

# /sdlc-generate-jotdown

Generate a Jot Down Implementation Spec from any source. The Jot Down is the
detailed technical blueprint that coding agents will use.

## Input

$ARGUMENTS — (optional) The primary source. In `remote` mode: a Scoping Doc
Notion URL, a Jira/Linear issue (URL or `XXX-NNN`), a Slack thread URL, a Notion page
URL, or free text. In `local` mode: a feature reference (`001`, `order-export`,
`001-order-export`), or free text — free text allocates a new feature directory
to hold the Jot Down, so local mode never requires a PRD or Scoping Doc to have
been generated first. If omitted, the skill will ask.

## Procedure

### Setup

0. **Resolve the artifact store.** Read `sdlc.mode` from
   `.claude/settings.local.json` (absent means `remote`). Read
   `${CLAUDE_PLUGIN_ROOT}/references/artifact-store.md` and use the
   implementation for that mode for every artifact operation named below.
   Never call Notion or Jira/Linear directly.

1. **Load `.claude/settings.local.json`** from the project root. Read the `sdlc`
   config key, including Notion config, `docs_database`, and `templates.jotdown`.

2. **Verify Notion permissions — `remote` mode only.** Skip this step entirely
   when `sdlc.mode` is `local`. In `remote` mode, test that the Notion MCP can
   both read and
   write to the configured `home_directory`. Fetch the home directory page
   using `notion-fetch`. If the fetch fails or returns an access error:
   - Tell the user: "The Notion integration does not have access to your
     home directory page. Please re-authorize the Notion MCP connection
     (run `/mcp` to check status) and ensure the integration has edit
     access to the target page."
   - **STOP.** Do not proceed until permissions are confirmed.

---

### Phase 1: Understand What Data Is Needed

3. **Fetch the Jot Down template.** If `templates.jotdown` is configured and
   `sdlc.mode` is `remote`, fetch it from Notion via `notion-fetch`.
   Read the template to understand what sections and data fields are required
   for the Jot Down output. The template defines the structure the generated
   document must follow.

   If no template is configured, use the default structure defined in Phase 3
   (step 12) of this procedure.

   From the template (or default structure), build a list of **required data
   fields** — the information that must be gathered before generation can begin.

---

### Phase 2: Gather Context

4. **Get initial context from the source.** If `$ARGUMENTS` is provided,
   detect the source type and fetch it:

   | Pattern | Source type | How to fetch |
   |---------|------------|-------------|
   | URL containing `notion.so` or `notion.site` | Notion page | `notion-fetch` |
   | URL containing `linear.app` or pattern `XXX-NNN` | Jira/Linear issue | `get_issue` |
   | URL containing `slack.com` | Slack thread | `slack_read_thread` |
   | A feature ref in `local` mode (`001`, `order-export`, `001-order-export`) | Local feature | `resolve_feature`, then `read_doc` for each kind present |
   | Other non-empty text | Free text | Use directly |
   | Empty / not provided | No source | Ask the user for a description of what needs to be built or fixed |

   Extract whatever context is available from the source material.

   **Bind `feature` before generation begins — `local` mode.** Every path
   through the table above must end with a bound `feature`, because step 13
   writes into it:

   - A feature ref binds it via `resolve_feature`.
   - Free text, or no source at all, binds it via `new_feature(<feature name>)`.
     Allocate it once the feature name is settled — after step 7, where the
     remaining gaps are filled — and tell the user which directory was
     allocated (e.g. "Writing to `.sdlc/features/003-order-export/`"). Any
     documents that later land in that directory belong to the same feature.

   In `remote` mode nothing is allocated here: `write_doc` creates the page in
   step 13.

5. **Check whether the source carries a Scoping Doc and a PRD.**

   In `remote` mode: if the source is a Notion page, look for Scoping Doc
   structural markers (milestones section, architectural decisions, affected
   services, linked PRD reference); if found, fetch the linked PRD as well.

   In `local` mode: call `read_doc(feature, scoping-doc)` and
   `read_doc(feature, prd)`. Treat whichever exist as the source documents.
   Make these two calls only when step 4 resolved an existing feature ref — a
   feature allocated from free text is not created until after step 7 and has
   no documents to read, so skip this step entirely on that path.

   If both documents are present in either mode:

   - **Validate both documents for blocking markers.** Scan both documents for:
     - `⚠️ NEEDS HUMAN INPUT` or `NEEDS HUMAN INPUT`
     - Open Questions marked as unresolved (`OQ-x` items without an answer)
     - Sections containing `TBD`, `TODO`, `[placeholder]`, or `[to be defined]`
     - Empty or stub sections (a heading with no content underneath)
     - Unresolved risks without mitigations in the Scoping Doc
     - PRD requirements (`REQ-xx`) referenced in the Scoping Doc that are
       incomplete or missing from the PRD

     **Classify each marker as blocking or non-blocking:**

     A marker is **non-blocking** (warn only) when ALL of these are true:
     - It is a `TBD` or `TODO` inside a table cell
     - The same row has a Resolution, Notes, or similar column that explicitly
       acknowledges it (e.g. "Not relevant in this moment", "Deferred to
       scoping", "Will be determined during engineering estimation")
     - The field is inherently a downstream concern — such as Duration,
       Estimate, or Timeline fields whose values are outputs of a later
       process, not inputs to this one

     Everything else is **blocking**.

     **If blocking items exist:**
     - List every one to the user, grouped by document and section.
     - Tell the user: "The source documents have unresolved items that must be
       completed before a Jot Down can be generated. Please resolve them and
       re-run this skill." Name the file path in `local` mode, or the Notion
       page in `remote` mode.
     - **STOP. Do NOT proceed.**

     **If only non-blocking items exist:**
     - List them so the user is aware.
     - **Proceed.**

   - Extract all available context from both documents.

6. **Always gather the following**, regardless of source. If already present
   in the source material, confirm with the user. If not, ask via
   `AskUserQuestion`. Batch related questions (up to 4 per call).

   a. **Affected repositories** — present the list from `settings.local.json`
      for selection (`multiSelect: true`). Always ask, even if inferred.

   b. **Feature flag** — read `sdlc.feature_flags` from
      `.claude/settings.local.json` first. If the key is missing or empty,
      ask the user which of `Split.io`, `Environment variables or settings
      tables`, or `None` applies — use the answer for this run and remind
      them they can persist it via `/sdlc:sdlc-workspace-init`.

      - If the setting is `none`: skip this step. No Section 8 in the output.
      - If the setting is `split`: ask "Does this work need a feature flag?"
        If yes, collect split name, traffic type, and treatments (default
        `off`).
      - If the setting is `env`: ask "Does this work need a feature flag?"
        If yes, collect flag name, scope (`env var` / `settings table` /
        `config file` / `other`), and default value.

      If a Scoping Doc is in scope, its Section 8 may already carry these
      values — pull from there rather than re-asking.

   c. **Data UI Inventory** — if the source context suggests frontend work
      (mentions UI, components, screens, pages, frontend, React, etc.), ask:
      "Is there a Data UI Inventory for this work?" If yes: in `remote` mode,
      collect the Notion URL and fetch it via `notion-fetch`; in `local` mode,
      call `read_doc(feature, data-ui-inventory)` if step 4 resolved an
      existing feature ref; otherwise ask for the file path and read it
      directly — a feature allocated from free text has no documents yet. If the
      context does not suggest frontend work, skip silently.

   d. **Google Tag Manager (GTM) Events** — if the source context suggests
      frontend work (same detection as 6c), ask: "Do you want to include
      Google Tag Manager (GTM) events for this feature?" If yes, collect
      a list of events — for each event, gather:
      - **Event name** — the dataLayer event name (e.g. `cta_click`,
        `form_submit`, `page_view`)
      - **Trigger** — what user action fires it (e.g. "User clicks the
        Export button")

      If the user declines, skip. If the context does not suggest frontend
      work, skip silently.

7. **Fill remaining gaps.** Compare what has been gathered against the required
   data fields from step 3. For each field still missing or unclear, prompt the
   user via `AskUserQuestion`. Batch related questions (up to 4 per call).

   Common gaps to check for:
   - **Change type** — bug fix, enhancement, new feature, refactor
   - **Scope boundary** — what's explicitly out of scope
   - **Milestones** — "Does this work have milestones/phases, or is it a
     single deliverable?" If milestones: collect names and brief scope for each.
   - **Affected services** — if inferable from source or codebase, propose
     them and ask the user to confirm. If not determinable, ask directly.
   - **Database/API changes** — whether schema or endpoint changes are expected
   - **Acceptance criteria** — how we know it's done
   - **Risks & mitigations** — known risks or constraints

   If context was extracted from a Scoping Doc + PRD, most fields will already
   be populated — the user only confirms or fills small gaps.

8. **Milestone handling.** If milestones were defined (from source or user):

   - Present them via `AskUserQuestion` (`multiSelect: true`), listing each
     milestone by name with a brief scope summary.
   - Let the user pick one or more. At least one must be selected.
   - In `remote` mode: each selected milestone produces a separate Jot Down
     document (a separate Notion page). Steps in Phase 3 execute once per
     milestone, scoped to that milestone only. Cross-milestone dependencies
     should be noted but not detailed.
   - In `local` mode: one feature directory holds one Jot Down. Steps 9–12a
     execute once per milestone to draft that milestone's section, and all
     selected milestones are assembled into the single document written in
     step 13, each under its own `### Milestone N of M` heading.
     Cross-milestone dependencies should be noted but not detailed.

   If no milestones: generate a single Jot Down covering entire scope.

---

### Phase 3: Generation

9. **Read affected repositories.** For each repo from step 6a, navigate to
    the repo path and read its `.claude/CLAUDE.md` and `.claude/ARCHITECTURE.md`
    (if they exist) to understand architecture, components, data flow, patterns,
    and constraints. If `.claude/CLAUDE.md` does not exist, check for a legacy
    `CLAUDE.md` at the repository root.

10. **Read relevant source code** in the affected repos to understand current
    implementation details: data models, API endpoints, service interactions,
    existing patterns.

10a. **Dispatch a research pass over the affected repositories.** Spawn a
    read-only research sub-agent (via the Agent tool) per affected repository
    to verify the source documents' concrete claims against the actual
    codebase — even when the Scoping Doc and PRD have already been reviewed
    and approved. Approval establishes intent, not correctness: a document
    can be internally consistent while resting on a false premise stated one
    line deep in an unrelated file (e.g. an API client that discards the
    credential the whole feature depends on, a source-scan rule that forbids
    the exact module name the plan introduces, a route table that already
    claims the prefix the plan appends to).

    For each concrete claim the source documents make about the codebase — a
    field that exists, a permission or auth model, a route table, a union's
    members, a contract or schema shape — instruct the sub-agent to report
    whether the tree confirms it. In particular, verify that every field the
    source documents promise to display, filter on, or otherwise expose
    exists in the repo's pinned contract/schema definitions, and flag any UI
    affordance (a nav pattern, an icon vocabulary, a badge) that breaks a
    precedent already established by prior screens in the same repo.

    Treat the sub-agent's own citations as claims to re-verify, not facts to
    transcribe directly — particularly any count of "N files reference X": a
    string literal or property name shared by two unrelated types is
    commonly reported as one set, and an instruction to change "the ten
    places" built on an unverified count can break the ones that share only
    the string. Spot-check any citation that will drive a Jot Down
    instruction before writing it in.

    Route each finding to the step that fits: a document claim directly
    contradicted by the code goes to step 11a. A schema gap or precedent
    break the source documents never anticipated, where more than one fix is
    reasonable, goes to step 11 as a decision for the user. A schema gap
    where there is only one reasonable fix is a source correction (step 11a)
    even though nothing in the source document was stated as fact and then
    disproved.

11. **Surface architectural decisions.** Before generating, identify any
    design choices where multiple valid approaches exist that were not already
    resolved in the source material. Common examples:

    - Synchronous (HTTP) vs asynchronous (message queue / events) processing
    - New model/table within an existing service vs new microservice
    - Existing database vs new dedicated database
    - REST vs gRPC vs GraphQL for a new API surface
    - Streaming vs batch for data processing
    - Specific library or framework choices (e.g. which CSV parser, which
      validation library)
    - Schema design trade-offs (embedded vs referenced documents, normalized
      vs denormalized)

    For each decision found, present it to the user using `AskUserQuestion`
    with concrete options. Explain the trade-offs briefly (1-2 sentences per
    option). Include relevant context from the codebase (e.g. "the existing
    service uses Mongoose with embedded documents for similar data").

    The user can:
    - **Pick an option** — the Jot Down will use that decision.
    - **Choose "Pending"** — the decision is recorded in the Jot Down as
      `⚠️ PENDING DECISION: <description>` so it can be resolved later.

    Skip decisions already resolved in the source material — reference them
    instead. Batch related decisions into a single question set when possible
    (up to 4 questions per `AskUserQuestion` call). Do NOT silently pick an
    approach — always ask.

11a. **Record source corrections.** Where a source document's claim about
    existing code is contradicted by the code, the code wins and the Jot
    Down states the corrected fact — do not silently follow the source, and
    do not silently correct it without a record.

    Capture each correction as a structured record with a stable ID:

    ```
    C-<n>:
      source: <prd | scoping-doc | other>
      location: <section/ID or heading in the source document>
      original_claim: "<the exact wording the source stated>"
      corrected_fact: "<what the tree actually shows>"
      evidence: "<file:line, grep output, or 1–2-line excerpt that proves it>"
      date: <YYYY-MM-DD>
      changes_work: <true | false>   # does the correction add/drop/rewrite a task?
    ```

    IDs run `C-1`, `C-2`, … across all milestones in the current run.

    - Add a row to the **1. Architectural Decisions** table (step 12) for
      each correction: Decision = the claim being corrected, Options
      Considered = what the source document said, Chosen Approach = the
      corrected fact, Rationale = `Correction C-<n> to <source doc>
      <section/ID>, verified against <artefact>, <date>.` plus the one or
      two lines of supporting evidence.
    - If `changes_work` is true (a migration turns out to be needed, or
      turns out not to be, a planned contract edit is dropped) — say so
      explicitly in the relevant Phase 3 section (Database Model Changes,
      API Specifications, etc.) too, since `generate-task-breakdown` reads
      those sections, not the decisions table, to build the work breakdown.
    - If the correction is **behavioural and visible to a user or
      operator** — the code settles what is *possible*, but not what is
      *wanted* — treat it as a step 11 question instead of a silent
      correction. (Example: the source says an operator retry clears a
      status field; a DB trigger forbids the clear. "Keep it sticky" vs.
      "add a migration to allow the clear" is a real choice for the user,
      not a correction.)
    - Also mirror every correction in the Jot Down's **Section 0
      Corrections** block (step 12) so a reader does not re-litigate the
      original claim.
    - Step 14a (after the Jot Down is written) offers to propagate the
      corrections back to the source documents as dated notes.

12. **Generate the Jot Down Implementation Spec.** If a template was fetched
    in step 3, follow its structure. Otherwise, use the default structure below.

    The Jot Down must be **self-sufficient** — `generate-task-breakdown` works
    from it alone without needing to fetch a PRD or Scoping Doc.

    ### Title: Jot Down — <Feature Name> (Milestone N: <Milestone Name>)
    If covering the full scope (no milestones), omit the parenthetical.

    ### References
    - If Scoping Doc + PRD exist: `[PRD link] | [Scoping Doc link]`
    - Otherwise: `Source: [link to original source]` or `Source: Manual input`

    ### Milestone: N of M — <Milestone Name>
    Include when milestones are defined (regardless of source). Omit if no
    milestones.

    ### Author / Date / Status: Draft

    ### 0. Corrections
    **Include only if step 11a recorded one or more corrections for this
    milestone.** Omit the section entirely otherwise.

    Numbered list, one entry per correction, in `C-<n>` order:

    - **C-<n>** — `<source doc> <section/ID>`: the source said
      "<original_claim>"; the tree shows "<corrected_fact>" (evidence:
      `<file:line or artefact>`, <date>).

    This section exists so a reader can skip re-litigating premises the
    code already settled. The original claim is quoted verbatim; it is not
    deleted from the source document. Step 14a offers to add a matching
    dated note to the source itself.

    ### 1. Architectural Decisions
    Table: Decision | Options Considered | Chosen Approach | Rationale

    Include every decision surfaced in step 11, every source correction
    recorded in step 11a, and any already resolved in the source material.
    For pending decisions, set Chosen Approach to
    `⚠️ PENDING DECISION` and Rationale to the context that will help the
    team resolve it later.

    ### 2. Overall Solution
    Technical narrative: what are we building, how do the pieces fit together,
    and what's the end-to-end flow?

    ### 3. Database Model Changes
    For each affected database:
    - Current schema (relevant tables/collections)
    - Proposed changes (new fields, new tables, indexes)
    - Migration strategy
    - Backward compatibility notes

    ### 4. API Specifications
    For each new or modified endpoint:
    - Method, path, description
    - Request schema (with types)
    - Response schema (with types)
    - Error responses
    - Authentication requirements
    - Acceptance criteria for this endpoint (embedded directly — do not rely
      on external PRD references alone)

    ### 5. System Design
    - Component diagram or description of service interactions
    - Data flow for the primary use case
    - Sequence of operations
    - Explicitly list all affected services

    ### 6. Service Interactions
    Which services call which? New inter-service communication. Message
    formats if using queues/events.

    ### 7. Dependencies
    External services, third-party APIs, shared libraries that need updates.

    ### 8. Feature Flag
    **Include only if a feature flag is needed** (from step 6b). Pick the
    subsection that matches `sdlc.feature_flags` and drop the other.

    If from a Scoping Doc, pull the flag details from the Scoping Doc's
    Section 8. Otherwise, use details gathered in step 6b and codebase
    analysis.

    **If `feature_flags` is `split`** (Split.io or equivalent SaaS):

    For each service that checks the flag:
    - **Service / Repo**: which service evaluates the split
    - **Evaluation point**: where in the code the split is checked (e.g.
      route handler, service method, middleware)
    - **Key**: what value is used as the Split key (e.g. `org_id`, `user_id`)
    - **Treatment mapping**: what each treatment value means in code
      (e.g. `on` → use new endpoint, `off` → use legacy endpoint)
    - **Fallback behavior**: what happens if the SDK can't reach the
      platform (must match the default treatment — safe/current behavior)

    **If `feature_flags` is `env`** (environment variables, settings
    tables, or per-tenant kill switches):

    For each service that reads the flag:
    - **Service / Repo**: which service reads the flag
    - **Scope**: `env var`, `settings table` row, `config file`, or other
    - **Read point**: where in the code the flag is read (e.g. module
      init, route handler, middleware)
    - **Value mapping**: what each value means in code (e.g. `true` → new
      path, `false` → legacy)
    - **Fallback behavior**: what happens if the flag is unset or
      unreachable (must match the default — safe/current behavior)

    ### 9. Deployment Stages
    Ordered list of what gets deployed when. Rollback plan for each stage.
    Include risks and mitigations per stage.

    ### 10. Testing Strategy
    What needs to be tested at each level (unit, integration, e2e)?
    Key test scenarios. Include acceptance criteria — testable conditions
    for "done" (embedded directly in this section).

    Every acceptance criterion must be **measurable**: a reader must be able
    to write a test that returns pass or fail without asking anyone what the
    criterion meant. Quality adjectives are not criteria — `fast`, `slow`,
    `scalable`, `secure`, `robust`, `intuitive`, `reliable`, `performant`,
    `user-friendly`, `efficient`, and `simple` must each carry a number, a
    threshold, or a concrete observable behavior.

    | Not acceptable            | Acceptable                                         |
    | ------------------------- | -------------------------------------------------- |
    | Endpoint is fast          | Endpoint responds in < 200 ms at p95 under 50 rps  |
    | Errors handled gracefully | 4xx returns the repo's standard error envelope; 5xx is logged with the request ID |
    | Export is reliable        | Export of 10k rows completes without truncation and is byte-identical on retry |

    ### 11. Frontend Components
    **Include if a Data UI Inventory was provided (from step 6c) or GTM
    events were selected (from step 6d).**

    Summarize the component inventory, payloads, and layout structure from
    the Data UI Inventory. Reference component names and their parent
    containers. Include integration points with backend APIs from Section 4.

    #### GTM Events
    **Include only if GTM events were selected** (from step 6d).

    Table: Event Name | Trigger

    List each event collected in step 6d. The event name is what will
    appear in the dataLayer push. The trigger is the user action that
    fires the event.

12a. **Gate the draft on measurable, executable acceptance criteria.** Before
    writing the Jot Down, re-read every acceptance criterion drafted in
    Section 10 (and any embedded per-endpoint criteria in Section 4).

    **First pass — measurability.** For each criterion, check whether it can
    be turned into a passing or failing test as written. Flag any criterion
    that leans on an unquantified quality adjective (the list in Section 10)
    or that describes an intent rather than an observable outcome.

    For each flagged criterion:
    - If the source documents or the repo's CLAUDE.md supply the threshold
      (an existing SLA, an established p95 target, a documented error
      envelope), rewrite the criterion using that value and note the source
      inline.
    - If no threshold exists anywhere, ask the user for it via
      `AskUserQuestion`. Batch these questions (up to 4 per call) and offer a
      recommended default with a one-line rationale, so the answer is a
      confirmation rather than an essay.
    - Only if the user explicitly declines to set a threshold, mark the
      criterion `⚠️ NEEDS HUMAN INPUT: no measurable threshold agreed` and
      leave it visible in the document.

    Do NOT invent a threshold silently. An invented number is worse than a
    flagged gap, because it looks agreed.

    **Second pass — executability.** For every criterion that survives the
    measurability pass, identify the harness that will run it (unit,
    integration, e2e) and confirm that harness can actually observe the
    thing being asserted. Read the real test configuration — the e2e
    runner's server-start command, the integration harness's bootstrapping —
    rather than assuming the suite exercises the deployed artifact or
    mechanism the criterion is about.

    - Where a criterion needs a harness change (e.g. the e2e server command
      must run the actual backend/worker instead of a static preview build)
      to be observable at all, list that change as an explicit task in
      Section 10 (Testing Strategy) and, if it affects rollout, Section 9
      (Deployment Stages).
    - Where a criterion would pass **vacuously** — the condition it asserts
      cannot arise in that harness at all, so a green result would be true
      for the wrong reason (e.g. asserting a cookie is absent in a stack
      that never sets any cookie) — mark it vacuous. Either move it to a
      harness that can falsify it, or drop it and say why in the document.
      A criterion that cannot fail is worse than a missing one: a missing
      criterion is visible, a vacuous one is not.

13. **Write the Jot Down.** Call `write_doc(feature, jotdown, <content>)`,
    where `feature` is the one bound in step 4 — resolved from a feature ref,
    or allocated by `new_feature` when the source was free text.

    **When to call it:**

    - In `remote` mode, call it now, for the milestone just drafted. Each
      selected milestone is its own Notion page, so this step runs once per
      milestone.
    - In `local` mode, **do not call it yet if any selected milestone is still
      undrafted.** Go to step 14, which sends you back for the next one. Call
      `write_doc` exactly once, after the last milestone's section exists, with
      every section assembled into a single document. One feature directory
      holds one Jot Down: writing after each milestone would target the same
      path twice and trip the contract's "target already exists — ask before
      overwriting" prompt on the second pass.

    In `remote` mode this creates the Notion page titled
    `Jot Down: <Feature Name> (Milestone N: <Name>)`, or
    `Jot Down: <Feature Name>` when covering the full scope, with the
    properties described below. In `local` mode it writes
    `.sdlc/features/NNN-slug/jotdown.md`; the milestone belongs in the document
    body, since one feature directory holds one Jot Down.

    Reference the PRD and Scoping Doc using `doc_link` so links resolve in both
    modes.

    **Remote mode — page properties:**

    **If `docs_database` is configured** (non-empty in `.claude/settings.local.json`):
    Create the page as an entry in the SDLC Documents database with these
    properties:
    - **Doc Type:** `Jot Down`
    - **Feature:** Extracted from the source or user input
    - **Quarter:** Computed from today's date (e.g. `2026-Q1`)
    - **Related PRD:** URL of the source PRD page (empty if no PRD)
    - **Source:** Original source URL if not a Scoping Doc/PRD (empty otherwise)
    - **Milestone:** The milestone name (e.g. `Milestone 1: Core Export`),
      or empty if covering full scope

    **If `docs_database` is empty:** Fall back to creating a flat page under
    the configured `home_directory`.

14. **Draft the milestones that remain.** If any selected milestone has not
    been drafted yet, return to step 9 and repeat steps 9–12a for the next one.

    - In `remote` mode, step 13 then runs again for that milestone, producing
      one Notion page per milestone.
    - In `local` mode, step 13 has not run yet. Once the last milestone is
      drafted, run step 13 a single time, writing every milestone section into
      the one `jotdown.md`, each under its own `### Milestone N of M` heading.

14a. **Propagate corrections to source documents.** Run this step only if
    step 11a recorded at least one correction across the run. Otherwise skip.

    - Present every correction (C-1, C-2, …) via `AskUserQuestion` with
      `multiSelect: true`:

      > "Phase 3 grounding found N contradictions in the source
      > documents. Which should also be noted on the source document
      > itself as a dated correction? The original claim stays — I only
      > append a note."
      >
      > One option per correction: `C-<n>: <source> <section/ID> —
      > <one-line summary>`.

    - For every selected correction:
      - Read the source document — PRD or Scoping Doc — via
        `read_doc(feature, prd)` or `read_doc(feature, scoping-doc)`.
      - Locate the paragraph, bullet, or table row that holds the
        original claim. Do **not** delete, rewrite, or move it.
      - Immediately after that paragraph/row, append a block of the form:

        ```
        > ⚠️ CORRECTION C-<n> (<YYYY-MM-DD>): <corrected_fact>.
        > Verified against <evidence>. See Jot Down Section 0.
        ```

        In table rows where appending a block is awkward, add a new
        trailing column cell or an inline footnote reference instead; the
        exact rendering is the skill's choice as long as the correction
        is dated, references `C-<n>`, and does not overwrite the
        original.
      - Write the updated document back via
        `write_doc(feature, prd, <content>)` or
        `write_doc(feature, scoping-doc, <content>)`.

    - For corrections the user chose **not** to propagate, do nothing to
      the source document. The Jot Down's Section 0 and the Decisions
      table still carry the correction for the record.

    - Report what was updated: the list of correction IDs applied to each
      source document, with the artifact references. If a selected
      correction's source document could not be located (free-text run,
      no PRD/Scoping Doc), say so and skip only that one.

15. **Return the artifact reference(s).** In `remote` mode, return all Notion
    page URLs, listed by milestone. In `local` mode, return the single file
    path returned by `write_doc`.

---

### Retrospective

16. **Spawn the Skill Retrospective Agent.** After the Jot Down is written and
    its artifact reference(s) returned — the Notion page(s) in `remote` mode,
    or the file in `local` mode — spawn a sub-agent using the instructions in
    `${CLAUDE_PLUGIN_ROOT}/agents/skill-retrospective.md`.

    Pass to the agent:
    - **Skill name**: `sdlc-generate-jotdown`
    - **What was built**: the Jot Down title(s) and artifact reference(s) —
      Notion URL(s) in `remote` mode, file path in `local` mode
    - **Run summary**: source type used (Scoping Doc, Jira/Linear, Slack, free text),
      key architectural decisions made, gaps that required user input, sections
      that needed iteration, any user corrections or pushback during the run
    - **Workspace config**: the repository list from `.claude/settings.local.json`
    - **Today's date**: in `YYYY-MM-DD` form, so the agent stamps lessons with
      a stable value instead of guessing

    The agent only proposes. It returns a ```retrospective``` fenced JSON
    block — it never asks the user and never writes any file.

17. **Ask the user and save the lessons.** Read
    `${CLAUDE_PLUGIN_ROOT}/references/retrospective-save.md` and follow it
    exactly on the agent's proposal.

## Important

- This document must be specific enough that a coding agent can implement from
  it without ambiguity. Vague descriptions like "update the API" are failures.
- Include actual field names, types, endpoint paths, and status codes.
- Reference the CLAUDE.md and ARCHITECTURE.md for each repo (e.g. if the
  repo uses a specific error handling pattern or data flow, the Jot Down
  should use that pattern).
- If you cannot determine something from the codebase, mark it as
  `⚠️ NEEDS HUMAN INPUT: <what's needed>` — do not guess.
- The Jot Down must be self-sufficient: `generate-task-breakdown` must be able
  to create tasks from it alone — Jira/Linear issues in `remote` mode, task files in
  `local` mode — without fetching a PRD or Scoping Doc. All milestones,
  acceptance criteria, affected services, architectural decisions, and risks
  must be embedded directly in the document.
