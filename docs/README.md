# StateTrace Documentation Index

This index provides a high-level map of the active planning and process documents for the StateTrace project. Use it as your starting point when navigating the repository. Each link below points to a Markdown file under docs/ and summarises its purpose.

## Planning & Strategy

- **[Plan Index (Plans A–G)](plans/PlanIndex.md)** - authoritative objectives, owners, and telemetry hooks for each pillar.
- **[StateTrace Consolidated Plans](StateTrace_Consolidated_Plans.md)** - archival log of investigation notes; update after recording the structured summary under `docs/plans/`.
- **[Diff Model Prototype](StateTrace_DiffModel_Prototype.md)** - proof-of-concept for change tracking data structures and access patterns.
- **[Feature and Functions Catalogue](StateTrace_Functions_Features.md)** - catalogue of current and proposed UI and workflow capabilities.
- **[Routing Data Architecture](StateTrace_Routing_DataArchitecture.md)** - schemas, diagrams, and integration points for routing telemetry.

## Process & Operations

- **[Task Board](StateTrace_TaskBoard.md)** - Kanban board with WIP limits and deliverable links.
- **[Risk Register](RiskRegister.md)** - centralises the top risks with triggers, mitigations, owners, and review cadences.
- **[Quarterly Roadmap](StateTrace_Quarterly_Roadmap.md)** - milestone dates, owners, scope bullets, and exit criteria.
- **[Release Guide](Release.md)** - packaging and versioning instructions and smoke test requirements.
- **[Security Guidelines](Security.md)** - data-handling rules, redaction policy, and retention expectations.
- **[Architecture Decision Records](adr/)** - authoritative decisions (data store, UI platform, compiled components).
- **[UI Smoke Checklist](UI_Smoke_Checklist.md)** - step-by-step verification of the WPF shell (Summary, Interfaces, SPAN, Templates, Alerts, Compare, Help).
- **[Schedule Daily Rollup Runbook](runbooks/Schedule_Daily_Rollup.md)** - instructions for registering the Windows Task Scheduler job that runs Tools/Invoke-DailyRollupScheduled.ps1 (wrapper over Tools/Invoke-DailyMetricRollup.ps1 for Plan E ST-E-003).
- **[Schedule Verification Runbook](runbooks/Schedule_Verification.md)** - instructions for registering the Windows Task Scheduler job that runs Tools/Invoke-StateTraceScheduledVerification.ps1 and emits `Logs/Verification/VerificationSummary-*.json`.
- **[Telemetry Bundle Verification Runbook](runbooks/Telemetry_Bundle_Verification.md)** - step-by-step checklist for validating `Logs/TelemetryBundles/<bundle>/` contents (README hashes, required artifacts, readiness scripts) before updating Plans E/G and release notes.
- **[Incremental Loading Performance Runbook](runbooks/Incremental_Loading_Performance.md)** - captures the Interfaces view telemetry sweep (PortBatchReady + InterfaceSyncTiming + analyzer report) so Plan D can baseline UI throughput whenever changes ship.

## Using AI Agents

- **[AI Agent Operations Guide](StateTrace_AI_Agent_Guide.md)** - the canonical playbook for agents (what they can and cannot do, safe implementation checklist, validation steps).
- **AGENT_INSTRUCTIONS.txt** - short, step-by-step operating loop for agents running in limited terminal sessions.
- **AI_Agent_Terminal_Prompt.txt** - the exact system prompt to load for terminal agents (command budget, guardrails, output format).
- **[Agent PR Checklist](agents/Agent_PR_Checklist.md)** - what every agent-generated PR must include.
- **[Agent Session Template](agents/Agent_Session_Template.md)** - a lightweight template for logging what the agent did and why.
- **[Core Ideas](Core_Ideas.md)** - quick reference to the project pillars mirrored from `AGENTS.md` for use in plans and reviews.
- **[Codex Autonomy Plan](CODEX_AUTONOMY_PLAN.md)** - defines autonomy levels, guardrails, and reporting requirements.
- **[Codex Operations Guide](CODEX_OPERATIONS_GUIDE.md)** - end-to-end instruction set for Codex sessions (select work, plan, execute, validate, document).
- **[Codex Session Checklist](CODEX_SESSION_CHECKLIST.md)** - checkbox flow covering pre-flight, execution, validation, and handoff steps.
- **[Codex Quick Start](CODEX_QUICK_START.md)** - three-step TL;DR (pick & plan, execute & validate, document & hand off).
- **[Codex Instruction Stack](CODEX_INSTRUCTION_STACK.md)** - shows which doc to use at every stage (guardrails, planning, execution, wrap-up).
- **[Codex Plan Automation Matrix](CODEX_PLAN_AUTOMATION_MATRIX.md)** - plan-by-plan cheat sheet for the scripts, telemetry, and doc updates required to finish work autonomously.
- **[Codex Documentation Sync Playbook](CODEX_DOC_SYNC_PLAYBOOK.md)** - step-by-step instructions for updating plan files, the Task Board + CSV, backlog, and session logs before closing a task.
- **[Codex Runbook](CODEX_RUNBOOK.md)** - command/validation matrix for automation tasks.
- **[Codex Backlog](CODEX_BACKLOG.md)** - automation-ready queue aligned with the task board.

## Historical & Completed Work

Completed plans are moved to docs/completed/ with a completion summary and date. If other documents still reference them, leave a short stub pointing to the archive.

## Execution & Overrides Quick Reference

- Run `powershell -File Tools/Invoke-StateTracePipeline.ps1 -VerboseParsing` for a full ingestion pass; use `-SkipTests` when the Pester suite already ran.
- Trial manual ceilings by passing `-ThreadCeilingOverride`, `-MaxWorkersPerSiteOverride`, `-MaxActiveSitesOverride`, `-MaxConsecutiveSiteLaunchesOverride`, `-JobsPerThreadOverride`, or `-MinRunspacesOverride`; these temporarily supersede the zero-valued hints in `Data/StateTraceSettings.json`.
- Each run logs telemetry (`ParseDuration`, `DatabaseWriteLatency`, `ConcurrencyProfileResolved`, etc.) to `Logs/IngestionMetrics/<date>.json`; review these files when capturing metrics for plan updates.
- Generate daily metric rollups with `Tools/Rollup-IngestionMetrics.ps1 -MetricsDirectory Logs/IngestionMetrics -OutputPath Logs/IngestionMetrics/IngestionMetricsSummary.csv`; add `-IncludePerSite`/`-IncludeSiteCache` for detailed slices, `-MetricFile <path>` for ad-hoc summaries, or `-MetricFileNameFilter '2025-11-*.json' -Latest 3` to filter the dataset without parsing the full archive.
- Package release evidence with `Tools/New-TelemetryBundle.ps1 -BundleName <name> -ColdTelemetryPath Logs\IngestionMetrics\<date>.json -WarmTelemetryPath Logs\IngestionMetrics\WarmRunTelemetry-*.json -AnalyzerPath Logs\IngestionMetrics\SharedCacheAnalysis-*.json -RollupPath Logs\IngestionMetrics\IngestionMetricsSummary-*.csv -DocSyncPath docs\agents\sessions\<date>_session-XXXX.md`; the script copies all artifacts into `Logs/TelemetryBundles/<name>/[Area]`, generates a manifest + README, and should be referenced from Plans B/E/G and the Task Board entry linked to the run.
- Remove the override parameters (or set them to `0`) once experiments finish so autoscaling resumes.
- Package release evidence automatically: `Tools/Publish-TelemetryBundle.ps1 -BundleName Release-20251113 -PlanReferences PlanB,PlanE,PlanG -TaskBoardIds ST-B-008,ST-E-007,ST-G-007 -Notes "Cold+Warm telemetry + analyzer outputs"` discovers the latest cold/warm logs, shared-cache analyzers, rollup CSV, and session log before invoking `Tools/New-TelemetryBundle.ps1`. Reference the resulting `Logs/TelemetryBundles/<bundle>/` path inside the relevant plans and Task Board rows.
- Adjust bulk staging by setting `ParserSettings.InterfaceBulkChunkSize` in `Data/StateTraceSettings.json`; ParserWorker now pushes the value to ParserPersistenceModule (default 24, use `0` to stage full batches).
- `Tools/Invoke-StateTracePipeline.ps1` now auto-imports and re-exports shared cache snapshots under `Logs/SharedCacheSnapshot/` so cold passes reuse the prior host dictionaries; override the directory with `-SharedCacheSnapshotDirectory` or disable the behaviour with `-DisableSharedCacheSnapshot`.
- Pass `-ShowSharedCacheSummary` when running the pipeline to print a quick table of cached sites/rows (uses `Tools/Inspect-SharedCacheSnapshot.ps1` under the hood and writes `SharedCacheSnapshot-*-summary.json` plus `SharedCacheSnapshot-latest-summary.json` alongside the snapshots).
- `Tools/Invoke-StateTraceVerification.ps1` enforces warm-run regression thresholds and now evaluates shared-cache coverage (minimum site/host/row counts and required site list) before emitting its pass/fail result; adjust the checks with `-SharedCacheMinimumSiteCount`, `-SharedCacheMinimumHostCount`, `-SharedCacheMinimumTotalRowCount`, or `-SharedCacheRequiredSites`, and skip with `-SkipSharedCacheSummaryEvaluation` when debugging.
- `Tools/Invoke-SharedCacheWarmup.ps1` primes the shared cache by calling the pipeline with `-ShowSharedCacheSummary`, then validates coverage using `Test-SharedCacheSummaryCoverage`; pass `-RequiredSites`, `-MinimumSiteCount`, `-MinimumHostCount`, or `-MinimumTotalRowCount` to enforce policy before pushing snapshots to verification. Coverage results are written to `SharedCacheCoverage-latest.json` (and archived by the scheduled verification harness).
- Inspect cached snapshot contents at any time with `Tools/Inspect-SharedCacheSnapshot.ps1` (use `-ShowPorts` for per-host detail or `-All` to review historical exports).
- Generate synthetic logs for missing hosts with `Tools/Expand-MockLogCorpus.ps1`; point `-SourceMetricsPath` at an existing telemetry file (for example `Logs\IngestionMetrics\2025-11-06.json`) and pass `-Force` to overwrite any prior synthetic log. The script clones template logs per site prefix so you can quickly seed WLLS/BOYO coverage for shared-cache warmups without waiting on new captures.
- Use `Tools/Analyze-WarmRunDiffHotspots.ps1 -TelemetryPath Logs\IngestionMetrics\<warm run>.json -Top 20` to rank hosts by `DiffComparisonDurationMs`, including their providers, reasons, and `LoadExistingRowSetCount`; add `-OutputPath` to dump the table for incident reports.
- `pwsh Tools/Invoke-DailyMetricRollup.ps1 -Days 1 -IncludePerSite -IncludeSiteCache` wraps the rollup script and writes a timestamped `IngestionMetricsSummary-<timestamp>.csv` so daily telemetry snapshots can be generated (and scheduled) without manually composing filters.
- `pwsh -STA -File Tools/Invoke-SpanViewSmokeTest.ps1 -Hostname <host> -PassThru` drives the SPAN view headlessly, runs `Get-SpanInfo`, and returns a snapshot (rows, VLANs, samples) so you can validate the UI even when the main window is unavailable; pair it with `Get-SpanViewSnapshot` for on-screen checks.
- Telemetry success criteria per plan now live in **[telemetry/Automation_Gates.md](telemetry/Automation_Gates.md)**; update the relevant plan/task whenever those thresholds change.




