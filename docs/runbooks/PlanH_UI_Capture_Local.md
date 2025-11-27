# Plan H UI Capture (Interactive) – ST-H-001

Use these steps on a machine with desktop access to capture real WPF evidence (freshness tooltip/help/Interfaces) and emit cache-provider telemetry for Plan H.

## Preconditions
- Seed data or use existing Access DB.
- Repo root as working directory.

## Steps
1) Launch UI:
   ```pwsh
   pwsh -NoLogo -NoProfile -File .\Main\MainWindow.ps1
   ```
2) Select site (e.g., WLLS).
3) Freshness tooltip:
   - Hover the freshness label; screenshot showing last ingest age + provider/reason + metrics path.
4) User actions:
   - Click **Scan Logs** once, then **Load from DB** for the same site.
5) Interfaces view:
   - Navigate to Interfaces; wait for rows; screenshot showing incremental loading.
6) Help:
   - Click **Help**; screenshot confirming the quickstart anchor opens.
7) Optional: switch to BOYO and repeat freshness tooltip + Interfaces screenshot.

### Automate (experimental)
If you prefer scripted clicks on a desktop session:
```pwsh
pwsh -NoLogo -File Tools\AutoCapture-PlanHUI.ps1 -ScreenshotDir docs\performance\screenshots -Timestamp <ts>
```
This uses UI Automation to click Scan Logs, Load from DB, select Interfaces, open Help, and capture window/help shots. Still requires an interactive desktop (not headless).

## After capture
1) Summaries:
   ```pwsh
   pwsh -NoLogo -File Tools\Analyze-UserActionTelemetry.ps1 -Path Logs\IngestionMetrics\<date>.json -OutputPath Logs\Reports\UserActionSummary-<date>.json
   pwsh -NoLogo -File Tools\Analyze-FreshnessTelemetry.ps1 -Path Logs\IngestionMetrics\<date>.json -OutputPath Logs\Reports\FreshnessTelemetrySummary-<date>.json
   ```
2) Bundle (enforces readiness):
   ```pwsh
   pwsh -NoLogo -File Tools\Invoke-PlanHBundle.ps1 -TelemetryPath Logs\IngestionMetrics\<date>.json -Force
   ```
3) Screenshots:
   - Save under `docs/performance/screenshots/onboarding-<timestamp>-*.png` and add a `*-titles.txt` listing them.
4) Reports/readiness:
   ```pwsh
   pwsh -NoLogo -File Tools\Invoke-PlanHChecks.ps1 -BundlePath Logs\TelemetryBundles\<bundle> -ReportPath docs\performance\PlanHReport-<date>.md
   ```
5) Update Plan H/task board/backlog/session log with bundle, readiness, summaries, and screenshot paths.
