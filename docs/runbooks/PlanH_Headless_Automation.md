# Plan H Headless Automation

Use this when an interactive WPF session isn’t available. The helper emits telemetry, generates headless screenshots, publishes a readiness-enforced bundle, and writes a Plan H report.

## One command
```pwsh
pwsh -NoLogo -File Tools\Run-PlanHHeadless.ps1
```
- Outputs:
  - Bundle: `Logs/TelemetryBundles/UI-<date>-planh-sim/` (with `PlanHReadiness.json`)
  - Summaries: `Logs/Reports/UserActionSummary-<timestamp>.json`, `FreshnessTelemetrySummary-<timestamp>.json`
  - Screenshots: `docs/performance/screenshots/onboarding-<timestamp>-*.png`
  - Report: `docs/performance/PlanHReport-<timestamp>.md`

## Under the hood
- `Tools/Simulate-PlanHUIRun.ps1` emits UserAction + freshness telemetry for WLLS/BOYO, generates headless screenshots, publishes a readiness-enforced bundle (`Tools/Invoke-PlanHBundle.ps1`), and runs readiness/report helpers.

## After running
- Update Plan H timeline/task board with bundle path, readiness JSON, summaries, screenshots, and report paths.
- If/when UI access is available, replace headless screenshots with live WPF captures per `docs/runbooks/PlanH_UI_Capture_Local.md`.
