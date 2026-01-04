# Plan S - Deprecation & Unused Code Cleanup

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Identify and remove unused code paths, scripts, feature flags, and legacy UI elements while proving no active harness, telemetry, or plans depend on them. Keep diffs small, gated by tests/smokes, and record removals for traceability.

## Current status (2025-12)
- Large modules (DeviceRepository, ParserPersistence, WarmRunTelemetry) likely contain orphaned helpers and legacy feature branches.
- Tools/ scripts and runbooks reference historical workflows; no automated detector flags unused exports or stale feature flags.
- UI surfaces (Templates/Compare legacy flows) may include controls no longer wired to data.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-S-001 | Unused export inventory | Architecture | Done - 2026-01-04 | Created `Tools\Report-UnusedExports.ps1` using PowerShell AST parsing to scan function definitions across Modules/Tools/Main and report zero-reference candidates. Supports `-Allowlist`, `-FailOnUnused`, and `-OutputPath` parameters. Wired into `Tools\Invoke-AllChecks.ps1` with `-SkipUnusedExportLint` flag; CI runs lint by default and reports to `Logs/Reports/UnusedExports.json`. |
| ST-S-002 | Feature flag audit | PMO | Backlog | Enumerate feature flags/config toggles; mark deprecated ones, remove dead branches, and document surviving flags in `docs/CODEX_RUNBOOK.md`. |
| ST-S-003 | Script/runbook pruning | Automation | Backlog | Identify unused scripts in `Tools/` and outdated runbooks; remove or archive to `docs/completed/` with pointers. |
| ST-S-004 | UI cleanup sweep | UI | Backlog | Remove unused XAML controls and code-behind handlers (esp. Compare/Templates legacy flows) after confirming no bindings/telemetry rely on them. |

## Recently delivered
- Plan created to track deprecation and cleanup work.
- Added `Tools\Report-UnusedExports.ps1` to generate unused export candidates with optional JSON output and allowlist support.
- Removed unused `Get-SharedCacheEntriesForExport` helper, normalized `Get-ShowConfig` naming, and fixed placeholder/NetOps lint scripts so scans run clean.

## Automation hooks
- Unused export scan: `pwsh -File Tools\Report-UnusedExports.ps1 [-OutputPath Logs/Reports/UnusedExports.json] [-FailOnUnused] [-Allowlist Name1,Name2]` to list zero-reference functions across `Modules/`, `Tools/`, and `Main/`.
- Feature flag map: script to scrape `StateTraceSettings.json`, modules, and runbooks for flag names; emit a CSV and fail if unknown flags appear.
- UI cleanup validation: `Tools\Invoke-SpanViewSmokeTest.ps1`, `Tools\Invoke-InterfacesViewSmokeTest.ps1`, and `Invoke-Pester Modules/Tests -Tag UI` after removals.

## Telemetry gates
- No failing references after removal (Pester + smokes pass).
- Settings/config parsing succeeds with deprecated flags removed; unknown flag detection enabled.
- Bundle/verification scripts continue to run without the pruned tools.

## References
- `docs/plans/PlanL_ModuleDecomposition.md` (related module restructuring).
- `docs/CODEX_RUNBOOK.md` (needs updates when flags/tools are removed).
- `docs/StateTrace_AI_Agent_Guide.md` (documentation primacy for removals).

