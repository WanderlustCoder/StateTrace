# ST-D-006 Template/helper catalog alignment

## Sources
- docs/StateTrace_Functions_Features.md
- docs/UI_Smoke_Checklist.md
- docs/plans/PlanD_FeatureExpansion.md

## Automation hooks (Plan D)
- - `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` to seed incremental-loading telemetry before UI validation (per `docs/CODEX_RUNBOOK.md`).
- - `pwsh -STA -File Tools\Invoke-SpanViewSmokeTest.ps1 -Hostname <host> -PassThru` to perform headless SPAN verification; attach the summary object and `Logs/Debug/SpanDiag.log` excerpt to plan/task updates.
- - `pwsh -STA -File Tools\Test-SpanViewBinding.ps1` (or `Tools\Invoke-AllChecks.ps1`) after UI changes to capture dispatcher binding regressions; upload the log snippet referenced in `docs/notes/2025-11-07_span-view-investigation.md`.
- - `pwsh -NoLogo -File Main\MainWindow.ps1` followed by the checklist in `docs/UI_Smoke_Checklist.md` to exercise Interfaces, SPAN, Templates, and guided workflows; capture any regressions and telemetry paths.
- - `pwsh -NoLogo -File Tools\Invoke-AllChecks.ps1` (runs Pester + Span smoke harness) whenever Span view or guided workflow code changes to keep UI regression coverage documented.
- - Follow `docs/runbooks/Incremental_Loading_Performance.md` whenever Interfaces performance needs validation (pipeline hydration + analyzer run + history update).
- - `pwsh Tools\Analyze-PortBatchReadyTelemetry.ps1 -Path Logs\IngestionMetrics\<file>.json -IncludeHostBreakdown -OutputPath Logs\Reports\PortBatchReady-<date>.json [-BaselineSummaryPath Logs\Reports\PortBatchReady-<prior>.json]` to summarise incremental-loading throughput; attach the generated JSON + console summary to plan/task board updates.
- - `pwsh Tools\Update-PortBatchHistory.ps1 -ReportPaths Logs\Reports\PortBatchReady-<date>.json -HistoryPath Logs\Reports\PortBatchHistory.csv` to append the analyzer results to the trend CSV so regressions are obvious.
- - `pwsh Tools\Analyze-InterfaceSyncTiming.ps1 -Path Logs\IngestionMetrics\<file>.json -OutputPath Logs\Reports\InterfaceSyncTiming-<date>.json -TopHosts 15` to identify high UiClone/StreamDispatch p95 hosts and per-site hot spots; capture the JSON + top-host table in Plan D notes.
- - `pwsh Tools\Update-InterfaceSyncHistory.ps1 -ReportPaths Logs\Reports\InterfaceSyncTiming-<date>.json -HistoryPath Logs\Reports\InterfaceSyncHistory.csv` to track UiClone/StreamDispatch trends over time.
- - `pwsh Tools\Analyze-PortBatchIntervals.ps1 -Path Logs\IngestionMetrics\<file>.json -TopIntervals 10 -ThresholdSeconds 60` to flag idle windows between batches; log any gaps > 60 seconds in the plan so follow-up (e.g., dispatcher/queue tuning) is prioritized.
- - When authoring guided troubleshooting runbooks, pull sanitized incidents via Plan F (`Tools\Sanitize-PostmortemLogs.ps1`, `docs/StateTrace_IncidentPostmortem_Intake.md`), then document the telemetry commands in the runbook template before publishing.

## Template/helper entries (feature catalog)
- - Vendor-specific parsing (`Modules/CiscoModule.psm1`, `Modules/BrocadeModule.psm1`, `Modules/AristaModule.psm1`) uses helpers from `Modules/DeviceParsingCommon.psm1` (e.g. `Invoke-RegexTableParser`) and produces normalized interface objects consumed across the UI.
- - In-memory globals: `DeviceMetadata` (host -> site/zone/building/room), `DeviceInterfaceCache` (hostname -> interface list), `AllInterfaces` (filtered working set), `AlertsList`. Template JSON caching now lives inside `TemplatesModule` (`ConfigurationTemplateCache`).
- - Row 3 content: TabControl hosting Summary, Interfaces, SPAN, Search Interfaces, Templates, Alerts; Compare sidebar lives in grid column `CompareHost` (width toggled in code).
- - `Main/MainWindow.ps1:256` `Set-ShowCommandsOSVersions` - populates the Brocade OS dropdown using `TemplatesModule::Get-ShowCommandsVersions`.
- - `Main/MainWindow.ps1:464` `Import-DeviceDetailsAsync` - background loader that fetches summary/interface/template data via `DeviceDetailsModule::Get-DeviceDetailsData` and marshals results to the UI thread through `InterfaceModule::Set-InterfaceViewData`.
- - `Modules/DeviceRepositoryModule.psm1:670` `Get-InterfaceConfiguration` - assembles configuration text for selected ports (used by Templates and Compare).
- - `Modules/DeviceDetailsModule.psm1:13` `Get-DeviceDetailsData` - loads summary/interfaces/templates from the per-site database and returns a blank DTO when the database is missing.
- - `Modules/FilterStateModule.psm1:100` `Set-DropdownItems` - helper to assign ItemsSource/selection on dropdown controls.
- - `Modules/InterfaceModule.psm1:224` `Get-PortSortKey` - wrapper over the shared port-sort helper in `Modules/PortNormalization.psm1`.
- - `Modules/InterfaceModule.psm1:263` `New-InterfaceObjectsFromDbRow` - converts DB rows into PSCustomObjects enriched with template/tooltips, location metadata, and `IsSelected` property.
- - `Modules/InterfaceModule.psm1:501` `Get-InterfaceInfo` - module-level helper returning cached interface objects.
- - Templates are resolved via `Modules/TemplatesModule.psm1:275` `Get-ConfigurationTemplates` (InterfaceModule no longer re-exports a wrapper).
- - `Modules/InterfaceModule.psm1:982` `Set-InterfaceViewData` - applies device detail DTOs to the Interfaces view (summary fields, grid, template dropdown).
- - `Modules/TelemetryModule.psm1:53` `Get-SpanDebugLogPath` / `Modules/TelemetryModule.psm1:82` `Write-SpanDebugLog` - centralized span debug logging helpers used by SpanView/DeviceRepository.
- - `Modules/TelemetryModule.psm1:196` `Remove-ComObjectSafe` - best-effort COM cleanup helper used by persistence/parser modules.
- - `Modules/StatisticsModule.psm1:3` `Get-PercentileValue` - shared percentile helper (used by VerificationModule and telemetry tooling).
- - `Modules/ViewStateService.psm1:31` `Get-SequenceCount` / `Modules/ViewStateService.psm1:60` `ConvertTo-FilterValue` - shared helpers used when building filter dropdowns and counts.
- - `Modules/CompareViewModule.psm1:333` `Get-PortsForHost` - derives port names from `ViewStateService` interface snapshots (falling back to `InterfaceModule` helpers when caches are empty).
- - `Modules/CompareViewModule.psm1:514` `Get-AuthTemplateFromTooltip` - extracts the auth template name from stored tooltips.
- - `Modules/CompareViewModule.psm1:574` `Set-CompareFromRows` - updates config/diff textboxes and auth template labels for both sides.
- - `Modules/ParserPersistenceModule.psm1:88` `Update-InterfacesInDb` - writes interface rows, history, tooltips, and template hints for each device.
- - `Modules/BrocadeModule.psm1:17` `Get-BrocadeDeviceFacts` - processes Brocade logs, normalises port identifiers, aggregates MAC/auth/config data, and returns device facts; helper `Modules/BrocadeModule.psm1:214` `Get-MacTable` feeds MAC lookups.
- - `Modules/CiscoModule.psm1:16` `Get-CiscoDeviceFacts` - Cisco-specific parser combining interface status, MAC table, dot1x and config sections; helper `Modules/CiscoModule.psm1:208` `Get-MacTable` normalises MAC entries.
- - `Modules/TemplatesViewModule.psm1:3` `New-TemplatesView` - loads Templates tab, lists JSON files, enables reload/save/add operations, and keeps selection/editor in sync.
- - `Modules/InterfaceModule.psm1:708` `New-InterfacesView` - loads Interfaces tab, wires filter debounce, copy button, compare integration, and template dropdown colour coding.
- ### `Modules/TemplatesModule.psm1`
- - `Modules/TemplatesModule.psm1:8` `script:Get-ShowConfig` - internal cached loader watching file mtime.
- - `Modules/TemplatesModule.psm1:27` `Get-ShowCommandsVersions` - returns available OS version groups for a vendor.
- - `Modules/TemplatesModule.psm1:49` `Get-ShowCommands` - merges common and version-specific commands, deduping while preserving order (used by Show Commands buttons).
- - `Views/InterfacesView.xaml` - Interfaces tab layout: device summary fields, interface DataGrid with checkboxes, template dropdown, copy-to-clipboard buttons, and Compare shortcuts.
- - `Views/TemplatesView.xaml` - Template file list, editor, OS selector, reload/save/add controls for managing JSON templates.
- ## Templates & Configuration Assets
- - `Modules/TemplatesModule.psm1:264` `Get-ConfigurationTemplateData` - supplies cached template objects and lookup dictionaries for repository/device modules.
- - `Modules/TemplatesModule.psm1:302` `Get-TemplateVendorKeyFromMake` - normalizes `DeviceSummary.Make` strings into template vendor keys (Cisco/Brocade) so callers avoid drift.
- - `Templates/Cisco.json`, `Templates/Brocade.json` - port configuration templates used by `Get-ConfigurationTemplates` and Interfaces tab suggestions.
- - `Templates/ShowCommands.json` - vendor/OS show command definitions backing clipboard buttons and default Brocade OS selection.
- - Template editing UI in `TemplatesViewModule` writes directly to these files; caches in `TemplatesModule` refresh on timestamp changes.
- - Show Commands buttons (`ShowCiscoButton`, `ShowBrocadeButton`) ? `TemplatesModule::Get-ShowCommands` ? clipboard export with success dialogs.
- - Templates tab save/add ? writes JSON files, triggers `Update-TemplatesList`, cached templates refresh when timestamps change.
- - Do not remove or rename global caches (`DeviceInterfaceCache`, `DeviceMetadata`, `AllInterfaces`, `AlertsList`, `templatesView`, `interfacesView`, `spanView`, `searchInterfacesView`). Other modules read them directly.
- - Retain Show Commands clipboard functionality backed by `TemplatesModule`; operators rely on the generated command lists.
- - Ensure template metadata (`AuthTemplate`, `ConfigStatus`, `PortColor`, tooltips) continues to be populated in interface objects for both the Templates tab and Alerts colouring.
- - `$global:DeviceMetadata`, `$global:DeviceInterfaceCache`, `$global:AllInterfaces`, `$global:AlertsList`, `$global:templatesView`, `$global:interfacesView`, `$global:searchInterfacesView`, `$global:spanView`, `$global:alertsView` - shared state consumed across modules.
- - `Modules/Tests/InterfaceModule.Tests.ps1` - Pester coverage for interface object creation, port sorting, and template handling. Run with `Invoke-Pester Modules\Tests` before shipping parser/interface changes.

## Template/helper entries (UI smoke checklist)
- | Templates tab | Load a template, copy text via the provided button, and confirm no errors surface in the console. | Template preview should appear; clipboard operations should not throw. |

## Help overlay scan
- No docs/*overlay* files found.

## Mapping notes
- Template helper UI actions are covered by the Plan D UI smoke checklist hook (manual UI run via Main/MainWindow + docs/UI_Smoke_Checklist.md).
- No headless automation hook exists for Templates tab actions; gap aligns with ST-D-008 (UI smoke checklist automation artifact).
- Help overlay artifacts were not located; no automation hook mapped (gap noted in ST-D-006).
