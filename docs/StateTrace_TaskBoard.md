# StateTrace Task Board (Kanban)
This board tracks work items across their lifecycle from backlog to done. Each card carries a role tag (e.g. [Ingestion], [Docs]) and should link to the relevant deliverable (script, document or test). Respect the **WIP=2** limit for the "In Progress" column as described in the resource plan.

## Backlog
_No cards currently in this column._

## Ready
- **Trial reduced auto-scale ceilings post-batching** - [Ingestion] Deliverable: benchmark run with capped MaxWorkersPerSite/MaxActiveSites appended to Plan B snapshots (targeting WLLS Access commits).
- **Investigate Access commit latency after staging** - [Ingestion][Performance] Deliverable: test smaller batches or per-site serialization for WLLS hosts and document the before/after metrics in Plan B.
- **Suppress duplicate-only reruns after spool reset** - [Automation][Telemetry] Deliverable: ensure the pipeline skips duplicate ParseDuration sweeps once `Logs/Extracted` is cleared and add validation coverage.


## In Progress (WIP=2)
- **Identity option scorecard for acknowledgements** - [Security][Docs] Started 2025-10-01. Deliverable: scorecard recorded in `docs/StateTrace_Consolidated_Plans.md#plan-f-security-identity-online-mode`.
_No other cards currently in this column._

## Blocked
_No cards currently in this column._ Add a note explaining the dependency or issue for each blocked card.

## Done
- **Unified ParserPersistence command-set caching** - [Ingestion][Automation] Completed 2025-10-02. Deliverable: `Modules/ParserPersistenceModule.psm1` command reuse + persistence failure logging, `Modules/DeviceLogParserModule.psm1` catch instrumentation, refreshed tests (`Modules/Tests/ParserPersistenceModule.Tests.ps1`, `Modules/Tests/ParserWorker.Tests.ps1`), and Plan B updates.
- **Add spool reset helper for benchmark reruns** - [Automation][Docs] Completed 2025-10-03. Deliverable: -ResetExtractedLogs switch in Tools/Invoke-StateTracePipeline.ps1 plus README/Plan B updates.
- **Profile Access bulk insert timing** - [Ingestion][Automation] Completed 2025-10-03. Deliverable: InterfaceBulkInsertTiming telemetry in Modules/ParserPersistenceModule.psm1 and 2025-10-03 Plan B snapshot.
- **Trialed parser concurrency overrides with mock slice corpus** - [Ingestion][Docs] Completed 2025-10-01. Deliverable: metrics summary in `docs/StateTrace_Consolidated_Plans.md#plan-b-performance-ingestion-scale` (baseline vs. manual overrides, single-thread duplicate guard).
- **Documented concurrency override workflow** - [Docs][Automation] Completed 2025-10-01. Deliverable: quick-reference updates in `docs/README.md` and `AGENTS.md`, session log `docs/agents/sessions/2025-10-01_session-0002.md`.
- **Verified database creation flow** - [Data][Automation] Completed 2025-10-01. Deliverable: host normalisation retest captured in `docs/StateTrace_Consolidated_Plans.md#plan-b-performance-ingestion-scale` and session log `docs/agents/sessions/2025-10-01_session-0001.md`.
- **Stress-tested autoscaling parser settings** - [Ingestion] Completed 2025-09-30. Deliverable: stress-test snapshot recorded in `StateTrace_Consolidated_Plans.md#plan-b-performance-ingestion-scale` (24-thread profile; DatabaseWriteLatency p95 ~564 ms, above 200 ms target).
- **Summarised pipeline script and autoscaling workflow** - [Docs] Completed 2025-09-30. Deliverable: execution playbook recorded in `StateTrace_Consolidated_Plans.md#plan-b-performance-ingestion-scale`.
- **Fix integer parameter binding in persistence layer** - [Automation] Completed 2025-09-30. Deliverable: parameterised ParserPersistenceModule with passing `Invoke-Pester Modules/Tests` and `Tools/Invoke-StateTracePipeline.ps1 -SkipTests`.
- **Refactored parser persistence to parameterised ADODB commands** - [Automation] Completed 2025-09-30. Deliverable: updated persistence helpers and passing tests.
- **Added orchestration script Tools/Invoke-StateTracePipeline.ps1** - [Automation] Completed 2025-09-30. Validated via `powershell -File Tools/Invoke-StateTracePipeline.ps1 -SkipParsing -VerboseParsing`.
- **Applied plan status header to each active plan** - [Docs] Completed 2025-09-30. All planning documents now include status and last reviewed fields.

