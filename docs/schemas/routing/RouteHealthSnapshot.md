# RouteHealthSnapshot Schema (v1)

## Purpose
Defines a point-in-time health view of routing state per device/VRF, based on
associated RouteRecord entries and detection latency.

## Schema Version
- `SchemaVersion`: `1.0`

## Required Fields
- `SchemaVersion` (string) - schema version, currently `1.0`
- `SnapshotId` (string) - unique identifier for the snapshot
- `CapturedAt` (string) - ISO 8601 timestamp when the snapshot was created
- `Site` (string) - site key (uppercase)
- `Hostname` (string) - device hostname (uppercase)
- `Vrf` (string) - VRF name (`default` if none)
- `PrimaryRouteStatus` (string) - `Up`, `Down`, `Degraded`, or `Missing`
- `SecondaryRouteStatus` (string) - `Up`, `Down`, `Standby`, or `Missing`
- `HealthState` (string) - overall health (`Healthy`, `Warning`, `Critical`)
- `DetectionLatencyMs` (number) - time to detect the latest routing state
- `RouteRecordIds` (array) - list of RouteRecord IDs included in the snapshot

## Optional Fields
- `FailoverState` (string) - `None`, `FailoverInProgress`, `FailoverComplete`
- `HealthScore` (number) - 0.0-1.0 normalized score
- `EvidenceSources` (array) - list of telemetry sources
- `Notes` (string) - human-readable context

## Normalization Notes
- `Site` and `Hostname` should be uppercase to match UI filtering.
- Use `default` for `Vrf` when none is provided.
- `CapturedAt` must be ISO 8601 (`Get-Date -Format o`).

## Generation Rules v1
- Group RouteRecord entries by `Site` + `Hostname` + `Vrf`.
- `PrimaryRouteStatus`:
  - `Up` when any Primary record has `RouteState = Active`.
  - `Down` when Primary records exist but none are Active.
  - `Missing` when no Primary records exist.
  - `Degraded` when Primary is `Down` and Secondary is `Up`.
- `SecondaryRouteStatus`:
  - `Up` when any Secondary record has `RouteState = Active`.
  - `Standby` when Secondary records exist but none are Active and Primary is `Up`.
  - `Down` when Secondary records exist but none are Active and Primary is not `Up`.
  - `Missing` when no Secondary records exist.
- `HealthState`:
  - `Healthy` when `PrimaryRouteStatus = Up`.
  - `Warning` when `PrimaryRouteStatus != Up` and `SecondaryRouteStatus = Up`.
  - `Critical` otherwise.
- `HealthScore`:
  - `Healthy` = `1.0`, `Warning` = `0.7`, `Critical` = `0.0`.
- `DetectionLatencyMs` is computed from the earliest and latest `CapturedAt` values in the RouteRecord set (0 when only one record).
- `FailoverState` defaults to `None`; set to `FailoverComplete` when `PrimaryRouteStatus = Degraded`.

## Machine-Readable Schema
- `docs/schemas/routing/route_health_snapshot.schema.json`
