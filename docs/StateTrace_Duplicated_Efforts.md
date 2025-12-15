**Scope**
- Quick inventory of duplicated implementations across Modules/, with references noted as path:line.

**Template Loading**
- Modules/DeviceLogParserModule.psm1 now delegates vendor template JSON parsing to Modules/TemplatesModule.psm1 (Get-ConfigurationTemplateData) so parser workers reuse the shared cache instead of maintaining a bespoke copy.

**Device Vendor Lookup**
- Centralized Make->Vendor mapping via `Modules/TemplatesModule.psm1:302` (`Get-TemplateVendorKeyFromMake`); adopted by `Modules/TemplatesModule.psm1:257`, `Modules/InterfaceModule.psm1:303`, and `Modules/DeviceRepositoryModule.psm1:5302`.

**Debug Switch Guards**
- Modules/DatabaseModule.psm1, Modules/DeviceLogParserModule.psm1, Modules/ParserWorker.psm1, and Modules/CompareViewModule.psm1 now rely on TelemetryModule\Initialize-StateTraceDebug rather than bespoke $Global:StateTraceDebug scaffolding.

**Interface Config Block Parsing**
- Centralized interface stanza extraction via `Modules/DeviceParsingCommon.psm1` (`Get-InterfaceConfigBlocks`); adopted by `Modules/CiscoModule.psm1` and `Modules/AristaModule.psm1` so vendor parsers only handle per-stanza post-processing (description parsing, name normalization).

**Cisco Template Compliance Command Lists**
- `Modules/CiscoModule.psm1:290` hard-codes the dual-auth compliance command list that overlaps the flexible auth templates in `Templates/Cisco.json:10`; consider sourcing required commands from the template JSON (via TemplatesModule) to prevent drift.

**Span Debug Logging**
- Centralized via TelemetryModule\Write-SpanDebugLog; both DeviceRepositoryModule.psm1 and SpanViewModule.psm1 now delegate to the shared helper instead of re-creating Logs\\Debug\SpanDebug.log and temp files independently.

**Db Result Normalization**
- Consolidated into DatabaseModule\ConvertTo-DbRowList; DeviceDetailsModule.psm1, DeviceRepositoryModule.psm1, InterfaceModule.psm1, and TemplatesModule.psm1 now delegate to the shared helper for DataTable/enumerable normalization.

**ViewStateService Bootstrap**
- Centralized via ViewStateService\Import-ViewStateServiceModule (renamed from the unapproved Ensure-ViewStateServiceLoaded); DeviceInsightsModule and InterfaceModule now call the helper instead of duplicating the import/probe logic.

**InterfaceCommon Bootstrap**
- TelemetryModule now exposes Import-InterfaceCommon (replacing the unapproved-verb Ensure-InterfaceCommonLoaded; shim removed after migration) so UI/device modules can import InterfaceCommon via a shared helper instead of repeating local `Get-Module`/`Import-Module` blocks (CompareViewModule, DeviceRepositoryModule, FilterStateModule, InterfaceModule, ViewStateService).

**CSV Export Dialog**
- Consolidated the repeated SaveFileDialog + Export-Csv workflow into `Modules/ViewCompositionModule.psm1:74` (Export-StRowsToCsv); adopted by `Modules/AlertsViewModule.psm1:23` and `Modules/SearchInterfacesViewModule.psm1:71`.

**UI Debounce Timers**
- Consolidated DispatcherTimer debounce boilerplate into `Modules/ViewCompositionModule.psm1:56` (New-StDebounceTimer); adopted by `Modules/InterfaceModule.psm1:866` and `Modules/SearchInterfacesViewModule.psm1:45`.

**Percentile Helpers**
- Consolidated duplicated `Get-PercentileValue` implementations (VerificationModule + warm-run/ingestion telemetry tools) into `Modules/StatisticsModule.psm1:3`; `Tools/AnalyzerStats.psm1:9` now delegates to the shared helper.

**Warm-run Telemetry Helpers**
- Extracted warm-run summary + provider-reason reconciliation helpers from `Tools/Invoke-WarmRunTelemetry.ps1` into `Modules/WarmRun.Telemetry.psm1:34` (Convert-MetricsToSummary), `Modules/WarmRun.Telemetry.psm1:103` (Measure-ProviderMetricsFromSummaries), and `Modules/WarmRun.Telemetry.psm1:303` (Resolve-SiteCacheProviderReasons) so Tools/tests import the module instead of dot-sourcing the script.

**Location Filter Dropdowns**
- `Main/MainWindow.ps1:699` (Populate-SiteDropdownWithAvailableSites) and `Modules/FilterStateModule.psm1:114` (Initialize-DeviceFilters) both build site dropdown items from metadata/location entries (and may fall back to database paths); consider consolidating to a single source to avoid drift.

**Extracted Log Cleanup**
- Deduped extracted-slice cleanup by having `Modules/LogIngestionModule.psm1` call `Clear-ExtractedLogs` from `Split-RawLogs` instead of maintaining a second inline deletion block.

**Scheduler Telemetry Writer**
- `Modules/ParserRunspaceModule.psm1:26` now stores the default scheduler telemetry writer scriptblock once (`$script:DefaultSchedulerTelemetryWriter`) and reuses it in `Set-SchedulerTelemetryWriter`, removing the duplicated `TelemetryModule\Write-StTelemetryEvent` closure.

**Port Row Defaults**
- Centralized Hostname/IsSelected defaulting via `Modules/InterfaceCommon.psm1:48` (`Set-PortRowDefaults`); adopted by `Modules/DeviceInsightsModule.psm1:214`, `Modules/DeviceRepositoryModule.psm1:4106`, and `Modules/ParserPersistenceModule.psm1:3724`.

**Port Sort Key**
- Centralized the port sort key algorithm + cache in `Modules/PortNormalization.psm1:106`; `Modules/InterfaceModule.psm1:224` and `Modules/DeviceRepositoryModule.psm1:20` now delegate via prefixed imports so parser/repository code doesn’t need to load the UI module to compute stable `PortSort` values.

**InterfaceModule Wrappers**
- Removed unused wrapper exports (`Get-InterfaceHostnames`, `Get-ConfigurationTemplates`, `Compare-InterfaceConfigs`) from `Modules/InterfaceModule.psm1` to avoid command shadowing; use `Modules/DeviceCatalogModule.psm1` / `Modules/TemplatesModule.psm1` / `Modules/CompareViewModule.psm1` directly.

**COM Release Helper**
- Centralized COM cleanup via `Modules/TelemetryModule.psm1:196` (`Remove-ComObjectSafe`); adopted by `Modules/DeviceLogParserModule.psm1:346` and `Modules/ParserPersistenceModule.psm1:634`.

**Module Shim Contracts**
- `Modules/DeviceRepository.Access.psm1` previously listed stale, non-existent export names (connection cache helpers); it now owns the DB/path + Access query helpers (Get-DataDirectoryPath, Get-DbPathForSite/Host, Get-AllSiteDbPaths, Import-DatabaseModule, Invoke-ParallelDbQuery) and is covered by `Modules/Tests/ModuleDecomposition.Tests.ps1`.
- `Modules/DeviceRepositoryModule.psm1` now wraps the DB/path helpers to preserve the existing `$script:DataDirPath` override contract used by unit tests and ad-hoc runs, passing the resolved path into `DeviceRepository.Access` via the optional `-DataDirectoryPath` parameter.
- `Modules/ParserPersistence.Core.psm1` now re-exports the real core persistence commands from `ParserPersistenceModule` (Update-DeviceSummaryInDb, Update-InterfacesInDb, Update-SpanInfoInDb, etc.) and imports `ParserPersistenceModule` into module scope so exports work even when the monolith is already loaded by `Modules/ModulesManifest.psd1`.
- `Modules/ParserPersistence.Diff.psm1` now re-exports the keyed site existing-row cache helpers (Get/Set/Clear snapshot + Import-SiteExistingRowCacheSnapshotFromEnv, Set-ParserSkipSiteCacheUpdate) and imports `ParserPersistenceModule` into module scope so exports work under normal startup ordering.

**Concurrency Heuristics**
- Modules/ParserWorker.psm1:54 (Get-AutoScaleConcurrencyProfile) and Modules/ParserRunspaceModule.psm1:208 (Get-AdaptiveThreadBudget) both derive thread ceilings and job batching limits from device queues.
- ParserRunspaceModule now exposes Get-ParserAutoScaleProfile (used when -UseAutoScaleProfile is set or when no concurrency hints are provided) to reuse the ParserWorker auto-scale calculation; further unification of adaptive budgeting remains open.
- Adaptive thread budgeting in ParserRunspaceModule now applies the same MaxActiveSites/MaxWorkersPerSite bounds that ParserWorker uses when resolving thread ceilings, reducing duplicate concurrency heuristics and over-allocation for single-site workloads.
- DeviceRepositoryModule\Import-SharedSiteInterfaceCacheSnapshotFromEnv now delegates to DeviceRepository.Cache\Import-SharedSiteInterfaceCacheSnapshotFromEnv first, avoiding two divergent snapshot import paths and keeping the preferred SiteKey/HostMap format primary while retaining the legacy fallback.
- ParserWorker snapshot export now imports DeviceRepository.Cache when available and prefers its Export-SharedCacheSnapshot (shared format) before falling back to the local writer, reducing duplicate serialization paths for shared cache snapshots.
- ParserWorker snapshot export now also prefers DeviceRepository.Cache\Get-SharedSiteInterfaceCacheSnapshotEntries before falling back to DeviceRepositoryModule, keeping the snapshot export and entry enumeration aligned on the same shared-cache module.
- When falling back to the legacy snapshot writer, ParserWorker normalizes cache module snapshot entries into the Site/Entry shape to avoid format drift between the two export paths.
- ParserWorker now attempts the cache module export first (without pre-enumerating entries), only enumerating snapshot entries when it has to fall back, reducing redundant work and keeping shared cache serialization centralized.
- DeviceRepositoryModule\Get-SharedSiteInterfaceCacheSnapshotEntries now defers to DeviceRepository.Cache when present, minimizing divergent snapshot enumeration logic across modules.
- Invoke-WarmRunTelemetry snapshot export now prefers DeviceRepository.Cache\Export-SharedCacheSnapshot (using site filters from the captured entries) before falling back to its local writer, aligning cold/warm harness exports with the shared cache module format.
- Invoke-StateTracePipeline snapshot export now prefers DeviceRepository.Cache\Export-SharedCacheSnapshot (with site filters) before falling back to its local writer, reducing duplicate snapshot writers across pipeline/warm harnesses.
- Invoke-WarmRunTelemetry now prefers DeviceRepository.Cache\Get-SharedSiteInterfaceCacheSnapshotEntries when capturing snapshot entries, keeping warm harness enumeration aligned with the shared cache module and avoiding duplicate snapshot entry logic.
- ParserWorker cache-module export now passes a site filter derived from the captured snapshot entries, aligning with the pipeline/warm harness exports and avoiding redundant serialization work.
- DeviceRepository.Cache now exposes ConvertTo-SharedCacheEntryArray for callers, and Invoke-WarmRunTelemetry delegates to it when available, trimming duplicated array-flattening helpers across snapshot writers.
- Invoke-StateTracePipeline fallback snapshot export now uses DeviceRepository.Cache\ConvertTo-SharedCacheEntryArray when available, keeping flattening consistent with the cache module and eliminating an extra local helper.
- ParserWorker fallback snapshot export now leverages DeviceRepository.Cache\ConvertTo-SharedCacheEntryArray when present, aligning flattening/normalization with other snapshot writers.
- Invoke-WarmRunTelemetry's flattening helper is now just a wrapper over DeviceRepository.Cache\ConvertTo-SharedCacheEntryArray, eliminating its local duplicate implementation.
- ParserWorker fallback writer now calls DeviceRepository.Cache\Write-SharedCacheSnapshotFileFallback first, reducing redundant serialization logic across modules before using its own internal writer.
- ParserWorker now delegates fallback-writer resolution to `Write-SharedCacheSnapshotFileInternal` so `Invoke-StateTraceParsing` doesn't duplicate the `Get-Command` lookup logic for shared cache snapshot export.
- DeviceRepository.Cache fallback snapshot writer now invokes its own Export-SharedCacheSnapshot when present, keeping Clixml depth/shape consistent even in fallback paths, with a plain Export-Clixml final fallback.
