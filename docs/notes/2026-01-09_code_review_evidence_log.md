# Code review evidence log (2026-01-09)

## Commands executed
| Date | Command | Purpose | Output/Artifact | Notes |
|------|---------|---------|----------------|-------|
| 2026-01-10 | Tools/Test-DocSyncChecklist.ps1 -TaskId ST-G-012 -SessionLogPath docs/agents/sessions/2026-01-10_session-0002.md -RequireSessionLog -RequireBacklogEntry -PlanPath docs/plans/PlanG_ReleaseGovernance.md -OutputPath Logs/Reports/DocSyncChecklist-ST-G-012-20260110-185738.json | Doc-sync checklist | Logs/Reports/DocSyncChecklist-ST-G-012-20260110-185738.json | Pass. |
| 2026-01-10 | Tools/Test-TaskBoardIntegrity.ps1 -OutputPath Logs/Reports/TaskBoardIntegrity-20260110-185749.json | TaskBoard integrity guard | Logs/Reports/TaskBoardIntegrity-20260110-185749.json | Pass. |
| 2026-01-10 | Tools/Publish-TelemetryBundle.ps1 -BundleName Review-20260110-ST-G-012-180409-Routing -AreaName Routing -PlanReferences PlanG -TaskBoardIds ST-G-012 -Notes "Routing bundle refresh from verification harness (queue delay + dispatcher logs)." -ColdTelemetryPath Logs/IngestionMetrics/2026-01-10.json -WarmTelemetryPath Logs/IngestionMetrics/WarmRunTelemetry-20260110-180409.json -QueueSummaryPath Logs/IngestionMetrics/QueueDelaySummary-20260110-180729.json -AdditionalPath Logs/DispatchHarness/*-20260110-180627.log,Logs/DispatchHarness/RoutingQueueSweep-pipeline-2026-01-10.json -Force | Routing bundle refresh | Logs/TelemetryBundles/Review-20260110-ST-G-012-180409-Routing/Routing | Includes dispatcher logs and routing queue sweep summary. |
| 2026-01-10 | Tools/Test-TelemetryBundleReadiness.ps1 -BundlePath Logs/TelemetryBundles/Review-20260110-ST-G-012-180409-Routing -Area Routing -IncludeReadmeHash -SummaryPath Logs/TelemetryBundles/Review-20260110-ST-G-012-180409-Routing/VerificationSummary-20260110-185535.json | Routing bundle readiness | Logs/TelemetryBundles/Review-20260110-ST-G-012-180409-Routing/VerificationSummary-20260110-185535.json | Pass; README hash F0394DAAB15873C1589BF922DA838E369A56A584BC9FF879E6A21BF00CEE0C77. |
| 2026-01-10 | Tools/Test-DocSyncChecklist.ps1 -TaskId ST-G-012 -SessionLogPath docs/agents/sessions/2026-01-10_session-0002.md -RequireSessionLog -RequireBacklogEntry -PlanPath docs/plans/PlanG_ReleaseGovernance.md -OutputPath Logs/Reports/DocSyncChecklist-ST-G-012-20260110-184137.json | Doc-sync checklist | Logs/Reports/DocSyncChecklist-ST-G-012-20260110-184137.json | Pass. |
| 2026-01-10 | Tools/Test-TaskBoardIntegrity.ps1 -OutputPath Logs/Reports/TaskBoardIntegrity-20260110-184059.json | TaskBoard integrity guard | Logs/Reports/TaskBoardIntegrity-20260110-184059.json | Pass. |
| 2026-01-10 | Tools/Test-DocSyncChecklist.ps1 -TaskId ST-G-012 -SessionLogPath docs/agents/sessions/2026-01-10_session-0002.md -RequireSessionLog -RequireBacklogEntry -PlanPath docs/plans/PlanG_ReleaseGovernance.md -OutputPath Logs/Reports/DocSyncChecklist-ST-G-012-20260110-184010.json | Doc-sync checklist | Logs/Reports/DocSyncChecklist-ST-G-012-20260110-184010.json | Pass. |
| 2026-01-10 | powershell.exe -NoProfile -Command "Invoke-Pester Modules/Tests" | Unit test rerun | Console output (Passed 1636, Failed 0, Inconclusive 0) | Final regression pass after telemetry bundle publish. |
| 2026-01-10 | Tools/Test-DocSyncChecklist.ps1 -TaskId ST-G-012 -SessionLogPath docs/agents/sessions/2026-01-10_session-0002.md -RequireSessionLog -RequireBacklogEntry -PlanPath docs/plans/PlanG_ReleaseGovernance.md -OutputPath Logs/Reports/DocSyncChecklist-ST-G-012-20260110-182143.json | Doc-sync checklist | Logs/Reports/DocSyncChecklist-ST-G-012-20260110-182143.json | Pass. |
| 2026-01-10 | Tools/Test-TaskBoardIntegrity.ps1 -OutputPath Logs/Reports/TaskBoardIntegrity-20260110-182143.json | TaskBoard integrity guard | Logs/Reports/TaskBoardIntegrity-20260110-182143.json | Pass. |
| 2026-01-10 | Tools/Publish-TelemetryBundle.ps1 -BundleName Review-20260110-ST-G-012-180409 -PlanReferences PlanG -TaskBoardIds ST-G-012 -Notes "Verification harness refresh (WarmRunTelemetry-20260110-180409; QueueDelaySummary-20260110-180729; DiffHotspots-20260110-180409)." -WarmTelemetryPath Logs/IngestionMetrics/WarmRunTelemetry-20260110-180409.json -DiffHotspotsPath Logs/IngestionMetrics/DiffHotspots-20260110-180409.csv -AnalyzerPath Logs/SharedCacheDiagnostics/SharedCacheStoreState-20260110-180409.json,Logs/SharedCacheDiagnostics/SiteCacheProviderReasons-20260110-180409.json -QueueSummaryPath Logs/IngestionMetrics/QueueDelaySummary-20260110-180729.json -AdditionalPath Logs/Reports/PortBatchSiteDiversity-2026-01-10.json -Force | Telemetry bundle refresh | Logs/TelemetryBundles/Review-20260110-ST-G-012-180409/Telemetry | Includes latest warm-run telemetry, queue delay summary, diff hotspots, shared cache diagnostics, and port diversity summary. |
| 2026-01-10 | Tools/Test-TelemetryBundleReadiness.ps1 -BundlePath Logs/TelemetryBundles/Review-20260110-ST-G-012-180409 -Area Telemetry -IncludeReadmeHash -SummaryPath Logs/TelemetryBundles/Review-20260110-ST-G-012-180409/VerificationSummary-20260110-181924.json | Telemetry bundle readiness | Logs/TelemetryBundles/Review-20260110-ST-G-012-180409/VerificationSummary-20260110-181924.json | Pass; README hash 4529AD5F433C281B69165E8B54C64EB78D21BB548258219910320C777BAF4479. |
| 2026-01-10 | Tools/Test-DocSyncChecklist.ps1 -TaskId ST-G-012 -SessionLogPath docs/agents/sessions/2026-01-10_session-0002.md -RequireSessionLog -RequireBacklogEntry -PlanPath docs/plans/PlanG_ReleaseGovernance.md -OutputPath Logs/Reports/DocSyncChecklist-ST-G-012-20260110-181257.json | Doc-sync checklist | Logs/Reports/DocSyncChecklist-ST-G-012-20260110-181257.json | Pass. |
| 2026-01-10 | Tools/Test-TaskBoardIntegrity.ps1 -OutputPath Logs/Reports/TaskBoardIntegrity-20260110-181257.json | TaskBoard integrity guard | Logs/Reports/TaskBoardIntegrity-20260110-181257.json | Pass. |
| 2026-01-10 | Tools/Invoke-StateTraceVerification.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs -GenerateSharedCacheDiagnostics -GenerateDiffHotspotReport -ForcePortBatchReadySynthesis | Verification harness refresh | Logs/IngestionMetrics/2026-01-10.json; Logs/IngestionMetrics/WarmRunTelemetry-20260110-180409.json; Logs/IngestionMetrics/QueueDelaySummary-20260110-180729.json; Logs/IngestionMetrics/DiffHotspots-20260110-180409.csv; Logs/Reports/PortBatchReady-2026-01-10.json; Logs/Reports/PortBatchSiteDiversity-2026-01-10.json; Logs/Reports/ParserSchedulerLaunch-2026-01-10.json; Logs/Reports/SchedulerVsPortDiversity-2026-01-10.json; Logs/SharedCacheDiagnostics/SharedCacheStoreState-20260110-180409.json; Logs/SharedCacheDiagnostics/SiteCacheProviderReasons-20260110-180409.json | Warm-run improvement 75.12% (SharedCache=37); queue delay avg/p95/p99/max 19.672/21.480/39.097/52.907 ms; scheduler fairness pass; PortBatch max streak 1; shared cache coverage 2 sites/37 hosts/1320 rows. |
| 2026-01-10 | powershell.exe -NoProfile -Command "Invoke-Pester Modules/Tests" | Unit test pass | Console output (Passed 1636, Failed 0, Inconclusive 0) | Fixture restoration + CISmoke guard alignment. |
| 2026-01-10 | powershell.exe -NoProfile -Command "Invoke-Pester Modules/Tests/CISmokeHarness.Tests.ps1" | CISmoke harness | Console output (Passed 13, Failed 0, Inconclusive 0) | Validated PortBatch diversity guard compatibility. |
| 2026-01-10 | Tools/Test-DocSyncChecklist.ps1 -TaskId ST-G-012 -SessionLogPath docs/agents/sessions/2026-01-10_session-0002.md -RequireSessionLog -RequireBacklogEntry -PlanPath docs/plans/PlanG_ReleaseGovernance.md -OutputPath Logs/Reports/DocSyncChecklist-ST-G-012-20260110-175822.json | Doc-sync checklist | Logs/Reports/DocSyncChecklist-ST-G-012-20260110-175822.json | Pass. |
| 2026-01-10 | Tools/Publish-TelemetryBundle.ps1 (Telemetry area, Review-20260110-ST-G-012) | Telemetry bundle publish | Logs/TelemetryBundles/Review-20260110-ST-G-012/Telemetry | Included cold/warm telemetry, rollup CSV, shared cache diagnostics, diff hotspots, queue delay summary, port diversity summary, doc-sync evidence. |
| 2026-01-10 | Tools/Publish-TelemetryBundle.ps1 (Routing area, Review-20260110-ST-G-012) | Routing bundle publish | Logs/TelemetryBundles/Review-20260110-ST-G-012/Routing | Included queue delay summary + latest pointer, dispatcher logs (BOYO/WLLS), routing sweep JSON, doc-sync evidence. |
| 2026-01-10 | Tools/Test-TelemetryBundleReadiness.ps1 -BundlePath Logs/TelemetryBundles/Review-20260110-ST-G-012 -Area Telemetry,Routing -IncludeReadmeHash -SummaryPath Logs/TelemetryBundles/Review-20260110-ST-G-012/VerificationSummary.json | Telemetry bundle readiness verification | Logs/TelemetryBundles/Review-20260110-ST-G-012/VerificationSummary.json | Pass; optional Telemetry port diversity + queue summary present; README hashes Telemetry 0B42A27E7FB95D3C06117109E33B80A566D1F6C664FEA01823251055DB0FB428, Routing D6C0200AF1EDF80BFAB5B125060CABB2760EF58B1A37A3F2A75D115431D4226EE. |
| 2026-01-10 | Tools/Invoke-StateTraceVerification.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs -GenerateSharedCacheDiagnostics -GenerateDiffHotspotReport -ForcePortBatchReadySynthesis | Verification harness (Plan G readiness + shared cache diagnostics) | Logs/IngestionMetrics/WarmRunTelemetry-20260110-150106.json; Logs/IngestionMetrics/DiffHotspots-20260110-150106.csv; Logs/IngestionMetrics/QueueDelaySummary-20260110-150417.json; Logs/SharedCacheDiagnostics/SharedCacheStoreState-20260110-150106.json; Logs/SharedCacheDiagnostics/SiteCacheProviderReasons-20260110-150106.json; Logs/SharedCacheSnapshot/SharedCacheCoverage-latest.json | Warm-run improvement pass; shared cache diagnostics pass (AccessRefresh 0). |
| 2026-01-10 | Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -RunQueueDelayHarness -SharedCacheSnapshotDirectory Logs/SharedCacheSnapshot -DisablePreserveRunspace -DisableSkipSiteCacheUpdate -RequireTelemetryIntegrity (Review-20260110-DbLatency3-20260110-114623) | Pipeline rerun for DB write latency (history reset + telemetry override) | Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/2026-01-10.json; Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/QueueDelaySummary-2026-01-10.json; Logs/DispatchHarness/RoutingQueueSweep-pipeline-2026-01-10.json; Logs/Reports/PortBatchReady-2026-01-10.json; Logs/Reports/InterfaceSyncTiming-2026-01-10.json; Logs/Reports/PortBatchSiteDiversity-2026-01-10.json; Logs/SharedCacheSnapshot/SharedCacheSnapshot-20260110-114624.clixml | Telemetry integrity passed; DB write latency p95 174.6 ms; PortBatch diversity guard failed (no PortBatchReady events); ingestion history cleared/restored; STATETRACE_TELEMETRY_DIR set to Review-20260110-DbLatency3-20260110-114623. |
| 2026-01-10 | Tools/Rollup-IngestionMetrics.ps1 -MetricsDirectory Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623 -MetricFileNameFilter 2026-01-10.json -IncludePerSite -IncludeSiteCache -OutputPath Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/IngestionMetricsSummary-2026-01-10.csv | Rollup ingestion metrics (DB write latency retest) | Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/IngestionMetricsSummary-2026-01-10.csv | DatabaseWriteLatency p95 174.6 ms; ParseDuration p95 0.646 s. |
| 2026-01-10 | Tools/Analyze-SharedCacheStoreState.ps1 -Path Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/2026-01-10.json -IncludeSiteBreakdown \| ConvertTo-Json -Depth 6 \| Set-Content Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/SharedCacheStoreState-20260110-114623.json | Shared cache analyzer (JSON export) | Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/SharedCacheStoreState-20260110-114623.json | SnapshotImported 1; GetHit 39; GetMiss 0. |
| 2026-01-10 | Tools/Analyze-SiteCacheProviderReasons.ps1 -Path Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/2026-01-10.json -IncludeHostBreakdown \| ConvertTo-Json -Depth 6 \| Set-Content Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/SiteCacheProviderReasons-20260110-114623.json | Site cache provider reasons (JSON export) | Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/SiteCacheProviderReasons-20260110-114623.json | AccessRefresh 0; SharedCacheMatch 37. |
| 2026-01-10 | Tools/Test-DocSyncChecklist.ps1 -TaskId ST-G-012 -SessionLogPath docs/agents/sessions/2026-01-10_session-0001.md -RequireSessionLog -RequireBacklogEntry -PlanPath docs/plans/PlanG_ReleaseGovernance.md -OutputPath Logs/Reports/DocSyncChecklist-ST-G-012-20260110-154121.json | Doc-sync checklist | Logs/Reports/DocSyncChecklist-ST-G-012-20260110-154121.json | Pass. |
| 2026-01-10 | Tools/Test-TaskBoardIntegrity.ps1 -OutputPath Logs/Reports/TaskBoardIntegrity-20260110-154225.json | TaskBoard integrity guard | Logs/Reports/TaskBoardIntegrity-20260110-154225.json | Pass. |
| 2026-01-10 | pwsh Tools/Maintain-AccessDatabases.ps1 -DataRoot Data -IndexAudit | Access DB compaction + index audit | Logs/Maintenance/20260110-101624.log; Logs/Maintenance/20260110-101624-index-audit.csv; Data/Backups/BOYO_20260110-101624.accdb; Data/Backups/WLLS_20260110-101625.accdb | Maintenance run before DB latency retest. |
| 2026-01-10 | Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -RunWarmRunRegression -SharedCacheSnapshotDirectory Logs/SharedCacheSnapshot -DisablePreserveRunspace -DisableSkipSiteCacheUpdate -RequireTelemetryIntegrity (Review-20260110-100711) | Pipeline rerun (telemetry override) | Logs/Reports/TelemetryIntegrity-20260110-100831.txt | Failed: telemetry integrity check hit corrupted 20260110.json; pipeline aborted. |
| 2026-01-10 | Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -RunWarmRunRegression -RunQueueDelayHarness -SharedCacheSnapshotDirectory Logs/SharedCacheSnapshot -DisablePreserveRunspace -DisableSkipSiteCacheUpdate -RequireTelemetryIntegrity (Review-20260110-101119) | Pipeline rerun with queue harness | Logs/IngestionMetrics/Review-20260110-101119/2026-01-10.json; Logs/IngestionMetrics/Review-20260110-101119/QueueDelaySummary-2026-01-10.json; Logs/IngestionMetrics/WarmRunTelemetry-20260110-101129.json; Logs/Reports/TelemetryIntegrity-20260110-101304.txt | ParseDuration pass; DB write latency p95 980 ms. |
| 2026-01-10 | Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -RunWarmRunRegression -RunQueueDelayHarness -SharedCacheSnapshotDirectory Logs/SharedCacheSnapshot -DisablePreserveRunspace -DisableSkipSiteCacheUpdate -RequireTelemetryIntegrity (Review-20260110-101639) | Pipeline rerun post-maintenance | Logs/IngestionMetrics/Review-20260110-101639/2026-01-10.json; Logs/IngestionMetrics/Review-20260110-101639/QueueDelaySummary-2026-01-10.json; Logs/IngestionMetrics/WarmRunTelemetry-20260110-101650.json; Logs/Reports/TelemetryIntegrity-20260110-101823.txt; Logs/SharedCacheSnapshot/SharedCacheSnapshot-20260110-101653.clixml | ParseDuration pass; DB write latency p95 958.1 ms (still over gate). |
| 2026-01-10 | Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -RunWarmRunRegression -RunQueueDelayHarness -SharedCacheSnapshotDirectory Logs/SharedCacheSnapshot -DisablePreserveRunspace -DisableSkipSiteCacheUpdate -RequireTelemetryIntegrity -ThreadCeilingOverride 6 -MaxWorkersPerSiteOverride 2 (Review-20260110-101924) | Pipeline rerun with concurrency overrides | Logs/IngestionMetrics/Review-20260110-101924/2026-01-10.json; Logs/IngestionMetrics/Review-20260110-101924/QueueDelaySummary-2026-01-10.json; Logs/IngestionMetrics/WarmRunTelemetry-20260110-101934.json; Logs/Reports/TelemetryIntegrity-20260110-102107.txt | Overrides reset by guard; DB write latency p95 968.7 ms (worse). |
| 2026-01-10 | Tools/Rollup-IngestionMetrics.ps1 -MetricFile Logs/IngestionMetrics/Review-20260110-101639/2026-01-10.json -OutputPath Logs/IngestionMetrics/IngestionMetricsSummary-2026-01-10.csv -IncludeSiteCache -GenerateHashManifest | Rollup ingestion metrics | Logs/IngestionMetrics/IngestionMetricsSummary-2026-01-10.csv; Logs/IngestionMetrics/IngestionMetricsSummary-2026-01-10.hashes.json | Summary reflects Review-20260110-101639. |
| 2026-01-10 | Tools/Test-SharedCacheSnapshot.ps1 -Path Logs/SharedCacheSnapshot/SharedCacheSnapshot-latest.clixml -MinimumSiteCount 2 -MinimumHostCount 10 -RequiredSites WLLS,BOYO | Shared cache snapshot gate | Logs/SharedCacheSnapshot/SharedCacheSnapshot-latest.clixml | Passed (Sites=2, Hosts=37, Rows=1320). |
| 2026-01-10 | Tools/Simulate-PlanHUIRun.ps1 -TelemetryPath Logs/IngestionMetrics/Review-20260110-101639/2026-01-10.json -Sites WLLS,BOYO -BundleName UI-20260110-102241-planh-sim | Plan H simulation + bundle | Logs/TelemetryBundles/UI-20260110-102241-planh-sim; docs/performance/PlanHReport-20260110-102242.md; Logs/IngestionMetrics/Reports/UserActionSummary-2026-01-10-planh.json; Logs/IngestionMetrics/Reports/FreshnessTelemetrySummary-2026-01-10-planh.json; docs/performance/screenshots/onboarding-20260110-102242-*.png | Ready. |
| 2026-01-10 | Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -RunWarmRunRegression -RunQueueDelayHarness | Cold + warm pipeline + queue harness | Logs/IngestionMetrics/2026-01-10.json; Logs/IngestionMetrics/WarmRunTelemetry-20260110-061541.json; Logs/IngestionMetrics/QueueDelaySummary-2026-01-10.json; Logs/Reports/PortBatchReady-2026-01-10.json; Logs/Reports/PortBatchSiteDiversity-2026-01-10.json; Logs/Reports/ParserSchedulerLaunch-2026-01-10.json | Failed: Port batch diversity guard (WLLS streak 23 > 8); warm-run improvement 57.69%. |
| 2026-01-10 | Tools/Analyze-SharedCacheStoreState.ps1 -Path Logs/IngestionMetrics/2026-01-10.json -IncludeSiteBreakdown | Shared cache analyzer | Logs/IngestionMetrics/SharedCacheStoreState-20260110-062102.json | Output exported to JSON. |
| 2026-01-10 | Tools/Analyze-SiteCacheProviderReasons.ps1 -Path Logs/IngestionMetrics/2026-01-10.json -IncludeHostBreakdown | Site cache provider reasons | Logs/IngestionMetrics/SiteCacheProviderReasons-20260110-062102.json | Output exported to JSON. |
| 2026-01-10 | Tools/Analyze-WarmRunDiffHotspots.ps1 -TelemetryPath Logs/IngestionMetrics/WarmRunTelemetry-20260110-061541.json -OutputPath Logs/IngestionMetrics/WarmRunDiffHotspots-20260110-061541.csv | Warm-run diff hotspot export | Logs/IngestionMetrics/WarmRunDiffHotspots-20260110-061541.csv | DiffComparisonMs entries present (0 ms). |
| 2026-01-10 | Tools/Rollup-IngestionMetrics.ps1 -MetricFile Logs/IngestionMetrics/2026-01-10.json -OutputPath Logs/IngestionMetrics/IngestionMetricsSummary-2026-01-10.csv -IncludeSiteCache -GenerateHashManifest | Rollup ingestion metrics | Logs/IngestionMetrics/IngestionMetricsSummary-2026-01-10.csv; Logs/IngestionMetrics/IngestionMetricsSummary-2026-01-10.hashes.json | Generated summary + hash manifest. |
| 2026-01-10 | Tools/Test-ParserSchedulerFairness.ps1 -ReportPath Logs/Reports/ParserSchedulerLaunch-2026-01-10.json -MaxAllowedStreak 8 -ThrowOnViolation | Scheduler fairness guard | Logs/Reports/ParserSchedulerLaunch-2026-01-10.json | PASS. |
| 2026-01-10 | Tools/Inspect-SharedCacheSnapshot.ps1 -Raw | Shared cache snapshot summary | Logs/Reports/SharedCacheSnapshotSummary-20260110-062924.json | Snapshot contains BOYO only (Hosts=12, Rows=120). |
| 2026-01-10 | Tools/Invoke-InterfacesViewSmokeTest.ps1 -PassThru (STA) | Interfaces view UI smoke | Logs/Reports/InterfacesViewSmoke-20260110-062351.json | Success. |
| 2026-01-10 | Tools/Invoke-SearchAlertsSmokeTest.ps1 -PassThru -SuppressDialogs (STA) | Search/Alerts UI smoke | Logs/Reports/SearchAlertsSmoke-20260110-062406.json | Output written; process required manual termination to exit. |
| 2026-01-10 | Tools/Invoke-SpanViewSmokeTest.ps1 -PassThru (STA) | Span view UI smoke | Logs/Reports/SpanViewSmoke-20260110-062605.json | Success. |
| 2026-01-10 | Tools/Invoke-PlanHBundle.ps1 | Plan H bundle + readiness | Logs/TelemetryBundles/UI-20260110-planh/UI/PlanHReadiness.json | Failed: missing UserAction coverage (ScanLogs, LoadFromDb, HelpQuickstart, InterfacesView). |
| 2026-01-10 | Tools/Invoke-WarmRunRegression.ps1 -VerboseParsing -OutputPath Logs/IngestionMetrics/WarmRunTelemetry-20260110-082340.json | Warm-run regression | Logs/IngestionMetrics/WarmRunTelemetry-20260110-082340.json | ImprovementPercent 85.76%; ColdProviderCounts ADODB=2/Refreshed=35; WarmProviderCounts SharedCache=37. |
| 2026-01-10 | powershell.exe -NoProfile -Command "Invoke-Pester Modules/Tests" | Unit test pass | Console output (Passed 1629, Failed 0, Inconclusive 7) | Run under Windows PowerShell 5.1; pwsh 7 + Pester 3 yields false Should Throw failures. |
| 2026-01-09 | Get-Content Modules/CapacityPlanningModule.psm1 | Review capacity planning module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/CapacityPlanningViewModule.psm1 | Review capacity planning view module | N/A | Finding CR-009. |
| 2026-01-09 | rg -n "Add-CapacityThreshold|Set-CapacityThreshold|Remove-CapacityThreshold" Modules/CapacityPlanningViewModule.psm1 | Locate CR-009 evidence | N/A | Line 1136 reference. |
| 2026-01-09 | Get-Content Modules/ConfigTemplateModule.psm1 | Review config template module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/ConfigTemplateViewModule.psm1 | Review config template view module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Set-Content|Remove-Item" Modules/ConfigTemplateModule.psm1 | Scan for high-risk operations | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/CompareViewModule.psm1 | Review compare view module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/CompareViewModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/CommandReferenceModule.psm1 | Review command reference module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/CommandReferenceModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/CommandReferenceViewModule.psm1 | Review command reference view module | N/A | Finding CR-010. |
| 2026-01-09 | rg -n "TaskName" Modules/CommandReferenceViewModule.psm1 | Locate CR-010 evidence | N/A | Lines 218, 366. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/CommandReferenceViewModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/ChangeManagementModule.psm1 | Review change management module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/ChangeManagementModule.psm1 | Scan for high-risk operations | N/A | Set-Content usage in report/database export paths. |
| 2026-01-09 | Get-Content Modules/ChangeManagementViewModule.psm1 | Review change management view module | N/A | Finding CR-011. |
| 2026-01-09 | rg -n "Read-Host" Modules/ChangeManagementViewModule.psm1 | Locate CR-011 evidence | N/A | Lines 879, 882, 914, 934, 937, 938. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/ChangeManagementViewModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/CableDocumentationModule.psm1 | Review cable documentation module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/CableDocumentationModule.psm1 | Scan for high-risk operations | N/A | Set-Content usage in export. |
| 2026-01-09 | Get-Content Modules/CableDocumentationViewModule.psm1 | Review cable documentation view module | N/A | Findings CR-012, CR-013. |
| 2026-01-09 | rg -n "Set-CableRun" Modules/CableDocumentationViewModule.psm1 | Locate CR-012 evidence | N/A | Line 947. |
| 2026-01-09 | rg -n "SourcePanel|DestPanel" Modules/CableDocumentationViewModule.psm1 | Locate CR-013 evidence | N/A | Lines 982-983. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/CableDocumentationViewModule.psm1 | Scan for high-risk operations | N/A | Add-Type for Microsoft.VisualBasic. |
| 2026-01-09 | Get-Content Modules/AlertsViewModule.psm1 | Review alerts view module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/AlertsViewModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/AlertRuleModule.psm1 | Review alert rules module | N/A | Finding CR-014. |
| 2026-01-09 | rg -n "Rule\\.Condition" Modules/AlertRuleModule.psm1 | Locate CR-014 evidence | N/A | Line 146. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/AlertRuleModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/DocumentationContainerViewModule.psm1 | Review documentation container view module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/DocumentationContainerViewModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/DatabaseModule.psm1 | Review database module | N/A | Finding CR-015. |
| 2026-01-09 | rg -n "Open-OleDbConnectionWithFallback|Microsoft.ACE.OLEDB.12.0|Microsoft.ACE.OLEDB.16.0" Modules/DatabaseModule.psm1 | Locate CR-015 evidence | N/A | Lines 171, 315. |
| 2026-01-09 | rg -n "Write-Host" Modules/DatabaseModule.psm1 | Review debug output | N/A | Debug-only Write-Host usage. |
| 2026-01-09 | Get-Content Modules/DatabaseIndexes.psm1 | Review database index definitions | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/DatabaseConnectionPool.psm1 | Review database connection pool | N/A | Finding CR-015. |
| 2026-01-09 | Get-Content Modules/DatabaseConcurrencyModule.psm1 | Review database concurrency module | N/A | Finding CR-016. |
| 2026-01-09 | rg -n "TestId|INSERT INTO|CREATE TABLE" Modules/DatabaseConcurrencyModule.psm1 | Locate CR-016 evidence | N/A | Lines 44, 90, 204. |
| 2026-01-09 | rg -n "ACE\\.OLEDB\\.12\\.0" Modules | Scan for provider usage | N/A | Shared provider list across modules. |
| 2026-01-09 | Get-Content Modules/ConfigValidationModule.psm1 | Review config validation module | N/A | Finding CR-017. |
| 2026-01-09 | rg -n "SW-006|native vlan" Modules/ConfigValidationModule.psm1 | Locate CR-017 evidence | N/A | Lines 560-564. |
| 2026-01-09 | Get-Content Modules/IntegrationApiModule.psm1 | Review integration API module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/IntegrationApiModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/DocumentationGeneratorViewModule.psm1 | Review documentation generator view module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/DocumentationGeneratorViewModule.psm1 | Scan for high-risk operations | N/A | Add-Type/InputBox and Start-Process usage. |
| 2026-01-09 | Get-Content Modules/DocumentationGeneratorModule.psm1 | Review documentation generator module | N/A | Finding CR-018. |
| 2026-01-09 | rg -n "\\^#" Modules/DocumentationGeneratorModule.psm1 | Locate CR-018 evidence | N/A | Lines 1203-1205, 1691-1693. |
| 2026-01-09 | Get-Content Modules/IPAMModule.psm1 | Review IPAM module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/IPAMViewModule.psm1 | Review IPAM view module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/LogAnalysisModule.psm1 | Review log analysis module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/LogAnalysisViewModule.psm1 | Review log analysis view module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/LogIngestionModule.psm1 | Review log ingestion module | N/A | Finding CR-008. |
| 2026-01-09 | Get-Content Modules/InterfaceCommon.psm1 | Review interface helper module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/InterfaceModule.psm1 | Review interfaces module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/InventoryModule.psm1 | Review inventory module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/InventoryViewModule.psm1 | Review inventory view module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/DecisionTreeModule.psm1 | Review decision tree engine | N/A | Finding CR-007. |
| 2026-01-09 | rg -n "Invoke-Expression" Modules/DecisionTreeModule.psm1 | Locate CR-007 evidence | N/A | Line 512 reference. |
| 2026-01-09 | Get-Content Modules/DecisionTreeViewModule.psm1 | Review decision tree view | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/DeviceInsightsModule.psm1 | Review device insights module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/DeviceDetailsModule.psm1 | Review device details module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/DeviceCatalogModule.psm1 | Review device catalog module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/CiscoModule.psm1 | Review vendor parser module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/AristaModule.psm1 | Review vendor parser module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/ArubaModule.psm1 | Review vendor parser module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/BrocadeModule.psm1 | Review vendor parser module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/JuniperModule.psm1 | Review vendor parser module | N/A | Finding CR-006. |
| 2026-01-09 | rg -n "\\(\\?:interface" Modules/JuniperModule.psm1 | Locate regex for CR-006 | N/A | Line 203 reference. |
| 2026-01-09 | Get-Content Modules/PaloAltoModule.psm1 | Review vendor parser module | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/VendorCommandTemplates.psm1 | Review vendor command templates | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/InfrastructureContainerViewModule.psm1 | Review infrastructure container view module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/InfrastructureContainerViewModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/FleetHealthModule.psm1 | Review fleet health module | N/A | Finding CR-019. |
| 2026-01-09 | rg -n "\\?\\s*'Passed'" Modules/FleetHealthModule.psm1 | Locate CR-019 evidence | N/A | Lines 798, 839, 881. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/FleetHealthModule.psm1 | Scan for high-risk operations | N/A | Set-Content usage in summary/config exports. |
| 2026-01-09 | rg -n "FleetHealthModule" | Review module import usage | N/A | Import in Tools/Invoke-DailyHealthCheck.ps1. |
| 2026-01-09 | Get-Content Modules/FilterStateModule.psm1 | Review filter state module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/FilterStateModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/WarmRun.Telemetry.psm1 | Review warm run telemetry module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/WarmRun.Telemetry.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/ViewStateService.psm1 | Review view state service module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/ViewStateService.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/ViewCompositionModule.psm1 | Review view composition module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/ViewCompositionModule.psm1 | Scan for high-risk operations | N/A | Set-Content usage in export preference save. |
| 2026-01-09 | Get-Content Modules/VerificationModule.psm1 | Review verification module | N/A | No findings. |
| 2026-01-09 | rg -n "improvementDisplay" Modules/VerificationModule.psm1 | Confirm improvement display formatting | N/A | Line 47. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/VerificationModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/TopologyViewModule.psm1 | Review topology view module | N/A | Findings CR-020, CR-021. |
| 2026-01-09 | rg -n "interfaceCache" Modules/TopologyViewModule.psm1 | Locate CR-020 evidence | N/A | Lines 306-307. |
| 2026-01-09 | rg -n "Delete-SelectedLayout|Remove-TopologyLayout" Modules/TopologyViewModule.psm1 | Locate CR-021 evidence | N/A | Lines 729, 751. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/TopologyViewModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/TopologyModule.psm1 | Review topology module | N/A | No findings. |
| 2026-01-09 | rg -n "Remove-TopologyLayout" Modules/TopologyModule.psm1 | Confirm missing layout removal function | N/A | No matches. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/TopologyModule.psm1 | Scan for high-risk operations | N/A | Remove-Item/Add-Type usage in Visio export. |
| 2026-01-09 | Get-Content Modules/ToolsContainerViewModule.psm1 | Review tools container view module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/ToolsContainerViewModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/ThemeModule.psm1 | Review theme module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/ThemeModule.psm1 | Scan for high-risk operations | N/A | Add-Type usage for PresentationFramework and converters. |
| 2026-01-09 | Get-Content Modules/TemplatesViewModule.psm1 | Review templates view module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/TemplatesViewModule.psm1 | Scan for high-risk operations | N/A | Remove-Item usage for template deletion. |
| 2026-01-09 | Get-Content Modules/TemplatesModule.psm1 | Review templates module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/TemplatesModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/TelemetryModule.psm1 | Review telemetry module | N/A | No findings. |
| 2026-01-09 | rg -n "Save-StTelemetryBuffer" Modules/TelemetryModule.psm1 | Confirm telemetry save helper syntax | N/A | Line 298. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/TelemetryModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/SummaryViewModule.psm1 | Review summary view module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/SummaryViewModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/StatisticsModule.psm1 | Review statistics module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/StatisticsModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/StabilityTestModule.psm1 | Review stability test module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/StabilityTestModule.psm1 | Scan for high-risk operations | N/A | Set-Content usage for report output. |
| 2026-01-09 | Get-Content Modules/SpanViewModule.psm1 | Review span view module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/SpanViewModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/SearchInterfacesViewModule.psm1 | Review search interfaces view module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/SearchInterfacesViewModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/PortReorgViewModule.psm1 | Review port reorg view module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/PortReorgViewModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/PortReorgModule.psm1 | Review port reorg module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/PortReorgModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/PortNormalization.psm1 | Review port normalization module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/PortNormalization.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/OperationsContainerViewModule.psm1 | Review operations container view module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/OperationsContainerViewModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/NetworkCalculatorViewModule.psm1 | Review network calculator view module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/NetworkCalculatorViewModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/NetworkCalculatorModule.psm1 | Review network calculator module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/NetworkCalculatorModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/ModulesManifest.psd1 | Review modules manifest | N/A | No findings. |
| 2026-01-09 | Get-Content Modules/ModuleLoaderModule.psm1 | Review module loader module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/ModuleLoaderModule.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Modules/MainWindow.Services.psm1 | Review main window services module | N/A | No findings. |
| 2026-01-09 | rg -n "Invoke-Expression|Add-Type|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Set-Content|Remove-Item" Modules/MainWindow.Services.psm1 | Scan for high-risk operations | N/A | No matches. |
| 2026-01-09 | Get-Content Views/TopologyView.xaml | Review topology view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/ToolsContainerView.xaml | Review tools container view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/TemplatesView.xaml | Review templates view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/SummaryView.xaml | Review summary view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/SpanView.xaml | Review span view XAML | N/A | No findings. |
| 2026-01-09 | rg --files Views | Enumerate view XAML files | N/A | Review batch planning. |
| 2026-01-09 | Get-Content Views/SearchInterfacesView.xaml | Review search interfaces view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/QuickNavigationDialog.xaml | Review quick navigation dialog XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/PortReorgWindow.xaml | Review port reorg window XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/OperationsContainerView.xaml | Review operations container view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/NetworkCalculatorView.xaml | Review network calculator view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/LogAnalysisView.xaml | Review log analysis view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/AlertsView.xaml | Review alerts view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/CapacityPlanningView.xaml | Review capacity planning view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/CableDocumentationView.xaml | Review cable documentation view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/ChangeManagementView.xaml | Review change management view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/IPAMView.xaml | Review IPAM view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/InventoryView.xaml | Review inventory view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/InterfacesView.xaml | Review interfaces view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/InfrastructureContainerView.xaml | Review infrastructure container view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/HelpWindow.xaml | Review help window XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/DocumentationGeneratorView.xaml | Review documentation generator view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/DocumentationContainerView.xaml | Review documentation container view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/DecisionTreeView.xaml | Review decision tree view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/ConfigTemplateView.xaml | Review config template view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/CompareView.xaml | Review compare view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Views/CommandReferenceView.xaml | Review command reference view XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Main/MainWindow.xaml | Review main window XAML | N/A | No findings. |
| 2026-01-09 | Get-Content Main/MainWindow.ps1 | Review main window logic | N/A | Finding CR-022. |
| 2026-01-09 | rg -n "Invoke-Expression|Start-Process|Invoke-WebRequest|Invoke-RestMethod|Add-Type|Set-Content|Remove-Item|Copy-Item|Out-File" Main/MainWindow.ps1 | Scan for high-risk operations | N/A | Start-Process/Remove-Item/Set-Content usage reviewed. |
| 2026-01-09 | rg -n "Reset-ParserCachesForRefresh|Start-ParserBackgroundJob" Main/MainWindow.ps1 | Locate CR-022 evidence | N/A | Lines 2019, 2022. |
| 2026-01-09 | Get-Content Tools/Invoke-StateTracePipeline.ps1 -TotalCount 400 | Review pipeline harness (segment 1) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-StateTracePipeline.ps1 \| Select-Object -Skip 400 -First 400 | Review pipeline harness (segment 2) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-StateTracePipeline.ps1 \| Select-Object -Skip 800 -First 400 | Review pipeline harness (segment 3) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-StateTracePipeline.ps1 \| Select-Object -Skip 1200 -First 400 | Review pipeline harness (segment 4) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-StateTracePipeline.ps1 \| Select-Object -Skip 1600 -First 200 | Review pipeline harness (segment 5) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-WarmRunRegression.ps1 | Review warm-run regression wrapper | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-StateTraceVerification.ps1 -TotalCount 400 | Review verification harness (segment 1) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-StateTraceVerification.ps1 \| Select-Object -Skip 400 -First 400 | Review verification harness (segment 2) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-StateTraceVerification.ps1 \| Select-Object -Skip 800 -First 200 | Review verification harness (segment 3) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-StateTraceScheduledVerification.ps1 -TotalCount 300 | Review scheduled verification harness (segment 1) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-StateTraceScheduledVerification.ps1 \| Select-Object -Skip 300 -First 200 | Review scheduled verification harness (segment 2) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-AllChecks.ps1 -TotalCount 300 | Review all-checks harness (segment 1) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-AllChecks.ps1 \| Select-Object -Skip 300 -First 300 | Review all-checks harness (segment 2) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-AllChecks.ps1 \| Select-Object -Skip 500 -First 200 | Review all-checks harness (segment 3) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-CIHarness.ps1 -TotalCount 250 | Review CI harness (segment 1) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-CIHarness.ps1 \| Select-Object -Skip 250 -First 200 | Review CI harness (segment 2) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-CIHarness.ps1 -Tail 80 | Review CI harness (tail) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-CablesSmokeTest.ps1 -TotalCount 200 | Review cables smoke test (segment 1) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-CablesSmokeTest.ps1 \| Select-Object -Skip 200 -First 200 | Review cables smoke test (segment 2) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-DesktopUIHarness.ps1 | Review desktop UI harness | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-SpanViewSmokeTest.ps1 | Review span view smoke test | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-SearchAlertsSmokeTest.ps1 -TotalCount 200 | Review search/alerts smoke test (segment 1) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-SearchAlertsSmokeTest.ps1 \| Select-Object -Skip 200 -First 200 | Review search/alerts smoke test (segment 2) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-SearchAlertsSmokeTest.ps1 \| Select-Object -Skip 380 -First 60 | Review search/alerts smoke test (tail) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-ScheduledHarnessSmoke.ps1 | Review scheduled harness smoke runner | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-WarmRunTelemetry.ps1 -TotalCount 400 | Review warm-run telemetry harness (segment 1) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-WarmRunTelemetry.ps1 \| Select-Object -Skip 400 -First 400 | Review warm-run telemetry harness (segment 2) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-WarmRunTelemetry.ps1 \| Select-Object -Skip 800 -First 400 | Review warm-run telemetry harness (segment 3) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-WarmRunTelemetry.ps1 \| Select-Object -Skip 1200 -First 400 | Review warm-run telemetry harness (segment 4) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-WarmRunTelemetry.ps1 \| Select-Object -Skip 1600 -First 400 | Review warm-run telemetry harness (segment 5) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-WarmRunTelemetry.ps1 \| Select-Object -Skip 2000 -First 400 | Review warm-run telemetry harness (segment 6) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-WarmRunTelemetry.ps1 \| Select-Object -Skip 2400 -First 200 | Review warm-run telemetry harness (segment 7) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-WarmRunTelemetry.ps1 \| Select-Object -Skip 2600 -First 200 | Review warm-run telemetry harness (segment 8) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-WarmRunTelemetry.ps1 \| Select-Object -Skip 2800 -First 400 | Review warm-run telemetry harness (segment 9) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-WarmRunTelemetry.ps1 \| Select-Object -Skip 3200 -First 200 | Review warm-run telemetry harness (segment 10) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-WarmRunTelemetry.ps1 \| Select-Object -Skip 3400 -First 200 | Review warm-run telemetry harness (segment 11) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-WarmRunTelemetry.ps1 \| Select-Object -Skip 3600 -First 200 | Review warm-run telemetry harness (segment 12) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-WarmRunTelemetry.ps1 \| Select-Object -Skip 3700 -First 200 | Review warm-run telemetry harness (segment 13) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-WarmRunTelemetry.ps1 \| Select-Object -Skip 3750 -First 120 | Review warm-run telemetry harness (segment 14) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-WarmRunTelemetry.ps1 -Tail 120 | Review warm-run telemetry harness (tail) | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-WarmRunTelemetry.psm1 | Review warm-run telemetry harness (typo) | N/A | File not found. |
| 2026-01-09 | (Get-Content Tools/Invoke-WarmRunTelemetry.ps1 \| Measure-Object -Line).Lines | Measure warm-run telemetry script length | N/A | 3781 lines. |
| 2026-01-09 | rg -n "Invoke-Expression\|Start-Process\|Invoke-WebRequest\|Invoke-RestMethod\|Add-Type\|Remove-Item\|Set-Content\|Out-File\|Copy-Item" Tools/Invoke-WarmRunTelemetry.ps1 | Scan for high-risk operations | N/A | Copy-Item/Remove-Item usage reviewed. |
| 2026-01-09 | (Get-Content Tools/Check-PlanHStatus.ps1 \| Measure-Object -Line).Lines | Measure Plan H status script length | N/A | 37 lines. |
| 2026-01-09 | (Get-Content Tools/Capture-PlanHScreenshots.ps1 \| Measure-Object -Line).Lines | Measure Plan H screenshots script length | N/A | 112 lines. |
| 2026-01-09 | (Get-Content Tools/AutoCapture-PlanHUI.ps1 \| Measure-Object -Line).Lines | Measure Plan H UI automation script length | N/A | 171 lines. |
| 2026-01-09 | (Get-Content Tools/Generate-PlanHReport.ps1 \| Measure-Object -Line).Lines | Measure Plan H report script length | N/A | 62 lines. |
| 2026-01-09 | (Get-Content Tools/Invoke-PlanHChecks.ps1 \| Measure-Object -Line).Lines | Measure Plan H checks script length | N/A | 40 lines. |
| 2026-01-09 | (Get-Content Tools/Invoke-PlanHBundle.ps1 \| Measure-Object -Line).Lines | Measure Plan H bundle script length | N/A | 76 lines. |
| 2026-01-09 | (Get-Content Tools/Run-PlanHHeadless.ps1 \| Measure-Object -Line).Lines | Measure Plan H headless script length | N/A | 24 lines. |
| 2026-01-09 | (Get-Content Tools/Simulate-PlanHUIRun.ps1 \| Measure-Object -Line).Lines | Measure Plan H simulation script length | N/A | 83 lines. |
| 2026-01-09 | Get-Content Tools/Check-PlanHStatus.ps1 | Review Plan H status helper | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Capture-PlanHScreenshots.ps1 | Review Plan H screenshot generator | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/AutoCapture-PlanHUI.ps1 | Review Plan H UI automation | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Generate-PlanHReport.ps1 | Review Plan H report generator | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-PlanHChecks.ps1 | Review Plan H checks runner | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-PlanHBundle.ps1 | Review Plan H bundle builder | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Run-PlanHHeadless.ps1 | Review Plan H headless wrapper | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Simulate-PlanHUIRun.ps1 | Review Plan H simulation script | N/A | Finding CR-023. |
| 2026-01-09 | rg -n "TelemetryPath\|Write-StTelemetryEvent" Tools/Simulate-PlanHUIRun.ps1 | Locate CR-023 evidence | N/A | Lines 4, 58, 76, 81, 88-89, 93. |
| 2026-01-09 | rg -n "function Write-StTelemetryEvent\|Write-StTelemetryEvent" Modules/TelemetryModule.psm1 | Confirm telemetry write path behavior | N/A | Definition at line 249. |
| 2026-01-09 | Get-Content Modules/TelemetryModule.psm1 \| Select-Object -Skip 220 -First 120 | Review telemetry write path implementation | N/A | Get-TelemetryLogPath used for writes. |
| 2026-01-09 | rg -n "function Get-TelemetryLogPath\|Get-TelemetryLogPath" Modules/TelemetryModule.psm1 | Locate telemetry path helper | N/A | Definition at line 126. |
| 2026-01-09 | Get-Content Modules/TelemetryModule.psm1 \| Select-Object -Skip 100 -First 80 | Review telemetry log path helper | N/A | Uses STATETRACE_TELEMETRY_DIR override. |
| 2026-01-09 | (Get-Content Tools/Show-PlanHReadiness.ps1 \| Measure-Object -Line).Lines | Measure Plan H readiness display script length | N/A | 48 lines. |
| 2026-01-09 | (Get-Content Tools/Test-PlanHReadiness.ps1 \| Measure-Object -Line).Lines | Measure Plan H readiness test script length | N/A | 124 lines. |
| 2026-01-09 | Get-Content Tools/Show-PlanHReadiness.ps1 | Review Plan H readiness display helper | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Test-PlanHReadiness.ps1 | Review Plan H readiness validator | N/A | No findings. |
| 2026-01-09 | (Get-Content Tools/Build-RoutingLogIndex.ps1 \| Measure-Object -Line).Lines | Measure routing log index script length | N/A | 293 lines. |
| 2026-01-09 | (Get-Content Tools/Bootstrap-DevSeat.ps1 \| Measure-Object -Line).Lines | Measure dev seat bootstrap script length | N/A | 278 lines. |
| 2026-01-09 | (Get-Content Tools/AnalyzerStats.psm1 \| Measure-Object -Line).Lines | Measure analyzer stats helper length | N/A | 93 lines. |
| 2026-01-09 | Get-Content Tools/Build-RoutingLogIndex.ps1 | Review routing log index builder | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Bootstrap-DevSeat.ps1 | Review developer seat bootstrapper | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/AnalyzerStats.psm1 | Review analyzer stats helper | N/A | No findings. |
| 2026-01-09 | (Get-Content Tools/Analyze-WarmRunDiffHotspots.ps1 \| Measure-Object -Line).Lines | Measure warm run diff hotspot analyzer length | N/A | 118 lines. |
| 2026-01-09 | (Get-Content Tools/Analyze-UserActionTelemetry.ps1 \| Measure-Object -Line).Lines | Measure user action telemetry analyzer length | N/A | 136 lines. |
| 2026-01-09 | (Get-Content Tools/Analyze-SiteCacheProviderReasons.ps1 \| Measure-Object -Line).Lines | Measure site cache provider reasons analyzer length | N/A | 233 lines. |
| 2026-01-09 | Get-Content Tools/Analyze-WarmRunDiffHotspots.ps1 | Review warm run diff hotspot analyzer | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Analyze-UserActionTelemetry.ps1 | Review user action telemetry analyzer | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Analyze-SiteCacheProviderReasons.ps1 | Review site cache provider reasons analyzer | N/A | No findings. |
| 2026-01-09 | (Get-Content Tools/Analyze-SharedCacheStoreState.ps1 \| Measure-Object -Line).Lines | Measure shared cache store analyzer length | N/A | 231 lines. |
| 2026-01-09 | (Get-Content Tools/Analyze-PortBatchSiteMix.ps1 \| Measure-Object -Line).Lines | Measure port batch site mix analyzer length | N/A | 169 lines. |
| 2026-01-09 | (Get-Content Tools/Analyze-PortBatchReadyTelemetry.ps1 \| Measure-Object -Line).Lines | Measure port batch readiness analyzer length | N/A | 236 lines. |
| 2026-01-09 | (Get-Content Tools/Analyze-PortBatchIntervals.ps1 \| Measure-Object -Line).Lines | Measure port batch interval analyzer length | N/A | 133 lines. |
| 2026-01-09 | (Get-Content Tools/Analyze-PortBatchGapTimeline.ps1 \| Measure-Object -Line).Lines | Measure port batch gap timeline analyzer length | N/A | 218 lines. |
| 2026-01-09 | (Get-Content Tools/Analyze-PortBatchGapBreakdown.ps1 \| Measure-Object -Line).Lines | Measure port batch gap breakdown analyzer length | N/A | 147 lines. |
| 2026-01-09 | Get-Content Tools/Analyze-SharedCacheStoreState.ps1 | Review shared cache store analyzer | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Analyze-PortBatchSiteMix.ps1 | Review port batch site mix analyzer | N/A | Finding CR-024. |
| 2026-01-09 | Get-Content Tools/Analyze-PortBatchReadyTelemetry.ps1 | Review port batch ready telemetry analyzer | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Analyze-PortBatchIntervals.ps1 | Review port batch interval analyzer | N/A | Finding CR-024. |
| 2026-01-09 | Get-Content Tools/Analyze-PortBatchGapTimeline.ps1 | Review port batch gap timeline analyzer | N/A | Finding CR-024. |
| 2026-01-09 | Get-Content Tools/Analyze-PortBatchGapBreakdown.ps1 | Review port batch gap breakdown analyzer | N/A | No findings. |
| 2026-01-09 | rg -n -F '? $startUtc' Tools/Analyze-PortBatchSiteMix.ps1 | Locate CR-024 evidence | N/A | Line 160. |
| 2026-01-09 | rg -n -F '? $startUtc' Tools/Analyze-PortBatchIntervals.ps1 | Locate CR-024 evidence | N/A | Line 119. |
| 2026-01-09 | rg -n -F '? $startUtc' Tools/Analyze-PortBatchGapTimeline.ps1 | Locate CR-024 evidence | N/A | Line 178. |
| 2026-01-09 | (Get-Content Tools/Analyze-ParserSchedulerLaunch.ps1 \| Measure-Object -Line).Lines | Measure parser scheduler launch analyzer length | N/A | 252 lines. |
| 2026-01-09 | (Get-Content Tools/Analyze-InterfaceSyncTiming.ps1 \| Measure-Object -Line).Lines | Measure interface sync timing analyzer length | N/A | 152 lines. |
| 2026-01-09 | (Get-Content Tools/Analyze-FreshnessTelemetry.ps1 \| Measure-Object -Line).Lines | Measure freshness telemetry analyzer length | N/A | 138 lines. |
| 2026-01-09 | (Get-Content Tools/Analyze-DispatchHarnessSweep.ps1 \| Measure-Object -Line).Lines | Measure dispatch harness sweep analyzer length | N/A | 143 lines. |
| 2026-01-09 | (Get-Content Tools/Analyze-DispatcherGaps.ps1 \| Measure-Object -Line).Lines | Measure dispatcher gaps analyzer length | N/A | 156 lines. |
| 2026-01-09 | (Get-Content Tools/Add-PortBatchReadyTelemetry.ps1 \| Measure-Object -Line).Lines | Measure PortBatchReady synthesis tool length | N/A | 190 lines. |
| 2026-01-09 | Get-Content Tools/Analyze-ParserSchedulerLaunch.ps1 | Review parser scheduler launch analyzer | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Analyze-InterfaceSyncTiming.ps1 | Review interface sync timing analyzer | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Analyze-FreshnessTelemetry.ps1 | Review freshness telemetry analyzer | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Analyze-DispatchHarnessSweep.ps1 | Review dispatch harness sweep analyzer | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Analyze-DispatcherGaps.ps1 | Review dispatcher gap analyzer | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Add-PortBatchReadyTelemetry.ps1 | Review PortBatchReady synthesis tool | N/A | No findings. |
| 2026-01-09 | (Get-Content Tools/Invoke-IncrementalLoadingChecklist.ps1 \| Measure-Object -Line).Lines | Measure incremental loading checklist length | N/A | 195 lines. |
| 2026-01-09 | (Get-Content Tools/Get-ModuleImportGraph.ps1 \| Measure-Object -Line).Lines | Measure module import graph tool length | N/A | 264 lines. |
| 2026-01-09 | (Get-Content Tools/Generate-QueueDelaySummary.ps1 \| Measure-Object -Line).Lines | Measure queue delay summary tool length | N/A | 85 lines. |
| 2026-01-09 | (Get-Content Tools/Invoke-IncidentDrill.ps1 \| Measure-Object -Line).Lines | Measure incident drill tool length | N/A | 230 lines. |
| 2026-01-09 | (Get-Content Tools/Generate-IncrementalPerformanceReport.ps1 \| Measure-Object -Line).Lines | Measure incremental performance report tool length | N/A | 168 lines. |
| 2026-01-09 | Get-Content Tools/Invoke-IncrementalLoadingChecklist.ps1 | Review incremental loading checklist tool | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Get-ModuleImportGraph.ps1 | Review module import graph tool | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Generate-QueueDelaySummary.ps1 | Review queue delay summary tool | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-IncidentDrill.ps1 | Review incident drill tool | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Generate-IncrementalPerformanceReport.ps1 | Review incremental performance report tool | N/A | No findings. |
| 2026-01-09 | (Get-Content Tools/Invoke-HeadlessRun.ps1 \| Measure-Object -Line).Lines | Measure headless run placeholder length | N/A | 3 lines. |
| 2026-01-09 | (Get-Content Tools/Invoke-FeatureFlagAudit.ps1 \| Measure-Object -Line).Lines | Measure feature flag audit tool length | N/A | 230 lines. |
| 2026-01-09 | (Get-Content Tools/Invoke-DispatcherHarnessWithEvidence.ps1 \| Measure-Object -Line).Lines | Measure dispatcher harness evidence tool length | N/A | 230 lines. |
| 2026-01-09 | (Get-Content Tools/Export-RoutingOfflineBundle.ps1 \| Measure-Object -Line).Lines | Measure routing offline bundle export tool length | N/A | 277 lines. |
| 2026-01-09 | (Get-Content Tools/Expand-RoutingOfflineBundle.ps1 \| Measure-Object -Line).Lines | Measure routing offline bundle expand tool length | N/A | 225 lines. |
| 2026-01-09 | Get-Content Tools/Invoke-HeadlessRun.ps1 | Review headless run placeholder | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-FeatureFlagAudit.ps1 | Review feature flag audit tool | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Invoke-DispatcherHarnessWithEvidence.ps1 | Review dispatcher harness evidence tool | N/A | Finding CR-025. |
| 2026-01-09 | Get-Content Tools/Export-RoutingOfflineBundle.ps1 | Review routing offline bundle export tool | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Expand-RoutingOfflineBundle.ps1 | Review routing offline bundle expand tool | N/A | No findings. |
| 2026-01-09 | rg --files -g 'Tools/Analyze-QueueDelaySummary.ps1' | Locate CR-025 script reference | N/A | No matches (script missing). |
| 2026-01-09 | rg --files -g 'Tools/*QueueDelaySummary*.ps1' | Confirm queue delay summary script name | N/A | Generate-QueueDelaySummary.ps1 present. |
| 2026-01-09 | rg --files docs \| sort | Enumerate docs inventory | N/A | Review planning coverage. |
| 2026-01-09 | rg --files -g "*.ps1" -g "*.psm1" -g "*.psd1" -g "*.cs" -g "*.xaml" -g "*.json" -g "*.yml" -g "*.yaml" | Enumerate code/config files | N/A | Coverage map refresh. |
| 2026-01-09 | Get-ChildItem -Force | List repo root contents | N/A | Confirmed .github/workflows. |
| 2026-01-09 | Get-ChildItem -Force .github\workflows | List CI workflows | N/A | Identified ci.yml. |
| 2026-01-09 | Get-Content .github\workflows\ci.yml | Review CI workflow | N/A | No findings. |
| 2026-01-09 | Get-Content Tools/Start-StateTraceApi.ps1 \| ForEach-Object -Begin {$i=1} {"{0,4}: {1}" -f $i++, $_} | Capture API auth evidence | N/A | Finding CR-027. |
| 2026-01-09 | rg -n " \\? " Tools -g "*.ps1" -g "*.psm1" | Locate PS7 ternary usage | N/A | Finding CR-026. |
| 2026-01-09 | Get-Content Tools/Invoke-SharedCacheWarmup.ps1 \| ForEach-Object -Begin {$i=1} {"{0,4}: {1}" -f $i++, $_} | Capture shared cache warmup ternary lines | N/A | Finding CR-026. |
| 2026-01-09 | Get-Content Tools/Update-QueueDelayHistory.ps1 \| ForEach-Object -Begin {$i=1} {"{0,4}: {1}" -f $i++, $_} | Capture missing Get-SampleCount import | N/A | Finding CR-028. |
| 2026-01-09 | rg -n -g "Switch-*.ps1" "C:\\\\|COM\\d+|192\\.168" Tools | Locate hardcoded serial ports/paths in switch scripts | N/A | Finding CR-029. |
| 2026-01-09 | Get-Content Tools/Switch-CreateProperLog.ps1 \| ForEach-Object -Begin {$i=1} {"{0,3}: {1}" -f $i++, $_} | Capture hardcoded path evidence | N/A | Finding CR-029. |
| 2026-01-09 | Get-Content Tools/Switch-Session.ps1 \| ForEach-Object -Begin {$i=1} {"{0,3}: {1}" -f $i++, $_} | Capture COM8 hardcoding evidence | N/A | Finding CR-029. |
| 2026-01-09 | Get-Content Tools/Switch-ConfigRadius.ps1 \| ForEach-Object -Begin {$i=1} {"{0,3}: {1}" -f $i++, $_} | Capture embedded credentials evidence | N/A | Finding CR-030. |
| 2026-01-09 | Get-Content Troubleshooting/Invoke-StateTraceDiagnostics.ps1 \| ForEach-Object -Begin {$i=1} {"{0,4}: {1}" -f $i++, $_} | Capture diagnostics syntax error | N/A | Finding CR-031. |
| 2026-01-09 | rg -n "Serial|Base MAC|Processor board ID|System Serial" Tests/Fixtures/LiveSwitch/LAB-C9200L-AS-01.log | Capture fixture identifiers | N/A | Finding CR-032. |
| 2026-01-09 | Get-ChildItem Data -Filter *.accdb -Recurse -File \| Select-Object -First 10 | Enumerate runtime Access databases | N/A | Finding CR-033. |
| 2026-01-09 | Get-Content docs/adr/0005-autonomous-development-and-ci.md \| ForEach-Object -Begin {$i=1} {"{0,3}: {1}" -f $i++, $_} | Capture ADR placeholder evidence | N/A | Finding CR-034. |
| 2026-01-09 | Get-Content docs/adr/0007-shared-cache-snapshot-governance.md \| ForEach-Object -Begin {$i=1} {"{0,3}: {1}" -f $i++, $_} | Capture ADR PlanQ link evidence | N/A | Finding CR-035. |
| 2026-01-09 | Get-Content docs/runbooks/Schedule_Daily_Rollup.md \| ForEach-Object -Begin {$i=1} {"{0,3}: {1}" -f $i++, $_} | Capture runbook line continuation issue | N/A | Finding CR-036. |
| 2026-01-09 | Get-Content docs/StateTrace_Quarterly_Roadmap.md \| ForEach-Object -Begin {$i=1} {"{0,3}: {1}" -f $i++, $_} | Capture roadmap encoding issues | N/A | Finding CR-037. |
| 2026-01-09 | powershell.exe -NoProfile -Command "Invoke-Pester Modules/Tests" | Unit test pass | Console output (Passed 1626, Inconclusive 10) | Inconclusive tests due to missing DiffPrototype + Telemetry bundle fixtures. |
| 2026-01-09 | Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -RunWarmRunRegression | Cold + warm ingestion | Logs/IngestionMetrics/<file>.json | Deferred; not executed in this session. |
| 2026-01-09 | rg -n "schedulerPollMs|Start-Sleep" Modules/ParserRunspaceModule.psm1 | Review scheduler polling behavior | N/A | Revalidated CR-003. |
| 2026-01-09 | Get-Content Modules/ParserRunspaceModule.psm1 \| Select-Object -Skip 1035 -First 150 | Review scheduler loop details | N/A | Confirmed fixed polling + WaitAny usage. |
| 2026-01-09 | Get-Content Tools/Start-StateTraceApi.ps1 | Verify anonymous warning addition | N/A | Confirmed warning for -AllowAnonymous. |

## Telemetry artifacts
| Artifact | Path | Plan gate | Notes |
|----------|------|-----------|-------|
| IngestionMetrics | Logs/IngestionMetrics/<file>.json | Plan A/B/E | |
| WarmRunTelemetry | Logs/IngestionMetrics/WarmRunTelemetry-<file>.json | Plan B/G | |
| SharedCacheSummary | Logs/SharedCacheSnapshot/SharedCacheSnapshot-*-summary.json | Plan G | |

## Diagnostics/analysis outputs
| Tool | Output path | Notes |
|------|-------------|-------|
| Tools/Analyze-SharedCacheStoreState.ps1 | Logs/Reports/<file>.json | |
| Tools/Analyze-SiteCacheProviderReasons.ps1 | Logs/Reports/<file>.json | |
| Tools/Analyze-InterfaceSyncTiming.ps1 | Logs/Reports/<file>.json | |
| Tools/Test-ParserSchedulerFairness.ps1 | Logs/Reports/<file>.json | |

## UI evidence (if applicable)
| Scenario | Evidence path | Notes |
|----------|---------------|-------|
| Interfaces view smoke | Logs/Reports/<file>.json | |
| Compare view smoke | Logs/Reports/<file>.json | |



