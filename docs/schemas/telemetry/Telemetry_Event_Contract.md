# Telemetry Event Contract

This document defines the canonical telemetry event contract for StateTrace.

Goals:
- stable event schema for parsers and rollups
- consistent metric naming and units
- deterministic fields so gating can be automated
- compatibility with Phase 1 dictionary coverage tracking (Plan E)

Related docs:
- `docs/telemetry/Phase1_metrics.md` (dictionary)
- `docs/telemetry/Automation_Gates.md` (thresholds)

## LANDMARK: Event envelope

Each telemetry event is a single JSON object matching:
- `docs/schemas/telemetry/telemetry_event.schema.json`

Required fields:
- `EventName` - telemetry event name (e.g., `ParseDuration`, `InterfaceSyncTiming`)
- `Timestamp` - ISO 8601 timestamp (`Get-Date -Format o`)

Payload fields are event-specific and appended to the envelope by `TelemetryModule\Write-StTelemetryEvent`.

Example:
```json
{
  "EventName": "ParseDuration",
  "Timestamp": "2025-12-24T05:20:18.0400000Z",
  "DurationMs": 2418.2,
  "HostCount": 37,
  "SiteCount": 2
}
```

## LANDMARK: Naming conventions

- Event names:
  - PascalCase (`QueueDelaySummary`, `WarmRunComparison`)
  - Avoid spaces and punctuation
- Payload fields:
  - PascalCase with unit suffixes (`DurationMs`, `Count`, `Percent`)
  - Keep names consistent with `docs/telemetry/Phase1_metrics.md`

## LANDMARK: Units

Units are encoded in field names:
- `Ms` - durations
- `Count` - event counts
- `Percent` - 0-100
- `Ratio` - 0-1
- `Bytes` - sizes

If legacy fields omit units, document the unit in `Phase1_metrics.md`.

## LANDMARK: Required dimensions

There is no global `tags` object yet. Dimension fields live directly on each event payload
(e.g., `Site`, `Hostname`, `Provider`, `RunDate`). Required dimensions are defined per event
in `docs/telemetry/Phase1_metrics.md` and enforced in verification/rollup tooling.

## LANDMARK: Output paths

Telemetry is newline-delimited JSON (one object per line). Default output:
- `Logs/IngestionMetrics/<date>.json`

When `STATETRACE_TELEMETRY_DIR` is set, the telemetry directory is overridden and the same
file naming convention is used within that directory (for run-scoped outputs).
