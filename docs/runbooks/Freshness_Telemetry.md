# Freshness Telemetry (Plan H)

Use this runbook to summarize cache/source signals that feed the toolbar freshness label.

## Summarize latest telemetry
```pwsh
pwsh -NoLogo -File Tools\Analyze-FreshnessTelemetry.ps1 `
  -Path (Get-ChildItem Logs\IngestionMetrics\*.json | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName `
  -OutputPath Logs\Reports/FreshnessTelemetrySummary-$(Get-Date -Format yyyyMMdd-HHmmss).json
```
- Emits per-site counts of cache providers, reasons, and cache statuses across InterfaceSiteCache* events.
- Supports newline-delimited telemetry files (no pre-processing required).

## When to run
- After a UI session where the freshness label should show cache provider/source details.
- Before capturing screenshots for ST-H-001 to verify the tooltip can cite a provider.

## Bundle / task updates
- Include the summary JSON in telemetry bundles when demonstrating freshness coverage.
- Reference the summary path in Plan H/task board updates when cache-source evidence is required.
