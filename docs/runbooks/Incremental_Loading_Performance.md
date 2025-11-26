# Incremental Loading Performance Sweep

Use this runbook to baseline UI incremental-loading throughput whenever the Interfaces view or related pipelines change. The sweep captures `PortBatchReady` + `InterfaceSyncTiming` telemetry, summarises the results with `Tools/Analyze-PortBatchReadyTelemetry.ps1`, and records the output for Plan D ST-D-003 plus release bundles.

## Prerequisites
- Cold parser pipeline can run locally (Access DB + test logs available).
- `Tools\Analyze-PortBatchReadyTelemetry.ps1` committed (see `docs/CODEX_RUNBOOK.md` entry).
- `Logs/IngestionMetrics/` contains the telemetry JSON produced by the pipeline run you are validating.

### Automation options
- **Telemetry-first checklist**
  ```powershell
  pwsh Tools\Invoke-IncrementalLoadingChecklist.ps1 `
      -MaxHosts 20 `
      -SiteFilter WLLS,BOYO
  ```
  This helper runs `Tools\Invoke-StateTracePipeline.ps1`, feeds the dispatcher harness, synthesizes missing telemetry, reruns `Tools\Test-IncrementalTelemetryCompleteness.ps1`, and emits the diversity/scheduler evidence (`Logs/Reports/PortBatchSiteDiversity-*.json`, `docs/performance/SchedulerVsPortDiversity-*.md`) referenced later in this runbook.

- **Headless Interfaces view session**
  ```powershell
  pwsh -NoLogo -STA -File Tools\Invoke-InterfacesViewChecklist.ps1 `
      -SiteFilter WLLS,BOYO `
      -MaxHosts 10 `
      -OutputPath Logs\Reports\InterfacesViewChecklist.json
  ```
  This command hosts the Interfaces view inside a hidden window, iterates through each host, streams incremental batches via the WPF dispatcher, and records a per-host summary while the standard UI telemetry (`PortBatchReady`, `InterfaceSyncTiming`, `DeviceDetailsLoadMetrics`) is produced. Use it whenever a “real UI” incremental-loading run is required but an interactive desktop is unavailable.

## UI workflow (deferred toolbar actions)
- At launch the WPF shell now loads instantly and idles until the operator chooses how to hydrate data. Nothing parses automatically, which keeps window creation responsive even on large log sets.
- **Scan Logs**: launches the parser pipeline in a background job so the WPF shell stays responsive. It honors the `Include archive/history` checkboxes, records stdout in `Logs\UI\ParserJob-<timestamp>.log`, and updates the parser status indicator (next bullet) as soon as the run starts.
- **Parser status indicator**: the label beside the toolbar buttons now shows `Parser idle`, `Parsing in progress`, or `Parsing finished (log: …)`. Once the indicator says the run completed you can click **Load from DB** (or let the auto-refresh kick in if you left the window untouched) to hydrate the UI with the new Access data.
- **Load from DB**: bypasses parsing entirely and hydrates the view directly from Access via `DeviceCatalogModule\Get-DeviceSummaries -SiteFilter <site>`. Use this when you only need to inspect an existing `.accdb` snapshot.
- The **Site** dropdown is populated from the `Data\<site>\<site>.accdb` file names at startup so you can pick a site before hitting either button. Selecting a site limits both parsing and database hydration to that Access file, which drastically shortens incremental UI checks when you only care about one campus.
- The Interfaces tab now shows the host loading indicator immediately and clears it once `Set-InterfaceViewData` finishes, so you get visual feedback even when only the DB import path runs.

## Steps
1. **Seed telemetry via parser pipeline**
  ```powershell
   pwsh Tools/Invoke-StateTracePipeline.ps1 `
       -SkipTests -VerboseParsing -ResetExtractedLogs `
       -VerifyTelemetryCompleteness -FailOnTelemetryMissing `
       -SynthesizeSchedulerTelemetryOnMissing `
       -RunSharedCacheDiagnostics
   ```
   - Follow the incremental-loading steps in `docs/StateTrace_Operators_Runbook.md` (open Interfaces, allow streaming batches to complete, capture progress bar screenshots if needed).
   - Scheduler fairness now fails the run automatically whenever `ParserSchedulerLaunch` streaks break the guard limit. Only pass `-FailOnSchedulerFairness:$false` (and call it out in Plan D/Plan A) when replaying incomplete telemetry for investigation.
   - Verify `Logs/IngestionMetrics/<timestamp>.json` exists after the run (contains `PortBatchReady` + `InterfaceSyncTiming` events).

2. **Generate the performance summary**
   ```powershell
   $metricsFile = 'Logs/IngestionMetrics/2025-11-13.json'
   $report      = 'Logs/Reports/PortBatchReady-20251113.json'
   pwsh Tools/Analyze-PortBatchReadyTelemetry.ps1 `
       -Path $metricsFile `
       -IncludeHostBreakdown `
       -OutputPath $report `
       -BaselineSummaryPath Logs/Reports/PortBatchReady-<previous>.json # optional
   ```
   - The script prints aggregate throughput (ports/minute, batch interval p95), InterfaceSyncTiming durations (UiClone/StreamDispatch/Diff), and a host-level batch table.
   - The JSON report includes the raw metrics and any baseline comparisons; store it under `Logs/Reports/` and add it to the telemetry bundle if release-bound.

3. **Document results**
   - Update `docs/plans/PlanD_FeatureExpansion.md` (ST-D-003 section + timeline) with:
     - Telemetry file path (`Logs/IngestionMetrics/<timestamp>.json`)
     - Analyzer report path (`Logs/Reports/PortBatchReady-<timestamp>.json`)
     - Key metrics (ports/min, UiClone/StreamDispatch p95, number of hosts).
   - Run the gap analyzer to highlight idle windows and persist the intervals:
     ```powershell
     pwsh Tools/Analyze-PortBatchIntervals.ps1 `
         -Path Logs/IngestionMetrics/<timestamp>.json `
         -TopIntervals 10 `
         -ThresholdSeconds 60 `
         -OutputPath Logs/Reports/PortBatchIntervals-<timestamp>.json
     ```
     Capture any gaps >= 60 seconds (start/end hosts + duration) in the plan entry and follow-up tasks.
   - Correlate dispatcher queue telemetry with the saved intervals:
     ```powershell
   pwsh Tools/Analyze-DispatcherGaps.ps1 `
       -QueueSummaryPaths Logs/IngestionMetrics/QueueDelaySummary-<timestamp>.json `
       -IntervalReportPath Logs/Reports/PortBatchIntervals-<timestamp>.json `
       -GapThresholdSeconds 60 `
       -OutputPath docs/performance/DispatcherGapCorrelation-<timestamp>.md
   ```
   Reference the markdown + queue summary path inside the plan/task board and copy the artifacts into the active telemetry bundle.
   - Produce the site-to-site breakdown so throttled transitions are obvious:
     ```powershell
     pwsh Tools/Analyze-PortBatchGapBreakdown.ps1 `
         -IntervalReportPath Logs/Reports/PortBatchIntervals-<timestamp>.json `
         -TopGaps 10 `
         -OutputPath docs/performance/PortBatchSiteGapSummary-<timestamp>.md
     ```
     Attach the markdown to the plan/task board updates (ST-D-003/ST-D-010) and include it in the telemetry bundle beside the dispatcher report.
   - Add the gap timeline so the per-host sequence is explicit:
      ```powershell
      pwsh Tools/Analyze-PortBatchGapTimeline.ps1 `
          -MetricsPath Logs/IngestionMetrics/<timestamp>.json `
          -GapThresholdSeconds 60 `
          -EventsBefore 5 `
          -EventsAfter 5 `
          -OutputPath docs/performance/WLLS_BOYO_GapTimeline-<timestamp>.md
      ```
      Link the timeline in the plan/task board entry and copy it into the telemetry bundle with the other performance artifacts.
   - Run the site-diversity guard so scheduler starvation fails fast:
      ```powershell
      pwsh Tools/Test-PortBatchSiteDiversity.ps1 `
          -MetricsPath Logs/IngestionMetrics/<timestamp>.json `
          -MaxAllowedConsecutive 8 `
          -OutputPath Logs/Reports/PortBatchSiteDiversity-<timestamp>.json
      ```
      Use the console output/JSON in Plan D ST-D-003 updates and add the JSON to the telemetry bundle; adjust the threshold as needed per runbook/plan guidance.
      > `Tools\Invoke-StateTracePipeline.ps1` now runs this guard automatically and emits `Logs/Reports/PortBatchSiteDiversity-<metrics>.json`; rerun it manually only when you need to inspect historical telemetry or change the threshold.
   - Verify parser scheduler rotation telemetry to confirm `ParserSchedulerLaunch` events show fair alternation:
      ```powershell
      pwsh Tools/Analyze-ParserSchedulerLaunch.ps1 `
          -Path Logs/IngestionMetrics/<timestamp>.json `
          -MaxAllowedStreak 8 `
          -OutputPath Logs/Reports/ParserSchedulerLaunch-<timestamp>.json
      ```
      Attach the JSON to the same telemetry bundle and reference streak counts (per-site launches, longest runs, and any violations) in Plan A/Plan D updates. Treat any streak above the guard threshold as a blocker for ST-D-010 until a new run passes both the diversity test and this analyzer.
      > `Tools/Invoke-StateTracePipeline.ps1` now runs this analyzer and `Tools\Test-ParserSchedulerFairness.ps1 -ReportPath ... -ThrowOnViolation` automatically after every ingestion pass, saves the report under `Logs/Reports/ParserSchedulerLaunch-<metrics>.json`, and appends the stats to `Logs/Reports/ParserSchedulerHistory.csv`; rerun the commands manually only when inspecting older telemetry or experimenting with custom thresholds.
   - Compare the parser scheduler streaks with PortBatchReady streaks:
      ```powershell
      pwsh Tools/Compare-SchedulerAndPortDiversity.ps1 `
          -SchedulerReportPath Logs/Reports/ParserSchedulerLaunch-<timestamp>.json `
          -PortDiversityReportPath Logs/Reports/PortBatchSiteDiversity-<timestamp>.json `
          -OutputPath Logs/Reports/SchedulerVsPortDiversity-<timestamp>.json `
          -MarkdownPath docs/performance/SchedulerVsPortDiversity-<timestamp>.md
      ```
      The pipeline now emits both the JSON (for telemetry bundles) and the markdown summary under `docs/performance/`, so Plan D ST-D-010 and release notes can cite the exact deltas without manual conversion. Rerun the command manually only when replaying older telemetry or experimenting with different sources.
   - Generate the balanced routing host list whenever telemetry reveals new hosts or the dispatcher sweep reports uneven coverage. This keeps `Data/RoutingHosts.txt` authoritative (37 WLLS/BOYO hosts) and emits the segmented order used by `Tools\Invoke-RoutingQueueSweep.ps1 -UseBalancedHostOrder`:
   ```powershell
   pwsh Tools/New-BalancedRoutingHostList.ps1 `
       -InputPath Data/RoutingHosts.txt `
       -OutputPath Data/RoutingHosts_Balanced.txt `
       -SiteOrder WLLS,BOYO
   ```
   Attach both routing host files plus the latest sweep summary (`Logs/DispatchHarness\RoutingQueueSweep-<timestamp>.json`) and report (`docs/performance/DispatchHarnessSweepOrder-<timestamp>.md`) to the telemetry bundle, then reference them in Plan A/Plan D updates before handing the order to the routing team.
   - If the ingestion metrics file does not contain any `PortBatchReady` events, synthesize them from the stream metrics before running the analyzers:
     ```powershell
     pwsh Tools/Add-PortBatchReadyTelemetry.ps1 `
         -MetricsPath Logs/IngestionMetrics/<timestamp>.json `
         -InPlace
     ```
     The script keeps a `.bak` of the original telemetry and appends synthesized rows (flagged with `Synthesized=true`) so the rest of the tooling continues to operate on the canonical path.
   - When the full verification harness cannot run, generate the queue-delay summary directly from telemetry:
     ```powershell
   pwsh Tools/Generate-QueueDelaySummary.ps1 `
       -MetricsPath Logs/IngestionMetrics/<timestamp>.json `
       -OutputPath Logs/IngestionMetrics/QueueDelaySummary-<timestamp>.json
   ```
   Include the summary JSON in the telemetry bundle and reference it in Plan A/Plan D updates alongside the gap/timeline markdown. `Tools/Invoke-StateTracePipeline.ps1` now generates this summary automatically after every cold run and appends the stats to `Logs/Reports/QueueDelayHistory.csv` via `Tools/Update-QueueDelayHistory.ps1`, so you only need to run the command manually when backfilling older telemetry or experimenting with non-default thresholds.
   - Double-check that telemetry includes every required signal (PortBatchReady, InterfaceSyncTiming, ParserSchedulerLaunch) before publishing docs or closing ST-D-003/ST-A-001:
     ```powershell
     pwsh Tools/Test-IncrementalTelemetryCompleteness.ps1 `
         -MetricsPath Logs/IngestionMetrics/<timestamp>.json `
         -RequirePortBatchReady -RequireInterfaceSync -RequireSchedulerLaunch -ThrowOnMissing
     ```
     Resolve any missing signals (for example, rerun the UI to capture InterfaceSync events) before marking the run as valid; the script warns when synthetic data (like the 2025-11-14 scheduler gap) needs a follow-up session.
     > `Tools/Invoke-StateTracePipeline.ps1 -VerifyTelemetryCompleteness` calls this script automatically (use `-FailOnTelemetryMissing` to stop the run). Invoke it manually only when validating historical telemetry or when the pipeline switches are omitted.
     > When historical telemetry lacks `ParserSchedulerLaunch` events and a new UI session is not feasible, run `Tools/Synthesize-ParserSchedulerTelemetry.ps1 -MetricsPath Logs/IngestionMetrics/<timestamp>.json -InPlace` (the pipeline does this automatically when `-SynthesizeSchedulerTelemetryOnMissing` is supplied) to backfill the scheduler launch stream before rerunning the completeness check.
   - Summarise the per-window site mix to highlight dominant periods:
      ```powershell
      pwsh Tools/Analyze-PortBatchSiteMix.ps1 `
          -MetricsPath Logs/IngestionMetrics/<timestamp>.json `
          -WindowMinutes 5 `
          -TopWindows 6 `
          -OutputPath docs/performance/PortBatchSiteMix-<timestamp>.md
      ```
      Reference the markdown in Plan D and include it in the telemetry bundle alongside the other performance artifacts.
   - Update `docs/StateTrace_TaskBoard.md` and `docs/taskboard/TaskBoard.csv` row ST-D-003 with the same data.
   - Mention the verification in your active session log per `docs/CODEX_DOC_SYNC_PLAYBOOK.md`.
   - Append the analyzer output to the history CSV so trends are obvious:
     ```powershell
     pwsh Tools/Update-PortBatchHistory.ps1 `
         -ReportPaths Logs/Reports/PortBatchReady-<timestamp>.json `
         -HistoryPath Logs/Reports/PortBatchHistory.csv
     ```

4. **Bundle and release linkage**
   - When preparing `Logs/TelemetryBundles/<version>/`, copy the analyzer report, gap JSON, dispatcher markdown, and history CSVs into the Telemetry area (for Plan E/G) so performance evidence ships with each release candidate.
   - Reference the summary in `docs/Release.md` telemetry gate notes if UI changes affect performance.

5. **Repeat after material UI changes**
   - Re-run Steps 1-4 after significant UI, pipeline, or caching work.
   - Use `-BaselineSummaryPath` to highlight regressions versus the prior report automatically.

## Outputs to retain
| Artifact | Description |
|----------|-------------|
| `Logs/IngestionMetrics/<timestamp>.json` | Raw telemetry from the incremental-loading run. |
| `Logs/Reports/PortBatchReady-<timestamp>.json` | Analyzer JSON containing throughput/latency metrics (plus baseline comparisons). |
| Console summary from `Tools/Analyze-PortBatchReadyTelemetry.ps1` | Include in plan/task updates and session logs. |
| `docs/performance/DispatcherGapCorrelation-<timestamp>.md` + `Logs/Reports/PortBatchIntervals-<timestamp>.json` | Dispatcher/idle-gap evidence tied to queue guardrails (must ship in telemetry bundles). |

Refer back to this runbook whenever incremental-loading performance is questioned or before UI releases that touch the Interfaces workflow.

