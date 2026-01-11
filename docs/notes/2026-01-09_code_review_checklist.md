# Code review checklist (2026-01-09)

This checklist expands the production readiness review plan with subsystem-specific checks, severity rubric, and evidence requirements.

## Severity rubric
- Blocker: Release-stopping defect or data loss/security risk.
- Critical: High likelihood of failure or corruption under normal use.
- High: Significant reliability or correctness risk; likely impact in production.
- Medium: Reliability/maintainability concern with moderate impact or workaround.
- Low: Minor robustness/clarity issue; low impact.
- Info: Observations, tech debt, or follow-up suggestions.

## Risk flags (use in ledger)
- AccessWrite: Access/ADODB writes, schema, or transaction handling.
- Concurrency: Runspaces, locks, shared caches, or scheduler behavior.
- Telemetry: Missing/incorrect telemetry or gates impact.
- OfflineFirst: Network dependency or non-offline behavior.
- Security: Data hygiene, redaction, or sensitive handling.
- UI: XAML bindings, view initialization, UX flows.
- Parser: Parsing correctness, vendor log parsing, ingestion pipeline.
- Tooling: Script safety, destructive operations, or guardrails.

## Subsystem checklists

### Parser pipeline + runspaces
- Strict mode; no implicit globals.
- Concurrency guardrails: locks, shared cache synchronization, fairness checks.
- Errors surfaced for critical failures; no silent catch on core paths.
- Telemetry emitted for ParseDuration, DatabaseWriteLatency, InterfaceSyncTiming.
- Shared cache snapshot handling uses documented helpers.

### Vendor parsers
- Parser logic handles missing fields and malformed lines safely.
- Vendor detection aligns with VendorDetectionModule and templates.
- Telemetry or diagnostics recorded for parsing errors.
- Tests/fixtures cover vendor-specific parsing edge cases.

### Repository/data modules (Access)
- Parameterized ADODB commands for all writes.
- Transactions and rollback errors surfaced.
- COM objects disposed/closed on success and error paths.
- Schema/version assumptions documented or validated.
- Global cache and shared cache contracts preserved.

### UI/view modules
- Parser/UI separation maintained (UI reads from Access/cache only).
- XAML bindings verified; ViewStateService initialized.
- Error handling for missing data; avoid silent failures.
- UI automation/harness readiness (no blocking dialogs in headless paths).

### Tools/automation
- Destructive actions guarded by path validation.
- Online-mode guardrails respected; NetworkGuard used for downloads.
- Telemetry outputs match runbook and gate requirements.
- Scripts use approved verbs and strict mode where applicable.

### Docs/governance
- Release/runbook docs aligned with Plan G and telemetry gates.
- Task board/backlog/session log references recorded.
- Risk register references present for release artifacts.

### Tests/fixtures
- Tests map to touched modules.
- Fixtures sanitized and scoped.
- Missing negative tests flagged.

### Data/config
- StateTraceSettings.json + history files referenced safely.
- No .accdb files touched or staged.

## Evidence checklist
- `Invoke-Pester Modules/Tests` output recorded in session log.
- Pipeline + warm regression telemetry JSON paths recorded.
- Shared-cache/provider reason analyzer outputs captured.
- Verification harness output recorded if Plan G gates required.
- UI smoke/harness output recorded when UI is in scope.

## Review output format (per finding)
- Severity, risk flags, file/line ref, impact, recommendation, required tests.
