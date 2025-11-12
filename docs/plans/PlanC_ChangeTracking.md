# Plan C – Change Tracking & Diff Experience

## Objective
Deliver reliable change tracking for device configs and interfaces, expose the diff experience in the UI, and keep the prototype data structures described in `docs/StateTrace_DiffModel_Prototype.md` aligned with production ingestion.

## Current status (2025-11)
- Diff model prototype exists but needs continued validation against live Access databases.
- UI telemetry for `DiffUsageRate` is defined in `docs/telemetry/Phase1_metrics.md`, but ingestion-side enforcement remains pending.
- No open incidents, but the codified backlog includes “Diff explorer instrumentation refresh” (see `docs/CODEX_BACKLOG.md`).

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-C-001 | Sync diff prototype schema with Access databases | Data | Backlog | Compare `docs/StateTrace_DiffModel_Prototype.md` with current `.accdb` schema and emit migration notes. |
| ST-C-002 | Capture DiffUsageRate events from UI | UI/Telemetry | Backlog | Instrument `Views/DiffViewModule.psm1` and log to `Logs/IngestionMetrics/` for rollups. |

## Recent timeline (migrated highlights)
| Date (MT) | Summary | Evidence / Metrics | Source |
|-----------|---------|--------------------|--------|
| 2025-10-03 | Feature expansion planning session set the sequencing: build the diff data model prototype, log metrics under `Logs/Research/DiffPrototype/metrics.csv`, and only then wire the UI diff explorer / anomaly workflows. | Backlog items captured for diff prototype, postmortem intake, and telemetry dependencies. | docs/notes/2025-10-03_feature-expansion.md |
| 2025-10-05 | Published the **Diff Model Prototype Runbook** describing schema drafts, parser spikes, Access persistence tests, and reporting requirements so diff experiments have consistent outputs. | Runbook spells out schema/table structure, hash strategy, metrics headers, and sign-off checklist. | docs/StateTrace_DiffModel_Prototype.md |

## Automation hooks
- Run UI smoke tests: launch `Main/MainWindow.ps1`, open the diff explorer, and confirm telemetry emission via local log.
- Update `docs/StateTrace_Functions_Features.md` and `docs/CODEX_RUNBOOK.md` with any new entry points or scripts.

## Telemetry gates
- `DiffUsageRate` weekly ratio ≥70% during pilot (per `docs/telemetry/Phase1_metrics.md`).
- `DriftDetectionTime` p95 trending downward vs. baseline once change tracking ships.

## References & history
- Prototype and architecture notes: `docs/StateTrace_DiffModel_Prototype.md`.
- Product catalogue cross-links: `docs/StateTrace_Functions_Features.md`.
