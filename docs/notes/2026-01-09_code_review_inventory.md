# Code review inventory (2026-01-09)

## Coverage map

### Main (2 files) - Reviewed
- Main\MainWindow.xaml
- Main\MainWindow.ps1

### Modules (80 files) - Reviewed
- Modules\ConfigTemplateViewModule.psm1
- Modules\ConfigTemplateModule.psm1
- Modules\CompareViewModule.psm1
- Modules\CommandReferenceViewModule.psm1
- Modules\CommandReferenceModule.psm1
- Modules\CiscoModule.psm1
- Modules\ChangeManagementViewModule.psm1
- Modules\ChangeManagementModule.psm1
- Modules\CapacityPlanningViewModule.psm1
- Modules\CapacityPlanningModule.psm1
- Modules\CableDocumentationViewModule.psm1
- Modules\CableDocumentationModule.psm1
- Modules\BrocadeModule.psm1
- Modules\ArubaModule.psm1
- Modules\AristaModule.psm1
- Modules\AlertsViewModule.psm1
- Modules\AlertRuleModule.psm1
- Modules\DocumentationContainerViewModule.psm1
- Modules\DeviceRepositoryModule.psm1
- Modules\DeviceRepository.Cache.psm1
- Modules\DeviceRepository.Access.psm1
- Modules\DeviceParsingCommon.psm1
- Modules\DeviceLogParserModule.psm1
- Modules\DeviceInsightsModule.psm1
- Modules\DeviceDetailsModule.psm1
- Modules\DeviceCatalogModule.psm1
- Modules\DecisionTreeViewModule.psm1
- Modules\DecisionTreeModule.psm1
- Modules\DatabaseModule.psm1
- Modules\DatabaseIndexes.psm1
- Modules\DatabaseConnectionPool.psm1
- Modules\DatabaseConcurrencyModule.psm1
- Modules\ConfigValidationModule.psm1
- Modules\InterfaceModule.psm1
- Modules\InterfaceCommon.psm1
- Modules\IntegrationApiModule.psm1
- Modules\InfrastructureContainerViewModule.psm1
- Modules\FleetHealthModule.psm1
- Modules\FilterStateModule.psm1
- Modules\DocumentationGeneratorViewModule.psm1
- Modules\DocumentationGeneratorModule.psm1
- Modules\IPAMViewModule.psm1
- Modules\IPAMModule.psm1
- Modules\InventoryViewModule.psm1
- Modules\InventoryModule.psm1
- Modules\LogAnalysisModule.psm1
- Modules\JuniperModule.psm1
- Modules\LogAnalysisViewModule.psm1
- Modules\LogIngestionModule.psm1
- Modules\WarmRun.Telemetry.psm1
- Modules\ViewStateService.psm1
- Modules\ViewCompositionModule.psm1
- Modules\VerificationModule.psm1
- Modules\VendorDetectionModule.psm1
- Modules\VendorCommandTemplates.psm1
- Modules\TopologyViewModule.psm1
- Modules\TopologyModule.psm1
- Modules\ToolsContainerViewModule.psm1
- Modules\ThemeModule.psm1
- Modules\TemplatesViewModule.psm1
- Modules\TemplatesModule.psm1
- Modules\TelemetryModule.psm1
- Modules\SummaryViewModule.psm1
- Modules\StatisticsModule.psm1
- Modules\StabilityTestModule.psm1
- Modules\SpanViewModule.psm1
- Modules\SearchInterfacesViewModule.psm1
- Modules\PortReorgViewModule.psm1
- Modules\PortReorgModule.psm1
- Modules\PortNormalization.psm1
- Modules\ParserWorker.psm1
- Modules\ParserRunspaceModule.psm1
- Modules\ParserPersistenceModule.psm1
- Modules\PaloAltoModule.psm1
- Modules\OperationsContainerViewModule.psm1
- Modules\NetworkCalculatorViewModule.psm1
- Modules\NetworkCalculatorModule.psm1
- Modules\ModulesManifest.psd1
- Modules\ModuleLoaderModule.psm1
- Modules\MainWindow.Services.psm1

### Modules/Tests (92 files) - Reviewed
- Modules\Tests\WarmRunTelemetry.Tests.ps1
- Modules\Tests\WarmRunHistoryBackup.Tests.ps1
- Modules\Tests\ViewStateService.Tests.ps1
- Modules\Tests\VerificationQueueDelayHarness.Tests.ps1
- Modules\Tests\VerificationModule.Tests.ps1
- Modules\Tests\VendorModules.Tests.ps1
- Modules\Tests\UiHarnessHelpers.Tests.ps1
- Modules\Tests\TopologyModule.Tests.ps1
- Modules\Tests\ThemeModule.Tests.ps1
- Modules\Tests\TestSharedCacheSnapshot.Tests.ps1
- Modules\Tests\TestPortBatchSiteDiversity.Tests.ps1
- Modules\Tests\TelemetryModule.Tests.ps1
- Modules\Tests\TelemetryGateEnforcement.Tests.ps1
- Modules\Tests\TelemetryBundleRiskRegister.Tests.ps1
- Modules\Tests\TelemetryBundleReadiness.Tests.ps1
- Modules\Tests\TelemetryBundleGuard.Tests.ps1
- Modules\Tests\TaskBoardIntegrity.Tests.ps1
- Modules\Tests\StatusStripIndicators.Tests.ps1
- Modules\Tests\StabilityTestModule.Tests.ps1
- Modules\Tests\SpanViewModule.Tests.ps1
- Modules\Tests\SpanViewBinding.Tests.ps1
- Modules\Tests\SkipSiteCacheUpdateGuard.Tests.ps1
- Modules\Tests\ScheduledHarnessSmoke.Tests.ps1
- Modules\Tests\Schedule-VerificationTask.Tests.ps1
- Modules\Tests\RoutingValidationRun.Tests.ps1
- Modules\Tests\RoutingSchemas.Tests.ps1
- Modules\Tests\RoutingRealDeviceEvidence.Tests.ps1
- Modules\Tests\RoutingOnlineCaptureReadiness.Tests.ps1
- Modules\Tests\RoutingOfflineDemo.Tests.ps1
- Modules\Tests\RoutingOfflineBundleValidation.Tests.ps1
- Modules\Tests\RoutingOfflineBundleExpand.Tests.ps1
- Modules\Tests\RoutingOfflineBundle.Tests.ps1
- Modules\Tests\RoutingLogViewer.Tests.ps1
- Modules\Tests\RoutingLogIndex.Tests.ps1
- Modules\Tests\RoutingLogExplorer.Tests.ps1
- Modules\Tests\RoutingDiscoveryPipeline.Tests.ps1
- Modules\Tests\RoutingDiscoveryCaptureConversion.Tests.ps1
- Modules\Tests\RoutingDiscoveryBaseline.Tests.ps1
- Modules\Tests\RoutingCliCaptureSessionGenerator.Tests.ps1
- Modules\Tests\RoutingCliCaptureSession.Tests.ps1
- Modules\Tests\RoutingCliCaptureIngestion.Tests.ps1
- Modules\Tests\RoutingBundleReview.Tests.ps1
- Modules\Tests\RouteHealthSnapshotGenerator.Tests.ps1
- Modules\Tests\RouteHealthSnapshotDiff.Tests.ps1
- Modules\Tests\RollupIngestionMetrics.Tests.ps1
- Modules\Tests\PublishTelemetryBundle.Tests.ps1
- Modules\Tests\PortReorgWindow.Paging.Tests.ps1
- Modules\Tests\PortReorgModule.Tests.ps1
- Modules\Tests\PortBatchReadySynthesisSwitch.Tests.ps1
- Modules\Tests\ParserWorker.Tests.ps1
- Modules\Tests\ParserRunspaceModule.Tests.ps1
- Modules\Tests\ParserPersistenceModule.Tests.ps1
- Modules\Tests\NetworkCalculatorModule.Tests.ps1
- Modules\Tests\ModuleDecomposition.Tests.ps1
- Modules\Tests\MainWindow.Services.Tests.ps1
- Modules\Tests\LogIngestionModule.Tests.ps1
- Modules\Tests\LogAnalysisModule.Tests.ps1
- Modules\Tests\IPAMModule.Tests.ps1
- Modules\Tests\Invoke-StateTraceScheduledVerification.Tests.ps1
- Modules\Tests\InventoryModule.Tests.ps1
- Modules\Tests\InterfaceModule.Tests.ps1
- Modules\Tests\InspectSharedCacheSnapshot.Tests.ps1
- Modules\Tests\HistoryUpdaters.Tests.ps1
- Modules\Tests\HarnessSmoke.Tests.ps1
- Modules\Tests\FleetHealthModule.Tests.ps1
- Modules\Tests\FilterStateModule.Tests.ps1
- Modules\Tests\DocumentationGeneratorModule.Tests.ps1
- Modules\Tests\DocSyncChecklist.Tests.ps1
- Modules\Tests\DiffPrototypeFixtures.Tests.ps1
- Modules\Tests\DeviceRepositoryModule.Tests.ps1
- Modules\Tests\DeviceRepositoryModule.InterfaceConfiguration.Tests.ps1
- Modules\Tests\DeviceParsingCommon.Tests.ps1
- Modules\Tests\DeviceLogParserModule.Tests.ps1
- Modules\Tests\DeviceInsightsModule.Tests.ps1
- Modules\Tests\DeviceDetailsModule.Tests.ps1
- Modules\Tests\DeviceCatalogModule.Tests.ps1
- Modules\Tests\DecisionTreeModule.Tests.ps1
- Modules\Tests\DatabaseModule.Tests.ps1
- Modules\Tests\DatabaseConcurrencyModule.Tests.ps1
- Modules\Tests\ContainerViews.Tests.ps1
- Modules\Tests\ConfigValidationModule.Tests.ps1
- Modules\Tests\ConfigTemplateModule.Tests.ps1
- Modules\Tests\ConcurrencyOverrideGuard.Tests.ps1
- Modules\Tests\CompareViewModule.Tests.ps1
- Modules\Tests\CompareTelemetrySmoke.Tests.ps1
- Modules\Tests\CompareSchedulerAndPortDiversity.Tests.ps1
- Modules\Tests\CommandReferenceModule.Tests.ps1
- Modules\Tests\CISmokeHarness.Tests.ps1
- Modules\Tests\ChangeManagementModule.Tests.ps1
- Modules\Tests\CapacityPlanningModule.Tests.ps1
- Modules\Tests\CableDocumentationModule.Tests.ps1
- Modules\Tests\AnalyzeDispatcherGaps.Tests.ps1

### Views (26 files) - Reviewed
- Views\TopologyView.xaml
- Views\ToolsContainerView.xaml
- Views\TemplatesView.xaml
- Views\SummaryView.xaml
- Views\SpanView.xaml
- Views\SearchInterfacesView.xaml
- Views\QuickNavigationDialog.xaml
- Views\PortReorgWindow.xaml
- Views\OperationsContainerView.xaml
- Views\NetworkCalculatorView.xaml
- Views\LogAnalysisView.xaml
- Views\IPAMView.xaml
- Views\InventoryView.xaml
- Views\InterfacesView.xaml
- Views\InfrastructureContainerView.xaml
- Views\HelpWindow.xaml
- Views\DocumentationGeneratorView.xaml
- Views\DocumentationContainerView.xaml
- Views\DecisionTreeView.xaml
- Views\ConfigTemplateView.xaml
- Views\CompareView.xaml
- Views\CommandReferenceView.xaml
- Views\ChangeManagementView.xaml
- Views\CapacityPlanningView.xaml
- Views\CableDocumentationView.xaml
- Views\AlertsView.xaml

### Tools (167 files) - Reviewed
- Tools\Check-PlanHStatus.ps1 (Reviewed)
- Tools\Capture-PlanHScreenshots.ps1 (Reviewed)
- Tools\Build-RoutingLogIndex.ps1 (Reviewed)
- Tools\Bootstrap-DevSeat.ps1 (Reviewed)
- Tools\AutoCapture-PlanHUI.ps1 (Reviewed)
- Tools\AnalyzerStats.psm1 (Reviewed)
- Tools\Analyze-WarmRunDiffHotspots.ps1 (Reviewed)
- Tools\Analyze-UserActionTelemetry.ps1 (Reviewed)
- Tools\Analyze-SiteCacheProviderReasons.ps1 (Reviewed)
- Tools\Analyze-SharedCacheStoreState.ps1 (Reviewed)
- Tools\Analyze-PortBatchSiteMix.ps1 (Reviewed)
- Tools\Analyze-PortBatchReadyTelemetry.ps1 (Reviewed)
- Tools\Analyze-PortBatchIntervals.ps1 (Reviewed)
- Tools\Analyze-PortBatchGapTimeline.ps1 (Reviewed)
- Tools\Analyze-PortBatchGapBreakdown.ps1 (Reviewed)
- Tools\Analyze-ParserSchedulerLaunch.ps1 (Reviewed)
- Tools\Analyze-InterfaceSyncTiming.ps1 (Reviewed)
- Tools\Analyze-FreshnessTelemetry.ps1 (Reviewed)
- Tools\Analyze-DispatchHarnessSweep.ps1 (Reviewed)
- Tools\Analyze-DispatcherGaps.ps1 (Reviewed)
- Tools\Add-PortBatchReadyTelemetry.ps1 (Reviewed)
- Tools\Invoke-IncrementalLoadingChecklist.ps1 (Reviewed)
- Tools\Get-ModuleImportGraph.ps1 (Reviewed)
- Tools\Generate-QueueDelaySummary.ps1 (Reviewed)
- Tools\Invoke-IncidentDrill.ps1 (Reviewed)
- Tools\Generate-PlanHReport.ps1 (Reviewed)
- Tools\Invoke-HeadlessRun.ps1 (Reviewed)
- Tools\Invoke-FeatureFlagAudit.ps1 (Reviewed)
- Tools\Generate-IncrementalPerformanceReport.ps1 (Reviewed)
- Tools\Invoke-DispatcherHarnessWithEvidence.ps1 (Reviewed)
- Tools\Export-RoutingOfflineBundle.ps1 (Reviewed)
- Tools\Expand-RoutingOfflineBundle.ps1 (Reviewed)
- Tools\Expand-MockLogCorpus.ps1
- Tools\Convert-RoutingDiscoveryCapture.ps1
- Tools\Convert-RoutingCliCaptureToDiscoveryCapture.ps1
- Tools\Convert-RouteRecordsToHealthSnapshot.ps1
- Tools\ConcurrencyOverrideGuard.psm1
- Tools\Compare-SchedulerAndPortDiversity.ps1
- Tools\Compare-RouteHealthSnapshots.ps1
- Tools\Collect-LocationStartupSnapshot.ps1
- Tools\Clean-ArtifactsAndBundle.ps1
- Tools\Invoke-DesktopUIHarness.ps1 (Reviewed)
- Tools\Invoke-DailyRollupScheduled.ps1
- Tools\Invoke-DailyMetricRollup.ps1
- Tools\Invoke-DailyHealthCheck.ps1
- Tools\Invoke-CIHarness.ps1 (Reviewed)
- Tools\Invoke-CablesSmokeTest.ps1 (Reviewed)
- Tools\Invoke-AllChecks.ps1 (Reviewed)
- Tools\Install-PreCommitHooks.ps1
- Tools\Inspect-SharedCacheSnapshot.ps1
- Tools\Initialize-SharedCacheSeed.ps1
- Tools\Invoke-StateTraceVerification.ps1 (Reviewed)
- Tools\Invoke-StateTraceUiDiagnostics.ps1
- Tools\Invoke-StateTraceScheduledVerification.ps1 (Reviewed)
- Tools\Invoke-StateTracePipeline.ps1 (Reviewed)
- Tools\Invoke-StabilityTests.ps1
- Tools\Invoke-SpanViewSmokeTest.ps1 (Reviewed)
- Tools\Invoke-SharedCacheWarmup.ps1
- Tools\Invoke-SearchAlertsSmokeTest.ps1 (Reviewed)
- Tools\Invoke-ScheduledHarnessSmoke.ps1 (Reviewed)
- Tools\Invoke-SanitizationWorkflow.ps1
- Tools\Invoke-RoutingValidationRun.ps1
- Tools\Invoke-RoutingQueueSweep.ps1
- Tools\Invoke-RoutingOfflineDemo.ps1
- Tools\Invoke-RoutingLogExplorer.ps1
- Tools\Invoke-RoutingDiscoveryPipeline.ps1
- Tools\Invoke-RoutingCliCaptureSession.ps1
- Tools\Invoke-RoutingBundleReview.ps1
- Tools\Invoke-PostIncidentVerification.ps1
- Tools\Invoke-PlanHChecks.ps1 (Reviewed)
- Tools\Invoke-PlanHBundle.ps1 (Reviewed)
- Tools\Invoke-InterfacesViewSmokeTest.ps1
- Tools\Invoke-InterfacesViewChecklist.ps1
- Tools\Invoke-InterfaceDispatchHarness.ps1
- Tools\New-TelemetryBundle.ps1
- Tools\New-SessionLogStub.ps1
- Tools\New-RoutingCliCaptureSession.ps1
- Tools\New-RollbackBundle.ps1
- Tools\New-ReleaseManifest.ps1
- Tools\New-ReleaseEvidenceBundle.ps1
- Tools\New-ModuleDocumentation.ps1
- Tools\New-BalancedRoutingHostList.ps1
- Tools\New-ArchitectureDecisionRecord.ps1
- Tools\NetworkGuard.psm1
- Tools\Measure-UiResponsiveness.ps1
- Tools\Maintain-AccessDatabases.ps1
- Tools\Launch-MainWindow.ps1
- Tools\Invoke-WarmRunTelemetry.ps1 (Reviewed)
- Tools\Invoke-WarmRunRegression.ps1 (Reviewed)
- Tools\Invoke-UiCleanupAudit.ps1
- Tools\Run-PlanHHeadless.ps1 (Reviewed)
- Tools\Rollup-IngestionMetrics.ps1
- Tools\Resolve-SharedCacheSnapshot.ps1
- Tools\Reset-OnlineModeFlags.ps1
- Tools\Report-UnusedScripts.ps1
- Tools\Report-UnusedExports.ps1
- Tools\Repair-AccessDatabase.ps1
- Tools\Publish-TelemetryBundle.ps1
- Tools\Pack-StateTrace.ps1
- Tools\Show-RoutingLogSummary.ps1
- Tools\Show-ReleaseReadiness.ps1
- Tools\Show-PlanHReadiness.ps1 (Reviewed)
- Tools\Schedule-VerificationTask.ps1
- Tools\Schedule-DailyRollupTask.ps1
- Tools\Sanitize-PostmortemLogs.ps1
- Tools\SkipSiteCacheUpdateGuard.psm1
- Tools\Simulate-PlanHUIRun.ps1 (Reviewed)
- Tools\Show-TelemetryBundleSummary.ps1
- Tools\Start-StateTraceApi.ps1
- Tools\Start-ConnectivityMonitor.ps1
- Tools\Switch-Capture.ps1
- Tools\Switch-CheckSVI.ps1
- Tools\Switch-CreateLog2.ps1
- Tools\Switch-CreateLog.ps1
- Tools\Switch-CR.ps1
- Tools\Switch-Connect.ps1
- Tools\Switch-ConfigVlan1.ps1
- Tools\Switch-Configure.ps1
- Tools\Switch-ConfigRadius.ps1
- Tools\Switch-CheckSVI2.ps1
- Tools\Switch-Init.ps1
- Tools\Switch-FixVlan1.ps1
- Tools\Switch-Detect.ps1
- Tools\Switch-CreateProperLog.ps1
- Tools\Sync-TaskBoard.ps1
- Tools\Switch-Session.ps1
- Tools\Switch-Interact.ps1
- Tools\Synthesize-InterfaceSyncTelemetry.ps1
- Tools\Synthesize-ParserSchedulerTelemetry.ps1
- Tools\Test-Accessibility.ps1
- Tools\Update-QueueDelayHistory.ps1
- Tools\Update-PortBatchHistory.ps1
- Tools\Update-ParserSchedulerHistory.ps1
- Tools\Update-InterfaceSyncHistory.ps1
- Tools\UiHarnessHelpers.ps1
- Tools\ToolingJson.psm1
- Tools\Test-UiResponsiveness.ps1
- Tools\Test-TelemetryIntegrity.ps1
- Tools\Test-TelemetryBundleReadiness.ps1
- Tools\Test-TaskBoardIntegrity.ps1
- Tools\Test-SpanViewBinding.ps1
- Tools\Test-SharedCacheSnapshot.ps1
- Tools\Test-SharedCacheEviction.ps1
- Tools\Test-SharedCacheCompatibility.ps1
- Tools\Test-RoutingSchemas.ps1
- Tools\Test-RoutingRealDeviceEvidence.ps1
- Tools\Test-RoutingOnlineCaptureReadiness.ps1
- Tools\Test-RoutingOfflineBundle.ps1
- Tools\Test-RoutingDiscoveryBaseline.ps1
- Tools\Test-ResponsiveLayout.ps1
- Tools\Test-RedactionCompliance.ps1
- Tools\Test-QueueDelayThreshold.ps1
- Tools\Test-PortBatchSiteDiversity.ps1
- Tools\Test-PlanTaskBoardDrift.ps1
- Tools\Test-PlanHReadiness.ps1 (Reviewed)
- Tools\Test-ParserSchedulerFairness.ps1
- Tools\Test-OfflineFirstEvidence.ps1
- Tools\Test-NetOpsEvidence.ps1
- Tools\Test-LogParser.ps1
- Tools\Test-InstallSmoke.ps1
- Tools\Test-IncrementalTelemetryCompleteness.ps1
- Tools\Test-IncidentClosureEvidence.ps1
- Tools\Test-HarnessSmoke.ps1
- Tools\Test-DocSyncChecklist.ps1
- Tools\Test-DependencyPreflight.ps1
- Tools\Test-DatabaseConsistency.ps1
- Tools\Test-CompareTelemetrySmoke.ps1

### Resources/Templates/Themes (12 files) - Reviewed
- Resources\SharedStyles.xaml
- Templates\ShowCommands.json
- Templates\Cisco.json
- Templates\Brocade.json
- Themes\w40k-salamanders.json
- Themes\spud-runner.json
- Themes\high-contrast.json
- Themes\high-contrast-white.json
- Themes\helldivers-spill-oil.json
- Themes\bros.json
- Themes\blue-angels.json
- Themes\base.json

### Troubleshooting (3 files) - Reviewed
- Troubleshooting\Invoke-StateTraceDiagnostics.ps1
- Troubleshooting\README.md
- Troubleshooting\KnowledgeBase.yml

### Tests (harness + fixtures) (65 files) - Reviewed
- Tests\Test-Accessibility.ps1
- Tests\Invoke-MainWindowSmokeTest.ps1
- Tests\Fixtures\manifests\Synthetic-5.1.json
- Tests\Fixtures\manifests\CISmoke.json
- Tests\Fixtures\README.md
- Tests\Fixtures\Vendors\PaloAlto\show_system_info.txt
- Tests\Fixtures\Vendors\PaloAlto\show_routing_route.txt
- Tests\Fixtures\Vendors\PaloAlto\show_interface_all.txt
- Tests\Fixtures\Routing\RoutingDiscoveryCapture.sample.json
- Tests\Fixtures\Routing\RouteRecords.sample.json
- Tests\Fixtures\Routing\RouteRecord.sample.json
- Tests\Fixtures\Routing\RouteHealthSnapshot.sample.json
- Tests\Fixtures\Routing\RouteHealthSnapshot.expected.json
- Tests\Fixtures\LiveSwitch\show_vlan_brief.txt
- Tests\Fixtures\LiveSwitch\show_version.txt
- Tests\Fixtures\LiveSwitch\show_spanning-tree.txt
- Tests\Fixtures\LiveSwitch\show_running-config.txt
- Tests\Fixtures\LiveSwitch\show_power_inline.txt
- Tests\Fixtures\LiveSwitch\show_mac_address-table.txt
- Tests\Fixtures\LiveSwitch\show_logging.txt
- Tests\Fixtures\LiveSwitch\show_ip_interface_brief.txt
- Tests\Fixtures\LiveSwitch\show_inventory.txt
- Tests\Fixtures\LiveSwitch\show_interfaces_status.txt
- Tests\Fixtures\LiveSwitch\show_interfaces.txt
- Tests\Fixtures\LiveSwitch\show_cdp_neighbors_detail.txt
- Tests\Fixtures\LiveSwitch\show_cdp_neighbors.txt
- Tests\Fixtures\LiveSwitch\LAB-C9200L-AS-01.log
- Tests\Fixtures\Vendors\Juniper\show_version.txt
- Tests\Fixtures\Vendors\Juniper\show_route.txt
- Tests\Fixtures\Vendors\Juniper\show_interfaces_terse.txt
- Tests\Fixtures\Vendors\Aruba\show_vlan.txt
- Tests\Fixtures\Vendors\Aruba\show_version.txt
- Tests\Fixtures\Vendors\Aruba\show_interface_brief.txt
- Tests\Fixtures\Routing\RouteDiff\RoutingDiff.sample.json
- Tests\Fixtures\Routing\RouteDiff\RouteRecords.old.json
- Tests\Fixtures\Routing\RouteDiff\RouteRecords.new.json
- Tests\Fixtures\Routing\RouteDiff\RouteHealthSnapshot.old.json
- Tests\Fixtures\Routing\RouteDiff\RouteHealthSnapshot.new.json
- Tests\Fixtures\Routing\LogExplorer\RoutingValidationRunSummary.sample.json
- Tests\Fixtures\Routing\LogExplorer\RoutingDiscoveryPipelineSummary.sample.json
- Tests\Fixtures\CISmoke\WarmRunTelemetry.json
- Tests\Fixtures\CISmoke\SharedCacheSeed.clixml
- Tests\Fixtures\CISmoke\IngestionMetrics.json
- Tests\Fixtures\Synthetic\5.1\IngestionMetrics.json
- Tests\Fixtures\Routing\RealDeviceEvidence\RoutingValidationRunSummary.sample.json
- Tests\Fixtures\Routing\RealDeviceEvidence\PreflightSummary.sample.json
- Tests\Fixtures\Routing\RealDeviceEvidence\OperatorRun.sample.log
- Tests\Fixtures\Routing\RealDeviceEvidence\OperatorEvidence.sample.md
- Tests\Fixtures\Routing\LogExplorer\LatestCompare\RoutingDiscoveryPipelineSummary.previous.json
- Tests\Fixtures\Routing\LogExplorer\LatestCompare\RoutingDiscoveryPipelineSummary.latest.json
- Tests\Fixtures\Routing\LogExplorer\LatestCompare\Index.latestcompare.sample.json
- Tests\Fixtures\Routing\LogExplorer\Index.sample.json
- Tests\Fixtures\Routing\CliCaptureSession\Hosts.sample.txt
- Tests\Fixtures\Routing\LogExplorer\Compare\RoutingDiscoveryPipelineSummary.old.json
- Tests\Fixtures\Routing\LogExplorer\Compare\RoutingDiscoveryPipelineSummary.new.json
- Tests\Fixtures\Routing\LogExplorer\Compare\RoutingDiscoveryPipelineSummary.missingSnapshot.json
- Tests\Fixtures\Routing\LogViewer\RoutingDiscoveryPipelineSummary.sample.json
- Tests\Fixtures\Routing\CliCaptureSession\CiscoIOSXE\WLLS-A01-AS-01_show_ip_route.txt
- Tests\Fixtures\Routing\CliCaptureSession\CiscoIOSXE\Session.json
- Tests\Fixtures\Routing\CliCaptureSession\AristaEOS\WLLS-A01-AS-02_show_ip_route.txt
- Tests\Fixtures\Routing\CliCaptureSession\AristaEOS\Session.json
- Tests\Fixtures\Routing\CliCapture\CiscoIOSXE\show_ip_route.txt
- Tests\Fixtures\Routing\CliCapture\CiscoIOSXE\Capture.json
- Tests\Fixtures\Routing\CliCapture\AristaEOS\Capture.json
- Tests\Fixtures\Routing\CliCapture\AristaEOS\show_ip_route.txt

### Docs (release/runbooks/governance) (41 files) - Reviewed
- docs\CODEX_PLAN_AUTOMATION_MATRIX.md
- docs\CODEX_BACKLOG.md
- docs\CODEX_SHARED_CACHE_DIAGNOSTICS.md
- docs\CODEX_OPERATIONS_GUIDE.md
- docs\CODEX_SESSION_CHECKLIST.md
- docs\CODEX_AUTONOMY_PLAN.md
- docs\CODEX_INSTRUCTION_STACK.md
- docs\CODEX_RUNBOOK.md
- docs\CODEX_DOC_SYNC_PLAYBOOK.md
- docs\CODEX_QUICK_START.md
- docs\Core_Ideas.md
- docs\Release.md
- docs\RiskRegister.md
- docs\StateTrace_Quarterly_Roadmap.md
- docs\StateTrace_AI_Agent_Guide.md
- docs\StateTrace_TaskBoard.md
- docs\taskboard\TaskBoard.csv
- docs\runbooks\Database_Recovery.md
- docs\runbooks\UserAction_Telemetry.md
- docs\runbooks\Telemetry_Bundle_Verification.md
- docs\runbooks\Schedule_Verification.md
- docs\runbooks\Schedule_Daily_Rollup.md
- docs\runbooks\Routing_RealDeviceValidation.md
- docs\runbooks\Routing_QuickStart.md
- docs\runbooks\PlanH_UI_Capture_Local.md
- docs\runbooks\PlanH_Headless_Automation.md
- docs\runbooks\PlanH_Bundle_Workflow.md
- docs\runbooks\Onboarding_Screenshots.md
- docs\runbooks\Incremental_Loading_Performance.md
- docs\runbooks\Incident_INC0006_DispatcherThroughputDrop.md
- docs\runbooks\Incident_INC0005_CacheProviderFallback.md
- docs\runbooks\Incident_INC0004_BulkStageLatencySpike.md
- docs\runbooks\Incident_INC0003_PortBatchMissing.md
- docs\runbooks\Incident_INC0002_SharedCacheRefresh.md
- docs\runbooks\Incident_INC0001_RoutingQueueDelay.md
- docs\runbooks\Incident_Drill_Schedule.md
- docs\runbooks\Identity_RBAC_Rollout.md
- docs\runbooks\Freshness_Telemetry.md
- docs\plans\PlanG_ReleaseGovernance.md
- docs\telemetry\Phase1_metrics.md
- docs\telemetry\Automation_Gates.md

### Data (json config/history, no accdb) (7 files) - Reviewed
- Data\ValidationStandards.json
- Data\StateTraceSettings.json
- Data\ScheduledReports.json
- Data\IngestionHistory\WLLS.json
- Data\CableDatabase.json
- Data\IngestionHistory\BOYO.json
- Data\ConfigTemplates.json

## Review ledger (seeded)
| File | Subsystem | Entry/Callers | Review Focus | Risk Flags | Findings (refs) | Severity | Evidence / Tests / Telemetry | Status |
|------|-----------|---------------|--------------|------------|----------------|----------|------------------------------|--------|
| Main\MainWindow.xaml | Main |  |  |  |  |  |  | Reviewed |
| Main\MainWindow.ps1 | Main |  |  |  |  |  |  | Reviewed |
| Modules\ConfigTemplateViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\ConfigTemplateModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\CompareViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\CommandReferenceViewModule.psm1 | Modules |  |  | UI | CR-010 (Modules/CommandReferenceViewModule.psm1:218) | Low | N/A | Reviewed |
| Modules\CommandReferenceModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\CiscoModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\ChangeManagementViewModule.psm1 | Modules |  |  | UI | CR-011 (Modules/ChangeManagementViewModule.psm1:879) | Medium | N/A | Reviewed |
| Modules\ChangeManagementModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\CapacityPlanningViewModule.psm1 | Modules |  |  | UI | CR-009 (Modules/CapacityPlanningViewModule.psm1:1136) | Medium | N/A | Reviewed |
| Modules\CapacityPlanningModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\CableDocumentationViewModule.psm1 | Modules |  |  | UI | CR-012 (Modules/CableDocumentationViewModule.psm1:947); CR-013 (Modules/CableDocumentationViewModule.psm1:982) | Medium | N/A | Reviewed |
| Modules\CableDocumentationModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\BrocadeModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\ArubaModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\AristaModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\AlertsViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\AlertRuleModule.psm1 | Modules |  |  | Tooling | CR-014 (Modules/AlertRuleModule.psm1:146) | Low | N/A | Reviewed |
| Modules\DocumentationContainerViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\DeviceRepositoryModule.psm1 | Modules | Repository core | Cache hydration, shared cache integration, DB query orchestration | Concurrency | None | None | N/A | Reviewed |
| Modules\DeviceRepository.Cache.psm1 | Modules | Shared cache store | Cache store lifecycle, snapshot export/import | Concurrency | None | None | N/A | Reviewed |
| Modules\DeviceRepository.Access.psm1 | Modules | Access helpers | DB path resolution, parallel query helper | AccessWrite | CR-005 (Modules/DeviceRepository.Access.psm1:336) | Medium | N/A | Reviewed |
| Modules\DeviceParsingCommon.psm1 | Modules | Parser helpers | Regex cache, parsing helpers | Parser | None | None | N/A | Reviewed |
| Modules\DeviceLogParserModule.psm1 | Modules | Parser ingestion | Log parsing, history checks, provider probe, connection cache | Parser | None | None | N/A | Reviewed |
| Modules\DeviceInsightsModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\DeviceDetailsModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\DeviceCatalogModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\DecisionTreeViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\DecisionTreeModule.psm1 | Modules |  |  | Security, Tooling | CR-007 (Modules/DecisionTreeModule.psm1:512) | Medium | N/A | Reviewed |
| Modules\DatabaseModule.psm1 | Modules |  |  | AccessWrite | CR-015 (Modules/DatabaseModule.psm1:171) | Medium | N/A | Reviewed |
| Modules\DatabaseIndexes.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\DatabaseConnectionPool.psm1 | Modules |  |  | AccessWrite | CR-015 (Modules/DatabaseConnectionPool.psm1:57) | Medium | N/A | Reviewed |
| Modules\DatabaseConcurrencyModule.psm1 | Modules |  |  | Tooling | CR-016 (Modules/DatabaseConcurrencyModule.psm1:90) | Low | N/A | Reviewed |
| Modules\ConfigValidationModule.psm1 | Modules |  |  | Tooling | CR-017 (Modules/ConfigValidationModule.psm1:563) | Low | N/A | Reviewed |
| Modules\InterfaceModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\InterfaceCommon.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\IntegrationApiModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\InfrastructureContainerViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\FleetHealthModule.psm1 | Modules |  |  | Tooling | CR-019 (Modules/FleetHealthModule.psm1:798) | Medium | N/A | Reviewed |
| Modules\FilterStateModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\DocumentationGeneratorViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\DocumentationGeneratorModule.psm1 | Modules |  |  | Tooling | CR-018 (Modules/DocumentationGeneratorModule.psm1:1203) | Low | N/A | Reviewed |
| Modules\IPAMViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\IPAMModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\InventoryViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\InventoryModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\LogAnalysisModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\JuniperModule.psm1 | Modules |  |  | Parser | CR-006 (Modules/JuniperModule.psm1:203) | Medium | N/A | Reviewed |
| Modules\LogAnalysisViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\LogIngestionModule.psm1 | Modules |  |  | Tooling | CR-008 (Modules/LogIngestionModule.psm1:41) | Medium | N/A | Reviewed |
| Modules\WarmRun.Telemetry.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\ViewStateService.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\ViewCompositionModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\VerificationModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\VendorDetectionModule.psm1 | Modules | Vendor detection | Prompt/content pattern scoring | Parser | None | None | N/A | Reviewed |
| Modules\VendorCommandTemplates.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\TopologyViewModule.psm1 | Modules |  |  | UI | CR-020 (Modules/TopologyViewModule.psm1:306); CR-021 (Modules/TopologyViewModule.psm1:751) | Medium | N/A | Reviewed |
| Modules\TopologyModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\ToolsContainerViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\ThemeModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\TemplatesViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\TemplatesModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\TelemetryModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\SummaryViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\StatisticsModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\StabilityTestModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\SpanViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\SearchInterfacesViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\PortReorgViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\PortReorgModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\PortNormalization.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\ParserWorker.psm1 | Modules | Parser pipeline entrypoint | Concurrency/profile resolution, settings, cache snapshot export, telemetry | Parser, Tooling | CR-001, CR-002 (Modules/ParserWorker.psm1:21, 614) | Medium | N/A | Reviewed |
| Modules\ParserRunspaceModule.psm1 | Modules | Runspace scheduler | Scheduler loop, runspace pool lifecycle, telemetry | Concurrency | CR-003 (Modules/ParserRunspaceModule.psm1:1151) | Low | N/A | Reviewed |
| Modules\ParserPersistenceModule.psm1 | Modules | Parser persistence | Access schema creation, bulk insert helpers, cache snapshots | AccessWrite | CR-004 (Modules/ParserPersistenceModule.psm1:1017) | Medium | N/A | Reviewed |
| Modules\PaloAltoModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\OperationsContainerViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\NetworkCalculatorViewModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\NetworkCalculatorModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\ModulesManifest.psd1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\ModuleLoaderModule.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\MainWindow.Services.psm1 | Modules |  |  |  |  |  |  | Reviewed |
| Modules\Tests\WarmRunTelemetry.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\WarmRunHistoryBackup.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\ViewStateService.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\VerificationQueueDelayHarness.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\VerificationModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\VendorModules.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\UiHarnessHelpers.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\TopologyModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\ThemeModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\TestSharedCacheSnapshot.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\TestPortBatchSiteDiversity.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\TelemetryModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\TelemetryGateEnforcement.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\TelemetryBundleRiskRegister.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\TelemetryBundleReadiness.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\TelemetryBundleGuard.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\TaskBoardIntegrity.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\StatusStripIndicators.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\StabilityTestModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\SpanViewModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\SpanViewBinding.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\SkipSiteCacheUpdateGuard.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\ScheduledHarnessSmoke.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\Schedule-VerificationTask.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingValidationRun.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingSchemas.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingRealDeviceEvidence.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingOnlineCaptureReadiness.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingOfflineDemo.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingOfflineBundleValidation.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingOfflineBundleExpand.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingOfflineBundle.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingLogViewer.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingLogIndex.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingLogExplorer.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingDiscoveryPipeline.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingDiscoveryCaptureConversion.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingDiscoveryBaseline.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingCliCaptureSessionGenerator.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingCliCaptureSession.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingCliCaptureIngestion.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RoutingBundleReview.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RouteHealthSnapshotGenerator.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RouteHealthSnapshotDiff.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\RollupIngestionMetrics.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\PublishTelemetryBundle.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\PortReorgWindow.Paging.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\PortReorgModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\PortBatchReadySynthesisSwitch.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\ParserWorker.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\ParserRunspaceModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\ParserPersistenceModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\NetworkCalculatorModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\ModuleDecomposition.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\MainWindow.Services.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\LogIngestionModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\LogAnalysisModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\IPAMModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\Invoke-StateTraceScheduledVerification.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\InventoryModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\InterfaceModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\InspectSharedCacheSnapshot.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\HistoryUpdaters.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\HarnessSmoke.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\FleetHealthModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\FilterStateModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\DocumentationGeneratorModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\DocSyncChecklist.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\DiffPrototypeFixtures.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\DeviceRepositoryModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\DeviceRepositoryModule.InterfaceConfiguration.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\DeviceParsingCommon.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\DeviceLogParserModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\DeviceInsightsModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\DeviceDetailsModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\DeviceCatalogModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\DecisionTreeModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\DatabaseModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\DatabaseConcurrencyModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\ContainerViews.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\ConfigValidationModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\ConfigTemplateModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\ConcurrencyOverrideGuard.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\CompareViewModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\CompareTelemetrySmoke.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\CompareSchedulerAndPortDiversity.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\CommandReferenceModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\CISmokeHarness.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\ChangeManagementModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\CapacityPlanningModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\CableDocumentationModule.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Modules\Tests\AnalyzeDispatcherGaps.Tests.ps1 | Modules/Tests |  |  |  |  |  |  | Reviewed |
| Views\TopologyView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\ToolsContainerView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\TemplatesView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\SummaryView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\SpanView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\SearchInterfacesView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\QuickNavigationDialog.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\PortReorgWindow.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\OperationsContainerView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\NetworkCalculatorView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\LogAnalysisView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\IPAMView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\InventoryView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\InterfacesView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\InfrastructureContainerView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\HelpWindow.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\DocumentationGeneratorView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\DocumentationContainerView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\DecisionTreeView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\ConfigTemplateView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\CompareView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\CommandReferenceView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\ChangeManagementView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\CapacityPlanningView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\CableDocumentationView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Views\AlertsView.xaml | Views |  |  |  |  |  |  | Reviewed |
| Tools\Check-PlanHStatus.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Capture-PlanHScreenshots.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Build-RoutingLogIndex.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Bootstrap-DevSeat.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\AutoCapture-PlanHUI.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\AnalyzerStats.psm1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Analyze-WarmRunDiffHotspots.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Analyze-UserActionTelemetry.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Analyze-SiteCacheProviderReasons.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Analyze-SharedCacheStoreState.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Analyze-PortBatchSiteMix.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Analyze-PortBatchReadyTelemetry.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Analyze-PortBatchIntervals.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Analyze-PortBatchGapTimeline.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Analyze-PortBatchGapBreakdown.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Analyze-ParserSchedulerLaunch.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Analyze-InterfaceSyncTiming.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Analyze-FreshnessTelemetry.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Analyze-DispatchHarnessSweep.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Analyze-DispatcherGaps.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Add-PortBatchReadyTelemetry.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-IncrementalLoadingChecklist.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Get-ModuleImportGraph.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Generate-QueueDelaySummary.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-IncidentDrill.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Generate-PlanHReport.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-HeadlessRun.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-FeatureFlagAudit.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Generate-IncrementalPerformanceReport.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-DispatcherHarnessWithEvidence.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Export-RoutingOfflineBundle.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Expand-RoutingOfflineBundle.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Expand-MockLogCorpus.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Convert-RoutingDiscoveryCapture.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Convert-RoutingCliCaptureToDiscoveryCapture.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Convert-RouteRecordsToHealthSnapshot.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\ConcurrencyOverrideGuard.psm1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Compare-SchedulerAndPortDiversity.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Compare-RouteHealthSnapshots.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Collect-LocationStartupSnapshot.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Clean-ArtifactsAndBundle.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-DesktopUIHarness.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-DailyRollupScheduled.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-DailyMetricRollup.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-DailyHealthCheck.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-CIHarness.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-CablesSmokeTest.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-AllChecks.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Install-PreCommitHooks.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Inspect-SharedCacheSnapshot.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Initialize-SharedCacheSeed.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-StateTraceVerification.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-StateTraceUiDiagnostics.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-StateTraceScheduledVerification.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-StateTracePipeline.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-StabilityTests.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-SpanViewSmokeTest.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-SharedCacheWarmup.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-SearchAlertsSmokeTest.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-ScheduledHarnessSmoke.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-SanitizationWorkflow.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-RoutingValidationRun.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-RoutingQueueSweep.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-RoutingOfflineDemo.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-RoutingLogExplorer.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-RoutingDiscoveryPipeline.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-RoutingCliCaptureSession.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-RoutingBundleReview.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-PostIncidentVerification.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-PlanHChecks.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-PlanHBundle.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-InterfacesViewSmokeTest.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-InterfacesViewChecklist.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-InterfaceDispatchHarness.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\New-TelemetryBundle.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\New-SessionLogStub.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\New-RoutingCliCaptureSession.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\New-RollbackBundle.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\New-ReleaseManifest.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\New-ReleaseEvidenceBundle.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\New-ModuleDocumentation.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\New-BalancedRoutingHostList.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\New-ArchitectureDecisionRecord.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\NetworkGuard.psm1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Measure-UiResponsiveness.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Maintain-AccessDatabases.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Launch-MainWindow.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-WarmRunTelemetry.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-WarmRunRegression.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Invoke-UiCleanupAudit.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Run-PlanHHeadless.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Rollup-IngestionMetrics.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Resolve-SharedCacheSnapshot.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Reset-OnlineModeFlags.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Report-UnusedScripts.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Report-UnusedExports.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Repair-AccessDatabase.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Publish-TelemetryBundle.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Pack-StateTrace.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Show-RoutingLogSummary.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Show-ReleaseReadiness.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Show-PlanHReadiness.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Schedule-VerificationTask.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Schedule-DailyRollupTask.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Sanitize-PostmortemLogs.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\SkipSiteCacheUpdateGuard.psm1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Simulate-PlanHUIRun.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Show-TelemetryBundleSummary.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Start-StateTraceApi.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Start-ConnectivityMonitor.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Switch-Capture.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Switch-CheckSVI.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Switch-CreateLog2.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Switch-CreateLog.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Switch-CR.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Switch-Connect.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Switch-ConfigVlan1.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Switch-Configure.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Switch-ConfigRadius.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Switch-CheckSVI2.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Switch-Init.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Switch-FixVlan1.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Switch-Detect.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Switch-CreateProperLog.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Sync-TaskBoard.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Switch-Session.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Switch-Interact.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Synthesize-InterfaceSyncTelemetry.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Synthesize-ParserSchedulerTelemetry.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-Accessibility.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Update-QueueDelayHistory.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Update-PortBatchHistory.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Update-ParserSchedulerHistory.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Update-InterfaceSyncHistory.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\UiHarnessHelpers.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\ToolingJson.psm1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-UiResponsiveness.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-TelemetryIntegrity.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-TelemetryBundleReadiness.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-TaskBoardIntegrity.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-SpanViewBinding.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-SharedCacheSnapshot.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-SharedCacheEviction.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-SharedCacheCompatibility.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-RoutingSchemas.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-RoutingRealDeviceEvidence.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-RoutingOnlineCaptureReadiness.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-RoutingOfflineBundle.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-RoutingDiscoveryBaseline.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-ResponsiveLayout.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-RedactionCompliance.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-QueueDelayThreshold.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-PortBatchSiteDiversity.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-PlanTaskBoardDrift.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-PlanHReadiness.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-ParserSchedulerFairness.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-OfflineFirstEvidence.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-NetOpsEvidence.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-LogParser.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-InstallSmoke.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-IncrementalTelemetryCompleteness.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-IncidentClosureEvidence.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-HarnessSmoke.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-DocSyncChecklist.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-DependencyPreflight.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-DatabaseConsistency.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Tools\Test-CompareTelemetrySmoke.ps1 | Tools |  |  |  |  |  |  | Reviewed |
| Resources\SharedStyles.xaml | Resources/Templates/Themes |  |  |  |  |  |  | Reviewed |
| Templates\ShowCommands.json | Resources/Templates/Themes |  |  |  |  |  |  | Reviewed |
| Templates\Cisco.json | Resources/Templates/Themes |  |  |  |  |  |  | Reviewed |
| Templates\Brocade.json | Resources/Templates/Themes |  |  |  |  |  |  | Reviewed |
| Themes\w40k-salamanders.json | Resources/Templates/Themes |  |  |  |  |  |  | Reviewed |
| Themes\spud-runner.json | Resources/Templates/Themes |  |  |  |  |  |  | Reviewed |
| Themes\high-contrast.json | Resources/Templates/Themes |  |  |  |  |  |  | Reviewed |
| Themes\high-contrast-white.json | Resources/Templates/Themes |  |  |  |  |  |  | Reviewed |
| Themes\helldivers-spill-oil.json | Resources/Templates/Themes |  |  |  |  |  |  | Reviewed |
| Themes\bros.json | Resources/Templates/Themes |  |  |  |  |  |  | Reviewed |
| Themes\blue-angels.json | Resources/Templates/Themes |  |  |  |  |  |  | Reviewed |
| Themes\base.json | Resources/Templates/Themes |  |  |  |  |  |  | Reviewed |
| Troubleshooting\Invoke-StateTraceDiagnostics.ps1 | Troubleshooting |  |  |  |  |  |  | Reviewed |
| Troubleshooting\README.md | Troubleshooting |  |  |  |  |  |  | Reviewed |
| Troubleshooting\KnowledgeBase.yml | Troubleshooting |  |  |  |  |  |  | Reviewed |
| Tests\Test-Accessibility.ps1 | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Invoke-MainWindowSmokeTest.ps1 | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\manifests\Synthetic-5.1.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\manifests\CISmoke.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\README.md | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Vendors\PaloAlto\show_system_info.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Vendors\PaloAlto\show_routing_route.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Vendors\PaloAlto\show_interface_all.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\RoutingDiscoveryCapture.sample.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\RouteRecords.sample.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\RouteRecord.sample.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\RouteHealthSnapshot.sample.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\RouteHealthSnapshot.expected.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\LiveSwitch\show_vlan_brief.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\LiveSwitch\show_version.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\LiveSwitch\show_spanning-tree.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\LiveSwitch\show_running-config.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\LiveSwitch\show_power_inline.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\LiveSwitch\show_mac_address-table.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\LiveSwitch\show_logging.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\LiveSwitch\show_ip_interface_brief.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\LiveSwitch\show_inventory.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\LiveSwitch\show_interfaces_status.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\LiveSwitch\show_interfaces.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\LiveSwitch\show_cdp_neighbors_detail.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\LiveSwitch\show_cdp_neighbors.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\LiveSwitch\LAB-C9200L-AS-01.log | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Vendors\Juniper\show_version.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Vendors\Juniper\show_route.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Vendors\Juniper\show_interfaces_terse.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Vendors\Aruba\show_vlan.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Vendors\Aruba\show_version.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Vendors\Aruba\show_interface_brief.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\RouteDiff\RoutingDiff.sample.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\RouteDiff\RouteRecords.old.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\RouteDiff\RouteRecords.new.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\RouteDiff\RouteHealthSnapshot.old.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\RouteDiff\RouteHealthSnapshot.new.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\LogExplorer\RoutingValidationRunSummary.sample.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\LogExplorer\RoutingDiscoveryPipelineSummary.sample.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\CISmoke\WarmRunTelemetry.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\CISmoke\SharedCacheSeed.clixml | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\CISmoke\IngestionMetrics.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Synthetic\5.1\IngestionMetrics.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\RealDeviceEvidence\RoutingValidationRunSummary.sample.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\RealDeviceEvidence\PreflightSummary.sample.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\RealDeviceEvidence\OperatorRun.sample.log | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\RealDeviceEvidence\OperatorEvidence.sample.md | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\LogExplorer\LatestCompare\RoutingDiscoveryPipelineSummary.previous.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\LogExplorer\LatestCompare\RoutingDiscoveryPipelineSummary.latest.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\LogExplorer\LatestCompare\Index.latestcompare.sample.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\LogExplorer\Index.sample.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\CliCaptureSession\Hosts.sample.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\LogExplorer\Compare\RoutingDiscoveryPipelineSummary.old.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\LogExplorer\Compare\RoutingDiscoveryPipelineSummary.new.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\LogExplorer\Compare\RoutingDiscoveryPipelineSummary.missingSnapshot.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\LogViewer\RoutingDiscoveryPipelineSummary.sample.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\CliCaptureSession\CiscoIOSXE\WLLS-A01-AS-01_show_ip_route.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\CliCaptureSession\CiscoIOSXE\Session.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\CliCaptureSession\AristaEOS\WLLS-A01-AS-02_show_ip_route.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\CliCaptureSession\AristaEOS\Session.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\CliCapture\CiscoIOSXE\show_ip_route.txt | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\CliCapture\CiscoIOSXE\Capture.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\CliCapture\AristaEOS\Capture.json | Tests |  |  |  |  |  |  | Reviewed |
| Tests\Fixtures\Routing\CliCapture\AristaEOS\show_ip_route.txt | Tests |  |  |  |  |  |  | Reviewed |
| docs\CODEX_PLAN_AUTOMATION_MATRIX.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\CODEX_BACKLOG.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\CODEX_SHARED_CACHE_DIAGNOSTICS.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\CODEX_OPERATIONS_GUIDE.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\CODEX_SESSION_CHECKLIST.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\CODEX_AUTONOMY_PLAN.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\CODEX_INSTRUCTION_STACK.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\CODEX_RUNBOOK.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\CODEX_DOC_SYNC_PLAYBOOK.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\CODEX_QUICK_START.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\Core_Ideas.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\Release.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\RiskRegister.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\StateTrace_Quarterly_Roadmap.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\StateTrace_AI_Agent_Guide.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\StateTrace_TaskBoard.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\taskboard\TaskBoard.csv | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\Database_Recovery.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\UserAction_Telemetry.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\Telemetry_Bundle_Verification.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\Schedule_Verification.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\Schedule_Daily_Rollup.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\Routing_RealDeviceValidation.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\Routing_QuickStart.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\PlanH_UI_Capture_Local.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\PlanH_Headless_Automation.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\PlanH_Bundle_Workflow.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\Onboarding_Screenshots.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\Incremental_Loading_Performance.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\Incident_INC0006_DispatcherThroughputDrop.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\Incident_INC0005_CacheProviderFallback.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\Incident_INC0004_BulkStageLatencySpike.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\Incident_INC0003_PortBatchMissing.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\Incident_INC0002_SharedCacheRefresh.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\Incident_INC0001_RoutingQueueDelay.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\Incident_Drill_Schedule.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\Identity_RBAC_Rollout.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\runbooks\Freshness_Telemetry.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\plans\PlanG_ReleaseGovernance.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\telemetry\Phase1_metrics.md | Docs |  |  |  |  |  |  | Reviewed |
| docs\telemetry\Automation_Gates.md | Docs |  |  |  |  |  |  | Reviewed |
| Data\ValidationStandards.json | Data |  |  |  |  |  |  | Reviewed |
| Data\StateTraceSettings.json | Data |  |  |  |  |  |  | Reviewed |
| Data\ScheduledReports.json | Data |  |  |  |  |  |  | Reviewed |
| Data\IngestionHistory\WLLS.json | Data |  |  |  |  |  |  | Reviewed |
| Data\CableDatabase.json | Data |  |  |  |  |  |  | Reviewed |
| Data\IngestionHistory\BOYO.json | Data |  |  |  |  |  |  | Reviewed |
| Data\ConfigTemplates.json | Data |  |  |  |  |  |  | Reviewed |

