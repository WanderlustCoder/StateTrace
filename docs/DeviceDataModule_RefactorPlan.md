# DeviceDataModule Refactor Plan

## Background & Goal
- `DeviceDataModule.psm1` currently mixes data access, cache management, UI filter orchestration, analytics (search/summary/alerts), and template plumbing.
- The module is now a catch-all dependency; changes here are risky and hard to reason about.
- Goal: redistribute responsibilities into targeted modules/services so ownership aligns with UI views and data layers, while keeping behaviour unchanged for end users.

## Current Responsibility Buckets
- **Data access & site resolution**: `Get-SiteFromHostname`, `Get-DbPathForHost`, `Get-AllSiteDbPaths`, `Invoke-ParallelDbQuery`, SQL literal helpers.
- **Cache & repository logic**: `Update-SiteZoneCache`, `Get-InterfacesForSite`, `Clear-SiteInterfaceCache`, `$global:DeviceInterfaceCache`, `$global:AllInterfaces` population.
- **Device catalog & metadata**: `Get-DeviceSummaries`, `Get-InterfaceHostnames`, `$global:DeviceMetadata` lifecycle.
- **UI filter state**: `Get-SelectedLocation`, `Get-LastLocation`, `Set-DropdownItems`, `Update-DeviceFilter`, guard flags.
- **Device detail retrieval**: `Get-DeviceDetails`, `Get-DeviceDetailsData`, `Get-InterfaceInfo`, `Get-InterfaceConfiguration`, `Get-InterfacesForHostsBatch`.
- **Analytics and view data**: `Update-SearchResults`, `Update-SearchGrid`, `Update-Summary`, `Update-Alerts`.
- **Utilities**: `Test-StringListEqualCI`, `Get-SqlLiteral`, `Get-PortSortKey`, `Import-DatabaseModule` guard.

## Target Module Ownership
- **DeviceRepositoryModule (new)**
  - Manage per-site database resolution and lifetime (`Get-SiteFromHostname`, `Get-DbPathForHost`, `Get-AllSiteDbPaths`).
  - House interface/device repository logic (`Update-SiteZoneCache`, `Get-InterfacesForSite`, `Clear-SiteInterfaceCache`, `Invoke-ParallelDbQuery`, `Get-InterfaceInfo`, `Get-InterfaceConfiguration`, `Get-InterfacesForHostsBatch`).
  - Expose cache coordination (wrapping `$global:DeviceInterfaceCache`, `$global:AllInterfaces`) behind functions.
- **DeviceCatalogModule (new)**
  - Maintain `$global:DeviceMetadata` lifecycle (`Get-DeviceSummaries`, `Get-InterfaceHostnames`).
  - Provide catalog queries consumed by filters and views.
- **FilterStateModule (new)**
  - Own selection getters/setters, dropdown population, filter debounce flags (`Get-SelectedLocation`, `Get-LastLocation`, `Set-DropdownItems`, `Update-DeviceFilter`, `Test-StringListEqualCI`).
  - Surface events/callbacks consumed by `MainWindow` and view modules.
- **DeviceDetailsModule (new)**
  - Provide host detail aggregations (`Get-DeviceDetails`, `Get-DeviceDetailsData`) using repository/services.
  - Keep UI-updating responsibilities minimal; return data for the caller to render.
- **DeviceInsightsModule (new)** or split by view
  - `Update-SearchResults`, `Update-SearchGrid` -> Search service consumed by `SearchInterfacesViewModule`.
  - `Update-Summary` -> Summary service consumed by `SummaryViewModule`.
  - `Update-Alerts` -> Alerts service consumed by `AlertsViewModule`.
  - Alternative: push logic directly into the respective view modules if we prefer view-owned behaviour; see migration notes.
- **TemplatesModule / InterfaceModule updates**
  - Move `Get-ConfigurationTemplates` alongside template caching (likely into `TemplatesModule` with shared cache).
  - Keep `Get-PortSortKey` with `InterfaceModule` (data ordering concern).
- **CommonUtilities.psm1 (new)**
  - Host generic helpers (`Get-SqlLiteral`, `Test-StringListEqualCI` if not kept with filters) to avoid circular dependencies.

## Function Relocation Map
| Function / Group | Proposed Destination | Notes |
| --- | --- | --- |
| `Get-SiteFromHostname`, `Get-DbPathForHost`, `Get-AllSiteDbPaths` | `DeviceRepositoryModule` | Shared across parser, repository, filters. Centralise to avoid duplicates. |
| `Update-SiteZoneCache`, `Get-InterfacesForSite`, `Clear-SiteInterfaceCache`, `Update-GlobalInterfaceList` | `DeviceRepositoryModule` | Keep cache and global list management together; expose explicit API for consumers. **Status: COMPLETE -- DeviceRepositoryModule now hosts Update-SiteZoneCache, Get-InterfacesForSite, Clear-SiteInterfaceCache, and Update-GlobalInterfaceList (DeviceDataModule now delegates via wrappers).** |
| `Invoke-ParallelDbQuery` | `DeviceRepositoryModule` | Low-level DB helper; ensure DatabaseModule dependency remains one-directional. |
| `Get-DeviceSummaries`, `$global:DeviceMetadata` setup | `DeviceCatalogModule` | Catalog module can coordinate repository + parser interactions and surface metadata queries. |
| `Get-InterfaceHostnames` | `DeviceCatalogModule` | Align host list retrieval with metadata owner. |
| `Get-SelectedLocation`, `Get-LastLocation`, `Set-DropdownItems`, `Update-DeviceFilter`, guard flags | `FilterStateModule` | Encapsulate selection state, emit events/callbacks for UI without global coupling. |
| `Test-StringListEqualCI` | `FilterStateModule` or `CommonUtilities` | Utility primarily used by filters; keep near usage. |
| `Get-DeviceDetails`, `Get-DeviceDetailsData`, `Import-DatabaseModule` guard | `DeviceDetailsModule` | Return pure data; UI modules call into this service to populate controls. |
| `Get-InterfacesForHostsBatch`, `Get-InterfaceInfo`, `Get-InterfaceConfiguration` | `DeviceRepositoryModule` or `DeviceDetailsModule` | Provide batched data access from repository; details module orchestrates results. **Status: COMPLETE -- Get-InterfacesForHostsBatch, Get-InterfaceInfo, and Get-InterfaceConfiguration now live in DeviceRepositoryModule (DeviceDataModule exposes thin wrappers).** |
| `Update-SearchResults`, `Update-SearchGrid` | `DeviceInsightsModule` (Search service) | `SearchInterfacesViewModule` consumes service functions. |
| `Update-Summary` | `DeviceInsightsModule` (Summary service) | Summary view invokes service to compute metrics. |
| `Update-Alerts` | `DeviceInsightsModule` (Alerts service) | Alerts view owners call service; service returns alert collection. |
| `Get-PortSortKey` | `InterfaceModule` | Used broadly for interface ordering; move to interface-focused module to avoid DeviceData dependency. |
| `Get-ConfigurationTemplates` | `TemplatesModule` | Merge with existing template cache to centralise template lookups. |
| `Get-SqlLiteral` | `CommonUtilities` or `DatabaseModule` | General SQL helper; DatabaseModule already handles DB operations. |

## Migration Plan
1. **Preparation**
   - Catalogue all callers for each function (use `rg` + tests) and document expectations in `docs/StateTrace_Functions_Features.md`.
   - Add regression tests (or extend `InterfaceModule.Tests.ps1`) covering filter behaviour, summary metrics, and alert generation before moving code.

2. **Introduce new modules (skeletons only)**
   - Create `Modules/Services` directory (or similar) with empty module shells exported via `ModulesManifest.psd1`.
   - Implement dependency injection pattern (functions returning data objects) without moving logic yet; this allows incremental adoption.

3. **Extract utilities and shared helpers**
   - Move `Get-PortSortKey` to `InterfaceModule`; update call sites to use the new location.
   - Move `Get-SqlLiteral` to `DatabaseModule` (as `ConvertTo-SqlLiteral` or similar) and update repository functions.
   - Confirm unit/integration tests cover new locations.

4. **Device repository & catalog extraction**
   - Move site/DB path helpers and interface cache functions into `DeviceRepositoryModule` with the same signatures.
   - Update `DeviceDataModule` to call into repository (wrapper pattern) and ensure behaviour remains identical.
   - Gradually update consumers (`ParserWorker`, `InterfaceModule`, `CompareViewModule`, `MainWindow`) to call repository directly; remove wrappers once all consumers switch.
   - Move `Get-DeviceSummaries` and host metadata caching into `DeviceCatalogModule`; adjust `Update-DeviceFilter`/views to use catalog service.

5. **Filter state module**
   - Relocate filter functions into `FilterStateModule`; expose a cohesive API (`Get-FilterSnapshot`, `Update-Filters`, `Register-FilterControls`).
   - Update `MainWindow` and view modules to consume the new module; ensure global flags remain accessible or encapsulated.
   - After adoption, delete filter code from `DeviceDataModule`.

6. **Device details service**
   - Move `Get-DeviceDetails` and `Get-DeviceDetailsData` to `DeviceDetailsModule`; refactor to return DTOs rather than writing to UI, leaving UI updates to `MainWindow`/view modules.
   - Update `Import-DeviceDetailsAsync` and `Get-HostnameChanged` to use the new service and apply UI bindings locally.

7. **Analytics (search/summary/alerts) extraction**
   - Decide between dedicated services or enhancing existing view modules. Recommended: create `DeviceInsightsModule` exposing `Get-SearchResults`, `Get-SummaryMetrics`, `Get-AlertRows`.
   - Move logic from `DeviceDataModule`; adjust `SearchInterfacesViewModule`, `SummaryViewModule`, `AlertsViewModule` to call new service functions and handle UI updates (e.g., assign ItemsSource).
   - Ensure global caches remain in repository to avoid duplication.

8. **Templates integration**
   - Relocate `Get-ConfigurationTemplates` into `TemplatesModule`; update consumers (`InterfaceModule`, `DeviceDetailsModule`).
   - Remove redundant template caches from multiple modules; centralise in `TemplatesModule`.

9. **Decommission DeviceDataModule**
   - After all consumers rely on new modules, shrink `DeviceDataModule` to a thin compatibility layer (temporarily re-exporting relocated functions) to support staged releases.
   - Once downstream code no longer imports from `DeviceDataModule`, remove the module and update `ModulesManifest.psd1` accordingly.

10. **Cleanup & documentation**
   - Update `docs/StateTrace_Functions_Features.md` with new module ownership.
   - Add README/CONTRIBUTING notes covering new architecture.
   - Ensure tests and build scripts reference new modules.

## Implementation Considerations
- Preserve global state initialisation (e.g., caches) within the new modules; expose explicit init/reset functions for parser runs.
- Maintain ordering of side effects triggered during app load (e.g., `Get-DeviceSummaries` -> `Update-DeviceFilter` -> `Update-CompareView`).
- Each migration step should keep public signatures stable or provide wrappers until all call sites are updated.
- Avoid circular dependencies: new services should depend only on `DatabaseModule`, `TemplatesModule`, and `DeviceRepositoryModule` as needed.
- Document any new global variables introduced by the refactor to keep future maintenance manageable.

## Testing & Validation Strategy
- Expand Pester tests to cover:
  - Device catalog queries for multiple sites.
  - Filter state transitions (site/zone/building/room) with mocked metadata.
  - Search, summary, and alerts outputs given sample `AllInterfaces` data.
  - Device detail retrieval for DB-present vs CSV fallback scenarios.
- Add smoke test script ensuring `Main/MainWindow.ps1` loads all modules without missing exports.
- Perform manual UI regression: run parser, exercise filters, compare view, search tab, alerts tab.

## Open Questions
- Should view modules own their analytics logic instead of a shared `DeviceInsightsModule`? Decide before extraction to avoid churn.
- Do we want to introduce a light-weight dependency injection or service locator to pass repository instances into view modules, reducing reliance on globals?
- Can we deprecate the use of global variables (e.g., replace with module-scoped singletons) as part of the refactor, or should that be a follow-up phase?
- Is there appetite to rename functions to align with approved verbs once relocation is complete (e.g., `ConvertTo-SqlLiteral`)?

## Current Regression Snapshot
- DeviceRepositoryModule now encapsulates cache refresh, global list coordination, and interface detail helpers; DeviceDataModule simply delegates.
- Track callers still importing these functions from DeviceDataModule so wrappers can be removed once downstream updates land.


## Progress
- [x] Data access & site resolution helpers now live in `DeviceRepositoryModule.psm1` (`Get-SiteFromHostname`, `Get-DbPathForSite`/`Get-DbPathForHost`, `Get-AllSiteDbPaths`; DeviceDataModule keeps wrappers only for legacy imports).
- [x] `Clear-SiteInterfaceCache` moved to `DeviceRepositoryModule.psm1`.
- [x] `Update-SiteZoneCache` moved to `DeviceRepositoryModule.psm1`.
- [x] `Get-InterfacesForHostsBatch`, `Get-InterfaceInfo`, and `Get-InterfaceConfiguration` now live in `DeviceRepositoryModule.psm1` (wrappers remain until downstream modules update their imports).
