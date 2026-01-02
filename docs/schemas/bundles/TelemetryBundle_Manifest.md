# Telemetry Bundle Manifest

Telemetry bundles are used for governance and evidence:
- release readiness (Plan G)
- telemetry tracking and rollups (Plan E)
- harness stability and gating evidence (Plan I/K/J)
- incident response and postmortems (Plan R)

Each bundle must contain a `TelemetryBundle.json` that:
- lists included artifacts,
- includes hashes/sizes,
- captures plan/task references,
- and can be validated via `Tools/Test-TelemetryBundleReadiness.ps1`.

## LANDMARK: Bundle directory layout

Recommended:
```text
Logs/
  TelemetryBundles/
    <bundleName>/
      <Area>/
        TelemetryBundle.json
        README.md
        <artifact files>
```

`Area` is typically `Telemetry` or `Routing` (set via `Tools/Publish-TelemetryBundle.ps1 -AreaName ...`).

## LANDMARK: Manifest fields

- `BundleName` - name passed to `Publish-TelemetryBundle`
- `AreaName` - area folder (Telemetry, Routing, etc.)
- `CreatedAt` - ISO 8601 timestamp
- `Hostname` - host that created the bundle
- `OutputRoot` - bundle root path
- `BundlePath` - area path containing the artifacts
- `PlanReferences` - list of plan IDs (e.g., PlanE, PlanG)
- `TaskBoardIds` - list of Task Board IDs (e.g., ST-E-007)
- `Notes` - freeform notes
- `Artifacts` - array of artifact entries (Category, TargetFile, SourcePath, Hash, SizeBytes)

Example (trimmed):
```json
{
  "BundleName": "CI-2025-12-24_0520Z",
  "AreaName": "Telemetry",
  "CreatedAt": "2025-12-24T05:25:00Z",
  "Hostname": "DEV-SEAT-01",
  "PlanReferences": ["PlanK", "PlanE"],
  "TaskBoardIds": ["ST-K-006"],
  "Artifacts": [
    {
      "Category": "QueueDelaySummary",
      "TargetFile": "QueueDelaySummary-20251224-0520.json",
      "SourcePath": "C:\\StateTrace\\Logs\\IngestionMetrics\\QueueDelaySummary-20251224-0520.json",
      "Hash": "<sha256>",
      "SizeBytes": 12345
    }
  ]
}
```

## LANDMARK: Validation

The bundle publisher/readiness script should validate that:
- `TelemetryBundle.json` exists
- every artifact exists and hash matches
- required plan/task IDs are present
- required artifacts for the area are present (see `Tools/Test-TelemetryBundleReadiness.ps1`)
