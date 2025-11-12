# Plan D – Feature Expansion & Guided Troubleshooting

## Objective
Expand the UI feature set (guided workflows, SPAN visualisations, template helpers) while keeping the parser/UI contract stable. Plan D covers user-facing enhancements, view wiring, and help/guide content.

## Current status (2025-11)
- Incremental loading workflow (2025-10-14 spike) is live; operators monitor progress via the status strip described in `docs/StateTrace_Operators_Runbook.md`.
- Guided SPAN investigations under review (`docs/notes/2025-11-07_span-view-investigation.md`).
- Help content and templates exist but need alignment with the new plan structure.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| _None_ | – | – | – | Add entries here as new UI initiatives surface. |

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
- Launch `Main/MainWindow.ps1`, exercise Interfaces, SPAN, Templates tabs, and record any regressions.
- Use `Tools/Invoke-StateTracePipeline.ps1` prior to UI validation so the cached data is fresh.

## Telemetry gates
- For incremental loading, ensure `PortBatchReady` emits one event per device and `DatabaseWriteLatency` stays within Plan B thresholds.
- For SPAN view, log relevant metrics (to be defined) into `Logs/IngestionMetrics/` and update `docs/telemetry/Automation_Gates.md` when available.

## References & history
- Operator instructions: `docs/StateTrace_Operators_Runbook.md`.
- Feature catalogue: `docs/StateTrace_Functions_Features.md`.
- Pending design work: `docs/notes/2025-11-07_span-view-investigation.md`.
