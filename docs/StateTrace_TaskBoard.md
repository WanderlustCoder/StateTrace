# StateTrace Task Board (Kanban)
This board tracks work items across their lifecycle from backlog to done. Each card carries a role tag (e.g. [Ingestion], [Docs]) and should link to the relevant deliverable (script, document or test). Respect the **WIP=2** limit for the "In Progress" column as described in the resource plan.

## Backlog
_No cards currently in this column._

## Ready
- **Trial reduced auto-scale ceilings post-batching** - [Ingestion] Deliverable: benchmark run with capped MaxWorkersPerSite/MaxActiveSites appended to Plan B snapshots (targeting WLLS Access commits).


## In Progress (WIP=2)
- **Investigate Access commit latency after staging** - [Ingestion][Performance] Started 2025-10-03. Deliverable: chunked staging (24-row) benchmarks captured in Plan B (2025-10-03 and 2025-10-05 snapshots); KPI still unmet with `DatabaseWriteLatency` p95 at 2.16 s (>0.2 s target).
  - 2025-10-04: ParserPersistenceModule now detects Jet vs. ACE provider failures, emits timing telemetry with stage errors, and ParserWorker surfaces `InterfaceBulkChunkSize` overrides.
  - 2025-10-05: Reset ingestion history and reran the BOYO/WLLS corpus; `DatabaseWriteLatency` p95 improved to 2.16 s (max 2.43 s) versus 4.08 s before chunking. `ParseDuration` p95 settled at 3.14 s with WLLS p95 2.78 s. `StageError=ParameterCreationFailed` still fires on 31 hosts via `LiteralFallback`; next focus is the Ready card for reduced ceilings.
  - 2025-10-05 13:24 MT: Trialled overrides (`MaxWorkersPerSiteOverride=2`, `MaxActiveSitesOverride=2`); `DatabaseWriteLatency` p95 climbed to 2.61 s (max 2.77 s) and average 1.02 s, so overrides were reverted after the run. Next up: fix ACE parameter creation failures or test smaller chunks.
  - 2025-10-05 19:10 MT: ParserPersistence now records `StageErrorDetail` with provider info and the Jet parameters that fail to bind, giving us the data needed to target ACE-compatible parameter types.
  - 2025-10-06 16:45 MT: Re-ran mock BOYO/WLLS pipeline after `AuthDefaultVLAN` string conversion; no `InterfacePersistenceFailure` events logged and `InterfaceBulkInsertTiming` omits StageError. Latency still ~3.1 s on WLLS (tuning tracked separately).
  - 2025-10-07: Applied default long-text parameter sizing for ACE/Jet so chunk staging stays parameterized; tests cover the `Add-AdodbParameter` sizing logic. Live Access verification now waits on provider fallback refinements.
## Blocked
_No cards currently in this column._ Add a note explaining the dependency or issue for each blocked card.

## Done
- **Suppress duplicate-only reruns after spool reset** - [Automation][Telemetry] Completed 2025-10-06. Deliverable: DeviceLogParser duplicate guard avoids extra Access opens, Pester coverage ensures duplicates skip `ParseDuration`, and the 2025-10-06 20:35Z rerun logged only `SkippedDuplicate` telemetry across two verification passes.
- **Identity option scorecard for acknowledgements** - [Security][Docs] Completed 2025-10-04. Deliverable: weighted scorecard and recommendation in `docs/StateTrace_Acknowledgement_Identity_Options.md` plus Plan F updates in `docs/StateTrace_Consolidated_Plans.md`.
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
