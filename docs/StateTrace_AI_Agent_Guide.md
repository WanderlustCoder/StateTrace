# StateTrace AI Agent Operations Guide

This guide is the canonical reference for AI contributors and tooling that touch the StateTrace repo. Keep it open while you work; every other helper (for example `AGENTS.md`, `docs/Core_Ideas.md`, or the agent templates) now points back here.

## Project snapshot
- **Runtime:** PowerShell 5.x on Windows; WPF for the UI.
- **Entry points:** `Main/MainWindow.ps1` (UI) and `Modules/ParserWorker.psm1` (ingestion).
- **Data:** Per-site Microsoft Access `.accdb` files under `Data/<prefix>/<Site>.accdb`.
- **Key modules:** `ParserWorker.psm1`, `ParserRunspaceModule.psm1`, vendor parsers (`*Vendor*.psm1`), repository modules, view modules (`Views/*ViewModule.psm1`).
- **Planning resources:** `docs/plans/PlanIndex.md` for long-range work, `docs/StateTrace_TaskBoard.md` for sortable cards, `docs/CODEX_BACKLOG.md` for automation-ready queueing.

## Core ideas (authoritative wording)
1. **Documentation Primacy** – consult docs before every change, publish your plan, and record results. Docs outrank all other priorities.
2. **Approved PowerShell Verbs** – exported cmdlets must use the verbs reported by `Get-Verb`. Document remediation if you uncover legacy names.
3. **Offline-first & Access-backed** – ship PowerShell + Access only. No compiled binaries, no external stores, runnable offline.
4. **Telemetry & Verification** – capture telemetry such as `ParseDuration`, `DatabaseWriteLatency`, `ConcurrencyProfileResolved`, and gate changes on the recorded metrics.
5. **Plan-first Collaboration** – record a multi-step plan (use `update_plan`) before editing and keep it updated until you finish or block.
6. **Security & Data Hygiene** – sanitize logs, exclude `.accdb`, and respect `.gitignore` plus retention rules.
7. **Parser/UI Separation** – hydrate Access databases with parser utilities first, then let the UI read the stored state; document when a run requires fresh parsing versus cached data.

## Operating loop
1. **Plan** – Log a 3-6 bullet plan (see `docs/agents/Agent_Session_Template.md`) citing which core ideas you reinforce and add a card to the task board/backlog if one does not exist.
2. **Search** – Use safe local tools (e.g., `Select-String`) to confirm file targets and related modules.
3. **Edit** – Apply the smallest viable change, keeping diffs tight (<150 lines across ≤3 files when possible). Prefer new helpers instead of touching many modules.
4. **Validate** – Run `Invoke-Pester Modules/Tests`. For ingestion or parser changes, also run `Tools\Invoke-StateTracePipeline.ps1` (add `-RunWarmRunRegression` when cache behaviour matters) and capture telemetry to `Logs/IngestionMetrics/`.
5. **Document** – Update the relevant plan (`docs/plans/*`), add metrics or notes to `docs/StateTrace_TaskBoard.md` / `docs/taskboard/TaskBoard.csv`, and log the session under `docs/agents/sessions/`.
6. **Hand off** – Summarise results using the CLI prompt format, move the task board card to the right column, and open a follow-up card if work remains.

## Guardrails (must-follow)
- **No compiled components** and **no unsanctioned internet use.** Enable the optional online dev mode only when the operator authorises it (`STATETRACE_AGENT_ALLOW_NET/INSTALL=1`) and log every download via `Tools/NetworkGuard.psm1::Invoke-AllowedDownload`.
- **Stay in PowerShell + Access.** Use parameterised `ADODB.Command` for writes. Avoid new data stores or background services.
- **Security & privacy:** Never commit raw logs or `.accdb`. Use `Tools/Sanitize-PostmortemLogs.ps1` for redaction and keep fixtures under `Tests/Fixtures/`.
- **Filesystem hygiene:** Honour `.gitignore`, keep site databases out of source control, and scrub hostnames in shared fixtures.
- **Docs first:** Treat this guide as the source of truth. Mirror any policy updates to `AGENTS.md` and `docs/Core_Ideas.md`.
- **Shared cache seeding:** When you need a preserved host snapshot, point `STATETRACE_SHARED_CACHE_SNAPSHOT` at the desired `.clixml` so every parser runspace hydrates it before touching Access. `Tools\Invoke-StateTracePipeline.ps1` and `Tools\Invoke-WarmRunTelemetry.ps1` now manage this automatically when you pass `-SharedCacheSnapshotPath`, so only set/reset the env var manually when running ad-hoc scripts.

## Safe implementation checklist
- Confirm target files with `Select-String -Path . -Pattern <term> -Recurse`.
- Preserve exported function names unless you update every importer and the module manifest.
- Maintain global state contracts (e.g., `$global:AllInterfaces`, `$global:DeviceInterfaceCache`). If you change a shape, update all readers.
- Keep PowerShell strict mode on (`Set-StrictMode -Version Latest`); avoid implicit globals.
- For Access writes, batch commands, use parameters, and record `DatabaseWriteLatency` p95 in telemetry.
- When touching parser streaming or runspace scheduling, avoid fully buffering files and measure `ParseDuration` plus cache hit ratios.
- For UI work: ensure XAML bindings remain valid, test by launching `Main/MainWindow.ps1`, and confirm `ViewStateService` initialises.

## Validation matrix
| Change type | Commands | Required artifacts |
|-------------|----------|--------------------|
| Module/unit change | `Invoke-Pester Modules/Tests` | Capture pass/fail summary in session log. |
| Parser/ingestion | `Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing` plus `-RunWarmRunRegression` when caches are in play | `Logs/IngestionMetrics/<date>.json` snippet noting `ParseDuration`, `DatabaseWriteLatency`, cache providers. |
| Shared cache verification | `Tools\Analyze-SharedCacheStoreState.ps1 -Path Logs\IngestionMetrics\<file>.json [-IncludeSiteBreakdown]` and `Tools\Analyze-SiteCacheProviderReasons.ps1 -Path Logs\IngestionMetrics\<file>.json [-IncludeHostBreakdown]` (or run `Tools\Invoke-StateTracePipeline.ps1 ... -RunSharedCacheDiagnostics`) | Record SnapshotImported/GetHit vs. AccessRefresh counts in plan/task updates; attach host tables when warm runs still report `AccessRefresh`. |
| Scheduler/autoscale | `Import-Module .\Modules\ParserRunspaceModule.psm1; Get-AutoScaleConcurrencyProfile ...` | Attachment of resolved profile + overrides in docs. |
| UI/view updates | Launch `Main/MainWindow.ps1`; exercise affected view | Note manual verification plus screenshots if helpful (store in docs/notes/). |

## Common agent tasks

### Add a vendor parsing helper
1. Implement helper inside `Modules/DeviceParsingCommon.psm1` (or another shared module) and refactor one vendor module to use it.
2. Add/extend fixtures under `Tests/Fixtures/`.
3. Cover with Pester tests mirroring the module name.
4. Validate via `Invoke-Pester` and, if ingestion paths changed, run the pipeline; log metrics under Plan B (`docs/plans/PlanB_Performance.md`).

### Optimise ingestion performance
1. Identify the hot path (module warm-up, mutex contention, cache miss, etc.).
2. Gate changes behind a switch when feasible.
3. Emit telemetry (`ParseDuration`, `DatabaseWriteLatency`, `InterfaceSiteCacheMetrics`) and compare against the thresholds in `docs/telemetry/Automation_Gates.md`.
4. Update Plan B and the task board with before/after data.

### Maintenance operations
- Run `Tools/Maintain-AccessDatabases.ps1 -DataRoot Data -IndexAudit` during maintenance windows only.
- Store Access backups in `Data/Backups/` (never commit them).
- Use `Tools/Rollup-IngestionMetrics.ps1` to refresh metric summaries for plan reviews.

## Troubleshooting & stop conditions
- If a change requires schema migration or compiled code, stop and open/extend an ADR under `docs/adr/`.
- If tests fail and cannot be fixed within the session, stop with a **Blocked** summary including failing suites and stack traces.
- If telemetry cannot be captured (for example due to missing logs), stop and log the dependency so the next agent can resolve it.

## Deliverables
- Minimal patch tied to a specific plan/task, passing tests, updated docs, telemetry snapshot when applicable, and task board update.
- Session log committed under `docs/agents/sessions/` using `docs/agents/Agent_Session_Template.md`.

## References
- `AGENTS.md` – quick-start pointer to this guide and the PowerShell verb policy.
- `docs/Core_Ideas.md` – mirrors the core ideas for inline reference.
- `docs/StateTrace_TaskBoard.md` & `docs/taskboard/TaskBoard.csv` – active work queue.
- `docs/plans/PlanIndex.md` – objective summaries for Plans A–G.
- `docs/CODEX_RUNBOOK.md` – automation run/test matrix keyed to common changes.
