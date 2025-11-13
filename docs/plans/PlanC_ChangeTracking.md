# Plan C – Change Tracking & Diff Experience

## Objective
Deliver reliable change tracking for device configs and interfaces, expose the diff experience in the UI, and keep the prototype data structures described in `docs/StateTrace_DiffModel_Prototype.md` aligned with production ingestion.

## Current status (2025-11)
- The diff model prototype runbook (`docs/StateTrace_DiffModel_Prototype.md`) defines the `DiffRun` / `DiffObject` / `DiffChange` tables plus metrics logging under `Logs/Research/DiffPrototype/metrics.csv`; Plan C owns validating those steps against sanitized Access baselines (seeded via `docs/StateTrace_IncidentPostmortem_Intake.md` / Plan F) before the UI exposes the flow.
- Feature-expansion notes (`docs/notes/2025-10-03_feature-expansion.md`) locked in the delivery order: prototype the schema, record metrics, wire the diff explorer/anomaly workflows, and only then publish guided runbooks. Any new backlog item must match that sequencing and reference the sanitized incidents powering it.
- `Modules/CompareViewModule.psm1` currently drives the diff/compare experience without emitting telemetry, so `DiffUsageRate` / `DriftDetectionTime` never leave the UI. Instrumentation + smoke tests must land before release, and Plan E needs the emitted events to appear in rollups.
- Telemetry gates in `docs/telemetry/Automation_Gates.md` reference `DiffUsageRate` and `DriftDetectionTime`, but there is no automation tying `Logs/IngestionMetrics/*.json` to those thresholds yet. Coordination with Plan E (rollup work + telemetry bundles) is required to land the verification workflow.
- Plan D will depend on Plan C’s sanitized incident coverage when drafting guided troubleshooting; Plan C keeps the schema/telemetry in sync while Plan D handles UX/runbooks.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-C-001 | Align diff prototype schema with Access baselines | Data | Ready | Follow the steps in `docs/StateTrace_DiffModel_Prototype.md` (schema draft → parser spike → persistence test) against the latest `.accdb` copies, log results to `Logs/Research/DiffPrototype/metrics.csv`, and record the viability call in the runbook + plan. |
| ST-C-002 | Instrument Compare view telemetry (`DiffUsageRate`) | UI + Telemetry | Ready | Add `TelemetryModule\Write-StTelemetryEvent` calls inside `Modules/CompareViewModule.psm1` (for example, `Show-CurrentComparison`) so UI usage emits `DiffUsageRate` events with host/session context, persist them to `Logs/IngestionMetrics/<date>.json`, and cover the path via `Modules/Tests/CompareViewModule.Tests.ps1`. |
| ST-C-003 | Drift detection benchmark + gate wiring | Data + Telemetry | Backlog | Run `Tools\Analyze-WarmRunDiffHotspots.ps1 -TelemetryPath Logs\IngestionMetrics\<warm>.json -Top 20` after each warm regression, capture `DriftDetectionTime` p50/p95, and propagate the numbers into `docs/telemetry/Automation_Gates.md` plus `docs/StateTrace_Consolidated_Plans.md`. |
| ST-C-004 | Diff UX smoke + documentation alignment | UI / Docs | Backlog | Extend `docs/UI_Smoke_Checklist.md` with the compare/diff workflow, summarize the UX in `docs/StateTrace_Functions_Features.md`, and ensure operator-facing instructions capture the telemetry that should fire when the diff explorer is used. |
| ST-C-005 | Sanitize + ingest diff fixtures | Data / Docs | Backlog | Partner with Plan F / incident intake to pull six sanitized incidents into `Data/Postmortems/<IncidentId>/Sanitized`, document them in `docs/StateTrace_IncidentPostmortem_Intake.md`, and rerun the diff prototype against those fixtures (record metrics + findings in the plan). |
| ST-C-006 | Hook diff telemetry into rollups | Telemetry + UI | Backlog | Once ST-C-002 emits `DiffUsageRate`/`DriftDetectionTime`, update `Tools/Rollup-IngestionMetrics.ps1` (Plan E) to surface those columns; document the expected CSV fields and sample output inside this plan/task board row. |

## Recent timeline (migrated highlights)
| Date (MT) | Summary | Evidence / Metrics | Source |
|-----------|---------|--------------------|--------|
| 2025-10-03 | Feature expansion planning session set the sequencing: build the diff data model prototype, log metrics under `Logs/Research/DiffPrototype/metrics.csv`, and only then wire the UI diff explorer / anomaly workflows. | Backlog items captured for diff prototype, postmortem intake, and telemetry dependencies. | docs/notes/2025-10-03_feature-expansion.md |
| 2025-10-05 | Published the **Diff Model Prototype Runbook** describing schema drafts, parser spikes, Access persistence tests, and reporting requirements so diff experiments have consistent outputs. | Runbook spells out schema/table structure, hash strategy, metrics headers, and sign-off checklist. | docs/StateTrace_DiffModel_Prototype.md |

## Automation hooks
- `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -RunWarmRunRegression` to seed diff-ready telemetry before UI work (see `docs/CODEX_RUNBOOK.md`).
- `pwsh Tools\Analyze-WarmRunDiffHotspots.ps1 -TelemetryPath Logs\IngestionMetrics\<warm>.json -Top 20 [-OutputPath Logs\Research/DiffHotspots.csv]` to calculate `DriftDetectionTime` deltas and attach the output table to the plan/task-board entries.
- `pwsh -NoLogo -Command "Invoke-Pester Modules/Tests/CompareViewModule.Tests.ps1"` whenever Compare view telemetry changes so parser/UI contracts stay covered.
- `pwsh Tools\Sanitize-PostmortemLogs.ps1 -SourcePath <raw> -DestinationPath Data\Postmortems\<IncidentId>\Sanitized -ReportPath Logs\Sanitization\<IncidentId>.json` followed by the prototype steps when new incident fixtures are introduced (reference Plan F intake doc).
- Follow `docs/UI_Smoke_Checklist.md` (launch `Main/MainWindow.ps1`, exercise Compare view) and paste the observations plus telemetry paths into this plan.

## Telemetry gates
- `DiffUsageRate` rolling weekly ratio >= 70% once the feature is live (`docs/telemetry/Phase1_metrics.md`).
- `DriftDetectionTime` p95 trending downward release-over-release; include analyzer output in the task board update when collecting data.
- Parser diff overhead stays <20% versus the baseline cold run, mirroring the sign-off checklist inside `docs/StateTrace_DiffModel_Prototype.md`.

## References & history
- Prototype and architecture notes: `docs/StateTrace_DiffModel_Prototype.md`.
- Delivery sequencing + backlog context: `docs/notes/2025-10-03_feature-expansion.md`.
- UI implementation: `Modules/CompareViewModule.psm1`, `Modules/Tests/CompareViewModule.Tests.ps1`.
- Operational playbooks: `docs/UI_Smoke_Checklist.md`, `docs/StateTrace_Functions_Features.md`, `docs/CODEX_RUNBOOK.md`.
- Drift analyzer workflow: `Tools/Analyze-WarmRunDiffHotspots.ps1`.
- Sanitized incident intake / fixture source: `docs/StateTrace_IncidentPostmortem_Intake.md`, Plan F backlog items.
