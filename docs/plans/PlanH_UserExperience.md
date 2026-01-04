# Plan H - User Experience & Adoption

## Objective
Strengthen operator-facing value by reducing time-to-first-insight, clarifying data freshness, and embedding guidance where users actually work (UI, harness checklists, and runbooks). Plan H keeps the experience aligned with the offline/Access contract while adding adoption telemetry so we can prove usefulness.

## Current status (2025-11)
- Incremental loading and background parsing are live (Plan D) but operators still rely on external notes to learn the workflow; there is no in-app quickstart or consolidated first-run checklist.
- Status cues for data freshness and pipeline health are fragmented across logs and telemetry bundles; the UI does not surface per-site freshness, last ingest time, or cache source in a single place.
- Telemetry focuses on parser/cache performance. UI actions (Scan Logs vs. Load from DB, Compare/Span usage, onboarding steps completed) are not measured, so we cannot tell which features deliver value or where users stall.

## Active work
| ID | Title | Owner | Status | Notes |
|----|-------|-------|--------|-------|
<!-- LANDMARK: PlanH ST-H-001 onboarding closure evidence -->
| ST-H-001 | Ship operator onboarding + quickstart surfaces | UI / Docs | Done - 2026-01-01 | Quickstart anchor published in `docs/StateTrace_Operators_Runbook.md`, UI smoke checklist updated, headless harness emits a summary (`-SummaryPath`) with time-to-first-view, toolbar Help opens the quickstart anchor, and the toolbar shows a freshness label per site. Cache-source telemetry summary refreshed at `Logs/Reports/FreshnessTelemetrySummary-ST-H-001-20260101-153643.json`. Headless onboarding screenshots refreshed at `docs/performance/screenshots/onboarding-20260101-153643-*.png` (generated via `Tools/Capture-PlanHScreenshots.ps1`). Latest evidence bundle remains `Logs/TelemetryBundles/UI-20251126-useraction9/`. |
| ST-H-002 | Expose data freshness & pipeline health in the UI | UI / Telemetry | Backlog | Add a top-level status strip summarizing last ingest timestamp per site, source (SharedOnly/AccessRefresh/Cache), and freshness thresholds (<24h green, >24h warning). Include a link to the latest pipeline log and allow refresh from Access without starting a parse. Cover with a minimal Pester UI harness plus a runbook note describing the indicator semantics. |
| ST-H-003 | Instrument user-facing telemetry + feedback loop | Telemetry / UI | In Progress | `UserAction` events now emit for Scan Logs, Load from DB, HelpQuickstart, InterfacesView, CompareView, and SpanSnapshot; rollups and bundle tooling pick up UserAction summaries. Latest evidence: `Logs/Reports/UserActionSummary-20251126-run3.json` (all core actions) is bundled in `Logs/TelemetryBundles/UI-20251126-useraction7/` with coverage metadata. Next: codify adoption thresholds and capture live UI runs beyond the headless harness. |
| ST-H-004 | Fix search/alerts port sorting | UI | Done - 2025-12-19 | Search + Alerts views sort ports by PortSort keys for natural numeric order; targeted Pester coverage added. Follow-up: async refresh proceeds when interface data is already loaded even if `InterfacesLoadAllowed` is false, and the Insights worker merges queued view requests so search/alerts refresh is not dropped by later updates. |
| ST-H-005 | Headless Search/Alerts smoke harness | UI | Done - 2025-12-19 | Added `Tools/Invoke-SearchAlertsSmokeTest.ps1` to load Search/Alerts in a hidden WPF host and assert grid binding; UI smoke checklist + Codex runbook now call out the headless check and require it for new UI features/functions, and `Tools/Invoke-AllChecks.ps1` runs it by default. |
| ST-H-006 | Desktop UI harness run (Span/Search/Alerts) | UI | Done - 2025-12-24 | Desktop UI harness completed; summary `Logs/UIHarness/UIHarnessSummary-20251224-154607.json` with Span/Search/Alerts logs under `Logs/UIHarness/`. |
| ST-H-007 | Fix Span view null in desktop harness | UI | Done - 2025-12-24 | Span view binding now retains the global view after dispatcher pump; diagnostics added for init failures; verified via desktop harness summary `Logs/UIHarness/UIHarnessSummary-20251224-154607.json`. |

## Near-term checkpoints
- Publish the onboarding/quickstart path (ST-H-001) before adding new UI entry points so operators have a known-good flow.
- Sequence ST-H-002 after ST-H-001 so the freshness banner reuses the onboarding samples and checklist harness.
- Wire telemetry from ST-H-003 into the daily rollups and telemetry bundles so adoption metrics ship alongside performance evidence.

## Timeline
<!-- LANDMARK: PlanH ST-H-001 closure timeline entry -->
- **2026-01-01:** Refreshed cache-source telemetry summary (`Logs/Reports/FreshnessTelemetrySummary-ST-H-001-20260101-153643.json`) and headless onboarding screenshots (`docs/performance/screenshots/onboarding-20260101-153643-*.png`) using `Tools/Analyze-FreshnessTelemetry.ps1` and `Tools/Capture-PlanHScreenshots.ps1`.
- **2025-11-26:** Quickstart anchor added to `docs/StateTrace_Operators_Runbook.md`, UI smoke checklist updated to enforce the help link/quickstart path, and `Tools/Invoke-InterfacesViewChecklist.ps1` now supports `-SummaryPath` to capture time-to-first-view. Notes captured in `docs/notes/2025-11-26_onboarding_quickstart.md`. Next: hook toolbar Help to the quickstart anchor and add the freshness banner with telemetry.
- **2025-11-26 (later):** Toolbar Help now opens the Operators Runbook quickstart anchor before displaying the help window (`Main/MainWindow.ps1`), keeping the quickstart path discoverable inside the app. Next: add the freshness banner + screenshots/telemetry for ST-H-001 closure.
- **2025-11-26 (evening):** Added a toolbar freshness label that reads `Data/IngestionHistory/<site>.json` to display the last ingest timestamp/age for the selected site and updated the UI smoke checklist with the new expectation. The label also consults the latest telemetry to show the cache provider/source when available. Next: capture screenshots and wire telemetry for ST-H-001 completion.
- **2025-11-26 (night):** Interfaces headless checklist summary now emits `SiteFreshness` (last ingest/age/source per site) via `-SummaryPath`, aligning the automation with the new UI label.
- **2025-11-27:** Added `docs/runbooks/Onboarding_Screenshots.md` to standardize evidence capture (toolbar freshness label, incremental loading, Help window pointing to the quickstart anchor). Next: produce screenshots and adoption telemetry to close ST-H-001.
- **2025-11-27 (later):** Created `docs/performance/screenshots/README.md` to house onboarding/UX evidence with naming guidance. Awaiting captured images and telemetry to finish ST-H-001.
- **2025-11-27 (telemetry):** UI now emits `UserAction` telemetry for Scan Logs and Load from DB (site/host context), laying groundwork for ST-H-003 adoption tracking.
- **2025-11-27 (help telemetry):** Help button now publishes `UserAction` (`HelpQuickstart`) with site/host context before opening the quickstart anchor, improving onboarding adoption visibility.
- **2025-11-27 (compare telemetry):** Compare view now emits `UserAction` (`CompareView`) with site/host/port context when telemetry is available, furthering ST-H-003.
- **2025-11-27 (span telemetry):** Span snapshot now emits `UserAction` (`SpanSnapshot`) with host/site/row count when telemetry exists, rounding out adoption signals.
- **2025-11-27 (interfaces telemetry):** Interfaces view now emits `UserAction` (`InterfacesView`) with hostname/site, completing the UI action set for adoption tracking.
- **2025-11-27 (adoption analyzer):** Added `Tools/Analyze-UserActionTelemetry.ps1` to summarize UserAction counts by action/site for bundles/rollups.
- **2025-11-28:** New runbook `docs/runbooks/UserAction_Telemetry.md` documents how to generate and attach UserAction summaries to telemetry bundles (Plan H gate).
- **2025-11-28 (rollup integration):** `Tools/Rollup-IngestionMetrics.ps1` now rolls up `UserAction` counts (per action and total) so daily rollups/bundles carry adoption signals automatically.
- **2025-11-28 (bundle sample):** Generated `Logs/Reports/UserActionSummary-20251126.json` from the quickstart harness and published bundle `Logs/TelemetryBundles/UI-20251126-useraction5/` (cold telemetry + user action summary + headless checklist outputs) for Plan H adoption evidence.
- **2025-11-28 (UserAction coverage):** Scripted harness emitted every core `UserAction` (ScanLogs/LoadFromDb/HelpQuickstart/InterfacesView/CompareView/SpanSnapshot) with BOYO + WLLS context; latest summary `Logs/Reports/UserActionSummary-20251126-run3.json` (coverage includes MissingActions/AllActionsPresent) bundled at `Logs/TelemetryBundles/UI-20251126-useraction7/` after adding UserAction support to the bundle tool.
- **2025-11-28 (onboarding evidence):** Generated headless onboarding screenshots at `docs/performance/screenshots/onboarding-20251126-154036-*.png` (toolbar freshness/help cues + incremental Interfaces load) to keep ST-H-001 evidence flowing until a live UI capture is available.
- **2025-11-28 (rollup coverage):** `Tools/Rollup-IngestionMetrics.ps1` now emits `Metric=UserActionCoverage` (Count vs Total, Notes=Missing=...) per scope/site so daily summaries flag missing actions and enforce the adoption gate automatically.
- **2025-11-28 (freshness source detail):** Freshness label now pulls cache provider/reason + timestamp from the latest telemetry log (with newline-JSON fallback) and surfaces it in the tooltip, so operators can see whether data came from cache/shared/access and when the signal was recorded.
- **2025-11-28 (freshness telemetry runbook):** Added `Tools/Analyze-FreshnessTelemetry.ps1` + `docs/runbooks/Freshness_Telemetry.md` to summarize cache provider/status signals per site for bundles/checklists; latest summary `Logs/Reports/FreshnessTelemetrySummary-20251126-run2.json` (AccessRefresh/Cache coverage) bundled in `Logs/TelemetryBundles/UI-20251126-useraction8/`.
- **2025-11-28 (bundle auto-discovery):** Bundle publisher now auto-discovers `FreshnessTelemetrySummary*.json` so Plan H evidence (cache source/provider) ships with UserAction summaries without manual wiring.
- **2025-11-28 (readiness check):** `Tools/Publish-TelemetryBundle.ps1 -VerifyPlanHReadiness` now runs `Tools/Test-PlanHReadiness.ps1` and emits `PlanHReadiness.json` inside the bundle to prove UserAction + freshness evidence are present; `Logs/Reports/PlanHReadiness-20251126.json` captures the current bundle status.
- **2025-11-28 (bundle v9):** Published `Logs/TelemetryBundles/UI-20251126-useraction9/` (UserActionSummary-20251126-run3, FreshnessTelemetrySummary-20251126-run2, quickstart outputs) with readiness enforced (`PlanHReadiness.json` present).
- **2025-11-28 (bundle workflow runbook):** Added `docs/runbooks/PlanH_Bundle_Workflow.md` to codify the steps (UserAction/Freshness summaries, readiness-enforced publish, evidence recording).
- **2025-11-28 (headless screenshots v2):** Added `Tools/Capture-PlanHScreenshots.ps1` to render toolbar/help/Interfaces evidence from quickstart + freshness summaries; generated `docs/performance/screenshots/onboarding-20251126-191000-*.png` as interim proof until live WPF captures are available.
- **2025-11-28 (status/report helpers):** Added `Tools/Invoke-PlanHBundle.ps1` (one-shot readiness-enforced bundle) and `Tools/Invoke-PlanHChecks.ps1` (readiness + markdown report) to streamline evidence capture; reports now land in `docs/performance/PlanHReport-*.md`.
- **2025-11-28 (headless simulation bundle):** `Tools/Simulate-PlanHUIRun.ps1` now emits UserAction + freshness telemetry, generates headless screenshots, and publishes a readiness-enforced bundle (`Logs/TelemetryBundles/UI-20251126-planh-sim/`) with report `docs/performance/PlanHReport-20251126-215102.md` as interim evidence.
- **2025-11-28 (headless automation helper):** Added `Tools/Run-PlanHHeadless.ps1` and `docs/runbooks/PlanH_Headless_Automation.md` for one-shot headless runs (telemetry + screenshots + readiness bundle + report) when UI is unavailable.
- **2025-11-28 (UI auto-click helper):** Added `Tools/AutoCapture-PlanHUI.ps1` (UIAutomation clicks for Scan/Load/Interfaces/Help + screenshots) for interactive sessions that need scripted capture.

## Automation hooks
- `pwsh -NoLogo -File Tools\Invoke-InterfacesViewChecklist.ps1 -SiteFilter <site(s)>` to exercise Scan Logs vs. Load from DB without the WPF shell; extend this harness with onboarding steps as part of ST-H-001.
- `pwsh -NoLogo -File Tools\Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing` (or `Tools\Invoke-IncrementalLoadingChecklist.ps1`) to seed Access data before UI validation; reference the resulting `Logs/IngestionMetrics/<date>.json` in plan/task updates.
- `pwsh Tools\Analyze-PortBatchReadyTelemetry.ps1 -Path Logs\IngestionMetrics/<file>.json -IncludeHostBreakdown` to verify the sample onboarding corpus still emits the expected host counts/latency before UI smoke runs.
- `pwsh Tools\Publish-TelemetryBundle.ps1 -AreaName UI` to bundle onboarding/adoption telemetry with the latest analyzer outputs for evidence.

## Telemetry gates
- **Time-to-first-view:** <= 2 minutes from launching the app to seeing the first Interfaces rows (cold start, offline corpus). Record in onboarding checklist output.
- **Freshness indicator coverage:** 100% of supported sites show last ingest timestamp + source; warn when >24 hours old and log the warning in telemetry.
- **Adoption signals:** Each telemetry bundle must show all required UserAction events (ScanLogs, LoadFromDb, HelpQuickstart, InterfacesView, CompareView, SpanSnapshot) with `RequiredCoverage.AllActionsPresent=$true` in the summary; onboarding completion rate >= 80% for guided runs; Compare/Span invocation rate trending upward release-over-release. Track in `docs/telemetry/Automation_Gates.md` and rollup CSVs.

## References
- Operator docs: `docs/StateTrace_Operators_Runbook.md`, `docs/UI_Smoke_Checklist.md`, `docs/CODEX_RUNBOOK.md`.
- UI harnesses: `Tools/Invoke-InterfacesViewChecklist.ps1`, `Tools/Invoke-IncrementalLoadingChecklist.ps1`, `Tools/Invoke-AllChecks.ps1`.
- Telemetry: `docs/telemetry/Automation_Gates.md`, `Tools/Publish-TelemetryBundle.ps1`, `Tools/Analyze-PortBatchReadyTelemetry.ps1`.
- Historical context: Plan D (feature expansion) and Plan C (diff UX) for dependencies on Compare/Span instrumentation.
