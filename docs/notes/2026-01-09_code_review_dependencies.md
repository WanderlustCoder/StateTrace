# Code review dependencies (2026-01-09)

## Data/fixtures
- BOYO/WLLS corpus availability (for ingestion + warm regression).
- Shared cache snapshot availability for warm-run comparisons.
- Tests/Fixtures coverage for vendor parsers and routing.
- Telemetry bundle output folder (`Logs/TelemetryBundles/`) available for Plan G checks.

## Tools/harness prerequisites
- PowerShell 5.x available for runtime parity.
- Access/ACE provider available for DB interactions.
- Shared cache snapshot path if running warm regression.
- Environment variables when needed: `STATETRACE_TELEMETRY_DIR`, `STATETRACE_SHARED_CACHE_SNAPSHOT`, `STATETRACE_SHARED_CACHE_SNAPSHOT_DIR`.
- UI harnesses require STA PowerShell and access to WPF assemblies.

## External constraints
- Offline-first requirement; no network unless explicitly authorized.
- Access DB files must remain untracked.
- Switch automation scripts require attached serial hardware if executed.

## Blockers to capture
- Missing fixtures or access to corpuses.
- Telemetry files missing required events.
- Harnesses failing due to environment constraints.
- Access provider mismatch (ACE 12 vs 16) when opening `.accdb`.
