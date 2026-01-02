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
| ST-C-001 | Align diff prototype schema with Access baselines | Data | Done - 2025-12-31 | Added deterministic fixtures under `Data/Samples/DiffPrototype` plus template `Logs/Research/DiffPrototype/metrics.csv`; telemetry sample uses real CompareView fields and rollup validated via `Tools/Rollup-IngestionMetrics.ps1`. Results Summary updated in `docs/StateTrace_DiffModel_Prototype.md`. Evidence: Logs/Verification/DiffPrototypeFixturesTests-ST-C-001-20251231-175714.log; Logs/Verification/RollupIngestionMetrics-ST-C-001-20251231-175735.log; Logs/Reports/IngestionMetricsSummary-ST-C-001-20251231-175735.csv; Logs/Verification/AllChecks-ST-C-001-20251231-175741.log; Logs/Reports/DocSyncChecklist-ST-C-001-20251231-180235.json. |
| ST-C-002 | Instrument Compare view telemetry (`DiffUsageRate`) | UI + Telemetry | Done - 2025-12-31 | Compare view emits DiffUsageRate with guarded telemetry; tests cover executed/missing compare; Phase1 metrics updated. Evidence: Logs/Verification/CompareViewTelemetry-ST-C-002-20251231-140819.log; Logs/Verification/AllChecks-ST-C-002-20251231-140834.log; Logs/Reports/DocSyncChecklist-ST-C-002-20251231-141238.json. |
| ST-C-003 | Compare view telemetry: DiffCompareDurationMs | UI + Telemetry | Done - 2025-12-31 | Compare view emits DiffCompareDurationMs with guarded telemetry; tests cover executed/failed compare; Phase1 metrics updated. Evidence: Logs/Verification/CompareViewTelemetry-ST-C-003-20251231-143035.log; Logs/Verification/AllChecks-ST-C-003-20251231-143050.log; Logs/Reports/DocSyncChecklist-ST-C-003-20251231-143501.json. |
| ST-C-004 | Compare view telemetry: DiffCompareResultCounts | UI + Telemetry | Done - 2025-12-31 | Compare view emits DiffCompareResultCounts with guarded telemetry; counts cover added/removed/unchanged; tests cover executed/failed/missing compare; Phase1 metrics updated. Evidence: Logs/Verification/CompareViewTelemetry-ST-C-004-20251231-150642.log; Logs/Verification/AllChecks-ST-C-004-20251231-150655.log; Logs/Reports/DocSyncChecklist-ST-C-004-20251231-151042.json. |
| ST-C-005 | Compare telemetry smoke summary (offline validator) | UI + Telemetry | Done - 2025-12-31 | Offline smoke tool executes deterministic Compare path and summarizes DiffUsageRate/DiffCompareDurationMs/DiffCompareResultCounts; tests cover pass/fail/latest pointer; runbook updated. Evidence: Logs/Verification/CompareTelemetrySmokeTests-ST-C-005-20251231-165709.log; Logs/Verification/CompareTelemetrySmoke-ST-C-005-20251231-170033.log; Logs/Reports/CompareTelemetrySmoke/CompareTelemetrySmoke-ST-C-005-20251231-170033.json; Logs/Verification/CompareTelemetrySmoke-ST-C-005-determinism-20251231-165647.log; Logs/Verification/AllChecks-ST-C-005-20251231-165721.log; Logs/Reports/DocSyncChecklist-ST-C-005-20251231-170045.json. |
| ST-C-006 | Hook diff telemetry into rollups | Telemetry + UI | Done - 2025-12-31 | Rollup aligns to compare telemetry schema and emits DiffCompareDurationMs + DiffCompareResultCounts alongside DiffUsageRate/DriftDetectionTimeMinutes. Expected CSV fields: `DiffUsageRate` -> Count/Average/Total/SecondaryTotal; `DriftDetectionTimeMinutes` -> Count/Average/P95/Max/Total from DurationMinutes; `DiffCompareDurationMs` -> Count/Average/P95/Max/Total from DurationMs (Status=Executed); `DiffCompareResultCounts` -> Count/Average/P95/Max/Total with Notes carrying Added/Removed/Changed/Unchanged totals. Sample output: `Logs/Reports/IngestionMetricsSummary-ST-C-006-20260101-021631.csv` (`DiffUsageRate` Average=0.667 Total=2 SecondaryTotal=3; `DriftDetectionTimeMinutes` Average=10 Max=12.5 Total=20; `DiffCompareDurationMs` Average=150 Total=150; `DiffCompareResultCounts` Total=4 Added=1 Removed=1 Unchanged=2). Evidence: Logs/Verification/RollupIngestionMetricsTests-ST-C-006-20260101-021614.log; Logs/Verification/DiffPrototypeFixturesTests-ST-C-006-20260101-021621.log; Logs/Verification/RollupIngestionMetrics-ST-C-006-20260101-021631.log; Logs/Verification/AllChecks-ST-C-006-20260101-021647.log; Logs/Reports/DocSyncChecklist-ST-C-006-20260101-022013.json. |

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
