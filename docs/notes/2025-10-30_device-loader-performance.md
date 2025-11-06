[2025-10-30] Device loader performance tuning
============================================

Baseline
--------
- Latest debug log (`Logs\StateTrace_Debug_20251030_094055.log`) showed 1.57 s from `Import-DeviceDetailsAsync start` to the first `Interface batch appended` for `BOYO-A05-AS-02`. Additional deltas: 0.29 s to open the background thread and 0.83 s to deliver the first batch once the aggregate refreshed.
- Device summary grids reported 636 interfaces across 12 devices for BOYO, confirming data volume for tuning estimates (target chunk size ≈ 100 rows per batch).

Changes
-------
- Main/MainWindow.ps1
  - Added a pooled STA runspace guarded by a semaphore so hostname changes reuse a warm pipeline instead of creating a new runspace/thread every selection.
  - Introduced `Queue-DeviceDetailsWarmup` to hydrate the device loader during window idle time. Modules from `ModulesManifest.psd1` import once per session (no `-Force`).
  - Captured detailed loader metrics (invoke duration, stream duration, first batch latency, UI dispatcher totals) and emit them through `TelemetryModule\Write-StTelemetryEvent -Name 'DeviceDetailsLoadMetrics'` plus diagnostics.
  - Snapshotted port data back into `DeviceInterfaceCache` after streaming finishes so subsequent selections avoid Access re-hydration.
- Modules/DeviceRepositoryModule.psm1
  - Added adaptive chunk sizing: targets ~6 batches per device with a 120-row ceiling while respecting overrides; metrics now include `ChunkSource`.
- Tools/Invoke-InterfacesViewSmokeTest.ps1
  - Dropped `-Force` module imports to keep smoke runs aligned with the warm cache path.
- Modules/ParserPersistenceModule.psm1
  - Skips site cache hydration when a site's Access database has no rows, avoiding the multi-second initial `Get-InterfaceSiteCache` refresh and tagging telemetry with `SiteCacheFetchStatus='SkippedEmpty'`.
  - Added `SkipSiteCacheUpdate` plumbing (settings + env flag) so bulk parses can bypass site-cache hydration entirely; DeviceLogParser now forwards the flag and telemetry includes `SkipSiteCacheUpdate` to confirm it fired.

Follow-ups
----------
1. Re-run the desktop UI (or `pwsh -STA -File Tools\Invoke-InterfacesViewSmokeTest.ps1 -Hostname 'BOYO-A05-AS-02' -PassThru`) to capture fresh timings. Expect fewer batches (≈6) and updated telemetry in `Logs\IngestionMetrics\*.json` plus `DeviceDetailsLoadMetrics`. Archive results alongside this note.
2. Execute `Invoke-Pester Modules/Tests` before shipping to confirm regressions weren’t introduced. The async loader now relies on shared runspace state; watch for strict-mode failures.
3. Review incoming `DeviceDetailsLoadMetrics` for large campuses (≥500 ports) to determine if the 120-row cap should be raised or if further batching is needed for multi-thread hosts.
4. If ingestion updates land mid-session, validate that the new cache snapshot still surfaces live data. If not, consider augmenting the cache key with the latest `RunDate`.
5. Update any monitoring dashboards to surface the new telemetry fields (`ChunkSource`, `InvokeDurationMs`, `StreamDurationMs`, etc.) once enough runs are collected.
6. When databases are cleared, run the parser utility (`Tools\Invoke-StateTracePipeline.ps1` or `ParserWorker\Invoke-StateTraceParsing`) to repopulate Access files before opening the UI, and record the parser run alongside UI validation steps.
7. With `SkipSiteCacheUpdate` enabled, watch `DatabaseWriteBreakdown.SkipSiteCacheUpdate` for `True` and confirm ingestion latencies (e.g., BOYO `SiteCacheFetchStatus='SkippedEmpty'`, WLLS `SiteCacheFetchStatus='SharedOnly'`) stay under ~0.8s per host; flip the setting back to `false` if the Access cache needs to be rebuilt for long-lived runspaces.

Notes
-----
- The warmup helper logs `Device loader warmup completed` in debug mode; if that line is missing, ensure `Queue-DeviceDetailsWarmup` fires (look for dispatcher exceptions).
- Cached interface lists are rebuilt on UI thread to avoid cross-thread enumeration. If throughput stalls, consider offloading snapshot creation to a background dispatcher priority.
