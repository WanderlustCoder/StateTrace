# 2025-11-26 – UI capture plan (Plan H ST-H-001)

Use these steps to collect live WPF evidence (freshness tooltip, help, Interfaces) while emitting cache-provider telemetry for the next bundle.

## Pre-reqs
- Data seeded (pipeline run or existing Access DB).
- Latest telemetry summaries: `Logs/IngestionMetrics/<date>.json` ready to receive events.

## Capture flow
1) Launch the UI: `pwsh -NoLogo -NoProfile -File .\Main\MainWindow.ps1`
2) Select site (e.g., WLLS).
3) Hover freshness label and take screenshot (tooltip should show provider/reason and metrics path).
4) Click **Scan Logs** once, then **Load from DB** (same site) to emit UserAction + cache provider telemetry.
5) Open Interfaces tab; wait for rows; screenshot showing incremental loading.
6) Open **Help**; screenshot verifying quickstart anchor opens.
7) Switch site (e.g., BOYO) and hover freshness tooltip; screenshot.

## Post-capture
- Run summaries:
  ```pwsh
  pwsh -NoLogo -File Tools\Analyze-UserActionTelemetry.ps1 -Path Logs\IngestionMetrics\<date>.json -OutputPath Logs\Reports\UserActionSummary-<date>.json
  pwsh -NoLogo -File Tools\Analyze-FreshnessTelemetry.ps1 -Path Logs\IngestionMetrics\<date>.json -OutputPath Logs\Reports\FreshnessTelemetrySummary-<date>.json
  ```
- Publish bundle with readiness: `Tools\Publish-TelemetryBundle.ps1 ... -VerifyPlanHReadiness -Force`
- Save screenshots under `docs/performance/screenshots/` with timestamps and list them in a `*-titles.txt`.
- Record paths in Plan H timeline, backlog/task board, and session log.
