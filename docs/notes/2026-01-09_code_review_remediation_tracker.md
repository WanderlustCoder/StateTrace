# Code review remediation tracker (2026-01-09)

Track fixes for findings and the required re-tests/telemetry validations.

| Finding ID | Fix summary | Files | Tests rerun | Telemetry rerun | Status | Notes |
|------------|-------------|-------|-------------|----------------|--------|-------|
| CR-001 | Warn on directory creation failures. | Modules/ParserWorker.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Verified in code. |
| CR-002 | Warn on settings JSON parse failures. | Modules/ParserWorker.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Verified in code. |
| CR-003 | Add backoff to scheduler polling interval. | Modules/ParserRunspaceModule.psm1 | Invoke-Pester Modules/Tests (2026-01-10) | N/A | Done | Backoff reduces idle polling overhead. |
| CR-004 | Warn on span table/index creation failures. | Modules/ParserPersistenceModule.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Verified warnings added. |
| CR-005 | Warn on parallel DB query failures. | Modules/DeviceRepository.Access.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Verified warning on EndInvoke failure. |
| CR-006 | Scope Juniper interface configs to interfaces block; ignore unit stanzas. | Modules/JuniperModule.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Verified in code. |
| CR-007 | Replace Invoke-Expression with AST-validated condition evaluation. | Modules/DecisionTreeModule.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Uses Test-DecisionTreeCondition. |
| CR-008 | Replace console spam with Write-Verbose. | Modules/LogIngestionModule.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Verified Write-Verbose usage. |
| CR-009 | Implement Add/Set/Remove-CapacityThreshold. | Modules/CapacityPlanningModule.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | View now calls existing commands. |
| CR-010 | Use snippet.Task for title text. | Modules/CommandReferenceViewModule.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Verified in code. |
| CR-011 | Replace Read-Host with InputBox dialog. | Modules/ChangeManagementViewModule.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Uses Read-HostDialog wrapper. |
| CR-012 | Swap Set-CableRun call to Update-CableRun. | Modules/CableDocumentationViewModule.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Verified in code. |
| CR-013 | Use SourceDevice/DestDevice in trace dialog. | Modules/CableDocumentationViewModule.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Verified in code. |
| CR-014 | Pass Context to alert condition scriptblock. | Modules/AlertRuleModule.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Verified in code. |
| CR-015 | Include ACE 16 in provider fallback list. | Modules/DatabaseModule.psm1; Modules/DatabaseConnectionPool.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Verified provider list. |
| CR-016 | Add TestId column and scoped integrity checks. | Modules/DatabaseConcurrencyModule.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Verified TestId insert/query. |
| CR-017 | Fix native VLAN regex grouping. | Modules/ConfigValidationModule.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Regex now grouped. |
| CR-018 | Apply multiline heading replacements. | Modules/DocumentationGeneratorModule.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Uses (?m) headings. |
| CR-019 | Replace PS7 ternary with PS5-compatible status mapping; harden fleet summary handling. | Modules/FleetHealthModule.psm1; Modules/Tests/FleetHealthModule.Tests.ps1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Pester: Passed 1626, Inconclusive 10. |
| CR-020 | Use DeviceInterfaceCache and flatten cached rows. | Modules/TopologyViewModule.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Verified in code. |
| CR-021 | Implement Remove-TopologyLayout and call from view. | Modules/TopologyModule.psm1; Modules/TopologyViewModule.psm1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Verified in code. |
| CR-022 | Clear caches only after parser job guard. | Main/MainWindow.ps1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Reset moved into Start-ParserBackgroundJob. |
| CR-023 | Route telemetry to TelemetryPath via STATETRACE_TELEMETRY_DIR and Save-StTelemetryBuffer. | Tools/Simulate-PlanHUIRun.ps1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Verified in code. |
| CR-024 | Replace PS7 ternary usage with PS5-compatible if/else formatting. | Tools/Analyze-PortBatchSiteMix.ps1; Tools/Analyze-PortBatchIntervals.ps1; Tools/Analyze-PortBatchGapTimeline.ps1 | Invoke-Pester Modules/Tests (2026-01-09) | N/A | Done | Verified ternary removed. |
| CR-025 | Update dispatcher harness manifest to reference Generate-QueueDelaySummary. | Tools/Invoke-DispatcherHarnessWithEvidence.ps1 | Not run | N/A | Done | Harness not executed. |
| CR-026 | Replace PS7 ternary usage with PS5-compatible if/else for warmup parameters. | Tools/Invoke-SharedCacheWarmup.ps1 | Not run | N/A | Done | Manual review only. |
| CR-027 | Require ApiKey unless AllowAnonymous; warn on anonymous use. | Tools/Start-StateTraceApi.ps1 | Not run | N/A | Done | Verified guard and warning present. |
| CR-028 | Import AnalyzerStats before calling Get-SampleCount. | Tools/Update-QueueDelayHistory.ps1 | Not run | N/A | Done | Verified module import. |
| CR-029 | Parameterize serial port/output paths via env + repo root. | Tools/Switch-Session.ps1; Tools/Switch-CreateProperLog.ps1; Tools/Switch-ConfigRadius.ps1 | Not run | N/A | Done | No hardcoded COM/paths detected. |
| CR-030 | Require SharedSecret/Test creds via parameters (no embedded secrets). | Tools/Switch-ConfigRadius.ps1 | Not run | N/A | Done | Verified parameters only. |
| CR-031 | Fix diagnostics CommandExports syntax. | Troubleshooting/Invoke-StateTraceDiagnostics.ps1 | Not run | N/A | Done | Verified in code. |
| CR-032 | Redact fixture identifiers. | Tests/Fixtures/LiveSwitch/LAB-C9200L-AS-01.log | N/A | N/A | Done | Serial/MAC values redacted. |
| CR-033 | Remove runtime .accdb from repo. | Data/BOYO/BOYO.accdb; Data/WLLS/WLLS.accdb | N/A | N/A | Done | Runtime .accdb files removed from repo tree. |
| CR-034 | Restore ADR content. | docs/adr/0005-autonomous-development-and-ci.md | N/A | N/A | Done | ADR content restored. |
| CR-035 | Fix shared cache ADR plan link. | docs/adr/0007-shared-cache-snapshot-governance.md | N/A | N/A | Done | Link updated. |
| CR-036 | Fix runbook line continuation. | docs/runbooks/Schedule_Daily_Rollup.md | N/A | N/A | Done | Uses backtick. |
| CR-037 | Fix roadmap encoding artifacts. | docs/StateTrace_Quarterly_Roadmap.md | N/A | N/A | Done | Text normalized. |
| CR-038 | Resolve port batch diversity guard failure (WLLS streak 23 > 8). | Logs/Reports/PortBatchSiteDiversity-2026-01-10.json | N/A | PortBatchSiteDiversity-2026-01-10.json | Done | MaxStreakSegment.Count=1 <= MaxAllowedConsecutive=8; ManualOverridesApplied=true. |
| CR-039 | Restore warm-run improvement >= 60%. | Logs/IngestionMetrics/WarmRunTelemetry-20260110-082340.json | Tools/Invoke-WarmRunRegression.ps1 | WarmRunTelemetry-20260110-082340.json | Done | WarmRunComparison ImprovementPercent 85.76 (Cold avg 668.728 ms, Warm avg 95.199 ms). |
| CR-040 | Restore shared cache snapshot coverage for WLLS. | Logs/SharedCacheSnapshot/SharedCacheSnapshot-latest.clixml | Tools/Test-SharedCacheSnapshot.ps1 | Review-20260110-101639 | Done | Snapshot includes BOYO+WLLS; test passed (Hosts=37, Rows=1320). |
| CR-041 | Complete Plan H UserAction coverage and readiness. | Logs/IngestionMetrics/Reports/UserActionSummary-2026-01-10-planh.json | Tools/Simulate-PlanHUIRun.ps1 | Review-20260110-101639 | Done | Plan H bundle ready; required actions present. |
| CR-042 | Resolve ParseDuration gate over threshold (p95 3.03 s, max 18.953 s). | Logs/IngestionMetrics/IngestionMetricsSummary-2026-01-10.csv | N/A | Review-20260110-101639 | Done | ParseDurationSeconds P95 1.103, Max 1.183 (within gate). |
| CR-043 | Resolve DatabaseWriteLatency gate over threshold (p95 958.1 ms > 950 ms). | Logs/IngestionMetrics/Review-20260110-DbLatency3-20260110-114623/IngestionMetricsSummary-2026-01-10.csv | Tools/Invoke-StateTracePipeline.ps1 | Review-20260110-DbLatency3-20260110-114623 | Done | P95 174.6 ms; AccessRefresh 0. |
| CR-044 | Scope verification harness shared cache diagnostics windows (store vs provider). | Tools/Invoke-StateTraceVerification.ps1 | Tools/Invoke-StateTraceVerification.ps1 (2026-01-10) | Logs/IngestionMetrics/2026-01-10.json; Logs/SharedCacheDiagnostics/SharedCacheStoreState-20260110-150106.json; Logs/SharedCacheDiagnostics/SiteCacheProviderReasons-20260110-150106.json | Done | Store window uses run span; provider window uses warm pass with lead/trail buffer. |
