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

## How to use the plans
1. **Before editing code** – open the relevant plan file, confirm the objective still matches your intent, and add your upcoming work to the “Active work” table (include the task-board or Codex backlog ID).
2. **While working** – capture telemetry and command output under the “Automation hooks” section of the same plan file so future agents can reproduce your steps.
3. **After finishing** – move the row to “Recently delivered” (if provided), link the doc/test diffs, and mirror the summary to the task board (`docs/StateTrace_TaskBoard.md` / `docs/taskboard/TaskBoard.csv`).
4. **When adding a new initiative** – clone one of the plan templates in this folder, update the index above, and add a pointer at the top of `docs/StateTrace_Consolidated_Plans.md`.

Historical narrative (per-minute notes, rich telemetry dumps) should continue to live in `docs/StateTrace_Consolidated_Plans.md`. Link back from each plan page so readers can dive deeper when necessary.
