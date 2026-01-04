# Plan M - Data Quality & Telemetry Hygiene

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Ensure all telemetry, rollups, and evidence bundles are clean, validated, and reproducible: no malformed JSON, no mixed debug slices, consistent hashing/README coverage, and redaction where required.

## Current status (2025-12)
- Analyzer warnings still occur when debug/worker slices land in `Logs/IngestionMetrics/*.json`.
- Bundle readiness relies on manual README/hash creation; no automated validation prior to publishing.
- Redaction/sanitizer tooling exists but is not enforced as a preflight for telemetry uploads or bundle generation.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-M-001 | Telemetry schema & lint gate | Telemetry | In Progress | Added `Tools\Test-TelemetryIntegrity.ps1` to fail fast on malformed JSON and missing InterfaceSync/queue metrics. Wired into `Tools\Invoke-StateTracePipeline.ps1` (optional switch), `Tools\Invoke-AllChecks.ps1`, and now defaults on in `Tools\Invoke-StateTraceScheduledVerification.ps1`; reports stored under `Logs/Reports/TelemetryIntegrity-*.txt`. |
| ST-M-002 | Bundle integrity checker | PMO | In Progress | Extend `Tools\Test-TelemetryBundleReadiness.ps1` (or new helper) to verify README presence, hash files, analyzer outputs, queue/diversity summaries, and shared-cache diagnostics before `Publish-TelemetryBundle`. |
| ST-M-003 | Redaction enforcement | Security | Backlog | Add optional `-RequireRedaction` flag to bundle/publish scripts that runs `Tools\Sanitize-PostmortemLogs.ps1` (or similar) and logs evidence paths in plan/task updates. |
| ST-M-004 | Rollup hygiene | Telemetry | Backlog | Ensure `Tools\Rollup-IngestionMetrics.ps1` fails when source JSON contains warnings, and records input file hashes next to the CSV for traceability. |

## Recently delivered
- Plan created to centralize telemetry hygiene and bundle integrity.

## Automation hooks
- Telemetry lint: `Tools\Test-TelemetryIntegrity.ps1 -Path Logs\IngestionMetrics\2025-12-01.json -RequireQueueSummary -RequireInterfaceSync` or `Tools\Invoke-StateTracePipeline.ps1 -RequireTelemetryIntegrity` / `Tools\Invoke-AllChecks.ps1 -RequireTelemetryIntegrity` (scheduled verification wrapper also supports `-RequireTelemetryIntegrity`).
- Bundle check: `Tools\Test-TelemetryBundleReadiness.ps1 -BundlePath Logs\TelemetryBundles\<bundle> -RequireHashes -RequireQueueSummary`.
- Rollup hygiene: `Tools\Rollup-IngestionMetrics.ps1 -MetricsDirectory Logs\IngestionMetrics -OutputPath Logs\IngestionMetrics\IngestionMetricsSummary.csv -FailOnWarning`.

## Telemetry gates
- No analyzer runs on malformed JSON; queue summary and `InterfaceSyncTiming` required for ingestion/warm-run telemetry before bundling.
- Bundles must include README + hashes for every artifact (telemetry, analyzers, diff hotspots, rollups).
- Redaction required when logs include postmortem data or NetOps evidence.

## References
- `docs/plans/PlanE_Telemetry.md` (rollup and bundle expectations).
- `docs/CODEX_SHARED_CACHE_DIAGNOSTICS.md` (analyzer outputs to include in bundles).
- `docs/StateTrace_AI_Agent_Guide.md` (data handling / redaction).

