# Agent Kickoff Tasks

Use this list to start agent-driven development safely. Each task includes a clear outcome and acceptance checks.

> **Planning requirement:** Before starting any kickoff task, record a multi-step plan using `update_plan`, keep it active until the work is complete, and call out which `AGENTS.md` core ideas the steps reinforce (see `docs/Core_Ideas.md`).


## 1) Emit core telemetry in parser
- **Outcome:** `ParseDuration`, `RowsWritten`, `DatabaseWriteLatency` captured during ingestion.
- **Where:** Parser modules; log to `Logs/IngestionMetrics/<date>.json`.
- **Acceptance:** Events present and validated by a small replay run.

## 2) Seed tiny sanitized fixtures
- **Outcome:** Minimal log samples (???3 per vendor) in `Tests/Fixtures/` with a short README.
- **Acceptance:** Unit tests run locally using fixtures; repo growth minimal.

## 3) Nightly Access DB maintenance
- **Outcome:** Scheduled task invokes `Tools/Maintain-AccessDatabases.ps1 -DataRoot Data -IndexAudit` nightly.
- **Acceptance:** Maintenance log written to `Logs/Maintenance/` and any compacted DB shows size reduction when >100 MB.

## 4) Daily ingestion metric rollup
- **Outcome:** `Tools/Rollup-IngestionMetrics.ps1` produces daily CSV summaries.
- **Acceptance:** CSV includes totals and p95s for key metrics as defined in `docs/telemetry/Phase1_metrics.md`.

**Agent output format:** Follow `docs/AI_Agent_Terminal_Prompt.txt` (`PATCH SUMMARY`, `TEST RESULTS`, `TASKBOARD UPDATE`, `NEXT STEP`).

**Stop conditions:** If you encounter missing identity/RBAC, provider errors, or schema mismatches you cannot fix in one pass, mark the task **Blocked** and log details in `docs/agents/Agent_Session_Template.md`.



