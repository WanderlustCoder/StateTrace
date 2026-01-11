# Code review methodology (2026-01-09)

## Approach
- Static review: inspect code paths, error handling, concurrency, and telemetry emission.
- Dynamic validation: run required tests/harnesses, capture telemetry, and compare to gates.
- Evidence-driven: every finding is linked to a file/line reference and supporting evidence.

## Review workflow
1. Start with entrypoints and high-risk modules.
2. Record findings in `docs/notes/2026-01-09_code_review_findings_report.md`.
3. Update the ledger for every file reviewed (`docs/notes/2026-01-09_code_review_inventory.md`).
4. Log evidence (commands + artifacts) in `docs/notes/2026-01-09_code_review_evidence_log.md`.
5. Track remediation and retest requirements in `docs/notes/2026-01-09_code_review_remediation_tracker.md`.

## Review phases
- Phase 1: Entrypoints + guardrails (ParserWorker, ParserRunspace, MainWindow).
- Phase 2: Repository + Access modules (persistence, schema, concurrency).
- Phase 3: Vendor parsers + detection (fixtures for edge cases).
- Phase 4: UI/view modules + XAML bindings (parser/UI separation).
- Phase 5: Tooling + automation (harnesses, diagnostics, release tooling).
- Phase 6: Docs/governance alignment (runbooks, ADRs, plans).

## Evidence handling
- Capture command output paths and timestamps in the evidence log.
- Prefer review telemetry runs under `STATETRACE_TELEMETRY_DIR` for traceability.
- Record which findings each test/harness retest validates.

## Decision/triage rules
- Blocker/Critical findings halt readiness until resolved or formally waived.
- High findings require remediation plans + targeted tests.
- Medium/Low findings documented for follow-up if not fixed immediately.

## Completion checks
- Findings report, remediation tracker, and test matrix stay in sync.
- Plan G gates either pass or have a documented waiver.
- Task board + session log updated with readiness verdict and blockers.

## Exit criteria
- See `docs/notes/2026-01-09_code_review_exit_criteria.md`.
