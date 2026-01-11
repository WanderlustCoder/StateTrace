# ADR 0005: Autonomous Development & CI

## Status
Accepted – 2026-01-09

## Context
StateTrace relies on automated agents and scripted pipelines to accelerate delivery. Without guardrails, autonomous changes can drift from offline-first requirements, skip required evidence, or introduce non-deterministic CI failures. CI must remain deterministic, offline-capable, and aligned with plan gating.

## Decision
Adopt a **plan-first, evidence-backed autonomous workflow** with CI parity:
- **Plan-first execution:** non-trivial tasks require a short plan before edits; the plan is updated as work completes.
- **Offline-first by default:** no network access or installs unless explicit opt-in flags are set; all outputs remain PowerShell + Access compatible.
- **Evidence and doc sync:** every session records evidence and updates the relevant plan/task documentation before closing.
- **CI parity:** automated runs follow the same automation matrix as local runs; no hidden dependencies or interactive prompts.

## Guardrails
- Require session logs under `docs/agents/sessions/` for autonomous runs.
- Follow `docs/CODEX_RUNBOOK.md` for authoritative commands and validations.
- Run `Invoke-Pester Modules/Tests` (or plan-specific gates) before claiming completion.
- Never commit `.accdb` files or generated logs; use `Data/Samples/` for tracked fixtures.
- Use module-qualified calls and approved verbs to preserve module boundaries.
- Online mode only with `STATETRACE_AGENT_ALLOW_NET=1` / `STATETRACE_AGENT_ALLOW_INSTALL=1` and NetOps logging.

## Consequences
- **Pros:** consistent evidence, reproducible CI, safer automation, and fewer review surprises.
- **Cons:** more process overhead and documentation updates.
- **Mitigations:** templated session logs and automation runbooks reduce friction.

## Alternatives Considered
- Allow autonomous changes without guardrails (rejected: higher regression and compliance risk).
- Require all changes to be fully manual (rejected: slows delivery).
- Permit CI to use online dependencies (rejected: violates offline-first posture).

## Follow-ups
- Keep `docs/StateTrace_AI_Agent_Guide.md` and `docs/Core_Ideas.md` in sync with these rules.
- Ensure runbooks enumerate required test gates for each plan.

## References
- `docs/StateTrace_AI_Agent_Guide.md`
- `docs/CODEX_RUNBOOK.md`
- `docs/Core_Ideas.md`
