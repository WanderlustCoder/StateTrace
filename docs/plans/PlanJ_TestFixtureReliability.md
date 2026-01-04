# Plan J - Test & Fixture Reliability

<!-- LANDMARK: ST-E-001 telemetry gates link -->
Telemetry gates: [docs/telemetry/Automation_Gates.md](../telemetry/Automation_Gates.md).

## Objective
Eliminate hidden fixture dependencies (missing mock logs, polluted telemetry files) and ensure harness/tests run reproducibly under PowerShell 5.1 with only repository-tracked assets.

## Current status (2025-12)
- DeviceLogParser duplicate-ingestion test now uses an inline fixture (no gitignored log dependency).
- Warm-run/pipeline telemetries occasionally polluted by stray debug slices or missing queue summaries; diversity guard can halt runs when datasets are unbalanced.
- Synthetic corpus generation (`Tools\Expand-MockLogCorpus.ps1`) depends on local templates; gitignored logs can still be absent until regenerated.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-J-001 | Commit synthetic fixture seeds | QA | Done - 2026-01-04 | Created `Tests/Fixtures/CISmoke/` with balanced BOYO/WLLS fixtures (6 hosts, 47 telemetry events). Added `IngestionMetrics.json` (line-delimited events) and `WarmRunTelemetry.json` (sample comparison). Manifest at `Tests/Fixtures/manifests/CISmoke.json`. Updated `Tests/Fixtures/README.md` with dataset docs and validation criteria. |
| ST-J-002 | Guard against polluted telemetry inputs | QA/Automation | Done - 2026-01-04 | Added preflight check in `Invoke-StateTracePipeline.ps1` and `Invoke-WarmRunTelemetry.ps1` to fail fast on non-JSON lines. Updated `Test-TelemetryIntegrity.ps1` with cleanup hints. Use `-SkipTelemetryIntegrityPreflight` to bypass. |
| ST-J-003 | CI smoke for harness paths | Automation | Done - 2026-01-04 | Created `Modules/Tests/CISmokeHarness.Tests.ps1` with `-Tag CISmoke` Pester tests using `Tests/Fixtures/CISmoke/` fixtures. Validates: queue summary generation, diversity guard (max streak <= 8), diff hotspot CSV, history updaters, and full harness smoke integration. 12 tests pass. |
| ST-J-004 | Fixture README + regeneration guard | QA | Done - 2026-01-04 | Added `Data/README.md` documenting fixture structure, gitignore policy, and regeneration steps. Updated `Tools/Expand-MockLogCorpus.ps1` with early template warnings and detailed error messages suggesting alternatives. |

## Recently delivered
- ST-J-003: Created `Modules/Tests/CISmokeHarness.Tests.ps1` with `-Tag CISmoke` Pester tests; validates queue summary, diversity guard, diff hotspots, history updaters, and full harness smoke (12 tests).
- ST-J-004: Added `Data/README.md` with fixture structure, gitignore policy, and regeneration docs; `Expand-MockLogCorpus.ps1` now warns on missing templates.
- ST-J-002: Added preflight telemetry integrity check to pipeline/warm-run scripts with cleanup hints; fails fast on polluted JSON.
- Duplicate-ingestion test now uses inline log content (no gitignored dependency).
- Shared skip-site-cache guard module reduces persistent settings drift during runs.

## Automation hooks
- Fixture expansion: `Tools\Expand-MockLogCorpus.ps1 -Force` (ensure templates exist or add committed seeds).
- CI smoke harness: `Invoke-Pester Modules/Tests/CISmokeHarness.Tests.ps1 -Tag CISmoke` validates queue summary, diversity guard, diff hotspots, and history updaters using `Tests/Fixtures/CISmoke/` fixtures.

## Telemetry gates
- Synthetic runs must still produce queue summaries and diversity reports; empty or malformed telemetry fails the smoke.
- No gitignored fixture required for tests; all required seeds tracked or generated in-run.

## References
- `docs/plans/PlanB_Performance.md` (warm-run/telemetry context).
- `docs/plans/PlanI_HarnessStability.md` (guard health).

