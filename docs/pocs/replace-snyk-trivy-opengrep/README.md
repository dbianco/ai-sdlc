# PoC — Replace Snyk with Trivy + Opengrep in the security gate

Validates that **Trivy** (SCA, secrets, IaC/misconfig) and **Opengrep**
(SAST, with `semgrep` as a drop-in stand-in) can replace the Snyk MCP
path in `plugins/sdlc/agents/security-agent.md` without regressing the
report shape or the setup ergonomics.

Tracking issue: [#1 — Replace Snyk with Trivy and Opengrep in the security
gate](../../../../../issues/1).

## Artifacts

| File | What it is |
|---|---|
| [`verdict.md`](verdict.md) | PoC verdict: signal, latency, caveats, and the migration budget estimate (2–4 h). |
| [`security-agent-prototype.md`](security-agent-prototype.md) | Prototype agent: the base for the production `security-agent.md` rewrite. |
| [`fixture-seeds.md`](fixture-seeds.md) | Documented seed table for the insecure Flask fixture used to measure detection. The fixture source is not committed — the seeds are reproducible from the table. |

## Status

PoC complete. Awaiting approval to open the migration PR described under
"Rough migration budget" in `verdict.md`.
