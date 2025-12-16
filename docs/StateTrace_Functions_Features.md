# StateTrace Function & Feature Directory

## Purpose
- Provide a stable map of modules, functions, and cross-module responsibilities so automated edits do not remove core behaviour.
- Summaries prioritise critical dependencies, data sources, and side effects that the UI relies on.

## Architecture Overview
- PowerShell 5.x WPF desktop app (`Main/MainWindow.ps1` + XAML) orchestrates view modules listed in `Modules/ModulesManifest.psd1`.
- Device data is stored per site in Access `.accdb` databases under `Data/`, populated by the parser (`Modules/ParserWorker.psm1`).
- UI modules share state through globals (e.g. `$global:DeviceMetadata`, `$global:DeviceInterfaceCache`, `$global:AllInterfaces`, `$global:alertsView`) populated by `DeviceCatalogModule`/`DeviceRepositoryModule` and initialised for the UI by `FilterStateModule::Initialize-DeviceFilters`.
- Vendor-specific parsing (`Modules/CiscoModule.psm1`, `Modules/BrocadeModule.psm1`, `Modules/AristaModule.psm1`) uses helpers from `Modules/DeviceParsingCommon.psm1` (e.g. `Invoke-RegexTableParser`) and produces normalized interface objects consumed across the UI.
- Theming infrastructure (`Themes/*.json` via `Modules/ThemeModule.psm1`) supplies brushes/styles merged into WPF resources at startup.
- Port Reorg workflow (`Modules/PortReorgModule.psm1` + `Modules/PortReorgViewModule.psm1` + `Views/PortReorgWindow.xaml`) provides an interactive label-driven mapping UI and generates vendor-specific change + rollback scripts.

## Data Stores & Core Caches
- `Data/*.accdb`: per-site Access databases with `DeviceSummary`, `Interfaces`, and history tables created/maintained by `DatabaseModule` + `ParserWorker`.
- `Logs/`: diagnostic log output when `$Global:StateTraceDebug` is set; driven by `Write-Diag`.
- In-memory globals: `DeviceMetadata` (host -> site/zone/building/room), `DeviceInterfaceCache` (hostname -> interface list), `AllInterfaces` (filtered working set), `AlertsList`. Template JSON caching now lives inside `TemplatesModule` (`ConfigurationTemplateCache`).
## Main Application Shell

### Layout (`Main/MainWindow.xaml`)
- Row 0 toolbar: host dropdown, `Scan Logs`, `Clear cache before scan`, `Load from DB`, archive/history checkboxes.
- Row 1 location filters: site/zone/building/room dropdowns (scopes Summary/Interfaces/Search/Alerts).
- Row 2 command bar: Show Commands buttons (`ShowCiscoButton`, `ShowBrocadeButton`), `BrocadeOSDropdown`, `HelpButton`, `ThemeSelector`, debug toggle.
- Row 3 content: TabControl hosting Summary, Interfaces, SPAN, Search Interfaces, Templates, Alerts; Compare sidebar lives in grid column `CompareHost` (width toggled in code).
- Row 4 status: parser status strip + site freshness indicator.

### Script Logic (`Main/MainWindow.ps1`)
- `Main/MainWindow.ps1:19` `Write-Diag` - gated logger that writes verbose lines and timestamped files when `$Global:StateTraceDebug` is true.
- `Main/MainWindow.ps1:256` `Set-ShowCommandsOSVersions` - populates the Brocade OS dropdown using `TemplatesModule::Get-ShowCommandsVersions`.
- `Main/MainWindow.ps1:271` `Set-BrocadeOSFromConfig` - selects the default Brocade OS based on `ShowCommands.json` metadata.
- `Main/MainWindow.ps1:280` `Initialize-View` - invokes each `New-*View` module with `Window` and `ScriptDir`; drives tab initialisation.
- `Main/MainWindow.ps1:483` `Initialize-ThemeSelector` - populates the theme selector and applies themes via `ThemeModule::Set-StateTraceTheme`.
- `Main/MainWindow.ps1:342` `Set-EnvToggle` - writes boolean toggles (`IncludeArchive`, `IncludeHistorical`) into the process environment for the parser to read.
- `Main/MainWindow.ps1:357` `Invoke-StateTraceRefresh` - handler for `Scan Logs`; updates env flags, calls `Invoke-StateTraceParsing`, then refreshes summaries, filters, and Compare view.
- `Main/MainWindow.ps1:1101` `Update-FreshnessIndicator` - updates the bottom-of-window freshness label from ingest history/telemetry.
- `Main/MainWindow.ps1:1183` `Reset-ParserCachesForRefresh` - clears cached ingestion history/interfaces before a refresh when requested.
- `Main/MainWindow.ps1:441` `Get-HostnameChanged` - synchronous device selection handler; loads device details and SPAN info for the chosen host.
- `Main/MainWindow.ps1:464` `Import-DeviceDetailsAsync` - background loader that fetches summary/interface/template data via `DeviceDetailsModule::Get-DeviceDetailsData` and marshals results to the UI thread through `InterfaceModule::Set-InterfaceViewData`.
- `Main/MainWindow.ps1:686` `Request-DeviceFilterUpdate` - debounced filter refresh guarded by `FilterStateModule::Get-FilterFaulted` and `$global:ProgrammaticFilterUpdate`.
- `Main/MainWindow.ps1:705` `Get-FilterDropdowns` - resolves site/zone/building/room combo boxes so change handlers can be wired once.
- Event wiring: Scan Logs ? `Invoke-StateTraceRefresh`; Load from DB ? catalog refresh without parsing; hostname dropdown ? `Get-HostnameChanged`; filter combos ? `Request-DeviceFilterUpdate`; Show Commands buttons ? clipboard exporters; Theme selector ? `Set-StateTraceTheme`; Help opens `Views/HelpWindow.xaml` and launches the Operators Runbook quickstart anchor.
## Module Reference

### `Modules/DatabaseModule.psm1`
- `Modules/DatabaseModule.psm1:51` `Open-DbReadSession` / `Modules/DatabaseModule.psm1:98` `Close-DbReadSession` - wrap an OleDb connection in a disposable session object.
- `Modules/DatabaseModule.psm1:109` `New-AccessDatabase` - creates Access databases, tables (`DeviceSummary`, `Interfaces`, history), adds indexes, and backfills newer columns (`AuthBlock`, `Config`, `PortColor`, `ConfigStatus`).
- `Modules/DatabaseModule.psm1:320` `Invoke-DbQuery` - runs SELECT statements returning a `DataTable`, optionally reusing an open session.
- `Modules/DatabaseModule.psm1:21` `Get-SqlLiteral` - escapes single quotes for SQL literals.
- Imported lazily by other modules via `Import-DatabaseModule` / `Ensure-DatabaseModule`; keep file path and exported function names stable.
### `Modules/DeviceRepositoryModule.psm1`
- `Modules/DeviceRepositoryModule.psm1:32` `Get-DataDirectoryPath` - resolves the repo `Data/` location so modules share a single Access root.
- `Modules/DeviceRepositoryModule.psm1:49` `Get-SiteFromHostname` / `Modules/DeviceRepositoryModule.psm1:74` `Get-DbPathForSite` / `Modules/DeviceRepositoryModule.psm1:83` `Get-DbPathForHost` - normalise hostnames into site codes and map them to Access database paths.
- `Modules/DeviceRepositoryModule.psm1:90` `Get-AllSiteDbPaths` - enumerates available per-site `.accdb` files for catalog refreshes.
- `Modules/DeviceRepositoryModule.psm1:101` `Clear-SiteInterfaceCache` - resets cached interface data (paired with `Update-SiteZoneCache`).
- `Modules/DeviceRepositoryModule.psm1:133` `Update-SiteZoneCache` - loads interface data for a site/zone into `$global:DeviceInterfaceCache` and `$global:AllInterfaces`.
- `Modules/DeviceRepositoryModule.psm1:205` `Invoke-ParallelDbQuery` - executes Access queries across multiple sites using runspace fan-out.
- `Modules/DeviceRepositoryModule.psm1:249` `Get-GlobalInterfaceSnapshot` - returns snapshot arrays for the requested site/zone filters without mutating globals; `Modules/DeviceRepositoryModule.psm1:310` `Update-GlobalInterfaceList` wraps the snapshot to keep `$global:AllInterfaces` populated for legacy callers.
- `Modules/DeviceRepositoryModule.psm1:311` `Get-InterfacesForSite` - fetches all interface rows for a site (optionally filtered by zone) when caches need rebuilding.
- `Modules/DeviceRepositoryModule.psm1:537` `Get-InterfaceInfo` - returns cached interface objects for a host; falls back to DB queries when the cache misses.
- `Modules/DeviceRepositoryModule.psm1:670` `Get-InterfaceConfiguration` - assembles configuration text for selected ports (used by Templates and Compare).
- `Modules/DeviceRepositoryModule.psm1:833` `Get-InterfacesForHostsBatch` - single query returning interfaces and metadata for a host collection (speeds bulk lookups).
### `Modules/DeviceCatalogModule.psm1`
- `Modules/DeviceCatalogModule.psm1:7` `Get-DeviceSummaries` - loads per-site metadata, populates `$global:DeviceMetadata`, and returns the host list used to seed filters.
- `Modules/DeviceCatalogModule.psm1:80` `Get-InterfaceHostnames` - filters cached hostnames by site/zone/building/room selections for Interfaces/Search/Compare views.

### `Modules/DeviceDetailsModule.psm1`
- `Modules/DeviceDetailsModule.psm1:3` `Get-DeviceDetails` - thin wrapper returning the device details DTO for synchronous callers.
- `Modules/DeviceDetailsModule.psm1:13` `Get-DeviceDetailsData` - loads summary/interfaces/templates from the per-site database and returns a blank DTO when the database is missing.
- `Modules/DeviceDetailsModule.psm1:55` `Get-DatabaseDeviceSummary` - queries Access summaries with history fallback for missing fields.
- `Modules/DeviceDetailsModule.psm1:105` `Get-DeviceHistoryFallback` - reads the latest history row to backfill make/model/uptime/building/room.

### `Modules/DeviceInsightsModule.psm1`
- `Modules/DeviceInsightsModule.psm1:7` `Get-SearchRegexEnabled` / `Modules/DeviceInsightsModule.psm1:14` `Set-SearchRegexEnabled` - toggle regex mode for the Search tab filter box.
- `Modules/DeviceInsightsModule.psm1:21` `Update-SearchResults` - filters `$global:AllInterfaces` by search term, status/auth filters, and current location selection before updating the Search view.
- `Modules/DeviceInsightsModule.psm1:125` `Update-Summary` - recalculates device/interface metrics for the Summary tab and ensures repository caches stay populated.
- `Modules/DeviceInsightsModule.psm1:226` `Update-Alerts` - rebuilds the alerts dataset (`$global:AlertsList`) using status/auth thresholds and returns view-ready objects.
- `Modules/DeviceInsightsModule.psm1:297` `Update-SearchGrid` - redraws the Search grid after state changes, wiring column formats and totals.

### `Modules/FilterStateModule.psm1`
- `Modules/FilterStateModule.psm1:36` `Get-SelectedLocation` - reads the active site/zone/building/room selections from the main window.
- `Modules/FilterStateModule.psm1:60` `Get-LastLocation` - returns the last recorded filter selections for reuse by other modules.
- `Modules/FilterStateModule.psm1:74` `Resolve-SelectionValue` - normalises UI selections against available options and sentinels.
- `Modules/FilterStateModule.psm1:100` `Set-DropdownItems` - helper to assign ItemsSource/selection on dropdown controls.
- `Modules/FilterStateModule.psm1:115` `Initialize-DeviceFilters` - initialises host/site filter controls and refreshes the global interface list.
- `Modules/FilterStateModule.psm1:212` `Update-DeviceFilter` - core filter engine triggered by UI events; uses ViewStateService snapshots to populate dropdowns and refreshes search/summary/alerts.
- `Modules/FilterStateModule.psm1:426` `Set-FilterFaulted` / `Get-FilterFaulted` - toggle and read the guard flag used by the filter debounce timer.
### `Modules/InterfaceModule.psm1`
- `Modules/InterfaceModule.psm1:88` `Get-SelectedInterfaceRows` - returns checked or selected rows from the Interfaces DataGrid (used for copy/export/compare actions).
- `Modules/InterfaceModule.psm1:127` `Get-InterfaceSiteCode` / `Modules/InterfaceModule.psm1:134` `Resolve-InterfaceDatabasePath` - map hostnames to site database paths.
- `Modules/InterfaceModule.psm1:159` `Ensure-DatabaseModule` - one-time import guard for `DatabaseModule`.
- `Modules/InterfaceModule.psm1:224` `Get-PortSortKey` - wrapper over the shared port-sort helper in `Modules/PortNormalization.psm1`.
- `Modules/InterfaceModule.psm1:263` `New-InterfaceObjectsFromDbRow` - converts DB rows into PSCustomObjects enriched with template/tooltips, location metadata, and `IsSelected` property.
- `Modules/InterfaceModule.psm1:501` `Get-InterfaceInfo` - module-level helper returning cached interface objects.
- `Modules/InterfaceModule.psm1:510` `Get-InterfaceList` - prefers ViewStateService snapshots for the active site/zone context and falls back to cached or database data to return sorted port names for Compare view dropdowns.
- `Modules/InterfaceModule.psm1:680` `Get-InterfaceConfiguration` - delegates to `DeviceRepositoryModule::Get-InterfaceConfiguration`. 
- `Modules/InterfaceModule.psm1:693` `Get-SpanningTreeInfo` - delegates to `DeviceRepositoryModule\Get-SpanningTreeInfo` (used by the SPAN view).
- Templates are resolved via `Modules/TemplatesModule.psm1:275` `Get-ConfigurationTemplates` (InterfaceModule no longer re-exports a wrapper).
- `Modules/InterfaceModule.psm1:982` `Set-InterfaceViewData` - applies device detail DTOs to the Interfaces view (summary fields, grid, template dropdown).
- `Modules/InterfaceModule.psm1:708` `New-InterfacesView` - loads Interfaces tab XAML, wires filter debounce, config dropdown binding, copy button, and integrates with Compare selection.

### `Modules/PortNormalization.psm1`
- `Modules/PortNormalization.psm1:106` `Get-PortSortKey` - canonical port sorting key + cache used by InterfaceModule/DeviceRepositoryModule.
- `Modules/PortNormalization.psm1:235` `Get-PortSortCacheStatistics` - exposes cache hit/miss counters for telemetry.
### `Modules/ThemeModule.psm1`
- `Modules/ThemeModule.psm1:37` `Get-ThemeDirectory` / `Modules/ThemeModule.psm1:44` `Get-ThemeFile` - resolve theme asset locations under `Themes/` and `Resources/SharedStyles.xaml`.
- `Modules/ThemeModule.psm1:63` `Read-ThemeDefinition` / `Modules/ThemeModule.psm1:85` `Resolve-ThemeTokens` - load theme JSON, apply inheritance, and build token dictionaries cached for reuse.
- `Modules/ThemeModule.psm1:273` `Set-StateTraceTheme` - applies a theme, updates resource dictionaries, and triggers registered change handlers.
- `Modules/ThemeModule.psm1:343` `Initialize-StateTraceTheme` - selects a default theme on startup and ensures resources are merged into the application.
- `Modules/ThemeModule.psm1:416` `Get-AvailableStateTraceThemes` / `Modules/ThemeModule.psm1:455` `Register-StateTraceThemeChanged` - enumerate installed themes and register callbacks for dynamic updates.

### `Modules/TelemetryModule.psm1`
- `Modules/TelemetryModule.psm1:3` `Initialize-StateTraceDebug` - ensures `$Global:StateTraceDebug` exists and optionally turns on verbose output when debug mode is enabled.
- `Modules/TelemetryModule.psm1:29` `Import-InterfaceCommon` - shared import guard for `Modules/InterfaceCommon.psm1` so modules avoid duplicating `Get-Module`/`Import-Module` probes.
- `Modules/TelemetryModule.psm1:53` `Get-SpanDebugLogPath` / `Modules/TelemetryModule.psm1:82` `Write-SpanDebugLog` - centralized span debug logging helpers used by SpanView/DeviceRepository.
- `Modules/TelemetryModule.psm1:110` `Get-TelemetryLogDirectory` / `Modules/TelemetryModule.psm1:126` `Get-TelemetryLogPath` - resolves the JSONL telemetry output file (supports `STATETRACE_TELEMETRY_DIR` override for tests).
- `Modules/TelemetryModule.psm1:160` `Write-StTelemetryEvent` - appends a single JSON event line to the daily telemetry file using a cross-process mutex.
- `Modules/TelemetryModule.psm1:196` `Remove-ComObjectSafe` - best-effort COM cleanup helper used by persistence/parser modules.

### `Modules/StatisticsModule.psm1`
- `Modules/StatisticsModule.psm1:3` `Get-PercentileValue` - shared percentile helper (used by VerificationModule and telemetry tooling).

### `Modules/VerificationModule.psm1`
- `Modules/VerificationModule.psm1:9` `Test-WarmRunRegressionSummary` - evaluates warm-run regression summaries against improvement/hit-ratio/miss thresholds (verification harness).
- `Modules/VerificationModule.psm1:143` `Test-SharedCacheSummaryCoverage` - validates shared-cache summary coverage and required site lists (shared-cache warmup + verification).
- `Modules/VerificationModule.psm1:310` `Test-InterfacePortQueueDelay` - evaluates InterfacePortQueueMetrics queue delay P95/P99 thresholds.

### `Modules/WarmRun.Telemetry.psm1`
- `Modules/WarmRun.Telemetry.psm1:3` `ConvertTo-NormalizedProviderCounts` - normalizes provider count hash tables for reporting.
- `Modules/WarmRun.Telemetry.psm1:34` `Convert-MetricsToSummary` - converts InterfaceSiteCacheMetrics telemetry events into per-host pass summary objects.
- `Modules/WarmRun.Telemetry.psm1:103` `Measure-ProviderMetricsFromSummaries` - aggregates provider counts and cache hit ratio, weighting by HostCount.
- `Modules/WarmRun.Telemetry.psm1:303` `Resolve-SiteCacheProviderReasons` - reconciles provider-reason fields from InterfaceSyncTiming/DatabaseWriteBreakdown telemetry onto summaries.

### `Modules/ViewCompositionModule.psm1`
- `Modules/ViewCompositionModule.psm1:3` `Set-StView` - loads a XAML view into a host `ContentControl`, optionally storing the instance in a global for cross-module access.
- `Modules/ViewCompositionModule.psm1:56` `New-StDebounceTimer` - creates a DispatcherTimer that runs an action after an idle delay (used by the Interfaces/Search debounced filters).
- `Modules/ViewCompositionModule.psm1:74` `Export-StRowsToCsv` - exports view rows to CSV via a shared SaveFileDialog.

### `Modules/ViewStateService.psm1`
- `Modules/ViewStateService.psm1:14` `Import-ViewStateServiceModule` - shared import guard so consumers can depend on `ViewStateService\*` commands without duplicating path probes.
- `Modules/ViewStateService.psm1:31` `Get-SequenceCount` / `Modules/ViewStateService.psm1:60` `ConvertTo-FilterValue` - shared helpers used when building filter dropdowns and counts.
- `Modules/ViewStateService.psm1:137` `Get-InterfacesForContext` - hydrates `$global:AllInterfaces`, caches site/zone selections, and returns filtered interface lists for downstream consumers.
- `Modules/ViewStateService.psm1:312` `Get-FilterSnapshot` - produces sorted site/zone/building/room collections and determines the suggested `ZoneToLoad` value.
- `Modules/ViewStateService.psm1:496` `Get-ZoneLoadHint` - resolves the default zone when filters or data are ambiguous.

### `Modules/CompareViewModule.psm1`
- `Modules/CompareViewModule.psm1:55` `Resolve-CompareControls` - caches references to Compare view dropdowns, textboxes, and labels after XAML load.
- `Modules/CompareViewModule.psm1:73` `Get-HostString` - normalises combo box items into plain hostnames.
- `Modules/CompareViewModule.psm1:173` `Get-HostsFromMain` - builds the host list using `ViewStateService` snapshots (with `DeviceMetadata` fallback) so Compare view mirrors current site/zone/building selections.
- `Modules/CompareViewModule.psm1:326` `Get-PortSortKey` - delegates to `InterfaceModule::Get-PortSortKey`.
- `Modules/CompareViewModule.psm1:333` `Get-PortsForHost` - derives port names from `ViewStateService` interface snapshots (falling back to `InterfaceModule` helpers when caches are empty).
- `Modules/CompareViewModule.psm1:434` `Set-PortsForCombo` - populates port dropdowns and preserves selection.
- `Modules/CompareViewModule.psm1:473` `Get-GridRowFor` - fetches the interface PSCustomObject for a given host/port (using cache or DB query).
- `Modules/CompareViewModule.psm1:514` `Get-AuthTemplateFromTooltip` - extracts the auth template name from stored tooltips.
- `Modules/CompareViewModule.psm1:574` `Set-CompareFromRows` - updates config/diff textboxes and auth template labels for both sides.
- `Modules/CompareViewModule.psm1:689` `Show-CurrentComparison` - orchestrates retrieving selected ports and rendering diffs.
- `Modules/CompareViewModule.psm1:754` `Get-CompareHandlers` - returns handlers for host/port `SelectionChanged` events (used by `Update-CompareView`).
- `Modules/CompareViewModule.psm1:837` `Update-CompareView` - ensures the compare view is loaded, populates host/port combos, wires handlers, and toggles the compare sidebar column.
- `Modules/CompareViewModule.psm1:959` `Set-CompareSelection` - external hook to programmatically sync compare host/port selections (used by Interfaces view buttons).
### `Modules/ParserWorker.psm1`
- `Modules/ParserWorker.psm1:10` `New-Directories` - ensures parser staging directories exist before log ingestion and archive work.
- `Modules/ParserWorker.psm1:372` `Invoke-StateTraceParsing` - top-level orchestrator that prepares paths, splits logs, selects execution mode, and cleans extracted slices.

### `Modules/ParserRunspaceModule.psm1`
- `Modules/ParserRunspaceModule.psm1:3` `Invoke-DeviceParseWorker` - imports vendor modules and parses a single device log with logging and rich error handling.
- `Modules/ParserRunspaceModule.psm1:86` `Invoke-DeviceParsingJobs` - manages synchronous or runspace-pooled execution of worker jobs with FullLanguage mode enforcement.

### `Modules/DeviceParsingCommon.psm1`
- `Modules/DeviceParsingCommon.psm1:3` `Invoke-RegexTableParser` - shared regex-table extractor used by vendor parsers to convert show-command blocks into strongly typed objects with optional post-processing.
- `Modules/DeviceParsingCommon.psm1:223` `Get-InterfaceConfigBlocks` - shared running-config stanza extractor used by vendor parsers to collect per-interface config blocks without duplicating scan loops.

### `Modules/LogIngestionModule.psm1`
- `Modules/LogIngestionModule.psm1:3` `Split-RawLogs` - streams raw log files and writes per-host slices to the Extracted folder (with overflow handling for unknown hosts).
- `Modules/LogIngestionModule.psm1:127` `Clear-ExtractedLogs` - removes generated device log slices between parser runs.

### `Modules/DeviceLogParserModule.psm1`
- `Modules/DeviceLogParserModule.psm1:12` `Get-LocationDetails` - parses SNMP location tokens into building/floor/room metadata.
- `Modules/DeviceLogParserModule.psm1:52` `Get-ShowCommandBlocks` - groups log lines by executed show command for downstream parsing.
- `Modules/DeviceLogParserModule.psm1:99` `Get-DeviceMakeFromBlocks` - detects vendor from a `show version` block.
- `Modules/DeviceLogParserModule.psm1:119` `Get-SnmpLocationFromLines` - extracts location strings from log lines.
- `Modules/DeviceLogParserModule.psm1:143` `ConvertFrom-SpanningTree` - normalises spanning-tree output for SPAN summaries.
- `Modules/DeviceLogParserModule.psm1:195` `Remove-OldArchiveFolder` - prunes aged archive directories for a device.
- `Modules/DeviceLogParserModule.psm1:225` `Get-BrocadeAuthBlockFromLines` - captures Brocade authentication block text for historical storage.
- `Modules/DeviceLogParserModule.psm1:258` `Invoke-DeviceLogParsing` - processes a single device log, populates facts, and orchestrates persistence/archive steps.

### `Modules/ParserPersistenceModule.psm1`
- `Modules/ParserPersistenceModule.psm1:3` `Update-DeviceSummaryInDb` - upserts summary rows and metadata into the per-site DB.
- `Modules/ParserPersistenceModule.psm1:88` `Update-InterfacesInDb` - writes interface rows, history, tooltips, and template hints for each device.

### Vendor Parsing Modules
- `Modules/AristaModule.psm1:3` `Get-AristaDeviceFacts` - parses Arista show outputs (prompt detection, version, uptime, interfaces, MAC table, dot1x, configs) and returns a normalised device object.
- `Modules/BrocadeModule.psm1:17` `Get-BrocadeDeviceFacts` - processes Brocade logs, normalises port identifiers, aggregates MAC/auth/config data, and returns device facts; helper `Modules/BrocadeModule.psm1:214` `Get-MacTable` feeds MAC lookups.
- `Modules/CiscoModule.psm1:16` `Get-CiscoDeviceFacts` - Cisco-specific parser combining interface status, MAC table, dot1x and config sections; helper `Modules/CiscoModule.psm1:208` `Get-MacTable` normalises MAC entries.
### View Loader Modules
- `Modules/AlertsViewModule.psm1:3` `New-AlertsView` - loads Alerts tab XAML, sets `AlertsHost.Content`, exposes `$global:alertsView`, wires export-to-CSV button, and immediately calls `Update-Alerts`.
- `Modules/SummaryViewModule.psm1:3` `New-SummaryView` - loads Summary tab into `SummaryHost` and invokes `Update-Summary`.
- `Modules/SpanViewModule.psm1:161` `New-SpanView` - loads SPAN tab, exposes `$global:spanView`, defines global `Get-SpanInfo`, wires VLAN filter and refresh button (which reruns parser and refreshes current host data).
- `Modules/SearchInterfacesViewModule.psm1:7` `New-SearchInterfacesView` - loads Search tab, wires debounced search box, regex toggle, status/auth filters, export button, and seeds `$global:searchInterfacesView`.
- `Modules/TemplatesViewModule.psm1:3` `New-TemplatesView` - loads Templates tab, lists JSON files, enables reload/save/add operations, and keeps selection/editor in sync.
- `Modules/InterfaceModule.psm1:708` `New-InterfacesView` - loads Interfaces tab, wires filter debounce, copy button, compare integration, and template dropdown colour coding.
- `Modules/PortReorgViewModule.psm1:3` `Show-PortReorgWindow` - opens the Port Reorg window (drag/drop mapping + script generation) from the Interfaces tab.

### `Modules/TemplatesModule.psm1`
- `Modules/TemplatesModule.psm1:8` `script:Get-ShowConfig` - internal cached loader watching file mtime.
- `Modules/TemplatesModule.psm1:27` `Get-ShowCommandsVersions` - returns available OS version groups for a vendor.
- `Modules/TemplatesModule.psm1:49` `Get-ShowCommands` - merges common and version-specific commands, deduping while preserving order (used by Show Commands buttons).
## View Definitions (`Views/*.xaml`)
- `Views/CompareView.xaml` - Compare sidebar layout with host/port combos, config text boxes, diff panes, copy buttons, and close toggle.
- `Views/InterfacesView.xaml` - Interfaces tab layout: device summary fields, interface DataGrid with checkboxes, template dropdown, copy-to-clipboard buttons, and Compare shortcuts.
- `Views/SearchInterfacesView.xaml` - Search tab UI with text box, regex checkbox, status/auth filters, results grid, export button.
- `Views/SpanView.xaml` - SPAN tab grid, VLAN dropdown, refresh button (works with `Get-SpanInfo`).
- `Views/SummaryView.xaml` - Summary metrics labels (devices, interfaces, up/down counts, VLAN diversity, up percentage).
- `Views/TemplatesView.xaml` - Template file list, editor, OS selector, reload/save/add controls for managing JSON templates.
- `Views/AlertsView.xaml` - Alerts DataGrid and export button for down/unauthorised interfaces.
- `Views/PortReorgWindow.xaml` - Port Reorg workflow window (label parking + drag/drop mapping + change/rollback script generation).
- `Views/HelpWindow.xaml` - Modal documentation for UI sections, opened from the main Help button (the button also opens the Operators Runbook quickstart in your browser).
## Templates & Configuration Assets
- `Modules/TemplatesModule.psm1:264` `Get-ConfigurationTemplateData` - supplies cached template objects and lookup dictionaries for repository/device modules.
- `Modules/TemplatesModule.psm1:302` `Get-TemplateVendorKeyFromMake` - normalizes `DeviceSummary.Make` strings into template vendor keys (Cisco/Brocade) so callers avoid drift.
- `Templates/Cisco.json`, `Templates/Brocade.json` - port configuration templates used by `Get-ConfigurationTemplates` and Interfaces tab suggestions.
- `Templates/ShowCommands.json` - vendor/OS show command definitions backing clipboard buttons and default Brocade OS selection.
- `Themes/*.json` - theme token dictionaries consumed by `ThemeModule` and the toolbar Theme selector (add a new file and restart to install a theme).
- Template editing UI in `TemplatesViewModule` writes directly to these files; caches in `TemplatesModule` refresh on timestamp changes.
## Event & Feature Map
- `Scan Logs` button ? `Invoke-StateTraceRefresh` ? `Invoke-StateTraceParsing` ? DB updates ? `Get-DeviceSummaries` / `Update-DeviceFilter` / `Update-CompareView`.
- `Load from DB` button ? `Get-DeviceSummaries` + `Update-DeviceFilter` without invoking the parser.
- `Clear cache before scan` checkbox ? `Reset-ParserCachesForRefresh` clears cached ingestion history and interface snapshots before parsing.
- Hostname dropdown change ? `Get-HostnameChanged` (sync) + `Import-DeviceDetailsAsync` (background) ? updates Interfaces tab and SPAN data.
- Site/zone/building/room dropdowns ? `Request-DeviceFilterUpdate` ? `Update-DeviceFilter` \? cascades to `Get-GlobalInterfaceSnapshot`/`Update-GlobalInterfaceList`, Summary/Search/Alerts/Compare refreshes.
- `Include archives` / `Include history` checkboxes ? `Set-EnvToggle` writes env vars consumed by the parser when choosing log folders.
- Show Commands buttons (`ShowCiscoButton`, `ShowBrocadeButton`) ? `TemplatesModule::Get-ShowCommands` ? clipboard export with success dialogs.
- Theme selector ? `Set-StateTraceTheme` + `Register-StateTraceThemeChanged` handlers update brushes in view modules.
- Templates tab save/add ? writes JSON files, triggers `Update-TemplatesList`, cached templates refresh when timestamps change.
- Interfaces grid `Copy Selected` button ? `Get-SelectedInterfaceRows` ? clipboard export of detailed port data.
- Compare view combos ? handlers from `Get-CompareHandlers` ? `Show-CurrentComparison` / `Set-CompareFromRows` update diffs.
- Port Reorg button (Interfaces tab) ? `PortReorgViewModule::Show-PortReorgWindow` ? `PortReorgModule::New-PortReorgScripts` emits vendor-specific change + rollback scripts.
- Search tab text/filters ? `Update-SearchGrid` ? `Update-SearchResults` (respects regex toggle, status/auth filters, location filters).
- SPAN refresh button ? `Invoke-StateTraceParsing` + `Get-DeviceSummaries` / `Update-DeviceFilter` ? `Get-SpanInfo` for current host.
## Core Feature Safeguards
- Preserve the per-site Access database workflow (`Get-DbPathForHost`, `Invoke-DbQuery`, parser updates); many modules assume that structure when loading data.
- Do not remove or rename global caches (`DeviceInterfaceCache`, `DeviceMetadata`, `AllInterfaces`, `AlertsList`, `templatesView`, `interfacesView`, `spanView`, `searchInterfacesView`). Other modules read them directly.
- Preserve ThemeModule resource merges (e.g. `Set-StateTraceTheme`, `Initialize-StateTraceTheme`) so view modules continue to resolve shared brushes and colours.
- Keep `Update-DeviceFilter` side effects intact (resetting dropdowns, refreshing search/summary/alerts/compare) when altering filter logic.
- Maintain Compare view plumbing (`Update-CompareView`, `Get-CompareHandlers`, `Set-CompareSelection`, `Get-GridRowFor`); the sidebar depends on these hooks to stay in sync with filters.
- Retain Show Commands clipboard functionality backed by `TemplatesModule`; operators rely on the generated command lists.
- Preserve `Import-DeviceDetailsAsync` background loading to avoid UI stalls on large datasets.
- Ensure template metadata (`AuthTemplate`, `ConfigStatus`, `PortColor`, tooltips) continues to be populated in interface objects for both the Templates tab and Alerts colouring.
- Parser functions (`Invoke-StateTraceParsing`, vendor modules, `Update-InterfacesInDb`) must continue to populate DB tables and history; removing these breaks downstream UI updates.
## Global Variables & Environment Flags
- `$Global:StateTraceDebug` - toggles diagnostic logging and log file creation.
- `$global:StateTraceDb` / `$env:StateTraceDbPath` - optional aggregation database paths used by parser/UI when set.
- `$global:ProgrammaticFilterUpdate`, `$script:DeviceFilterUpdating`, and `FilterStateModule::Get-FilterFaulted` guard device filter refresh cycles.
- `$global:DeviceMetadata`, `$global:DeviceInterfaceCache`, `$global:AllInterfaces`, `$global:AlertsList`, `$global:templatesView`, `$global:interfacesView`, `$global:searchInterfacesView`, `$global:spanView`, `$global:alertsView` - shared state consumed across modules.
- `$env:IncludeArchive`, `$env:IncludeHistorical` - set by `Set-EnvToggle`; parser reads them to include archive/history folders.
## Module Manifest & Tests
- `Modules/ModulesManifest.psd1` - authoritative list of modules imported during startup; keep in sync when adding or renaming modules.
- `Modules/Tests/InterfaceModule.Tests.ps1` - Pester coverage for interface object creation, port sorting, and template handling. Run with `Invoke-Pester Modules\Tests` before shipping parser/interface changes.
- `Tests/Invoke-MainWindowSmokeTest.ps1` - Non-interactive smoke test that imports the module manifest and validates critical commands; outputs logs to `Logs/RefactorValidation/MainWindowSmokeTest_*.log`.
## Usage Notes
- Update this directory whenever new modules, functions, or significant behaviours are added.
- Before modifying a function, review the dependent modules listed above to avoid breaking UI flows or parser pipelines.
- When refactoring, confirm that caches (`DeviceInterfaceCache`, `DeviceMetadata`, `AllInterfaces`) and event wiring still function end-to-end by running a parser cycle and exercising each tab.
