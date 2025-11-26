# Telemetry Bundle Verification

Use this runbook to prove that every telemetry bundle (Plan E ST-E-007/ST-E-009, Plan G ST-G-007) contains the artifacts required for release sign-off. Follow it after running `Tools/Publish-TelemetryBundle.ps1` for the `Telemetry` and `Routing` areas.

## Prerequisites
- Latest cold + warm runs (or daily rollup) completed with artifacts under `Logs/IngestionMetrics/` and `Logs/TelemetryBundles/<bundle>/`.
- `Tools/New-TelemetryBundle.ps1` / `Tools/Publish-TelemetryBundle.ps1` committed (see `docs/CODEX_RUNBOOK.md`).
- Doc-sync checklist output per `docs/CODEX_DOC_SYNC_PLAYBOOK.md`.

## Required bundle contents

| Area | Required files | Notes |
|------|----------------|-------|
| Telemetry (`Logs/TelemetryBundles/<bundle>/Telemetry/`) | `README.md` (with command list + TaskBoard IDs), manifest JSON, latest rollup CSV (`IngestionMetricsSummary-*.csv`), shared-cache analyzer exports (`SharedCacheStoreState*.json`, `SiteCacheProviderReasons*.json`), warm-run telemetry summary (`WarmRunTelemetry-*.json`), diff-hotspot CSV, doc-sync checklist output (copy under `DocSync/`), optional additional analyzer output. | Ensure README hash is recorded in Plan E + Plan G. |
| Routing (`Logs/TelemetryBundles/<bundle>/Routing/`) | `README.md`, manifest JSON, `Logs/IngestionMetrics/<run>.json`, queue summary (`QueueDelaySummary-*.json` + `QueueDelaySummary-latest.json` pointer), dispatcher harness logs or sweep JSON, routing host list snapshot, doc-sync checklist output referencing ST-A-001/005/006, history CSVs (`QueueDelayHistory.csv`, `ParserSchedulerHistory.csv`, `PortBatchHistory.csv`, `InterfaceSyncHistory.csv`). | Dispatcher logs should include slowest-host transcripts from `Tools\Invoke-RoutingQueueSweep.ps1`. |

## Steps
1. **Identify the bundle folder**  
   ```powershell
   $bundle = 'Logs/TelemetryBundles/2025-11-13.1'
   Get-ChildItem $bundle
   ```
   Verify that at least the `Telemetry` and `Routing` subfolders exist.

2. **Run the readiness script (captures README hashes automatically)**  
   ```powershell
   pwsh Tools/Test-TelemetryBundleReadiness.ps1 `
       -BundlePath $bundle `
       -Area Telemetry,Routing `
       -IncludeReadmeHash `
       -SummaryPath "$bundle/VerificationSummary.json"
   ```
   The script prints a table of README hashes (SHA-256 by default) plus the requirement checklist for each area, and it writes a machine-readable summary JSON file you can reference from plans/task board rows. Keep the summary with the bundle so reviewers can see which files were validated.

3. **Verify Telemetry payload**  
   ```powershell
   Test-Path "$bundle/Telemetry/IngestionMetricsSummary-*.csv"
   Test-Path "$bundle/Telemetry/SharedCacheStoreState*.json"
   Test-Path "$bundle/Telemetry/SiteCacheProviderReasons*.json"
   Test-Path "$bundle/Telemetry/WarmRunTelemetry-*.json"
   Test-Path "$bundle/Telemetry/DiffHotspots-*.csv"
   Test-Path "$bundle/Telemetry/DocSync/DocSyncChecklist.json"
   ```
   Each command must return `True`. If a file is missing, regenerate it (rerun rollup/analyzers) before proceeding.

4. **Verify Routing payload**  
```powershell
Test-Path "$bundle/Routing/QueueDelaySummary-*.json"
Test-Path "$bundle/Routing/QueueDelaySummary-latest.json"
Test-Path "$bundle/Routing/QueueDelayHistory.csv"
Test-Path "$bundle/Routing/ParserSchedulerHistory.csv"
Test-Path "$bundle/Routing/PortBatchHistory.csv"
Test-Path "$bundle/Routing/InterfaceSyncHistory.csv"
Test-Path "$bundle/Routing/DispatcherLogs/*.log"
Test-Path "$bundle/Routing/RoutingQueueSweep-*.json"
Test-Path "$bundle/Routing/DocSync/DocSyncChecklist.json"
```
   Confirm the dispatcher logs cover the host matrix specified in Plan A ST-A-001. Re-run `Tools\Invoke-RoutingQueueSweep.ps1` if coverage is incomplete.

5. **Document evidence & stash the summary**  
   - Append the bundle path + README hashes to `docs/plans/PlanE_Telemetry.md` (ST-E-007/009) and `docs/plans/PlanG_ReleaseGovernance.md` (ST-G-007).  
   - Update `docs/StateTrace_TaskBoard.md` release + telemetry rows with the bundle ID, hash, and verification timestamp.  
   - Commit (or archive alongside the bundle) the `VerificationSummary.json` emitted by the readiness script so future reviewers can diff what changed between bundles.  
   - Use `pwsh Tools\Show-TelemetryBundleSummary.ps1 -BundlePath <bundle>` whenever you need to re-display the hashes/requirement table without rerunning the readiness checks.  
   - Mention the verification in the active session log per `docs/CODEX_DOC_SYNC_PLAYBOOK.md`.

6. **(Optional) Manual spot checks**  
   The readiness script throws if required artifacts are missing, but you can still run the `Test-Path` commands from Steps 3–4 to spot-check individual files (useful when regenerating a single artifact). In CI, call `pwsh Tools\Invoke-AllChecks.ps1 -SkipPester -SkipSpanHarness -SkipNetOpsLint -TelemetryBundlePath $bundle -RequireTelemetryBundleReady` to reuse the same guardrail.

## Documentation updates
- Plans A/E/G timelines must cite the verified bundle path and README hash.
- `docs/CODEX_PLAN_AUTOMATION_MATRIX.md` (Plan E + Plan G rows) should reference this runbook when describing telemetry bundle tasks.
- `docs/Release.md` “Telemetry Bundle Verification” step should link to this runbook for operators.
