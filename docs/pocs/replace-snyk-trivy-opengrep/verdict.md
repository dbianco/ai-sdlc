# PoC #30 — Trivy + Opengrep vs Snyk, verdict

**Date:** 2026-11-10. **Branch:** `poc/issue-30-trivy-opengrep`.

**Scope:** validate that Trivy (SCA/secret/misconfig) and Opengrep (SAST,
stand-in: Semgrep 1.184.0) can replace the Snyk MCP path in
`security-agent.md` without regressing the PASS / PASS-WITH-FP / FAIL /
SKIPPED report shape or the setup ergonomics (no OAuth, no per-folder
trust).

## Signal

Fixture: a seven-seed insecure Flask repo in `poc-fixture/` with a
vulnerable Python `requirements.txt`, four hardcoded secrets, two unsafe
Flask handlers, and a Dockerfile running as root.

| Seed                                | Expected tool  | Found? | Notes                                                                 |
|-------------------------------------|---------------|--------|-----------------------------------------------------------------------|
| `urllib3@1.25.3`                     | Trivy SCA      | yes    | 5 HIGH CVEs flagged                                                   |
| `requests@2.20.0`                    | Trivy SCA      | yes    | HIGH                                                                   |
| `jinja2@2.10`                        | Trivy SCA      | yes    | HIGH                                                                   |
| AWS access-key-id + secret           | Trivy secret   | yes    | CRITICAL — once seed was not the AWS canonical example key            |
| GitHub PAT                          | Trivy secret   | yes    | CRITICAL                                                              |
| Slack webhook URL                   | Trivy secret   | **no** | known gap — confirms issue reporter's finding on webhooks + keystores |
| `eval(user_input)` Flask handler    | Semgrep SAST   | yes    | ERROR + WARNING                                                       |
| `request.args["url"]` SSRF handler  | Semgrep SAST   | no     | not covered by `p/python` + `p/flask`; curated rule-set needed        |
| Flask `host=0.0.0.0, debug=True`    | Semgrep SAST   | yes    | 2 WARNINGs                                                            |
| Dockerfile without `USER`           | Trivy misconfig| yes    | HIGH DS-0002                                                          |

### Counts

- **Trivy:** 8 SCA HIGH, 3 secrets CRITICAL, 1 misconfig HIGH, 0 noise findings.
- **Semgrep:** 4 findings (2 ERROR, 2 WARNING), 0 noise findings on this
  fixture. **Caveat:** the issue reporter's real repo produced 101/140
  `jsx-not-internationalized` findings — the noise is rule-set dependent,
  not tool-dependent. The agent must ship with a curated rule set.

### Latency

- **Trivy first run (cold DB, 133 MiB):** ~25 s on fast link.
- **Trivy cached:** 1.03 s against the fixture.
- **Semgrep:** 3.06 s against the fixture.

Both are well under the time budget of a Coding Agent run. No daemon
required. Both run entirely offline after first-run DB cache.

## What worked

1. **JSON output shape is clean** for both tools. Parsing into the
   agent's internal finding record is 10 lines of code per tool.
2. **Severity mapping is obvious:** CRITICAL/HIGH→blocking, MEDIUM→warn,
   LOW→drop for Trivy; ERROR→blocking, WARNING→warn for Opengrep.
3. **No OAuth, no browser prompt, no per-folder trust.** Both tools work
   immediately after `brew install` with no account.
4. **File-routing is deterministic** by extension — no MCP round-trip.

## What broke, caveats, open questions

1. **Trivy secret coverage has gaps.** Slack webhooks not detected.
   Known from the issue; confirmed here. Options: layer in `trufflehog`
   or `gitleaks` for a second secret pass, or document the gap and set
   expectations.
2. **Semgrep rule set matters a lot.** Default `p/python` + `p/flask`
   missed SSRF on `/fetch`. The real noise problem (101 `jsx-not-
   internationalized` findings) is a rule-set problem, not an engine
   problem. Production needs a vetted rule set per language, probably
   vendored under `plugins/sdlc/references/opengrep-rules/`.
3. **Opengrep isn't in Homebrew at PoC time.** PoC used semgrep. The
   production agent needs a decision: download the opengrep release
   binary during `sdlc-workspace-init`, or ship semgrep and document the
   difference. Both work; pick one.
4. **Trivy DB download has a 5-min default timeout** that failed on a
   slow link in the issue reporter's eval. Production must support
   `--db-repository` and a custom timeout via workspace config.
5. **Suppressions move** from `snyk:ignore` to `.trivyignore` +
   `# nosem:`. Mechanical migration for existing suppressions; new ones
   pick up the new form.
6. **Auto-remediation stays the same** for SCA (bump to lowest fixed
   version). No auto-remediation for secrets (user must rotate) or
   SAST (needs code-aware judgment). Misconfig fixes are usually small
   but need project context — suggest, don't apply.

## Verdict

**Viable.** The signal is strong enough for a production migration. The
JSON mapping is trivial, latency is well within budget, and the setup
story is dramatically simpler than Snyk (no OAuth, no trust store, no
MCP server to register globally). The main cost is picking a curated
Opengrep rule set and deciding how Opengrep gets onto `PATH` in
`sdlc-workspace-init`.

**Rough migration budget:** 2–4 hours of focused work, broken as:

- Replace `security-agent.md` body with the Trivy + Opengrep procedure
  (base: `scratchpad/security-agent-poc.md`) — 60–90 min.
- Rewrite `sdlc-workspace-init` Phase 6 (detect-or-install `trivy` +
  `opengrep`, replace OAuth and trust-gate steps, remove `SNYK_TOKEN`
  handling and the `mcpServers.Snyk` write) — 60 min.
- Curate the Opengrep rule set under
  `plugins/sdlc/references/opengrep-rules/` with
  `jsx-not-internationalized` disabled by default — 20–30 min (small
  starter set; expand over time).
- Doc sweep: `.claude/ARCHITECTURE.md`, `.claude/CLAUDE.md`, `AGENTS.md`,
  `README.md`, `.vscode/settings.json` — 20 min.
- Suppression docs (migration note for `snyk:ignore` → `.trivyignore` /
  `# nosem:`) — 10 min.

## Next step

If the migration is approved: open a feature branch
`feat/issue-30-trivy-opengrep`, base the agent on
`scratchpad/security-agent-poc.md`, decide the Opengrep-vs-semgrep
question, and bundle the five bullets above into one PR referencing
#30. The PoC branch (`poc/issue-30-trivy-opengrep`) can be deleted — it
carries nothing except this verdict and the scratchpad fixture.
