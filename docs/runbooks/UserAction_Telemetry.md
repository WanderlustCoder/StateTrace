# UserAction Telemetry (Plan H)

Use this runbook to summarize adoption signals emitted by the UI (`UserAction` events) and attach the output to Plan H task updates and telemetry bundles.

## Summarize latest telemetry
```pwsh
pwsh -NoLogo -File Tools\Analyze-UserActionTelemetry.ps1 `
  -Path (Get-ChildItem Logs\IngestionMetrics\*.json | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName `
  -OutputPath Logs\Reports\UserActionSummary-$(Get-Date -Format yyyyMMdd-HHmmss).json
```
- Console output shows totals by action and site; the JSON is bundle-friendly.
- Required actions: `ScanLogs`, `LoadFromDb`, `HelpQuickstart`, `InterfacesView`, `CompareView`, `SpanSnapshot` (assert they appear at least once per bundle).

## Attach to telemetry bundle
- Drop the summary JSON into `Logs/TelemetryBundles/<bundle>/Telemetry/` when publishing a bundle.
- Reference the summary path in Plan H / task board updates to satisfy the Plan H gate.

## Notes
- The script is a no-op for non-`UserAction` events; run after any UI evidence session.
- If no `UserAction` entries are present, re-run the UI checklists to generate signals.
