# Plan L - Module Decomposition & Maintainability

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Reduce the size and coupling of core modules (DeviceRepository, ParserPersistence, WarmRun telemetry) and the WPF shell by carving them into testable components with stable interfaces, while keeping ingestion and UI performance within existing gates.

## Current status (2025-12)
- `Modules/DeviceRepositoryModule.psm1` (~273k) and `Modules/ParserPersistenceModule.psm1` (~220k) mix Access adapters, cache types, diffing, and persistence guards; changes are high risk despite Pester coverage.
- `Tools/Invoke-WarmRunTelemetry.ps1` and `Main/MainWindow.ps1` host service logic that could live in dedicated modules, making UI and harness debugging harder.
- No micro-bench coverage exists for cache hit/miss paths or diff hotspot routines; regressions are caught late in warm-run telemetry.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-L-001 | Define target boundaries & ADR | Architecture | Done - 2026-01-04 | ADR 0006 complete with module size analysis, import graph (23 edges), and public contract summary (40 modules, 416 functions, 234 exported). Created `Tools/Get-ModuleImportGraph.ps1` to generate import graphs and contract lists. Priority targets: DeviceRepositoryModule (311KB), ParserPersistenceModule (207KB). |
| ST-L-002 | Extract repository cache layer | Ingestion | Done - 2026-01-04 | Cache layer extraction complete: `DeviceRepository.Cache.psm1` (18 exports) and `DeviceRepository.Access.psm1` (7 exports). Pester tests in `Modules/Tests/ModuleDecomposition.Tests.ps1` cover: cache helper exports, snapshot exports with wrapped entries, case-insensitive site keys, holder/AppDomain promotion. All 10 `-Tag Decomposition` tests pass. |
| ST-L-003 | Extract parser persistence/diff layer | Ingestion | Done - 2026-01-04 | Added micro-bench Pester tests (`-Tag Decomposition,MicroBench`) that assert `ParseDuration`/`DatabaseWriteLatency` stay within Plan B p95 gates using CISmoke fixture datasets; also added shim module export tests for `ParserPersistence.Core` and `ParserPersistence.Diff`. Tests: `Invoke-Pester Modules/Tests/ParserPersistenceModule.Tests.ps1 -Tag Decomposition` (21 tests passed). |
| ST-L-004 | Move UI services out of MainWindow | UI | Backlog | Extract parser job orchestration, user-action telemetry publishing, and freshness caching into `MainWindow.Services.psm1` (or similar) so XAML code-behind shrinks and gains unit coverage. |
| ST-L-005 | Regression harness for decomposed modules | Automation | Done - 2026-01-04 | Added `-SkipDecomposition` parameter to `Tools/Invoke-CIHarness.ps1`; CI harness runs `-Tag Decomposition` tests as Phase 1.5 after Pester Smoke. Outputs to `Decomposition.log` in CI run directory. |

## Recently delivered
- ST-L-003: Added micro-bench Pester tests (`-Tag Decomposition,MicroBench`) validating `ParseDuration` and `DatabaseWriteLatency` against Plan B p95 gates using CISmoke fixtures; added shim export tests for `ParserPersistence.Core`/`ParserPersistence.Diff` (21 tests passed).
- Plan created to track module decomposition and associated test coverage.
- Added shim modules (`DeviceRepository.Cache`, `DeviceRepository.Access`, `ParserPersistence.Core`, `ParserPersistence.Diff`, `WarmRun.Telemetry`) with re-exports and a Pester tag (`Decomposition`) to keep imports verified.

## Automation hooks
- Cache tests: `Invoke-Pester Modules/Tests/DeviceRepositoryModule.Tests.ps1 -Tag Cache` (extend with new cases when cache layer is split).
- Persistence/diff tests: `Invoke-Pester Modules/Tests/ParserPersistenceModule.Tests.ps1 -Tag Diff` (add micro-bench assertions).
- Decomposition/micro-bench tests: `Invoke-Pester Modules/Tests/ParserPersistenceModule.Tests.ps1 -Tag Decomposition` (validates ParseDuration/DatabaseWriteLatency p95 gates and shim exports).
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

