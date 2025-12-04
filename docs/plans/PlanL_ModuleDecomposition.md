# Plan L - Module Decomposition & Maintainability

## Objective
Reduce the size and coupling of core modules (DeviceRepository, ParserPersistence, WarmRun telemetry) and the WPF shell by carving them into testable components with stable interfaces, while keeping ingestion and UI performance within existing gates.

## Current status (2025-12)
- `Modules/DeviceRepositoryModule.psm1` (~273k) and `Modules/ParserPersistenceModule.psm1` (~220k) mix Access adapters, cache types, diffing, and persistence guards; changes are high risk despite Pester coverage.
- `Tools/Invoke-WarmRunTelemetry.ps1` and `Main/MainWindow.ps1` host service logic that could live in dedicated modules, making UI and harness debugging harder.
- No micro-bench coverage exists for cache hit/miss paths or diff hotspot routines; regressions are caught late in warm-run telemetry.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-L-001 | Define target boundaries & ADR | Architecture | Ready | Draft an ADR proposing module splits: `DeviceRepository.Cache`, `DeviceRepository.AccessAdapters`, `ParserPersistence.Core`, `ParserPersistence.Diff`, `WarmRun.Telemetry`, `UI.Services`. Include import graphs and public contract lists. |
| ST-L-002 | Extract repository cache layer | Ingestion | In Progress | Move cache types and cache-access helpers from `DeviceRepositoryModule` into `DeviceRepository.Cache.psm1`; add Pester tests for cache signature and hit/miss behaviour using synthetic fixtures. Update callers to module-qualify new exports. |
| ST-L-003 | Extract parser persistence/diff layer | Ingestion | Ready | Split `ParserPersistenceModule` into core batch writer and diff/comparison helpers. Add micro-bench Pester tests that assert `ParseDuration`/`DiffComparisonDurationMs` stay within existing p95 gates on fixture datasets. |
| ST-L-004 | Move UI services out of MainWindow | UI | Backlog | Extract parser job orchestration, user-action telemetry publishing, and freshness caching into `MainWindow.Services.psm1` (or similar) so XAML code-behind shrinks and gains unit coverage. |
| ST-L-005 | Regression harness for decomposed modules | Automation | Backlog | Add a Pester tag set (`-Tag Decomposition`) that exercises new modules plus warm-run telemetry end-to-end; wire into Plan K CI harness. |

## Recently delivered
- Plan created to track module decomposition and associated test coverage.

## Automation hooks
- Cache tests: `Invoke-Pester Modules/Tests/DeviceRepositoryModule.Tests.ps1 -Tag Cache` (extend with new cases when cache layer is split).
- Persistence/diff tests: `Invoke-Pester Modules/Tests/ParserPersistenceModule.Tests.ps1 -Tag Diff` (add micro-bench assertions).
- Warm-run regression: `Tools\Invoke-WarmRunTelemetry.ps1 -GenerateDiffHotspotReport -RestrictWarmComparisonToColdHosts` to detect perf regressions after refactors.
- UI service extraction validation: `Tools\Invoke-SpanViewSmokeTest.ps1` and `Tools\Invoke-InterfacesViewSmokeTest.ps1` after moving code-behind logic.

## Telemetry gates
- `ParseDuration` and `DatabaseWriteLatency` remain within Plan B thresholds after each module split.
- Warm run improvement stays non-negative with `WarmCacheHitRatioPercentRaw > 0`; no increase in `AccessRefresh` for fixture sites.
- UI smokes pass without null reference or binding errors; user-action telemetry still publishes and appears in rollups.

## References
- `docs/plans/PlanB_Performance.md` (perf gates and warm-run expectations).
- `docs/plans/PlanD_FeatureExpansion.md` (UI smoke contexts).
- `docs/plans/PlanK_DeveloperExperience.md` (CI harness consuming the new tests).
