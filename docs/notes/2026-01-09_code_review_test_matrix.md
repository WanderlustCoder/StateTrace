# Code review test matrix (2026-01-09)

This matrix maps subsystems to required tests, harnesses, and evidence artifacts.
Note: Run `Invoke-Pester` in Windows PowerShell 5.1 (`powershell.exe`); Pester 3 under `pwsh` can report false Should Throw failures.

## Core tests (always)
| Subsystem | Command | Evidence |
|-----------|---------|----------|
| All modules | `Invoke-Pester Modules/Tests` | Pester summary in session log |

## Parser/ingestion (Plan B/E/G gates)
| Subsystem | Command | Evidence |
|-----------|---------|----------|
| Parser/ingestion | `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -RunWarmRunRegression -RunQueueDelayHarness` | `Logs/IngestionMetrics/Review-20260110-101639/2026-01-10.json`, `Logs/IngestionMetrics/WarmRunTelemetry-20260110-101650.json`, `Logs/Reports/TelemetryIntegrity-20260110-101823.txt` |
| DatabaseWriteLatency retest (cold) | `Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -RunQueueDelayHarness -SharedCacheSnapshotDirectory Logs/SharedCacheSnapshot -DisablePreserveRunspace -DisableSkipSiteCacheUpdate -RequireTelemetryIntegrity` | `Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/2026-01-10.json`, `Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/IngestionMetricsSummary-2026-01-10.csv`, `Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/QueueDelaySummary-2026-01-10.json` |
| Shared cache diagnostics | `Tools/Analyze-SharedCacheStoreState.ps1 -Path Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/2026-01-10.json -IncludeSiteBreakdown` | `Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/SharedCacheStoreState-20260110-114623.json` |
| Shared cache reasons | `Tools/Analyze-SiteCacheProviderReasons.ps1 -Path Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/2026-01-10.json -IncludeHostBreakdown` | `Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/SiteCacheProviderReasons-20260110-114623.json` |
| Scheduler fairness | `Tools/Test-ParserSchedulerFairness.ps1 -ReportPath Logs/Reports/ParserSchedulerLaunch-<date>.json -MaxAllowedStreak 8 -ThrowOnViolation` | Fairness report JSON |

## Queue/port batch gates (Plan A/D/I)
| Subsystem | Command | Evidence |
|-----------|---------|----------|
| Queue delay | `Tools/Invoke-StateTracePipeline.ps1 -RunQueueDelayHarness` | `Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/QueueDelaySummary-2026-01-10.json` |
| PortBatchReady | `Tools/Analyze-PortBatchReadyTelemetry.ps1 -Path Logs/IngestionMetrics/<file>.json` | Analyzer output JSON |

## UI harnesses (Plan H, UI changes)
| Subsystem | Command | Evidence |
|-----------|---------|----------|
| Interfaces view | `Tools/Invoke-InterfacesViewSmokeTest.ps1` | Harness summary JSON/log |
| Search/Alerts | `Tools/Invoke-SearchAlertsSmokeTest.ps1` | Harness summary JSON/log |
| Span view | `Tools/Invoke-SpanViewSmokeTest.ps1` | Harness summary JSON/log |
| Plan H bundle | `Tools/Simulate-PlanHUIRun.ps1 -TelemetryPath Logs/IngestionMetrics/Review-20260110-101639/2026-01-10.json -Sites WLLS,BOYO` | `Logs/TelemetryBundles/UI-20260110-102241-planh-sim` |

## Release governance (Plan G)
| Subsystem | Command | Evidence |
|-----------|---------|----------|
| Verification harness | `Tools/Invoke-StateTraceVerification.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs -GenerateSharedCacheDiagnostics -GenerateDiffHotspotReport -ForcePortBatchReadySynthesis` | `Logs/IngestionMetrics/WarmRunTelemetry-20260110-150106.json`, `Logs/IngestionMetrics/QueueDelaySummary-20260110-150417.json`, `Logs/SharedCacheDiagnostics/SharedCacheStoreState-20260110-150106.json`, `Logs/SharedCacheDiagnostics/SiteCacheProviderReasons-20260110-150106.json` |
| Bundle readiness | `Tools/Test-TelemetryBundleReadiness.ps1 -BundlePath Logs/TelemetryBundles/Review-20260110-ST-G-012 -Area Telemetry,Routing -IncludeReadmeHash -SummaryPath Logs/TelemetryBundles/Review-20260110-ST-G-012/VerificationSummary.json` | `Logs/TelemetryBundles/Review-20260110-ST-G-012/VerificationSummary.json` |
| Doc-sync | `Tools/Test-DocSyncChecklist.ps1 -TaskId ST-G-012 -SessionLogPath docs/agents/sessions/2026-01-10_session-0001.md -RequireSessionLog -RequireBacklogEntry -PlanPath docs/plans/PlanG_ReleaseGovernance.md -OutputPath Logs/Reports/DocSyncChecklist-ST-G-012-20260110-154121.json` | `Logs/Reports/DocSyncChecklist-ST-G-012-20260110-154121.json` |

## Offline-first verification
| Subsystem | Command | Evidence |
|-----------|---------|----------|
| Offline-first | `Tools/Test-OfflineFirstEvidence.ps1 -SessionLogPath docs/agents/sessions/2026-01-09_session-0003.md` | Offline-first evidence JSON |

