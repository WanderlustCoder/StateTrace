# StateTrace AI Agent Operations Guide

This guide is the canonical reference for AI contributors and tools working in the StateTrace repository.

## Project snapshot
- **Runtime:** PowerShell 5.x on Windows; WPF for the UI.
- **Entry points:** `Main/MainWindow.ps1` (UI) and `Modules/ParserWorker.psm1` (ingestion).
- **Data:** Perâ€‘site Microsoft Access `.accdb` under `Data/<prefix>/<Site>.accdb`.
- **Key modules:** `ParserWorker.psm1`, `ParserRunspaceModule.psm1`, vendor parsers (`*Vendor*.psm1`), repository modules, view modules (`Views/*ViewModule.psm1`).

## Guardrails (mustâ€‘follow)
- **No compiled components** and **no internet access**.
- **No new data stores.** Stay with PowerShell + Access. Use parameterised `ADODB.Command` for writes.
- **Security & privacy:** Never commit raw logs or `.accdb`. Use `Tools/Sanitize-PostmortemLogs.ps1`. Keep fixtures under `Tests/Fixtures/`.
- **Docs first:** Update plans when you change behaviour. Every change must have a corresponding entry on the task board.

## Safe implementation checklist
- Confirm target files with local search (`Select-String -Path . -Pattern <term> -Recurse`).
- Keep diffs small (â‰¤ ~150 lines across â‰¤ 3 files).
- Preserve exported function names unless you also update the module manifest and imports.
- Maintain global state contracts used by UI modules (e.g., `global:AllInterfaces`). If you change shape, update all consumers.
- For Access writes, prefer batched transactions and parameterised commands; measure p95 latency with `DatabaseWriteLatency` metric.
- If touching parser streaming, avoid buffering entire files; process line groups.
- For UI updates: ensure XAML `x:Name` bindings and event handlers still resolve; test by launching the main window.

## Validation expectations
1. Run unit tests: `Invoke-Pester Modules/Tests` (must pass).
2. When changing ingestion or persistence, run: `Tools\Invoke-StateTracePipeline.ps1` and capture key metrics to `Logs/IngestionMetrics/`.
3. For UI changes, launch the app and verify views open without exceptions.
4. Attach the summary to your task board entry.

## Common agent tasks

### Add a new vendor parsing helper
1. Create helper in `Modules/DeviceParsingCommon.psm1` (or the appropriate shared module).
2. Refactor one vendor module to use it.
3. Add/extend Pester tests with small fixtures under `Tests/Fixtures/`.
4. Validate and document in `docs/StateTrace_Consolidated_Plans.md#plan-b-performance-ingestion-scale` under verification.

### Optimise ingestion performance
1. Identify the hot path (e.g., module warmâ€‘up, mutex contention).
2. Implement change behind a flag where possible.
3. Emit `ParseDuration`/`DatabaseWriteLatency` metrics.
4. Record before/after numbers and update `docs/StateTrace_Consolidated_Plans.md#plan-b-performance-ingestion-scale` DoD table.

### Maintenance operations
- Use `Tools/Maintain-AccessDatabases.ps1 -DataRoot Data -IndexAudit` to compact and audit indexes. Ensure no ingestion is running.
- Ensure backups are stored under `Data/Backups/` and not committed.

## Troubleshooting & stop conditions
- If a change requires a schema migration or compiled code â†’ stop and mark **Blocked**, propose an ADR.
- If tests fail and you cannot resolve within your session â†’ stop with a **Blocked** summary including failing test names and stack traces.

## Deliverables
- Minimal patch, passing tests, updated docs, task board entry, and (when applicable) metrics under `Logs/`.
