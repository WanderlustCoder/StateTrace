# ADR 0006 - Module Decomposition Boundaries

## Context
- `DeviceRepositoryModule.psm1` (~273k) mixes cache types, Access adapters, and snapshot helpers.
- `ParserPersistenceModule.psm1` (~220k) hosts bulk write, diff/comparison, and shared-cache interop.
- `Tools/Invoke-WarmRunTelemetry.ps1` and `Main/MainWindow.ps1` embed service logic that would benefit from stable module interfaces.
- Large monoliths slow review, increase regression risk, and block focused micro-bench tests.

## Decision
- Introduce dedicated modules to isolate responsibilities:
  - `Modules/DeviceRepository.Cache.psm1` (cache types, cache access, snapshot import/export).
  - `Modules/DeviceRepository.Access.psm1` (Access adapters, connection lifecycle, persistence helpers).
  - `Modules/ParserPersistence.Core.psm1` (batch writes, telemetry/metrics plumbing).
  - `Modules/ParserPersistence.Diff.psm1` (diff/comparison routines, keyed existing-row cache helpers).
  - `Modules/WarmRun.Telemetry.psm1` (warm-run summary aggregation, provider reason reconciliation).
- Main modules (`DeviceRepositoryModule`, `ParserPersistenceModule`) will re-export public functions from the new modules to preserve compatibility while callers are migrated.
- Add Pester tags for decomposed areas (`-Tag Cache`, `-Tag Diff`) to support micro-bench harness runs (Plan L).

## Consequences
- Enables smaller, targeted changes with clearer ownership and import graphs.
- Slight import overhead from additional modules; mitigated by re-export pattern and module-qualified calls.
- Requires phased migration: first extract code without behavior changes, keep existing tests green, then update callers to module-qualified exports.

## Next Steps
- Create the new module files with existing logic moved verbatim and re-exported from the main modules.
- Add Pester tag coverage and micro-bench cases for cache hit/miss and diff hotspots.
- Update runbooks (CODEX_RUNBOOK + Plan L) with new module paths and test tags.
- Gradually update callers to module-qualified exports, then prune legacy shims once CI/harness is clean.
