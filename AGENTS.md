# Repository Guidelines

## Project Structure & Module Organization
- `Modules/` hosts the PowerShell modules (e.g., `DeviceLogParserModule.psm1`, `ParserWorker.psm1`) and companion specs under `Modules/Tests/`.
- `Data/` stores per-site Access databases (`Data/<SitePrefix>/<Site>.accdb`) and configuration such as `StateTraceSettings.json`.
- `Logs/` captures ingestion telemetry, mock fixtures, and metrics exports (`Logs/IngestionMetrics/`).
- `docs/` carries operational plans and architecture notes; keep it aligned with implementation changes.

## Build, Test, and Development Commands
- `Invoke-Pester Modules/Tests` — run the full Pester suite (unit plus scheduler helpers).
- `Import-Module .\Modules\ParserWorker.psm1; Invoke-StateTraceParsing -Synchronous` — execute an end-to-end parsing pass against the local `Logs/` queue.
- `Import-Module .\Modules\ParserRunspaceModule.psm1; Get-AutoScaleConcurrencyProfile -DeviceFiles ...` — inspect autoscaling decisions without launching jobs.

## Coding Style & Naming Conventions
- All modules enforce `Set-StrictMode -Version Latest`; prefer explicit parameter binding and idempotent helpers.
- Use four-space indentation, PascalCase for exported functions/cmdlets, and camelCase for locals (`$siteDbDir`).
- Prefer `Join-Path`, `Test-Path -LiteralPath`, and module-qualified calls (`DeviceRepositoryModule\Get-DbPathForSite`) to avoid implicit state.
- Save files as ASCII/UTF-8 (no BOM) and avoid non-ASCII characters unless fixtures require them.

## Testing Guidelines
- Tests live in `Modules/Tests/*.Tests.ps1`, mirroring the module name (`ParserWorker.Tests.ps1`).
- New functionality should include unit coverage plus, when applicable, integration smoke checks via `Invoke-StateTraceParsing`.
- Tests should use `$TestDrive` for temp artifacts and clean up external resources.
- Run `Invoke-Pester Modules/Tests` prior to every commit or pull request update.

## Commit & Pull Request Guidelines
- Follow the imperative commit style seen in history (e.g., `Add parser autoscaling and metrics instrumentation`).
- Group related module, test, and doc updates; never commit generated logs or `.accdb` databases.
- Pull requests should include a concise summary, `Invoke-Pester` output (or equivalent), and links to issues/incidents when relevant.
- Call out configuration or schema migrations (such as the `Data/<prefix>/` layout) so operators can plan rollouts.

## Concurrency Overrides Workflow
- Default runs (`Tools/Invoke-StateTracePipeline.ps1`) honour `Data/StateTraceSettings.json` and auto-scale ceilings.
- For manual trials, add switches such as `-ThreadCeilingOverride`, `-MaxWorkersPerSiteOverride`, `-MaxActiveSitesOverride`, `-JobsPerThreadOverride`, or `-MinRunspacesOverride`; keep values > 0 only for the duration of the experiment.
- Always note override usage in your session log and capture metrics from `Logs/IngestionMetrics/<date>.json` (look for `ParseDuration`, `DatabaseWriteLatency`, `ConcurrencyProfileResolved`).
- Omit the override switches (or pass `0`) once testing finishes so the system reverts to autoscaling defaults.


## Security & Configuration Tips
- Keep site databases outside source control; ensure `.gitignore` continues to exclude `.accdb` files.
- Update `Data/StateTraceSettings.json` deliberately and document new toggles or defaults in `docs/`.
- Treat `Logs/` contents as sensitive: scrub hostnames when creating shared fixtures.


## Online Dev Mode (Optional)
When authorised, agents and developers may use limited internet access and dev-seat binaries to speed up work.

**Enable** by setting environment variables:
- `STATETRACE_AGENT_ALLOW_NET=1` to permit network operations.
- `STATETRACE_AGENT_ALLOW_INSTALL=1` to permit installing dev tools.

**Use the guardrails:**
- `Tools/NetworkGuard.psm1::Invoke-AllowedDownload` for all downloads (allowlist + hash).
- `Tools/Bootstrap-DevSeat.ps1` (winget pins) for installations.
- Record actions in `docs/agents/sessions/*` and `Logs/NetOps/<date>.json`.

**Still true:** Runtime releases remain scripts-only and offline-ready.

