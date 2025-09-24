# StateTrace AI Agent Operations Guide

## Purpose
- Central reference so automated assistants understand StateTrace's architecture, guardrails, and validation expectations before making changes.
- Complements existing design notes: always cross-reference `docs/StateTrace_Functions_Features.md`, `docs/DeviceDataModule_RefactorPlan.md`, and `docs/DynamicThemeRefactorPlan.md` for authoritative behaviour details.

## Project Snapshot
- **Platform:** PowerShell 5.x WPF desktop client (`Main/MainWindow.ps1` + XAML views).
- **Module manifest:** `Modules/ModulesManifest.psd1` controls load order; module filenames are contracts, so avoid renames unless the manifest and import sites update together.
- **Data layer:** Per-site Access `.accdb` databases under `Data/`; the parser (`Modules/ParserWorker.psm1`) and vendor modules keep them current. CSV fallbacks live under `ParsedData/` when a database is missing.
- **Shared state:** UI flows depend on globals seeded by the repository/catalog modules, e.g. `$global:DeviceMetadata`, `$global:DeviceInterfaceCache`, `$global:AllInterfaces`, `$global:alertsView`, `$global:templatesView`. Breaking these names or their shape cascades into runtime failures.
- **Backups:** Restorable snapshots of the project live at `C:\Users\Werem\StateTraceBackups`. Use them for comparison, not as an editing workspace.

## Before You Change Anything
1. Read the task twice, then review the docs above to confirm desired behaviour. If the task intersects DeviceData or view logic, consult the refactor plan tables to see current vs target ownership.
2. Identify the modules and views involved. Use `rg` to trace function usage instead of guessing.
3. Check for planned migrations or wrappers (e.g., `DeviceDataModule` delegating to `DeviceRepositoryModule`) so you edit the correct source of truth.
4. If the change touches themes, load `Modules/ThemeModule.psm1` and `Themes/*.json` to respect the runtime theme system rather than hard-coding colours.

## Safe Implementation Checklist
- **Approved verbs:** When adding or renaming PowerShell functions, use approved verbs (see `Get-Verb`) so exports stay compliant, and never embed `StateTrace` in the verb portion.
- **Preserve exports:** Ensure any function you move or rename remains exported where consumers expect it. Update both the manifest and downstream imports together.
- **Maintain caches:** When altering repository/catalog logic, keep cache invalidation (`Clear-SiteInterfaceCache`, `Update-GlobalInterfaceList`) and globals in sync. Never purge globals without repopulation.
- **Respect parser IO:** Parser-worker functions assume Access schema names and environment flags (`$env:IncludeArchive`, `$env:IncludeHistorical`). Do not repurpose these without auditing `ParserWorker` and `MainWindow` handlers.
- **UI bindings:** XAML views bind to specific property names and DataContext members from their modules. Verify bindings remain valid after edits by searching for `x:Name` and matching handler functions.
- **Theme-aware UI:** Use `ThemeModule` tokens and `DynamicResource` bindings; avoid new literal colours unless you also extend the theme definition and defaults.
- **Vendor modules:** Keep normalised interface objects consistent (properties like `PortColor`, `AuthTemplate`, `ConfigStatus`). UI modules rely on these fields for styling and alerts.
- **Compatibility wrappers:** `DeviceDataModule` currently proxies to newer modules; remove wrappers only when all consumers are migrated.

## Validation Expectations
- Run automated tests whenever you touch parser, repository, or analytics logic: `Invoke-Pester Modules/Tests` from the repo root.
- After providing your change summary to the operator, launch `Main/MainWindow.ps1` once to confirm it starts without errors and report the outcome.
- For theme or UI adjustments, confirm that resource dictionaries still merge without throwing (search for `StateTraceThemeChanged` handlers) and that new tokens exist in the default theme JSON.
- After parser or repository changes, perform a dry-run by executing `Main/MainWindow.ps1` manually if possible, or inspect log output to ensure refresh routines succeed.
- Update or add docs/tests alongside code when behaviour changes; missing coverage is a regression risk.

## Documentation & Logging Duties
- Record noteworthy architectural changes in the relevant doc(s) under `docs/` and append migration notes to `AIworkLog.docx` if instructed by the task.
- When introducing new modules or tokens, extend `docs/StateTrace_Functions_Features.md` and the appropriate refactor plan checklists.
- When functions or features are created, removed, or moved, update `docs/StateTrace_Functions_Features.md` to stay in sync.
- Keep log verbosity toggled via `$Global:StateTraceDebug`; do not leave debug logging permanently enabled.

## When in Doubt
- Compare against the latest backup in `C:\Users\Werem\StateTraceBackups` to understand intended behaviour.
- Ask for clarification rather than guessing when requirements or ownership are ambiguous.
- Default to conservative edits that maintain backwards compatibility until refactor checklists mark a component as fully migrated.

Adhering to this guide ensures automated changes respect StateTrace's architecture, protect critical caches, and ship with the validation our operators expect.
