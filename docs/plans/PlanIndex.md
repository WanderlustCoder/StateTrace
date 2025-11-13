# StateTrace Plan Index

The seven active StateTrace plans now live in discrete files so automation agents can reference a small, structured surface instead of parsing the historical log inside `docs/StateTrace_Consolidated_Plans.md`. Treat the per-plan pages as the **source of truth for objectives, owners, active work, and telemetry gates**; append narrative updates or long-form investigation notes to the historical log only after you have updated the plan page.

| Plan | Focus | Primary owner(s) | Key telemetry | Plan file |
|------|-------|------------------|---------------|-----------|
| A | Routing reliability & dispatcher health | Ingestion / Routing | `InterfacePortQueueMetrics`, `InterfaceSyncTiming` | `docs/plans/PlanA_RoutingReliability.md` |
| B | Performance & ingestion scale | Ingestion / Parser Worker | `ParseDuration`, `DatabaseWriteLatency`, `InterfaceSiteCacheMetrics` | `docs/plans/PlanB_Performance.md` |
| C | Change tracking & diff model | UI / Data | `DiffUsageRate`, diff snapshot health | `docs/plans/PlanC_ChangeTracking.md` |
| D | Feature expansion & guided troubleshooting | UI / Guided Ops | Feature telemetry, SPAN helpers | `docs/plans/PlanD_FeatureExpansion.md` |
| E | Telemetry, launch metrics, and rollups | Telemetry / Ops | `Phase1` metrics dictionary plus rollup CSVs | `docs/plans/PlanE_Telemetry.md` |
| F | Security, identity, & online mode | Security / Platform | Redaction tooling, RBAC switches, NetOps logs | `docs/plans/PlanF_SecurityIdentity.md` |
| G | Release & governance | Release / PMO | Release checklist completion, warm-run verification | `docs/plans/PlanG_ReleaseGovernance.md` |

## Status snapshot (2025-11)
- **Plan A** – Routing instrumentation restored; dispatcher harness + verification scripts must log `InterfaceSyncTiming` counts before merges. Outstanding tasks: queue-delay alert, dispatcher harness evidence automation.
- **Plan B** – Shared-cache diagnostics highlight `SnapshotImported=0` for WLLS/BOYO; keyed existing-row cache prototype + warm diff hotspot automation remain in progress, and `Tools\Publish-TelemetryBundle.ps1` now packages cold/warm telemetry for release evidence (ST-B-008/009).
- **Plan C** – Diff prototype validation and Compare view telemetry instrumentation are queued; drift analyzer output must accompany warm-run reports.
- **Plan D** – Incremental-loading telemetry sweep, SPAN telemetry wiring, guided troubleshooting runbooks, and UI smoke artifact automation are the next focus items.
- **Plan E** – Daily rollup scheduling, Phase 1 dictionary refresh, and telemetry gate enforcement harness pending; telemetry bundles (via `Tools\Publish-TelemetryBundle.ps1`/`Tools\New-TelemetryBundle.ps1`) must include shared-cache analyzer output before Plan G sign-off.
- **Plan F** – NetOps logging workflow, sanitizer automation, and evidence templates need implementation before any online-mode or sanitized-fixture work proceeds.
- **Plan G** – Release checklist needs explicit shared-cache snapshot policy plus scheduled verification summaries/telemetry bundles (`Tools\Publish-TelemetryBundle.ps1`) archived with each candidate build alongside doc-sync evidence.

## How to use the plans
1. **Before editing code** - open the relevant plan file, confirm the objective still matches your intent, and add your upcoming work to the "Active work" table (include the task-board or Codex backlog ID).
2. **While working** - capture telemetry and command output under the "Automation hooks" section of the same plan file so future agents can reproduce your steps.
3. **After finishing** - move the row to "Recently delivered" (if provided), link the doc/test diffs, and mirror the summary to the task board (`docs/StateTrace_TaskBoard.md` / `docs/taskboard/TaskBoard.csv`).
4. **When adding a new initiative** - clone one of the plan templates in this folder, update the index above, and add a pointer at the top of `docs/StateTrace_Consolidated_Plans.md`.

## Cross-references & telemetry hygiene
- Pair this index with `docs/CODEX_PLAN_AUTOMATION_MATRIX.md` and the per-plan "Automation hooks" tables so every task cites the exact scripts/tests to run.
- Always log telemetry artifacts (e.g., `Logs/IngestionMetrics/<date>.json`, rollup CSVs, shared-cache diagnostics, NetOps JSON) and mention the paths in plan/task-board updates per `docs/CODEX_DOC_SYNC_PLAYBOOK.md`.
- When a plan references sanitized incidents, link the matching entry in `docs/StateTrace_IncidentPostmortem_Intake.md` and the relevant session log under `docs/agents/sessions/`.
- Historical narrative (per-minute notes, rich telemetry dumps) should continue to live in `docs/StateTrace_Consolidated_Plans.md`. Link back from each plan page so readers can dive deeper when necessary.
