# Onboarding Screenshots (Plan H, ST-H-001)

Use this guide when capturing UI evidence for the onboarding/quickstart path.

## What to capture
- Toolbar showing the Help button, freshness label (with site + age/source), and quickstart-related controls.
- Interfaces tab with incremental loading progress visible (status text and progress bar).
- Help window opened from the toolbar (confirm it points to the quickstart anchor).

## How to capture
1. Ensure data is seeded or loaded from Access (`Tools/Invoke-StateTracePipeline.ps1 -SkipTests -VerboseParsing -ResetExtractedLogs` or use existing DB files).
2. Launch the UI: `pwsh -NoLogo -NoProfile -File .\Main\MainWindow.ps1`.
3. Select a site in the toolbar; verify the freshness label populates.
4. Click **Scan Logs** once; then click **Load from DB** for the same site to avoid re-parsing.
5. Navigate to Interfaces, wait for batches to appear, and grab the screenshot.
6. Click **Help**; grab the Help window showing the quickstart pointer.

## Storage
- Save screenshots under `docs/performance/screenshots/` with timestamps, e.g., `docs/performance/screenshots/onboarding-<yyyyMMdd-HHmmss>.png`.
- Reference the saved paths in Plan H timeline and the task board entry for ST-H-001.

## Notes
- If running headless, rely on `Tools/Invoke-InterfacesViewChecklist.ps1 -SummaryPath Logs/Reports/InterfacesViewQuickstart.json` for evidence; annotate plan/task updates with the summary path when screenshots aren’t feasible.
