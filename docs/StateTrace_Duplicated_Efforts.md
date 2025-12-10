**Scope**
- Quick inventory of duplicated implementations across Modules/, with references noted as path:line.

**Template Loading**
- Modules/DeviceLogParserModule.psm1 now delegates vendor template JSON parsing to Modules/TemplatesModule.psm1 (Get-ConfigurationTemplateData) so parser workers reuse the shared cache instead of maintaining a bespoke copy.

**Debug Switch Guards**
- Modules/DatabaseModule.psm1, Modules/DeviceLogParserModule.psm1, Modules/ParserWorker.psm1, and Modules/CompareViewModule.psm1 now rely on TelemetryModule\Initialize-StateTraceDebug rather than bespoke $Global:StateTraceDebug scaffolding.

**Span Debug Logging**
- Centralized via TelemetryModule\Write-SpanDebugLog; both DeviceRepositoryModule.psm1 and SpanViewModule.psm1 now delegate to the shared helper instead of re-creating Logs\\Debug\SpanDebug.log and temp files independently.

**Db Result Normalization**
- Consolidated into DatabaseModule\ConvertTo-DbRowList; DeviceDetailsModule.psm1, DeviceRepositoryModule.psm1, InterfaceModule.psm1, and TemplatesModule.psm1 now delegate to the shared helper for DataTable/enumerable normalization.

**ViewStateService Bootstrap**
- Centralized via ViewStateService\Import-ViewStateServiceModule (renamed from the unapproved Ensure-ViewStateServiceLoaded); DeviceInsightsModule and InterfaceModule now call the helper instead of duplicating the import/probe logic.

**InterfaceCommon Bootstrap**
- TelemetryModule now exposes Import-InterfaceCommon (replacing the unapproved-verb Ensure-InterfaceCommonLoaded) so UI/device modules can import InterfaceCommon via a shared helper instead of repeating local `Get-Module`/`Import-Module` blocks (CompareViewModule, DeviceRepositoryModule, FilterStateModule, InterfaceModule, ViewStateService).

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
- DeviceRepository.Cache fallback snapshot writer now invokes its own Export-SharedCacheSnapshot when present, keeping Clixml depth/shape consistent even in fallback paths, with a plain Export-Clixml final fallback.
