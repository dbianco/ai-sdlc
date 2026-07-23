---
name: sdlc-implement-task
description: Implement a Linear issue by orchestrating the Coding, Test, Security, and Documentator agents
disable-model-invocation: true
---

# /sdlc-implement-task

Implement a Linear issue by orchestrating the Coding Agent, Test Agent,
Security Agent, and Documentator Agent. This is the entry point for the
autonomous coding loop.

## Input

$ARGUMENTS — A Linear issue identifier (e.g. `YAL-123`).

## Procedure

1. **Load `.claude/settings.local.json`** from the project root. Read the `sdlc` config key,
   including safety boundaries.

2. **Fetch the Linear issue** via the Linear MCP. Read:
   - Title, description, acceptance criteria
   - Parent issue (for broader context)
   - Sub-issues (list them with their status)
   - Dependencies (ensure they are completed — abort if not)
   - Labels (to identify target repository and language)

3. **Confirm with the user** before proceeding. Present a summary using
   `AskUserQuestion`:
   - **Issue ID and title**
   - **Description** (first ~3 sentences or acceptance criteria)
   - **Status and priority**
   - **Sub-issues** (list each with ID, title, and status)
   - **Dependencies** (list any, noting if they are completed or not)
   - **Labels**

   Ask: "Do you want to proceed with implementing this issue?"
   Options:
   - "Yes, implement it" — continue to step 4.
   - "No, cancel" — abort gracefully with no changes.

   If the user cancels, stop execution and inform them that no changes were
   made. Do NOT proceed to any subsequent steps.

4. **Identify the target repository** from the issue description or labels.
   Validate it exists in `.claude/settings.local.json`. Abort if not found.

5. **Navigate to the repository** and read its `.claude/CLAUDE.md` and
   `.claude/ARCHITECTURE.md` (if they exist). If `.claude/CLAUDE.md` does
   not exist, check for a legacy `CLAUDE.md` at the repository root.

6. **Validate safety boundaries:**
   - Check that the implementation won't require modifying restricted paths.
   - Read `sdlc.safety_boundaries.max_files_per_pr` (default: 20) and
     `sdlc.safety_boundaries.max_lines_per_pr` (default: 500) from the config.
     Check that estimated changes are within these limits.
   - If boundaries would be violated, report to user and abort.

7. **Pull latest from remote and create a working branch:**
   ```
   git fetch origin
   git checkout main
   git pull origin main
   git checkout -b ai/<issue-id>-<slugified-title>
   ```

8. **Spawn the Coding Agent** as a sub-agent via Task:

   Pass to the Coding Agent:
   - The Linear issue details (title, description, acceptance criteria)
   - The repository path and CLAUDE.md content
   - The workspace safety boundaries
   - Instruction: "Implement the changes and write tests. Do not submit a PR."

   Read the Coding Agent instructions from `${CLAUDE_PLUGIN_ROOT}/agents/coding-agent.md`.

9. **Spawn the Test Agent** as a sub-agent via Task:

   Pass to the Test Agent:
   - The changes made by the Coding Agent (files modified)
   - The repository path and CLAUDE.md content
   - The acceptance criteria from the Linear issue

   Read the Test Agent instructions from `${CLAUDE_PLUGIN_ROOT}/agents/test-agent.md`.

10. **Handle Test Agent feedback:**
   - If the Test Agent reports **PASS**: proceed to step 11.
   - If the Test Agent reports **FAIL**: pass the feedback back to a new
     Coding Agent Task for iteration. Maximum 3 iteration cycles.
     If still failing after 3 cycles, report to user and abort.

11. **Spawn the Security Agent** as a sub-agent via Task:

    Pass to the Security Agent:
    - The exact list of files modified by the Coding Agent
    - The repository path, CLAUDE.md content, and ARCHITECTURE.md content
      (if it exists)
    - The Linear issue details (title, description, acceptance criteria) —
      used for false positive evaluation context
    - The workspace safety boundaries from `.claude/settings.local.json`

    Read the Security Agent instructions from
    `${CLAUDE_PLUGIN_ROOT}/agents/security-agent.md`.

    **Handle Security Agent results:**
    - **PASS** or **PASS-WITH-FP**: proceed to step 12. If PASS-WITH-FP,
      include the FP summary in the final report.
    - **FAIL**: surface the unresolved findings to the user. Ask whether to:
      - "Fix manually and continue" — pause for human fixes, then re-run
        the Security Agent once more before proceeding.
      - "Accept risk and continue" — proceed with a documented security
        exception noted in the commit message.
      - "Abort" — stop, update the Linear issue to "Blocked" with a comment
        listing the unresolved findings.
    - **SKIPPED**: proceed to step 12 with a warning note for the commit
      message: `Security scan was skipped — Snyk not configured.`

12. **Spawn the Documentator Agent** as a sub-agent via Task:

    Pass to the Documentator Agent:
    - The changes made (files modified, new endpoints, schema changes)
    - The repository path and CLAUDE.md content

    Read the Documentator Agent instructions from
    `${CLAUDE_PLUGIN_ROOT}/agents/documentator-agent.md`.

13. **Commit all changes:**
    ```
    git add -A
    git commit -m "<type>(<scope>): <description>

    Implements <LINEAR-ISSUE-ID>

    <bullet summary of changes>

    Security: <PASS|PASS-WITH-FP|FAIL|SKIPPED> — <N findings remediated, M FPs documented, 'unresolved findings — see report', or 'scan skipped'>"
    ```
    Follow the repo's commit convention from CLAUDE.md if one exists.
    Always include the `Security:` trailer line from the Security Agent report.

14. **Report to the user:**
    - Summary of changes made
    - Test results (pass/fail counts, coverage)
    - Security scan results (status, findings remediated, FPs documented)
    - Files modified (list)
    - Number of iteration cycles needed
    - Ready for human review: `git diff main..HEAD`

15. **Update the Linear issue** status to "In Review" via the Linear MCP.

---

### Retrospective

16. **Spawn the Skill Retrospective Agent.** After all changes are committed
    and the Linear issue is updated, spawn a sub-agent using the instructions
    in `${CLAUDE_PLUGIN_ROOT}/agents/skill-retrospective.md`.

    Pass to the agent:
    - **Skill name**: `sdlc-implement-task`
    - **What was built**: the Linear issue ID, title, and branch name
    - **Run summary**: number of Coding/Test Agent iteration cycles needed,
      test results (pass/fail/coverage), security scan status and finding
      counts, files modified count, any safety boundary concerns, any user
      corrections or pushback during the run
    - **Workspace config**: the repository list from `.claude/settings.local.json`

## Important

- This skill orchestrates. It does NOT write code itself.
- Each sub-agent runs in a sandboxed Task. The orchestrator passes context
  in and reads results out.
- If any step fails unrecoverably, update the Linear issue with a comment
  explaining what happened, set status to "Blocked", and report to the user.
- Never push to remote or create a PR automatically. The human decides when
  to push.