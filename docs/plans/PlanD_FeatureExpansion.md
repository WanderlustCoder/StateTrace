# Plan D – Feature Expansion & Guided Troubleshooting

## Objective
Expand the UI feature set (guided workflows, SPAN visualisations, template helpers) while keeping the parser/UI contract stable. Plan D covers user-facing enhancements, view wiring, and help/guide content.

## Current status (2025-11)
- Incremental loading workflow (2025-10-14 spike) is live and documented in `docs/StateTrace_Operators_Runbook.md`; telemetry expectations (`PortBatchReady`, `InterfaceSyncTiming`, `DatabaseWriteLatency`) now live in the runbook plus `docs/CODEX_RUNBOOK.md`, but the plan still needs a standing validation task so operators capture evidence every time the workflow changes.
- Span View refresh (2025-11-07 investigation) added dispatcher-safe bindings, `Get-SpanViewSnapshot`, `Tools/Invoke-SpanViewSmokeTest.ps1`, `Tools/Test-SpanViewBinding.ps1`, and `Modules/Tests/SpanViewModule.Tests.ps1`, yet telemetry for SPAN usage has not been wired into `Logs/IngestionMetrics/*.json`.
- The UI smoke checklist and feature catalogue reference incremental loading + Span View at a high level, but guided troubleshooting templates/runbooks and template helper docs have not been updated since the plan split (`docs/notes/2025-10-03_feature-expansion.md` still lists "Not started" for those items, and `docs/StateTrace_Functions_Features.md` lacks the new helpers).
- `docs/CODEX_PLAN_AUTOMATION_MATRIX.md` now routes Plan D automation through this file; each UI initiative must tie back to the plan's telemetry gates before landing, and UI smoke runs must log the checklist output plus telemetry paths.
- Sanitized incident intake (Plan F / `docs/StateTrace_IncidentPostmortem_Intake.md`) is the dependency for guided troubleshooting; Plan D cannot publish new runbooks until the sanitized bundles exist and link back to Plan C diff validations.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-D-003 | Incremental loading telemetry sweep | UI + Ingestion | Ready | Run `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs`, exercise Interfaces view per `docs/StateTrace_Operators_Runbook.md`, capture `PortBatchReady` + `InterfaceSyncTiming` counts in `Logs/IngestionMetrics/<date>.json`, and append the evidence (counts, latency bands, UI observations) to this plan + task board. |
| ST-D-004 | Span view telemetry instrumentation | UI + Telemetry | Backlog | Add `TelemetryModule\Write-StTelemetryEvent` calls when `Get-SpanInfo`/`Get-SpanViewSnapshot` runs so SPAN usage emits row counts + host context; update `docs/telemetry/Phase1_metrics.md` and cover the new events via `Modules/Tests/SpanViewModule.Tests.ps1`. |
| ST-D-005 | Guided troubleshooting runbooks refresh | Docs / Guided Ops | Backlog | Use `docs/templates/runbook-template.md` to draft guided workflows for the first three sanitized incidents, link them in `docs/StateTrace_Operators_Runbook.md`, and ensure help content references the corresponding telemetry. |
| ST-D-006 | Template/helper catalog alignment | UI Docs | Backlog | Audit `docs/StateTrace_Functions_Features.md`, `docs/UI_Smoke_Checklist.md`, and help overlays to ensure every UI helper/template maps to an automation hook described in this plan; capture gaps and open task board rows as needed. |
| ST-D-007 | Span view telemetry + logging bridge | UI + Telemetry | Backlog | Instrument `Modules/SpanViewModule.psm1` / `Tools/Invoke-SpanViewSmokeTest.ps1` to emit `SpanViewUsage` events (host, VLAN count, RowsBound) into `Logs/IngestionMetrics/<date>.json`, update `docs/telemetry/Phase1_metrics.md`, and add Pester coverage to `Modules/Tests/SpanViewModule.Tests.ps1`. |
| ST-D-008 | UI smoke checklist automation artifact | Automation | Backlog | Extend `docs/UI_Smoke_Checklist.md` + `Tools/Invoke-AllChecks.ps1` to export a formatted report (`Logs/UI/UI-Smoke-<timestamp>.md`) capturing PortBatchReady counts, Span snapshot stats, template helper notes, and attach it to plan/task board updates for every major UI change. |
| ST-D-009 | Guided troubleshooting runbooks (sanitized incidents) | Docs / Guided Ops | Backlog | After Plan F delivers six sanitized incident bundles, build runbooks under `docs/runbooks/` using `docs/templates/runbook-template.md`, reference the sanitized paths + telemetry expectations, and link each runbook from this plan and `docs/StateTrace_Operators_Runbook.md`. |

## Recently delivered
| ID | Date | Summary | Evidence |
|----|------|---------|----------|
| ST-D-001 | 2025-11-12 | Refreshed the incremental-loading documentation: Operators runbook now includes explicit telemetry capture instructions (PortBatchReady, InterfaceSyncTiming, DatabaseWriteLatency) and Codex Runbook contains an "Incremental loading verification" entry. | `docs/StateTrace_Operators_Runbook.md`, `docs/CODEX_RUNBOOK.md`, task board row ST-D-001. |
| ST-D-002 | 2025-11-12 | Captured the SPAN-view smoke workflow (README + Codex Runbook now point to `Tools/Invoke-SpanViewSmokeTest.ps1` / `Get-SpanViewSnapshot`) so UI automation can validate the investigation changes without manual context. | `docs/README.md`, `docs/CODEX_RUNBOOK.md`, task board row ST-D-002. |

## Recent timeline (migrated highlights)
| Date (MT) | Summary | Evidence / Metrics | Source |
|-----------|---------|--------------------|--------|
| 2025-10-14 | Incremental loading workflow landed: Operators Runbook now documents streaming port batches, status strip states, and telemetry expectations (`PortBatchReady`, `InterfaceSyncTiming`). | `docs/StateTrace_Operators_Runbook.md` details commands, UI cues (`Loading ports`, progress bar), and expected latency bands. | docs/StateTrace_Operators_Runbook.md |
| 2025-11-07 | Span View investigation refreshed the module, added dispatcher-safe bindings, status labels, `Get-SpanViewSnapshot`, and a headless smoke test harness. | `Tools/Invoke-SpanViewSmokeTest.ps1`, `Modules/Tests/SpanViewModule.Tests.ps1`, and updated UI logging captured in span debug logs. | docs/notes/2025-11-07_span-view-investigation.md |

## Automation hooks
- `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` to seed incremental-loading telemetry before UI validation (per `docs/CODEX_RUNBOOK.md`).
- `pwsh -STA -File Tools\Invoke-SpanViewSmokeTest.ps1 -Hostname <host> -PassThru` to perform headless SPAN verification; attach the summary object and `Logs/Debug/SpanDiag.log` excerpt to plan/task updates.
- `pwsh -STA -File Tools\Test-SpanViewBinding.ps1` (or `Tools\Invoke-AllChecks.ps1`) after UI changes to capture dispatcher binding regressions; upload the log snippet referenced in `docs/notes/2025-11-07_span-view-investigation.md`.
- `pwsh -NoLogo -File Main\MainWindow.ps1` followed by the checklist in `docs/UI_Smoke_Checklist.md` to exercise Interfaces, SPAN, Templates, and guided workflows; capture any regressions and telemetry paths.
- `pwsh -NoLogo -File Tools\Invoke-AllChecks.ps1` (runs Pester + Span smoke harness) whenever Span view or guided workflow code changes to keep UI regression coverage documented.
- When authoring guided troubleshooting runbooks, pull sanitized incidents via Plan F (`Tools\Sanitize-PostmortemLogs.ps1`, `docs/StateTrace_IncidentPostmortem_Intake.md`), then document the telemetry commands in the runbook template before publishing.

## Telemetry gates
- Incremental loading: `PortBatchReady` emits one event per processed device (37 for BOYO/WLLS) and `InterfaceSyncTiming`/`DatabaseWriteLatency` stay within Plan A/B thresholds (see `docs/telemetry/Automation_Gates.md`); log counts + samples in the plan entry.
- SPAN view: `Get-SpanViewSnapshot` (or future telemetry event) must report `RowsBound > 0` for the requested host/site and log timestamps to `Logs/Debug/SpanDiag.log`; once telemetry events exist, add them to `docs/telemetry/Phase1_metrics.md` and enforce via this plan.
- Guided workflows/templates: each published workflow must include a verification command (per runbook template) and reference the telemetry it expects (e.g., `GuidedWorkflowCompletionRate`, once defined) before it ships.

## References & history
- Operator instructions: `docs/StateTrace_Operators_Runbook.md`.
- Feature catalogue: `docs/StateTrace_Functions_Features.md`.
- UI automation matrix: `docs/CODEX_PLAN_AUTOMATION_MATRIX.md`, `docs/CODEX_RUNBOOK.md`, `docs/UI_Smoke_Checklist.md`.
- Pending design work & session notes: `docs/notes/2025-11-07_span-view-investigation.md`, `docs/notes/2025-10-03_feature-expansion.md`.
- Span tooling references: `Tools/Invoke-SpanViewSmokeTest.ps1`, `Tools/Test-SpanViewBinding.ps1`, `Modules/Tests/SpanViewModule.Tests.ps1`.
- Sanitized incident intake dependency: `docs/StateTrace_IncidentPostmortem_Intake.md`, `docs/agents/Agent_Kickoff_Tasks.md`, Plan F backlog.
