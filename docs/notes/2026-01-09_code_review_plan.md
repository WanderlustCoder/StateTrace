# Code review plan (2026-01-09)

Scope: production readiness review of the StateTrace repo (Modules/, Tools/, Views/, Main/, and release/runbook docs). Focus on reliability, security, offline-first compliance, telemetry, and parser/UI separation.

## Objectives
- Review every module/script and record findings with severity + file/line refs.
- Validate error handling, concurrency safety, parameterized Access writes, and telemetry coverage.
- Execute required tests/harnesses and compare metrics against automation gates.

## Guardrail plan (3-6 steps)
1. Reconfirm scope/entrypoints and sync planning docs (scope, methodology, artifact map).
2. Review modules/tools in priority order; log findings with file/line refs.
3. Run Pester and required pipeline/verification harnesses; capture telemetry.
4. Triage findings, implement fixes, add tests as needed, and rerun targeted validations.
5. Update findings report, remediation tracker, task board, and session log with readiness verdict.

## Review checklist (per file)
- Strict mode in modules; approved PowerShell verbs for exports.
- Error handling emits warnings/errors on critical paths (avoid silent failures).
- Access writes use parameterized ADODB commands and dispose COM objects.
- Concurrency safety for shared/global caches and runspaces.
- Telemetry emitted for key paths (ParseDuration, DatabaseWriteLatency, InterfaceSyncTiming, etc.).
- Offline-first + security hygiene respected (no network dependencies, no raw logs/.accdb in repo).

## Test + telemetry plan
- Invoke-Pester Modules/Tests
- Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -RunWarmRunRegression
- Tools/Analyze-SharedCacheStoreState.ps1 -Path Logs/IngestionMetrics/<file>.json -IncludeSiteBreakdown
- Tools/Analyze-SiteCacheProviderReasons.ps1 -Path Logs/IngestionMetrics/<file>.json -IncludeHostBreakdown
- Tools/Invoke-StateTraceVerification.ps1 (Plan G gate) and telemetry bundle readiness checks as required
- UI smoke/harnesses per runbook if UI surfaces are reviewed

## Artifacts to produce
- Review ledger (table below) with status per file.
- Findings report with severity-ranked issues and recommendations.
- Session log + plan/task board/backlog updates.
- Telemetry/test evidence paths under Logs/.

## Coverage map (seeded)
Inventory + ledger: `docs/notes/2026-01-09_code_review_inventory.md`.
- Main (2 files): Reviewed
- Modules (80 files): Reviewed
- Modules/Tests (92 files): Reviewed
- Views (26 files): Reviewed
- Tools (167 files): Reviewed
- Resources/Templates/Themes (12 files): Reviewed
- Troubleshooting (3 files): Reviewed
- Tests (harness + fixtures) (65 files): Reviewed
- Docs (release/runbooks/governance) (41 files): Reviewed
- Data (json config/history) (7 files): Reviewed

## Review ledger
Seeded in `docs/notes/2026-01-09_code_review_inventory.md`; update status/notes there as review progresses.

## Checklist reference
Subsystem checklists, severity rubric, risk flags, and evidence requirements live in `docs/notes/2026-01-09_code_review_checklist.md`.

## Supporting planning docs
- Scope + review order: `docs/notes/2026-01-09_code_review_scope.md`.
- Evidence log template: `docs/notes/2026-01-09_code_review_evidence_log.md`.
- Findings report template: `docs/notes/2026-01-09_code_review_findings_report.md`.
- Entrypoints map: `docs/notes/2026-01-09_code_review_entrypoints.md`.
- Test matrix: `docs/notes/2026-01-09_code_review_test_matrix.md`.
- Progress tracker: `docs/notes/2026-01-09_code_review_tracking.md`.
- Risk log: `docs/notes/2026-01-09_code_review_risk_log.md`.
- Environment checklist: `docs/notes/2026-01-09_code_review_env_checklist.md`.
- Exit criteria: `docs/notes/2026-01-09_code_review_exit_criteria.md`.
- Dependencies log: `docs/notes/2026-01-09_code_review_dependencies.md`.
- Decision log: `docs/notes/2026-01-09_code_review_decision_log.md`.
- Remediation tracker: `docs/notes/2026-01-09_code_review_remediation_tracker.md`.
- Schedule: `docs/notes/2026-01-09_code_review_schedule.md`.
- Methodology: `docs/notes/2026-01-09_code_review_methodology.md`.
- Artifact map: `docs/notes/2026-01-09_code_review_artifact_map.md`.
- Telemetry gate checklist: `docs/notes/2026-01-09_code_review_telemetry_gate_checklist.md`.
