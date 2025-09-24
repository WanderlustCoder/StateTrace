# StateTrace Function & Feature Directory


# StateTrace Function & Feature Directory

## Purpose
- Provide a stable map of modules, functions, and cross-module responsibilities so automated edits do not remove core behaviour.
- Summaries prioritise critical dependencies, data sources, and side effects that the UI relies on.

## Architecture Overview
- PowerShell 5.x WPF desktop app (`Main/MainWindow.ps1` + XAML) orchestrates view modules listed in `Modules/ModulesManifest.psd1`.
- Device data is stored per site in Access `.accdb` databases under `Data/`, populated by the parser (`Modules/ParserWorker.psm1`).
- UI modules share state through globals (e.g. `$global:DeviceMetadata`, `$global:DeviceInterfaceCache`, `$global:AllInterfaces`, `$global:alertsView`) populated by `DeviceCatalogModule`/`DeviceRepositoryModule` and initialised for the UI by `FilterStateModule::Initialize-DeviceFilters`.
- Vendor-specific parsing (`Modules/CiscoModule.psm1`, `Modules/BrocadeModule.psm1`, `Modules/AristaModule.psm1`) produces normalized interface objects consumed across the UI.

## Data Stores & Core Caches
- `Data/*.accdb`: per-site Access databases with `DeviceSummary`, `Interfaces`, and history tables created/maintained by `DatabaseModule` + `ParserWorker`.
- `Logs/`: diagnostic log output when `$Global:StateTraceDebug` is set; driven by `Write-Diag`.
- In-memory globals: `DeviceMetadata` (host -> site/zone/building/room), `DeviceInterfaceCache` (hostname -> interface list), `AllInterfaces` (filtered working set), `AlertsList`. Template JSON caching now lives inside `TemplatesModule` (`ConfigurationTemplateCache`).
- `ParsedData/`: transient CSV fallback when a database is missing; cleaned on exit in `Main/MainWindow.ps1`.
## Main Application Shell

### Layout (`Main/MainWindow.xaml`)
- Row 0 toolbar: host dropdown, `Scan Logs` button, archive/history checkboxes, and site/zone/building/room filters.
- Row 1 command bar: Show Commands buttons (`ShowCiscoButton`, `ShowBrocadeButton`), `BrocadeOSDropdown`, and `HelpButton`.
- Row 2 content: TabControl hosting Summary, Interfaces, SPAN, Search Interfaces, Templates, Alerts; Compare sidebar lives in grid column `CompareHost` (width toggled in code).

### Script Logic (`Main/MainWindow.ps1`)
- `Main/MainWindow.ps1:19` `Write-Diag` - gated logger that writes verbose lines and timestamped files when `$Global:StateTraceDebug` is true.
- `Main/MainWindow.ps1:168` `Set-ShowCommandsOSVersions` - populates the Brocade OS dropdown using `TemplatesModule::Get-ShowCommandsVersions`.
- `Main/MainWindow.ps1:183` `Set-BrocadeOSFromConfig` - selects the default Brocade OS based on `ShowCommands.json` metadata.
- `Main/MainWindow.ps1:191` `Initialize-View` - invokes each `New-*View` module with `Window` and `ScriptDir`; drives tab initialisation.
- `Main/MainWindow.ps1:253` `Set-EnvToggle` - writes boolean toggles (`IncludeArchive`, `IncludeHistorical`) into the process environment for the parser to read.
- `Main/MainWindow.ps1:268` `Invoke-StateTraceRefresh` - handler for `Scan Logs`; updates env flags, calls `Invoke-StateTraceParsing`, then refreshes summaries, filters, and Compare view.
- `Main/MainWindow.ps1:303` `Get-HostnameChanged` - synchronous device selection handler; loads device details and SPAN info for the chosen host.
- `Main/MainWindow.ps1:326` `Import-DeviceDetailsAsync` - background loader that fetches summary/interface/template data via `DeviceDetailsModule::Get-DeviceDetailsData` and marshals results to the UI thread through `InterfaceModule::Set-InterfaceViewData`.
- `Main/MainWindow.ps1:547` `Request-DeviceFilterUpdate` - debounced filter refresh guarded by `FilterStateModule::Get-FilterFaulted` and `$global:ProgrammaticFilterUpdate`.
- `Main/MainWindow.ps1:566` `Get-FilterDropdowns` - resolves site/zone/building/room combo boxes so change handlers can be wired once.
- Event wiring: refresh button ? `Invoke-StateTraceRefresh`; hostname dropdown ? `Get-HostnameChanged`; filter combos ? `Request-DeviceFilterUpdate`; Show Commands buttons ? clipboard exporters; Help button opens `Views/HelpWindow.xaml`.
## Module Reference

### `Modules/DatabaseModule.psm1`
- `Modules/DatabaseModule.psm1:21` `Initialize-StateTraceDatabase` - ensures the `Data/` directory exists; leaves `$global:StateTraceDb` unset so per-site DBs can be selected dynamically.
- `Modules/DatabaseModule.psm1:46` `Open-DbReadSession` / `Modules/DatabaseModule.psm1:93` `Close-DbReadSession` - wrap an OleDb connection in a disposable session object.
- `Modules/DatabaseModule.psm1:104` `New-AccessDatabase` - creates Access databases, tables (`DeviceSummary`, `Interfaces`, history), adds indexes, and backfills newer columns (`AuthBlock`, `Config`, `PortColor`, `ConfigStatus`).
- `Modules/DatabaseModule.psm1:291` `Invoke-DbNonQuery` - executes write statements against a specified `.accdb`.
- `Modules/DatabaseModule.psm1:315` `Invoke-DbQuery` - runs SELECT statements returning a `DataTable`, optionally reusing an open session.
- `Modules/DatabaseModule.psm1:21` `Get-SqlLiteral` - escapes single quotes for SQL literals.
- Imported lazily by other modules via `Import-DatabaseModule` / `Ensure-DatabaseModule`; keep file path and exported function names stable.
### `Modules/DeviceRepositoryModule.psm1`
- `Modules/DeviceRepositoryModule.psm1:49` `Get-InterfacesForHostsBatch` - single query returning interfaces and summary metadata for a set of hostnames.
- Manages per-site database paths (`Get-SiteFromHostname`, `Get-DbPathForSite`, `Get-DbPathForHost`).
- `Get-AllSiteDbPaths` enumerates available per-site Access databases for repository consumers.
- `Modules/DeviceRepositoryModule.psm1:156` `Update-SiteZoneCache` - loads per-site/per-zone interface data into shared caches.
- `Get-DataDirectoryPath` returns the resolved `Data/` directory when other modules need the absolute path.
### `Modules/FilterStateModule.psm1`
- `Modules/FilterStateModule.psm1:36` `Get-SelectedLocation` - reads the active site/zone/building/room selections from the main window.
- `Modules/FilterStateModule.psm1:55` `Get-LastLocation` - returns the last recorded filter selections for reuse by other modules.
- `Modules/FilterStateModule.psm1:67` `Set-DropdownItems` - helper to assign ItemsSource/selection on dropdown controls.
- `Modules/FilterStateModule.psm1:89` `Initialize-DeviceFilters` - initialises host/site filter controls and refreshes the global interface list.
- `Modules/FilterStateModule.psm1:147` `Update-DeviceFilter` - core filter engine triggered by UI events; repopulates dropdowns and refreshes search/summary/alerts.
- `Modules/FilterStateModule.psm1:249` `Set-FilterFaulted` / `Get-FilterFaulted` - toggle and read the guard flag used by the filter debounce timer.
### `Modules/InterfaceModule.psm1`
- `Modules/InterfaceModule.psm1:11` `Get-SelectedInterfaceRows` - returns checked or selected rows from the Interfaces DataGrid (used for copy/export/compare actions).
- `Modules/InterfaceModule.psm1:56` `Get-InterfaceSiteCode` / `Modules/InterfaceModule.psm1:63` `Resolve-InterfaceDatabasePath` - map hostnames to site database paths.
- `Modules/InterfaceModule.psm1:69` `Ensure-DatabaseModule` - one-time import guard for `DatabaseModule`.
- `Modules/InterfaceModule.psm1:84` `Get-PortSortKey` - canonical port sorting key reused by DeviceData and Compare modules.
- `Modules/InterfaceModule.psm1:130` `Get-InterfaceHostnames` - retrieves catalog data via `DeviceCatalogModule::Get-InterfaceHostnames`. 
- `Modules/InterfaceModule.psm1:139` `New-InterfaceObjectsFromDbRow` - converts DB rows into PSCustomObjects enriched with template/tooltips, location metadata, and `IsSelected` property.
- `Modules/InterfaceModule.psm1:356` `Get-InterfaceInfo` - module-level helper returning cached interface objects.
- `Modules/InterfaceModule.psm1:445` `Get-InterfaceList` - returns sorted port names for a host (used by Compare view dropdowns).
- `Modules/InterfaceModule.psm1:481` `Compare-InterfaceConfigs` - produces diff output between two port configs for display in Compare view.
- `Modules/InterfaceModule.psm1:497` `Get-InterfaceConfiguration` - delegates to `DeviceRepositoryModule::Get-InterfaceConfiguration`. 
- `Modules/InterfaceModule.psm1:515` `Get-SpanningTreeInfo` - fetches parsed spanning tree rows (backed by DB/history) for the SPAN tab.
- `Modules/InterfaceModule.psm1:538` `Get-ConfigurationTemplates` - forwards to `TemplatesModule` so the Interfaces view uses the shared cache.
- `Modules/InterfaceModule.psm1:776` `Set-InterfaceViewData` - applies device detail DTOs to the Interfaces view (summary fields, grid, template dropdown).
- `Modules/InterfaceModule.psm1:881` `Get-DeviceDetails` - retrieves device details via `DeviceDetailsModule` and calls `Set-InterfaceViewData`, emitting user-friendly errors on failure.
- `Modules/InterfaceModule.psm1:552` `New-InterfacesView` - loads Interfaces tab XAML, wires filter debounce, config dropdown binding, copy button, and integrates with Compare selection.
### `Modules/CompareViewModule.psm1`
- `Modules/CompareViewModule.psm1:25` `Resolve-CompareControls` - caches references to Compare view dropdowns, textboxes, and labels after XAML load.
- `Modules/CompareViewModule.psm1:43` `Get-HostString` - normalises combo box items into plain hostnames.
- `Modules/CompareViewModule.psm1:54` `Get-HostsFromMain` - builds the filtered host list from `$global:DeviceInterfaceCache`, honouring site/zone/building/room via `FilterStateModule::Get-LastLocation` and `DeviceRepositoryModule::Update-SiteZoneCache`.
- `Modules/CompareViewModule.psm1:171` `Get-PortSortKey` - delegates to `InterfaceModule::Get-PortSortKey`.
- `Modules/CompareViewModule.psm1:178` `Get-PortsForHost` - retrieves port names via `InterfaceModule::Get-InterfaceList` with DB fallback.
- `Modules/CompareViewModule.psm1:242` `Set-PortsForCombo` - populates port dropdowns and preserves selection.
- `Modules/CompareViewModule.psm1:281` `Get-GridRowFor` - fetches the interface PSCustomObject for a given host/port (using cache or DB query).
- `Modules/CompareViewModule.psm1:322` `Get-AuthTemplateFromTooltip` - extracts the auth template name from stored tooltips.
- `Modules/CompareViewModule.psm1:335` `Set-CompareFromRows` - updates config/diff textboxes and auth template labels for both sides.
- `Modules/CompareViewModule.psm1:465` `Show-CurrentComparison` - orchestrates retrieving selected ports and rendering diffs.
- `Modules/CompareViewModule.psm1:503` `Get-CompareHandlers` - returns handlers for host/port `SelectionChanged` events (used by `Update-CompareView`).
- `Modules/CompareViewModule.psm1:626` `Update-CompareView` - ensures the compare view is loaded, populates host/port combos, wires handlers, and toggles the compare sidebar column.
- `Modules/CompareViewModule.psm1:771` `Set-CompareSelection` - external hook to programmatically sync compare host/port selections (used by Interfaces view buttons).
### `Modules/ParserWorker.psm1`
- `Modules/ParserWorker.psm1:11` `New-Directories` - ensures parsing output directories exist.
- `Modules/ParserWorker.psm1:32` `Split-RawLogs` - streams raw log files, splitting them into per-host slices under `ExtractedLogs`.
- `Modules/ParserWorker.psm1:158` `Start-ParallelDeviceProcessing` - runspace pool worker that processes device logs concurrently with `FullLanguage` execution mode.
- `Modules/ParserWorker.psm1:288` `Clear-ExtractedLogs` - removes generated log slices between runs.
- `Modules/ParserWorker.psm1:300` `Get-SiteFromHostname` - parser-side site helper (mirrors DeviceData logic).
- `Modules/ParserWorker.psm1:318` `Invoke-StateTraceParsing` - high-level orchestrator handling archive/history flags, splitting logs, dispatching parse jobs, and refreshing DBs.
- `Modules/ParserWorker.psm1:367` `Get-LocationDetails` - extracts building/room metadata from log snippets.
- `Modules/ParserWorker.psm1:405` `Get-ShowCommandBlocks` - tokenises logs into individual show command outputs consumed by vendor parsers.
- `Modules/ParserWorker.psm1:451` `Get-DeviceMakeFromBlocks` - detects vendor from command blocks.
- `Modules/ParserWorker.psm1:470` `Get-SnmpLocationFromLines` - shared SNMP location parser.
- `Modules/ParserWorker.psm1:493` `ConvertFrom-SpanningTree` - creates structured spanning tree rows for SPAN view.
- `Modules/ParserWorker.psm1:544` `Remove-OldArchiveFolder` - cleans older archive directories to avoid growth.
- `Modules/ParserWorker.psm1:573` `Get-BrocadeAuthBlockFromLines` - pulls full Brocade authentication block text for history/storage.
- `Modules/ParserWorker.psm1:602` `Update-DeviceSummaryInDb` - upserts summary rows and metadata into the per-site DB.
- `Modules/ParserWorker.psm1:688` `Update-InterfacesInDb` - writes interface rows, history, tooltips, and template hints for each device.
- `Modules/ParserWorker.psm1:846` `Invoke-DeviceLogParsing` - per-device pipeline: detect vendor, parse via vendor module, update DB, archive log copy.
### Vendor Parsing Modules
- `Modules/AristaModule.psm1:1` `Get-AristaDeviceFacts` - parses Arista show outputs (prompt detection, version, uptime, interfaces, MAC table, dot1x, configs) and returns a normalised device object.
- `Modules/BrocadeModule.psm1:4` `Get-BrocadeDeviceFacts` - processes Brocade logs, normalises port identifiers, aggregates MAC/auth/config data, and returns device facts; helper `Modules/BrocadeModule.psm1:272` `Get-MacTable` feeds MAC lookups.
- `Modules/CiscoModule.psm1:2` `Get-CiscoDeviceFacts` - Cisco-specific parser combining interface status, MAC table, dot1x and config sections; helper `Modules/CiscoModule.psm1:266` `Get-MacTable` normalises MAC entries.
### View Loader Modules
- `Modules/AlertsViewModule.psm1:1` `New-AlertsView` - loads Alerts tab XAML, sets `AlertsHost.Content`, exposes `$global:alertsView`, wires export-to-CSV button, and immediately calls `Update-Alerts`.
- `Modules/SummaryViewModule.psm1:1` `New-SummaryView` - loads Summary tab into `SummaryHost` and invokes `Update-Summary`.
- `Modules/SpanViewModule.psm1:1` `New-SpanView` - loads SPAN tab, exposes `$global:spanView`, defines global `Get-SpanInfo`, wires VLAN filter and refresh button (which reruns parser and refreshes current host data).
- `Modules/SearchInterfacesViewModule.psm1:6` `New-SearchInterfacesView` - loads Search tab, wires debounced search box, regex toggle, status/auth filters, export button, and seeds `$global:searchInterfacesView`.
- `Modules/TemplatesViewModule.psm1:1` `New-TemplatesView` - loads Templates tab, lists JSON files, enables reload/save/add operations, and keeps selection/editor in sync.
- `Modules/InterfaceModule.psm1:552` `New-InterfacesView` - loads Interfaces tab, wires filter debounce, copy button, compare integration, and template dropdown colour coding.

### `Modules/TemplatesModule.psm1`
- `Modules/TemplatesModule.psm1:9` `Set-ShowCommandsConfigPath` - override default `ShowCommands.json` location and clear caches.
- `Modules/TemplatesModule.psm1:18` `Clear-ShowCommandsCache` - resets cached JSON and timestamp.
- `Modules/TemplatesModule.psm1:25` `script:Get-ShowConfig` - internal cached loader watching file mtime.
- `Modules/TemplatesModule.psm1:44` `Get-ShowVendors` - lists vendors defined in `ShowCommands.json`.
- `Modules/TemplatesModule.psm1:53` `Get-ShowCommandsVersions` - returns available OS version groups for a vendor.
- `Modules/TemplatesModule.psm1:75` `Get-ShowCommands` - merges common and version-specific commands, deduping while preserving order (used by Show Commands buttons).
## View Definitions (`Views/*.xaml`)
- `Views/CompareView.xaml` - Compare sidebar layout with host/port combos, config text boxes, diff panes, copy buttons, and close toggle.
- `Views/InterfacesView.xaml` - Interfaces tab layout: device summary fields, interface DataGrid with checkboxes, template dropdown, copy-to-clipboard buttons, and Compare shortcuts.
- `Views/SearchInterfacesView.xaml` - Search tab UI with text box, regex checkbox, status/auth filters, results grid, export button.
- `Views/SpanView.xaml` - SPAN tab grid, VLAN dropdown, refresh button (works with `Get-SpanInfo`).
- `Views/SummaryView.xaml` - Summary metrics labels (devices, interfaces, up/down counts, VLAN diversity, up percentage).
- `Views/TemplatesView.xaml` - Template file list, editor, OS selector, reload/save/add controls for managing JSON templates.
- `Views/AlertsView.xaml` - Alerts DataGrid and export button for down/unauthorised interfaces.
- `Views/HelpWindow.xaml` - Modal documentation for UI sections, opened from the main Help button.
## Templates & Configuration Assets
- `Modules/TemplatesModule.psm1:300` `Get-ConfigurationTemplateData` - supplies cached template objects and lookup dictionaries for repository/device modules.
- `Templates/Cisco.json`, `Templates/Brocade.json` - port configuration templates used by `Get-ConfigurationTemplates` and Interfaces tab suggestions.
- `Templates/ShowCommands.json` - vendor/OS show command definitions backing clipboard buttons and default Brocade OS selection.
- Template editing UI in `TemplatesViewModule` writes directly to these files; caches in `TemplatesModule` refresh on timestamp changes.
## Event & Feature Map
- `Scan Logs` button ? `Invoke-StateTraceRefresh` ? `Invoke-StateTraceParsing` ? DB updates ? `Get-DeviceSummaries` / `Update-DeviceFilter` / `Update-CompareView`.
- Hostname dropdown change ? `Get-HostnameChanged` (sync) + `Import-DeviceDetailsAsync` (background) ? updates Interfaces tab and SPAN data.
- Site/zone/building/room dropdowns ? `Request-DeviceFilterUpdate` ? `Update-DeviceFilter` ? cascades to `Update-GlobalInterfaceList`, Summary/Search/Alerts/Compare refreshes.
- `Include archives` / `Include history` checkboxes ? `Set-EnvToggle` writes env vars consumed by the parser when choosing log folders.
- Show Commands buttons (`ShowCiscoButton`, `ShowBrocadeButton`) ? `TemplatesModule::Get-ShowCommands` ? clipboard export with success dialogs.
- Templates tab save/add ? writes JSON files, triggers `Update-TemplatesList`, cached templates refresh when timestamps change.
- Interfaces grid `Copy Selected` button ? `Get-SelectedInterfaceRows` ? clipboard export of detailed port data.
- Compare view combos ? handlers from `Get-CompareHandlers` ? `Show-CurrentComparison` / `Set-CompareFromRows` update diffs.
- Search tab text/filters ? `Update-SearchGrid` ? `Update-SearchResults` (respects regex toggle, status/auth filters, location filters).
- SPAN refresh button ? `Invoke-StateTraceParsing` + `Get-DeviceSummaries` / `Update-DeviceFilter` ? `Get-SpanInfo` for current host.
## Core Feature Safeguards
- Preserve the per-site Access database workflow (`Get-DbPathForHost`, `Invoke-DbQuery`, parser updates); many modules assume that structure when loading data.
- Do not remove or rename global caches (`DeviceInterfaceCache`, `DeviceMetadata`, `AllInterfaces`, `AlertsList`, `templatesView`, `interfacesView`, `spanView`, `searchInterfacesView`). Other modules read them directly.
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
## Usage Notes
- Update this directory whenever new modules, functions, or significant behaviours are added.
- Before modifying a function, review the dependent modules listed above to avoid breaking UI flows or parser pipelines.
- When refactoring, confirm that caches (`DeviceInterfaceCache`, `DeviceMetadata`, `AllInterfaces`) and event wiring still function end-to-end by running a parser cycle and exercising each tab.

