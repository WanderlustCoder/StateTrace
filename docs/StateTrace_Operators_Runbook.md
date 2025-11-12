# Operators Runbook - Incremental Interface Loading

## Summary
This runbook explains how the refreshed incremental-loading workflow surfaces device metadata immediately and streams interface ports in batches. Operators should use it to monitor ingestion sessions, interpret the bottom-of-window loading indicator, and validate that the UI stays responsive while the parser continues to deliver ports.

## Preconditions
- Current StateTrace build (2025-10-14 incremental-loading spike) deployed with the updated ParserPersistence, DeviceRepository, and Interface modules.
- BOYO/WLLS mock corpus or equivalent site data staged for ingestion.
- Access to `Tools/Invoke-StateTracePipeline.ps1` and the StateTrace WPF client on the local workstation.
- `Logs/IngestionMetrics/<date>.json` writeable so telemetry can be reviewed after the run.

## Steps
1. Run a fresh ingestion pass to stage interface batches:  
   `pwsh Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs`  
   (clear `Data/IngestionHistory/*.json` beforehand for clean telemetry).
2. Launch the StateTrace desktop client and open the Interfaces view for a device. Site, building, and switch metadata should appear immediately even before ports populate.
3. Watch the bottom status strip:
   - The `Loading ports.` message becomes visible as soon as streaming begins.
   - When batch counts are known the text changes to `Loading ports (<loaded> of <total>)`, and the adjacent progress bar reflects the delivered count.
   - Once all batches are consumed the message flips to `Ports loaded (<total>)` before collapsing.
4. As ports append, confirm that rows appear in small bursts (24-row chunks for large devices, smaller sets for others). The grid should stay interactive while additional batches arrive.
5. After the UI finishes, inspect `Logs/IngestionMetrics/<date>.json`:
   - `PortBatchReady` entries list `Hostname`, `PortsCommitted`, and `EstimatedBatchCount` per device.
   - `InterfaceSyncTiming` shows `BulkStageDurationMs`, `DiffDurationMs`, and `LoadExistingDurationMs` so you can correlate backend timings with the UI experience.
   - Capture these readings using the steps in **Telemetry capture & logging** below so every run records the evidence needed for Plan B/Plan D gates.

## Telemetry capture & logging
Once the incremental run completes, collect the telemetry snapshot and record it in your session log/plan update.

```pwsh
$logPath = 'Logs\IngestionMetrics\<date>.json'   # replace with the run you just completed
$telemetry = Get-Content -Raw $logPath | ConvertFrom-Json
$portBatchReady = $telemetry | Where-Object { $_.EventName -eq 'PortBatchReady' }
$interfaceSync = $telemetry | Where-Object { $_.EventName -eq 'InterfaceSyncTiming' }
$dbLatency = $telemetry | Where-Object { $_.EventName -eq 'DatabaseWriteBreakdown' }
```

| Signal | Command / Where to check | Target / Notes |
|--------|-------------------------|----------------|
| `PortBatchReady` count + sample | `$portBatchReady.Count` and `$portBatchReady | Select Hostname, PortsCommitted, EstimatedBatchCount` | Expect one entry per processed host (37 for BOYO/WLLS). Record the total count and at least one sample host in your plan/session log. |
| Incremental telemetry fields | `$interfaceSync | Select Hostname, BulkStageDurationMs, DiffDurationMs, LoadExistingDurationMs` | Bulk stage should stay near 60 ms (p95 < 120 ms); `LoadExistingDurationMs` should remain < 500 ms. Note any hosts exceeding those numbers. |
| Database write latency | `$dbLatency | Measure-Object -Property DatabaseWriteLatencyMs -Maximum -Average` | Plan B gate: p95 < 950 ms for cold passes. Capture the average/p95 so future runs can compare. |
| Snapshot status | `$interfaceSync | Group-Object SiteCacheProvider` | Confirm `SiteCacheProvider` values are `Cache`/`SharedCache`; any `ADODB` entries require follow-up. |

Store the telemetry path (`$logPath`) and the summarized numbers in your session log and in the Plan D timeline entry. These values support the automation gates listed in `docs/telemetry/Automation_Gates.md`.

## Warm-run Cache Reuse Validation (Optional)
1. Stay in the same PowerShell session that completed Step 1 (or start a new one and keep it open), then execute the preserved-session warm-run harness:  
   `.\Tools\Invoke-WarmRunRegression.ps1 -VerboseParsing`  
   The wrapper drives both cold and warm passes with `-RefreshSiteCaches`, enforces single-thread overrides, asserts cache reuse, and exports a timestamped summary under `Logs\IngestionMetrics\WarmRunTelemetry-<timestamp>.json`. Record the invocation and output path in your session log.
   - When running the end-to-end harness instead of the standalone wrapper, append `-RunWarmRunRegression` (and optionally `-WarmRunRegressionOutputPath <path>`) to `Tools\Invoke-StateTracePipeline.ps1` to execute the preserved-session regression immediately after the baseline ingestion pass.
2. Review the console summary after the script completes. A healthy run reports cold average InterfaceCallDurationMs in the 360–420 ms range (p95 under ~950 ms) and warm averages below 180 ms with a >60% improvement. The provider breakdown should read `Cache=37` (or the number of hosts processed). Any `AssertWarmCache` failure aborts the script; capture the error text and escalate immediately.
3. For deeper inspection, open the exported JSON summary and filtrate the `WarmRunComparison` record plus the `WarmPass` entries. Confirm each warm host reports `CacheStatus=Hit`, `SiteCacheProvider=Cache`, `HostMapSignatureMatchCount` equal to the host’s row count, and `SiteCacheHostMapSignatureRewriteCount=0`. Archive or remove generated `Data\IngestionHistory\*.warmrun.*.bak` files after review.

## Expected Results
- Each device emits at least one `PortBatchReady` event (37 total for the BOYO/WLLS corpus in the 2025-10-14 13:12 MT run, average `PortsCommitted` 43.6, max 91).
- Bottom status indicator remains visible until `BatchesRemaining` reaches zero, with the progress bar advancing alongside delivered ports.
- UI interactions (sorting, scrolling) stay responsive while streaming occurs; dispatcher updates run every ~150 ms until the queue drains.
- Telemetry reports `DatabaseWriteLatency` averages near 0.61 s (p95 +/- 1.86 s) and `BulkStageDurationMs` averaging ~61 ms for this run; higher latencies should trigger follow-up investigation.
- Preserved-session warm runs executed via `Tools\Invoke-WarmRunRegression.ps1` should emit `WarmRunComparison` with cold averages near 360-420 ms, warm averages below 180 ms, improvement >=60%, `WarmProviderCounts` showing only `Cache`, and zero signature rewrites. If the script fails its assertions or any warm host falls back to `Provider=ADODB`, collect the exported JSON plus console output and escalate with the ingestion team.

## Escalation
- If the status indicator never appears or remains stuck on `Loading ports.` for more than 30 seconds, collect `PortBatchReady` and `InterfaceSyncTiming` samples and escalate to the ingestion team (ParserPersistence/DeviceRepository owners).
- If telemetry lacks `PortBatchReady` events, verify that ParserPersistence staged batches successfully and fall back to the previous full-load workflow (restart the client after a complete ingestion pass).
- If `Tools\Invoke-WarmRunRegression.ps1` fails or the exported telemetry shows `HostMapSignatureMatchCount=0`/`Provider=ADODB`, verify ingestion history was restored between passes and rerun once. Persisting failures should be escalated to the DeviceRepository owners with the JSON summary and corresponding `InterfaceSiteCacheMetrics` samples.
- Report client UI issues (indicator stuck visible, dispatcher exceptions in console) to the UI maintainers before re-running ingestion.
