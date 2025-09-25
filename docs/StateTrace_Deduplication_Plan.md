# StateTrace Duplication & Simplification Plan

## Objectives
- Reduce maintenance cost by consolidating repeated parsing and UI plumbing logic.
- Simplify critical data-loading flows so future features can rely on clear extension points.
- Improve test coverage around refactored areas to guard against regression while deduplicating code.

## Key Pain Points
1. **Repeated interface and MAC parsing across vendor modules** (`Modules/AristaModule.psm1`, `Modules/CiscoModule.psm1`, `Modules/BrocadeModule.psm1`).
2. **Copy-pasted XAML view bootstrapping** in every `*ViewModule.psm1` (`Alerts`, `Summary`, `SearchInterfaces`, `Span`, `Templates`, `Compare`).
3. **Parallel filter logic** spread across `DeviceRepositoryModule`, `FilterStateModule`, and `DeviceInsightsModule`, each re-implementing site/zone/building filtering and global cache updates.
4. **Over-engineered parser pipeline** in `ParserWorker.psm1` (stream-splitting, runspace orchestration) that obscures error handling and is difficult to unit test.

## Recommended Workstreams

### 1. Shared Device Parsing Library
- Extract common table/regex helpers (interface status, MAC table, dot1x) into a new module (e.g. `Modules/DeviceParsingCommon.psm1`).
- Refactor vendor modules to supply vendor-specific patterns/data maps while delegating looping and object construction to the shared helpers.
- Cover helpers with focused unit tests (Fixtures in `Modules/Tests`) using captured CLI samples to prove parity with current output.

### 2. UI Composition & Filter Service
- Introduce a reusable `Load-View` helper that accepts a view name, host control, and global slot to eliminate repeated XAML loader boilerplate.
- Centralise dropdown/filter state management in a dedicated service (e.g. `Modules/ViewStateService.psm1`) that owns `global:AllInterfaces` hydration and exposes query functions consumed by UI modules.
- Update `FilterStateModule` and `DeviceInsightsModule` to call the shared service instead of duplicating site/zone/building filtering logic.
- Back new service with smoke tests that assert correct filtering for representative selections.

### 3. Parser & Repository Simplification
- Split `ParserWorker.psm1` into discrete responsibilities: log ingestion, per-device parsing, and persistence. Replace manual stream buffering with a simpler line-grouping pipeline.
- Wrap runspace creation in a small orchestrator object so the worker logic can be invoked synchronously during tests.
- Move cache mutations (`DeviceRepositoryModule` global dictionaries) behind intent-based functions that return immutable snapshots to callers.
- Add regression tests for parsing edge cases (unknown host, mixed log files) and repository behaviours (site cache invalidation, global list refresh).

## Suggested Sequence
1. **Sprint 1 – Device parsing**: build shared helpers, refactor one vendor end-to-end, validate against existing tests/fixtures, then migrate remaining vendors.
2. **Sprint 2 – UI/service consolidation**: land view loader helper, migrate each view module, then refactor filter logic onto the new service with accompanying tests.
3. **Sprint 3 – Parser/repository cleanup**: modularise `ParserWorker`, simplify cache handling, and update consumers to use immutable results.

## Definition of Done
- Vendor modules consume shared parsing helpers with no local copies of interface/MAC parsing loops.
- View modules instantiate XAML through the shared loader; filter behaviour is verified through the central service.
- Parser pipeline is decomposed into testable units with automated coverage for log splitting and runspace orchestration.
- Regression suite (existing Pester tests + new cases) passes and demonstrates parity with pre-refactor behaviour.
