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
  - Update (2025-09-24): Template retrieval and caching now live in `TemplatesModule` (`Get-ConfigurationTemplateData`, `Get-ConfigurationTemplates`); DeviceDetailsModule and InterfaceModule delegate; the temporary DeviceDataModule wrapper was removed after the cutover.
  - Keep `Get-PortSortKey` with `InterfaceModule` (data ordering concern).
- **CommonUtilities.psm1 (new)**
  - Host generic helpers (`Get-SqlLiteral`, `Test-StringListEqualCI` if not kept with filters) to avoid circular dependencies.

## Function Relocation Map
| Function / Group | Proposed Destination | Status | Notes |
| --- | --- | --- | --- |
| `Get-SiteFromHostname`, `Get-DbPathForHost`, `Get-AllSiteDbPaths` | `DeviceRepositoryModule` | Complete | Functions relocated; legacy DeviceDataModule wrappers have been removed following consumer updates. |
| `Update-SiteZoneCache`, `Get-InterfacesForSite`, `Clear-SiteInterfaceCache`, `Update-GlobalInterfaceList` | `DeviceRepositoryModule` | Complete | Cache lifecycle owned by repository; legacy wrappers removed with DeviceDataModule retirement. |
| `Invoke-ParallelDbQuery` | `DeviceRepositoryModule` | Complete | Function now lives in `DeviceRepositoryModule`; DeviceDataModule wrapper removed during retirement. |
| `Get-DeviceSummaries`, `$global:DeviceMetadata` setup | `DeviceCatalogModule` | Complete | Catalog module implemented; UI wiring now handled in MainWindow/FilterState with DeviceDataModule removed. |
| `Get-InterfaceHostnames` | `DeviceCatalogModule` | Complete | Hostname filtering now lives in DeviceCatalogModule; consumers updated to call the catalog directly. |
| `Get-SelectedLocation`, `Get-LastLocation`, `Set-DropdownItems`, `Update-DeviceFilter`, guard flags | `FilterStateModule` | Complete | Logic now lives in `FilterStateModule`; DeviceDataModule retired after migration. |
| `Test-StringListEqualCI` | `FilterStateModule` | Complete | Helper relocated with filter logic; DeviceDataModule wrapper removed. |
| `Get-DeviceDetails`, `Get-DeviceDetailsData`, `Import-DatabaseModule` guard | `DeviceDetailsModule` | Complete | Retrieval helpers now live in `DeviceDetailsModule`; `MainWindow::Show-DeviceDetails` applies UI updates using `Set-InterfaceViewData`. |
| `Get-InterfacesForHostsBatch`, `Get-InterfaceInfo`, `Get-InterfaceConfiguration` | `DeviceRepositoryModule` | Complete | Functions now live in repository; DeviceDataModule retirement removed the compatibility layer. |
| `Update-SearchResults`, `Update-SearchGrid` | `DeviceInsightsModule` (Search service) | Complete | Business logic now lives in DeviceInsightsModule; UI modules call the service directly post-DeviceDataModule retirement. |
| `Update-Summary` | `DeviceInsightsModule` (Summary service) | Complete | Summary computation delegated to DeviceInsightsModule; UI updates now call the service directly without wrappers. |
| `Update-Alerts` | `DeviceInsightsModule` (Alerts service) | Complete | Alerts list now generated in DeviceInsightsModule; UI binds to the returned objects without DeviceDataModule. |
| `Get-PortSortKey` | `InterfaceModule` | Complete | Function lives in `InterfaceModule` and callers import it directly; DeviceDataModule wrapper removed with module retirement. |
| `Get-ConfigurationTemplates` | `TemplatesModule` | Complete | Function and caching now live in TemplatesModule; InterfaceModule now delegates to the shared helper following DeviceDataModule removal. |
| `Get-SqlLiteral` | `DatabaseModule` | Complete | DatabaseModule exports the helper and callers import it directly; no DeviceDataModule wrapper remains. |
| DeviceDataModule export wrappers | Temporary compatibility layer | Complete | Module retired; downstream modules call new services directly. |

## Migration Plan
1. **Preparation**
   - Catalogue all callers for each function (use `rg` and module manifests) and document expectations in `docs/StateTrace_Functions_Features.md`.
   - Expand regression tests (or extend `InterfaceModule.Tests.ps1`) covering filter behaviour, summary metrics, and alert generation before moving code.
   - Document current global state initialisation order to replicate in new modules.

2. **Introduce new modules (skeletons only)**
   - Create `Modules/Services` directory (or similar) with empty module shells exported via `ModulesManifest.psd1`.
   - Implement dependency injection pattern (functions returning data objects) without moving logic yet; this allows incremental adoption.
   - Ensure each new module exports only the intended surface area to prevent tight coupling.

3. **Extract utilities and shared helpers**
   - Move `Get-PortSortKey` to `InterfaceModule` (complete); update DeviceDataModule call sites to rely on the new location and plan wrapper removal.
   - Move `Get-SqlLiteral` to `DatabaseModule` (complete); migrate remaining callers to import DatabaseModule directly.
   - (Complete) `Test-StringListEqualCI` moved to `FilterStateModule`; evaluate remaining cross-cutting helpers before additional migrations.
   - Confirm unit/integration tests cover new locations.

4. **Device repository & catalog extraction**
   - Move site/DB path helpers and interface cache functions into `DeviceRepositoryModule` with the same signatures (complete).
   - Migrate `Invoke-ParallelDbQuery` next so all DB access funnels through repository.
   - Update `DeviceDataModule` to call into repository (wrapper pattern) and ensure behaviour remains identical.
   - Gradually update consumers (`ParserWorker`, `InterfaceModule`, `CompareViewModule`, `MainWindow`) to call repository or catalog directly; completed and wrappers removed once all consumers switched.
   - Move `Get-DeviceSummaries` and host metadata caching into `DeviceCatalogModule`; adjust `Update-DeviceFilter`/views to use catalog service.

5. **Filter state module**
   - Relocate filter functions into `FilterStateModule`; expose a cohesive API (`Get-FilterSnapshot`, `Update-Filters`, `Register-FilterControls`).
   - Update `MainWindow` and view modules to consume the new module; ensure global flags remain accessible or encapsulated via exported state object.
   - After adoption, delete filter code from `DeviceDataModule`.

6. **Device details service**
   - Move `Get-DeviceDetails` and `Get-DeviceDetailsData` to `DeviceDetailsModule`; refactor to return DTOs rather than writing to UI, leaving UI updates to `MainWindow`/view modules. *Complete: `Get-DeviceDetails` now exports from `DeviceDetailsModule`; `MainWindow::Show-DeviceDetails` calls `Set-InterfaceViewData`.*
   - Update `Import-DeviceDetailsAsync` and related callers to use the new service and apply UI bindings locally.
   - Validate that cached repository calls provide required data without re-querying the database excessively.

7. **Analytics (search/summary/alerts) extraction**
   - Decide between dedicated services or enhancing existing view modules. Recommended: create `DeviceInsightsModule` exposing `Get-SearchResults`, `Get-SummaryMetrics`, `Get-AlertRows`.
   - Move logic from `DeviceDataModule`; adjust `SearchInterfacesViewModule`, `SummaryViewModule`, `AlertsViewModule` to call new service functions and handle UI updates (e.g., assign `ItemsSource`).
   - Ensure global caches remain in repository to avoid duplication.

8. **Templates integration**
   - Relocate `Get-ConfigurationTemplates` into `TemplatesModule`; consolidate template cache handling and ensure repository helpers are available as needed.
   - Update `InterfaceModule`, `DeviceDetailsModule`, and any template consumers to use the centralised helper.
   - Remove redundant template caches from multiple modules.

9. **Decommission DeviceDataModule**
   - After all consumers rely on new modules, shrink `DeviceDataModule` to a thin compatibility layer (temporarily re-exporting relocated functions) to support staged releases.
   - Remove wrappers and delete legacy exports once all call sites import new modules.
   - Update `ModulesManifest.psd1`, module load scripts, and tests to exclude DeviceDataModule.

10. **Cleanup & documentation**
   - Update `docs/StateTrace_Functions_Features.md` with new module ownership.
   - Add README/CONTRIBUTING notes covering new architecture.
   - Ensure tests and build scripts reference new modules.
   - Capture migration outcomes and lessons learned in `docs/` for future refactors.

## Workstreams & Ownership
| Workstream | Lead | Key Deliverables | Dependencies | Status |
| --- | --- | --- | --- | --- |
| Repository extraction | Data services | DeviceRepositoryModule with DB helpers, caches, parallel query wrapper | DatabaseModule, data directory config | Complete |
| Catalog service | Data services | DeviceCatalogModule loading/refreshing metadata, exposing summaries | Repository functions, metadata schema | Complete |
| Filter state service | UI platform | FilterStateModule API plus updated UI bindings | Catalog metadata, existing event wiring | Complete |
| Device details service | Device experience | DeviceDetailsModule DTOs, UI integration, async guard | Repository interface methods, template loading | Complete |
| Analytics/insights | UI analytics | DeviceInsightsModule (or per-view services) delivering search/summary/alerts data | Repository + catalog outputs | Complete |
| Templates consolidation | UI platform | TemplatesModule owning configuration template cache & tests | Repository helpers, template assets | Complete |
| Testing & automation | QA | Extended Pester coverage landed; smoke test script in place; regression checklist updates still pending | Module migrations in progress | In progress |
| DeviceDataModule retirement | Core maintainers | Compatibility wrappers removed, manifest updated, module deleted | All other workstreams complete | Complete |

## Timeline & Milestones
1. **Phase 0 - Foundations (Complete)**
   - New module shells created and repository cache/helpers migrated.
   - Wrapper exports in place to keep UI functioning.

2. **Phase 1 - Data services (Target: Week 1 after plan sign-off)**
   - `Invoke-ParallelDbQuery` migration, catalog metadata load implemented, basic tests passing.

3. **Phase 2 - UI state & details (Target: Week 2)**
   - Filter state API adopted by `MainWindow`.
   - Device details DTOs driving UI without direct DeviceDataModule calls.

4. **Phase 3 - Analytics & templates (Target: Week 3)**
   - Search/Summary/Alerts logic extracted.
   - Template consolidation complete with regression validation.

5. **Phase 4 - Decommissioning (Target: Week 4)**
   - Wrappers removed, module manifest updated, documentation refreshed.
   - Final regression pass and release communication.

## Implementation Considerations
- Preserve global state initialisation (e.g., caches) within the new modules; expose explicit init/reset functions for parser runs.
- Maintain ordering of side effects triggered during app load (e.g., `Get-DeviceSummaries` -> `Update-DeviceFilter` -> `Update-CompareView`).
- Each migration step should keep public signatures stable or provide wrappers until all call sites are updated.
- Avoid circular dependencies: new services should depend only on `DatabaseModule`, `TemplatesModule`, and `DeviceRepositoryModule` as needed.
- Update module manifests and autoload scripts whenever new exports are required to keep packaging consistent.
- Track performance metrics (cache hit rate, DB query counts) before and after migration to ensure no regressions.

## Testing & Validation Strategy
- Expand Pester tests to cover:
  - Device catalog queries for multiple sites.
  - Filter state transitions (site/zone/building/room) with mocked metadata.
  - Search, summary, and alerts outputs given sample `AllInterfaces` data.
  - Device detail retrieval for DB-present vs CSV fallback scenarios.
- Run `Tests/Invoke-MainWindowSmokeTest.ps1` to ensure `Main/MainWindow.ps1` loads all modules without missing exports; the script records evidence under `Logs/RefactorValidation/` (e.g., `MainWindowSmokeTest_YYYYMMDD_HHmmss.log`).
- Perform manual UI regression: run parser, exercise filters, compare view, search tab, alerts tab.
- Capture test evidence in `Logs/RefactorValidation/` per phase to support release go/no-go decisions.

## Risks & Mitigations
- **Risk:** Regression in UI bindings when functions relocate.  
  **Mitigation:** Maintain wrappers until each consumer updates; run smoke tests after every module switch.
- **Risk:** Circular dependencies between new services.  
  **Mitigation:** Keep services layered (repository -> catalog -> UI services) and enforce dependencies via reviews.
- **Risk:** Cache invalidation bugs after splitting responsibilities.  
  **Mitigation:** Document cache ownership, add Pester tests covering cache refresh scenarios, and expose explicit reset APIs.
- **Risk:** Performance degradation from additional module calls.  
  **Mitigation:** Benchmark key flows before/after moves and co-locate heavy operations with repository services.
- **Risk:** Template retrieval differences breaking device details view.  
  **Mitigation:** Migrate templates with dedicated tests and maintain fallback data until parity confirmed.

## Rollback & Contingency Plan
- Keep DeviceDataModule wrappers for each migrated function until parity is verified (historical; complete).
- If a module extraction causes regressions, revert only the affected module by re-enabling DeviceDataModule exports in `ModulesManifest.psd1`.
- Maintain tagged Git snapshots at the end of each phase for rapid restore.
- Use feature toggles (e.g., `$script:EnableNewDeviceDetails`) during cutover so UI can flip back to legacy paths without redeploy.
- Document rollback steps in `Logs/RefactorValidation/rollback.md` after each phase.

## Communication Plan
- Share weekly status in engineering sync with highlights per workstream (blocked/unblocked).
- Post migration notes and required downstream changes in the team chat channel after each phase completes.
- Update `docs/StateTrace_Functions_Features.md` and the project README to reflect new ownership before release.
- Coordinate with support/training to brief them on module changes ahead of production roll-out.
- Capture final summary and metrics in `AIworkLog.docx` for historical traceability.

## Open Questions
- Should view modules own their analytics logic instead of a shared `DeviceInsightsModule`? Decide before extraction to avoid churn.
- Do we want to introduce a light-weight dependency injection or service locator to pass repository instances into view modules, reducing reliance on globals?
- Can we deprecate the use of global variables (e.g., replace with module-scoped singletons) as part of the refactor, or should that be a follow-up phase?
- Is there appetite to rename functions to align with approved verbs once relocation is complete (e.g., `ConvertTo-SqlLiteral`)?
- Where should cross-cutting validation (e.g., host/site guards) live once responsibilities split across modules?

## Current Regression Snapshot
- DeviceRepositoryModule now encapsulates cache refresh, global list coordination, and interface detail helpers; consumers call it directly after DeviceDataModule retirement.
- Callers now reference the new modules directly; monitor for any legacy imports resurfacing.
- Templates now resolve via `TemplatesModule`; module import order and regression coverage validated as part of DeviceDataModule retirement.

## Outstanding Follow-up
- [x] Build out automated coverage called for in the Testing & Validation Strategy (repository/catalog/insights/device detail modules). Pester suites now live under `Modules/Tests/`.
- [x] MainWindow smoke test script added (`Tests/Invoke-MainWindowSmokeTest.ps1`); latest evidence captured in `Logs/RefactorValidation/MainWindowSmokeTest_20250925_053344.log`.
- [x] Release documentation updated (`docs/StateTrace_Functions_Features.md`); no root README present.

## Progress Checklist
- [x] Data access & site resolution helpers now live in `DeviceRepositoryModule.psm1` (`Get-SiteFromHostname`, `Get-DbPathForSite`/`Get-DbPathForHost`, `Get-AllSiteDbPaths`).
- [x] `Clear-SiteInterfaceCache` moved to `DeviceRepositoryModule.psm1`.
- [x] `Update-SiteZoneCache` moved to `DeviceRepositoryModule.psm1`.
- [x] `Get-InterfacesForHostsBatch`, `Get-InterfaceInfo`, and `Get-InterfaceConfiguration` now live in `DeviceRepositoryModule.psm1` (legacy compatibility layer removed).
- [x] `Invoke-ParallelDbQuery` moved to `DeviceRepositoryModule.psm1` and exported for shared use .
- [x] `Get-DeviceSummaries` and `$global:DeviceMetadata` lifecycle now bootstrapped via `DeviceCatalogModule.psm1` (UI wiring handled in FilterState/MainWindow).
- [x] `Get-InterfaceHostnames` served from `DeviceCatalogModule.psm1` .
- [x] Filter state API exposed from `FilterStateModule.psm1`; MainWindow now calls filter fault helpers.
- [x] Device details aggregation moved to `DeviceDetailsModule.psm1` with DTO outputs consumed by UI (including `Get-DeviceDetails` now exported for synchronous callers).
- [x] `Show-DeviceDetails` helper in `MainWindow` now consumes `DeviceDetailsModule::Get-DeviceDetails` and applies `Set-InterfaceViewData`.
- [x] Search/Summary/Alerts logic extracted into `DeviceInsightsModule.psm1` (DeviceDataModule retired; continue regression coverage).
- [x] `Get-ConfigurationTemplates` relocated to `TemplatesModule.psm1` and redundant caches removed.
- [x] DeviceDataModule wrappers removed and module retired from `ModulesManifest.psd1`.
