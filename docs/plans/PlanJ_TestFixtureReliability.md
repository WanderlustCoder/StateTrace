# Plan J - Test & Fixture Reliability

## Objective
Eliminate hidden fixture dependencies (missing mock logs, polluted telemetry files) and ensure harness/tests run reproducibly under PowerShell 5.1 with only repository-tracked assets.

## Current status (2025-12)
- DeviceLogParser duplicate-ingestion test now uses an inline fixture (no gitignored log dependency).
- Warm-run/pipeline telemetries occasionally polluted by stray debug slices or missing queue summaries; diversity guard can halt runs when datasets are unbalanced.
- Synthetic corpus generation (`Tools\Expand-MockLogCorpus.ps1`) depends on local templates; gitignored logs can still be absent until regenerated.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
| ST-J-001 | Commit synthetic fixture seeds | QA | Ready | Add small, committed seed fixtures for parser/warm-run smokes (minimal host set, balanced sites) so CI can run without regenerating gitignored logs. Document generation steps in README. |
| ST-J-002 | Guard against polluted telemetry inputs | QA/Automation | In Progress | Add preflight check in warm-run/pipeline scripts to fail fast when `Logs/IngestionMetrics/<date>.json` contains non-JSON lines (e.g., debug slices). Surface path in error and suggest cleanup. |
| ST-J-003 | CI smoke for harness paths | Automation | Backlog | Add a Pester/CI smoke that runs a reduced pipeline + warm-run on synthetic fixtures under PowerShell 5.1, asserting: queue summary present, diversity guard passes, diff hotspot CSV emitted, history updaters succeed. |
| ST-J-004 | Fixture README + regeneration guard | QA | Backlog | Add a README under `Logs/` or `Data/` describing how to regenerate synthetic corpora and how gitignore interacts; script should warn when required template logs are missing and suggest `Tools\Expand-MockLogCorpus.ps1 -Force`. |

## Recently delivered
- Duplicate-ingestion test now uses inline log content (no gitignored dependency).
- Shared skip-site-cache guard module reduces persistent settings drift during runs.

## Automation hooks
- Fixture expansion: `Tools\Expand-MockLogCorpus.ps1 -Force` (ensure templates exist or add committed seeds).
- Harness smoke (proposed): pipeline cold pass + warm-run on minimal balanced fixtures, with queue summary and diversity guard enabled.

## Telemetry gates
- Synthetic runs must still produce queue summaries and diversity reports; empty or malformed telemetry fails the smoke.
- No gitignored fixture required for tests; all required seeds tracked or generated in-run.

## References
- `docs/plans/PlanB_Performance.md` (warm-run/telemetry context).
- `docs/plans/PlanI_HarnessStability.md` (guard health).
